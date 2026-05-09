import Foundation
import SliceCore

/// MCP server 配置校验错误。
///
/// 错误 case 保持 Equatable，方便 store / importer 测试直接断言 fail-closed 原因。
public enum MCPServerValidationError: Error, Sendable, Equatable {
    /// 当前代码不支持该 mcp.json schema version。
    case unsupportedSchemaVersion(version: Int)
    /// 同一个配置文件里出现重复 server id。
    case duplicateServerID(id: String)
    /// MCPDescriptor 不允许未知来源写入 store。
    case unknownProvenance(id: String)
    /// stdio transport 缺少 command。
    case missingCommand(id: String)
    /// stdio command 是相对路径、未知 bare command、wrapper command，或包含父目录跳转；错误不回显用户路径。
    case invalidCommandPath(id: String)
    /// allowlisted runner 缺少首次 typed confirmation。
    case unconfirmedRunner(id: String, command: String)
    /// 当前 milestone 不支持写入的 transport。
    case unsupportedTransport(id: String, transport: MCPTransport)
    /// transport URL 缺失、scheme 不合规，或明文 HTTP 指向非本机 host。
    case invalidRemoteURL(id: String)
}

/// MCP server store / importer 的 fail-closed 校验入口。
public enum MCPServerValidation {

    private static let allowlistedRunners = Set(["npx", "uvx", "node", "python", "python3"])
    private static let blockedWrapperBasenames = Set(["env", "sh", "bash", "zsh", "fish", "dash"])

    /// 校验整个 MCP server 配置。
    /// - Parameter configuration: 待写入或读取的 `mcp.json` 配置对象。
    /// - Throws: 首个违反 fail-closed 规则的 `MCPServerValidationError`。
    public static func validate(_ configuration: MCPServerConfiguration) throws {
        guard configuration.schemaVersion == MCPServerStore.currentSchemaVersion else {
            throw MCPServerValidationError.unsupportedSchemaVersion(version: configuration.schemaVersion)
        }

        var seenIDs = Set<String>()
        for descriptor in configuration.servers {
            guard seenIDs.insert(descriptor.id).inserted else {
                throw MCPServerValidationError.duplicateServerID(id: descriptor.id)
            }
            try validate(descriptor, runnerConfirmations: configuration.runnerConfirmations)
        }
    }

    /// 校验单个 MCPDescriptor。
    /// - Parameters:
    ///   - descriptor: 待校验的 server descriptor。
    ///   - runnerConfirmations: 用户对 allowlisted runner 的 typed confirmation 列表。
    /// - Throws: 首个违反 fail-closed 规则的 `MCPServerValidationError`。
    public static func validate(
        _ descriptor: MCPDescriptor,
        runnerConfirmations: [RunnerConfirmation]
    ) throws {
        try validateKnownProvenance(descriptor.provenance, id: descriptor.id)

        switch descriptor.transport {
        case .stdio:
            try validateStdio(descriptor, runnerConfirmations: runnerConfirmations)
        case .streamableHTTP:
            try validateStreamableHTTP(descriptor)
        case .sse, .websocket:
            // deprecated SSE 与 websocket 仍不在当前 milestone 支持范围内。
            throw MCPServerValidationError.unsupportedTransport(
                id: descriptor.id,
                transport: descriptor.transport
            )
        }
    }

    /// 校验 provenance 是否为已知来源。
    /// - Parameters:
    ///   - provenance: 待校验的来源。
    ///   - id: 用于错误定位的 server id。
    /// - Throws: `.unknownProvenance`。
    static func validateKnownProvenance(_ provenance: Provenance, id: String) throws {
        if case .unknown = provenance {
            throw MCPServerValidationError.unknownProvenance(id: id)
        }
    }

    /// 校验 stdio descriptor 的 command / url / runner confirmation。
    /// - Parameters:
    ///   - descriptor: transport 为 `.stdio` 的 descriptor。
    ///   - runnerConfirmations: 用户 typed confirmation 列表。
    /// - Throws: stdio 相关 fail-closed 错误。
    private static func validateStdio(
        _ descriptor: MCPDescriptor,
        runnerConfirmations: [RunnerConfirmation]
    ) throws {
        if descriptor.url != nil {
            throw MCPServerValidationError.invalidRemoteURL(id: descriptor.id)
        }

        guard let rawCommand = descriptor.command else {
            throw MCPServerValidationError.missingCommand(id: descriptor.id)
        }
        let command = rawCommand.trimmingCharacters(in: .whitespacesAndNewlines)
        guard command.isEmpty == false else {
            throw MCPServerValidationError.missingCommand(id: descriptor.id)
        }

        if allowlistedRunners.contains(command) {
            try validateRunnerConfirmation(
                id: descriptor.id,
                command: command,
                runnerConfirmations: runnerConfirmations
            )
            return
        }

        try validateAbsoluteCommandPath(id: descriptor.id, command: command)
        try validateNotWrapperCommand(id: descriptor.id, command: command)
        if let runnerCommand = allowlistedRunnerBasename(for: command) {
            try validateRunnerConfirmation(
                id: descriptor.id,
                command: runnerCommand,
                runnerConfirmations: runnerConfirmations
            )
        }
    }

    /// 校验 Streamable HTTP descriptor 的 URL 安全边界。
    /// - Parameter descriptor: transport 为 `.streamableHTTP` 的 descriptor。
    /// - Throws: `.invalidRemoteURL`。
    private static func validateStreamableHTTP(_ descriptor: MCPDescriptor) throws {
        guard let url = descriptor.url,
              let scheme = url.scheme?.lowercased(),
              let host = url.host,
              !host.isEmpty else {
            throw MCPServerValidationError.invalidRemoteURL(id: descriptor.id)
        }
        if scheme == "https" {
            return
        }
        if scheme == "http", isLocalHTTPHost(host) {
            return
        }
        throw MCPServerValidationError.invalidRemoteURL(id: descriptor.id)
    }

