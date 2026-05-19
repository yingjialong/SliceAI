import Foundation
import OSLog
import SliceCore

private let claudeDesktopMCPImportLog = Logger(
    subsystem: "com.sliceai.capabilities",
    category: "ClaudeDesktopMCPImporter"
)

/// Claude Desktop `mcpServers` 配置导入器。
///
/// M1 只导入本地 stdio 配置；远程 URL / SSE / HTTP 留到 M4。
public struct ClaudeDesktopMCPImporter: Sendable {

    /// 构造 Claude Desktop MCP importer。
    public init() {}

    /// 从 Claude Desktop JSON 数据导入 MCPDescriptor。
    /// - Parameters:
    ///   - data: Claude Desktop 配置 JSON 数据。
    ///   - provenance: 调用方确认后的来源；`.unknown` 会被拒绝。
    /// - Returns: 按 id 排序的 canonical MCPDescriptor 列表。
    /// - Throws: JSON 解码错误或 `MCPServerValidationError`。
    public func importDescriptors(from data: Data, provenance: Provenance) throws -> [MCPDescriptor] {
        let config = try JSONDecoder().decode(ClaudeDesktopConfig.self, from: data)
        let descriptors = try config.mcpServers.map { id, server in
            try importDescriptor(id: id, server: server, provenance: provenance)
        }
        let sorted = descriptors.sorted { lhs, rhs in
            lhs.id < rhs.id
        }
        claudeDesktopMCPImportLog.debug("imported Claude Desktop MCP servers count=\(sorted.count, privacy: .public)")
        return sorted
    }

    /// 导入单个 Claude Desktop server 配置。
    /// - Parameters:
    ///   - id: Claude Desktop `mcpServers` 字典 key。
    ///   - server: 单个 server 配置。
    ///   - provenance: 调用方确认后的来源。
    /// - Returns: canonical MCPDescriptor。
    /// - Throws: 兼容性或 provenance 校验错误。
    private func importDescriptor(
        id: String,
        server: ClaudeDesktopServer,
        provenance: Provenance
    ) throws -> MCPDescriptor {
        try MCPServerValidation.validateKnownProvenance(provenance, id: id)

        if server.url != nil {
            throw MCPServerValidationError.invalidRemoteURL(id: id)
        }

        guard let command = server.command,
              command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else {
            throw MCPServerValidationError.missingCommand(id: id)
        }

        return MCPDescriptor(
            id: id,
            transport: .stdio,
            command: command,
            args: server.args,
            url: nil,
            env: server.env,
            capabilities: [],
            provenance: provenance
        )
    }
}

/// Claude Desktop 顶层 JSON shape。
private struct ClaudeDesktopConfig: Decodable {
    /// Claude Desktop `mcpServers` 字典。
    let mcpServers: [String: ClaudeDesktopServer]
}

/// Claude Desktop 单个 server JSON shape。
private struct ClaudeDesktopServer: Decodable {
    /// stdio command。
    let command: String?
    /// stdio args。
    let args: [String]?
    /// stdio env。
    let env: [String: String]?
    /// 远程 URL；M1 看到即拒绝。
    let url: URL?
}
