import Foundation
import SliceCore

/// `OutputDispatcher.handle(...)` 的派发结果。
///
/// 两态模型：
/// - `.delivered`：chunk 已成功投递到对应 sink
/// - `.notImplemented(reason:)`：保留给自定义 dispatcher 或后续真实 sink 缺失场景；
///   M3.0 默认 OutputDispatcher 对 non-window mode 已 fallback 到 `.window`
public enum DispatchOutcome: Sendable, Equatable {
    /// chunk 已成功投递到对应 sink
    case delivered
    /// 该 `PresentationMode` 未实现；reason 应含模式名，便于调试 / audit
    case notImplemented(reason: String)
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

    /// 把单个 LLM stream chunk 派发到 `mode` 对应的 sink。
    ///
    /// - Parameters:
    ///   - chunk: 一次流式片段（不含分隔符；调用方负责合并）
    ///   - mode: `Tool.displayMode` 是 mode 的 primary truth；不读 `outputBinding.primary`
    ///     （`outputBinding.primary` 仅 Tool decoder 用作冗余一致性校验字段）
    ///   - invocationId: 当前 invocation 的唯一标识，用于 sink 路由 / 关联 cancel
    /// - Returns: `DispatchOutcome`；默认实现对 6 种 mode 都应返回 `.delivered`。
    ///   仅自定义 dispatcher 明确无法 fallback 时才返回 `.notImplemented`。
    /// - Throws: 当 sink 自身抛错（如文件 IO 失败）时透传
    func handle(
        chunk: String,
        mode: PresentationMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome
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
