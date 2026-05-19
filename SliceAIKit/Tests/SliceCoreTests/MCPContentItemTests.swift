import XCTest
@testable import SliceCore

final class MCPContentItemTests: XCTestCase {

    /// 验证 MCP content item 与 structuredContent 使用 MCP wire shape 往返。
    func test_mcpContentItem_roundTrips_textAndStructuredContent() throws {
        let result = MCPCallResult(
            content: [
                .text("done"),
                .image(data: "base64", mimeType: "image/png"),
                .resourceLink(uri: "file:///tmp/a.md", name: "a.md", mimeType: "text/markdown"),
                .embeddedResource(uri: "file:///tmp/b.txt", text: "hello", blob: nil, mimeType: "text/plain")
            ],
            structuredContent: .object([
                "ok": .bool(true),
                "count": .number(3)
            ]),
            isError: false,
            meta: ["requestId": .string("abc")]
        )

        let data = try JSONEncoder().encode(result)
        let decoded = try JSONDecoder().decode(MCPCallResult.self, from: data)

        XCTAssertEqual(decoded, result)
    }

    /// 验证 MCPCallResult 使用 MCP Result 的 `_meta` wire key，而不是 Swift 属性名 `meta`。
    func test_mcpCallResult_goldenJSON_metaUsesUnderscoreKey() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let result = MCPCallResult(
            content: [],
            structuredContent: nil,
            isError: false,
            meta: ["requestId": .string("abc")]
        )

        let json = try XCTUnwrap(String(data: try encoder.encode(result), encoding: .utf8))

