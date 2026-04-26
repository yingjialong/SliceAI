import Capabilities
import SliceCore
import XCTest
@testable import Orchestration

/// PromptExecutor actor 单元测试
///
/// 覆盖矩阵：
/// 1. 流元素顺序：[chunk]* + completed
/// 2. 空 chunk 路径：仅 completed
/// 3. 未授权：keychain 空 / 空字符串
/// 4. 协议族限制：anthropic / gemini / ollama 抛 .validationFailed
/// 5. .openAICompatible + nil baseURL：抛 .validationFailed（防御性 guard，正常 V2Provider 不会到这里）
/// 6. 渲染：变量注入、systemPrompt 包含
/// 7. 透传：temperature / maxTokens / model
/// 8. UsageStats 估算：input/output > 0
/// 9. V2Provider → v1 Provider 适配等价
/// 10. 错误透传：factory.make 抛错 / stream 同步抛错 / stream 中途抛错
final class PromptExecutorTests: XCTestCase {

    // MARK: - Fixture builders

    /// 构造一个最小可用的 ResolvedExecutionContext stub
    /// - Parameters:
    ///   - selectionText: 选区文本（注入 {{selection}}）
    ///   - appName: 前台 app 名（注入 {{app}}）
    ///   - urlString: 浏览器 URL；nil 则 url 字段为 nil
    private func makeResolved(
        selectionText: String = "hello world",
        appName: String = "Safari",
        urlString: String? = nil
    ) -> ResolvedExecutionContext {
        let url: URL? = urlString.flatMap { URL(string: $0) }
        let snapshot = SelectionSnapshot(
            text: selectionText,
            source: .accessibility,
            length: selectionText.count,
            language: nil,
            contentType: nil
        )
        let app = AppSnapshot(
            bundleId: "com.test.app",
            name: appName,
            url: url,
            windowTitle: nil
        )
        let seed = ExecutionSeed(
            invocationId: UUID(),
            selection: snapshot,
            frontApp: app,
            screenAnchor: .zero,
            timestamp: Date(),
            triggerSource: .floatingToolbar,
            isDryRun: false
        )
        return ResolvedExecutionContext(
            seed: seed,
            contexts: ContextBag(values: [:]),
            resolvedAt: Date(),
            failures: [:]
        )
    }

    /// 构造一个最小 PromptTool
    /// - Parameters:
    ///   - systemPrompt: system 模板，nil 表示无 system message
    ///   - userPrompt: user 模板
    ///   - temperature / maxTokens / variables: 透传到 ChatRequest
    private func makePromptTool(
        systemPrompt: String? = nil,
        userPrompt: String = "Process: {{selection}}",
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        variables: [String: String] = [:]
    ) -> PromptTool {
        PromptTool(
            systemPrompt: systemPrompt,
            userPrompt: userPrompt,
            contexts: [],
            provider: .fixed(providerId: "test-openai", modelId: nil),
            temperature: temperature,
            maxTokens: maxTokens,
            variables: variables
        )
    }

    /// 构造一个 .openAICompatible 的 V2Provider，apiKeyRef = "keychain:<id>"
    private func makeOpenAIV2Provider(
        id: String = "test-openai",
        defaultModel: String = "gpt-5",
        baseURL: URL? = URL(string: "https://api.openai.com/v1") // swiftlint:disable:this force_unwrapping
    ) -> V2Provider {
        V2Provider(
            id: id,
            kind: .openAICompatible,
            name: "Test OpenAI",
            baseURL: baseURL,
            apiKeyRef: "keychain:\(id)",
            defaultModel: defaultModel,
            capabilities: []
        )
    }

    /// 收集 stream 全部元素到数组（含错误透传场景）
    private func collect(
        _ stream: AsyncThrowingStream<PromptStreamElement, any Error>
    ) async throws -> [PromptStreamElement] {
        var out: [PromptStreamElement] = []
        for try await element in stream { out.append(element) }
        return out
    }

    // MARK: - Test 1: happy path 顺序

