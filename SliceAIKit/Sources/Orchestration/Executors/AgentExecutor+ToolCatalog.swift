import Foundation
import SliceCore

extension AgentExecutor {

    /// 构造 Agent 可见和可解析的 MCP tool catalog。
    func makeToolCatalog(tool: Tool, agent: AgentTool) async throws -> AgentToolCatalog {
        let descriptors = try await mcpDescriptors()
        let descriptorById = try makeDescriptorLookup(descriptors)
        let allowlist = Set(agent.mcpAllowlist)
        var allowlistedByName: [String: MCPToolRef] = [:]
        var availableRefs = Set<MCPToolRef>()
        var chatTools: [ChatTool] = []
        let boundSkills = try await resolveBoundSkills(tool: tool, agent: agent)

        for serverId in Set(agent.mcpAllowlist.map(\.server)) {
            guard let descriptor = descriptorById[serverId] else {
                throw missingServerError(toolId: tool.id)
            }
            let toolDescriptors = try await mcpClient.tools(for: descriptor)
            try registerTools(
                toolDescriptors,
                allowlist: allowlist,
                allowlistedByName: &allowlistedByName,
                availableRefs: &availableRefs,
                chatTools: &chatTools
            )
        }
        try validateAllAllowedToolsExist(tool: tool, allowlist: allowlist, availableRefs: availableRefs)
        if !boundSkills.isEmpty {
            chatTools.append(Self.loadSkillChatTool())
            if boundSkills.contains(where: { !$0.resources.isEmpty }) {
                chatTools.append(Self.loadSkillResourceChatTool())
            }
        }
        return AgentToolCatalog(
            allowlist: allowlist,
            allowlistedByName: allowlistedByName,
            chatTools: chatTools,
            boundSkills: boundSkills,
            skillByName: Dictionary(uniqueKeysWithValues: boundSkills.map { ($0.canonicalName, $0) })
        )
    }

    /// 解析当前 Agent 绑定的 enabled skills。
    /// - Parameters:
    ///   - tool: 顶层 Tool，用于构造配置错误。
    ///   - agent: AgentTool 配置。
    /// - Returns: 按绑定顺序返回的 Skill 数组。
    func resolveBoundSkills(tool: Tool, agent: AgentTool) async throws -> [Skill] {
        var skills: [Skill] = []
        var seenNames = Set<String>()
        for reference in agent.skills {
            guard let skill = try await skillRegistry.findSkill(id: reference.id) else {
                throw SliceError.configuration(.invalidTool(
                    id: tool.id,
                    reason: "Skill not configured or disabled: <redacted>"
                ))
            }
            guard seenNames.insert(skill.canonicalName).inserted else {
                throw SliceError.configuration(.invalidTool(
                    id: tool.id,
                    reason: "Duplicate bound skill name: <redacted>"
                ))
            }
            skills.append(skill)
        }
        return skills
    }

