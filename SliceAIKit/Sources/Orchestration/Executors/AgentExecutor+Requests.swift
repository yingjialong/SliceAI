import Foundation
import SliceCore

extension AgentExecutor {

    /// 构造 Agent 首轮消息。
    func makeInitialMessages(
        agent: AgentTool,
        resolved: ResolvedExecutionContext,
        catalog: AgentToolCatalog
    ) -> [ChatMessage] {
        AgentPromptBuilder.buildInitialMessages(
            agent: agent,
            resolved: resolved,
            boundSkills: catalog.boundSkills
        )
    }

    /// 构造单次 Agent 运行的工具调用状态。
    func makeToolCallRunState(
        agent: AgentTool,
        catalog: AgentToolCatalog,
        maxSteps: Int
    ) -> AgentToolCallRunState {
        AgentToolCallRunState(
            policy: effectiveToolCallPolicy(agent: agent, catalog: catalog, maxSteps: maxSteps)
        )
    }

    /// 构造一轮 tool-chat 请求。
    nonisolated func makeChatToolRequest(
        model: String,
        messages: [ChatMessage],
        catalog: AgentToolCatalog,
        toolChoice: ChatToolChoice
    ) -> ChatToolRequest {
        ChatToolRequest(
            model: model,
            messages: messages,
            tools: catalog.chatTools,
            toolChoice: toolChoice
        )
    }

    /// 构造禁用工具后的最终答案请求。
    ///
    /// 这里刻意不传 tools schema，也不传 `tool_choice`。部分 OpenAI-compatible provider 在
    /// `tool_choice=none` 但仍收到 tools schema 时，会把内部工具调用标记当普通文本输出。
    nonisolated func makeFinalAnswerRequest(model: String, messages: [ChatMessage]) -> ChatToolRequest {
        ChatToolRequest(
            model: model,
            messages: messages + [finalAnswerInstructionMessage()],
            tools: [],
            toolChoice: nil
        )
    }

    /// 构造最终答案指令消息。
    nonisolated func finalAnswerInstructionMessage() -> ChatMessage {
        ChatMessage(
            role: .user,
            content: """
            No more tool calls are available. Based only on the tool results already provided, write the final \
            answer for the user. Do not output tool-call markup, XML, JSON, or internal protocol tokens.
            """
        )
    }

    /// 判断 provider 是否把内部工具调用协议误作为普通文本返回。
    nonisolated func containsToolCallMarkup(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let hasToolCalls = normalized.contains("tool_calls")
        let hasMarkupToken = normalized.contains("dsml")
            || normalized.contains("invoke name=")
            || normalized.contains("parameter name=")
        return hasToolCalls && hasMarkupToken
    }

    /// 解析工具级 model override。
    nonisolated func resolveModel(selection: ProviderSelection, fallback: String) -> String {
        if case .fixed(_, let modelId) = selection, let modelId {
            return modelId
        }
        return fallback
    }
}
