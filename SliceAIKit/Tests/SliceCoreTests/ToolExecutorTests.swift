import XCTest
@testable import SliceCore

// MARK: - Fakes

/// 假 Configuration 提供者，用 actor 保证线程安全
private actor FakeConfig: ConfigurationProviding {
    var cfg: Configuration
    init(_ cfg: Configuration) { self.cfg = cfg }
    func current() async -> Configuration { cfg }
    func update(_ configuration: Configuration) async throws { self.cfg = configuration }
}

/// 假 Keychain 存储，支持预置初始 key-value
private actor FakeKeychain: KeychainAccessing {
    var store: [String: String]
    init(_ store: [String: String] = [:]) { self.store = store }
    func readAPIKey(providerId: String) async throws -> String? { store[providerId] }
    func writeAPIKey(_ value: String, providerId: String) async throws { store[providerId] = value }
    func deleteAPIKey(providerId: String) async throws { store.removeValue(forKey: providerId) }
}

/// 假 LLM Provider，按预置 chunks 依次 yield
private struct FakeProvider: LLMProvider {
    let chunks: [String]
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        let chunks = self.chunks
        return AsyncThrowingStream { cont in
            Task {
                for c in chunks { cont.yield(ChatChunk(delta: c)) }
                cont.finish()
            }
        }
    }
}

/// 简单假工厂：返回一个固定 chunks 的 FakeProvider
private struct FakeFactory: LLMProviderFactory {
    let chunks: [String]
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        FakeProvider(chunks: chunks)
    }
}

/// 捕获型工厂：将传入的 apiKey 保存到 Box，用于断言 ToolExecutor 正确传递密钥
private struct CapturingFactory: LLMProviderFactory {
    final class Box: @unchecked Sendable { var capturedKey: String? }
    let box = Box()
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        box.capturedKey = apiKey
        return FakeProvider(chunks: ["ok"])
    }
}

final class ToolExecutorTests: XCTestCase {

    /// 验证 execute 正常渲染 prompt 并正确转发流式 chunk
    func test_execute_renderPromptAndStream() async throws {
        let cfg = DefaultConfiguration.initial()
        let keychain = FakeKeychain(["openai-official": "sk-test"])
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(cfg),
            providerFactory: FakeFactory(chunks: ["Hello ", "World"]),
            keychain: keychain
        )
        let payload = SelectionPayload(
            text: "hola", appBundleID: "x", appName: "X", url: nil,
            screenPoint: .zero, source: .accessibility, timestamp: Date()
        )
        let stream = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
        var collected = ""
        for try await chunk in stream { collected += chunk.delta }
        XCTAssertEqual(collected, "Hello World")
    }

    /// 验证当 Keychain 读不到 API Key 时，抛出 .provider(.unauthorized)
    func test_execute_missingAPIKey_throwsUnauthorized() async {
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(DefaultConfiguration.initial()),
            providerFactory: FakeFactory(chunks: []),
            keychain: FakeKeychain()   // 空
        )
        let payload = SelectionPayload(
            text: "x", appBundleID: "", appName: "", url: nil,
            screenPoint: .zero, source: .accessibility, timestamp: Date()
        )
        do {
            _ = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
            XCTFail("should have thrown")
        } catch SliceError.provider(.unauthorized) {
            // OK
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    /// 验证 ToolExecutor 把 Keychain 中的 API Key 原样传给工厂
    func test_execute_passesAPIKeyToFactory() async throws {
        let factory = CapturingFactory()
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(DefaultConfiguration.initial()),
            providerFactory: factory,
            keychain: FakeKeychain(["openai-official": "sk-captured"])
        )
        let payload = SelectionPayload(text: "x", appBundleID: "", appName: "", url: nil,
                                       screenPoint: .zero, source: .accessibility, timestamp: Date())
        let stream = try await exec.execute(tool: DefaultConfiguration.translate, payload: payload)
        for try await _ in stream {}
        XCTAssertEqual(factory.box.capturedKey, "sk-captured")
    }

    /// 验证当 Tool.providerId 在 Configuration.providers 中找不到时抛配置错误
    func test_execute_unknownProvider_throws() async {
        var cfg = DefaultConfiguration.initial()
        cfg.tools[0].providerId = "ghost"     // 引用不存在的 provider
        let exec = ToolExecutor(
            configurationProvider: FakeConfig(cfg),
            providerFactory: FakeFactory(chunks: []),
            keychain: FakeKeychain()
        )
        let payload = SelectionPayload(text: "x", appBundleID: "", appName: "", url: nil,
                                       screenPoint: .zero, source: .accessibility, timestamp: Date())
        do {
            _ = try await exec.execute(tool: cfg.tools[0], payload: payload)
            XCTFail("should have thrown")
        } catch SliceError.configuration(.referencedProviderMissing(let id)) {
            XCTAssertEqual(id, "ghost")
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
