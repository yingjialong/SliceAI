import Capabilities
import Foundation
import SliceCore
import SwiftUI

/// MCP Servers 设置页视图模型。
///
/// 负责把 SettingsUI 的用户操作转换为 `MCPServerStore` 读写、Claude Desktop JSON 导入，
/// 以及 MCP `tools/list` 测试连接。类型限定在 `@MainActor`，保证 `@Published` 状态只在主线程更新。
@MainActor
public final class MCPServersViewModel: ObservableObject {

    /// 当前 `mcp.json` 中的 server 列表。
    @Published public private(set) var servers: [MCPDescriptor]

    /// 最近一次校验或读写错误，供页面展示。
    @Published public var validationMessage: String?

    /// 按 server id 缓存最近一次 `tools/list` 返回的工具列表，供页面预览。
    @Published public private(set) var toolsByServerID: [String: [MCPToolDescriptor]]

    /// 最近一次连接测试结果文案。
    @Published public private(set) var connectionMessage: String?

    /// 当前正在测试连接的 server id 集合；允许多行同时测试时互不覆盖状态。
    @Published public private(set) var testingServerIDs: Set<String>

    /// MCP server 本地配置 store。
    private let store: MCPServerStore

    /// Claude Desktop JSON 导入器。
    private let importer: ClaudeDesktopMCPImporter

    /// MCP client 抽象；测试注入 `MockMCPClient`，生产默认使用 `RoutingMCPClient`。
    private let client: any MCPClientProtocol

    /// 构造 MCP Servers 设置页 ViewModel。
    /// - Parameters:
    ///   - store: 本地 `mcp.json` store；测试可注入临时文件路径。
    ///   - importer: Claude Desktop JSON 导入器。
    ///   - client: MCP client；nil 时创建 stdio routing client。
    public init(
        store: MCPServerStore = MCPServerStore(),
        importer: ClaudeDesktopMCPImporter = ClaudeDesktopMCPImporter(),
        client: (any MCPClientProtocol)? = nil
    ) {
        self.store = store
        self.importer = importer
        self.client = client ?? Self.makeDefaultClient(store: store)
        self.servers = []
        self.validationMessage = nil
        self.toolsByServerID = [:]
        self.connectionMessage = nil
        self.testingServerIDs = []
    }

    /// 从 `MCPServerStore` 重新加载当前 server 列表。
    public func reload() async {
        do {
            let configuration = try await store.load()
            servers = configuration.servers
            validationMessage = nil
            print("[MCPServersViewModel] reload: loaded servers=\(configuration.servers.count)")
        } catch {
            let message = validationMessage(for: error)
            validationMessage = message
            print("[MCPServersViewModel] reload: failed - \(message)")
        }
    }

    /// 导入 Claude Desktop `mcpServers` JSON，并合并保存到本地 `mcp.json`。
    /// - Parameter data: Claude Desktop 配置 JSON 数据。
    public func importClaudeDesktopConfig(_ data: Data) async {
        do {
            let imported = try importer.importDescriptors(
                from: data,
                provenance: .selfManaged(userAcknowledgedAt: Date())
            )
            let configuration = try await store.update { configuration in
                configuration.servers = Self.merge(existing: configuration.servers, imported: imported)
            }
            servers = configuration.servers
            clearToolsPreview(ids: imported.map(\.id))
            validationMessage = nil
            connectionMessage = "已导入 \(imported.count) 个 MCP server"
            print("[MCPServersViewModel] importClaudeDesktopConfig: imported count=\(imported.count)")
        } catch {
            let message = validationMessage(for: error)
            validationMessage = message
            print("[MCPServersViewModel] importClaudeDesktopConfig: failed - \(message)")
        }
    }

    /// 保存单个 MCP server descriptor；同 id 时覆盖，新增 id 时追加。
    /// - Parameters:
    ///   - descriptor: 待保存的 MCP server descriptor。
    ///   - originalID: 编辑前的 server id；改 id 时用于原子删除旧 id。
    public func save(_ descriptor: MCPDescriptor, replacing originalID: String? = nil) async {
        do {
            let configuration = try await store.update { configuration in
                try Self.replaceOrUpsert(descriptor, replacing: originalID, into: &configuration.servers)
            }
            servers = configuration.servers
            clearToolsPreview(ids: [originalID, descriptor.id].compactMap { $0 })
            validationMessage = nil
            connectionMessage = "已保存 \(descriptor.id)"
            print("[MCPServersViewModel] save: saved id=\(descriptor.id)")
        } catch {
            let message = validationMessage(for: error)
            validationMessage = message
            print("[MCPServersViewModel] save: failed - \(message)")
        }
    }

    /// 删除指定 id 的 MCP server 并持久化。
    /// - Parameter id: 要删除的 server id。
    public func delete(id: String) async {
        do {
            let configuration = try await store.update { configuration in
                configuration.servers.removeAll { $0.id == id }
            }
            servers = configuration.servers
            clearToolsPreview(ids: [id])
            validationMessage = nil
            connectionMessage = "已删除 \(id)"
            print("[MCPServersViewModel] delete: deleted id=\(id)")
        } catch {
            let message = validationMessage(for: error)
            validationMessage = message
            print("[MCPServersViewModel] delete: failed - \(message)")
        }
    }