    /// LLM yield 3 chunks → stream 应产出 3 .chunk + 1 .completed，顺序严格
    func test_run_happyPath_yieldsChunksThenCompleted() async throws {
        let llm = MockLLMProvider(chunks: [
            ChatChunk(delta: "Hello "),
            ChatChunk(delta: "from "),
            ChatChunk(delta: "GPT", finishReason: .stop)
        ])
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        let elements = try await collect(stream)

        XCTAssertEqual(elements.count, 4, "应 yield 3 chunks + 1 completed = 4 个元素")
        guard case .chunk(let c0) = elements[0] else { return XCTFail("element[0] 应为 .chunk") }
        guard case .chunk(let c1) = elements[1] else { return XCTFail("element[1] 应为 .chunk") }
        guard case .chunk(let c2) = elements[2] else { return XCTFail("element[2] 应为 .chunk") }
        guard case .completed = elements[3] else { return XCTFail("element[3] 应为 .completed") }
        XCTAssertEqual(c0, "Hello ")
        XCTAssertEqual(c1, "from ")
        XCTAssertEqual(c2, "GPT")
    }

    // MARK: - Test 2: 空 chunk 路径

    /// LLM yield 0 chunks → stream 应仅产出 1 .completed
    func test_run_emptyChunks_yieldsCompletedOnly() async throws {
        let llm = MockLLMProvider(chunks: [])
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        let elements = try await collect(stream)

        XCTAssertEqual(elements.count, 1, "空 chunk 输入应只产出 .completed")
        guard case .completed(let stats) = elements[0] else {
            return XCTFail("element[0] 应为 .completed")
        }
        // 空 chunk → outputTokens = 0 / 4 = 0
        XCTAssertEqual(stats.outputTokens, 0, "空输出应 outputTokens=0")
        XCTAssertGreaterThan(stats.inputTokens, 0, "user 模板非空，inputTokens 应 > 0")
    }

    // MARK: - Test 3 / 4: 未授权（缺失 / 空字符串）

