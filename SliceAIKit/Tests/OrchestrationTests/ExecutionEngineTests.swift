import Capabilities
import SliceCore
import XCTest
@testable import Orchestration

/// ExecutionEngine 主流程集成验证（spec §3.4 Step 1-10）
///
/// 覆盖矩阵（与 plan §1648 7 条主路径对齐）：
/// 1. happy —— 全 mock 放行，stream 正常 .started → .llmChunk* → .finished
/// 2. context-fail —— required ContextRequest 失败 → .failed(.context(.requiredFailed))
/// 3. permission-deny —— PermissionBroker.gate 返回 .denied → .failed(.toolPermission(.denied))
/// 4. permission-undeclared —— PermissionGraph 检测出 undeclared → .failed(.toolPermission(.undeclared))
/// 5. dry-run —— seed.isDryRun=true + sideEffect → .sideEffectSkippedDryRun + dryRunCompleted
/// 6. requiresUserConsent (non-dry-run) —— Mock 返回 .requiresUserConsent → .failed(.toolPermission(.notGranted))
/// 7. partial-failure —— 2 个 sideEffect 一通过一拒绝 → success + flags 含 .partialFailure
final class ExecutionEngineTests: XCTestCase {

    // MARK: - Test lifecycle state

    /// 收集本测试类创建过的临时 CostAccounting db 文件 URL。
    /// makeEngine() 每次注册一个 URL，tearDown 统一删除，避免在 NSTemporaryDirectory()
    /// 堆积 sqlite db 文件污染 CI 环境（与 CostAccountingTests 自身的 tearDown 清理对齐）。
    private var tempDbURLs: [URL] = []

    /// 测试方法结束后清理 tempDbURLs：
    /// - 此时 makeEngine() 返回的 ExecutionEngine actor（持有 CostAccounting）通常已是 local
    ///   var 出作用域，ARC 释放后 CostAccounting deinit 关闭 sqlite 句柄；
    /// - 然后再删 db 文件；用 try? 是因为文件可能已不存在（上一轮删掉过 / 测试根本没创建），
    ///   不应导致 tearDown 失败。
    override func tearDown() async throws {
        for url in tempDbURLs {
            try? FileManager.default.removeItem(at: url)
        }
        tempDbURLs.removeAll()
        try await super.tearDown()
    }

    // MARK: - Fixture builders

