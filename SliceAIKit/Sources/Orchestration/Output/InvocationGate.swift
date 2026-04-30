import Foundation

/// F9.2 single-flight invocation 隔离契约的状态持有者与 chunk gating 入口。
///
/// `InvocationGate` 是 single-flight 状态的唯一来源：调用方在 stream 开始前设置 active invocation，
/// 在取消 / dismiss / 完成时用 `ifCurrent` 清理，所有 chunk 通过 `gatedAppend` 决定是否投递。
///
/// 使用 `@MainActor` class 而不是 actor，是为了让 AppDelegate 与 ResultPanel adapter 在主线程同步共享
/// 同一个 gate 实例，避免跨 actor await 引入新的清理竞态。
@MainActor
public final class InvocationGate {

    /// 当前允许接收 chunk 的 invocation；nil 时拒绝所有 chunk。
    private var activeInvocationId: UUID?

    /// 构造空 gate；默认没有 active invocation。
    public init() {}

    /// 设置当前 active invocation。
    ///
    /// - Parameter id: 新 invocation 的唯一 ID；后续 chunk 只有携带该 ID 才会被接受。
    public func setActiveInvocation(_ id: UUID) {
        activeInvocationId = id
    }

    /// 只在调用方仍是当前 active invocation 时清理 gate。
    ///
    /// 该 guard 防止旧 invocation 的 defer / dismiss 晚到，把已经切换到的新 invocation 误清空。
    ///
    /// - Parameter id: 试图清理 gate 的 invocation ID。
    public func clearActiveInvocation(ifCurrent id: UUID) {
        guard activeInvocationId == id else { return }
        activeInvocationId = nil
    }

    /// 判断指定 invocation 的 chunk 是否应该被接受。
    ///
    /// 该方法主要用于测试和少量诊断；生产投递路径应优先调用 `gatedAppend`，避免外部漏掉 guard。
    ///
    /// - Parameter invocationId: chunk 所属 invocation ID。
    /// - Returns: 当 `invocationId` 等于当前 active invocation 时返回 true。
    public func shouldAccept(invocationId: UUID) -> Bool {
        activeInvocationId == invocationId
    }

    /// 带 gate 的 chunk 投递入口。
    ///
    /// 如果 `invocationId` 不是当前 active invocation，本方法静默丢弃 chunk，且不会调用 `sink`。
    /// 这样 adapter 只需要委托本方法，不再复制 single-flight 判断逻辑。
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段。
    ///   - invocationId: chunk 所属 invocation ID。
    ///   - sink: 实际投递闭包；仅 active invocation 匹配时调用。
    public func gatedAppend(
        chunk: String,
        invocationId: UUID,
        sink: @MainActor (String) -> Void
    ) {
        guard activeInvocationId == invocationId else {
            // 过期 invocation 的 chunk 静默丢弃；不要污染当前结果面板。
            return
        }
        sink(chunk)
    }
}