    /// keychain 中无对应 key → stream 第一次 next() 抛 .provider(.unauthorized)
    func test_run_unauthorized_throwsWhenKeychainMissing() async {
        let executor = PromptExecutor(
            keychain: MockKeychain(),  // 空
            llmProviderFactory: MockLLMProviderFactory(provider: MockLLMProvider())
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        await assertThrows(stream) { error in
            guard case SliceError.provider(.unauthorized) = error else {
                return XCTFail("应抛 .provider(.unauthorized)，实际：\(error)")
            }
        }
    }

    /// keychain 中存的是空字符串 → 同样抛 .unauthorized
    func test_run_unauthorized_throwsWhenKeychainEmptyString() async {
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": ""]),
            llmProviderFactory: MockLLMProviderFactory(provider: MockLLMProvider())
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        await assertThrows(stream) { error in
            guard case SliceError.provider(.unauthorized) = error else {
                return XCTFail("空字符串 API Key 应抛 .unauthorized，实际：\(error)")
            }
        }
    }

    // MARK: - Test 5/6/7: 协议族限制

    /// V2Provider.kind == .anthropic → 抛 .configuration(.validationFailed)
    func test_run_anthropicKind_throwsValidationFailed() async {
        let v2 = V2Provider(
            id: "claude", kind: .anthropic, name: "Claude",
            baseURL: nil, apiKeyRef: "keychain:claude", defaultModel: "claude-sonnet-4-6",
            capabilities: []
        )
        let executor = PromptExecutor(
            keychain: MockKeychain(["claude": "sk-anthropic"]),
            llmProviderFactory: MockLLMProviderFactory(provider: MockLLMProvider())
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: v2
        )
        await assertThrows(stream) { error in
            guard case SliceError.configuration(.validationFailed(let msg)) = error else {
                return XCTFail("应抛 .configuration(.validationFailed)，实际：\(error)")
            }
            XCTAssertTrue(msg.contains("openAICompatible"), "msg 应解释 M2 限制：\(msg)")
            XCTAssertTrue(msg.contains("claude"), "msg 应包含 provider id：\(msg)")
        }
    }

    /// V2Provider.kind == .gemini → 同样抛 .validationFailed
    func test_run_geminiKind_throwsValidationFailed() async {
        let v2 = V2Provider(
            id: "gem", kind: .gemini, name: "Gemini",
            baseURL: nil, apiKeyRef: "keychain:gem", defaultModel: "gemini-2.5",
            capabilities: []
        )
        let executor = PromptExecutor(
            keychain: MockKeychain(["gem": "sk-google"]),
            llmProviderFactory: MockLLMProviderFactory(provider: MockLLMProvider())
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: v2
        )
        await assertThrows(stream) { error in
            guard case SliceError.configuration(.validationFailed) = error else {
                return XCTFail("应抛 .configuration(.validationFailed)，实际：\(error)")
            }
        }
    }

    /// V2Provider.kind == .ollama → 同样抛 .validationFailed
    /// （注意 ollama 在 V2Provider decoder 里要求非 nil baseURL，因此这里直接通过 init 构造）
    func test_run_ollamaKind_throwsValidationFailed() async {
        let v2 = V2Provider(
            id: "ollama", kind: .ollama, name: "Ollama",
            baseURL: URL(string: "http://localhost:11434"), // swiftlint:disable:this force_unwrapping
            apiKeyRef: "keychain:ollama", defaultModel: "llama3",
            capabilities: []
        )
        let executor = PromptExecutor(
            keychain: MockKeychain(["ollama": "no-key-needed"]),
            llmProviderFactory: MockLLMProviderFactory(provider: MockLLMProvider())
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: v2
        )
        await assertThrows(stream) { error in
            guard case SliceError.configuration(.validationFailed) = error else {
                return XCTFail("应抛 .configuration(.validationFailed)，实际：\(error)")
            }
        }
    }

    // MARK: - Test 8: nil baseURL 防御性兜底

    /// V2Provider.kind == .openAICompatible + baseURL == nil → 抛 .validationFailed
    /// 注：正常路径 V2Provider decoder/validate 已要求 .openAICompatible 必有 baseURL，
    /// 此用例验证 PromptExecutor 在构造路径绕过 validate 的场景下仍能 fail-fast。
    func test_run_openAICompatibleNilBaseURL_throwsValidationFailed() async {
        // V2Provider public init 不做校验（仅 validate() / decoder 做），可构造非法对象
        let v2 = makeOpenAIV2Provider(baseURL: nil)
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: MockLLMProviderFactory(provider: MockLLMProvider())
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: v2
        )
        await assertThrows(stream) { error in
            guard case SliceError.configuration(.validationFailed(let msg)) = error else {
                return XCTFail("应抛 .configuration(.validationFailed)，实际：\(error)")
            }
            XCTAssertTrue(msg.contains("nil baseURL"), "msg 应解释 nil baseURL：\(msg)")
        }
    }

    // MARK: - Test 9: prompt 渲染（variables 注入）