    /// 构造最小 V2Tool 测试 stub
    /// - Parameters:
    ///   - id: tool id，默认 "test.tool"
    ///   - permissions: tool 静态声明的权限，默认空
    ///   - contexts: PromptTool.contexts，默认空
    ///   - sideEffects: outputBinding.sideEffects；非空时 outputBinding.primary 与 displayMode 同为 .window
    ///   - providerSelection: ProviderSelection；默认 fixed providerId="test-provider"
    private func makeStubTool(
        id: String = "test.tool",
        permissions: [Permission] = [],
        contexts: [ContextRequest] = [],
        sideEffects: [SideEffect] = [],
        providerSelection: ProviderSelection = .fixed(providerId: "test-provider", modelId: nil)
    ) -> V2Tool {
        let outputBinding: OutputBinding? = sideEffects.isEmpty
            ? nil
            : OutputBinding(primary: .window, sideEffects: sideEffects)
        return V2Tool(
            id: id,
            name: "Test Tool",
            icon: "T",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: "system",
                userPrompt: "user {{selection}}",
                contexts: contexts,
                provider: providerSelection,
                temperature: nil,
                maxTokens: nil,
                variables: [:]
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: outputBinding,
            permissions: permissions,
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造最小 ExecutionSeed 测试 stub
    /// - Parameter isDryRun: 是否 dry-run；默认 false
    private func makeStubSeed(isDryRun: Bool = false) -> ExecutionSeed {
        let snapshot = SelectionSnapshot(
            text: "test selection",
            source: .accessibility,
            length: 14,
            language: nil,
            contentType: nil
        )
        let app = AppSnapshot(
            bundleId: "com.test.app",
            name: "Test App",
            url: nil,
            windowTitle: nil
        )
        return ExecutionSeed(
            invocationId: UUID(),
            selection: snapshot,
            frontApp: app,
            screenAnchor: .zero,
            timestamp: Date(),
            triggerSource: .floatingToolbar,
            isDryRun: isDryRun
        )
    }

    /// 参数化的 ExecutionEngine 装配 helper —— 让 7 条用例用单一 helper 配置不同行为。
    ///
    /// 默认行为构成"happy path 全放行"骨架：空 ContextProvider 注册表 + happy MockPermissionBroker +
    /// 默认 V2Provider stub + 空 LLM chunks（PromptExecutor 仍能产出 .completed(.zero)）。
    /// 每条用例按需替换 broker / contextRegistry / resolver / chunks / keychain 等参数。
    ///
    /// - Parameters:
    ///   - broker: PermissionBroker mock；默认全放行
    ///   - resolver: ProviderResolver mock；默认返回 openAI stub
    ///   - contextProviders: ContextProviderRegistry 注册表内容；默认空
    ///   - chunks: MockLLMProvider 流式 chunk 列表；默认空（PromptExecutor 仍 yield .completed(.zero)）
    ///   - keychainStore: MockKeychain 预置 key-value；默认匹配 default provider id（"openai-stub" → "fake-key"）
    ///     注：keychain 的 key 必须与 `MockProviderResolver` 默认返回的 `MockProvider.openAIStub()` 的
    ///     `apiKeyRef = "keychain:openai-stub"` 解析出的 account 一致；不一致会让 PromptExecutor 抛 .unauthorized
    ///   - audit: AuditLog mock；默认空 MockAuditLog
    ///   - output: OutputDispatcher mock；默认 MockOutputDispatcher
    ///   - llmProviderOverride: 测试需要 cancellation / 阻塞行为时注入的自定义 LLMProvider；
    ///     非 nil 时**忽略** `chunks` 并直接走 override。默认 nil → MockLLMProvider(chunks:)。
    /// - Returns: (ExecutionEngine, broker, audit, output, resolver) 元组，便于断言阶段读出注入实例
    private func makeEngine(
        broker: MockPermissionBroker? = nil,
        resolver: MockProviderResolver? = nil,
        contextProviders: [String: any ContextProvider] = [:],
        chunks: [ChatChunk] = [],
        keychainStore: [String: String] = ["openai-stub": "fake-key"],
        audit: MockAuditLog? = nil,
        output: MockOutputDispatcher? = nil,
        llmProviderOverride: (any LLMProvider)? = nil
    ) throws -> (
        engine: ExecutionEngine,
        broker: MockPermissionBroker,
        audit: MockAuditLog,
        output: MockOutputDispatcher,
        resolver: MockProviderResolver
    ) {
        let registry = ContextProviderRegistry(providers: contextProviders)
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-engine-cost-\(UUID().uuidString).db")
        // 先注册到清理列表，再 try CostAccounting init —— 即便 init 失败抛错，
        // 已落盘的临时文件（若有）仍能在 tearDown 中被删除。
        tempDbURLs.append(dbURL)
        let costAccounting = try CostAccounting(dbURL: dbURL)

        let actualBroker = broker ?? MockPermissionBroker()
        let actualResolver = resolver ?? MockProviderResolver()
        let actualAudit = audit ?? MockAuditLog()
        let actualOutput = output ?? MockOutputDispatcher()
        let llmProvider: any LLMProvider = llmProviderOverride ?? MockLLMProvider(chunks: chunks)
        let promptExecutor = PromptExecutor(
            keychain: MockKeychain(keychainStore),
            llmProviderFactory: MockLLMProviderFactory(provider: llmProvider)
        )

        let engine = ExecutionEngine(
            contextCollector: ContextCollector(registry: registry),
            permissionBroker: actualBroker,
            permissionGraph: PermissionGraph(providerRegistry: registry),
            providerResolver: actualResolver,
            promptExecutor: promptExecutor,
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: costAccounting,
            auditLog: actualAudit,
            output: actualOutput
        )
        return (engine, actualBroker, actualAudit, actualOutput, actualResolver)
    }

    /// 顺序消费 stream 收集所有事件（含正常完成 / 抛错路径）。
    /// 由于 ExecutionEngine 主流程的失败路径是"yield .failed + finish()"而**不**抛错，
    /// 测试用 do/catch 包一层防御；正常路径不会进 catch 分支。
    private func collectEvents(
        from stream: AsyncThrowingStream<ExecutionEvent, any Error>
    ) async -> [ExecutionEvent] {
        var collected: [ExecutionEvent] = []
        do {
            for try await event in stream {
                collected.append(event)
            }
        } catch {
            // 主流程不应抛错（统一 yield .failed 后 finish）；进到这里说明实现退化了，让断言失败
            XCTFail("Unexpected stream throw: \(error)")
        }
        return collected
    }

    // MARK: - Tests: Skeleton

    /// 冒烟测试：10-dep init 能正常编译并构造 actor 实例
    func test_init_buildsActorWithAllTenDependencies() async throws {
        let bundle = try makeEngine()
        // actor 构造成功即视为 init 通过；显式 XCTAssertNotNil 让测试意图明确
        // （Swift actor 引用永远非 nil，但断言可读性优于 `_ = engine`，
        //  并避免覆盖率工具把无断言的测试算成"测过"造成假象）
        XCTAssertNotNil(bundle.engine)
    }

    // MARK: - Tests: 7 主路径

    /// 1. happy —— 全 mock 放行 → 收到 .started + .llmChunk(...) + .finished(report)
    func test_execute_happy_yieldsLLMChunksAndFinishesSuccess() async throws {
        let bundle = try makeEngine(
            chunks: [ChatChunk(delta: "Hello", finishReason: nil), ChatChunk(delta: " world", finishReason: nil)]
        )
        let tool = makeStubTool()
        let seed = makeStubSeed()

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        // 事件序列：.started → .llmChunk("Hello") → .llmChunk(" world") → .finished
        XCTAssertEqual(events.count, 4, "happy path should produce 4 events; got: \(events)")
        guard case .started = events.first else {
            XCTFail("event[0] expected .started, got \(events[0])"); return
        }
        guard case .llmChunk(let delta1) = events[1], delta1 == "Hello" else {
            XCTFail("event[1] expected .llmChunk(\"Hello\"), got \(events[1])"); return
        }
        guard case .llmChunk(let delta2) = events[2], delta2 == " world" else {
            XCTFail("event[2] expected .llmChunk(\" world\"), got \(events[2])"); return
        }
        guard case .finished(let report) = events[3] else {
            XCTFail("event[3] expected .finished, got \(events[3])"); return
        }
        XCTAssertEqual(report.outcome, .success)
        XCTAssertTrue(report.flags.isEmpty, "happy path should have no flags")

        // audit 必须恰有 1 条 .invocationCompleted
        let entries = await bundle.audit.entries
        XCTAssertEqual(entries.count, 1)
        guard case .invocationCompleted(let auditReport) = entries[0] else {
            XCTFail("audit[0] expected .invocationCompleted, got \(entries[0])"); return
        }
        XCTAssertEqual(auditReport.outcome, .success)
    }

    /// 2. context-fail —— required ContextRequest 失败 → .failed(.context(.requiredFailed))
    func test_execute_contextFail_yieldsFailedAndAuditsContext() async throws {
        // 注入一个 always-fail 的 provider；用 required 触发主流程中止
        let providerName = "fail.provider"
        let providerError = SliceError.provider(.networkTimeout)  // 任意 SliceError，会被 collector 包装为 requiredFailed
        let providers: [String: any ContextProvider] = [
            providerName: MockFailureProvider(name: providerName, error: providerError)
        ]
        let bundle = try makeEngine(contextProviders: providers)
        let tool = makeStubTool(
            contexts: [ContextRequest(
                key: ContextKey(rawValue: "ctx.fail"),
                provider: providerName,
                args: [:],
                cachePolicy: .none,
                requiredness: .required
            )]
        )
        let seed = makeStubSeed()

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        // 事件序列：.started → .failed(.context(.requiredFailed))
        XCTAssertEqual(events.count, 2, "context-fail path should produce 2 events; got: \(events)")
        guard case .failed(let error) = events[1] else {
            XCTFail("event[1] expected .failed, got \(events[1])"); return
        }
        guard case .context(.requiredFailed(let key, _)) = error else {
            XCTFail("error should be .context(.requiredFailed), got \(error)"); return
        }
        XCTAssertEqual(key.rawValue, "ctx.fail")

        // audit 必须恰有 1 条 .invocationCompleted(failed: .context)
        let entries = await bundle.audit.entries
        XCTAssertEqual(entries.count, 1)
        guard case .invocationCompleted(let auditReport) = entries[0] else {
            XCTFail("audit[0] expected .invocationCompleted, got \(entries[0])"); return
        }
        XCTAssertEqual(auditReport.outcome, .failed(errorKind: .context))
    }

    /// 3. permission-deny —— MockPermissionBroker.gate 返回 .denied → .failed(.toolPermission(.denied))
    func test_execute_permissionDeny_yieldsFailedAndAuditsToolPermission() async throws {
        let denyReason = "blacklisted host"
        let denyPermission = Permission.network(host: "example.com")
        let broker = MockPermissionBroker(
            outcomeOverride: .denied(permission: denyPermission, reason: denyReason)
        )
        let bundle = try makeEngine(broker: broker)
        let tool = makeStubTool()
        let seed = makeStubSeed()

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        // 事件序列：.started → .failed(.toolPermission(.denied))
        XCTAssertEqual(events.count, 2)
        guard case .failed(let error) = events[1] else {
            XCTFail("event[1] expected .failed, got \(events[1])"); return
        }
        guard case .toolPermission(.denied(let permission, let reason)) = error else {
            XCTFail("error should be .toolPermission(.denied), got \(error)"); return
        }
        XCTAssertEqual(permission, denyPermission)
        XCTAssertEqual(reason, denyReason)

        let entries = await bundle.audit.entries
        XCTAssertEqual(entries.count, 1)
        guard case .invocationCompleted(let auditReport) = entries[0] else {
            XCTFail("audit[0] expected .invocationCompleted, got \(entries[0])"); return
        }
        XCTAssertEqual(auditReport.outcome, .failed(errorKind: .toolPermission))
    }

    /// 4. permission-undeclared —— ContextRequest 引用某 ContextProvider 推导出权限，但 tool.permissions 为空
    /// → PermissionGraph 检测出 undeclared → .failed(.toolPermission(.undeclared))
    func test_execute_permissionUndeclared_yieldsFailedWithMissingSet() async throws {
        // 自定义 ContextProvider：inferredPermissions 返回 .fileRead；resolve 不会被调到（前面就拦了）
        let providerName = "undeclared.provider"
        let providers: [String: any ContextProvider] = [
            providerName: UndeclaredFileReadProvider(name: providerName)
        ]
        let bundle = try makeEngine(contextProviders: providers)
        // tool.permissions 故意为空 —— PermissionGraph.compute 会算出 undeclared = {.fileRead("/tmp/x")}
        let tool = makeStubTool(
            permissions: [],
            contexts: [ContextRequest(
                key: ContextKey(rawValue: "ctx.file"),
                provider: providerName,
                args: ["path": "/tmp/x"],
                cachePolicy: .none,
                requiredness: .optional  // optional 也会触发 inferredPermissions 聚合
            )]
        )
        let seed = makeStubSeed()

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        // 事件序列：.started → .failed(.toolPermission(.undeclared))
        XCTAssertEqual(events.count, 2)
        guard case .failed(let error) = events[1] else {
            XCTFail("event[1] expected .failed, got \(events[1])"); return
        }
        guard case .toolPermission(.undeclared(let missing)) = error else {
            XCTFail("error should be .toolPermission(.undeclared), got \(error)"); return
        }
        XCTAssertEqual(missing, [.fileRead(path: "/tmp/x")])

        let entries = await bundle.audit.entries
        XCTAssertEqual(entries.count, 1)
        guard case .invocationCompleted(let auditReport) = entries[0] else {
            XCTFail("audit[0] expected .invocationCompleted, got \(entries[0])"); return
        }
        XCTAssertEqual(auditReport.outcome, .failed(errorKind: .toolPermission))
    }

    /// 5. dry-run —— seed.isDryRun=true + sideEffect → .sideEffectSkippedDryRun + dryRunCompleted
    func test_execute_dryRun_skipsSideEffectsAndAuditsDryRunCompleted() async throws {
        let bundle = try makeEngine(
            chunks: [ChatChunk(delta: "ok", finishReason: nil)]
        )
        let sideEffect = SideEffect.copyToClipboard
        // tool.permissions 显式包含 .clipboard，让 PermissionGraph 闭环通过
        let tool = makeStubTool(
            permissions: [.clipboard],
            sideEffects: [sideEffect]
        )
        let seed = makeStubSeed(isDryRun: true)

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        // 事件流：.started → .llmChunk("ok") → .sideEffectSkippedDryRun → .finished
        guard let last = events.last, case .finished(let report) = last else {
            XCTFail("last event expected .finished, got \(events)"); return
        }
        XCTAssertEqual(report.outcome, .dryRunCompleted)
        XCTAssertTrue(report.flags.contains(.dryRun), "dry-run report should include .dryRun flag")

        // 必须出现 .sideEffectSkippedDryRun，且**不**出现 .sideEffectTriggered
        var skippedFound = false
        for event in events {
            if case .sideEffectSkippedDryRun = event { skippedFound = true }
            if case .sideEffectTriggered = event {
                XCTFail("dry-run should NOT yield .sideEffectTriggered, got \(event)"); return
            }
        }
        XCTAssertTrue(skippedFound, "dry-run should yield .sideEffectSkippedDryRun")

        // audit 仅 1 条 .invocationCompleted（dry-run skipped sideEffect 不写 audit）
        let entries = await bundle.audit.entries
        XCTAssertEqual(entries.count, 1)
        guard case .invocationCompleted(let auditReport) = entries[0] else {
            XCTFail("audit[0] expected .invocationCompleted, got \(entries[0])"); return
        }
        XCTAssertEqual(auditReport.outcome, .dryRunCompleted)
    }

    /// 6. requiresUserConsent (non-dry-run) —— Mock 返回 .requiresUserConsent → .failed(.toolPermission(.notGranted))
    func test_execute_requiresUserConsentNonDryRun_yieldsFailedNotGranted() async throws {
        let permission = Permission.network(host: "example.com")
        let broker = MockPermissionBroker(
            outcomeOverride: .requiresUserConsent(permission: permission, uxHint: "Need to ask user")
        )
        let bundle = try makeEngine(broker: broker)
        let tool = makeStubTool()
        let seed = makeStubSeed(isDryRun: false)

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        XCTAssertEqual(events.count, 2)
        guard case .failed(let error) = events[1] else {
            XCTFail("event[1] expected .failed, got \(events[1])"); return
        }
        guard case .toolPermission(.notGranted(let p)) = error else {
            XCTFail("error should be .toolPermission(.notGranted), got \(error)"); return
        }
        XCTAssertEqual(p, permission)

        let entries = await bundle.audit.entries
        XCTAssertEqual(entries.count, 1)
        guard case .invocationCompleted(let auditReport) = entries[0] else {
            XCTFail("audit[0] expected .invocationCompleted, got \(entries[0])"); return
        }
        XCTAssertEqual(auditReport.outcome, .failed(errorKind: .toolPermission))
    }

    /// 7. partial-failure —— 2 个 sideEffects，第 1 个 approved + 第 2 个 denied
    /// → finishSuccess + flags 含 .partialFailure；audit 同步含 .partialFailure
    func test_execute_partialFailure_finishesSuccessWithFlag() async throws {
        // broker.gate 调用顺序：
        //   call 0 = Step 2.5 整体 effective gate → approved
        //   call 1 = sideEffect[0]（copyToClipboard）→ approved
        //   call 2 = sideEffect[1]（notify）→ denied
        let broker = MockPermissionBroker(
            outcomeFunction: { callIndex, _, _, _, _ in
                if callIndex >= 2 {
                    return .denied(
                        permission: .network(host: "blocked"),
                        reason: "second sideEffect denied"
                    )
                }
                return .approved
            }
        )
        let bundle = try makeEngine(
            broker: broker,
            chunks: [ChatChunk(delta: "ok", finishReason: nil)]
        )
        let sideEffect1 = SideEffect.copyToClipboard
        // .notify 的 inferredPermissions 是空集 —— 让 broker 的"按 callIndex 区分"逻辑起作用
        // 而不依赖 effective set 的具体内容
        let sideEffect2 = SideEffect.notify(title: "T", body: "B")
        let tool = makeStubTool(
            permissions: [.clipboard],  // sideEffect1.inferredPermissions = [.clipboard]
            sideEffects: [sideEffect1, sideEffect2]
        )
        let seed = makeStubSeed(isDryRun: false)

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        // 终态必须是 .finished（不是 .failed），且 flags 含 .partialFailure
        guard let last = events.last, case .finished(let report) = last else {
            XCTFail("last event expected .finished, got \(events)"); return
        }
        XCTAssertEqual(report.outcome, .success)
        XCTAssertTrue(report.flags.contains(.partialFailure),
                      "partial-failure report should include .partialFailure flag; flags=\(report.flags)")

        // 必须出现 .sideEffectTriggered（第 1 个），但不应该出现 .sideEffectSkippedDryRun（非 dry-run）
        var triggeredCount = 0
        for event in events {
            if case .sideEffectTriggered = event { triggeredCount += 1 }
            if case .sideEffectSkippedDryRun = event {
                XCTFail("non-dry-run should NOT yield .sideEffectSkippedDryRun, got \(event)"); return
            }
        }
        XCTAssertEqual(triggeredCount, 1, "exactly one sideEffect should be triggered before deny")

        // audit 主条目（.invocationCompleted）+ 1 条 sideEffectTriggered（仅第一个 sideEffect 实际执行写 audit）
        let entries = await bundle.audit.entries
        XCTAssertEqual(entries.count, 2, "audit should contain 1 invocationCompleted + 1 sideEffectTriggered")
        guard case .sideEffectTriggered = entries[0] else {
            XCTFail("audit[0] expected .sideEffectTriggered, got \(entries[0])"); return
        }
        guard case .invocationCompleted(let auditReport) = entries[1] else {
            XCTFail("audit[1] expected .invocationCompleted, got \(entries[1])"); return
        }
        XCTAssertEqual(auditReport.outcome, .success)
        XCTAssertTrue(auditReport.flags.contains(.partialFailure))
    }

    // MARK: - ToolKind 分流（M2 stub 路径）

    /// .agent ToolKind 在 M2 应直接 `finishNotImplementedKind` (stub success)，
    /// 不应跑 Step 3 ContextCollector + Step 4 ProviderResolver。
    /// ToolKind 分流提前到 Step 2.5 之后：分流前 .agent 仍会浪费一次 ProviderResolver
    /// 调用 + 触发 ContextCollector 预执行（Phase 1 真实 ContextProvider 会做 fileRead/MCP IO）。
    func test_execute_agentKind_skipsContextAndProviderResolution_yieldsNotImplementedSuccess() async throws {
        let bundle = try makeEngine()
        let agentTool = V2Tool(
            id: "tool.agent",
            name: "Agent",
            icon: "A",
            description: nil,
            kind: .agent(AgentTool(
                systemPrompt: "agent system",
                initialUserPrompt: "user",
                contexts: [],
                provider: .fixed(providerId: "test-provider", modelId: nil),
                skill: nil,
                mcpAllowlist: [],
                builtinCapabilities: [],
                maxSteps: 5,
                stopCondition: .maxStepsReached
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
        let seed = makeStubSeed()

        let events = await collectEvents(from: bundle.engine.execute(tool: agentTool, seed: seed))

        // 事件序列：.started → .notImplemented → .finished(stub success)
        XCTAssertEqual(events.count, 3, ".agent stub path 应只有 3 个事件; got: \(events)")
        guard case .started = events[0] else {
            XCTFail("event[0] expected .started, got \(events[0])"); return
        }
        guard case .notImplemented = events[1] else {
            XCTFail("event[1] expected .notImplemented, got \(events[1])"); return
        }
        guard case .finished(let report) = events[2] else {
            XCTFail("event[2] expected .finished, got \(events[2])"); return
        }
        XCTAssertEqual(report.outcome, .success, ".agent stub 应是 .success，避免下游 UI 当 .failed 处理")

        // 关键断言：ProviderResolver 没被调（fix 前 .agent 会有 1 次浪费调用）
        let resolverCalls = await bundle.resolver.resolveCalls
        XCTAssertEqual(resolverCalls, 0,
                       ".agent kind 不应触发 ProviderResolver；fix 前会浪费 1 次调用")
    }

    /// .pipeline ToolKind 同样应直接 `finishNotImplementedKind`。
    /// **关键**：fix 前 .pipeline 路径会跑 ProviderResolver 用 fake `<pipeline-default>`
    /// providerId → 抛 ProviderResolutionError.notFound → finishFailure 写
    /// `.failed(.configuration(.referencedProviderMissing))` audit；这违反 spec M2 stub
    /// 语义（应是 stub success + .notImplemented event）。fix 后直接分流 → .success audit。
    func test_execute_pipelineKind_skipsProviderResolution_yieldsNotImplementedSuccessNotProviderMissing() async throws {
        let bundle = try makeEngine()
        let pipelineTool = V2Tool(
            id: "tool.pipeline",
            name: "Pipeline",
            icon: "P",
            description: nil,
            kind: .pipeline(PipelineTool(steps: [], onStepFail: .abort)),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
        let seed = makeStubSeed()

        let events = await collectEvents(from: bundle.engine.execute(tool: pipelineTool, seed: seed))

        // 事件序列：.started → .notImplemented → .finished(stub success)
        XCTAssertEqual(events.count, 3, ".pipeline stub path 应只有 3 个事件; got: \(events)")
        guard case .finished(let report) = events.last else {
            XCTFail("last event expected .finished, got \(events)"); return
        }
        XCTAssertEqual(report.outcome, .success,
                       "fix 前 outcome=.failed(.configuration(.referencedProviderMissing)); fix 后应 .success")

        // 关键断言：ProviderResolver 没被调（fix 前会用 <pipeline-default> 触发 1 次调用 + 抛 .notFound）
        let resolverCalls = await bundle.resolver.resolveCalls
        XCTAssertEqual(resolverCalls, 0,
                       ".pipeline kind 不应触发 ProviderResolver；fix 前用 <pipeline-default> 抛 .notFound")

        // audit 主条目应是 .invocationCompleted(.success)，不是 .failed
        let entries = await bundle.audit.entries
        XCTAssertEqual(entries.count, 1, "expected 1 audit entry; got \(entries.count)")
        guard case .invocationCompleted(let auditReport) = entries[0] else {
            XCTFail("audit[0] expected .invocationCompleted, got \(entries[0])"); return
        }
        XCTAssertEqual(auditReport.outcome, .success,
                       "fix 前 audit outcome=.failed.configuration; fix 后应 .success")
    }

    // MARK: - 跨流追踪 / 取消语义补充用例

    /// invocationId 一致性回归：seed.invocationId 必须贯穿
    /// `.started(invocationId:)` / `.finished(report).invocationId` /
    /// `audit .invocationCompleted(report).invocationId` 三个链路出口。
    ///
    /// `ExecutionSeed.invocationId` 文档明确"贯穿日志的追踪 id；同一次划词/快捷键触发只生成一次"。
    /// 早期实现用 `UUID()` 自生成新 id，导致触发层日志（按 seed id 索引）与执行链 audit /
    /// cost 记录（按引擎自生 id）查不到对应——M3 接 UI 后做事故追踪 / 取消路由 / 窗口路由会断链。
    func test_execute_invocationIdMatchesSeed_acrossEventsAndAudit() async throws {
        let bundle = try makeEngine(
            chunks: [ChatChunk(delta: "ok", finishReason: nil)]
        )
        let tool = makeStubTool()
        let seed = makeStubSeed()
        let expectedId = seed.invocationId

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        // .started 的 invocationId 必须等于 seed.invocationId
        guard case .started(let startedId) = events.first else {
            XCTFail("event[0] expected .started, got \(events.first as Any)"); return
        }
        XCTAssertEqual(startedId, expectedId,
                       ".started invocationId must equal seed.invocationId")

        // .finished(report) 的 report.invocationId 也必须等于 seed.invocationId
        guard case .finished(let report) = events.last else {
            XCTFail("last event expected .finished, got \(events.last as Any)"); return
        }
        XCTAssertEqual(report.invocationId, expectedId,
                       "InvocationReport.invocationId must equal seed.invocationId")

        // audit 的 .invocationCompleted(report) 也必须用同一 id
        let entries = await bundle.audit.entries
        guard let auditTail = entries.last,
              case .invocationCompleted(let auditReport) = auditTail else {
            XCTFail("audit last entry expected .invocationCompleted, got \(entries.last as Any)"); return
        }
        XCTAssertEqual(auditReport.invocationId, expectedId,
                       "audit InvocationReport.invocationId must equal seed.invocationId")
    }

    /// ProviderSelection.fixed.modelId 必须同时贯穿 LLM ChatRequest.model 与 CostRecord.model——
    /// 否则"请求模型"与"记账模型"会漂移；与 v1 ToolExecutor 同口径
    /// （`tool.modelId ?? provider.defaultModel`），M3 切换不应静默换模型。
    /// 直接构造 Engine（不走 makeEngine）以便保留 CostAccounting / MockLLMProviderFactory 句柄做断言。
    func test_execute_modelOverride_propagatesToBothChatRequestAndCostRecord() async throws {
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "ok", finishReason: .stop)])
        let factory = MockLLMProviderFactory(provider: llm)
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-engine-modelid-\(UUID().uuidString).db")
        tempDbURLs.append(dbURL)
        let costAccounting = try CostAccounting(dbURL: dbURL)
        let registry = ContextProviderRegistry(providers: [:])
        let promptExecutor = PromptExecutor(
            keychain: MockKeychain(["test-provider": "fake-key"]),
            llmProviderFactory: factory
        )
        // resolver 返回 V2Provider.defaultModel="gpt-4o-mini"；工具级 ProviderSelection 用
        // modelId="gpt-4-turbo" override；断言两侧 model 都是 turbo
        let resolver = MockProviderResolver(
            defaultProvider: MockProvider.openAIStub(id: "test-provider", defaultModel: "gpt-4o-mini")
        )
        let audit = MockAuditLog()
        let output = MockOutputDispatcher()
        let broker = MockPermissionBroker()

        let engine = ExecutionEngine(
            contextCollector: ContextCollector(registry: registry),
            permissionBroker: broker,
            permissionGraph: PermissionGraph(providerRegistry: registry),
            providerResolver: resolver,
            promptExecutor: promptExecutor,
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: costAccounting,
            auditLog: audit,
            output: output
        )
        // 工具级 modelId override
        let tool = V2Tool(
            id: "tool.modelOverride",
            name: "Override",
            icon: "M",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: "system",
                userPrompt: "user {{selection}}",
                contexts: [],
                provider: .fixed(providerId: "test-provider", modelId: "gpt-4-turbo"),
                temperature: nil,
                maxTokens: nil,
                variables: [:]
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
        let seed = makeStubSeed()

        let events = await collectEvents(from: engine.execute(tool: tool, seed: seed))

        guard let last = events.last, case .finished = last else {
            XCTFail("expected .finished, got \(events)"); return
        }

        // ① ChatRequest.model 必须用 override
        guard let request = llm.capturedRequest else {
            XCTFail("MockLLMProvider 未捕获 ChatRequest"); return
        }
        XCTAssertEqual(request.model, "gpt-4-turbo",
                       "ChatRequest.model 必须用 ProviderSelection.fixed.modelId override")

        // ② CostRecord.model 也必须用 override —— 不能因 Engine 写记录时回到 provider.defaultModel
        let records = try await costAccounting.findByToolId("tool.modelOverride")
        XCTAssertEqual(records.count, 1, "expected 1 cost record; got \(records.count)")
        XCTAssertEqual(records.first?.model, "gpt-4-turbo",
                       "CostRecord.model 必须用 ProviderSelection.fixed.modelId override，与 ChatRequest 同源")
    }

    /// 早取消（Early-cancel）：consumer 收到 `.started` 后立即 break，不应再启动
    /// Keychain / LLM 等下游昂贵动作。
    ///
    /// runMainFlow 在每个 await 边界都显式 `Task.isCancelled` 短路；如果只在 sideEffects
    /// 边界短路，pre-LLM 阶段会浪费 keychain / 网络资源。
    ///
    /// **测试机理**：mock 全 sync 时 actor 上没有真实让出点，cancel 信号无传导窗口；
    /// 注入 `YieldingMockProviderResolver` 在 ProviderResolver.resolve 内显式 `Task.yield()`，
    /// 模拟生产环境的真实异步 IO，让 onTermination 触发的 cancel signal 在 Step 4 让出
    /// 期间到达；Step 4 之后 `if Task.isCancelled { return }` 捕获并 return，
    /// PromptExecutor 不被调用。
    ///
    /// 关键断言：
    /// - audit.entries 应为空（无 .invocationCompleted）；
    /// - llm.capturedRequest 应仍为 nil（LLM stream 从未被发起）。
    func test_execute_earlyCancellationAfterStarted_skipsLLMStreamAndAudit() async throws {
        // chunks 故意非空：一旦 LLM 真被调到，capturedRequest 会被写入 → 测试失败可被察觉
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "should-not-stream", finishReason: .stop)])
        // 直接 inline 构造 engine —— makeEngine 仅接受 MockProviderResolver；
        // 这里需要 YieldingMockProviderResolver 引入真实 await 让出点
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-engine-earlycancel-\(UUID().uuidString).db")
        tempDbURLs.append(dbURL)
        let costAccounting = try CostAccounting(dbURL: dbURL)
        let registry = ContextProviderRegistry(providers: [:])
        let promptExecutor = PromptExecutor(
            keychain: MockKeychain(["openai-stub": "fake-key"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )
        let audit = MockAuditLog()
        let resolver = YieldingMockProviderResolver()

        let engine = ExecutionEngine(
            contextCollector: ContextCollector(registry: registry),
            permissionBroker: MockPermissionBroker(),
            permissionGraph: PermissionGraph(providerRegistry: registry),
            providerResolver: resolver,
            promptExecutor: promptExecutor,
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: costAccounting,
            auditLog: audit,
            output: MockOutputDispatcher()
        )
        let tool = makeStubTool()
        let seed = makeStubSeed()

        // 关键：stream 必须**仅**被 consumer task 持有；如果 main test func 也持引用，
        // consumer break 后 stream var 仍存活，AsyncThrowingStream onTermination 不触发，
        // cancel cascade 链路断 → audit/LLM 仍写。把 execute 调用 inline 进 consumer
        // task body 让 stream 仅 consumer 持有 → consumer return → stream deinit →
        // onTermination → task.cancel() → runMainFlow 在 isCancelled check 处 return
        let consumerTask = Task<[ExecutionEvent], Never> {
            let stream = engine.execute(tool: tool, seed: seed)
            var events: [ExecutionEvent] = []
            do {
                for try await event in stream {
                    events.append(event)
                    if case .started = event { break }
                }
            } catch {
                // 任何 catch（含 CancellationError）都视为消费结束
            }
            return events
        }

        let collected = await consumerTask.value
        XCTAssertEqual(collected.count, 1, "consumer should observe .started only; got=\(collected)")
        guard case .started = collected.first else {
            XCTFail("event[0] expected .started, got \(collected)"); return
        }

        // 等待 cancellation 完整传导：onTermination → task.cancel() → runMainFlow 在
        // 下一个 isCancelled 检查处 return；300ms 是 actor hop 安全上界，CI 抖动一般 < 100ms
        try? await Task.sleep(nanoseconds: 300_000_000)

        // ① audit 必须为空 —— early-cancel 不应写任何 .invocationCompleted
        let entries = await audit.entries
        XCTAssertTrue(entries.isEmpty,
                      "early-cancelled invocation must NOT write audit; got=\(entries)")

        // ② LLM stream 必须从未被发起 —— capturedRequest 仍为 nil
        XCTAssertNil(llm.capturedRequest,
                     "early-cancelled invocation must NOT initiate LLM stream; got=\(String(describing: llm.capturedRequest))")
    }

    /// stream cancellation 必须传导到内部 Task：consumer drop iterator → execute() 的
    /// `continuation.onTermination` 触发 → engine 内部 task.cancel() →
    /// runPromptStream 在 for-await 上抛 CancellationError → 静默 return nil →
    /// runMainFlow 的 `guard ... else { return }` 退出 → **不**写 success audit、**不**触发 sideEffects。
    ///
    /// 关键安全保证：用户关闭结果面板（M3 ResultPanel onDismiss）后，LLM 续流 / 写文件 /
    /// 通知等不可逆副作用不再发生。等价于 v0.1 中 `streamTask.cancel()` 的语义在 V2 链路上保持一致。
    func test_execute_consumerCancellation_skipsSideEffectsAndSuccessAudit() async throws {
        // BlockingMockLLMProvider yield 一个 chunk 后阻塞 sleep；consumer cancel 时
        // 通过 onTermination 链传导，runPromptStream 抛 CancellationError 被新增 catch 拿下
        let blocking = BlockingMockLLMProvider(
            initialChunk: ChatChunk(delta: "first", finishReason: nil)
        )
        let bundle = try makeEngine(
            llmProviderOverride: blocking
        )
        // declare .clipboard 让 PermissionGraph 闭环通过；sideEffect 用 copyToClipboard 验证"被跳过"
        let tool = makeStubTool(
            permissions: [.clipboard],
            sideEffects: [.copyToClipboard]
        )
        let seed = makeStubSeed()

        let stream = bundle.engine.execute(tool: tool, seed: seed)

        // consumer 消费到第一个 .llmChunk 后 break；break 让 for-await 退出 → 隐式 iterator 释放 →
        // continuation.onTermination → engine 内部 task.cancel()
        let consumerTask = Task<[ExecutionEvent], Never> {
            var events: [ExecutionEvent] = []
            do {
                for try await event in stream {
                    events.append(event)
                    if case .llmChunk = event { break }
                }
            } catch {
                // 任何 catch（含 CancellationError）都视为消费结束，不影响测试断言
            }
            return events
        }

        let collected = await consumerTask.value
        // 至少看到 .started + 一条 .llmChunk
        XCTAssertGreaterThanOrEqual(collected.count, 2,
                                    "consumer should observe .started + first .llmChunk before cancel; got=\(collected)")

        // 等待 cancellation 完整传导：runPromptStream catch CancellationError → return nil → runMainFlow 退出
        // 300 ms 是 actor hop + AsyncThrowingStream cancellation 传播的安全上界；CI 抖动一般 < 100ms
        try? await Task.sleep(nanoseconds: 300_000_000)

        let entries = await bundle.audit.entries
        let hasCompleted = entries.contains { entry in
            if case .invocationCompleted = entry { return true }
            return false
        }
        let hasSideEffect = entries.contains { entry in
            if case .sideEffectTriggered = entry { return true }
            return false
        }

        XCTAssertFalse(hasCompleted,
                       "cancelled invocation must NOT write .invocationCompleted; got=\(entries)")
        XCTAssertFalse(hasSideEffect,
                       "cancelled invocation must NOT trigger sideEffect; got=\(entries)")
    }

    /// ContextCollector 解析途中取消：consumer drop stream → onTermination → task.cancel() →
    /// child task 内部 Task.sleep / raceWithTimeout 抛 CancellationError →
    /// ContextCollector.runOne 透传（不分类为 requiredFailure）→ withThrowingTaskGroup
    /// 整体 throw CancellationError → ExecutionEngine.runContextCollection 的
    /// `catch is CancellationError { return nil }` 静默退出 → 不写 audit、不进 ProviderResolver、
    /// 不调 LLMProvider。
    ///
    /// 反例：若 runOne 把 CancellationError 包装为 `.context(.requiredFailed)`，
    /// 上层会当业务失败 → 写 `.failed(.context)` audit + yield `.failed`，
    /// 与"取消静默退出"语义冲突。当前实现 cancellation 全程透传。
    func test_execute_cancellationDuringContextCollection_skipsAuditAndLLM() async throws {
        // CancellableContextProvider.resolve 内 Task.sleep 5s；
        // consumer break 触发的 cancel cascade 让 sleep 抛 CancellationError
        let provider = CancellableContextProvider()
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "should-not-stream", finishReason: .stop)])

        let bundle = try makeEngine(
            contextProviders: ["test.cancellable": provider],
            llmProviderOverride: llm
        )

        // tool 声明 1 个 required ContextRequest 指向 cancellable provider
        let req = ContextRequest(
            key: ContextKey(rawValue: "ctx"),
            provider: "test.cancellable",
            args: [:],
            cachePolicy: .none,
            requiredness: .required
        )
        let tool = makeStubTool(contexts: [req])
        let seed = makeStubSeed()

        // stream 必须仅 consumer 持有；否则 break 后 stream 仍存活，
        // onTermination 不触发，cancel cascade 链路断（参见 earlyCancel 测试同源说明）
        let consumerTask = Task<[ExecutionEvent], Never> {
            let stream = bundle.engine.execute(tool: tool, seed: seed)
            var events: [ExecutionEvent] = []
            do {
                for try await event in stream {
                    events.append(event)
                    if case .started = event { break }
                }
            } catch {
                // 任何 catch（含 CancellationError）都视为消费结束
            }
            return events
        }

        let collected = await consumerTask.value
        XCTAssertEqual(collected.count, 1, "consumer should observe .started only; got=\(collected)")
        guard case .started = collected.first else {
            XCTFail("event[0] expected .started, got \(collected)"); return
        }

        // 等待 cancellation 完整传导：onTermination → task.cancel() → ContextCollector child task
        // 内 Task.sleep 抛 CancellationError → group throw → runContextCollection catch → return nil
        try? await Task.sleep(nanoseconds: 300_000_000)

        // ① audit 必须为空 —— cancel 静默退出绝不能写 .invocationCompleted (尤其不能 .failed(.context))
        let entries = await bundle.audit.entries
        XCTAssertTrue(entries.isEmpty,
                      "cancelled-during-context invocation must NOT write audit; got=\(entries)")

        // ② LLM stream 必须从未被发起 —— ContextCollector 抛 CancellationError 后主流程提前退出
        XCTAssertNil(llm.capturedRequest,
                     "cancelled-during-context invocation must NOT initiate LLM stream; got=\(String(describing: llm.capturedRequest))")
    }

