import Foundation
import SliceCore

/// Playground 输出快照，供 SettingsUI 在 ExecutionEvent 之外补充 final-only 预览。
public struct PlaygroundOutputSnapshot: Sendable, Equatable {
    /// invocation id。
    public let invocationId: UUID
    /// 输出模式。
    public var mode: DisplayMode
    /// 流式 chunk 列表。
    public var chunks: [String]
    /// 完整 final text。
    public var finalText: String?
    /// 失败时的用户可读错误。
    public var failureMessage: String?
}

/// Settings Playground 专用输出派发器。
///
/// 本派发器只记录 preview 状态，不打开 ResultPanel / BubblePanel，
/// 不写文件，不替换前台选区，也不写剪贴板。
public actor PlaygroundOutputDispatcher: OutputDispatcherProtocol {
    private var snapshots: [UUID: PlaygroundOutputSnapshot] = [:]

    /// 构造 Playground 输出派发器。
    public init() {}

    /// 标记一次 preview 输出开始。
    public func begin(context: OutputInvocationContext) async throws {
        snapshots[context.invocationId] = PlaygroundOutputSnapshot(
            invocationId: context.invocationId,
            mode: context.mode,
            chunks: [],
            finalText: nil,
            failureMessage: nil
        )
    }

    /// 记录 chunk；这是 `OutputDispatcherProtocol` 的 required 方法。
    public func handle(
        chunk: String,
        mode: DisplayMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome {
        ensureSnapshot(invocationId: invocationId, mode: mode)
        snapshots[invocationId]?.chunks.append(chunk)
        return .delivered
    }

    /// 记录带生命周期上下文的 chunk，并复用三参数 required 方法。
    public func handle(chunk: String, context: OutputInvocationContext) async throws -> DispatchOutcome {
        try await handle(chunk: chunk, mode: context.mode, invocationId: context.invocationId)
    }

    /// 记录 final text；final-only 模式也不执行真实输出。
    public func finish(finalText: String, context: OutputInvocationContext) async throws {
        ensureSnapshot(context: context)
        snapshots[context.invocationId]?.finalText = finalText
    }

    /// 记录失败状态。
    public func fail(error: SliceError, context: OutputInvocationContext) async {
        ensureSnapshot(context: context)
        snapshots[context.invocationId]?.failureMessage = error.userMessage
    }

    /// 读取一次 invocation 的 preview 快照。
    public func snapshot(for invocationId: UUID) -> PlaygroundOutputSnapshot? {
        snapshots[invocationId]
    }

    /// 确保字典中存在当前 invocation。
    private func ensureSnapshot(context: OutputInvocationContext) {
        ensureSnapshot(invocationId: context.invocationId, mode: context.mode)
    }

    /// 确保字典中存在当前 invocation。
    private func ensureSnapshot(invocationId: UUID, mode: DisplayMode) {
        if snapshots[invocationId] == nil {
            // 允许调用方跳过 begin，仍然能得到完整 preview 状态，方便错误收口。
            snapshots[invocationId] = PlaygroundOutputSnapshot(
                invocationId: invocationId,
                mode: mode,
                chunks: [],
                finalText: nil,
                failureMessage: nil
            )
        }
    }
}
