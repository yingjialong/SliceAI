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
        provenance: Provenance = .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))
    ) -> MCPDescriptor {
        MCPDescriptor(
            id: id,
            transport: .stdio,
            command: "/opt/sliceai/bin/\(id)-mcp",
            args: ["--fixture"],
            url: nil,
            env: nil,
            capabilities: [.tools(["list"])],
            provenance: provenance
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