    /// 对指定 server 执行 `tools/list` 测试连接，并缓存工具预览。
    /// - Parameter id: 要测试连接的 server id。
    public func testConnection(id: String) async {
        guard let descriptor = servers.first(where: { $0.id == id }) else {
            let message = "未找到 MCP server：\(id)"
            validationMessage = message
            connectionMessage = message
            print("[MCPServersViewModel] testConnection: failed - \(message)")
            return
        }

        testingServerIDs.insert(id)
        defer {
            testingServerIDs.remove(id)
        }

        do {
            let tools = try await client.tools(for: descriptor)
            toolsByServerID[id] = tools
            validationMessage = nil
            connectionMessage = "连接成功：发现 \(tools.count) 个工具"
            print("[MCPServersViewModel] testConnection: success id=\(id) tools=\(tools.count)")
        } catch {
            let message = validationMessage(for: error)
            toolsByServerID[id] = nil
            validationMessage = message
            connectionMessage = "连接失败：\(message)"
            print("[MCPServersViewModel] testConnection: failed - \(message)")
        }
    }

    /// 查询指定 server 是否正在测试连接。
    /// - Parameter id: server id。
    /// - Returns: 正在测试时返回 true。
    public func isTesting(id: String) -> Bool {
        testingServerIDs.contains(id)
    }

    /// 创建生产默认 MCP client。
    /// - Parameter store: 默认 client 读取 descriptor snapshot 的 store。
    /// - Returns: 只启用 stdio 的 routing client；旧 SSE 不会被创建或连接。
    private static func makeDefaultClient(store: MCPServerStore) -> any MCPClientProtocol {
        let descriptorsProvider: @Sendable () async throws -> [MCPDescriptor] = {
            try await store.snapshot()
        }
        let stdio = StdioMCPClient(descriptors: descriptorsProvider)
        return RoutingMCPClient(descriptors: descriptorsProvider, stdio: stdio)
    }

    /// 合并导入结果：同 id 覆盖，新增 id 追加。
    /// - Parameters:
    ///   - existing: 当前 store 中已有的 server 列表。
    ///   - imported: 本次从 Claude Desktop 导入的 server 列表。
    /// - Returns: 合并后的 server 列表。
    private nonisolated static func merge(existing: [MCPDescriptor], imported: [MCPDescriptor]) -> [MCPDescriptor] {
        var merged = existing
        for descriptor in imported {
            upsert(descriptor, into: &merged)
        }
        return merged
    }

    /// 将 descriptor 按 id 写入数组；存在则替换，不存在则追加。
    /// - Parameters:
    ///   - descriptor: 待写入的 descriptor。
    ///   - servers: 被原地更新的 server 数组。
    private nonisolated static func upsert(_ descriptor: MCPDescriptor, into servers: inout [MCPDescriptor]) {
        if let index = servers.firstIndex(where: { $0.id == descriptor.id }) {
            // 保持原有顺序，只替换同 id 内容。
            servers[index] = descriptor
        } else {
            servers.append(descriptor)
        }
    }

    /// 按编辑来源替换或新增 descriptor。
    /// - Parameters:
    ///   - descriptor: 待保存的 descriptor。
    ///   - originalID: 编辑前 id；nil 时走普通 upsert。
    ///   - servers: 被原地更新的 server 数组。
    /// - Throws: 新 id 与其他 server 冲突时抛 `.duplicateServerID`。
    private nonisolated static func replaceOrUpsert(
        _ descriptor: MCPDescriptor,
        replacing originalID: String?,
        into servers: inout [MCPDescriptor]
    ) throws {
        guard let originalID else {
            upsert(descriptor, into: &servers)
            return
        }

        if originalID != descriptor.id, servers.contains(where: { $0.id == descriptor.id }) {
            throw MCPServerValidationError.duplicateServerID(id: descriptor.id)
        }

        if let index = servers.firstIndex(where: { $0.id == originalID }) {
            servers[index] = descriptor
        } else {
            servers.append(descriptor)
        }
    }

    /// 清理指定 server id 的工具预览缓存。
    /// - Parameter ids: 需要失效的 server id 列表。
    private func clearToolsPreview(ids: [String]) {
        for id in ids {
            toolsByServerID[id] = nil
        }
    }

    /// 将错误转换为用户可读且不泄露敏感路径的校验提示。
    /// - Parameter error: store、importer 或 client 抛出的错误。
    /// - Returns: 可展示在 UI 上的错误说明。
    private func validationMessage(for error: any Error) -> String {
        if let validationError = error as? MCPServerValidationError {
            return validationMessage(for: validationError)
        }
        if let clientError = error as? MCPClientError {
            return clientError.developerContext
        }
        return error.localizedDescription
    }

    /// 将 MCP server 校验错误转换为更明确的 UI 提示。
    /// - Parameter error: MCP server validation error。
    /// - Returns: 可展示在 UI 上的错误说明。
    private func validationMessage(for error: MCPServerValidationError) -> String {
        switch error {
        case .unsupportedSchemaVersion(let version):
            return "不支持的 mcp.json schemaVersion：\(version)"
        case .duplicateServerID(let id):
            return "MCP server id 重复：\(id)"
        case .unknownProvenance(let id):
            return "MCP server \(id) 的 provenance 为 unknown，不能保存"
        case .missingCommand(let id):
            return "MCP server \(id) 缺少 stdio command"
        case .invalidCommandPath(let id):
            return "MCP server \(id) 的 command 必须是允许的绝对路径"
        case .unconfirmedRunner(let id, let command):
            return "MCP server \(id) 使用 runner \(command)，需要先完成 typed confirmation"
        case .unsupportedTransport(let id, let transport):
            return "MCP server \(id) 暂不支持 transport：\(transport.rawValue)"
        case .invalidRemoteURL(let id):
            return "MCP server \(id) 的远程 URL 暂不支持"
        }
    }
}
