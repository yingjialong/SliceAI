import CoreGraphics
import Foundation
import SliceCore

/// `OutputDispatcher.handle(...)` 的派发结果。
///
/// 两态模型：
/// - `.delivered`：chunk 已成功投递到对应 sink
/// - `.notImplemented(reason:)`：保留给自定义 dispatcher 或后续真实 sink 缺失场景；
///   默认 OutputDispatcher 当前已覆盖 Phase 2 的 non-window modes。
public enum DispatchOutcome: Sendable, Equatable {
    /// chunk 已成功投递到对应 sink
    case delivered
    /// 该 `DisplayMode` 未实现；reason 应含模式名，便于调试 / audit
    case notImplemented(reason: String)
}

/// 一次输出派发的生命周期上下文。
///
/// 该上下文把原先散落在 `handle(chunk:mode:invocationId:)` 参数里的 mode / invocationId
/// 扩展为 sink 后续需要的稳定元数据。`Tool.displayMode` 仍是 mode 的单一事实源；
/// `screenAnchor` 来自 `ExecutionSeed`，供 bubble / replace / structured 等 UI sink 定位。
public struct OutputInvocationContext: Sendable, Equatable {
    /// 当前 invocation 的唯一标识。
    public let invocationId: UUID
    /// 当前执行的 Tool id。
    public let toolId: String
    /// 当前执行的 Tool 显示名。
    public let toolName: String
    /// 当前输出模式。
    public let mode: DisplayMode
    /// 触发时的屏幕锚点。
    public let screenAnchor: CGPoint
    /// 当前 Tool 的 outputBinding；`.file` 等 final-only sink 用它读取目标配置。
    public let outputBinding: OutputBinding?

    /// 构造输出生命周期上下文。
    public init(
        invocationId: UUID,
        toolId: String,
        toolName: String,
        mode: DisplayMode,
        screenAnchor: CGPoint,
        outputBinding: OutputBinding? = nil
    ) {
        self.invocationId = invocationId
        self.toolId = toolId
        self.toolName = toolName
        self.mode = mode
        self.screenAnchor = screenAnchor
        self.outputBinding = outputBinding
    }
}

/// 输出派发协议；ExecutionEngine Step 6 调用，负责按 `mode` 路由到对应 sink。
///
/// 调用契约：
/// - `mode` 来自 `Tool.displayMode`，是 mode 的 primary truth；
///   ExecutionEngine **严禁**传 `tool.outputBinding?.primary`，那个字段只是
///   Tool decoder 用来做一致性校验的冗余字段。
/// - `invocationId` 与当前 invocation 的 audit / cost / cancel 路由 ID 一致，
///   sink 用它把多次 chunk 合并到同一窗口或文件。
public protocol OutputDispatcherProtocol: Sendable {

    /// 标记一次输出开始。
    ///
    /// sink 可在这里准备窗口、buffer、文件句柄或 UI 状态。默认实现为空，方便旧测试
    /// dispatcher 渐进迁移。
    func begin(context: OutputInvocationContext) async throws

    /// 把单个 LLM stream chunk 派发到 `mode` 对应的 sink。
    ///
    /// - Parameters:
    ///   - chunk: 一次流式片段（不含分隔符；调用方负责合并）
    ///   - mode: `Tool.displayMode` 是 mode 的 primary truth；不读 `outputBinding.primary`
    ///     （`outputBinding.primary` 仅 Tool decoder 用作冗余一致性校验字段）
    ///   - invocationId: 当前 invocation 的唯一标识，用于 sink 路由 / 关联 cancel
    /// - Returns: `DispatchOutcome`；默认实现对 6 种 mode 都应返回 `.delivered`。
    ///   仅自定义 dispatcher 明确无法处理时才返回 `.notImplemented`。
    /// - Throws: 当 sink 自身抛错（如文件 IO 失败）时透传
    func handle(
        chunk: String,
        mode: DisplayMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome

    /// 把单个 LLM stream chunk 派发到 `context.mode` 对应的 sink。
    ///
    /// 新实现应优先覆盖本方法；旧实现可继续复用三参数 `handle(...)`，协议 extension 会
    /// 统一桥接。
    func handle(
        chunk: String,
        context: OutputInvocationContext
    ) async throws -> DispatchOutcome

    /// 标记一次输出成功结束，并提供完整最终文本。
    ///
    /// `.replace` / `.file` / `.structured` / `tts` 等 final-only 能力必须使用本方法中的
    /// `finalText`，避免在流式 chunk 阶段做破坏性输出。
    func finish(finalText: String, context: OutputInvocationContext) async throws

    /// 标记一次输出失败。
    ///
    /// sink 可以在这里关闭临时 UI 或展示受控错误状态；本方法不抛错，避免失败收口再次失败。
    func fail(error: SliceError, context: OutputInvocationContext) async
}

public extension OutputDispatcherProtocol {

    /// 默认 begin 为空，兼容当前只关心 chunk 的测试 dispatcher。
    func begin(context: OutputInvocationContext) async throws {}

    /// 默认把新 lifecycle chunk API 桥接回旧三参数 API。
    func handle(
        chunk: String,
        context: OutputInvocationContext
    ) async throws -> DispatchOutcome {
        try await handle(
            chunk: chunk,
            mode: context.mode,
            invocationId: context.invocationId
        )
    }

    /// 默认 finish 为空，后续 final-only sink 按需覆盖。
    func finish(finalText: String, context: OutputInvocationContext) async throws {}

    /// 默认 fail 为空，避免旧 dispatcher 必须实现失败收口。
    func fail(error: SliceError, context: OutputInvocationContext) async {}
}

/// `.window` 模式的投递目标。
///
/// 测试期 `OutputDispatcher` 注入 `InMemoryWindowSink`；生产路径在 M3 替换为
/// `ResultPanel` adapter（直接转发到既有 v0.1 ResultPanel）。
///
/// 实现要求：按 `invocationId` 隔离不同 invocation 的 chunk 流，避免跨窗口窜流。
public protocol WindowSinkProtocol: Sendable {

    /// 把 chunk 追加到指定 invocation 的窗口。
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段
    ///   - invocationId: 与 `OutputDispatcher.handle(...)` 透传的 invocation ID 一致
    /// - Throws: sink 实现层抛错时透传（如 ResultPanel 投递失败）
    func append(chunk: String, invocationId: UUID) async throws
}
