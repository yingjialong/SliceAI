import Foundation
import SliceCore

/// `OutputDispatcherProtocol` 的默认 actor 实现。
///
/// **职责拆分（spec §3.3.6 + §3.4 Step 6）**：
/// - 仅按 `mode` 路由到对应 sink；不做任何 chunk 改写 / 脱敏（sink 自己负责）
/// - `OutputBinding.sideEffects` 与本类完全解耦——由 `ExecutionEngine` Step 7 直接读
///   `tool.outputBinding?.sideEffects` 触发，避免把 sideEffect 路由耦合进 `mode` 派发
///
/// **M2 范围**：
/// - `.window` → 调 `windowSink.append(chunk:invocationId:)` 后返回 `.delivered`
/// - 其他 5 种 `PresentationMode` → 返回 `.notImplemented(reason:)`，
///   `reason` 必须含模式名以便 audit / 调试
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

    /// 构造默认 OutputDispatcher。
    ///
    /// - Parameter windowSink: `.window` 模式 sink；其他模式 M2 阶段不需要 sink，
    ///   返回 `.notImplemented` 即可
    public init(windowSink: any WindowSinkProtocol) {
        self.windowSink = windowSink
    }

    /// 根据 `mode` 派发 chunk；`.window` 走 sink，其他模式 M2 阶段返回 `.notImplemented`。
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段
    ///   - mode: 来自 `V2Tool.displayMode`
    ///   - invocationId: 当前 invocation 的唯一标识
    /// - Returns: `.delivered` 当 sink 接收成功；`.notImplemented(reason:)` 当模式未实现
    /// - Throws: `.window` 模式下 sink 抛错时透传
    public func handle(
        chunk: String,
        mode: PresentationMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome {
        // 路由策略：单一 switch，6 个 case 显式覆盖（编译期 .allCases 守卫由 PresentationMode 自带）
        switch mode {
        case .window:
            // 唯一 sink-backed 分支：把 chunk 转发给注入的 windowSink
            try await windowSink.append(chunk: chunk, invocationId: invocationId)
            return .delivered
        case .bubble:
            // M2 stub：reason 含 "bubble" 关键字便于 audit 反查
            return .notImplemented(reason: "PresentationMode.bubble — M2 not implemented; awaits Phase 2 BubblePanel")
        case .replace:
            return .notImplemented(
                reason: "PresentationMode.replace — M2 not implemented; awaits Phase 2 InlineReplaceOverlay"
            )
        case .file:
            return .notImplemented(
                reason: "PresentationMode.file — M2 not implemented; awaits Phase 2+ FileOutputAdapter"
            )
        case .silent:
            return .notImplemented(
                reason: "PresentationMode.silent — M2 not implemented; awaits Phase 2 SilentSink"
            )
        case .structured:
            return .notImplemented(
                reason: "PresentationMode.structured — M2 not implemented; awaits Phase 2 StructuredResultView"
            )
        }
    }
}
