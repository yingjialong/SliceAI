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
    /// - Returns: (ExecutionEngine, broker, audit, output, resolver) 元组，便于断言阶段读出注入实例
    private func makeEngine(
        broker: MockPermissionBroker? = nil,
        resolver: MockProviderResolver? = nil,
        contextProviders: [String: any ContextProvider] = [:],
        chunks: [ChatChunk] = [],
        keychainStore: [String: String] = ["openai-stub": "fake-key"],
        audit: MockAuditLog? = nil,
        output: MockOutputDispatcher? = nil
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
        let promptExecutor = PromptExecutor(
            keychain: MockKeychain(keychainStore),
            llmProviderFactory: MockLLMProviderFactory(provider: MockLLMProvider(chunks: chunks))
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
