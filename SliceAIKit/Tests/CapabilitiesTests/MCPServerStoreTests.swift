import Foundation
import SliceCore
import XCTest
@testable import Capabilities

/// MCP server 本地配置 store 与 fail-closed 校验测试。
final class MCPServerStoreTests: XCTestCase {

    /// store 应能保存 / 读取 canonical mcp.json，并让 snapshot 返回按 id 排序的已校验 descriptor。
    func test_store_roundTrips_mcpJSON() async throws {
        let fileURL = try makeTemporaryFileURL()
        let store = MCPServerStore(fileURL: fileURL)
        let acknowledgedAt = Date(timeIntervalSince1970: 1)
        let confirmedAt = Date(timeIntervalSince1970: 2)
        let configuration = MCPServerConfiguration(
            schemaVersion: 1,
            servers: [
                descriptor(
                    id: "z-files",
                    command: "/usr/local/bin/mcp-files",
                    args: ["--root", "/Users/me/Documents"],
                    env: ["SLICEAI_TEST": "1"],
                    acknowledgedAt: acknowledgedAt
                ),
                descriptor(
                    id: "a-npx",
                    command: "npx",
                    args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Documents"],
                    env: nil,
                    acknowledgedAt: acknowledgedAt
                ),
            ],
            runnerConfirmations: [
                RunnerConfirmation(
                    command: "npx",
                    confirmedAt: confirmedAt,
                    confirmationText: "我确认 npx 会以当前用户身份执行本地 MCP server"
                ),
            ]
        )

        try await store.save(configuration)
        let loaded = try await store.load()
        let snapshot = try await store.snapshot()

        XCTAssertEqual(loaded.schemaVersion, 1)
        XCTAssertEqual(loaded.servers.count, 2)
        assertDescriptor(
            loaded.servers[0],
            id: "z-files",
            command: "/usr/local/bin/mcp-files",
            args: ["--root", "/Users/me/Documents"],
            env: ["SLICEAI_TEST": "1"],
            acknowledgedAt: acknowledgedAt
        )
        assertDescriptor(
            loaded.servers[1],
            id: "a-npx",
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Documents"],
            env: nil,
            acknowledgedAt: acknowledgedAt
        )
        XCTAssertEqual(loaded.runnerConfirmations, configuration.runnerConfirmations)
        XCTAssertEqual(snapshot.map(\.id), ["a-npx", "z-files"])
    }

    /// `.unknown` provenance 必须 fail closed，避免未审查来源写入本地 MCP server 配置。
    func test_store_rejectsUnknownProvenance() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let configuration = MCPServerConfiguration(
            schemaVersion: 1,
            servers: [
                MCPDescriptor(
                    id: "unknown-source",
                    transport: .stdio,
                    command: "/usr/local/bin/server",
                    args: nil,
                    url: nil,
                    env: nil,
                    capabilities: [],
                    provenance: .unknown(
                        importedFrom: URL(string: "file:///tmp/mcp.json"),
                        importedAt: Date(timeIntervalSince1970: 1)
                    )
                ),
            ],
            runnerConfirmations: []
        )