    /// 验证 {{selection}} {{app}} {{url}} 内置变量注入 + LLM 收到的 user content 与渲染结果一致
    func test_run_promptRendering_variablesInjected() async throws {
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "ok")])
        let factory = MockLLMProviderFactory(provider: llm)
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: factory
        )
        let promptTool = makePromptTool(
            userPrompt: "Selection={{selection}} App={{app}} URL={{url}}"
        )
        let resolved = makeResolved(
            selectionText: "hola",
            appName: "Chrome",
            urlString: "https://example.com/page"
        )

        let stream = await executor.run(promptTool: promptTool, resolved: resolved, provider: makeOpenAIV2Provider())
        _ = try await collect(stream)

        guard let req = llm.capturedRequest else { return XCTFail("LLM 未收到 request") }
        guard let lastMsg = req.messages.last, lastMsg.role == .user else {
            return XCTFail("最后一条 message 应为 user")
        }
        XCTAssertEqual(
            lastMsg.content,
            "Selection=hola App=Chrome URL=https://example.com/page",
            "user content 应正确替换变量"
        )
    }

    /// systemPrompt 非空时应作为 messages[0]，role=.system；user 在后
    func test_run_systemPromptIncluded_andOrderedFirst() async throws {
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "ok")])
        let factory = MockLLMProviderFactory(provider: llm)
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: factory
        )
        let promptTool = makePromptTool(
            systemPrompt: "You are translator targeting {{language}}.",
            userPrompt: "Translate: {{selection}}",
            variables: ["language": "Chinese"]
        )

        let stream = await executor.run(
            promptTool: promptTool,
            resolved: makeResolved(selectionText: "Hi"),
            provider: makeOpenAIV2Provider()
        )
        _ = try await collect(stream)

        guard let req = llm.capturedRequest else { return XCTFail("LLM 未收到 request") }
        XCTAssertEqual(req.messages.count, 2)
        XCTAssertEqual(req.messages[0].role, .system)
        XCTAssertEqual(req.messages[0].content, "You are translator targeting Chinese.")
        XCTAssertEqual(req.messages[1].role, .user)
        XCTAssertEqual(req.messages[1].content, "Translate: Hi")
    }

    // MARK: - Test 10/11: temperature / maxTokens / model 透传

    /// temperature / maxTokens 透传到 ChatRequest
    func test_run_temperatureAndMaxTokensForwarded() async throws {
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "ok")])
        let factory = MockLLMProviderFactory(provider: llm)
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: factory
        )

        let stream = await executor.run(
            promptTool: makePromptTool(temperature: 0.7, maxTokens: 256),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        _ = try await collect(stream)

        guard let req = llm.capturedRequest else { return XCTFail("LLM 未收到 request") }
        XCTAssertEqual(req.temperature, 0.7)
        XCTAssertEqual(req.maxTokens, 256)
    }

    /// ChatRequest.model 应来自 V2Provider.defaultModel
    func test_run_modelComesFromProviderDefault() async throws {
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "ok")])
        let factory = MockLLMProviderFactory(provider: llm)
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: factory
        )
        let v2 = makeOpenAIV2Provider(defaultModel: "gpt-4o-mini")

        let stream = await executor.run(promptTool: makePromptTool(), resolved: makeResolved(), provider: v2)
        _ = try await collect(stream)

        guard let req = llm.capturedRequest else { return XCTFail("LLM 未收到 request") }
        XCTAssertEqual(req.model, "gpt-4o-mini")
    }

    // MARK: - Test 12: UsageStats 估算

    /// inputTokens > 0 && outputTokens > 0；UsageStats 顺序在 chunks 之后
    func test_run_usageStatsEstimatedAndOrderedLast() async throws {
        // userPrompt 渲染后约 40+ 字符 → inputTokens ≈ 40/4=10
        let userPrompt = String(repeating: "a", count: 40)
        // 输出 chunks 总字符 80 → outputTokens ≈ 80/4=20
        let chunks = (0..<4).map { _ in ChatChunk(delta: String(repeating: "b", count: 20)) }
        let llm = MockLLMProvider(chunks: chunks)
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )

        let stream = await executor.run(
            promptTool: makePromptTool(userPrompt: userPrompt),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        let elements = try await collect(stream)

        // .completed 必须在最后一个位置
        guard case .completed(let stats) = elements.last else {
            return XCTFail("末尾元素应为 .completed")
        }
        XCTAssertGreaterThan(stats.inputTokens, 0)
        XCTAssertGreaterThan(stats.outputTokens, 0)
        // 前 N-1 都应是 chunk
        for (idx, element) in elements.dropLast().enumerated() {
            guard case .chunk = element else {
                return XCTFail("element[\(idx)] 应为 .chunk")
            }
        }
    }

    // MARK: - Test 13: V2Provider → v1 Provider 适配等价

    /// 验证 factory 收到的 v1 Provider 字段与 V2Provider 一致（id / name / baseURL / apiKeyRef / defaultModel）
    func test_run_v2ToV1ProviderAdapter_fieldsEqual() async throws {
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "ok")])
        let factory = MockLLMProviderFactory(provider: llm)
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-key-xyz"]),
            llmProviderFactory: factory
        )
        let v2 = makeOpenAIV2Provider(
            id: "test-openai",
            defaultModel: "gpt-5"
        )

        let stream = await executor.run(promptTool: makePromptTool(), resolved: makeResolved(), provider: v2)
        _ = try await collect(stream)

        guard let v1 = factory.capturedProvider else { return XCTFail("factory 未捕获 Provider") }
        XCTAssertEqual(v1.id, v2.id)
        XCTAssertEqual(v1.name, v2.name)
        XCTAssertEqual(v1.baseURL, v2.baseURL)
        XCTAssertEqual(v1.apiKeyRef, v2.apiKeyRef)
        XCTAssertEqual(v1.defaultModel, v2.defaultModel)
        // API Key 透传
        XCTAssertEqual(factory.capturedAPIKey, "sk-key-xyz")
    }

    // MARK: - Test 14/15/16: 错误透传

    /// LLMProviderFactory.make 抛错 → stream 透传同错误
    func test_run_factoryMakeThrows_propagatesError() async {
        let factory = MockLLMProviderFactory(
            provider: MockLLMProvider(),
            makeError: SliceError.provider(.serverError(500))
        )
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: factory
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        await assertThrows(stream) { error in
            guard case SliceError.provider(.serverError(let code)) = error else {
                return XCTFail("应透传 factory 错误，实际：\(error)")
            }
            XCTAssertEqual(code, 500)
        }
    }

    /// LLMProvider.stream 同步抛错（创建 AsyncThrowingStream 之前）→ stream 透传
    func test_run_streamSyncThrows_propagatesError() async {
        let llm = MockLLMProvider(throwBeforeStream: SliceError.provider(.networkTimeout))
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        await assertThrows(stream) { error in
            guard case SliceError.provider(.networkTimeout) = error else {
                return XCTFail("应透传 stream 错误，实际：\(error)")
            }
        }
    }

    /// LLM stream 中途抛错 → stream 透传 + 已 yield 的 chunk 不撤回
    func test_run_streamMidwayThrows_propagatesAndKeepsYieldedChunks() async throws {
        let llm = MockLLMProvider(
            chunks: [ChatChunk(delta: "first"), ChatChunk(delta: "second")],
            trailingError: SliceError.provider(.invalidResponse("test"))
        )
        let executor = PromptExecutor(
            keychain: MockKeychain(["test-openai": "sk-abc"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )

        let stream = await executor.run(
            promptTool: makePromptTool(),
            resolved: makeResolved(),
            provider: makeOpenAIV2Provider()
        )
        var collected: [PromptStreamElement] = []
        var caughtError: (any Error)?
        do {
            for try await element in stream { collected.append(element) }
        } catch {
            caughtError = error
        }

        // 已 yield 2 chunk 应保留；不应有 .completed（错误中断）
        XCTAssertEqual(collected.count, 2)
        for element in collected {
            guard case .chunk = element else { return XCTFail("中断前元素应全为 .chunk") }
        }
        // 注：caughtError 是 (any Error)?；先解包再 cast 再 case 匹配
        guard let caught = caughtError,
              case SliceError.provider(.invalidResponse) = caught else {
            return XCTFail("应捕获 .invalidResponse，实际：\(String(describing: caughtError))")
        }
    }

    // MARK: - Helpers

    /// 通用断言：消费 stream 并期望抛错；handler 验证错误形态
    private func assertThrows(
        _ stream: AsyncThrowingStream<PromptStreamElement, any Error>,
        _ handler: (any Error) -> Void
    ) async {
        do {
            for try await _ in stream {}
            XCTFail("expected stream to throw")
        } catch {
            handler(error)
        }
    }
}
