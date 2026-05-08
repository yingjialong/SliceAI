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
        return AgentToolCatalog(allowlist: allowlist, allowlistedByName: allowlistedByName, chatTools: chatTools)
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

/// Agent 可调用 MCP tool catalog。
struct AgentToolCatalog: Sendable {
    let allowlist: Set<MCPToolRef>
    let allowlistedByName: [String: MCPToolRef]
    let chatTools: [ChatTool]

    /// 按 function name 找 MCP ref；未知 tool 走 redacted synthetic ref，供 UI 事件显示固定形状。
    func ref(forToolName name: String) -> MCPToolRef {
        allowlistedByName[name] ?? MCPToolRef(server: "<redacted>", tool: name)
    }

    /// 判断 ref 是否在 Agent allowlist 中。
    func isAllowed(_ ref: MCPToolRef) -> Bool {
        allowlist.contains(ref)
    }
}
