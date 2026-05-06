import XCTest
@testable import SliceCore

final class MCPJSONValueTests: XCTestCase {

    /// 验证嵌套 JSON object 能以值类型形式完整往返。
    func test_mcpJSONValue_roundTrips_nestedObject() throws {
        let value: MCPJSONValue = .object([
            "q": .string("hi"),
            "n": .number(3),
            "nested": .object(["ok": .bool(true)]),
            "items": .array([.null, .string("x")])
        ])

        let data = try JSONEncoder().encode(value)
        let decoded = try JSONDecoder().decode(MCPJSONValue.self, from: data)

        XCTAssertEqual(decoded, value)
    }

    /// 验证 Codable 使用透明 raw JSON 形状，不出现 Swift enum wrapper。
    func test_mcpJSONValue_codableUsesTransparentRawJSONShape() throws {
        let raw = Data(#"{"q":"hi","n":3,"nested":{"ok":true},"items":[null,"x"]}"#.utf8)

        XCTAssertEqual(
            try JSONDecoder().decode(MCPJSONValue.self, from: raw),
            .object([
                "q": .string("hi"),
                "n": .number(3),
                "nested": .object(["ok": .bool(true)]),
                "items": .array([.null, .string("x")])
            ])
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let encoded = try XCTUnwrap(String(data: try encoder.encode(MCPJSONValue.object([
            "q": .string("hi"),
            "n": .number(3)
        ])), encoding: .utf8))

        XCTAssertEqual(encoded, #"{"n":3,"q":"hi"}"#)
        XCTAssertFalse(encoded.contains("\"string\""))
        XCTAssertFalse(encoded.contains("\"object\""))
        XCTAssertFalse(encoded.contains("\"_0\""))
    }

    /// 验证变量渲染只作用于字符串叶子，其他 JSON 形状不变。
    func test_mcpJSONValue_rendersStringLeavesWithoutChangingShape() {
        let value: MCPJSONValue = .object([
            "query": .string("{{selection}}"),
            "limit": .number(3),
            "filters": .object(["safe": .bool(true)])
        ])

        let rendered = value.renderingStringLeaves(variables: ["selection": "Swift MCP"])

        XCTAssertEqual(rendered, .object([
            "query": .string("Swift MCP"),
            "limit": .number(3),
            "filters": .object(["safe": .bool(true)])
        ]))
    }

    /// 验证日志摘要会隐藏 secret-like key，且不会超过调用方指定长度。
    func test_mcpJSONValue_redactedSummary_redactsSecretKeys() {
        let value: MCPJSONValue = .object([
            "apiKey": .string("sk-live-secret"),
            "authorization": .string("Bearer token"),
            "query": .string("hello")
        ])

        let summary = value.redactedSummary(maxCharacters: 80)

        XCTAssertLessThanOrEqual(summary.count, 80)
        XCTAssertTrue(summary.contains("<redacted>"), summary)
        XCTAssertTrue(summary.contains("query"), summary)
        XCTAssertFalse(summary.contains("sk-live-secret"), summary)
        XCTAssertFalse(summary.contains("Bearer token"), summary)
    }
}
