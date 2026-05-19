import XCTest
@testable import SliceCore

final class MCPDescriptorTests: XCTestCase {

    /// stdio descriptor 的 Codable round-trip 必须逐字段保持一致，不能依赖 id-only Equatable。
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

        XCTAssertEqual(decoded.id, d.id)
        XCTAssertEqual(decoded.transport, d.transport)
        XCTAssertEqual(decoded.command, d.command)
        XCTAssertEqual(decoded.args, d.args)
        XCTAssertEqual(decoded.url, d.url)
        XCTAssertEqual(decoded.env, d.env)
        XCTAssertEqual(decoded.capabilities, d.capabilities)
        XCTAssertEqual(decoded.provenance, d.provenance)
    }

    /// SSE descriptor 的 Codable round-trip 必须逐字段保持一致，不能依赖 id-only Equatable。
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

        XCTAssertEqual(decoded.id, d.id)
        XCTAssertEqual(decoded.transport, d.transport)
        XCTAssertEqual(decoded.command, d.command)
        XCTAssertEqual(decoded.args, d.args)
        XCTAssertEqual(decoded.url, d.url)
        XCTAssertEqual(decoded.env, d.env)
        XCTAssertEqual(decoded.capabilities, d.capabilities)
        XCTAssertEqual(decoded.provenance, d.provenance)
    }

    /// 验证 streamable HTTP transport 使用 MCP 约定的 kebab-case wire value。
    func test_mcpTransport_streamableHTTP_decodesAndEncodes() throws {
        let data = Data(#""streamable-http""#.utf8)

        let transport = try JSONDecoder().decode(MCPTransport.self, from: data)
        let encoded = try JSONEncoder().encode(transport)
        let json = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertEqual(transport, .streamableHTTP)
        XCTAssertEqual(json, #""streamable-http""#)
        XCTAssertTrue(transport.isCreatableInPhase1Settings)
    }

    /// 验证 websocket 可解码历史配置，但 Phase 1 设置页不能新建。
    func test_mcpTransport_websocket_decodesButIsNotCreatableInSettings() throws {
        let data = Data(#""websocket""#.utf8)

        let transport = try JSONDecoder().decode(MCPTransport.self, from: data)

        XCTAssertEqual(transport, .websocket)
        XCTAssertFalse(transport.isCreatableInPhase1Settings)
    }

    /// 旧 HTTP+SSE 只保留解码兼容，Phase 1 设置页不能新建。
    func test_mcpTransport_sse_decodesButIsNotCreatableInSettings() throws {
        let data = Data(#""sse""#.utf8)

        let transport = try JSONDecoder().decode(MCPTransport.self, from: data)

        XCTAssertEqual(transport, .sse)
        XCTAssertFalse(transport.isCreatableInPhase1Settings)
    }

    func test_mcpToolRef_hashable_forSet() {
        let a = MCPToolRef(server: "s", tool: "t")
        let b = MCPToolRef(server: "s", tool: "t")
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    /// MCPDescriptor 的身份语义只看稳定本地注册 ID；配置内容变化不应影响字典命中。
    func test_mcpDescriptor_identityUsesStableIDForEqualityAndHashing() throws {
        let original = MCPDescriptor(
            id: "brave",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-brave-search"],
            url: nil,
            env: nil,
            capabilities: [.tools(["brave_web_search"])],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))
        )
        let updated = MCPDescriptor(
            id: "brave",
            transport: .sse,
            command: nil,
            args: nil,
            url: try XCTUnwrap(URL(string: "https://mcp.example.com/events")),
            env: ["BRAVE_API_KEY": "redacted-in-test"],
            capabilities: [.tools(["brave_web_search", "brave_news_search"]), .resources(["search://history"])],
            provenance: .firstParty
        )
        let toolsByDescriptor = [original: ["brave_web_search"]]

        XCTAssertEqual(original, updated)
        XCTAssertEqual(toolsByDescriptor[updated], ["brave_web_search"])
    }

    func test_mcpCapability_tools_codable() throws {
        let cap = MCPCapability.tools(["a", "b"])
        let data = try JSONEncoder().encode(cap)
        let decoded = try JSONDecoder().decode(MCPCapability.self, from: data)
        XCTAssertEqual(cap, decoded)
    }

    // MARK: - Decoder negative tests（canonical 单键 + 未知键拒绝；Task 3/8/10/11 同款纪律）

    func test_mcpCapability_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MCPCapability.self, from: data))
    }

    func test_mcpCapability_decode_unknownKey_throws() {
        let data = Data(#"{"bogus":["x"]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MCPCapability.self, from: data))
    }

    func test_mcpCapability_decode_twoKeys_throws() {
        let data = Data(#"{"tools":["a"],"resources":["b"]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(MCPCapability.self, from: data))
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

    func test_mcpCapability_goldenJSON_prompts_directArray() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(MCPCapability.prompts(["summarize", "rewrite"])), encoding: .utf8))
        XCTAssertEqual(json, #"{"prompts":["summarize","rewrite"]}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_mcpDescriptor_goldenJSON_sseMinimal() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let d = MCPDescriptor(
            id: "remote",
            transport: .sse,
            command: nil,
            args: nil,
            url: URL(string: "https://mcp.example.com/events"),
            env: nil,
            capabilities: [],
            provenance: .firstParty
        )
        let json = try XCTUnwrap(String(data: try enc.encode(d), encoding: .utf8))
        // 检查所有 nil 可选字段被省略（Foundation 默认行为）
        XCTAssertFalse(json.contains("\"command\""))
        XCTAssertFalse(json.contains("\"args\""))
        XCTAssertFalse(json.contains("\"env\""))
        // 检查必要字段在场
        XCTAssertTrue(json.contains(#""id":"remote""#))
        XCTAssertTrue(json.contains(#""transport":"sse""#))
        XCTAssertTrue(json.contains(#""url":"https:\/\/mcp.example.com\/events""#))
        XCTAssertTrue(json.contains(#""capabilities":[]"#))
        XCTAssertTrue(json.contains(#""provenance":{"firstParty":{}}"#))
    }
}
