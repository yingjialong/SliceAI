import Foundation
import SliceCore

/// Agent 初始 prompt 构造器。
///
/// 本类型只做纯字符串渲染，不触碰 LLM / MCP / 权限。把 prompt 组装从
/// `AgentExecutor` 主 loop 拆出，可以让 ReAct loop 保持在"请求-执行-回填"的核心流程上。
enum AgentPromptBuilder {

    /// 构造 AgentExecutor 第一轮 ChatMessage。
    /// - Parameters:
    ///   - agent: AgentTool 配置。
    ///   - resolved: ContextCollector 已解析的上下文。
    /// - Returns: system/user 初始消息。
    static func buildInitialMessages(
        agent: AgentTool,
        resolved: ResolvedExecutionContext
    ) -> [ChatMessage] {
        let variables = makeVariables(resolved: resolved)
        var messages: [ChatMessage] = []
        if let systemPrompt = agent.systemPrompt, !systemPrompt.isEmpty {
            messages.append(ChatMessage(
                role: .system,
                content: PromptTemplate.render(systemPrompt, variables: variables)
            ))
        }
        let userPrompt = PromptTemplate.render(agent.initialUserPrompt, variables: variables)
        messages.append(ChatMessage(role: .user, content: appendContextBag(userPrompt, resolved: resolved)))
        return messages
    }

    /// 构造模板变量。
    /// - Parameter resolved: 已解析上下文。
    /// - Returns: Agent prompt 可使用的变量字典。
    private static func makeVariables(resolved: ResolvedExecutionContext) -> [String: String] {
        [
            "selection": resolved.selection.text,
            "app": resolved.frontApp.name,
            "url": resolved.frontApp.url?.absoluteString ?? "",
            "language": resolved.selection.language ?? "",
            "windowTitle": resolved.frontApp.windowTitle ?? ""
        ]
    }

    /// 把 ContextBag 附加到 user prompt 尾部。
    /// - Parameters:
    ///   - prompt: 已渲染的 user prompt。
    ///   - resolved: 已解析上下文。
    /// - Returns: 带上下文摘要的 user prompt。
    private static func appendContextBag(
        _ prompt: String,
        resolved: ResolvedExecutionContext
    ) -> String {
        let summaries = contextSummaries(resolved: resolved)
        guard !summaries.isEmpty else { return prompt }
        return prompt + "\n\nContext:\n" + summaries.joined(separator: "\n")
    }

    /// 生成稳定顺序的上下文摘要。
    /// - Parameter resolved: 已解析上下文。
    /// - Returns: 每个上下文一行的脱敏摘要。
    private static func contextSummaries(resolved: ResolvedExecutionContext) -> [String] {
        resolved.contexts.values
            .sorted { $0.key.rawValue < $1.key.rawValue }
            .map { key, value in
                "- \(key.rawValue): \(summarize(value))"
            }
    }

    /// 将 ContextValue 转为适合进入 prompt 的短摘要。
    /// - Parameter value: 上下文值。
    /// - Returns: 脱敏后的短摘要。
    private static func summarize(_ value: ContextValue) -> String {
        switch value {
        case .text(let text):
            return Redaction.scrub(text)
        case .json(let data):
            return "<json \(data.count) bytes>"
        case .file(let url, let mimeType):
            return Redaction.scrub("<file \(url.path) \(mimeType)>")
        case .image(let data, let format):
            return "<image \(format) \(data.count) bytes>"
        case .error(let error):
            return error.developerContext
        }
    }
}
