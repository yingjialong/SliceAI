import Foundation
import SliceCore

extension AgentExecutor {

    /// 构造 Agent 可见和可解析的 MCP tool catalog。
    func makeToolCatalog(tool: Tool, agent: AgentTool) async throws -> AgentToolCatalog {
        let descriptors = try await mcpDescriptors()
        let descriptorById = Dictionary(uniqueKeysWithValues: descriptors.map { ($0.id, $0) })
        let allowlist = Set(agent.mcpAllowlist)
        var allByName: [String: MCPToolRef] = [:]
        var chatTools: [ChatTool] = []

        for serverId in Set(agent.mcpAllowlist.map(\.server)) {
            guard let descriptor = descriptorById[serverId] else {
                throw missingServerError(toolId: tool.id)
            }
            let toolDescriptors = try await mcpClient.tools(for: descriptor)
            try registerTools(toolDescriptors, allowlist: allowlist, allByName: &allByName, chatTools: &chatTools)
        }
        try validateAllAllowedToolsExist(tool: tool, allowlist: allowlist, allByName: allByName)
        return AgentToolCatalog(allowlist: allowlist, allByName: allByName, chatTools: chatTools)
    }

    /// 注册一个 server 的工具列表。
    func registerTools(
        _ descriptors: [MCPToolDescriptor],
        allowlist: Set<MCPToolRef>,
        allByName: inout [String: MCPToolRef],
        chatTools: inout [ChatTool]
    ) throws {
        for descriptor in descriptors {
            if let existing = allByName[descriptor.ref.tool], existing != descriptor.ref {
                throw SliceError.configuration(.validationFailed("Duplicate MCP tool names are not supported"))
            }
            allByName[descriptor.ref.tool] = descriptor.ref
            if allowlist.contains(descriptor.ref) {
                chatTools.append(ChatTool(
                    name: descriptor.ref.tool,
                    description: descriptor.description ?? descriptor.title,
                    inputSchema: descriptor.inputSchema
                ))
            }
        }
    }

    /// 确认 allowlist 中的每个 ref 都能从 server tools/list 解析到。
    func validateAllAllowedToolsExist(
        tool: Tool,
        allowlist: Set<MCPToolRef>,
        allByName: [String: MCPToolRef]
    ) throws {
        let availableRefs = Set(allByName.values)
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
    let allByName: [String: MCPToolRef]
    let chatTools: [ChatTool]

    /// 按 function name 找 MCP ref；未知 tool 走 redacted synthetic ref，供 UI 事件显示固定形状。
    func ref(forToolName name: String) -> MCPToolRef {
        allByName[name] ?? MCPToolRef(server: "<redacted>", tool: name)
    }

    /// 判断 ref 是否在 Agent allowlist 中。
    func isAllowed(_ ref: MCPToolRef) -> Bool {
        allowlist.contains(ref)
    }
}