        XCTAssertEqual(json, #"{"_meta":{"requestId":"abc"},"content":[],"isError":false}"#)
        XCTAssertFalse(json.contains(#""meta""#), "MCP wire key must be _meta, got: \(json)")
    }

    /// 验证 MCP wire `_meta` 能解码回 Swift 的 `meta` 属性。
    func test_mcpCallResult_decodesUnderscoreMetaWireKey() throws {
        let data = Data(#"{"content":[{"type":"text","text":"ok"}],"structuredContent":{"ok":true},"isError":false,"_meta":{"trace":"123"}}"#.utf8)

        let decoded = try JSONDecoder().decode(MCPCallResult.self, from: data)

        XCTAssertEqual(decoded, MCPCallResult(
            content: [.text("ok")],
            structuredContent: .object(["ok": .bool(true)]),
            isError: false,
            meta: ["trace": .string("123")]
        ))
    }

    /// 验证 text content item 的 JSON discriminator 与字段名符合 MCP 风格。
    func test_mcpContentItem_goldenJSON_text() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let json = try XCTUnwrap(String(data: try encoder.encode(MCPContentItem.text("hello")), encoding: .utf8))

        XCTAssertEqual(json, #"{"text":"hello","type":"text"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    /// 验证 resource_link 编码包含 MCP wire required 的 name 字段。
    func test_mcpContentItem_goldenJSON_resourceLink_requiresNameOnWire() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let item = MCPContentItem.resourceLink(
            uri: "file:///project/src/main.rs",
            name: "main.rs",
            mimeType: "text/x-rust"
        )
        let json = try XCTUnwrap(String(data: try encoder.encode(item), encoding: .utf8))

        XCTAssertEqual(json, #"{"mimeType":"text\/x-rust","name":"main.rs","type":"resource_link","uri":"file:\/\/\/project\/src\/main.rs"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    /// 验证 wire JSON 缺少 resource_link.name 时必须解码失败。
    func test_mcpContentItem_resourceLinkDecodeWithoutName_throws() {
        let data = Data(#"{"type":"resource_link","uri":"file:///project/src/main.rs"}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MCPContentItem.self, from: data))
    }

    /// 验证 public optional name 为 nil 时不会编码出非法 MCP resource_link。
    func test_mcpContentItem_resourceLinkEncodeWithoutName_throws() {
        let item = MCPContentItem.resourceLink(uri: "file:///project/src/main.rs", name: nil, mimeType: nil)

        XCTAssertThrowsError(try JSONEncoder().encode(item))
    }

    /// 验证 embedded text resource 使用 MCP 2025-06-18 的嵌套 resource wire shape。
    func test_mcpContentItem_goldenJSON_embeddedTextResource_nestedResource() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let item = MCPContentItem.embeddedResource(
            uri: "file:///tmp/a.md",
            text: "hello",
            blob: nil,
            mimeType: "text/markdown"
        )
        let json = try XCTUnwrap(String(data: try encoder.encode(item), encoding: .utf8))

        XCTAssertEqual(json, #"{"resource":{"mimeType":"text\/markdown","text":"hello","uri":"file:\/\/\/tmp\/a.md"},"type":"resource"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    /// 验证 embedded blob resource 使用 MCP 2025-06-18 的嵌套 resource wire shape。
    func test_mcpContentItem_goldenJSON_embeddedBlobResource_nestedResource() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let item = MCPContentItem.embeddedResource(
            uri: "file:///tmp/a.bin",
            text: nil,
            blob: "base64",
            mimeType: "application/octet-stream"
        )
        let json = try XCTUnwrap(String(data: try encoder.encode(item), encoding: .utf8))

        XCTAssertEqual(json, #"{"resource":{"blob":"base64","mimeType":"application\/octet-stream","uri":"file:\/\/\/tmp\/a.bin"},"type":"resource"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    /// 验证嵌套 text resource wire JSON 可解码为既有 public value case。
    func test_mcpContentItem_embeddedTextResourceNestedWire_decodes() throws {
        let data = Data(#"{"type":"resource","resource":{"uri":"file:///tmp/a.md","text":"hello","mimeType":"text/markdown"}}"#.utf8)

        let decoded = try JSONDecoder().decode(MCPContentItem.self, from: data)

        XCTAssertEqual(decoded, .embeddedResource(
            uri: "file:///tmp/a.md",
            text: "hello",
            blob: nil,
            mimeType: "text/markdown"
        ))
    }

    /// 验证嵌套 blob resource wire JSON 可解码为既有 public value case。
    func test_mcpContentItem_embeddedBlobResourceNestedWire_decodes() throws {
        let data = Data(#"{"type":"resource","resource":{"uri":"file:///tmp/a.bin","blob":"base64","mimeType":"application/octet-stream"}}"#.utf8)

        let decoded = try JSONDecoder().decode(MCPContentItem.self, from: data)

        XCTAssertEqual(decoded, .embeddedResource(
            uri: "file:///tmp/a.bin",
            text: nil,
            blob: "base64",
            mimeType: "application/octet-stream"
        ))
    }

    /// 验证 nested resource 缺 text/blob 时必须解码失败，避免违反 MCP resource union。
    func test_mcpContentItem_embeddedResourceDecodeWithoutTextOrBlob_throws() {
        let data = Data(#"{"type":"resource","resource":{"uri":"file:///tmp/empty","mimeType":"text/plain"}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MCPContentItem.self, from: data))
    }

    /// 验证 nested resource 同时含 text/blob 时必须解码失败，避免 union 两分支混合。
    func test_mcpContentItem_embeddedResourceDecodeWithTextAndBlob_throws() {
        let data = Data(#"{"type":"resource","resource":{"uri":"file:///tmp/mixed","text":"hello","blob":"base64"}}"#.utf8)

        XCTAssertThrowsError(try JSONDecoder().decode(MCPContentItem.self, from: data))
    }

    /// 验证 embeddedResource 缺 text/blob 时不会编码出非法 MCP resource。
    func test_mcpContentItem_embeddedResourceEncodeWithoutTextOrBlob_throws() {
        let item = MCPContentItem.embeddedResource(
            uri: "file:///tmp/empty",
            text: nil,
            blob: nil,
            mimeType: "text/plain"
        )

        XCTAssertThrowsError(try JSONEncoder().encode(item))
    }

    /// 验证 embeddedResource 同时含 text/blob 时不会编码出非法 MCP resource。
    func test_mcpContentItem_embeddedResourceEncodeWithTextAndBlob_throws() {
        let item = MCPContentItem.embeddedResource(
            uri: "file:///tmp/mixed",
            text: "hello",
            blob: "base64",
            mimeType: nil
        )

        XCTAssertThrowsError(try JSONEncoder().encode(item))
    }
}
