import Capabilities
import SliceCore
import XCTest
@testable import Orchestration

/// SideEffectExecutor 的行为测试。
final class SideEffectExecutorTests: XCTestCase {

    /// 每个测试的临时目录。
    private var tempDirectory: URL?

    /// 清理临时目录。
    override func tearDown() async throws {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        try await super.tearDown()
    }

    /// copyToClipboard 必须把 final text 写入剪贴板 adapter。
    func test_execute_copyToClipboard_writesFinalText() async throws {
        let clipboard = SpyClipboardWriter()
        let executor = makeExecutor(clipboard: clipboard)

        let outcome = await executor.execute(SideEffect.copyToClipboard, finalText: "final answer", invocationId: UUID())

        XCTAssertEqual(outcome, .executed)
        let writes = await clipboard.writes
        XCTAssertEqual(writes, ["final answer"])
    }

    /// appendToFile 必须写入 header 和 final text。
    func test_execute_appendToFile_appendsHeaderAndFinalText() async throws {
        let dir = try makeTempDirectory()
        let outputURL = dir.appendingPathComponent("result.md")
        let executor = makeExecutor(userAllowlist: [dir.path])

        let outcome = await executor.execute(
            SideEffect.appendToFile(path: outputURL.path, header: "## Result"),
            finalText: "final answer",
            invocationId: UUID()
        )

        XCTAssertEqual(outcome, .executed)
        let content = try String(contentsOf: outputURL, encoding: .utf8)
        XCTAssertTrue(content.contains("## Result"))
        XCTAssertTrue(content.contains("final answer"))
    }

    /// notify 必须调用 notification adapter，且不依赖 final text。
    func test_execute_notify_sendsConfiguredNotification() async throws {
        let notifier = SpyNotifier()
        let executor = makeExecutor(notifier: notifier)

        let outcome = await executor.execute(
            SideEffect.notify(title: "Done", body: "Completed"),
            finalText: "raw output should not be used",
            invocationId: UUID()
        )

        XCTAssertEqual(outcome, .executed)
        let notifications = await notifier.notifications
        XCTAssertEqual(notifications, [SpyNotifier.Notification(title: "Done", body: "Completed")])
    }

    /// callMCP 必须使用 side effect 中声明的 ref 和 params。
    func test_execute_callMCP_usesConfiguredRefAndParams() async throws {
        let ref = MCPToolRef(server: "fs", tool: "read")
        let params: MCPJSONValue.Object = ["path": .string("/tmp/a.txt")]
        let mcpClient = MockMCPClient(responses: [
            ref: MCPCallResult(content: [.text("ok")], structuredContent: nil, isError: false, meta: nil)
        ])
        let executor = makeExecutor(mcpClient: mcpClient)

        let outcome = await executor.execute(
            SideEffect.callMCP(ref: ref, params: params),
            finalText: "ignored",
            invocationId: UUID()
        )

        XCTAssertEqual(outcome, .executed)
        let callCount = await mcpClient.callCount
        let lastArguments = await mcpClient.lastArguments
        XCTAssertEqual(callCount, 1)
        XCTAssertEqual(lastArguments, params)
    }

    /// tts 必须把 final text 和 voice 传给 speech adapter。
    func test_execute_tts_speaksFinalText() async throws {
        let speaker = SpySpeechSynthesizer()
        let executor = makeExecutor(speaker: speaker)

        let outcome = await executor.execute(SideEffect.tts(voice: "Alex"), finalText: "Read this", invocationId: UUID())

        XCTAssertEqual(outcome, .executed)
        let calls = await speaker.calls
        XCTAssertEqual(calls, [SpySpeechSynthesizer.Call(text: "Read this", voice: "Alex")])
    }

    /// writeMemory 在 Phase 2 必须是显式 unsupported，不能假装成功。
    func test_execute_writeMemory_returnsUnsupported() async throws {
        let executor = makeExecutor()

        let outcome = await executor.execute(
            SideEffect.writeMemory(tool: "english-tutor", entry: "remember"),
            finalText: "ignored",
            invocationId: UUID()
        )

        XCTAssertEqual(outcome, .unsupported(reason: "writeMemory is planned for Phase 3"))
    }

    /// ExecutionEngine 必须在 side effect gate 通过后调用 executor，并传入完整 final text。
    func test_executionEngine_invokesSideEffectExecutorWithFinalText() async throws {
        let recorder = RecordingSideEffectExecutor()
        let engine = try makeEngine(sideEffectExecutor: recorder, chunks: [
            ChatChunk(delta: "final ", finishReason: nil),
            ChatChunk(delta: "answer", finishReason: nil)
        ])
        let tool = makePromptToolWithSideEffect()

        _ = await collectEvents(from: engine.execute(tool: tool, seed: makeSeed()))

        let calls = await recorder.calls
        XCTAssertEqual(calls, [
            RecordingSideEffectExecutor.Call(
                sideEffect: .copyToClipboard,
                finalText: "final answer"
            )
        ])
    }

