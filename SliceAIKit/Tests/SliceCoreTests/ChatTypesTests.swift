import XCTest
@testable import SliceCore

final class ChatTypesTests: XCTestCase {
    func test_chatMessageEncoding_systemRole() throws {
        let msg = ChatMessage(role: .system, content: "You are helpful.")
        let data = try JSONEncoder().encode(msg)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\"role\":\"system\""))
        XCTAssertTrue(s.contains("\"content\":\"You are helpful.\""))
    }

    func test_chatRequest_nilFieldsOmitted() throws {
        // temperature/maxTokens 为 nil 时必须不出现在 JSON 中，保持服务端默认
        let req = ChatRequest(model: "gpt-5", messages: [], temperature: nil, maxTokens: nil)
        let data = try JSONEncoder().encode(req)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertFalse(s.contains("temperature"))
        XCTAssertFalse(s.contains("max_tokens"))
        XCTAssertTrue(s.contains("\"model\":\"gpt-5\""))
    }

    func test_chatRequest_nonNilFieldsPresent() throws {
        let req = ChatRequest(model: "gpt-5", messages: [], temperature: 0.5, maxTokens: 100)
        let data = try JSONEncoder().encode(req)
        let s = String(data: data, encoding: .utf8) ?? ""
        XCTAssertTrue(s.contains("\"temperature\":0.5"))
        XCTAssertTrue(s.contains("\"max_tokens\":100"))
    }
}
