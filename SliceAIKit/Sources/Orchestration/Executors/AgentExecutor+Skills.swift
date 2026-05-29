import Capabilities
import Foundation
import SliceCore

// MARK: - Skill pseudo-tool handling

extension AgentExecutor {

    /// 分派内置 pseudo-tool（skill 加载 / supporting file 读取）。
    ///
    /// 这些 pseudo-tool 不进入 MCP allowlist、权限 gate 或 MCP client；
    /// 不是内置工具时返回 nil，交回 `processOneToolCall` 走常规 MCP 路径。
    /// - Parameters:
    ///   - context: 当前 provider tool call 上下文。
    ///   - catalog: 当前 Agent 可用工具 catalog。
    ///   - toolCallState: 当前运行状态，用于去重已加载 skill。
    /// - Returns: 内置工具的 tool message；非内置工具返回 nil。
    func handleBuiltInToolCall(
        _ context: AgentToolCallContext,
        catalog: AgentToolCatalog,
        toolCallState: inout AgentToolCallRunState
    ) async -> ChatMessage? {
        if context.call.name == AgentBuiltInTool.loadSkillName {
            return await handleLoadSkill(context, catalog: catalog, toolCallState: &toolCallState)
        }
        if context.call.name == AgentBuiltInTool.loadSkillResourceName {
            return await handleLoadSkillResource(context, catalog: catalog, toolCallState: toolCallState)
        }
        return nil
    }

    /// 本地处理 `sliceai_load_skill` pseudo-tool，不进入 MCP allowlist、权限 gate 或 MCP client。
    /// - Parameters:
    ///   - context: 当前 provider tool call 上下文。
    ///   - catalog: 当前 Agent 可用工具 catalog。
    ///   - toolCallState: 当前运行状态，用于去重已加载 skill。
    /// - Returns: 回填给 provider 的 tool message。
    func handleLoadSkill(
        _ context: AgentToolCallContext,
        catalog: AgentToolCatalog,
        toolCallState: inout AgentToolCallRunState
    ) async -> ChatMessage {
        context.continuation.yield(.toolCallApproved(id: context.uiId))
        guard let args = context.call.arguments,
              case .string(let name) = args["name"],
              !name.isEmpty else {
            return failToolCall(
                context,
                summary: "invalid skill load arguments",
                content: "Use {\"name\":\"<skill name>\"} to load a bound skill"
            )
        }
        guard let skill = catalog.skillByName[name] else {
            return failToolCall(
                context,
                summary: "Skill not bound: \(Redaction.scrub(name))",
                content: "Skill not bound to this Agent Tool: \(Redaction.scrub(name))"
            )
        }
        if toolCallState.loadedSkillNames.contains(name) {
            let summary = "Skill already loaded: \(Redaction.scrub(name))"
            context.continuation.yield(.toolCallResult(id: context.uiId, summary: summary))
            return toolMessage(call: context.call, content: summary)
        }
        do {
            let payload = try await skillRegistry.loadSkillInstructions(id: skill.id)
            toolCallState.recordLoadedSkill(name: name)
            let summary = "Loaded skill: \(Redaction.scrub(name))"
            context.continuation.yield(.toolCallResult(id: context.uiId, summary: summary))
            logger.debug("loaded SliceAI skill \(name, privacy: .public)")
            return toolMessage(call: context.call, content: skillToolMessage(payload))
        } catch {
            let summary = summarize(error: error)
            return failToolCall(context, summary: summary, content: summary)
        }
    }

    /// 构造回填给模型的 skill 指令内容。
    /// - Parameter payload: registry 加载出的 SKILL.md payload。
    /// - Returns: 包含 frontmatter 摘要和完整 instructions 的 tool message。
    func skillToolMessage(_ payload: SkillInstructionPayload) -> String {
        let content = """
        Loaded SliceAI skill: \(payload.canonicalName)
        Path: \(payload.skillFile.path)
        Description: \(payload.frontmatterSummary.description)

        Instructions:
        \(payload.instructions)
        """
        return sanitizeToolMessageContent(content)
    }
}