    /// 构造 provider 可见的本地 skill 加载 pseudo-tool schema。
    /// - Returns: OpenAI-compatible function tool。
    static func loadSkillChatTool() -> ChatTool {
        ChatTool(
            name: AgentBuiltInTool.loadSkillName,
            description: "Load the full SKILL.md instructions for a bound SliceAI skill.",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Exact skill name from the metadata block")
                    ])
                ]),
                "required": .array([.string("name")]),
                "additionalProperties": .bool(false)
            ]
        )
    }

    /// 构造 provider 可见的本地 supporting file 只读加载 pseudo-tool schema。
    /// - Returns: OpenAI-compatible function tool。
    static func loadSkillResourceChatTool() -> ChatTool {
        ChatTool(
            name: AgentBuiltInTool.loadSkillResourceName,
            description: "Read a listed references/ or text assets/ file from an already loaded bound SliceAI skill.",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "name": .object([
                        "type": .string("string"),
                        "description": .string("Exact skill name from the metadata block")
                    ]),
                    "path": .object([
                        "type": .string("string"),
                        "description": .string("Exact resource path listed in the skill metadata block")
                    ])
                ]),
                "required": .array([.string("name"), .string("path")]),
                "additionalProperties": .bool(false)
            ]
        )
    }

    /// 构造 server id 查找表；重复 id 必须走可恢复配置错误，避免字典初始化 trap。
    func makeDescriptorLookup(_ descriptors: [MCPDescriptor]) throws -> [String: MCPDescriptor] {
        var descriptorById: [String: MCPDescriptor] = [:]
        for descriptor in descriptors {
            guard descriptorById[descriptor.id] == nil else {
                throw SliceError.configuration(.validationFailed("Duplicate MCP server id: <redacted>"))
            }
            descriptorById[descriptor.id] = descriptor
        }
        return descriptorById
    }

    /// 注册一个 server 的工具列表。
    func registerTools(
        _ descriptors: [MCPToolDescriptor],
        allowlist: Set<MCPToolRef>,
        allowlistedByName: inout [String: MCPToolRef],
        availableRefs: inout Set<MCPToolRef>,
        chatTools: inout [ChatTool]
    ) throws {
        for descriptor in descriptors {
            availableRefs.insert(descriptor.ref)
            guard allowlist.contains(descriptor.ref) else { continue }
            if let existing = allowlistedByName[descriptor.ref.tool], existing != descriptor.ref {
                throw SliceError.configuration(.validationFailed("Duplicate MCP tool names are not supported"))
            }
            allowlistedByName[descriptor.ref.tool] = descriptor.ref
            chatTools.append(ChatTool(
                name: descriptor.ref.tool,
                description: descriptor.description ?? descriptor.title,
                inputSchema: descriptor.inputSchema
            ))
        }
    }

    /// 确认 allowlist 中的每个 ref 都能从 server tools/list 解析到。
    func validateAllAllowedToolsExist(
        tool: Tool,
        allowlist: Set<MCPToolRef>,
        availableRefs: Set<MCPToolRef>
    ) throws {
        guard allowlist.isSubset(of: availableRefs) else {
            throw SliceError.configuration(.invalidTool(
                id: tool.id,
                reason: "MCP tool not configured: <redacted>"
            ))
        }
    }

    /// 缺失 MCP server 的配置错误。
    func missingServerError(toolId: String) -> SliceError {
        .configuration(.invalidTool(id: toolId, reason: "MCP server not configured: <redacted>"))
    }
}

/// AgentExecutor 内置 pseudo-tool 常量。
enum AgentBuiltInTool {
    /// Provider-visible function name；OpenAI-compatible function name 不能使用点号。
    static let loadSkillName = "sliceai_load_skill"
    /// UI/lifecycle synthetic ref；表达概念上的 `sliceai.load_skill`。
    static let loadSkillRef = MCPToolRef(server: "sliceai", tool: "load_skill")
    /// Provider-visible function name；用于只读加载 supporting file。
    static let loadSkillResourceName = "sliceai_load_skill_resource"
    /// UI/lifecycle synthetic ref；表达概念上的 `sliceai.load_skill_resource`。
    static let loadSkillResourceRef = MCPToolRef(server: "sliceai", tool: "load_skill_resource")
}

/// Agent 可调用 MCP tool catalog。
struct AgentToolCatalog: Sendable {
    let allowlist: Set<MCPToolRef>
    let allowlistedByName: [String: MCPToolRef]
    let chatTools: [ChatTool]
    let boundSkills: [Skill]
    let skillByName: [String: Skill]

    /// 按 function name 找 MCP ref；未知 tool 走 redacted synthetic ref，供 UI 事件显示固定形状。
    func ref(forToolName name: String) -> MCPToolRef {
        if name == AgentBuiltInTool.loadSkillName {
            return AgentBuiltInTool.loadSkillRef
        }
        if name == AgentBuiltInTool.loadSkillResourceName {
            return AgentBuiltInTool.loadSkillResourceRef
        }
        return allowlistedByName[name] ?? MCPToolRef(server: "<redacted>", tool: name)
    }

    /// 判断 ref 是否在 Agent allowlist 中。
    func isAllowed(_ ref: MCPToolRef) -> Bool {
        allowlist.contains(ref)
    }
}
