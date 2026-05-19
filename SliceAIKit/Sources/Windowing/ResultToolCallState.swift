import Foundation

/// ResultPanel 中展示的单个工具调用生命周期状态。
public struct ResultToolCallState: Sendable, Equatable, Identifiable {

    /// 工具调用当前阶段。
    public enum Status: Sendable, Equatable {
        /// LLM 已提出调用，但尚未通过权限检查。
        case proposed
        /// 调用已通过权限检查。
        case approved
        /// 调用已成功返回结果。
        case result
        /// 调用被 allowlist 或权限 gate 拒绝。
        case denied
        /// 调用参数、权限或 MCP 执行发生错误。
        case error
    }

    /// UI 稳定 id，来自 `ExecutionEvent` 的 tool-call UUID。
    public let id: UUID
    /// 面向用户的工具标题，例如 `fs.read`。
    public var title: String
    /// 参数摘要、结果摘要或错误原因。
    public var detail: String
    /// 当前生命周期状态。
    public var status: Status

    /// 构造工具调用状态。
    /// - Parameters:
    ///   - id: UI 稳定 id。
    ///   - title: 工具标题。
    ///   - detail: 状态详情。
    ///   - status: 当前状态。
    public init(id: UUID, title: String, detail: String, status: Status) {
        self.id = id
        self.title = title
        self.detail = detail
        self.status = status
    }
}

/// ResultPanel 工具调用状态集合，集中维护同一 id 的状态转换。
public struct ResultToolCallStateStore: Sendable, Equatable {
    /// 当前按出现顺序排列的工具调用状态。
    public private(set) var calls: [ResultToolCallState]

    /// 构造空状态集合。
    public init(calls: [ResultToolCallState] = []) {
        self.calls = calls
    }

    /// 记录 LLM 提出的工具调用。
    /// - Parameters:
    ///   - id: UI 稳定 id。
    ///   - title: 工具标题。
    ///   - detail: 参数摘要。
    public mutating func proposed(id: UUID, title: String, detail: String) {
        upsert(id: id, title: title, detail: detail, status: .proposed)
    }

    /// 将工具调用标记为已批准。
    /// - Parameter id: UI 稳定 id。
    public mutating func approved(id: UUID) {
        update(id: id, status: .approved, fallbackDetail: "Approved")
    }

    /// 将工具调用标记为成功并记录结果摘要。
    /// - Parameters:
    ///   - id: UI 稳定 id。
    ///   - summary: 结果摘要。
    public mutating func result(id: UUID, summary: String) {
        update(id: id, status: .result, detail: summary)
    }

    /// 将工具调用标记为拒绝并记录原因。
    /// - Parameters:
    ///   - id: UI 稳定 id。
    ///   - reason: 拒绝原因。
    public mutating func denied(id: UUID, reason: String) {
        update(id: id, status: .denied, detail: reason)
    }

    /// 将工具调用标记为错误并记录摘要。
    /// - Parameters:
    ///   - id: UI 稳定 id。
    ///   - summary: 错误摘要。
    public mutating func error(id: UUID, summary: String) {
        update(id: id, status: .error, detail: summary)
    }

    /// 清空所有工具调用状态。
    public mutating func reset() {
        calls.removeAll()
    }

    /// 插入或覆盖同一 id 的完整状态。
    private mutating func upsert(id: UUID, title: String, detail: String, status: ResultToolCallState.Status) {
        let state = ResultToolCallState(id: id, title: title, detail: detail, status: status)
        if let index = calls.firstIndex(where: { $0.id == id }) {
            calls[index] = state
        } else {
            calls.append(state)
        }
    }

    /// 更新已有状态；若事件乱序到达，则创建兜底行，避免 UI 静默丢失生命周期事件。
    private mutating func update(
        id: UUID,
        status: ResultToolCallState.Status,
        detail: String? = nil,
        fallbackDetail: String = ""
    ) {
        if let index = calls.firstIndex(where: { $0.id == id }) {
            calls[index].status = status
            if let detail {
                calls[index].detail = detail
            }
        } else {
            calls.append(ResultToolCallState(
                id: id,
                title: "Tool call",
                detail: detail ?? fallbackDetail,
                status: status
            ))
        }
    }
}
