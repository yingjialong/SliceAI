import Foundation
import SliceCore

/// Agent 初始 prompt 构造器。
///
/// 本类型只做纯字符串渲染，不触碰 LLM / MCP / 权限。把 prompt 组装从
/// `AgentExecutor` 主 loop 拆出，可以让 ReAct loop 保持在"请求-执行-回填"的核心流程上。
enum AgentPromptBuilder {
    /// marker 后 metadata block 的最大字符预算。
    private static let maxSkillMetadataCharacters = 8_000
    /// Skill metadata block 固定 marker，测试和 prompt contract 依赖此文本。
    private static let skillMetadataMarker = "Available SliceAI skills for this tool:"

    /// 构造 AgentExecutor 第一轮 ChatMessage。
    /// - Parameters:
    ///   - agent: AgentTool 配置。
    ///   - resolved: ContextCollector 已解析的上下文。
    ///   - boundSkills: 当前 Agent 绑定且已解析为 enabled 的 skills。
    /// - Returns: system/user 初始消息。
    static func buildInitialMessages(
        agent: AgentTool,
        resolved: ResolvedExecutionContext,
        boundSkills: [Skill] = []
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
        let promptWithContext = appendContextBag(userPrompt, resolved: resolved)
        messages.append(ChatMessage(
            role: .user,
            content: appendSkillMetadata(promptWithContext, boundSkills: boundSkills)
        ))
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

    /// 把当前工具绑定的 skill metadata 附加到 user prompt。
    /// - Parameters:
    ///   - prompt: 已渲染并追加 ContextBag 的 user prompt。
    ///   - boundSkills: 当前 Agent 绑定的 enabled skills。
    /// - Returns: 包含 skill metadata block 的 prompt。
    private static func appendSkillMetadata(_ prompt: String, boundSkills: [Skill]) -> String {
        guard !boundSkills.isEmpty else { return prompt }
        return prompt + "\n\n" + skillMetadataMarker + skillMetadataBody(boundSkills: boundSkills)
    }

    /// 构造 marker 之后的受限 metadata body。
    ///
    /// name/path 是 identity 字段，永远保留；description 使用剩余预算并用 ASCII `...` 截断。
    /// - Parameter boundSkills: 当前 Agent 绑定的 enabled skills。
    /// - Returns: marker 后的 metadata body，正常情况下不超过 8,000 字符。
    private static func skillMetadataBody(boundSkills: [Skill]) -> String {
        let footer = """


Use sliceai_load_skill with the exact skill name when a skill is relevant.
Do not assume instructions from a skill until you load it.
After loading a skill, use sliceai_load_skill_resource with listed references/ or assets/ paths when needed.
Do not request scripts or paths that are not listed.
"""
        let fixedEntries = boundSkills.map { skill in
            """
            - name: \(skill.canonicalName)
              description:
              path: \(skill.skillFile.path)
              resources:
            """
        }
        let fixedBody = "\n" + fixedEntries.joined(separator: "\n") + footer
        var remaining = maxSkillMetadataCharacters - fixedBody.count
        if remaining <= 0 {
            // 5 个 skill 的 MVP 上限下通常不会触发；触发时仍保留 name/path 供模型精确调用。
            print("skill metadata fixed fields exceeded budget")
            return fixedBody
        }

        let entries = boundSkills.map { skill in
            let description = budgetedDescription(skill.manifest.description, remaining: &remaining)
            let resources = budgetedResources(skill.resources, remaining: &remaining)
            let descriptionLine = description.isEmpty ? "  description:" : "  description: \(description)"
            return [
                "- name: \(skill.canonicalName)",
                descriptionLine,
                "  path: \(skill.skillFile.path)",
                "  resources:\(resources)"
            ].joined(separator: "\n")
        }
        return "\n" + entries.joined(separator: "\n") + footer
    }

    /// 从剩余预算中切出 description 文本，并计入 `description: ` 的动态分隔空格。
    /// - Parameters:
    ///   - description: 原始描述。
    ///   - remaining: 可消耗预算；本函数会原地扣减。
    /// - Returns: 原文或带 ASCII `...` 后缀的截断文本。
    private static func budgetedDescription(_ description: String, remaining: inout Int) -> String {
        guard remaining > 1 else { return "" }
        let contentBudget = remaining - 1
        guard description.count <= contentBudget else {
            if contentBudget <= 3 {
                remaining = 0
                return ""
            }
            let prefixCount = contentBudget - 3
            remaining = 0
            return String(description.prefix(prefixCount)) + "..."
        }
        remaining -= description.count + 1
        return description
    }

    /// 从剩余预算中渲染 supporting file 路径列表。
    /// - Parameters:
    ///   - resources: skill 已索引的只读资源。
    ///   - remaining: 可消耗预算；本函数会原地扣减。
    /// - Returns: `resources:` 后的路径行；无资源时返回短空列表标记。
    private static func budgetedResources(_ resources: [SkillResource], remaining: inout Int) -> String {
        guard !resources.isEmpty else { return "" }
        var lines = ""
        for resource in resources.sorted(by: { $0.relativePath < $1.relativePath }) {
            let line = "\n    - \(resource.relativePath)"
            guard line.count <= remaining else {
                let omission = "\n    - ..."
                if omission.count <= remaining {
                    lines += omission
                    remaining -= omission.count
                }
                break
            }
            lines += line
            remaining -= line.count
        }
        return lines
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
