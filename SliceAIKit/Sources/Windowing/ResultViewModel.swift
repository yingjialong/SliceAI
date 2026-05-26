import SliceCore
import SwiftUI

/// 结果窗的 SwiftUI 状态源。
///
/// 作为 `ObservableObject` 在主 actor 驱动 UI；`@Published` 字段由 `ResultPanel`
/// 公开方法改写，SwiftUI 视图通过 `@ObservedObject` 订阅变化。
@MainActor
final class ResultViewModel: ObservableObject {

    /// 流式输出的完整生命周期状态。
    enum StreamingState: Equatable {
        /// 刚创建，未开始请求。
        case idle
        /// 请求已发出，等待 LLM 首字节响应。
        case thinking
        /// 正在接收流式 delta，文本持续追加中。
        case streaming
        /// 流正常结束，文本已完整展示。
        case finished
        /// 流以错误结束，切换到错误态视图。
        case error
    }

    /// 当前流式状态。
    @Published var streamingState: StreamingState = .idle
    /// 当前工具名。
    @Published var toolName: String = ""
    /// 当前模型名。
    @Published var model: String = ""
    /// 已累积的 Markdown 文本或 structured 原始 final text。
    @Published var text: String = ""
    /// 用户可见的错误信息。
    @Published var errorMessage: String?
    /// 错误详情，已由 `SliceError` 脱敏。
    @Published var errorDetail: String?
    /// 是否钉住。
    @Published var isPinned: Bool = false
    /// 当前 Agent MCP 工具调用生命周期行。
    @Published var toolCalls: [ResultToolCallState] = []
    /// structured display mode 的解析字段；nil 时正文按 Markdown 渲染。
    @Published var structuredFields: [StructuredField]?

    /// 是否处于活跃流式输出中。
    var isStreaming: Bool {
        streamingState == .thinking || streamingState == .streaming
    }

    /// "重试"动作回调。
    var onRetry: (@MainActor () -> Void)?
    /// "打开设置"动作回调。
    var onOpenSettings: (@MainActor () -> Void)?
    /// "钉/取消钉"切换回调。
    var onTogglePin: (@MainActor () -> Void)?
    /// "关闭窗口"回调。
    var onClose: (@MainActor () -> Void)?
    /// "复制"回调。
    var onCopy: (@MainActor () -> Void)?
    /// "重新生成"回调。
    var onRegenerate: (@MainActor () -> Void)?

    /// 纯状态模型，负责按 tool-call id 维护 upsert 与状态转换。
    private var toolCallStore = ResultToolCallStateStore()

    /// 重置视图状态为新一次请求。
    ///
    /// - Parameters:
    ///   - toolName: 当前工具显示名。
    ///   - model: 当前模型显示名。
    func reset(toolName: String, model: String) {
        self.toolName = toolName
        self.model = model
        self.text = ""
        self.streamingState = .thinking
        self.errorMessage = nil
        self.errorDetail = nil
        self.toolCallStore.reset()
        self.toolCalls = toolCallStore.calls
        self.structuredFields = nil
        self.onRetry = nil
        self.onOpenSettings = nil
        self.onCopy = nil
        self.onRegenerate = nil
    }

    /// 拼接一段流式 delta 到现有文本。
    /// - Parameter delta: 单段 LLM stream 文本。
    func append(_ delta: String) {
        if streamingState == .thinking {
            streamingState = .streaming
        }
        text += delta
    }

    /// 展示 LLM 提出的 MCP 工具调用。
    /// - Parameters:
    ///   - id: 生命周期稳定 id。
    ///   - title: 工具标题。
    ///   - detail: 参数摘要。
    func showToolCallProposed(id: UUID, title: String, detail: String) {
        toolCallStore.proposed(id: id, title: title, detail: detail)
        publishToolCalls()
    }

    /// 将 MCP 工具调用标记为已通过权限检查。
    /// - Parameter id: 生命周期稳定 id。
    func showToolCallApproved(id: UUID) {
        toolCallStore.approved(id: id)
        publishToolCalls()
    }

    /// 将 MCP 工具调用标记为成功返回结果。
    /// - Parameters:
    ///   - id: 生命周期稳定 id。
    ///   - summary: 结果摘要。
    func showToolCallResult(id: UUID, summary: String) {
        toolCallStore.result(id: id, summary: summary)
        publishToolCalls()
    }

    /// 将 MCP 工具调用标记为被权限或 allowlist 拒绝。
    /// - Parameters:
    ///   - id: 生命周期稳定 id。
    ///   - reason: 拒绝原因。
    func showToolCallDenied(id: UUID, reason: String) {
        toolCallStore.denied(id: id, reason: reason)
        publishToolCalls()
    }

    /// 将 MCP 工具调用标记为执行错误。
    /// - Parameters:
    ///   - id: 生命周期稳定 id。
    ///   - summary: 错误摘要。
    func showToolCallError(id: UUID, summary: String) {
        toolCallStore.error(id: id, summary: summary)
        publishToolCalls()
    }

    /// 标记流正常结束。
    func finish() {
        streamingState = .finished
    }

    /// 展示结构化结果并结束加载态。
    ///
    /// - Parameters:
    ///   - fields: 已解析的 structured 字段。
    ///   - rawText: 原始 final text；用于复制按钮。
    func showStructured(fields: [StructuredField], rawText: String) {
        self.text = rawText
        self.structuredFields = fields
        self.streamingState = .finished
    }

    /// 标记流失败。
    /// - Parameters:
    ///   - message: 面向用户的错误摘要。
    ///   - detail: 开发者上下文，调用方需保证已脱敏。
    ///   - onRetry: 可选重试回调。
    ///   - onOpenSettings: 可选打开设置回调。
    func fail(
        message: String,
        detail: String,
        onRetry: (@MainActor () -> Void)?,
        onOpenSettings: (@MainActor () -> Void)?
    ) {
        self.streamingState = .error
        self.errorMessage = message
        self.errorDetail = detail
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }

    /// 发布当前工具调用状态数组。
    private func publishToolCalls() {
        toolCalls = toolCallStore.calls
    }
}