        do {
            try await store.save(configuration)
            XCTFail("expected unknown provenance to be rejected")
        } catch let error as MCPServerValidationError {
            XCTAssertEqual(error, .unknownProvenance(id: "unknown-source"))
        } catch {
            XCTFail("expected MCPServerValidationError, got \(error)")
        }
    }

    /// 相对 command path 必须拒绝，避免把 cwd 变化变成执行路径变化。
    func test_store_rejectsRelativeCommandPath() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let configuration = MCPServerConfiguration(
            schemaVersion: 1,
            servers: [
                descriptor(
                    id: "relative-command",
                    command: "./server",
                    args: nil,
                    env: nil,
                    acknowledgedAt: Date(timeIntervalSince1970: 1)
                ),
            ],
            runnerConfirmations: []
        )

        do {
            try await store.save(configuration)
            XCTFail("expected relative command path to be rejected")
        } catch let error as MCPServerValidationError {
            XCTAssertEqual(
                error,
                .invalidCommandPath(id: "relative-command")
            )
        } catch {
            XCTFail("expected MCPServerValidationError, got \(error)")
        }
    }

    /// load 原始 JSON 时必须拒绝未来 schema，避免旧代码静默接受未知配置格式。
    func test_store_loadRejectsUnsupportedSchemaVersion() async throws {
        let fileURL = try makeTemporaryFileURL()
        let store = MCPServerStore(fileURL: fileURL)
        let data = Data(#"""
        {
          "schemaVersion": 999,
          "servers": [],
          "runnerConfirmations": []
        }
        """#.utf8)
        try data.write(to: fileURL, options: .atomic)

        do {
            _ = try await store.load()
            XCTFail("expected unsupported schema version to be rejected")
        } catch let error as MCPServerValidationError {
            XCTAssertEqual(error, .unsupportedSchemaVersion(version: 999))
        } catch {
            XCTFail("expected MCPServerValidationError, got \(error)")
        }
    }

    /// 同一个 mcp.json 里 server id 必须唯一，不能依赖 MCPDescriptor id-only Equatable 事后覆盖。
    func test_store_rejectsDuplicateServerID() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let configuration = MCPServerConfiguration(
            schemaVersion: 1,
            servers: [
                descriptor(
                    id: "dup",
                    command: "/usr/local/bin/server-a",
                    args: ["a"],
                    env: nil,
                    acknowledgedAt: Date(timeIntervalSince1970: 1)
                ),
                descriptor(
                    id: "dup",
                    command: "/usr/local/bin/server-b",
                    args: ["b"],
                    env: nil,
                    acknowledgedAt: Date(timeIntervalSince1970: 2)
                ),
            ],
            runnerConfirmations: []
        )

        do {
            try await store.save(configuration)
            XCTFail("expected duplicate server id to be rejected")
        } catch let error as MCPServerValidationError {
            XCTAssertEqual(error, .duplicateServerID(id: "dup"))
        } catch {
            XCTFail("expected MCPServerValidationError, got \(error)")
        }
    }

    /// update API 应在 actor 内原子完成 load / mutate / validate / save，避免并发写入丢更新。
    func test_updateAppliesConcurrentMutationsAtomically() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let serverIDs = (0..<12).map { "atomic-\($0)" }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for id in serverIDs {
                group.addTask {
                    try await store.update { configuration in
                        configuration.servers.append(Self.descriptor(
                            id: id,
                            command: "/opt/sliceai/bin/\(id)-mcp",
                            args: nil,
                            env: nil,
                            acknowledgedAt: Date(timeIntervalSince1970: 1)
                        ))
                    }
                }
            }
            try await group.waitForAll()
        }

        let loaded = try await store.load()
        XCTAssertEqual(Set(loaded.servers.map(\.id)), Set(serverIDs))
    }

    /// npx / uvx / node / python / python3 这类 runner 首次使用必须有 typed confirmation。
    func test_runnerConfirmationRequiredForNpxUvxNodePython() throws {
        let commands = ["npx", "uvx", "node", "python", "python3"]

        for command in commands {
            let server = descriptor(
                id: "runner-\(command)",
                command: command,
                args: ["server-package"],
                env: nil,
                acknowledgedAt: Date(timeIntervalSince1970: 1)
            )

            XCTAssertThrowsError(try MCPServerValidation.validate(server, runnerConfirmations: [])) { error in
                XCTAssertEqual(
                    error as? MCPServerValidationError,
                    .unconfirmedRunner(id: "runner-\(command)", command: command)
                )
            }

            let confirmation = RunnerConfirmation(
                command: command,
                confirmedAt: Date(timeIntervalSince1970: 2),
                confirmationText: "我确认 \(command) 会以当前用户身份执行 MCP server"
            )
            XCTAssertNoThrow(try MCPServerValidation.validate(server, runnerConfirmations: [confirmation]))
        }
    }

    /// 即使 runner 以绝对路径出现，也必须按 basename 识别并要求 typed confirmation。
    func test_runnerConfirmationRequiredForAbsoluteRunnerPaths() throws {
        let server = descriptor(
            id: "absolute-npx",
            command: "/usr/local/bin/npx",
            args: ["-y", "@modelcontextprotocol/server-filesystem"],
            env: nil,
            acknowledgedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertThrowsError(try MCPServerValidation.validate(server, runnerConfirmations: [])) { error in
            XCTAssertEqual(
                error as? MCPServerValidationError,
                .unconfirmedRunner(id: "absolute-npx", command: "npx")
            )
        }

        let confirmation = RunnerConfirmation(
            command: "npx",
            confirmedAt: Date(timeIntervalSince1970: 2),
            confirmationText: "我确认 npx 会以当前用户身份执行 MCP server"
        )
        XCTAssertNoThrow(try MCPServerValidation.validate(server, runnerConfirmations: [confirmation]))
    }

    /// 版本化或大小写不同的绝对 runner path 也必须归一到 runner 家族后要求 typed confirmation。
    func test_runnerConfirmationRequiredForVersionedRunnerPaths() throws {
        let pythonServer = descriptor(
            id: "python-versioned",
            command: "/opt/homebrew/bin/python3.11",
            args: ["server.py"],
            env: nil,
            acknowledgedAt: Date(timeIntervalSince1970: 1)
        )
        let nodeServer = descriptor(
            id: "node-versioned",
            command: "/usr/local/bin/Node22",
            args: ["server.js"],
            env: nil,
            acknowledgedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertThrowsError(try MCPServerValidation.validate(pythonServer, runnerConfirmations: [])) { error in
            XCTAssertEqual(
                error as? MCPServerValidationError,
                .unconfirmedRunner(id: "python-versioned", command: "python3")
            )
        }
        XCTAssertThrowsError(try MCPServerValidation.validate(nodeServer, runnerConfirmations: [])) { error in
            XCTAssertEqual(
                error as? MCPServerValidationError,
                .unconfirmedRunner(id: "node-versioned", command: "node")
            )
        }

        let confirmations = [
            RunnerConfirmation(
                command: "python3",
                confirmedAt: Date(timeIntervalSince1970: 2),
                confirmationText: "我确认 python3 会以当前用户身份执行 MCP server"
            ),
            RunnerConfirmation(
                command: "node",
                confirmedAt: Date(timeIntervalSince1970: 2),
                confirmationText: "我确认 node 会以当前用户身份执行 MCP server"
            )
        ]
        XCTAssertNoThrow(try MCPServerValidation.validate(pythonServer, runnerConfirmations: confirmations))
        XCTAssertNoThrow(try MCPServerValidation.validate(nodeServer, runnerConfirmations: confirmations))
    }

    /// env / shell wrapper 会隐藏真实 runner，M1 先整体拒绝以保持 fail-closed。
    func test_storeRejectsWrapperCommandsThatCanHideRunners() throws {
        let envServer = descriptor(
            id: "env-wrapper",
            command: "/usr/bin/env",
            args: ["npx", "-y", "@modelcontextprotocol/server-filesystem"],
            env: nil,
            acknowledgedAt: Date(timeIntervalSince1970: 1)
        )
        let shellServer = descriptor(
            id: "shell-wrapper",
            command: "/bin/sh",
            args: ["-c", "npx -y @modelcontextprotocol/server-filesystem"],
            env: nil,
            acknowledgedAt: Date(timeIntervalSince1970: 1)
        )

        XCTAssertThrowsError(try MCPServerValidation.validate(envServer, runnerConfirmations: [])) { error in
            XCTAssertEqual(error as? MCPServerValidationError, .invalidCommandPath(id: "env-wrapper"))
        }
        XCTAssertThrowsError(try MCPServerValidation.validate(shellServer, runnerConfirmations: [])) { error in
            XCTAssertEqual(error as? MCPServerValidationError, .invalidCommandPath(id: "shell-wrapper"))
        }
    }

    /// streamable HTTP descriptor 必须允许 HTTPS URL 写入 store，否则 Task 14 transport 无法从配置启用。
    func test_store_acceptsStreamableHTTPRemoteHTTPSURL() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let descriptor = streamableHTTPDescriptor(
            id: "remote-http",
            url: URL(string: "https://mcp.example.com/mcp")!
        )
        let configuration = MCPServerConfiguration(
            schemaVersion: 1,
            servers: [descriptor],
            runnerConfirmations: []
        )

        try await store.save(configuration)
        let snapshot = try await store.snapshot()

        XCTAssertEqual(snapshot, [descriptor])
    }

    /// 本机 localhost 明文 HTTP URL 可用于本地开发调试；非本机明文 HTTP 仍必须拒绝。
    func test_store_acceptsStreamableHTTPLocalPlainHTTPURL() throws {
        let urls = [
            URL(string: "http://localhost:8765/mcp")!,
            URL(string: "http://127.0.0.1:8765/mcp")!,
            URL(string: "http://[::1]:8765/mcp")!,
        ]

        for (index, url) in urls.enumerated() {
            let descriptor = streamableHTTPDescriptor(id: "local-http-\(index)", url: url)
            XCTAssertNoThrow(try MCPServerValidation.validate(descriptor, runnerConfirmations: []))
        }
    }

    /// streamable HTTP descriptor 缺少 URL 时必须 fail closed。
    func test_store_rejectsStreamableHTTPMissingURL() throws {
        let descriptor = streamableHTTPDescriptor(id: "missing-url", url: nil)

        XCTAssertThrowsError(try MCPServerValidation.validate(descriptor, runnerConfirmations: [])) { error in
            XCTAssertEqual(error as? MCPServerValidationError, .invalidRemoteURL(id: "missing-url"))
        }
    }

    /// streamable HTTP URL 即使用 HTTPS，也必须包含 host，避免 malformed URL 静默写入配置。
    func test_store_rejectsStreamableHTTPMissingHost() throws {
        let descriptor = streamableHTTPDescriptor(id: "missing-host", url: URL(string: "https:/mcp")!)

        XCTAssertThrowsError(try MCPServerValidation.validate(descriptor, runnerConfirmations: [])) { error in
            XCTAssertEqual(error as? MCPServerValidationError, .invalidRemoteURL(id: "missing-host"))
        }
    }

    /// 非 localhost 的明文 HTTP URL 必须拒绝，避免静默连接局域网或公网明文服务。
    func test_store_rejectsStreamableHTTPNonLocalPlainHTTPURL() throws {
        let descriptor = streamableHTTPDescriptor(
            id: "plain-remote",
            url: URL(string: "http://192.168.1.10:8765/mcp")!
        )

        XCTAssertThrowsError(try MCPServerValidation.validate(descriptor, runnerConfirmations: [])) { error in
            XCTAssertEqual(error as? MCPServerValidationError, .invalidRemoteURL(id: "plain-remote"))
        }
    }

    /// deprecated SSE descriptor 仍必须拒绝，不能被当成 streamable HTTP 兼容入口。
    func test_store_rejectsDeprecatedSSETransport() throws {
        let descriptor = MCPDescriptor(
            id: "deprecated-sse",
            transport: .sse,
            command: nil,
            args: nil,
            url: URL(string: "https://mcp.example.com/sse")!,
            env: nil,
            capabilities: [.tools(["list"])],
            provenance: .firstParty
        )

        XCTAssertThrowsError(try MCPServerValidation.validate(descriptor, runnerConfirmations: [])) { error in
            XCTAssertEqual(
                error as? MCPServerValidationError,
                .unsupportedTransport(id: "deprecated-sse", transport: .sse)
            )
        }
    }

    /// 构造临时 mcp.json 路径；每个测试独立目录避免并发测试互相污染。
    private func makeTemporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SliceAI-MCPServerStoreTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("mcp.json")
    }

    /// 构造 stdio descriptor fixture。
    private static func descriptor(
        id: String,
        command: String,
        args: [String]?,
        env: [String: String]?,
        acknowledgedAt: Date
    ) -> MCPDescriptor {
        MCPDescriptor(
            id: id,
            transport: .stdio,
            command: command,
            args: args,
            url: nil,
            env: env,
            capabilities: [.tools(["list"])],
            provenance: .selfManaged(userAcknowledgedAt: acknowledgedAt)
        )
    }

    /// 构造 stdio descriptor fixture。
    private func descriptor(
        id: String,
        command: String,
        args: [String]?,
        env: [String: String]?,
        acknowledgedAt: Date
    ) -> MCPDescriptor {
        Self.descriptor(
            id: id,
            command: command,
            args: args,
            env: env,
            acknowledgedAt: acknowledgedAt
        )
    }

    /// 构造 streamable HTTP descriptor fixture。
    private func streamableHTTPDescriptor(id: String, url: URL?) -> MCPDescriptor {
        MCPDescriptor(
            id: id,
            transport: .streamableHTTP,
            command: nil,
            args: nil,
            url: url,
            env: nil,
            capabilities: [.tools(["list"])],
            provenance: .firstParty
        )
    }

    /// 逐字段断言 descriptor，避免 `MCPDescriptor` id-only Equatable 掩盖 round-trip 问题。
    private func assertDescriptor(
        _ descriptor: MCPDescriptor,
        id: String,
        command: String,
        args: [String]?,
        env: [String: String]?,
        acknowledgedAt: Date
    ) {
        XCTAssertEqual(descriptor.id, id)
        XCTAssertEqual(descriptor.transport, .stdio)
        XCTAssertEqual(descriptor.command, command)
        XCTAssertEqual(descriptor.args, args)
        XCTAssertNil(descriptor.url)
        XCTAssertEqual(descriptor.env, env)
        XCTAssertEqual(descriptor.capabilities, [.tools(["list"])])
        XCTAssertEqual(descriptor.provenance, .selfManaged(userAcknowledgedAt: acknowledgedAt))
    }
}
