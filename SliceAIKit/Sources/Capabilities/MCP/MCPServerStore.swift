import Foundation
import OSLog
import SliceCore

private let mcpServerStoreLog = Logger(subsystem: "com.sliceai.capabilities", category: "MCPServerStore")

/// 本地 `mcp.json` 配置文件结构。
public struct MCPServerConfiguration: Sendable, Codable, Equatable {
    /// 配置 schema 版本；M1 初始版本为 1。
    public var schemaVersion: Int
    /// MCP server descriptor 列表。
    public var servers: [MCPDescriptor]
    /// 对 allowlisted runner 的用户 typed confirmation。
    public var runnerConfirmations: [RunnerConfirmation]

    /// 构造 MCP server 配置。
    /// - Parameters:
    ///   - schemaVersion: 配置 schema 版本。
    ///   - servers: MCP server descriptor 列表。
    ///   - runnerConfirmations: runner typed confirmation 列表。
    public init(
        schemaVersion: Int,
        servers: [MCPDescriptor],
        runnerConfirmations: [RunnerConfirmation]
    ) {
        self.schemaVersion = schemaVersion
        self.servers = servers
        self.runnerConfirmations = runnerConfirmations
    }
}

/// 对 `npx` / `uvx` / `node` / `python` 等 runner 的首次 typed confirmation。
public struct RunnerConfirmation: Sendable, Codable, Equatable {
    /// runner command，例如 `npx`。
    public let command: String
    /// 用户确认时间。
    public let confirmedAt: Date
    /// 用户 typed confirmation 文本；非空才视为有效。
    public let confirmationText: String

    /// 构造 runner confirmation。
    /// - Parameters:
    ///   - command: runner command。
    ///   - confirmedAt: 用户确认时间。
    ///   - confirmationText: 用户 typed confirmation 文本。
    public init(command: String, confirmedAt: Date, confirmationText: String) {
        self.command = command
        self.confirmedAt = confirmedAt
        self.confirmationText = confirmationText
    }
}

/// MCP server 本地配置 store。
///
/// 默认路径：`~/Library/Application Support/SliceAI/mcp.json`。
public actor MCPServerStore {

    /// 当前 store schema version。
    public static let currentSchemaVersion = 1

    private let fileURL: URL

    /// 构造 MCP server store。
    /// - Parameter fileURL: 可选自定义路径；nil 时使用标准 Application Support 路径。
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.standardFileURL()
    }

    /// 读取本地 MCP server 配置；文件不存在时返回空配置。
    /// - Returns: 已通过 fail-closed 校验的配置对象。
    /// - Throws: JSON 读取 / 解码错误或 `MCPServerValidationError`。
    public func load() async throws -> MCPServerConfiguration {
        try loadSync()
    }

    /// 保存本地 MCP server 配置。
    /// - Parameter configuration: 待写入的配置对象。
    /// - Throws: `MCPServerValidationError` 或文件写入错误。
    public func save(_ configuration: MCPServerConfiguration) async throws {
        try saveSync(configuration)
    }

    /// 在 store actor 内原子更新 MCP server 配置。
    ///
    /// `load -> mutate -> validate -> save` 全部发生在同一个 actor 方法内，且中间没有 `await`，
    /// 避免 SettingsUI 多个并发操作各自读取旧快照后互相覆盖。
    /// - Parameter mutate: 对配置的同步原地修改闭包。
    /// - Returns: 已写入磁盘的最新配置。
    /// - Throws: 读取、闭包校验、保存或 `MCPServerValidationError`。
    public func update(
        _ mutate: @Sendable (inout MCPServerConfiguration) throws -> Void
    ) async throws -> MCPServerConfiguration {
        var configuration = try loadSync()
        try mutate(&configuration)
        try saveSync(configuration)
        return configuration
    }

    /// 返回 runtime wiring 使用的 descriptor 快照。
    /// - Returns: 已校验且按 `id` 排序的 MCP descriptor 列表。
    /// - Throws: `load()` 可能抛出的读取 / 解码 / 校验错误。
    public func snapshot() async throws -> [MCPDescriptor] {
        let configuration = try loadSync()
        return configuration.servers.sorted { lhs, rhs in
            lhs.id < rhs.id
        }
    }

    /// 同步读取本地 MCP server 配置；仅供 actor 内部 public API 复用。
    /// - Returns: 已通过 fail-closed 校验的配置对象。
    /// - Throws: JSON 读取 / 解码错误或 `MCPServerValidationError`。
    private func loadSync() throws -> MCPServerConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            mcpServerStoreLog.debug("mcp.json missing, returning empty configuration")
            return MCPServerConfiguration(
                schemaVersion: Self.currentSchemaVersion,
                servers: [],
                runnerConfirmations: []
            )
        }

        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(MCPServerConfiguration.self, from: data)
        try MCPServerValidation.validate(configuration)
        mcpServerStoreLog.debug(
            "loaded mcp.json servers=\(configuration.servers.count, privacy: .public)"
        )
        return configuration
    }

    /// 同步保存本地 MCP server 配置；仅供 actor 内部 public API 复用。
    /// - Parameter configuration: 待写入的配置对象。
    /// - Throws: `MCPServerValidationError` 或文件写入错误。
    private func saveSync(_ configuration: MCPServerConfiguration) throws {
        try MCPServerValidation.validate(configuration)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        mcpServerStoreLog.debug(
            "saved mcp.json bytes=\(data.count, privacy: .public) servers=\(configuration.servers.count, privacy: .public)"
        )
    }

    /// 标准 `mcp.json` 路径。
    /// - Returns: `~/Library/Application Support/SliceAI/mcp.json`。
    public static func standardFileURL() -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("mcp.json")
    }
}
