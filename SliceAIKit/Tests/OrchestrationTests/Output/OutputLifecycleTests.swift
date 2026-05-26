import Capabilities
import SliceCore
import XCTest
@testable import Orchestration

/// Output lifecycle 的执行链测试。
final class OutputLifecycleTests: XCTestCase {

    /// 本测试类创建的临时 cost db，测试结束后统一清理。
    private var tempDbURLs: [URL] = []

    /// 清理临时 sqlite 文件。
    override func tearDown() async throws {
        for url in tempDbURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempDbURLs.removeAll()
        try await super.tearDown()
    }

    /// Prompt stream 必须调用 begin/chunk/finish，并在 finish 阶段提供完整 final text。
    func test_promptStream_callsBeginChunkAndFinishWithFinalText() async throws {
        let output = MockOutputDispatcher()
        let engine = try makeEngine(
            output: output,
            chunks: [
                ChatChunk(delta: "Hello", finishReason: nil),
                ChatChunk(delta: " world", finishReason: nil)
            ]
        )

        _ = await collectEvents(from: engine.execute(tool: makePromptTool(displayMode: .silent), seed: makeSeed()))

        let calls = await output.lifecycleCalls
        XCTAssertEqual(calls.map(\.kind), [.begin, .chunk, .chunk, .finish])
        XCTAssertEqual(calls.last?.finalText, "Hello world")
    }

    /// Agent stream 也必须调用同一套 output lifecycle，供 structured / TTS 使用最终文本。
    func test_agentStream_callsBeginChunkAndFinishWithFinalText() async throws {
        let output = MockOutputDispatcher()
        let llm = MockToolCallingLLMProvider(turns: [
            [.textDelta("{\"answer\":\"ok\"}"), .finished(.stop)]
        ])
        let agentExecutor = AgentExecutor(
            providerResolver: MockProviderResolver(),
            mcpClient: MockMCPClient(),
            permissionBroker: MockPermissionBroker(),
            keychain: MockKeychain(["openai-stub": "fake-key"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm),
            mcpDescriptors: { [] }
        )
        let engine = try makeEngine(output: output, chunks: [], agentExecutor: agentExecutor)

        _ = await collectEvents(from: engine.execute(tool: makeAgentTool(displayMode: .structured), seed: makeSeed()))

        let calls = await output.lifecycleCalls
        XCTAssertEqual(calls.map(\.kind), [.begin, .chunk, .finish])
        XCTAssertEqual(calls.last?.finalText, "{\"answer\":\"ok\"}")
    }

    /// 构造最小 prompt tool。
    private func makePromptTool(displayMode: DisplayMode) -> Tool {
        Tool(
            id: "lifecycle.tool",
            name: "Lifecycle Tool",
            icon: "T",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: "system",
                userPrompt: "user {{selection}}",
                contexts: [],
                provider: .fixed(providerId: "test-provider", modelId: nil),
                temperature: nil,
                maxTokens: nil,
                variables: [:]
            )),
            visibleWhen: nil,
            displayMode: displayMode,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造最小 agent tool。
    private func makeAgentTool(displayMode: DisplayMode) -> Tool {
        Tool(
            id: "lifecycle.agent",
            name: "Lifecycle Agent",
            icon: "A",
            description: nil,
            kind: .agent(AgentTool(
                systemPrompt: "agent system",
                initialUserPrompt: "agent user {{selection}}",
                contexts: [],
                provider: .fixed(providerId: "openai-stub", modelId: nil),
                skills: [],
                mcpAllowlist: [],
                builtinCapabilities: [],
                maxSteps: 3,
                stopCondition: .finalAnswerProvided
            )),
            visibleWhen: nil,
            displayMode: displayMode,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造最小 ExecutionSeed。
    private func makeSeed() -> ExecutionSeed {
        ExecutionSeed(
            invocationId: UUID(),
            selection: SelectionSnapshot(
                text: "selected text",
                source: .accessibility,
                length: 13,
                language: nil,
                contentType: nil
            ),
            frontApp: AppSnapshot(
                bundleId: "com.test.app",
                name: "Test App",
                url: nil,
                windowTitle: nil
            ),
            screenAnchor: .zero,
            timestamp: Date(),
            triggerSource: .floatingToolbar,
            isDryRun: false
        )
    }

    /// 构造带 mock provider 的 ExecutionEngine。
    private func makeEngine(
        output: MockOutputDispatcher,
        chunks: [ChatChunk],
        agentExecutor: AgentExecutor? = nil
    ) throws -> ExecutionEngine {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-output-lifecycle-\(UUID().uuidString).db")
        tempDbURLs.append(dbURL)
        let promptExecutor = PromptExecutor(
            keychain: MockKeychain(["openai-stub": "fake-key"]),
            llmProviderFactory: MockLLMProviderFactory(provider: MockLLMProvider(chunks: chunks))
        )
        let registry = ContextProviderRegistry(providers: [:])
        return ExecutionEngine(
            contextCollector: ContextCollector(registry: registry),
            permissionBroker: MockPermissionBroker(),
            permissionGraph: PermissionGraph(providerRegistry: registry),
            providerResolver: MockProviderResolver(),
            promptExecutor: promptExecutor,
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: try CostAccounting(dbURL: dbURL),
            auditLog: MockAuditLog(),
            output: output,
            agentExecutor: agentExecutor
        )
    }

    /// 收集 stream 事件；ExecutionEngine 正常失败路径不会 throw。
    private func collectEvents(
        from stream: AsyncThrowingStream<ExecutionEvent, any Error>
    ) async -> [ExecutionEvent] {
        var events: [ExecutionEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch {
            XCTFail("Unexpected stream throw: \(error)")
        }
        return events
    }
}
