import Foundation
import SliceCore
import XCTest
@testable import Capabilities

/// Claude Desktop `mcpServers` 导入测试。
final class ClaudeDesktopMCPImporterTests: XCTestCase {

    /// Claude Desktop stdio 配置应导入为 canonical MCPDescriptor，并使用调用方传入 provenance。
    func test_importer_acceptsClaudeDesktopStdioConfig() throws {
        let data = Data(#"""
        {
          "mcpServers": {
            "filesystem": {
              "command": "npx",
              "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Documents"]
            }
          }
        }
        """#.utf8)
        let provenance = Provenance.selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))

        let descriptors = try ClaudeDesktopMCPImporter().importDescriptors(
            from: data,
            provenance: provenance
        )

        XCTAssertEqual(descriptors.count, 1)
        XCTAssertEqual(descriptors.first?.id, "filesystem")
        XCTAssertEqual(descriptors.first?.transport, .stdio)
        XCTAssertEqual(descriptors.first?.command, "npx")
        XCTAssertEqual(
            descriptors.first?.args,
            ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Documents"]
        )
        XCTAssertNil(descriptors.first?.url)
        XCTAssertNil(descriptors.first?.env)
        XCTAssertEqual(descriptors.first?.capabilities, [MCPCapability]())
        XCTAssertEqual(descriptors.first?.provenance, provenance)
    }

    /// M1 只导入本地 stdio；Claude Desktop 远程 URL 配置必须等 M4 再开放。
    func test_importer_rejectsRemoteURLBeforeM4() throws {
        let data = Data(#"""
        {
          "mcpServers": {
            "remote": {
              "url": "https://mcp.example.com/sse"
            }
          }
        }
        """#.utf8)

        XCTAssertThrowsError(try ClaudeDesktopMCPImporter().importDescriptors(
            from: data,
            provenance: Provenance.selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))
        )) { error in
            XCTAssertEqual(error as? MCPServerValidationError, .invalidRemoteURL(id: "remote"))
        }
    }
}
