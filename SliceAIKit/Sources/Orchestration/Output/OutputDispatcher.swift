import Foundation
import OSLog
import SliceCore

/// `OutputDispatcherProtocol` 的默认 actor 实现。
///
/// **职责拆分（spec §3.3.6 + §3.4 Step 6）**：
/// - 仅按 `mode` 路由到对应 sink；不做任何 chunk 改写 / 脱敏（sink 自己负责）
/// - `OutputBinding.sideEffects` 与本类完全解耦——由 `ExecutionEngine` Step 7 直接读
///   `tool.outputBinding?.sideEffects` 触发，避免把 sideEffect 路由耦合进 `mode` 派发
///
/// **M3.0 Step 1 范围**：
/// - `.window` → 调 `windowSink.append(chunk:invocationId:)` 后返回 `.delivered`
/// - 其他 5 种 `PresentationMode` → v0.2 暂时 fallback 到 `.window` sink，保留用户可见输出
/// - 每个 invocation 只在首次 fallback 时写一条日志，避免 stream chunk 高频刷屏
/// - 日志节流状态固定容量，避免长时间运行时无界增长
///
/// **M3 范围（后续接入）**：
/// - `.bubble` → BubblePanelSink
/// - `.replace` → InlineReplaceOverlaySink（AX setSelectedText / paste fallback）
/// - `.file` → FileOutputAdapter（PathSandbox 校验后 append）
/// - `.silent` → SilentSink（仅消费 chunk，不展示）
/// - `.structured` → StructuredResultViewSink（按 JSONSchema 渲染表单 / 表格）
public actor OutputDispatcher: OutputDispatcherProtocol {

    /// `.window` 模式的投递目标；M2 测试用 `InMemoryWindowSink`，M3 替换为 `ResultPanel` adapter
    private let windowSink: any WindowSinkProtocol
    /// fallback 日志节流状态容量；足够覆盖并发/近期 invocation，且避免长期无界增长。
    private static let maxLoggedFallbackInvocations = 128
    /// fallback 日志节流状态：同一个 invocation 只记录一次 non-window fallback。
    private var loggedInvocations: Set<UUID> = []
    /// fallback 日志节流 FIFO 队列；配合 `loggedInvocations` 做固定容量淘汰。
    private var loggedInvocationOrder: [UUID] = []
    /// 输出派发诊断日志；只记录模式和 invocation，不记录 chunk 内容。
    private let logger = Logger(subsystem: "com.sliceai.app", category: "outputdispatcher")

    /// 构造默认 OutputDispatcher。
    ///
    /// - Parameter windowSink: `.window` 模式 sink；v0.2 阶段其他模式会 fallback 到该 sink。
    public init(windowSink: any WindowSinkProtocol) {
        self.windowSink = windowSink
    }

    /// 根据 `mode` 派发 chunk；v0.2 期间 non-window mode fallback 到 window sink。
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段
    ///   - mode: 来自 `V2Tool.displayMode`
    ///   - invocationId: 当前 invocation 的唯一标识
    /// - Returns: `.delivered` 当 sink 接收成功。
    /// - Throws: `.window` 模式下 sink 抛错时透传
    public func handle(
        chunk: String,
        mode: PresentationMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome {
        // 路由策略：单一 switch，6 个 case 显式覆盖。
        switch mode {
        case .window:
            // 唯一 sink-backed 分支：把 chunk 转发给注入的 windowSink
            try await windowSink.append(chunk: chunk, invocationId: invocationId)
            return .delivered
        case .bubble, .replace, .file, .silent, .structured:
            logFallbackIfNeeded(mode: mode, invocationId: invocationId)
            try await windowSink.append(chunk: chunk, invocationId: invocationId)
            return .delivered
        }
    }

    /// 对 non-window fallback 做固定容量日志节流。
    /// - Parameters:
    ///   - mode: 当前 fallback 的展示模式。
    ///   - invocationId: 当前 invocation 标识。
    private func logFallbackIfNeeded(mode: PresentationMode, invocationId: UUID) {
        guard !loggedInvocations.contains(invocationId) else { return }
        if loggedInvocationOrder.count >= Self.maxLoggedFallbackInvocations,
           let evicted = loggedInvocationOrder.first {
            loggedInvocationOrder.removeFirst()
            loggedInvocations.remove(evicted)
        }
        loggedInvocations.insert(invocationId)
        loggedInvocationOrder.append(invocationId)
        logger.info(
            "OutputDispatcher fallback mode=\(String(describing: mode), privacy: .public) to .window sink"
        )
    }
}
