import Capabilities
import SliceCore
import XCTest
@testable import Orchestration

/// Task 3: ExecutionEngine actor 骨架验证
///
/// 仅验证 10-dep init 编译通过 + Task 3 占位流（3 事件框架）的正确性。
/// Task 4 填入真实主流程后，本文件中的 `test_execute_*` 测试会被扩展或替换。
final class ExecutionEngineTests: XCTestCase {

    // MARK: - Fixture builders

    /// 构造最小 V2Tool 测试 stub
    /// - Parameter id: tool id，默认 "test.tool"
    private func makeStubTool(id: String = "test.tool") -> V2Tool {
        V2Tool(
            id: id,
            name: "Test Tool",
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
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造最小 ExecutionSeed 测试 stub
    private func makeStubSeed() -> ExecutionSeed {
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
            isDryRun: false
        )
    }

    /// 构造带全部 10 个依赖的 ExecutionEngine
    ///
    /// Task 5 已把 `ContextCollector()` stub init 替换为 `init(registry:)`；
    /// Task 7 把 `PermissionGraph()` 替换为 `init(providerRegistry:)`，
    /// fixture 注入空 `ContextProviderRegistry`（无任何 provider）以保持骨架测试不依赖真实采集。
    private func makeEngine() -> ExecutionEngine {
        let emptyRegistry = ContextProviderRegistry(providers: [:])
        return ExecutionEngine(
            contextCollector: ContextCollector(registry: emptyRegistry),
            permissionBroker: MockPermissionBroker(),
            permissionGraph: PermissionGraph(providerRegistry: emptyRegistry),
            providerResolver: DefaultProviderResolver(
                configurationProvider: { MockProvider.configWith([]) }
            ),
            promptExecutor: PromptExecutor(),
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: CostAccounting(),
            auditLog: MockAuditLog(),
            output: MockOutputDispatcher()
        )
    }

    // MARK: - Tests

    /// 冒烟测试：10-dep init 能正常编译并构造 actor 实例
    func test_init_buildsActorWithAllTenDependencies() async {
        let engine = makeEngine()
        // actor 构造成功即视为 init 通过；显式 XCTAssertNotNil 让测试意图明确
        // （Swift actor 引用永远非 nil，但断言可读性优于 `_ = engine`，
        //  并避免覆盖率工具把无断言的测试算成"测过"造成假象）
        XCTAssertNotNil(engine)
    }

    /// 验证 Task 3 占位流：execute 输出恰好 3 个事件（.started / .notImplemented / .finished）
    func test_execute_yieldsStartedNotImplementedFinishedThenCompletes() async throws {
        let engine = makeEngine()
        let tool = makeStubTool(id: "task3.placeholder")
        let seed = makeStubSeed()

        // 收集全部事件
        var collected: [ExecutionEvent] = []
        for try await event in engine.execute(tool: tool, seed: seed) {
            collected.append(event)
        }

        XCTAssertEqual(collected.count, 3, "Task 3 占位流应恰好产出 3 个事件")

        // 事件[0] 必须是 .started
        guard case .started = collected[0] else {
            XCTFail("event[0] expected .started, got \(collected[0])")
            return
        }

        // 事件[1] 必须是 .notImplemented，且 reason 包含 "Task 3 placeholder"
        guard case .notImplemented(let reason) = collected[1] else {
            XCTFail("event[1] expected .notImplemented, got \(collected[1])")
            return
        }
        XCTAssertTrue(
            reason.contains("Task 3 placeholder"),
            "notImplemented reason 应包含 'Task 3 placeholder'，实际：\(reason)"
        )

        // 事件[2] 必须是 .finished，report.toolId 与 tool.id 一致，outcome 为 .success
        guard case .finished(let report) = collected[2] else {
            XCTFail("event[2] expected .finished, got \(collected[2])")
            return
        }
        XCTAssertEqual(report.toolId, "task3.placeholder")
        XCTAssertEqual(report.outcome, .success)
    }
}