    /// `.file` display mode 已在 OutputDispatcher.finish 写文件，不能再执行同一个 appendToFile side effect。
    func test_executionEngine_fileMode_skipsAppendToFileSideEffectExecutor() async throws {
        let recorder = RecordingSideEffectExecutor()
        let engine = try makeEngine(sideEffectExecutor: recorder, chunks: [
            ChatChunk(delta: "final ", finishReason: nil),
            ChatChunk(delta: "answer", finishReason: nil)
        ])
        let tool = makeFilePromptToolWithSideEffects()

        _ = await collectEvents(from: engine.execute(tool: tool, seed: makeSeed()))

        let calls = await recorder.calls
        XCTAssertEqual(calls, [
            RecordingSideEffectExecutor.Call(
                sideEffect: .copyToClipboard,
                finalText: "final answer"
            )
        ])
    }

    /// 构造 executor。
    private func makeExecutor(
        clipboard: SpyClipboardWriter = SpyClipboardWriter(),
        notifier: SpyNotifier = SpyNotifier(),
        speaker: SpySpeechSynthesizer = SpySpeechSynthesizer(),
        mcpClient: any MCPClientProtocol = MockMCPClient(),
        userAllowlist: [String] = []
    ) -> SideEffectExecutor {
        SideEffectExecutor(
            clipboard: clipboard,
            notifier: notifier,
            speaker: speaker,
            mcpClient: mcpClient,
            pathSandbox: PathSandbox(userAllowlist: userAllowlist)
        )
    }

    /// 创建临时目录。
    private func makeTempDirectory() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-side-effect-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirectory = url
        return url
    }

    /// 构造带 side effect 的测试 Tool。
    private func makePromptToolWithSideEffect() -> Tool {
        Tool(
            id: "side-effect.tool",
            name: "Side Effect Tool",
            icon: "S",
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
            displayMode: .window,
            outputBinding: OutputBinding(primary: .window, sideEffects: [.copyToClipboard]),
            permissions: [.clipboard],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造 `.file` 主输出并带额外 side effect 的测试 Tool。
    private func makeFilePromptToolWithSideEffects() -> Tool {
        Tool(
            id: "file-side-effect.tool",
            name: "File Side Effect Tool",
            icon: "F",
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
            displayMode: .file,
            outputBinding: OutputBinding(
                primary: .file,
                sideEffects: [
                    .appendToFile(path: "/tmp/sliceai-result.md", header: nil),
                    .copyToClipboard
                ]
            ),
            permissions: [.fileWrite(path: "/tmp/sliceai-result.md"), .clipboard],
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
                text: "selected",
                source: .accessibility,
                length: 8,
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

    /// 构造测试 ExecutionEngine。
    private func makeEngine(
        sideEffectExecutor: any SideEffectExecutorProtocol,
        chunks: [ChatChunk]
    ) throws -> ExecutionEngine {
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-side-effect-engine-\(UUID().uuidString).db")
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
            output: MockOutputDispatcher(),
            sideEffectExecutor: sideEffectExecutor
        )
    }

    /// 收集 ExecutionEngine 事件。
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

/// 测试用 clipboard adapter。
private actor SpyClipboardWriter: ClipboardWriting {
    private(set) var writes: [String] = []

    /// 记录写入文本。
    func writeString(_ text: String) async throws {
        writes.append(text)
    }
}

/// 测试用 notification adapter。
private actor SpyNotifier: UserNotifying {
    struct Notification: Sendable, Equatable {
        let title: String
        let body: String
    }

    private(set) var notifications: [Notification] = []

    /// 记录通知请求。
    func notify(title: String, body: String) async throws {
        notifications.append(Notification(title: title, body: body))
    }
}

/// 测试用 speech adapter。
private actor SpySpeechSynthesizer: TextSpeaking {
    struct Call: Sendable, Equatable {
        let text: String
        let voice: String?
    }

    private(set) var calls: [Call] = []

    /// 记录朗读请求。
    func speak(_ text: String, voice: String?) async throws {
        calls.append(Call(text: text, voice: voice))
    }
}

/// 测试用 side effect executor。
private actor RecordingSideEffectExecutor: SideEffectExecutorProtocol {
    struct Call: Sendable, Equatable {
        let sideEffect: SideEffect
        let finalText: String
    }

    private(set) var calls: [Call] = []

    /// 记录调用并返回成功。
    func execute(
        _ sideEffect: SideEffect,
        finalText: String,
        invocationId: UUID
    ) async -> SideEffectExecutionOutcome {
        calls.append(Call(sideEffect: sideEffect, finalText: finalText))
        return .executed
    }
}
