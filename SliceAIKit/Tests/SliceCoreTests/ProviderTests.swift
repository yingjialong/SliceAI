import XCTest
@testable import SliceCore

final class ProviderTests: XCTestCase {

    func test_init_anthropic_allowsNilBaseURL() {
        let p = Provider(
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
        let p = Provider(
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

    func test_provider_codable_goldenShape() throws {
        let p = Provider(
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

    func test_provider_codable_roundtrip() throws {
        let p = Provider(
            id: "openai-official",
            kind: .openAICompatible,
            name: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1"),
            apiKeyRef: "keychain:openai-official",
            defaultModel: "gpt-5",
            capabilities: []
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(Provider.self, from: data)
        XCTAssertEqual(p, decoded)
    }

    func test_decode_normalizesDuplicatesAndOrder() throws {
        // 用户手改 config-v2.json 故意塞入重复 + 乱序 capabilities；decoder 必须归一化
        let json = #"""
        {"id":"x","kind":"anthropic","name":"X","apiKeyRef":"keychain:x","defaultModel":"m","capabilities":["toolCalling","promptCaching","toolCalling","vision","promptCaching"]}
        """#
        let decoded = try JSONDecoder().decode(Provider.self, from: Data(json.utf8))
        // 预期：去重后按 rawValue 字母序排列
        XCTAssertEqual(decoded.capabilities, [.promptCaching, .toolCalling, .vision])
    }

    func test_provider_keychainAccount() {
        let p = Provider(id: "x", kind: .anthropic, name: "X", baseURL: nil,
                            apiKeyRef: "keychain:custom-account", defaultModel: "m", capabilities: [])
        XCTAssertEqual(p.keychainAccount, "custom-account")
    }

    func test_provider_keychainAccount_nonKeychainPrefix_returnsNil() {
        let p = Provider(id: "x", kind: .anthropic, name: "X", baseURL: nil,
                            apiKeyRef: "raw-literal-key", defaultModel: "m", capabilities: [])
        XCTAssertNil(p.keychainAccount)
    }

    // MARK: - Decoder 校验 baseURL 要求（P2a 修复）
    //
    // 背景：ProviderKind.openAICompatible / .ollama 协议族必须有 baseURL（两者都是
    // "用户填入 endpoint"的设计）。init(id:…:) 历史上允许传 nil，但生产路径都是
    // 开发期可控的 static let 常量；真正的外部输入入口是 decoder（用户手改
    // config-v2.json）。本组测试锁定 decoder 的不变量。

    /// openAICompatible 协议族 JSON 若缺 baseURL / baseURL=null，decoder 必须拒绝
    func test_decode_openAICompatibleRequiresNonNilBaseURL() {
        let json = #"""
        {"id":"x","kind":"openAICompatible","name":"X","baseURL":null,"apiKeyRef":"keychain:x","defaultModel":"gpt-4","capabilities":[]}
        """#
        XCTAssertThrowsError(try JSONDecoder().decode(Provider.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("expected DecodingError.dataCorrupted, got \(error)")
                return
            }
        }
    }

    /// ollama 同样要求 baseURL（本地 endpoint 必填，如 http://localhost:11434/v1）
    func test_decode_ollamaRequiresNonNilBaseURL() {
        let json = #"""
        {"id":"x","kind":"ollama","name":"X","baseURL":null,"apiKeyRef":"keychain:x","defaultModel":"llama3","capabilities":[]}
        """#
        XCTAssertThrowsError(try JSONDecoder().decode(Provider.self, from: Data(json.utf8))) { error in
            guard case DecodingError.dataCorrupted = error else {
                XCTFail("expected DecodingError.dataCorrupted, got \(error)")
                return
            }
        }
    }

    /// anthropic 协议族允许 baseURL=nil（官方 SDK endpoint 固定，无需用户填）
    func test_decode_anthropicAllowsNilBaseURL() throws {
        let json = #"""
        {"id":"x","kind":"anthropic","name":"X","baseURL":null,"apiKeyRef":"keychain:x","defaultModel":"claude-sonnet-4","capabilities":[]}
        """#
        let decoded = try JSONDecoder().decode(Provider.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.kind, .anthropic)
        XCTAssertNil(decoded.baseURL)
    }

    /// gemini 同样允许 baseURL=nil
    func test_decode_geminiAllowsNilBaseURL() throws {
        let json = #"""
        {"id":"x","kind":"gemini","name":"X","baseURL":null,"apiKeyRef":"keychain:x","defaultModel":"gemini-2","capabilities":[]}
        """#
        let decoded = try JSONDecoder().decode(Provider.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.kind, .gemini)
        XCTAssertNil(decoded.baseURL)
    }

    // MARK: - Public `validate()` 写入边界校验（第八轮 P2-1 修复）
    //
    // 背景：decoder 侧已校验 baseURL；但 `init(id:...)` 非 throws、允许代码侧
    // 构造非法对象（典型场景：测试 fixture、默认值、migrator 输出）。M3 接入后
    // 这些对象会通过 `ConfigurationStore.save()` 落盘——因此 save() 必须在
    // 写盘前调用 `p.validate()` 拦截。本组测试锁定 validate() 本身的契约。

    /// openAICompatible 协议族 + nil baseURL → validate() 必须 throw .validationFailed
    func test_validate_throwsForOpenAICompatibleWithNilBaseURL() {
        let p = Provider(
            id: "broken",
            kind: .openAICompatible,
            name: "Broken",
            baseURL: nil,
            apiKeyRef: "keychain:broken",
            defaultModel: "gpt-5",
            capabilities: []
        )
        XCTAssertThrowsError(try p.validate()) { error in
            guard case SliceError.configuration(.validationFailed(let msg)) = error else {
                XCTFail("expected .configuration(.validationFailed), got \(error)")
                return
            }
            // msg 必须包含 provider id + 字段名，便于用户定位
            XCTAssertTrue(msg.contains("broken"), "msg missing provider id; got: \(msg)")
            XCTAssertTrue(msg.contains("baseURL"), "msg missing field name; got: \(msg)")
        }
    }

    /// anthropic 协议族 + nil baseURL 合法 → validate() 必须不 throw
    func test_validate_passesForAnthropicWithNilBaseURL() {
        let p = Provider(
            id: "claude",
            kind: .anthropic,
            name: "Claude",
            baseURL: nil,
            apiKeyRef: "keychain:claude",
            defaultModel: "claude-sonnet-4-6",
            capabilities: [.promptCaching]
        )
        XCTAssertNoThrow(try p.validate())
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
