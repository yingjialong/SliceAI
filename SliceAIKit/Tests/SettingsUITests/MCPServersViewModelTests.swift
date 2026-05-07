import Capabilities
import Foundation
import SliceCore
@testable import SettingsUI
import XCTest

/// MCP Servers 设置页 ViewModel 行为测试。
@MainActor
final class MCPServersViewModelTests: XCTestCase {

    /// Claude Desktop JSON 导入后应更新内存列表，并持久化到注入的临时 `mcp.json`。
    func test_importClaudeDesktopConfig_addsServerAndPersists() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let viewModel = MCPServersViewModel(store: store, client: MockMCPClient())
        let data = Data(#"""
        {
          "mcpServers": {
            "filesystem": {
              "command": "/opt/sliceai/bin/filesystem-mcp",
              "args": ["--root", "/tmp"],
              "env": {
                "SLICEAI_MCP_TEST": "1"
              }
            }
          }
        }
        """#.utf8)

        await viewModel.importClaudeDesktopConfig(data)

        XCTAssertNil(viewModel.validationMessage)
        XCTAssertEqual(viewModel.servers.count, 1)
        let server = try XCTUnwrap(viewModel.servers.first)
        XCTAssertEqual(server.id, "filesystem")
        XCTAssertEqual(server.transport, .stdio)
        XCTAssertEqual(server.command, "/opt/sliceai/bin/filesystem-mcp")
        XCTAssertEqual(server.args, ["--root", "/tmp"])
        XCTAssertEqual(server.env, ["SLICEAI_MCP_TEST": "1"])
        assertSelfManaged(server.provenance)

        let loaded = try await store.load()
        XCTAssertEqual(loaded.servers.count, 1)
        XCTAssertEqual(loaded.servers.first?.id, "filesystem")
        XCTAssertEqual(loaded.servers.first?.command, "/opt/sliceai/bin/filesystem-mcp")
    }

    /// `.unknown` provenance 必须转为可展示的 validationMessage，不能崩溃或写入 store。
    func test_unknownProvenanceShowsValidationError() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let viewModel = MCPServersViewModel(store: store, client: MockMCPClient())
        let descriptor = descriptor(
            id: "unknown-source",
            provenance: .unknown(
                importedFrom: URL(string: "file:///tmp/mcp.json"),
                importedAt: Date(timeIntervalSince1970: 2)
            )
        )

        await viewModel.save(descriptor)

        XCTAssertTrue(viewModel.servers.isEmpty)
        XCTAssertTrue(viewModel.validationMessage?.contains("unknown") ?? false)
        let loaded = try await store.load()
        XCTAssertTrue(loaded.servers.isEmpty)
    }

    /// 测试连接应调用注入 MCP client 的 `tools(for:)`，并把返回工具保存到预览状态。
    func test_testConnectionCallsToolsList() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let server = descriptor(id: "filesystem")
        let tool = MCPToolDescriptor(
            ref: MCPToolRef(server: server.id, tool: "list"),
            title: "List Files",
            description: "列出测试目录",
            inputSchema: ["type": .string("object")]
        )
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [server],
            runnerConfirmations: []
        ))
        let client = MockMCPClient(tools: [server: [tool]])
        let viewModel = MCPServersViewModel(store: store, client: client)

        await viewModel.reload()
        await viewModel.testConnection(id: server.id)

        let lastToolsDescriptor = await client.lastToolsDescriptor
        XCTAssertEqual(lastToolsDescriptor, server)
        XCTAssertEqual(viewModel.toolsByServerID[server.id], [tool])
        XCTAssertNil(viewModel.validationMessage)
    }

    /// 删除 server 后应同步更新内存列表与临时 `mcp.json`。
    func test_deleteRemovesServerAndPersists() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let keep = descriptor(id: "keep")
        let removed = descriptor(id: "remove")
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [keep, removed],
            runnerConfirmations: []
        ))
        let viewModel = MCPServersViewModel(store: store, client: MockMCPClient())

        await viewModel.reload()
        await viewModel.delete(id: removed.id)

        XCTAssertEqual(viewModel.servers.map(\.id), ["keep"])
        let loaded = try await store.load()
        XCTAssertEqual(loaded.servers.map(\.id), ["keep"])
    }

    /// 并发 save / import / delete 不应互相覆盖独立更新。
    func test_concurrentSaveImportDeleteDoNotDropIndependentUpdates() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let deleted = descriptor(id: "delete-me")
        let saved = descriptor(id: "manual")
        let importData = Data(#"""
        {
          "mcpServers": {
            "imported": {
              "command": "/opt/sliceai/bin/imported-mcp"
            }
          }
        }
        """#.utf8)
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [deleted],
            runnerConfirmations: []
        ))
        let viewModel = MCPServersViewModel(store: store, client: MockMCPClient())

        async let saveTask: Void = viewModel.save(saved)
        async let importTask: Void = viewModel.importClaudeDesktopConfig(importData)
        async let deleteTask: Void = viewModel.delete(id: deleted.id)
        _ = await (saveTask, importTask, deleteTask)

        let loaded = try await store.load()
        let ids = Set(loaded.servers.map(\.id))
        XCTAssertFalse(ids.contains(deleted.id))
        XCTAssertTrue(ids.contains(saved.id))
        XCTAssertTrue(ids.contains("imported"))
    }

    /// replacing 保存应保留调用方传入的 metadata，并在改 ID 时删除旧 server。
    func test_saveReplacingOriginalID_preservesMetadataAndRemovesOldID() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let provenance = Provenance.communitySigned(
            publisher: "slice-test",
            signedAt: Date(timeIntervalSince1970: 3)
        )
        let original = descriptor(
            id: "old-id",
            capabilities: [.tools(["list"]), .resources(["files"])],
            provenance: provenance
        )
        let edited = descriptor(
            id: "new-id",
            command: "/opt/sliceai/bin/new-id-mcp",
            capabilities: original.capabilities,
            provenance: original.provenance
        )
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [original],
            runnerConfirmations: []
        ))
        let viewModel = MCPServersViewModel(store: store, client: MockMCPClient())

        await viewModel.reload()
        await viewModel.save(edited, replacing: original.id)

        XCTAssertNil(viewModel.validationMessage)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.servers.map(\.id), ["new-id"])
        XCTAssertEqual(loaded.servers.first?.capabilities, original.capabilities)
        XCTAssertEqual(loaded.servers.first?.provenance, provenance)
    }

    /// replacing 改成已有 id 时不能静默覆盖另一个 server。
    func test_saveReplacingOriginalID_rejectsDuplicateNewID() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let old = descriptor(id: "old")
        let existing = descriptor(id: "existing")
        let renamedToExisting = descriptor(id: existing.id, command: "/opt/sliceai/bin/renamed-mcp")
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [old, existing],
            runnerConfirmations: []
        ))
        let viewModel = MCPServersViewModel(store: store, client: MockMCPClient())

        await viewModel.reload()
        await viewModel.save(renamedToExisting, replacing: old.id)

        XCTAssertTrue(viewModel.validationMessage?.contains("重复") ?? false)
        let loaded = try await store.load()
        XCTAssertEqual(Set(loaded.servers.map(\.id)), ["old", "existing"])
    }

    /// 编辑草稿应携带 originalID，并在生成 descriptor 时保留原 capabilities / provenance。
    func test_editorDraftPreservesMetadataWhenIDChanges() throws {
        let provenance = Provenance.communitySigned(
            publisher: "slice-test",
            signedAt: Date(timeIntervalSince1970: 4)
        )
        let original = descriptor(
            id: "original",
            capabilities: [.tools(["list"]), .resources(["files"])],
            provenance: provenance
        )
        var draft = MCPServerDraft(descriptor: original)

        draft.id = "renamed"
        let descriptor = try XCTUnwrap(draft.makeDescriptor())

        XCTAssertEqual(draft.originalID, "original")
        XCTAssertEqual(descriptor.id, "renamed")
        XCTAssertEqual(descriptor.capabilities, original.capabilities)
        XCTAssertEqual(descriptor.provenance, provenance)
    }

    /// 保存同 id server 后，旧 tools/list 预览必须失效。
    func test_saveClearsToolsPreviewForChangedServer() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let server = descriptor(id: "filesystem")
        let tool = tool(serverID: server.id, name: "list")
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [server],
            runnerConfirmations: []
        ))
        let viewModel = MCPServersViewModel(
            store: store,
            client: MockMCPClient(tools: [server: [tool]])
        )

        await viewModel.reload()
        await viewModel.testConnection(id: server.id)
        XCTAssertEqual(viewModel.toolsByServerID[server.id], [tool])

        await viewModel.save(descriptor(id: server.id, command: "/opt/sliceai/bin/filesystem-v2-mcp"))

        XCTAssertNil(viewModel.toolsByServerID[server.id])
    }

    /// 测试连接失败时必须清理该 server 的旧 tools/list 预览。
    func test_testConnectionFailureClearsStaleToolsPreview() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let server = descriptor(id: "filesystem")
        let tool = tool(serverID: server.id, name: "list")
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [server],
            runnerConfirmations: []
        ))
        let client = ScriptedMCPClient(results: [
            .success([tool]),
            .failure(.transportFailed(reason: "offline")),
        ])
        let viewModel = MCPServersViewModel(store: store, client: client)

        await viewModel.reload()
        await viewModel.testConnection(id: server.id)
        XCTAssertEqual(viewModel.toolsByServerID[server.id], [tool])

        await viewModel.testConnection(id: server.id)

        XCTAssertNil(viewModel.toolsByServerID[server.id])
        XCTAssertNotNil(viewModel.validationMessage)
    }

    /// 导入同 id server 后，旧 tools/list 预览必须失效。
    func test_importClearsToolsPreviewForImportedServer() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let server = descriptor(id: "filesystem")
        let tool = tool(serverID: server.id, name: "list")
        let importData = Data(#"""
        {
          "mcpServers": {
            "filesystem": {
              "command": "/opt/sliceai/bin/filesystem-v2-mcp"
            }
          }
        }
        """#.utf8)
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [server],
            runnerConfirmations: []
        ))
        let viewModel = MCPServersViewModel(
            store: store,
            client: MockMCPClient(tools: [server: [tool]])
        )

        await viewModel.reload()
        await viewModel.testConnection(id: server.id)
        XCTAssertEqual(viewModel.toolsByServerID[server.id], [tool])

        await viewModel.importClaudeDesktopConfig(importData)

        XCTAssertNil(viewModel.toolsByServerID[server.id])
    }

    /// 导入失败时应保留现有 servers 并设置 validationMessage，供页面保持 sheet 输入。
    func test_importFailureKeepsServersAndSetsValidationMessage() async throws {
        let store = MCPServerStore(fileURL: try makeTemporaryFileURL())
        let server = descriptor(id: "filesystem")
        try await store.save(MCPServerConfiguration(
            schemaVersion: MCPServerStore.currentSchemaVersion,
            servers: [server],
            runnerConfirmations: []
        ))
        let viewModel = MCPServersViewModel(store: store, client: MockMCPClient())

        await viewModel.reload()
        await viewModel.importClaudeDesktopConfig(Data("not-json".utf8))

        XCTAssertEqual(viewModel.servers.map(\.id), [server.id])
        XCTAssertNotNil(viewModel.validationMessage)
        let loaded = try await store.load()
        XCTAssertEqual(loaded.servers.map(\.id), [server.id])
    }

    /// 构造临时 `mcp.json` 路径，避免测试之间共享状态。
    private func makeTemporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SliceAI-MCPServersViewModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("mcp.json")
    }

    /// 构造合法 stdio descriptor fixture。
    private func descriptor(
        id: String,
        command: String? = nil,
        capabilities: [MCPCapability] = [.tools(["list"])],
        provenance: Provenance = .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))
    ) -> MCPDescriptor {
        MCPDescriptor(
            id: id,
            transport: .stdio,
            command: command ?? "/opt/sliceai/bin/\(id)-mcp",
            args: ["--fixture"],
            url: nil,
            env: nil,
            capabilities: capabilities,
            provenance: provenance
        )
    }

    /// 构造 MCP tool fixture。
    private func tool(serverID: String, name: String) -> MCPToolDescriptor {
        MCPToolDescriptor(
            ref: MCPToolRef(server: serverID, tool: name),
            title: name,
            description: nil,
            inputSchema: ["type": .string("object")]
        )
    }

    /// 断言 provenance 为 selfManaged，不比较具体时间以避免把导入时间钉死。
    private func assertSelfManaged(
        _ provenance: Provenance,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        if case .selfManaged = provenance {
            return
        }
        XCTFail("expected selfManaged provenance, got \(provenance)", file: file, line: line)
    }
}

/// 可按脚本返回成功或失败的 MCP client。
private actor ScriptedMCPClient: MCPClientProtocol {

    /// `tools(for:)` 的脚本化结果队列。
    private var results: [Result<[MCPToolDescriptor], MCPClientError>]

    /// 构造脚本化 MCP client。
    /// - Parameter results: 按调用顺序返回的结果。
    init(results: [Result<[MCPToolDescriptor], MCPClientError>]) {
        self.results = results
    }

    /// 返回下一个脚本化 tools/list 结果。
    func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolDescriptor] {
        guard results.isEmpty == false else {
            return []
        }
        let result = results.removeFirst()
        switch result {
        case .success(let tools):
            return tools
        case .failure(let error):
            throw error
        }
    }

    /// 当前测试不覆盖 tool call。
    func call(ref: MCPToolRef, args: MCPJSONValue.Object) async throws -> MCPCallResult {
        throw MCPClientError.toolNotFound(ref: ref)
    }
}
