import XCTest
@testable import SliceCore

final class ChatTypesTests: XCTestCase {
    func test_chatMessageEncoding_systemRole() throws {
        let msg = ChatMessage(role: .system, content: "You are helpful.")
        let data = try JSONEncoder().encode(msg)
        let s = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(s.contains("\"role\":\"system\""))
        XCTAssertTrue(s.contains("\"content\":\"You are helpful.\""))
    }

    func test_chatRequest_nilFieldsOmitted() throws {
        // temperature/maxTokens 为 nil 时必须不出现在 JSON 中，保持服务端默认
        let req = ChatRequest(model: "gpt-5", messages: [], temperature: nil, maxTokens: nil)
        let data = try JSONEncoder().encode(req)
        let s = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertFalse(s.contains("temperature"))
        XCTAssertFalse(s.contains("max_tokens"))
        XCTAssertTrue(s.contains("\"model\":\"gpt-5\""))
    }

    func test_chatRequest_nonNilFieldsPresent() throws {
        let req = ChatRequest(model: "gpt-5", messages: [], temperature: 0.5, maxTokens: 100)
        let data = try JSONEncoder().encode(req)
        let s = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(s.contains("\"temperature\":0.5"))
        XCTAssertTrue(s.contains("\"max_tokens\":100"))
    }

    func test_finishReason_rawValuesStable() {
        // rawValue 是线上协议兼容的基础，snake_case 映射必须稳定
        XCTAssertEqual(FinishReason.stop.rawValue, "stop")
        XCTAssertEqual(FinishReason.length.rawValue, "length")
        XCTAssertEqual(FinishReason.contentFilter.rawValue, "content_filter")
        XCTAssertEqual(FinishReason.toolCalls.rawValue, "tool_calls")
    }

    func test_chatTool_encodesOpenAISchema() throws {
        let tool = ChatTool(
            name: "brave_web_search",
            description: "Search the web",
            inputSchema: [
                "type": .string("object"),
                "properties": .object([
                    "q": .object(["type": .string("string")]),
                ]),
                "required": .array([.string("q")]),
            ]
        )

        let object = try encodeJSONObject(tool)
        XCTAssertEqual(object["type"] as? String, "function")

        let function = try XCTUnwrap(object["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "brave_web_search")
        XCTAssertEqual(function["description"] as? String, "Search the web")

        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["required"] as? [String], ["q"])
    }

    func test_chatToolRequest_encodesToolsAndToolChoice() throws {
        let request = ChatToolRequest(
            model: "gpt-5",
            messages: [ChatMessage(role: .user, content: "search this")],
            tools: [
                ChatTool(
                    name: "brave_web_search",
                    description: "Search the web",
                    inputSchema: ["type": .string("object")]
                ),
            ],
            toolChoice: .auto,
            temperature: 0.2,
            maxTokens: 200
        )

        let object = try encodeJSONObject(request)
        XCTAssertEqual(object["model"] as? String, "gpt-5")
        XCTAssertEqual(object["tool_choice"] as? String, "auto")
        XCTAssertEqual(object["temperature"] as? Double, 0.2)
        XCTAssertEqual(object["max_tokens"] as? Int, 200)

        let tools = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools.first?["type"] as? String, "function")
    }

    func test_chatMessage_toolResultEncodesOpenAIToolCallID() throws {
        let message = ChatMessage(
            role: .tool,
            content: "Search result summary",
            toolCallID: "call_1",
            toolCalls: nil
        )

        let object = try encodeJSONObject(message)
        XCTAssertEqual(object["role"] as? String, "tool")
        XCTAssertEqual(object["content"] as? String, "Search result summary")
        XCTAssertEqual(object["tool_call_id"] as? String, "call_1")
        XCTAssertNil(object["tool_calls"])
    }

    func test_chatStreamEvent_supportsTextToolCallAndFinishEvents() {
        XCTAssertEqual(ChatStreamEvent.textDelta("Hi"), .textDelta("Hi"))
        XCTAssertEqual(
            ChatStreamEvent.toolCallDelta(ChatToolCallDelta(
                index: 0,
                id: "call_1",
                name: "brave_web_search",
                argumentsDelta: "{\"q\""
            )),
            .toolCallDelta(ChatToolCallDelta(
                index: 0,
                id: "call_1",
                name: "brave_web_search",
                argumentsDelta: "{\"q\""
            ))
        )
        XCTAssertEqual(ChatStreamEvent.finished(.toolCalls), .finished(.toolCalls))
    }

    /// 把 Codable 值编码为 JSON object，避免测试依赖字段顺序。
    private func encodeJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