    /// 判断明文 HTTP host 是否限定在本机。
    /// - Parameter host: URL host。
    /// - Returns: localhost / 127.0.0.1 / ::1 返回 true。
    private static func isLocalHTTPHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    /// 拒绝会把真实 runner 藏进 args 的 wrapper command。
    /// - Parameters:
    ///   - id: server id。
    ///   - command: 已通过绝对路径校验的 command。
    /// - Throws: `.invalidCommandPath`。
    private static func validateNotWrapperCommand(id: String, command: String) throws {
        let basename = URL(fileURLWithPath: command).lastPathComponent.lowercased()
        guard blockedWrapperBasenames.contains(basename) == false else {
            throw MCPServerValidationError.invalidCommandPath(id: id)
        }
    }

    /// 从绝对 command path 提取 allowlisted runner basename。
    /// - Parameter command: 已通过绝对路径校验的 command。
    /// - Returns: 归一后的 `npx` / `uvx` / `node` / `python` / `python3` runner 名；非 runner path 返回 nil。
    private static func allowlistedRunnerBasename(for command: String) -> String? {
        let basename = URL(fileURLWithPath: command).lastPathComponent.lowercased()
        return canonicalRunnerName(forBasename: basename)
    }

    /// 将绝对路径 basename 归一到需要 typed confirmation 的 runner 家族。
    /// - Parameter basename: 已转为小写的 command basename。
    /// - Returns: 用于匹配 `RunnerConfirmation.command` 的规范 runner 名；不认识的 basename 返回 nil。
    private static func canonicalRunnerName(forBasename basename: String) -> String? {
        if basename == "npx" || basename == "uvx" {
            return basename
        }
        if basename == "node" || isVersionedNodeBasename(basename) {
            return "node"
        }
        if basename == "python" {
            return "python"
        }
        if basename == "python3" || isVersionedPython3Basename(basename) {
            return "python3"
        }
        return nil
    }

    /// 判断 basename 是否为常见的版本化 Node runner，例如 `node22`。
    /// - Parameter basename: 已转为小写的 command basename。
    /// - Returns: 若 basename 是 `node` 后接纯数字版本号则返回 true。
    private static func isVersionedNodeBasename(_ basename: String) -> Bool {
        let prefix = "node"
        guard basename.hasPrefix(prefix) else {
            return false
        }
        let suffix = basename.dropFirst(prefix.count)
        return containsOnlyDigits(suffix)
    }

    /// 判断 basename 是否为常见的版本化 Python 3 runner，例如 `python3.11`。
    /// - Parameter basename: 已转为小写的 command basename。
    /// - Returns: 若 basename 是 `python3.` 后接一段或多段纯数字版本号则返回 true。
    private static func isVersionedPython3Basename(_ basename: String) -> Bool {
        let prefix = "python3."
        guard basename.hasPrefix(prefix) else {
            return false
        }

        let suffix = basename.dropFirst(prefix.count)
        let components = suffix.split(separator: ".", omittingEmptySubsequences: false)
        guard components.isEmpty == false else {
            return false
        }
        return components.allSatisfy(containsOnlyDigits)
    }

    /// 判断字符串片段是否只包含十进制数字。
    /// - Parameter value: 待检查的字符串片段。
    /// - Returns: 非空且全部为十进制数字时返回 true。
    private static func containsOnlyDigits(_ value: Substring) -> Bool {
        guard value.isEmpty == false else {
            return false
        }
        return value.allSatisfy { character in
            character.unicodeScalars.allSatisfy { CharacterSet.decimalDigits.contains($0) }
        }
    }

    /// 校验 allowlisted runner 是否已有非空 typed confirmation。
    /// - Parameters:
    ///   - id: server id。
    ///   - command: runner command。
    ///   - runnerConfirmations: 用户 typed confirmation 列表。
    /// - Throws: `.unconfirmedRunner`。
    private static func validateRunnerConfirmation(
        id: String,
        command: String,
        runnerConfirmations: [RunnerConfirmation]
    ) throws {
        let hasConfirmation = runnerConfirmations.contains { confirmation in
            confirmation.command == command &&
                confirmation.confirmationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        }
        guard hasConfirmation else {
            throw MCPServerValidationError.unconfirmedRunner(id: id, command: command)
        }
    }

    /// 校验 stdio command 是否为不含父目录跳转的绝对路径。
    /// - Parameters:
    ///   - id: server id。
    ///   - command: command 字符串。
    /// - Throws: `.invalidCommandPath`。
    private static func validateAbsoluteCommandPath(id: String, command: String) throws {
        guard command.hasPrefix("/") else {
            throw MCPServerValidationError.invalidCommandPath(id: id)
        }

        // 绝对路径也拒绝 `..` 组件，避免 `/usr/../tmp/server` 这类路径绕过审查语义。
        let rawComponents = command.split(separator: "/", omittingEmptySubsequences: true)
        if rawComponents.contains("..") {
            throw MCPServerValidationError.invalidCommandPath(id: id)
        }

        let standardizedPath = URL(fileURLWithPath: command).standardizedFileURL.path
        let standardizedComponents = standardizedPath.split(separator: "/", omittingEmptySubsequences: true)
        if standardizedComponents.contains("..") {
            throw MCPServerValidationError.invalidCommandPath(id: id)
        }
    }
}
