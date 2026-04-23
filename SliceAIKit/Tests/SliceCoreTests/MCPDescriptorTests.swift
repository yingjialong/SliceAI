import XCTest
@testable import SliceCore

final class MCPDescriptorTests: XCTestCase {

    func test_stdio_descriptor_codable() throws {
        let d = MCPDescriptor(
            id: "postgres",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost"],
            url: nil,
            env: ["PGUSER": "me"],
            capabilities: [.tools(["query", "schema"])],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 100))
        )
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(MCPDescriptor.self, from: data)
        XCTAssertEqual(d, decoded)
    }

    func test_sse_descriptor_codable() throws {
        let d = MCPDescriptor(
            id: "remote-mcp",
            transport: .sse,
            command: nil,
            args: nil,
            url: URL(string: "https://mcp.example.com/events"),
            env: nil,
            capabilities: [],
            provenance: .firstParty
        )
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(MCPDescriptor.self, from: data)
        XCTAssertEqual(d, decoded)
    }

    func test_mcpToolRef_hashable_forSet() {
        let a = MCPToolRef(server: "s", tool: "t")
        let b = MCPToolRef(server: "s", tool: "t")
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func test_mcpCapability_tools_codable() throws {
        let cap = MCPCapability.tools(["a", "b"])
        let data = try JSONEncoder().encode(cap)
        let decoded = try JSONDecoder().decode(MCPCapability.self, from: data)
        XCTAssertEqual(cap, decoded)
    }

    // MARK: - Golden JSON shape（模板 D）

    func test_mcpCapability_goldenJSON_tools_directArray() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(MCPCapability.tools(["query", "schema"])), encoding: .utf8))
        XCTAssertEqual(json, #"{"tools":["query","schema"]}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_mcpCapability_goldenJSON_resources_directArray() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(MCPCapability.resources(["/a", "/b"])), encoding: .utf8))
        XCTAssertEqual(json, #"{"resources":["\/a","\/b"]}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }
}