    /// PermissionGate 期间取消：consumer drop stream → onTermination → task.cancel() →
    /// runPermissionGate 内 broker.gate yields 让出 cooperative thread → 后续 isCancelled
    /// 短路 → 跳过 finishFailure → 不写 .failed(.toolPermission) audit、不进入后续 step。
    ///
    /// 反例：若 broker 返回 .denied/.requiresUserConsent 时直接 finishFailure，会在 audit 留下
    /// 取消后才发生的 .failed 记录，与"取消静默退出"语义冲突。当前实现 gate await 后
    /// 显式 `Task.isCancelled` 短路。
    func test_execute_cancellationDuringPermissionGate_skipsAuditAndLLM() async throws {
        // YieldingMockPermissionBroker 在 gate 内 Task.yield()，让 cancel cascade 在
        // 此 await 边界落地；outcome=.denied 模拟"如果不查 cancel 就会 finishFailure"的最坏情况
        let broker = YieldingMockPermissionBroker(
            outcomeOverride: .denied(permission: .clipboard, reason: "test deny")
        )
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "should-not-stream", finishReason: .stop)])

        let bundle = try makeEngine(
            broker: nil,  // 用下方 inline 装配 engine 替代 (makeEngine 仅接受 MockPermissionBroker)
            llmProviderOverride: llm
        )
        // 由于 makeEngine 强类型 broker: MockPermissionBroker?，需要为本测试单独装配 engine
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-engine-permcancel-\(UUID().uuidString).db")
        tempDbURLs.append(dbURL)
        let costAccounting = try CostAccounting(dbURL: dbURL)
        let registry = ContextProviderRegistry(providers: [:])
        let promptExecutor = PromptExecutor(
            keychain: MockKeychain(["openai-stub": "fake-key"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )
        let audit = MockAuditLog()
        let engine = ExecutionEngine(
            contextCollector: ContextCollector(registry: registry),
            permissionBroker: broker,
            permissionGraph: PermissionGraph(providerRegistry: registry),
            providerResolver: MockProviderResolver(),
            promptExecutor: promptExecutor,
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: costAccounting,
            auditLog: audit,
            output: MockOutputDispatcher()
        )

        // declare .clipboard 让 PermissionGraph compute pass；gate 才会被调用并 yield
        let tool = makeStubTool(permissions: [.clipboard])
        let seed = makeStubSeed()
        _ = bundle  // 仅为消费 makeEngine 的清理资源；engine 实际用 inline 装配的版本

        // stream 必须仅 consumer 持有；inline execute → consumer return → stream deinit → onTermination
        let consumerTask = Task<[ExecutionEvent], Never> {
            let stream = engine.execute(tool: tool, seed: seed)
            var events: [ExecutionEvent] = []
            do {
                for try await event in stream {
                    events.append(event)
                    if case .started = event { break }
                }
            } catch {
                // 任何 catch（含 CancellationError）都视为消费结束
            }
            return events
        }

        let collected = await consumerTask.value
        XCTAssertEqual(collected.count, 1, "consumer should observe .started only; got=\(collected)")
        guard case .started = collected.first else {
            XCTFail("event[0] expected .started, got \(collected)"); return
        }

        // 等待 cancellation 完整传导：consumer break → onTermination → task.cancel() →
        // broker.gate yield 后 Task.isCancelled=true → runPermissionGate return false → runMainFlow return
        try? await Task.sleep(nanoseconds: 300_000_000)

        // 关键断言：audit 为空 —— 取消 + .denied 不应组合出 .failed(.toolPermission(.denied)) audit
        let entries = await audit.entries
        XCTAssertTrue(entries.isEmpty,
                      "cancelled-during-permissionGate invocation must NOT write audit; got=\(entries)")
        XCTAssertNil(llm.capturedRequest,
                     "cancelled-during-permissionGate invocation must NOT initiate LLM stream; got=\(String(describing: llm.capturedRequest))")
    }

    /// PromptStream 完成后 sideEffects/cost 阶段取消：cancel 在 sideEffect gate yield /
    /// recordCost 之间到达时，**不应**写 .invocationCompleted(success) audit。
    ///
    /// 反例：若 runSideEffects 不查 cancel 会 yield .sideEffectTriggered + 写 audit；
    /// runPromptKindPipeline 不查 cancel 会跑 recordCostAndFinishSuccess → 写 .invocationCompleted；
    /// recordCostAndFinishSuccess 不查 cancel 会在 cost.record 后仍 finishSuccess。
    /// 当前实现：sideEffect 循环入口 + gate 后 + sideEffects 出口 + cost.record 后均显式 isCancelled 短路。
    func test_execute_cancellationDuringSideEffects_skipsCostAndCompletedAudit() async throws {
        // sync MockLLMProvider：1 chunk + finish；让 PromptStream 完成快进入 sideEffects
        let llm = MockLLMProvider(chunks: [ChatChunk(delta: "ok", finishReason: .stop)])
        // YieldingMockPermissionBroker：每次 gate 都 Task.yield() —— Step 7 sideEffect gate
        // yield 时给 consumer 调度窗口，cancel cascade 在 await 边界落地
        let broker = YieldingMockPermissionBroker(outcomeOverride: nil)  // nil → .approved

        // declare .clipboard + 多个 .copyToClipboard sideEffect：让循环跑数轮、增加 cancel 落地概率
        let tool = makeStubTool(
            permissions: [.clipboard],
            sideEffects: [.copyToClipboard, .copyToClipboard, .copyToClipboard]
        )
        let seed = makeStubSeed()

        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-engine-sidefxcancel-\(UUID().uuidString).db")
        tempDbURLs.append(dbURL)
        let costAccounting = try CostAccounting(dbURL: dbURL)
        let registry = ContextProviderRegistry(providers: [:])
        let promptExecutor = PromptExecutor(
            keychain: MockKeychain(["openai-stub": "fake-key"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )
        let audit = MockAuditLog()
        let engine = ExecutionEngine(
            contextCollector: ContextCollector(registry: registry),
            permissionBroker: broker,
            permissionGraph: PermissionGraph(providerRegistry: registry),
            providerResolver: MockProviderResolver(),
            promptExecutor: promptExecutor,
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: costAccounting,
            auditLog: audit,
            output: MockOutputDispatcher()
        )

        // 消费到 .llmChunk 后 break；onTermination → task.cancel() →
        // sideEffect 循环 / cost record 任一 await 边界 isCancelled=true
        let consumerTask = Task<[ExecutionEvent], Never> {
            let stream = engine.execute(tool: tool, seed: seed)
            var events: [ExecutionEvent] = []
            do {
                for try await event in stream {
                    events.append(event)
                    if case .llmChunk = event { break }
                }
            } catch {
                // 任何 catch（含 CancellationError）都视为消费结束
            }
            return events
        }

        let collected = await consumerTask.value
        XCTAssertGreaterThanOrEqual(collected.count, 2,
                                    "consumer should observe .started + first .llmChunk before cancel; got=\(collected)")

        // 等 cancellation 完整传导：runPromptKindPipeline 后续每个 await 边界 isCancelled 短路
        try? await Task.sleep(nanoseconds: 500_000_000)

        let entries = await audit.entries
        let hasCompleted = entries.contains { entry in
            if case .invocationCompleted = entry { return true }
            return false
        }
        // 关键断言：取消后绝不能写 .invocationCompleted（尤其不能是 success outcome）
        XCTAssertFalse(hasCompleted,
                       "cancelled-during-sideEffects invocation must NOT write .invocationCompleted; got=\(entries)")
    }

    /// PromptStream chunk 派发期间取消：multi-chunk LLM yield 多个 chunk，consumer 在第一个
    /// `.llmChunk` 后 break；后续 chunk 不应再 yield .llmChunk / 调用 OutputDispatcher.handle。
    ///
    /// 反例：若 runPromptStream 仅在 `for-await` 边界查 cancel，每个 chunk 处理体内的
    /// `await output.handle(...)` 后没有 isCancelled 短路，多 chunk 流会在 cancel 后
    /// 继续 dispatch — Phase 1 接真实 OutputDispatcher 时会有 chunk 投递到已关闭 panel。
    /// 当前实现：chunk 入口 + output.handle await 后均显式 `Task.isCancelled` 短路。
    func test_execute_cancellationDuringPromptStream_skipsLaterChunkDispatch() async throws {
        // 多 chunk LLM：chunks 间 Task.yield() 给 consumer 调度窗口
        let chunks = (0..<5).map { ChatChunk(delta: "chunk-\($0)", finishReason: nil) }
            + [ChatChunk(delta: "tail", finishReason: .stop)]
        let llm = YieldingMultiChunkLLMProvider(chunks: chunks)

        // MockOutputDispatcher 默认 .delivered；记录 handleCallCount 用于断言"少于总 chunk 数"
        let outputDispatcher = MockOutputDispatcher()

        // 装配 engine（makeEngine 不接受 OutputDispatcher 注入；inline 装配）
        let dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-engine-streamcancel-\(UUID().uuidString).db")
        tempDbURLs.append(dbURL)
        let costAccounting = try CostAccounting(dbURL: dbURL)
        let registry = ContextProviderRegistry(providers: [:])
        let promptExecutor = PromptExecutor(
            keychain: MockKeychain(["openai-stub": "fake-key"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm)
        )
        let audit = MockAuditLog()
        let engine = ExecutionEngine(
            contextCollector: ContextCollector(registry: registry),
            permissionBroker: MockPermissionBroker(),
            permissionGraph: PermissionGraph(providerRegistry: registry),
            providerResolver: MockProviderResolver(),
            promptExecutor: promptExecutor,
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: costAccounting,
            auditLog: audit,
            output: outputDispatcher
        )

        let tool = makeStubTool()
        let seed = makeStubSeed()

        let consumerTask = Task<[ExecutionEvent], Never> {
            let stream = engine.execute(tool: tool, seed: seed)
            var events: [ExecutionEvent] = []
            do {
                for try await event in stream {
                    events.append(event)
                    if case .llmChunk = event { break }
                }
            } catch {
                // 任何 catch（含 CancellationError）都视为消费结束
            }
            return events
        }

        let collected = await consumerTask.value
        XCTAssertGreaterThanOrEqual(collected.count, 2,
                                    "consumer should observe .started + first .llmChunk before cancel; got=\(collected)")

        // 等 cancellation 完整传导：consumer break → onTermination → task.cancel() → 后续每个 chunk 入口 isCancelled=true
        try? await Task.sleep(nanoseconds: 500_000_000)

        // 关键断言：handleCallCount ≤ 1 ——
        // 修前：所有 6 个 chunk 都会调 handle（cancel 信号在 yield 后未被 yield-result/isCancelled 拦截）；
        // 修后：第 1 个 chunk 进入 output.handle 后 cancel 已传导，第 2+ chunk 被 yield-result `.terminated`
        // 或 post-handle isCancelled 短路拦下，dispatcher 最多被调 1 次
        let callCount = await outputDispatcher.handleCallCount
        XCTAssertLessThanOrEqual(callCount, 1,
                                 "cancelled-during-prompt-stream must dispatch at most 1 chunk (the trigger); got handleCallCount=\(callCount), totalChunks=\(chunks.count)")

        // audit 也不应有 .invocationCompleted —— cancel 静默退出
        let entries = await audit.entries
        let hasCompleted = entries.contains { entry in
            if case .invocationCompleted = entry { return true }
            return false
        }
        XCTAssertFalse(hasCompleted,
                       "cancelled-during-prompt-stream must NOT write .invocationCompleted; got=\(entries)")
    }
}

// MARK: - 辅助：cancellation 测试用 LLMProvider

/// 阻塞型 LLMProvider —— yield 一个 chunk 后挂起 sleep 等待外部 cancellation。
///
/// 用于 `test_execute_consumerCancellation_*`：固定 LLM 流"长时活动"语义，
/// 让 consumer 在 chunk yield 与 stream finish 之间有确定窗口可以 cancel。
/// 收到 cancel 时 producer Task 的 `Task.sleep` 抛 CancellationError，
/// 被外层 catch 转为 `continuation.finish(throwing: error)` 让 stream 优雅退出。
private final class BlockingMockLLMProvider: LLMProvider, @unchecked Sendable {
    private let initialChunk: ChatChunk

    init(initialChunk: ChatChunk) {
        self.initialChunk = initialChunk
    }

    /// LLMProvider 协议方法：yield 1 chunk → 阻塞 → cancel-aware finish
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        let chunk = initialChunk
        return AsyncThrowingStream { continuation in
            let producer = Task {
                continuation.yield(chunk)
                do {
                    // 10s 上限：测试 Task 期望在 < 1s 内取消；任何超时都说明 cancellation 链断了
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // 当 ExecutionEngine 内部 task 被取消，其 iterator 被释放 → onTermination →
            // 取消 producer Task → Task.sleep 抛 CancellationError → 走 catch 关流
            continuation.onTermination = { _ in
                producer.cancel()
            }
        }
    }
}

// MARK: - 辅助：early-cancel 测试用 ProviderResolver

/// 在 resolve 内显式 `Task.yield()`，模拟生产环境真实 ProviderResolver 的异步让出点。
///
/// **存在理由**：mock 全 sync 时 actor 上没有真实让出点，
/// cancel signal（来自 onTermination）无传导窗口；early-cancel 测试需要这道
/// 让出点把 cancel 信号在 Step 4 期间引入 runMainFlow，让 Step 4 之后的
/// `if Task.isCancelled { return }` 能捕获并提前 return（不调 PromptExecutor）。
private final class YieldingMockProviderResolver: ProviderResolverProtocol, @unchecked Sendable {
    private let provider: V2Provider

    init(provider: V2Provider = MockProvider.openAIStub()) {
        self.provider = provider
    }

    /// ProviderResolverProtocol 实现：让出 cooperative thread 一次后返回 provider
    func resolve(_ selection: ProviderSelection) async throws -> V2Provider {
        await Task.yield()
        return provider
    }
}

// MARK: - 辅助：cancellation-during-prompt-stream 测试用 LLMProvider

/// chunks 之间显式 `Task.yield()` 的 LLMProvider —— 让 consumer 有机会在某个 chunk 后 break，
/// cancel cascade 在 yield 边界落地，后续 chunk 进入 runPromptStream for-await 时 isCancelled=true。
///
/// 用于 `test_execute_cancellationDuringPromptStream_*`：验证 chunk 入口 + output.handle await 后
/// 的两道 cancel 短路不让"取消后还派发剩余 chunk"。producer Task 在 onTermination 后被 cancel，
/// Task.yield() 抛 CancellationError 则 continuation.finish(throwing:) 静默关流。
private final class YieldingMultiChunkLLMProvider: LLMProvider, @unchecked Sendable {
    private let chunks: [ChatChunk]

    init(chunks: [ChatChunk]) {
        self.chunks = chunks
    }

    /// LLMProvider 协议方法：每 chunk 之间 Task.yield() 让出 cooperative thread
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        let allChunks = chunks
        return AsyncThrowingStream { continuation in
            let producer = Task {
                for chunk in allChunks {
                    if Task.isCancelled { break }
                    continuation.yield(chunk)
                    await Task.yield()
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in producer.cancel() }
        }
    }
}

// MARK: - 辅助：cancellation-during-permission/sideEffect 测试用 PermissionBroker

/// gate 内 `Task.yield()` 后再返回 outcome 的 PermissionBroker —— 给 cancel cascade
/// 落地的 cooperative 让出点。模拟 Phase 1 真实 broker（Keychain 查询 / consent UI 通信）
/// 在 await 边界让出执行的真实行为。
///
/// 用于 `test_execute_cancellationDuringPermissionGate_*` / `test_execute_cancellationDuringSideEffects_*`：
/// 让 cancel 信号能在 broker.gate await 后被新增的 `if Task.isCancelled` 短路捕获。
private final actor YieldingMockPermissionBroker: PermissionBrokerProtocol {
    private let outcomeOverride: GateOutcome?

    init(outcomeOverride: GateOutcome?) {
        self.outcomeOverride = outcomeOverride
    }

    /// gate 实现：先 Task.yield() 让出 cooperative thread，再返回 override outcome（默认 .approved）
    func gate(
        effective: Set<Permission>,
        provenance: Provenance,
        scope: GrantScope,
        isDryRun: Bool
    ) async -> GateOutcome {
        await Task.yield()
        return outcomeOverride ?? .approved
    }
}

// MARK: - 辅助：cancellation-during-context 测试用 ContextProvider

/// resolve 内做长时 `Task.sleep(5s)` 等外部 cancellation 把它打断的 ContextProvider。
///
/// 用于 `test_execute_cancellationDuringContextCollection_*`：模拟 Phase 1 真实 fileRead /
/// MCP / clipboard provider 在 IO 中被 cancel 的场景（合作式取消 contract）。
/// Task.sleep 是 cooperative cancellation 的 textbook 用法 —— 收到 cancel 立即抛
/// CancellationError，让 ContextCollector.runOne 的 `catch is CancellationError` 透传。
private final class CancellableContextProvider: ContextProvider, @unchecked Sendable {
    let name: String

    init(name: String = "test.cancellable") {
        self.name = name
    }

    /// 静态推导：测试不验证 PermissionGraph，返回空避免 undeclared 校验干扰
    static func inferredPermissions(for args: [String: String]) -> [Permission] { [] }

    /// 5s sleep 上限：测试期望 < 1s 内 cancel；任何超时都说明 cancellation 链断了
    func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        try await Task.sleep(nanoseconds: 5_000_000_000)
        XCTFail("CancellableContextProvider.resolve should be cancelled before sleep completes")
        return .text("unreachable")
    }
}

// MARK: - 辅助：用例 4 专用的 ContextProvider，inferredPermissions 返回 fileRead

/// 用例 4 专用的 ContextProvider —— inferredPermissions 静态返回 `.fileRead(path: args["path"]!)`，
/// 让 PermissionGraph 能聚合出 declared 集合外的 .fileRead 触发 undeclared 校验失败。
private final class UndeclaredFileReadProvider: ContextProvider, @unchecked Sendable {
    let name: String

    init(name: String) {
        self.name = name
    }

    /// 静态推导：args["path"] 存在则返回 .fileRead，否则空（D-24 闭环的输入）
    static func inferredPermissions(for args: [String: String]) -> [Permission] {
        guard let path = args["path"] else { return [] }
        return [.fileRead(path: path)]
    }

    /// resolve 不会被调到 —— PermissionGraph 在 Step 2 就会拦下 undeclared，主流程不会走到 Step 3
    func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        XCTFail("UndeclaredFileReadProvider.resolve should not be called when undeclared check fails")
        return .text("unreachable")
    }
}
