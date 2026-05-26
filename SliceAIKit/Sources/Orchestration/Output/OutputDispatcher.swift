import Foundation
import OSLog
import SliceCore

/// `OutputDispatcherProtocol` 的默认 actor 实现。
///
/// **职责拆分（spec §3.3.6 + §3.4 Step 6）**：
/// - 仅按 `mode` 路由到对应 sink；不做任何 chunk 改写 / 脱敏（sink 自己负责）
/// - side effect 实执行仍由 `ExecutionEngine` Step 7 触发；`.file` 只复用
///   `appendToFile` 配置作为 primary output destination，避免新增重复字段
///
/// **当前范围**：
/// - `.window` → 调 `windowSink.append(chunk:invocationId:)` 后返回 `.delivered`
/// - `.silent` → 消费 chunk，不展示
/// - `.file` → chunk 阶段不展示，finish 阶段追加完整 final text
/// - `.replace` → chunk 阶段不展示，finish 阶段替换前台 App 选区
/// - `.bubble` → chunk 阶段不展示，finish 阶段展示自动消失气泡
/// - `.structured` → chunk 阶段不展示，finish 阶段展示结构化结果
///
/// **M3 范围（后续接入）**：
/// - `.replace` → InlineReplaceOverlaySink（AX setSelectedText / paste fallback）
/// - `.file` → FileOutputAdapter（PathSandbox 校验后 append）
public actor OutputDispatcher: OutputDispatcherProtocol {

    /// `.window` 模式的投递目标；M2 测试用 `InMemoryWindowSink`，M3 替换为 `ResultPanel` adapter
    private let windowSink: any WindowSinkProtocol
    /// `.file` 模式的 final text 写入器。
    private let fileAppender: any FinalTextFileAppending
    /// `.replace` 模式的前台 App 文本替换 client。
    private let replacementClient: (any TextReplacementClient)?
    /// `.bubble` 模式的自动消失气泡 sink。
    private let bubbleSink: (any BubbleOutputSink)?
    /// `.structured` 模式的结构化结果 sink。
    private let structuredSink: (any StructuredOutputSink)?
    /// 输出派发诊断日志；只记录模式和 invocation，不记录 chunk 内容。
    private let logger = Logger(subsystem: "com.sliceai.app", category: "outputdispatcher")

    /// 构造默认 OutputDispatcher。
    ///
    /// - Parameters:
    ///   - windowSink: `.window` 模式 sink。
    ///   - fileAppender: `.file` 模式 final text 文件写入器。
    ///   - replacementClient: `.replace` 模式文本替换 client。
    ///   - bubbleSink: `.bubble` 模式展示 sink。
    ///   - structuredSink: `.structured` 模式展示 sink。
    public init(
        windowSink: any WindowSinkProtocol,
        fileAppender: any FinalTextFileAppending = SandboxedFinalTextFileAppender(),
        replacementClient: (any TextReplacementClient)? = nil,
        bubbleSink: (any BubbleOutputSink)? = nil,
        structuredSink: (any StructuredOutputSink)? = nil
    ) {
        self.windowSink = windowSink
        self.fileAppender = fileAppender
        self.replacementClient = replacementClient
        self.bubbleSink = bubbleSink
        self.structuredSink = structuredSink
    }

    /// 根据 `mode` 派发 chunk；兼容旧调用方并复用 lifecycle 路由规则。
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段
    ///   - mode: 来自 `Tool.displayMode`
    ///   - invocationId: 当前 invocation 的唯一标识
    /// - Returns: `.delivered` 当 sink 接收成功。
    /// - Throws: `.window` 模式下 sink 抛错时透传
    public func handle(
        chunk: String,
        mode: DisplayMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome {
        let context = OutputInvocationContext(
            invocationId: invocationId,
            toolId: "legacy-output-handle",
            toolName: "Legacy Output Handle",
            mode: mode,
            screenAnchor: .zero
        )
        return try await handle(chunk: chunk, context: context)
    }

    /// lifecycle chunk 派发；`.silent` / `.file` 不再写入 window sink。
    public func handle(
        chunk: String,
        context: OutputInvocationContext
    ) async throws -> DispatchOutcome {
        switch context.mode {
        case .window:
            try await windowSink.append(chunk: chunk, invocationId: context.invocationId)
        case .silent, .file, .replace, .bubble, .structured:
            return .delivered
        }
        return .delivered
    }

    /// lifecycle finish；final-only display modes 在此阶段消费完整 final text。
    public func finish(finalText: String, context: OutputInvocationContext) async throws {
        switch context.mode {
        case .file:
            try await finishFile(finalText: finalText, context: context)
        case .replace:
            try await finishReplace(finalText: finalText)
        case .bubble:
            try await finishBubble(finalText: finalText, context: context)
        case .structured:
            try await finishStructured(finalText: finalText, context: context)
        case .window, .silent:
            return
        }
    }

    /// `.file` finish：写入 appendToFile 目标。
    private func finishFile(finalText: String, context: OutputInvocationContext) async throws {
        guard let destination = context.outputBinding?.appendToFileDestination else {
            throw SliceError.configuration(.validationFailed(
                "DisplayMode.file requires outputBinding.sideEffects appendToFile destination"
            ))
        }
        try await fileAppender.append(
            finalText: finalText,
            to: destination.path,
            header: destination.header
        )
    }

    /// `.replace` finish：只在 final text 完整后替换前台选区。
    private func finishReplace(finalText: String) async throws {
        guard let replacementClient else {
            throw SliceError.configuration(.validationFailed(
                "DisplayMode.replace requires TextReplacementClient"
            ))
        }
        let result = await replacementClient.replaceSelection(with: finalText)
        switch result {
        case .replaced, .fallbackCopied:
            return
        case .failed:
            throw SliceError.execution(.unknown("replace display mode failed"))
        }
    }

    /// `.bubble` finish：只展示完整 final text。
    private func finishBubble(finalText: String, context: OutputInvocationContext) async throws {
        guard let bubbleSink else {
            logger.error("DisplayMode.bubble missing sink")
            throw SliceError.configuration(.validationFailed(
                "DisplayMode.bubble requires BubbleOutputSink"
            ))
        }
        try await bubbleSink.showBubble(finalText: finalText, context: context)
    }

    /// `.structured` finish：只展示完整 final text。
    private func finishStructured(finalText: String, context: OutputInvocationContext) async throws {
        guard let structuredSink else {
            logger.error("DisplayMode.structured missing sink")
            throw SliceError.configuration(.validationFailed(
                "DisplayMode.structured requires StructuredOutputSink"
            ))
        }
        try await structuredSink.showStructured(finalText: finalText, context: context)
    }
}

private extension OutputBinding {

    /// `.file` mode 使用的 appendToFile 目标。
    var appendToFileDestination: (path: String, header: String?)? {
        for sideEffect in sideEffects {
            if case .appendToFile(let path, let header) = sideEffect {
                return (path, header)
            }
        }
        return nil
    }
}
