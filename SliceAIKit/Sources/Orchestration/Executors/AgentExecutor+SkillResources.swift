import Capabilities
import Foundation
import SliceCore

/// 已通过本地校验的 skill supporting file 请求。
private struct AgentSkillResourceRequest {
    let skill: Skill
    let name: String
    let path: String
}

/// skill supporting file 请求的本地校验结果。
private enum AgentSkillResourceValidation {
    case valid(AgentSkillResourceRequest)
    case invalid(summary: String, content: String)
}

extension AgentExecutor {

    /// 本地处理 `sliceai_load_skill_resource` pseudo-tool，只读取已加载 skill 的已索引资源。
    /// - Parameters:
    ///   - context: 当前 provider tool call 上下文。
    ///   - catalog: 当前 Agent 可用工具 catalog。
    ///   - toolCallState: 当前运行状态，用于确认 skill 主说明已加载。
    /// - Returns: 回填给 provider 的 tool message。
    func handleLoadSkillResource(
        _ context: AgentToolCallContext,
        catalog: AgentToolCatalog,
        toolCallState: AgentToolCallRunState
    ) async -> ChatMessage {
        context.continuation.yield(.toolCallApproved(id: context.uiId))
        switch validateSkillResourceRequest(context, catalog: catalog, toolCallState: toolCallState) {
        case .valid(let request):
            return await loadSkillResource(request, context: context)
        case .invalid(let summary, let content):
            return failToolCall(context, summary: summary, content: content)
        }
    }

    /// 校验 provider 请求是否只访问当前 Agent 已加载 skill 的已列出资源。
    private func validateSkillResourceRequest(
        _ context: AgentToolCallContext,
        catalog: AgentToolCatalog,
        toolCallState: AgentToolCallRunState
    ) -> AgentSkillResourceValidation {
        guard let args = context.call.arguments,
              case .string(let name) = args["name"],
              case .string(let path) = args["path"],
              !name.isEmpty,
              !path.isEmpty else {
            return .invalid(
                summary: "invalid skill resource arguments",
                content: """
                Use {"name":"<skill name>","path":"<resource path>"} to read a listed resource
                """
            )
        }
        guard let skill = catalog.skillByName[name] else {
            return .invalid(
                summary: "Skill not bound: \(Redaction.scrub(name))",
                content: "Skill not bound to this Agent Tool: \(Redaction.scrub(name))"
            )
        }
        return validateSkillResourcePath(skill: skill, name: name, path: path, toolCallState: toolCallState)
    }

    /// 校验 resource path 是否属于已加载 skill 的 metadata 列表。
    private func validateSkillResourcePath(
        skill: Skill,
        name: String,
        path: String,
        toolCallState: AgentToolCallRunState
    ) -> AgentSkillResourceValidation {
        guard toolCallState.loadedSkillNames.contains(name) else {
            return .invalid(
                summary: "load skill first: \(Redaction.scrub(name))",
                content: "Load the skill with sliceai_load_skill before reading supporting files"
            )
        }
        guard skill.resources.contains(where: { $0.relativePath == path }) else {
            return .invalid(
                summary: "Skill resource not listed: \(Redaction.scrub(path))",
                content: "Skill resource is not listed in this Agent Tool metadata: \(Redaction.scrub(path))"
            )
        }
        return .valid(AgentSkillResourceRequest(skill: skill, name: name, path: path))
    }

    /// 调用 registry 读取资源并映射为 provider tool message。
    private func loadSkillResource(
        _ request: AgentSkillResourceRequest,
        context: AgentToolCallContext
    ) async -> ChatMessage {
        do {
            let payload = try await skillRegistry.loadSkillResource(
                id: request.skill.id,
                relativePath: request.path
            )
            let summary = "Loaded skill resource: \(Redaction.scrub(request.path))"
            context.continuation.yield(.toolCallResult(id: context.uiId, summary: summary))
            logger.debug("loaded SliceAI skill resource \(request.path, privacy: .public)")
            return toolMessage(call: context.call, content: skillResourceToolMessage(payload))
        } catch {
            let summary = summarize(error: error)
            return failToolCall(context, summary: summary, content: summary)
        }
    }

    /// 构造回填给模型的 supporting file 内容。
    /// - Parameter payload: registry 加载出的资源 payload。
    /// - Returns: 包含路径、MIME 和正文的 tool message。
    func skillResourceToolMessage(_ payload: SkillResourcePayload) -> String {
        let content = """
        Loaded SliceAI skill resource: \(payload.canonicalName)
        Resource: \(payload.relativePath)
        Path: \(payload.fileURL.path)
        MIME: \(payload.mimeType)

        Content:
        \(payload.content)
        """
        return sanitizeToolMessageContent(content)
    }
}
