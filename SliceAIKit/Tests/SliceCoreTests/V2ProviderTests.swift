import XCTest
@testable import SliceCore

final class V2ProviderTests: XCTestCase {

    func test_init_anthropic_allowsNilBaseURL() {
        let p = V2Provider(
            id: "claude",
            kind: .anthropic,
            name: "Claude",
            baseURL: nil,
            apiKeyRef: "keychain:claude",
            defaultModel: "claude-sonnet-4-6",
            capabilities: [.promptCaching, .toolCalling, .extendedThinking, .vision, .longContext]
        )
        XCTAssertEqual(p.kind, .anthropic)
        XCTAssertNil(p.baseURL)
        XCTAssertTrue(p.capabilities.contains(.extendedThinking))
    }

    func test_init_openAICompatible_requiresBaseURL() {
        let p = V2Provider(
            id: "openai-official",
            kind: .openAICompatible,
            name: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1"),
            apiKeyRef: "keychain:openai-official",
            defaultModel: "gpt-5",
            capabilities: []
        )
        XCTAssertNotNil(p.baseURL)
    }

    func test_providerKind_codable_goldenShape() throws {
        // golden JSON shape for each kind
        XCTAssertEqual(try encodeString(ProviderKind.openAICompatible), "\"openAICompatible\"")
        XCTAssertEqual(try encodeString(ProviderKind.anthropic), "\"anthropic\"")
        XCTAssertEqual(try encodeString(ProviderKind.gemini), "\"gemini\"")
        XCTAssertEqual(try encodeString(ProviderKind.ollama), "\"ollama\"")
    }

    func test_providerKind_allCases_stable() {
        XCTAssertEqual(
            Set(ProviderKind.allCases.map(\.rawValue)),
            ["openAICompatible", "anthropic", "gemini", "ollama"]
        )
    }

    func test_v2Provider_codable_goldenShape() throws {
        let p = V2Provider(
            id: "claude",
            kind: .anthropic,
            name: "Claude",
            baseURL: nil,
            apiKeyRef: "keychain:claude",
            defaultModel: "claude-sonnet-4-6",
            capabilities: [.promptCaching]
        )
        let data = try encode(p)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"anthropic\""))
        XCTAssertTrue(json.contains("\"id\":\"claude\""))
        XCTAssertTrue(json.contains("\"capabilities\":[\"promptCaching\"]"))
        XCTAssertFalse(json.contains("\"baseURL\""))  // nil 字段不写出
    }

    func test_v2Provider_codable_roundtrip() throws {
        let p = V2Provider(
            id: "openai-official",
            kind: .openAICompatible,
            name: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1"),
            apiKeyRef: "keychain:openai-official",
            defaultModel: "gpt-5",
            capabilities: []
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(V2Provider.self, from: data)
        XCTAssertEqual(p, decoded)
    }

    func test_decode_normalizesDuplicatesAndOrder() throws {
        // 用户手改 config-v2.json 故意塞入重复 + 乱序 capabilities；decoder 必须归一化
        let json = #"""
        {"id":"x","kind":"anthropic","name":"X","apiKeyRef":"keychain:x","defaultModel":"m","capabilities":["toolCalling","promptCaching","toolCalling","vision","promptCaching"]}
        """#
        let decoded = try JSONDecoder().decode(V2Provider.self, from: Data(json.utf8))
        // 预期：去重后按 rawValue 字母序排列
        XCTAssertEqual(decoded.capabilities, [.promptCaching, .toolCalling, .vision])
    }

    func test_v2Provider_keychainAccount() {
        let p = V2Provider(id: "x", kind: .anthropic, name: "X", baseURL: nil,
                            apiKeyRef: "keychain:custom-account", defaultModel: "m", capabilities: [])
        XCTAssertEqual(p.keychainAccount, "custom-account")
    }

    func test_v2Provider_keychainAccount_nonKeychainPrefix_returnsNil() {
        let p = V2Provider(id: "x", kind: .anthropic, name: "X", baseURL: nil,
                            apiKeyRef: "raw-literal-key", defaultModel: "m", capabilities: [])
        XCTAssertNil(p.keychainAccount)
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(value)
    }

    private func encodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
