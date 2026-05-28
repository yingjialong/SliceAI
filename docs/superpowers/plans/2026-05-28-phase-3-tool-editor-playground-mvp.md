# Phase 3 ToolEditor v2 + Prompt Playground MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]` / `- [x]`) syntax for tracking; completed implementation steps are marked checked.

**Goal:** Build a Settings-based ToolEditor v2 with an inline Prompt Playground that can run unsaved tool drafts through the real `ExecutionEngine` while routing output to a safe preview and keeping production side effects dry-run.

**Architecture:** Add an explicit run policy to SliceCore and propagate it through Orchestration, so Playground can mean “real LLM, optional real MCP with permission broker, dry-run side effects, preview output” instead of overloading `ExecutionSeed.isDryRun`. Keep `ExecutionEngine.execute(tool:seed:)` as the only execution entry point by creating a dedicated Playground engine instance in `AppContainer` with preview output dependencies. Introduce a SettingsUI draft editing layer so ToolEditor changes do not mutate `Configuration.tools` until Save.

**Tech Stack:** Swift 6.0, SwiftPM, XCTest, SwiftUI, AppKit, existing SliceCore / Orchestration / Capabilities / SettingsUI modules, SQLite3 for cost telemetry.

---

## File Structure

- Create `SliceAIKit/Sources/SliceCore/ExecutionRunPolicy.swift`: production/playground run source, side-effect mode, MCP mode, output routing mode, and default policy helpers.
- Modify `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift`: add optional `runPolicy` while preserving current initializer compatibility.
- Modify `SliceAIKit/Sources/SliceCore/TriggerSource.swift`: add `.playground`.
- Modify `SliceAIKit/Sources/Orchestration/Engine/FlowContext.swift`: carry the resolved run policy through the execution flow.
- Modify `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`: initialize `FlowContext.runPolicy` from `ExecutionSeed`.
- Modify `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`: use run policy for permission gate, cost source, report flags, and side-effect dry-run.
- Modify `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+PromptPipeline.swift`: pass run policy dry-run mode to prompt and agent side-effect / finish paths.
- Modify `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+AgentPipeline.swift`: pass run policy to `AgentExecutor`.
- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`: add a defaulted run policy parameter to `run(...)`.
- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`: enforce Playground MCP disabled/real modes and pass `isDryRun` correctly to `PermissionBroker`.
- Modify `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`: add `InvocationFlag.playground`.
- Modify `SliceAIKit/Sources/Orchestration/Telemetry/CostRecord.swift`: add nullable `source`.
- Modify `SliceAIKit/Sources/Orchestration/Telemetry/CostAccounting.swift`: add idempotent `source` column migration and source-aware read/write.
- Create `SliceAIKit/Sources/Orchestration/Output/PlaygroundOutputDispatcher.swift`: safe preview dispatcher that records lifecycle and never opens production UI or writes files/clipboard/selection.
- Create `SliceAIKit/Sources/Orchestration/Playground/ToolPlaygroundRunner.swift`: wrapper around a dedicated `ExecutionEngine` for SettingsUI.
- Create `SliceAIKit/Sources/SettingsUI/ToolEditorDraftState.swift`: local draft/session model, draft validation, and save/revert helpers.
- Create `SliceAIKit/Sources/SettingsUI/ToolPlaygroundState.swift`: UI-facing state reducer for `ExecutionEvent` plus DisplayMode previews.
- Create `SliceAIKit/Sources/SettingsUI/ToolPlaygroundView.swift`: right-side Playground controls and preview surface.
- Create `SliceAIKit/Sources/SettingsUI/ToolEditorV2View.swift`: two-column editor + Playground composition.
- Modify `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`: remain the left-side editor; remove wording that says it directly binds production configuration.
- Modify `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`: replace direct production `Tool` binding with draft sessions and Save/Revert controls.
- Modify `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Actions.swift`: add draft create/save/revert/delete behavior.
- Modify `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`: widen the Settings window for the two-column editor.
- Modify `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`: hold injected Playground runner and expose draft conflict state.
- Modify `SliceAIKit/Package.swift`: add `Orchestration` dependency to `SettingsUI` and `SettingsUITests`.
- Modify `SliceAIApp/AppContainer.swift`: construct the dedicated Playground engine and inject the runner into Settings.
- Add/modify tests:
  - `SliceAIKit/Tests/SliceCoreTests/ExecutionRunPolicyTests.swift`
  - `SliceAIKit/Tests/SliceCoreTests/ExecutionSeedTests.swift`
  - `SliceAIKit/Tests/OrchestrationTests/InvocationReportTests.swift`
  - `SliceAIKit/Tests/OrchestrationTests/CostAccountingTests.swift`
  - `SliceAIKit/Tests/OrchestrationTests/PlaygroundOutputDispatcherTests.swift`
  - `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`
  - `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
  - `SliceAIKit/Tests/SettingsUITests/ToolEditorDraftStateTests.swift`
  - `SliceAIKit/Tests/SettingsUITests/ToolPlaygroundStateTests.swift`
- Update docs:
  - `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`
  - `docs/Task_history.md`
  - `docs/v2-refactor-master-todolist.md`
  - `docs/Module/Orchestration.md`
  - `docs/Module/SettingsUI.md`

## Task 1: Run Policy And Telemetry Foundation

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ExecutionRunPolicy.swift`
- Modify: `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift`
- Modify: `SliceAIKit/Sources/SliceCore/TriggerSource.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Telemetry/CostRecord.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Telemetry/CostAccounting.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Engine/FlowContext.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+PromptPipeline.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ExecutionRunPolicyTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ExecutionSeedTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/InvocationReportTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/CostAccountingTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`

- [x] **Step 1: Write failing SliceCore run policy tests**

Create `SliceAIKit/Tests/SliceCoreTests/ExecutionRunPolicyTests.swift`:

```swift
import XCTest
@testable import SliceCore

/// ExecutionRunPolicy 的编码、默认值和 Playground 语义测试。
final class ExecutionRunPolicyTests: XCTestCase {

    /// 生产默认策略应该真实执行输出和 MCP，并由 isDryRun 决定 side effect 模式。
    func test_defaultPolicyForProductionReflectsDryRunFlag() {
        let normal = ExecutionRunPolicy.production(isDryRun: false)
        XCTAssertEqual(normal.source, .production)
        XCTAssertEqual(normal.sideEffects, .real)
        XCTAssertEqual(normal.mcpToolCalls, .realWithPermissionBroker)
        XCTAssertEqual(normal.outputRouting, .production)

        let dryRun = ExecutionRunPolicy.production(isDryRun: true)
        XCTAssertEqual(dryRun.source, .production)
        XCTAssertEqual(dryRun.sideEffects, .dryRun)
        XCTAssertEqual(dryRun.mcpToolCalls, .realWithPermissionBroker)
        XCTAssertEqual(dryRun.outputRouting, .production)
    }

    /// Playground 默认策略必须真实调用 LLM、禁用 MCP、dry-run side effects，并路由到预览输出。
    func test_defaultPlaygroundPolicyDisablesMCPUntilUserConfirms() {
        let policy = ExecutionRunPolicy.playground(allowMCPToolCalls: false)
        XCTAssertEqual(policy.source, .playground)
        XCTAssertEqual(policy.sideEffects, .dryRun)
        XCTAssertEqual(policy.mcpToolCalls, .disabled)
        XCTAssertEqual(policy.outputRouting, .playgroundPreview)
    }

    /// 用户显式允许 MCP 后，Playground 才能在 PermissionBroker 闭环下真实调用 MCP。
    func test_playgroundPolicyAllowsMCPOnlyWhenExplicitlyEnabled() {
        let policy = ExecutionRunPolicy.playground(allowMCPToolCalls: true)
        XCTAssertEqual(policy.mcpToolCalls, .realWithPermissionBroker)
    }

    /// policy 必须可稳定编码，便于 ExecutionSeed 和审计测试使用。
    func test_policyCodableRoundtrip() throws {
        let policy = ExecutionRunPolicy.playground(allowMCPToolCalls: true)
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(ExecutionRunPolicy.self, from: data)
        XCTAssertEqual(decoded, policy)
    }
}
```

Also extend `SliceAIKit/Tests/SliceCoreTests/ExecutionSeedTests.swift`:

```swift
func test_executionSeed_defaultsRunPolicyToNilForBackwardCompatibility() {
    let seed = ExecutionSeed(
        invocationId: UUID(),
        selection: SelectionSnapshot(
            text: "hello",
            source: .inputBox,
            length: 5,
            language: nil,
            contentType: .prose
        ),
        frontApp: AppSnapshot(bundleId: "com.test", name: "Test", url: nil, windowTitle: nil),
        screenAnchor: .zero,
        timestamp: Date(timeIntervalSince1970: 0),
        triggerSource: .floatingToolbar,
        isDryRun: false
    )
    XCTAssertNil(seed.runPolicy)
    XCTAssertEqual(seed.effectiveRunPolicy, .production(isDryRun: false))
}

func test_executionSeed_canCarryPlaygroundRunPolicy() {
    let policy = ExecutionRunPolicy.playground(allowMCPToolCalls: false)
    let seed = ExecutionSeed(
        invocationId: UUID(),
        selection: SelectionSnapshot(
            text: "hello",
            source: .inputBox,
            length: 5,
            language: nil,
            contentType: .prose
        ),
        frontApp: AppSnapshot(bundleId: "com.test", name: "Test", url: nil, windowTitle: nil),
        screenAnchor: .zero,
        timestamp: Date(timeIntervalSince1970: 0),
        triggerSource: .playground,
        isDryRun: true,
        runPolicy: policy
    )
    XCTAssertEqual(seed.effectiveRunPolicy, policy)
}
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SliceCoreTests.ExecutionRunPolicyTests|SliceCoreTests.ExecutionSeedTests'
```

Expected: compile failure because `ExecutionRunPolicy`, `TriggerSource.playground`, `ExecutionSeed.runPolicy`, and `ExecutionSeed.effectiveRunPolicy` do not exist.

- [x] **Step 3: Add SliceCore run policy types**

Create `SliceAIKit/Sources/SliceCore/ExecutionRunPolicy.swift`:

```swift
import Foundation

/// 一次执行的来源；用于区分生产触发和 Settings Playground 试跑。
public enum ExecutionRunSource: String, Sendable, Codable, Equatable {
    /// 浮条、命令面板、工具热键等真实生产触发。
    case production
    /// Settings 中的 Prompt Playground 试跑。
    case playground
}

/// SideEffect 执行模式。
public enum SideEffectRunMode: String, Sendable, Codable, Equatable {
    /// 真实执行剪贴板、文件、通知、TTS 等副作用。
    case real
    /// 只产出 dry-run 事件，不执行真实副作用。
    case dryRun
}

/// Agent MCP tool call 执行模式。
public enum MCPToolCallRunMode: String, Sendable, Codable, Equatable {
    /// 禁止真实 MCP tool call，模型提出调用时返回受控拒绝。
    case disabled
    /// 允许真实 MCP tool call，但必须经过 allowlist 与 PermissionBroker。
    case realWithPermissionBroker
}

/// 输出路由模式。
public enum OutputRoutingMode: String, Sendable, Codable, Equatable {
    /// 使用生产 ResultPanel / BubblePanel / Replace / File 等输出依赖。
    case production
    /// 输出只进入 Settings Playground 预览依赖。
    case playgroundPreview
}

/// 一次执行的运行策略。
///
/// `ExecutionSeed.isDryRun` 继续表示“副作用 dry-run / dry-run outcome”，
/// 本类型补充 source、MCP 与输出路由语义，避免 Playground 复用含混布尔值。
public struct ExecutionRunPolicy: Sendable, Codable, Equatable {
    /// 本次执行的来源。
    public let source: ExecutionRunSource
    /// SideEffect 执行模式。
    public let sideEffects: SideEffectRunMode
    /// Agent MCP tool call 执行模式。
    public let mcpToolCalls: MCPToolCallRunMode
    /// 输出路由模式。
    public let outputRouting: OutputRoutingMode

    /// 构造运行策略。
    public init(
        source: ExecutionRunSource,
        sideEffects: SideEffectRunMode,
        mcpToolCalls: MCPToolCallRunMode,
        outputRouting: OutputRoutingMode
    ) {
        self.source = source
        self.sideEffects = sideEffects
        self.mcpToolCalls = mcpToolCalls
        self.outputRouting = outputRouting
    }

    /// 生产触发默认策略。
    public static func production(isDryRun: Bool) -> ExecutionRunPolicy {
        ExecutionRunPolicy(
            source: .production,
            sideEffects: isDryRun ? .dryRun : .real,
            mcpToolCalls: .realWithPermissionBroker,
            outputRouting: .production
        )
    }

    /// Playground 试跑默认策略。
    public static func playground(allowMCPToolCalls: Bool) -> ExecutionRunPolicy {
        ExecutionRunPolicy(
            source: .playground,
            sideEffects: .dryRun,
            mcpToolCalls: allowMCPToolCalls ? .realWithPermissionBroker : .disabled,
            outputRouting: .playgroundPreview
        )
    }
}
```

Modify `SliceAIKit/Sources/SliceCore/TriggerSource.swift`:

```swift
    /// Settings Prompt Playground 试跑。
    case playground
```

Modify `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift`:

```swift
    /// 可选运行策略；nil 表示按旧语义从 `isDryRun` 推导生产策略。
    public let runPolicy: ExecutionRunPolicy?

    /// 解析后的运行策略。
    public var effectiveRunPolicy: ExecutionRunPolicy {
        runPolicy ?? .production(isDryRun: isDryRun)
    }
```

Add a defaulted initializer parameter:

```swift
        triggerSource: TriggerSource,
        isDryRun: Bool,
        runPolicy: ExecutionRunPolicy? = nil
```

and assign:

```swift
        self.runPolicy = runPolicy
```

- [x] **Step 4: Run SliceCore focused tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SliceCoreTests.ExecutionRunPolicyTests|SliceCoreTests.ExecutionSeedTests|SliceCoreTests.TriggerSourceTests'
```

Expected: pass after updating `TriggerSourceTests` expected cases to include `.playground`.

- [x] **Step 5: Write failing telemetry compatibility tests**

Extend `SliceAIKit/Tests/OrchestrationTests/InvocationReportTests.swift`:

```swift
func test_invocationFlag_playgroundCodableRoundtrip() throws {
    let flag = InvocationFlag.playground
    let data = try JSONEncoder().encode(flag)
    let decoded = try JSONDecoder().decode(InvocationFlag.self, from: data)
    XCTAssertEqual(decoded, .playground)
    XCTAssertEqual(String(data: data, encoding: .utf8), "\"playground\"")
}
```

Extend `SliceAIKit/Tests/OrchestrationTests/CostAccountingTests.swift`. Add `import SQLite3` at the top because the legacy migration test creates an old schema directly:

```swift
func test_record_playgroundSource_roundtrips() async throws {
    let record = CostRecord(
        invocationId: UUID(),
        toolId: "tool.playground",
        providerId: "openai",
        model: "gpt-4o-mini",
        inputTokens: 10,
        outputTokens: 20,
        usd: Decimal(string: "0.00003")!,
        recordedAt: Date(timeIntervalSince1970: 1),
        source: .playground
    )

    try await sut.record(record)
    let records = try await sut.findByToolId("tool.playground")

    XCTAssertEqual(records.first?.source, .playground)
}

func test_init_migratesOldCostSchemaByAddingNullableSourceColumn() async throws {
    sut = nil
    try? FileManager.default.removeItem(at: dbURL)
    try createLegacyCostDatabase(at: dbURL)

    sut = try CostAccounting(dbURL: dbURL)
    let records = try await sut.findByToolId("legacy-tool")

    XCTAssertEqual(records.count, 1)
    XCTAssertNil(records[0].source)
}
```

Add this helper below the test methods in the same file:

```swift
private func createLegacyCostDatabase(at url: URL) throws {
    var db: OpaquePointer?
    XCTAssertEqual(sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil), SQLITE_OK)
    defer { sqlite3_close(db) }
    let sql = """
    CREATE TABLE cost_records (
        invocation_id TEXT PRIMARY KEY,
        tool_id       TEXT,
        provider_id   TEXT,
        model         TEXT,
        input_tokens  INTEGER,
        output_tokens INTEGER,
        usd           TEXT NOT NULL,
        recorded_at   INTEGER
    );
    INSERT INTO cost_records
        (invocation_id, tool_id, provider_id, model, input_tokens, output_tokens, usd, recorded_at)
    VALUES
        ('00000000-0000-0000-0000-000000000001', 'legacy-tool', 'openai', 'gpt-4o-mini', 1, 2, '0.1', 1000);
    """
    XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
}
```

- [x] **Step 6: Run telemetry tests to verify they fail**

Run:

```bash
swift test --package-path SliceAIKit --filter 'OrchestrationTests.InvocationReportTests|OrchestrationTests.CostAccountingTests'
```

Expected: compile failure because `InvocationFlag.playground` and `CostRecord.source` do not exist.

- [x] **Step 7: Implement telemetry source fields and schema migration**

Modify `InvocationFlag` in `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`:

```swift
    /// Settings Playground 试跑。
    case playground
```

Modify `SliceAIKit/Sources/Orchestration/Telemetry/CostRecord.swift` by adding `import SliceCore` below the existing `import Foundation`, then add the source field:

```swift
import SliceCore

    /// 执行来源；nil 表示旧数据或尚未标记的生产触发。
    public let source: ExecutionRunSource?
```

Add defaulted initializer parameter:

```swift
        recordedAt: Date,
        source: ExecutionRunSource? = nil
```

Modify `SliceAIKit/Sources/Orchestration/Telemetry/CostAccounting.swift`:

```swift
        do {
            try Self.createSchema(db: handle)
            try Self.migrateSchema(db: handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }
```

Change INSERT columns to include `source`, bind it as nullable text, and update SELECT/decode indexes:

```swift
        INSERT INTO cost_records
            (invocation_id, tool_id, provider_id, model, input_tokens, output_tokens, usd, recorded_at, source)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
```

```swift
        if let source = record.source?.rawValue {
            sqlite3_bind_text(stmt, 9, source, -1, SQLITE_TRANSIENT)
        } else {
            sqlite3_bind_null(stmt, 9)
        }
```

Update `createSchema` so new databases include the column without relying on migration:

```sql
CREATE TABLE IF NOT EXISTS cost_records (
    invocation_id TEXT PRIMARY KEY,
    tool_id       TEXT,
    provider_id   TEXT,
    model         TEXT,
    input_tokens  INTEGER,
    output_tokens INTEGER,
    usd           TEXT NOT NULL,
    recorded_at   INTEGER,
    source        TEXT
)
```

Update the `findByToolId` SELECT list:

```sql
SELECT invocation_id, tool_id, provider_id, model, input_tokens, output_tokens, usd, recorded_at, source
FROM cost_records
WHERE tool_id = ?
ORDER BY recorded_at ASC
```

Add idempotent migration:

```swift
    /// 轻量迁移 cost_records，确保旧 sqlite 文件拥有 nullable source 列。
    private static func migrateSchema(db: OpaquePointer) throws {
        guard try !tableHasColumn(db: db, table: "cost_records", column: "source") else { return }
        let sql = "ALTER TABLE cost_records ADD COLUMN source TEXT"
        let result = sqlite3_exec(db, sql, nil, nil, nil)
        guard result == SQLITE_OK else {
            throw SliceError.configuration(
                .validationFailed("sqlite schema migrate source failed (code=\(result))")
            )
        }
    }

    /// 检查 sqlite 表是否已有指定列。
    private static func tableHasColumn(db: OpaquePointer, table: String, column: String) throws -> Bool {
        var stmt: OpaquePointer?
        let sql = "PRAGMA table_info(\(table))"
        let prepResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard prepResult == SQLITE_OK else {
            throw SliceError.configuration(.validationFailed("sqlite prepare PRAGMA failed"))
        }
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let nameCStr = sqlite3_column_text(stmt, 1) else { continue }
            if String(cString: nameCStr) == column { return true }
        }
        return false
    }
```

Decode `source` as nullable raw value at column index 8:

```swift
        let source: ExecutionRunSource?
        if sqlite3_column_type(stmt, 8) == SQLITE_NULL {
            source = nil
        } else if let sourceCStr = sqlite3_column_text(stmt, 8) {
            source = ExecutionRunSource(rawValue: String(cString: sourceCStr))
        } else {
            source = nil
        }
```

- [x] **Step 8: Propagate policy through ExecutionEngine reports and cost records**

Modify `FlowContext` to include:

```swift
    /// 本次执行的运行策略。
    let runPolicy: ExecutionRunPolicy
```

Add constructor parameter and assignment:

```swift
        runPolicy: ExecutionRunPolicy,
```

In `ExecutionEngine.runMainFlow`, pass:

```swift
            runPolicy: seed.effectiveRunPolicy,
```

Change the overall permission gate call to use the policy instead of the legacy seed flag:

```swift
        guard await runPermissionGate(
            tool: tool,
            effective: effective,
            isDryRun: context.runPolicy.sideEffects == .dryRun,
            context: context
        ) else { return }
```

In `ExecutionEngine+PromptPipeline.swift`, change both prompt and agent paths to derive dry-run from the context policy:

```swift
        let isDryRun = context.runPolicy.sideEffects == .dryRun
        let partialFailure = await runSideEffects(
            tool: tool,
            isDryRun: isDryRun,
            context: context
        )
        ...
        await recordCostAndFinishSuccess(
            tool: tool,
            provider: provider,
            usage: promptUsage,
            isDryRun: isDryRun,
            context: context
        )
```

Apply the same replacement in `runAgentKindPipeline`, using its local `usage`.

In `recordCostAndFinishSuccess`, change side-effect dry-run and flags:

```swift
        try? await costAccounting.record(CostRecord(
            invocationId: context.invocationId,
            toolId: tool.id,
            providerId: provider.id,
            model: model,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            usd: costUSD,
            recordedAt: Date(),
            source: context.runPolicy.source
        ))
        if context.runPolicy.sideEffects == .dryRun { context.flags.insert(.dryRun) }
        if context.runPolicy.source == .playground { context.flags.insert(.playground) }
```

Use `context.runPolicy.sideEffects == .dryRun` when deciding outcome:

```swift
            outcome: context.runPolicy.sideEffects == .dryRun ? .dryRunCompleted : .success
```

In `finishFailure`, add playground flag before building the report:

```swift
        if context.runPolicy.source == .playground {
            context.flags.insert(.playground)
        }
```

- [x] **Step 9: Run focused tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SliceCoreTests.ExecutionRunPolicyTests|SliceCoreTests.ExecutionSeedTests|OrchestrationTests.InvocationReportTests|OrchestrationTests.CostAccountingTests|OrchestrationTests.ExecutionEngineTests'
```

Expected: pass.

- [x] **Step 10: Commit**

```bash
git add SliceAIKit/Sources/SliceCore SliceAIKit/Sources/Orchestration SliceAIKit/Tests/SliceCoreTests SliceAIKit/Tests/OrchestrationTests
git commit -m "feat: add playground run policy telemetry"
```

## Task 2: Playground Output Dispatcher

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Output/PlaygroundOutputDispatcher.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/PlaygroundOutputDispatcherTests.swift`

- [x] **Step 1: Write failing preview output tests**

Create `SliceAIKit/Tests/OrchestrationTests/PlaygroundOutputDispatcherTests.swift`:

```swift
import XCTest
import SliceCore
@testable import Orchestration

/// PlaygroundOutputDispatcher 不得触发生产 UI 或系统副作用。
final class PlaygroundOutputDispatcherTests: XCTestCase {

    func test_windowMode_collectsChunksAndFinalText() async throws {
        let dispatcher = PlaygroundOutputDispatcher()
        let context = makeContext(mode: .window)

        try await dispatcher.begin(context: context)
        _ = try await dispatcher.handle(chunk: "hello", context: context)
        _ = try await dispatcher.handle(chunk: " world", context: context)
        try await dispatcher.finish(finalText: "hello world", context: context)

        let snapshot = await dispatcher.snapshot(for: context.invocationId)
        XCTAssertEqual(snapshot?.chunks, ["hello", " world"])
        XCTAssertEqual(snapshot?.finalText, "hello world")
        XCTAssertEqual(snapshot?.mode, .window)
    }

    func test_fileReplaceBubbleStructuredAndSilent_doNotThrowAtFinish() async throws {
        for mode in [DisplayMode.file, .replace, .bubble, .structured, .silent] {
            let dispatcher = PlaygroundOutputDispatcher()
            let context = makeContext(mode: mode)
            try await dispatcher.begin(context: context)
            _ = try await dispatcher.handle(chunk: "preview", context: context)
            try await dispatcher.finish(finalText: "preview", context: context)
            let snapshot = await dispatcher.snapshot(for: context.invocationId)
            XCTAssertEqual(snapshot?.finalText, "preview")
        }
    }

    func test_fail_recordsRedactedErrorState() async {
        let dispatcher = PlaygroundOutputDispatcher()
        let context = makeContext(mode: .window)

        await dispatcher.fail(error: .provider(.unauthorized), context: context)

        let snapshot = await dispatcher.snapshot(for: context.invocationId)
        XCTAssertEqual(snapshot?.failureMessage, SliceError.provider(.unauthorized).userMessage)
    }

    private func makeContext(mode: DisplayMode) -> OutputInvocationContext {
        OutputInvocationContext(
            invocationId: UUID(),
            toolId: "tool",
            toolName: "Tool",
            mode: mode,
            screenAnchor: .zero,
            outputBinding: nil
        )
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path SliceAIKit --filter OrchestrationTests.PlaygroundOutputDispatcherTests
```

Expected: compile failure because `PlaygroundOutputDispatcher` does not exist.

- [x] **Step 3: Implement preview dispatcher**

Create `SliceAIKit/Sources/Orchestration/Output/PlaygroundOutputDispatcher.swift`:

```swift
import Foundation
import SliceCore

/// Playground 输出快照，供 SettingsUI 在 ExecutionEvent 之外补充 final-only 预览。
public struct PlaygroundOutputSnapshot: Sendable, Equatable {
    /// invocation id。
    public let invocationId: UUID
    /// 输出模式。
    public var mode: DisplayMode
    /// 流式 chunk 列表。
    public var chunks: [String]
    /// 完整 final text。
    public var finalText: String?
    /// 失败时的用户可读错误。
    public var failureMessage: String?
}

/// Settings Playground 专用输出派发器。
///
/// 本派发器只记录 preview 状态，不打开 ResultPanel / BubblePanel，
/// 不写文件，不替换前台选区，也不写剪贴板。
public actor PlaygroundOutputDispatcher: OutputDispatcherProtocol {
    private var snapshots: [UUID: PlaygroundOutputSnapshot] = [:]

    /// 标记一次 preview 输出开始。
    public func begin(context: OutputInvocationContext) async throws {
        snapshots[context.invocationId] = PlaygroundOutputSnapshot(
            invocationId: context.invocationId,
            mode: context.mode,
            chunks: [],
            finalText: nil,
            failureMessage: nil
        )
    }

    /// 记录 chunk；这是 `OutputDispatcherProtocol` 的 required 方法。
    public func handle(
        chunk: String,
        mode: DisplayMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome {
        ensureSnapshot(invocationId: invocationId, mode: mode)
        snapshots[invocationId]?.chunks.append(chunk)
        return .delivered
    }

    /// 记录带生命周期上下文的 chunk，并复用三参数 required 方法。
    public func handle(chunk: String, context: OutputInvocationContext) async throws -> DispatchOutcome {
        try await handle(chunk: chunk, mode: context.mode, invocationId: context.invocationId)
        return .delivered
    }

    /// 记录 final text；final-only 模式也不执行真实输出。
    public func finish(finalText: String, context: OutputInvocationContext) async throws {
        ensureSnapshot(context: context)
        snapshots[context.invocationId]?.finalText = finalText
    }

    /// 记录失败状态。
    public func fail(error: SliceError, context: OutputInvocationContext) async {
        ensureSnapshot(context: context)
        snapshots[context.invocationId]?.failureMessage = error.userMessage
    }

    /// 读取一次 invocation 的 preview 快照。
    public func snapshot(for invocationId: UUID) -> PlaygroundOutputSnapshot? {
        snapshots[invocationId]
    }

    /// 确保字典中存在当前 invocation。
    private func ensureSnapshot(context: OutputInvocationContext) {
        ensureSnapshot(invocationId: context.invocationId, mode: context.mode)
    }

    /// 确保字典中存在当前 invocation。
    private func ensureSnapshot(invocationId: UUID, mode: DisplayMode) {
        if snapshots[invocationId] == nil {
            snapshots[invocationId] = PlaygroundOutputSnapshot(
                invocationId: invocationId,
                mode: mode,
                chunks: [],
                finalText: nil,
                failureMessage: nil
            )
        }
    }
}
```

- [x] **Step 4: Run focused output tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'OrchestrationTests.PlaygroundOutputDispatcherTests|OrchestrationTests.OutputLifecycleTests|OrchestrationTests.OutputDispatcherFallbackTests'
```

Expected: pass.

- [x] **Step 5: Commit**

```bash
git add SliceAIKit/Sources/Orchestration/Output/PlaygroundOutputDispatcher.swift SliceAIKit/Tests/OrchestrationTests/PlaygroundOutputDispatcherTests.swift
git commit -m "feat: add playground output dispatcher"
```

## Task 3: Agent MCP Run Policy

**Files:**
- Modify: `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+AgentPipeline.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`

- [x] **Step 1: Write failing Agent MCP policy tests**

Add to `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`:

```swift
func test_agentExecutor_playgroundPolicyDisabledMCPDeniesAllowedToolBeforeBroker() async throws {
    let llm = MockToolCallingLLMProvider(turns: [
        toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
        finalAnswerTurn("done")
    ])
    let broker = MockPermissionBroker()
    let executor = makeExecutor(llm: llm, broker: broker, mcpClient: makeMCPClient())
    let agent = makeAgent(allowlist: [readRef])

    let events = await collectEvents(from: await executor.run(
        tool: makeTool(agent: agent),
        agent: agent,
        resolved: makeResolvedContext(),
        provider: MockProvider.openAIStub(),
        runPolicy: .playground(allowMCPToolCalls: false)
    ))

    XCTAssertTrue(events.contains { event in
        if case .toolCallDenied(_, let reason) = event {
            return reason.contains("MCP calls are disabled")
        }
        return false
    })
    let gateCalls = await broker.gateCalls
    XCTAssertTrue(gateCalls.isEmpty)
}

func test_agentExecutor_playgroundPolicyDisabledMCPDoesNotConsumeToolBudget() async throws {
    let llm = MockToolCallingLLMProvider(turns: [
        toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
        toolCallTurn(id: "call-2", name: "read", arguments: "{\"path\":\"/tmp/b.txt\"}"),
        finalAnswerTurn("done")
    ])
    let broker = MockPermissionBroker()
    let mcp = makeMCPClient()
    let executor = makeExecutor(llm: llm, broker: broker, mcpClient: mcp)
    let policy = AgentToolCallPolicy(
        maxTotalCalls: 1,
        maxCallsPerTurn: 1,
        perToolLimits: [],
        duplicateArgumentStrategy: .allow,
        stopOnRateLimit: true
    )
    let agent = makeAgent(allowlist: [readRef], maxSteps: 2, toolCallPolicy: policy)

    let events = await collectEvents(from: await executor.run(
        tool: makeTool(agent: agent),
        agent: agent,
        resolved: makeResolvedContext(),
        provider: MockProvider.openAIStub(),
        runPolicy: .playground(allowMCPToolCalls: false)
    ))

    let disabledDenials = events.filter { event in
        if case .toolCallDenied(_, let reason) = event {
            return reason.contains("MCP calls are disabled")
        }
        return false
    }
    XCTAssertEqual(disabledDenials.count, 2)
    XCTAssertEqual(llm.toolStreamCallCount, 3)
    XCTAssertEqual(await mcp.callCount, 0)
    let gateCalls = await broker.gateCalls
    XCTAssertTrue(gateCalls.isEmpty)
}

func test_agentExecutor_playgroundPolicyAllowedMCPPassesNonDryRunToBroker() async throws {
    let llm = MockToolCallingLLMProvider(turns: [
        toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
        finalAnswerTurn("done")
    ])
    let broker = MockPermissionBroker()
    let executor = makeExecutor(llm: llm, broker: broker, mcpClient: makeMCPClient())
    let agent = makeAgent(allowlist: [readRef])

    _ = await collectEvents(from: await executor.run(
        tool: makeTool(agent: agent),
        agent: agent,
        resolved: makeResolvedContext(),
        provider: MockProvider.openAIStub(),
        runPolicy: .playground(allowMCPToolCalls: true)
    ))

    let gateCalls = await broker.gateCalls
    XCTAssertEqual(gateCalls.last?.isDryRun, false)
    XCTAssertEqual(gateCalls.last?.scope, .oneTime)
}
```

Add the tests next to the existing AgentExecutor tool-call tests and use the file's existing `MockToolCallingLLMProvider`, `toolCallTurn`, `finalAnswerTurn`, `makeExecutor`, `makeMCPClient`, `makeAgent`, `makeTool`, `makeResolvedContext`, `collectEvents`, and `MockPermissionBroker` helpers.

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests
```

Expected: compile failure because `AgentExecutor.run(..., runPolicy:)` does not exist.

- [x] **Step 3: Add run policy to AgentExecutor**

Modify `AgentExecutor.run(...)` in `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`:

```swift
public func run(
    tool: Tool,
    agent: AgentTool,
    resolved: ResolvedExecutionContext,
    provider: Provider,
    runPolicy: ExecutionRunPolicy = .production(isDryRun: false)
) async -> AsyncThrowingStream<ExecutionEvent, any Error>
```

Store the policy in `AgentToolTurnProcessingContext`:

```swift
struct AgentToolTurnProcessingContext: Sendable {
    let catalog: AgentToolCatalog
    let tool: Tool
    let runPolicy: ExecutionRunPolicy
    let continuation: AgentEventContinuation
}
```

Pass it from each turn creation:

```swift
let turnContext = AgentToolTurnProcessingContext(
    catalog: catalog,
    tool: tool,
    runPolicy: runPolicy,
    continuation: continuation
)
```

Thread the policy through the existing tool-call chain in `AgentExecutor+ToolCalls.swift`:

```swift
let processingResult = await processToolCalls(
    turn.toolCalls,
    catalog: context.catalog,
    tool: context.tool,
    runPolicy: context.runPolicy,
    toolCallState: &toolCallState,
    continuation: context.continuation
)
```

Update `processToolCalls`:

```swift
func processToolCalls(
    _ calls: [ChatToolCall],
    catalog: AgentToolCatalog,
    tool: Tool,
    runPolicy: ExecutionRunPolicy,
    toolCallState: inout AgentToolCallRunState,
    continuation: AgentEventContinuation
) async -> AgentToolCallProcessingResult
```

Pass it into each call:

```swift
let message = await processOneToolCall(
    call,
    catalog: catalog,
    tool: tool,
    runPolicy: runPolicy,
    toolCallState: &toolCallState,
    continuation: continuation
)
```

Update `processOneToolCall`:

```swift
func processOneToolCall(
    _ call: ChatToolCall,
    catalog: AgentToolCatalog,
    tool: Tool,
    runPolicy: ExecutionRunPolicy,
    toolCallState: inout AgentToolCallRunState,
    continuation: AgentEventContinuation
) async -> ChatMessage
```

Finally, pass the policy to `callAllowedTool`:

```swift
if runPolicy.mcpToolCalls == .disabled {
    continuation.yield(.toolCallDenied(
        id: context.uiId,
        reason: "MCP calls are disabled for this Playground run"
    ))
    return toolMessage(call: context.call, content: "MCP calls are disabled for this Playground run")
}
if let reason = toolCallState.skipReason(ref: ref, args: args) {
    logger.debug("agent tool call skipped reason=\(reason.summary, privacy: .public)")
    return skipToolCall(context, reason: reason)
}
toolCallState.recordExecution(ref: ref, args: args)
let message = await callAllowedTool(
    context,
    ref: ref,
    args: args,
    tool: tool,
    runPolicy: runPolicy
)
```

The disabled-mode guard must live in `processOneToolCall` after allowlist / argument validation but before `toolCallState.skipReason(...)` and `toolCallState.recordExecution(...)`. This preserves the meaning of `AgentToolCallRunState.recordExecution`: it only counts MCP calls that are eligible for real execution. A disabled Playground MCP call still yields a tool message back to the model, but it must not consume total/per-turn/per-tool budgets or duplicate fingerprints.

- [x] **Step 4: Enforce MCP mode in tool calls**

Modify `callAllowedTool` signature in `AgentExecutor+ToolCalls.swift`:

```swift
func callAllowedTool(
    _ context: AgentToolCallContext,
    ref: MCPToolRef,
    args: MCPJSONValue.Object,
    tool: Tool,
    runPolicy: ExecutionRunPolicy
) async -> ChatMessage
```

Keep a defensive guard before broker gate as well:

```swift
        guard runPolicy.mcpToolCalls == .realWithPermissionBroker else {
            context.continuation.yield(.toolCallDenied(
                id: context.uiId,
                reason: "MCP calls are disabled for this Playground run"
            ))
            return toolMessage(call: context.call, content: "MCP calls are disabled for this Playground run")
        }
```

Update `gateMCP`:

```swift
    func gateMCP(ref: MCPToolRef, tool: Tool, runPolicy: ExecutionRunPolicy) async -> GateOutcome {
        await permissionBroker.gate(
            effective: [.mcp(server: ref.server, tools: [ref.tool])],
            provenance: tool.provenance,
            scope: .oneTime,
            isDryRun: runPolicy.mcpToolCalls != .realWithPermissionBroker
        )
    }
```

For production and confirmed Playground MCP calls, `isDryRun` is false. For disabled mode, `processOneToolCall` already returns before budget counting; the guard in `callAllowedTool` is a second safety net and should be unreachable in normal flow.

- [x] **Step 5: Pass run policy from ExecutionEngine**

Modify `ExecutionEngine+AgentPipeline.swift`:

```swift
        let stream = await agentExecutor.run(
            tool: tool,
            agent: agent,
            resolved: resolved,
            provider: provider,
            runPolicy: context.runPolicy
        )
```

- [x] **Step 6: Run focused tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'OrchestrationTests.AgentExecutorTests|OrchestrationTests.ExecutionEngineTests'
```

Expected: pass.

- [x] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/Orchestration/Executors SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+AgentPipeline.swift SliceAIKit/Tests/OrchestrationTests
git commit -m "feat: gate playground mcp tool calls"
```

## Task 4: Tool Playground Runner

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Playground/ToolPlaygroundRunner.swift`
- Modify: `SliceAIApp/AppContainer.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`

- [x] **Step 1: Write failing runner smoke test**

First widen the local test helpers in `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift` so this test can inject `PlaygroundOutputDispatcher`:

```swift
private func makeStubTool(
    id: String = "test.tool",
    permissions: [Permission] = [],
    contexts: [ContextRequest] = [],
    displayMode: DisplayMode = .window,
    sideEffects: [SideEffect] = [],
    providerSelection: ProviderSelection = .fixed(providerId: "test-provider", modelId: nil)
) -> Tool {
    let outputBinding: OutputBinding? = sideEffects.isEmpty
        ? nil
        : OutputBinding(primary: displayMode, sideEffects: sideEffects)
    return Tool(
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
        displayMode: displayMode,
        outputBinding: outputBinding,
        permissions: permissions,
        provenance: .firstParty,
        budget: nil,
        hotkey: nil,
        labelStyle: .iconAndName,
        tags: []
    )
}

private func makeStubSeed(
    isDryRun: Bool = false,
    triggerSource: TriggerSource = .floatingToolbar,
    runPolicy: ExecutionRunPolicy? = nil
) -> ExecutionSeed {
    let snapshot = SelectionSnapshot(
        text: "test selection",
        source: .accessibility,
        length: 14,
        language: nil,
        contentType: nil
    )
    let app = AppSnapshot(bundleId: "com.test.app", name: "Test App", url: nil, windowTitle: nil)
    return ExecutionSeed(
        invocationId: UUID(),
        selection: snapshot,
        frontApp: app,
        screenAnchor: .zero,
        timestamp: Date(),
        triggerSource: triggerSource,
        isDryRun: isDryRun,
        runPolicy: runPolicy
    )
}
```

Also add an optional `outputDispatcher: (any OutputDispatcherProtocol)? = nil` parameter to the local `makeEngine` helper while keeping the existing `output: MockOutputDispatcher? = nil` parameter and return tuple field unchanged. Build the engine with `outputDispatcher ?? actualOutput`. This lets the new Playground test inject `PlaygroundOutputDispatcher` without forcing existing tests that inspect `bundle.output.lifecycleCalls` to change.

Then add this test:

```swift
func test_playgroundRun_marksReportAndSkipsSideEffects() async throws {
    let output = PlaygroundOutputDispatcher()
    let bundle = try makeEngine(outputDispatcher: output, chunks: [
        ChatChunk(delta: "Hello", finishReason: nil)
    ])
    let tool = makeStubTool(
        permissions: [.clipboard],
        displayMode: .window,
        sideEffects: [.copyToClipboard]
    )
    let seed = makeStubSeed(
        isDryRun: true,
        triggerSource: .playground,
        runPolicy: .playground(allowMCPToolCalls: false)
    )

    let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

    let report = try XCTUnwrap(events.compactMap { event -> InvocationReport? in
        if case .finished(let report) = event { return report }
        return nil
    }.last)
    XCTAssertTrue(report.flags.contains(.playground))
    XCTAssertTrue(report.flags.contains(.dryRun))
    XCTAssertEqual(report.outcome, .dryRunCompleted)
    XCTAssertTrue(events.contains { event in
        if case .sideEffectSkippedDryRun(.copyToClipboard) = event { return true }
        return false
    })
}

func test_toolPlaygroundRunner_rejectsInvalidToolBeforeEngineRun() async throws {
    let output = PlaygroundOutputDispatcher()
    let bundle = try makeEngine(outputDispatcher: output, chunks: [
        ChatChunk(delta: "must not stream", finishReason: nil)
    ])
    let runner = ToolPlaygroundRunner(engine: bundle.engine)
    var tool = makeStubTool(displayMode: .window)
    tool.outputBinding = OutputBinding(primary: .file, sideEffects: [])

    let events = await collectEvents(from: runner.run(ToolPlaygroundRunRequest(
        tool: tool,
        selectionText: "hello",
        appName: "Playground",
        windowTitle: nil,
        url: nil,
        allowMCPToolCalls: false
    )))

    XCTAssertTrue(events.contains { event in
        if case .failed(.configuration(.validationFailed(_))) = event { return true }
        return false
    })
    XCTAssertFalse(events.contains { event in
        if case .llmChunk = event { return true }
        return false
    })
}
```

- [x] **Step 2: Run test to verify current gaps**

Run:

```bash
swift test --package-path SliceAIKit --filter 'OrchestrationTests.ExecutionEngineTests/test_playgroundRun_marksReportAndSkipsSideEffects|OrchestrationTests.ExecutionEngineTests/test_toolPlaygroundRunner_rejectsInvalidToolBeforeEngineRun'
```

Expected: fail until Task 1, Task 2, and `ToolPlaygroundRunner` are implemented; after those tasks, these become regression tests.

- [x] **Step 3: Add runner protocol and implementation**

Create `SliceAIKit/Sources/Orchestration/Playground/ToolPlaygroundRunner.swift`:

```swift
import CoreGraphics
import Foundation
import SliceCore

/// Playground 运行请求。
public struct ToolPlaygroundRunRequest: Sendable, Equatable {
    /// 未保存的 Tool 草稿。
    public let tool: Tool
    /// 临时 selection 文本。
    public let selectionText: String
    /// 临时前台 App 名称。
    public let appName: String
    /// 临时窗口标题。
    public let windowTitle: String?
    /// 临时 URL。
    public let url: URL?
    /// 是否允许本次运行真实调用 MCP。
    public let allowMCPToolCalls: Bool

    /// 构造 Playground 运行请求。
    public init(
        tool: Tool,
        selectionText: String,
        appName: String,
        windowTitle: String?,
        url: URL?,
        allowMCPToolCalls: Bool
    ) {
        self.tool = tool
        self.selectionText = selectionText
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.allowMCPToolCalls = allowMCPToolCalls
    }
}

/// Tool Playground 运行边界。
public protocol ToolPlaygroundRunning: Sendable {
    /// 执行一次 Playground 试跑。
    func run(_ request: ToolPlaygroundRunRequest) -> AsyncThrowingStream<ExecutionEvent, any Error>
}

/// 默认 Playground runner，复用专用 ExecutionEngine。
public struct ToolPlaygroundRunner: ToolPlaygroundRunning {
    private let engine: ExecutionEngine

    /// 构造 runner。
    public init(engine: ExecutionEngine) {
        self.engine = engine
    }

    /// 构造 seed 并调用唯一执行入口。
    public func run(_ request: ToolPlaygroundRunRequest) -> AsyncThrowingStream<ExecutionEvent, any Error> {
        do {
            try request.tool.validate()
        } catch let error as SliceError {
            return Self.failureStream(error)
        } catch {
            return Self.failureStream(.configuration(.validationFailed("Tool.validate failed")))
        }

        let seed = ExecutionSeed(
            invocationId: UUID(),
            selection: SelectionSnapshot(
                text: request.selectionText,
                source: .inputBox,
                length: request.selectionText.count,
                language: nil,
                contentType: .prose
            ),
            frontApp: AppSnapshot(
                bundleId: "com.sliceai.playground",
                name: request.appName,
                url: request.url,
                windowTitle: request.windowTitle
            ),
            screenAnchor: CGPoint(x: 0, y: 0),
            timestamp: Date(),
            triggerSource: .playground,
            isDryRun: true,
            runPolicy: .playground(allowMCPToolCalls: request.allowMCPToolCalls)
        )
        return engine.execute(tool: request.tool, seed: seed)
    }

    /// 构造一个只产出失败事件的 stream，避免非法 draft 进入 LLM / MCP 执行链。
    private static func failureStream(
        _ error: SliceError
    ) -> AsyncThrowingStream<ExecutionEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.failed(error))
            continuation.finish()
        }
    }
}
```

- [x] **Step 4: Wire a dedicated Playground engine in AppContainer**

Modify `AppContainer` to create a second `ExecutionEngine` with:

- same `ContextProviderRegistry`
- same `PermissionBroker`
- same `ProviderResolver`
- same `PromptExecutor`
- same MCP runtime and SkillRegistry
- same `CostAccounting` and `AuditLog`
- `PlaygroundOutputDispatcher()` as output
- `sideEffectExecutor: nil` because `isDryRun` prevents side effects from executing

Add to `RuntimeDependencies`:

```swift
    let playgroundRunner: any ToolPlaygroundRunning
```

In `makeV2RuntimeDependencies`, create the runner from the same engine dependencies after `executionEngine`:

```swift
let executionEngine = makeExecutionEngine(dependencies: engineDependencies)
let playgroundRunner = makePlaygroundRunner(dependencies: engineDependencies)
```

Return `playgroundRunner` from `RuntimeDependencies`. In `bootstrap()`, assign it after `v2Runtime` is created and before returning `AppContainer`:

```swift
ui.settingsViewModel.playgroundRunner = v2Runtime.playgroundRunner
```

This keeps the existing bootstrap order intact: UI panels are still created first so production output can be wired, then runtime creates the Playground runner, then Settings receives the runner before the app is exposed.

Add a helper:

```swift
private static func makePlaygroundRunner(dependencies: ExecutionEngineDependencies) -> any ToolPlaygroundRunning {
    let previewEngine = ExecutionEngine(
        contextCollector: ContextCollector(registry: dependencies.providerRegistry),
        permissionBroker: dependencies.permissionBroker,
        permissionGraph: PermissionGraph(providerRegistry: dependencies.providerRegistry),
        providerResolver: dependencies.providerResolver,
        promptExecutor: dependencies.promptExecutor,
        mcpClient: dependencies.mcpClient,
        skillRegistry: dependencies.skillRegistry,
        costAccounting: dependencies.costAccounting,
        auditLog: dependencies.auditLog,
        output: PlaygroundOutputDispatcher(),
        agentExecutor: dependencies.agentExecutor,
        sideEffectExecutor: nil
    )
    return ToolPlaygroundRunner(engine: previewEngine)
}
```

Do not call `makeContextProviderRegistry()` here. Playground must share the production `ContextProviderRegistry`; only `output` and `sideEffectExecutor` differ from the production engine.

- [x] **Step 5: Run focused tests and build**

Run:

```bash
swift test --package-path SliceAIKit --filter 'OrchestrationTests.ExecutionEngineTests|OrchestrationTests.PlaygroundOutputDispatcherTests'
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected: tests pass and App Debug build succeeds.

- [x] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Orchestration/Playground SliceAIKit/Sources/Orchestration/Output SliceAIKit/Tests/OrchestrationTests SliceAIApp/AppContainer.swift
git commit -m "feat: add tool playground runner"
```

## Task 5: ToolEditor Draft State

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/ToolEditorDraftState.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`
- Test: `SliceAIKit/Tests/SettingsUITests/ToolEditorDraftStateTests.swift`

- [x] **Step 1: Write failing draft validation tests**

Create `SliceAIKit/Tests/SettingsUITests/ToolEditorDraftStateTests.swift`:

```swift
import HotkeyManager
import SliceCore
import XCTest
@testable import SettingsUI

/// ToolEditor v2 草稿状态和保存校验测试。
final class ToolEditorDraftStateTests: XCTestCase {

    func test_existingDraftSaveDoesNotMutateOriginalUntilCommit() throws {
        let original = makePromptTool(id: "translate", name: "Translate")
        var session = ToolEditorDraftSession.existing(original: original, hotkeys: makeHotkeys())
        session.draft.tool.name = "Translate Draft"

        XCTAssertEqual(original.name, "Translate")
        XCTAssertEqual(session.draft.tool.name, "Translate Draft")
    }

    func test_validatorRejectsDuplicateToolIdForCreatingDraft() {
        let existing = makePromptTool(id: "translate", name: "Translate")
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Other"), hotkeys: makeHotkeys())

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [existing],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains(.duplicateToolId("translate")))
    }

    func test_validatorAllowsSameIdForExistingDraft() {
        let existing = makePromptTool(id: "translate", name: "Translate")
        let draft = ToolEditorDraft(
            tool: makePromptTool(id: "translate", name: "Translate Draft"),
            hotkeys: makeHotkeys()
        )

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [existing],
            availableSkills: [],
            originalToolId: "translate"
        )

        XCTAssertFalse(errors.contains(.duplicateToolId("translate")))
    }

    func test_validatorRejectsDisabledOrUnknownSkills() {
        let skill = Skill(
            id: "english",
            canonicalName: "english",
            path: URL(fileURLWithPath: "/tmp/skills/english"),
            skillFile: URL(fileURLWithPath: "/tmp/skills/english/SKILL.md"),
            manifest: SkillManifest(name: "english", description: "English"),
            resources: [],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 0)),
            source: SkillSourceRef(sourceId: "test", rootPath: "/tmp/skills"),
            state: .disabled
        )
        var tool = makeAgentTool(id: "agent")
        tool.kind = .agent(AgentTool(
            systemPrompt: "system",
            initialUserPrompt: "{{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai", modelId: nil),
            skills: [SkillReference(id: "english", pinVersion: nil)],
            mcpAllowlist: [],
            builtinCapabilities: [],
            maxSteps: 4,
            stopCondition: .finalAnswerProvided,
            toolCallPolicy: nil
        ))

        let errors = ToolDraftValidator.validate(
            draft: ToolEditorDraft(tool: tool, hotkeys: makeHotkeys()),
            existingTools: [tool],
            availableSkills: [skill],
            originalToolId: "agent"
        )

        XCTAssertTrue(errors.contains(.skillNotEnabled("english")))
    }

    func test_validatorRejectsToolHotkeyConflictWithCommandPalette() {
        var hotkeys = makeHotkeys()
        hotkeys.tools["translate"] = "option+space"
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Translate"), hotkeys: hotkeys)

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains { error in
            if case .hotkeyConflict = error { return true }
            return false
        })
    }

    func test_validatorRejectsLegacyFallbackToolHotkeyConflict() {
        var other = makePromptTool(id: "summarize", name: "Summarize")
        other.hotkey = "command+k"
        var hotkeys = makeHotkeys()
        hotkeys.tools["translate"] = "command+k"
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Translate"), hotkeys: hotkeys)

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [other],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains { error in
            if case .hotkeyConflict = error { return true }
            return false
        })
    }

    func test_validatorRejectsInvalidToolHotkey() {
        var hotkeys = makeHotkeys()
        hotkeys.tools["translate"] = "not-a-hotkey"
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Translate"), hotkeys: hotkeys)

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains(.invalidHotkey("not-a-hotkey")))
    }

    private func makePromptTool(id: String, name: String) -> Tool {
        Tool(
            id: id,
            name: name,
            icon: "wand.and.stars",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: nil,
                userPrompt: "{{selection}}",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
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
            labelStyle: .icon,
            tags: []
        )
    }

    private func makeAgentTool(id: String) -> Tool {
        Tool(
            id: id,
            name: "Agent",
            icon: "brain",
            description: nil,
            kind: .agent(AgentTool(
                systemPrompt: "system",
                initialUserPrompt: "{{selection}}",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
                skills: [],
                mcpAllowlist: [],
                builtinCapabilities: [],
                maxSteps: 4,
                stopCondition: .finalAnswerProvided,
                toolCallPolicy: nil
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
    }

    private func makeHotkeys() -> HotkeyBindings {
        HotkeyBindings(toggleCommandPalette: "option+space")
    }
}
```

The helper implementations above intentionally use public `Tool`, `PromptTool`, `AgentTool`, `Skill`, and `HotkeyBindings` initializers so failures point at production model contracts rather than test-only shortcuts.

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path SliceAIKit --filter SettingsUITests.ToolEditorDraftStateTests
```

Expected: compile failure because draft types do not exist.

- [x] **Step 3: Implement draft session and validator**

Create `SliceAIKit/Sources/SettingsUI/ToolEditorDraftState.swift`:

```swift
import Foundation
import HotkeyManager
import SliceCore

/// ToolEditor v2 的可保存草稿。
public struct ToolEditorDraft: Sendable, Equatable {
    /// 未保存的 Tool 草稿。
    public var tool: Tool
    /// 未保存的 hotkey 草稿。
    public var hotkeys: HotkeyBindings

    /// 构造草稿。
    public init(tool: Tool, hotkeys: HotkeyBindings) {
        self.tool = tool
        self.hotkeys = hotkeys
    }
}

/// ToolEditor 当前会话。
public enum ToolEditorDraftSession: Sendable, Equatable {
    /// 编辑已有工具。
    case editingExisting(original: Tool, draft: ToolEditorDraft)
    /// 创建新工具。
    case creating(draft: ToolEditorDraft)

    /// 创建已有工具编辑会话。
    public static func existing(original: Tool, hotkeys: HotkeyBindings) -> ToolEditorDraftSession {
        .editingExisting(original: original, draft: ToolEditorDraft(tool: original, hotkeys: hotkeys))
    }

    /// 当前草稿。
    public var draft: ToolEditorDraft {
        get {
            switch self {
            case .editingExisting(_, let draft), .creating(let draft): return draft
            }
        }
        set {
            switch self {
            case .editingExisting(let original, _): self = .editingExisting(original: original, draft: newValue)
            case .creating: self = .creating(draft: newValue)
            }
        }
    }

    /// 已有工具原始 id；创建新工具时为 nil。
    public var originalToolId: String? {
        if case .editingExisting(let original, _) = self { return original.id }
        return nil
    }
}

/// Tool 草稿校验错误。
public enum ToolDraftValidationError: Sendable, Equatable, LocalizedError {
    case duplicateToolId(String)
    case invalidTool(String)
    case skillNotEnabled(String)
    case invalidHotkey(String)
    case hotkeyConflict(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateToolId(let id): return "工具 id 已存在：\(id)"
        case .invalidTool(let message): return message
        case .skillNotEnabled(let skill): return "Skill 未启用或不存在：\(skill)"
        case .invalidHotkey(let hotkey): return "快捷键无效：\(hotkey)"
        case .hotkeyConflict(let hotkey): return "快捷键冲突：\(hotkey)"
        }
    }
}

/// ToolEditor v2 草稿保存前校验。
public enum ToolDraftValidator {
    /// 校验草稿。
    public static func validate(
        draft: ToolEditorDraft,
        existingTools: [Tool],
        availableSkills: [SliceCore.Skill],
        originalToolId: String?
    ) -> [ToolDraftValidationError] {
        var errors: [ToolDraftValidationError] = []
        if existingTools.contains(where: { $0.id == draft.tool.id && $0.id != originalToolId }) {
            errors.append(.duplicateToolId(draft.tool.id))
        }
        do {
            try draft.tool.validate()
        } catch {
            errors.append(.invalidTool(error.localizedDescription))
        }
        errors.append(contentsOf: validateSkills(tool: draft.tool, availableSkills: availableSkills))
        errors.append(contentsOf: validateHotkeys(draft: draft, tools: existingTools, originalToolId: originalToolId))
        return errors
    }

    /// 校验 Agent skill 绑定必须来自 enabled skills。
    private static func validateSkills(
        tool: Tool,
        availableSkills: [SliceCore.Skill]
    ) -> [ToolDraftValidationError] {
        guard case .agent(let agent) = tool.kind else { return [] }
        let enabled = Set(availableSkills.filter { $0.state == .enabled }.map(\.id))
        return agent.skills
            .map(\.id)
            .filter { !enabled.contains($0) }
            .map { .skillNotEnabled($0) }
    }

    /// 校验工具热键不与命令面板或其它工具冲突。
    private static func validateHotkeys(
        draft: ToolEditorDraft,
        tools: [Tool],
        originalToolId: String?
    ) -> [ToolDraftValidationError] {
        var comparisonTools = tools.filter { tool in
            tool.id != originalToolId && tool.id != draft.tool.id
        }
        comparisonTools.append(draft.tool)
        let effectiveToolHotkeys = HotkeyBindingValidator.effectiveToolHotkeys(
            bindings: draft.hotkeys,
            tools: comparisonTools
        )
        let issues = HotkeyBindingValidator.issues(
            commandPalette: draft.hotkeys.toggleCommandPalette,
            tools: effectiveToolHotkeys
        )
        return issues.compactMap { issue in
            guard HotkeyBindingValidator.issue(issue, involves: draft.tool.id) else { return nil }
            switch issue {
            case .invalidCommandPalette:
                return nil
            case .invalidTool(_, let rawHotkey):
                return .invalidHotkey(rawHotkey)
            case .commandPaletteConflict(_, let normalizedHotkey):
                return .hotkeyConflict(normalizedHotkey)
            case .toolConflict(_, _, let normalizedHotkey):
                return .hotkeyConflict(normalizedHotkey)
            }
        }
    }
}
```

- [x] **Step 4: Update ToolEditorView wording and init docs**

Modify the top comment in `ToolEditorView.swift` so it no longer says the binding always points directly to production configuration:

```swift
/// 单个 Tool 的编辑表单。
///
/// v2 中该 binding 可以指向 `ToolEditorDraftSession` 的本地草稿；
/// 只有外层页面执行 Save 时，草稿才会写回 `Configuration.tools`。
```

- [x] **Step 5: Run focused SettingsUI tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SettingsUITests.ToolEditorDraftStateTests|SettingsUITests.ToolEditorSkillsBindingTests|SettingsUITests.ToolEditorAgentAllowlistCodecTests'
```

Expected: pass.

- [x] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SettingsUI/ToolEditorDraftState.swift SliceAIKit/Sources/SettingsUI/ToolEditorView.swift SliceAIKit/Tests/SettingsUITests/ToolEditorDraftStateTests.swift
git commit -m "feat: add tool editor draft state"
```

## Task 6: Playground State Reducer

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/ToolPlaygroundState.swift`
- Test: `SliceAIKit/Tests/SettingsUITests/ToolPlaygroundStateTests.swift`

- [x] **Step 1: Write failing state reducer tests**

Create `SliceAIKit/Tests/SettingsUITests/ToolPlaygroundStateTests.swift`:

```swift
import XCTest
import SliceCore
import Orchestration
@testable import SettingsUI

/// Playground UI 状态 reducer 测试。
final class ToolPlaygroundStateTests: XCTestCase {

    func test_reduceStreamingChunksAccumulatesText() {
        var state = ToolPlaygroundState()
        state.reduce(.started(invocationId: UUID()), tool: makeTool(displayMode: .window))
        state.reduce(.llmChunk(delta: "hello"), tool: makeTool(displayMode: .window))
        state.reduce(.llmChunk(delta: " world"), tool: makeTool(displayMode: .window))

        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(state.streamedText, "hello world")
    }

    func test_finishStructuredParsesTopLevelJSONObject() {
        var state = ToolPlaygroundState()
        let tool = makeTool(displayMode: .structured)
        state.reduce(.llmChunk(delta: #"{"word":"hello","score":1}"#), tool: tool)
        state.reduce(.finished(report: .stub(flags: [.playground, .dryRun], outcome: .dryRunCompleted)), tool: tool)

        XCTAssertEqual(state.status, .succeeded)
        XCTAssertEqual(state.displayPreview.kind, .structured)
        XCTAssertTrue(state.displayPreview.summary.contains("word"))
    }

    func test_fileModeShowsWouldAppendSummary() {
        var state = ToolPlaygroundState()
        let tool = makeFileTool(path: "/tmp/out.md")
        state.reduce(.llmChunk(delta: "result"), tool: tool)
        state.reduce(.finished(report: .stub(flags: [.playground], outcome: .dryRunCompleted)), tool: tool)

        XCTAssertEqual(state.displayPreview.kind, .file)
        XCTAssertTrue(state.displayPreview.summary.contains("would append"))
        XCTAssertTrue(state.displayPreview.summary.contains("/tmp/out.md"))
    }

    func test_promptAndPermissionEventsAreRecordedForPreview() {
        var state = ToolPlaygroundState()
        let tool = makeTool(displayMode: .window)

        state.reduce(.promptRendered(preview: "redacted prompt"), tool: tool)
        state.reduce(
            .permissionWouldBeRequested(permission: .clipboard, uxHint: "Clipboard access"),
            tool: tool
        )

        XCTAssertEqual(state.promptPreview, "redacted prompt")
        XCTAssertTrue(state.permissionRows.contains { row in
            row.contains("Clipboard access")
        })
    }

    func test_finishedAndFailedExposeReportAndErrorSummaries() {
        var state = ToolPlaygroundState()
        let tool = makeTool(displayMode: .window)
        let report = InvocationReport(
            invocationId: UUID(),
            toolId: "tool",
            declaredPermissions: [],
            effectivePermissions: [],
            flags: [.playground, .dryRun],
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 1),
            totalTokens: 12,
            estimatedCostUSD: Decimal(string: "0.42")!,
            outcome: .dryRunCompleted
        )

        state.reduce(.finished(report: report), tool: tool)

        XCTAssertTrue(state.reportSummary.contains("12"))
        XCTAssertTrue(state.reportSummary.contains("0.42"))
        XCTAssertTrue(state.reportSummary.contains("playground"))

        state.reduce(.failed(.provider(.unauthorized)), tool: tool)

        XCTAssertEqual(state.errorMessage, SliceError.provider(.unauthorized).userMessage)
    }

    private func makeTool(displayMode: DisplayMode) -> Tool {
        Tool(
            id: "tool",
            name: "Tool",
            icon: "wand.and.stars",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: nil,
                userPrompt: "{{selection}}",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
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
            labelStyle: .icon,
            tags: []
        )
    }

    private func makeFileTool(path: String) -> Tool {
        var tool = makeTool(displayMode: .file)
        tool.outputBinding = OutputBinding(
            primary: .file,
            sideEffects: [.appendToFile(path: path, header: nil)]
        )
        return tool
    }
}
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --package-path SliceAIKit --filter SettingsUITests.ToolPlaygroundStateTests
```

Expected: compile failure because `ToolPlaygroundState` does not exist and SettingsUI does not import Orchestration yet.

- [x] **Step 3: Add Orchestration dependency to SettingsUI**

Modify `SliceAIKit/Package.swift`:

```swift
        .target(name: "SettingsUI",
                dependencies: [
                    "SliceCore",
                    "LLMProviders",
                    "HotkeyManager",
                    "DesignSystem",
                    "Permissions",
                    "Capabilities",
                    "Orchestration",
                ],
                swiftSettings: swiftSettings),
```

Also add `Orchestration` to `SettingsUITests` because the reducer tests import `ExecutionEvent`:

```swift
        .testTarget(name: "SettingsUITests",
                    dependencies: ["SettingsUI", "SliceCore", "Capabilities", "Orchestration"],
                    swiftSettings: swiftSettings),
```

SettingsUI depending on Orchestration is acceptable for Phase 3 because Playground is a Settings feature that consumes `ExecutionEvent`. Do not make Orchestration depend on SettingsUI.

- [x] **Step 4: Implement ToolPlaygroundState**

Create `SliceAIKit/Sources/SettingsUI/ToolPlaygroundState.swift`:

```swift
import Foundation
import Orchestration
import SliceCore

/// Playground 运行状态。
public enum ToolPlaygroundRunStatus: Sendable, Equatable {
    case idle
    case running
    case cancelling
    case succeeded
    case failed(String)
}

/// DisplayMode 预览类型。
public enum ToolPlaygroundPreviewKind: Sendable, Equatable {
    case window
    case bubble
    case replace
    case file
    case silent
    case structured
}

/// Playground DisplayMode 预览摘要。
public struct ToolPlaygroundDisplayPreview: Sendable, Equatable {
    public var kind: ToolPlaygroundPreviewKind
    public var summary: String
}

/// Playground UI 状态。
public struct ToolPlaygroundState: Sendable, Equatable {
    public var selectionText = ""
    public var appName = "Playground"
    public var windowTitle = ""
    public var urlText = ""
    public var allowMCPToolCalls = false
    public var status: ToolPlaygroundRunStatus = .idle
    public var streamedText = ""
    public var promptPreview = ""
    public var toolCallRows: [String] = []
    public var permissionRows: [String] = []
    public var skippedSideEffects: [String] = []
    public var displayPreview = ToolPlaygroundDisplayPreview(kind: .window, summary: "")
    public var lastReport: InvocationReport?
    public var reportSummary = ""
    public var errorMessage: String?

    /// 构造空状态。
    public init() {}

    /// 根据 ExecutionEvent 更新 UI 状态。
    public mutating func reduce(_ event: ExecutionEvent, tool: Tool) {
        switch event {
        case .started:
            status = .running
            streamedText = ""
            promptPreview = ""
            toolCallRows = []
            permissionRows = []
            skippedSideEffects = []
            lastReport = nil
            reportSummary = ""
            errorMessage = nil
            displayPreview = preview(for: tool, finalText: "")
        case .promptRendered(let preview):
            promptPreview = preview
        case .permissionWouldBeRequested(let permission, let uxHint):
            permissionRows.append("would request \(permission.playgroundName): \(uxHint)")
        case .llmChunk(let delta):
            streamedText += delta
        case .toolCallProposed(_, let ref, _):
            toolCallRows.append("proposed \(ref.server).\(ref.tool)")
        case .toolCallApproved:
            toolCallRows.append("approved")
        case .toolCallDenied(_, let reason):
            toolCallRows.append("denied \(reason)")
        case .toolCallResult(_, let summary):
            toolCallRows.append("result \(summary)")
        case .toolCallError(_, let summary):
            toolCallRows.append("error \(summary)")
        case .sideEffectSkippedDryRun(let sideEffect):
            skippedSideEffects.append(sideEffect.previewName)
        case .finished(let report):
            status = .succeeded
            lastReport = report
            reportSummary = report.playgroundSummary
            displayPreview = preview(for: tool, finalText: streamedText)
        case .failed(let error):
            errorMessage = error.userMessage
            status = .failed(error.userMessage)
            displayPreview = preview(for: tool, finalText: streamedText)
        default:
            break
        }
    }

    /// 生成 DisplayMode 预览。
    private func preview(for tool: Tool, finalText: String) -> ToolPlaygroundDisplayPreview {
        switch tool.displayMode {
        case .window:
            return .init(kind: .window, summary: finalText)
        case .bubble:
            return .init(kind: .bubble, summary: "would show bubble: \(finalText)")
        case .replace:
            return .init(kind: .replace, summary: "would replace selected text: \(finalText)")
        case .file:
            let path = tool.outputBinding?.appendToFilePreviewPath ?? "<missing appendToFile path>"
            return .init(kind: .file, summary: "would append to \(path): \(finalText)")
        case .silent:
            return .init(kind: .silent, summary: "silent dry-run final text: \(finalText)")
        case .structured:
            return .init(kind: .structured, summary: structuredSummary(finalText))
        }
    }

    /// 生成结构化 JSON 预览摘要。
    private func structuredSummary(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return "structured parse error"
        }
        return object.keys.sorted().joined(separator: ", ")
    }
}

private extension SideEffect {
    /// Playground side effect 预览名称。
    var previewName: String {
        switch self {
        case .appendToFile(let path, _): return "would append to \(path)"
        case .copyToClipboard: return "would copy to clipboard"
        case .notify: return "would notify"
        case .runAppIntent: return "would run AppIntent"
        case .callMCP(let ref, _): return "would call MCP \(ref.server).\(ref.tool)"
        case .writeMemory: return "would write memory"
        case .tts: return "would speak"
        }
    }
}

private extension Permission {
    /// Playground permission 预览名称。
    var playgroundName: String {
        String(describing: self)
    }
}

private extension InvocationReport {
    /// Playground report 摘要，供右侧面板显示 tokens / cost / flags。
    var playgroundSummary: String {
        let flagsText = flags.map(\.rawValue).sorted().joined(separator: ", ")
        return "tokens \(totalTokens), cost \(estimatedCostUSD), outcome \(outcome.playgroundName), flags \(flagsText)"
    }
}

private extension InvocationOutcome {
    /// Playground outcome 预览名称。
    var playgroundName: String {
        switch self {
        case .success:
            return "success"
        case .dryRunCompleted:
            return "dry-run completed"
        case .failed(let errorKind):
            return "failed \(errorKind.rawValue)"
        }
    }
}

private extension OutputBinding {
    /// `.file` 预览路径。
    var appendToFilePreviewPath: String? {
        for sideEffect in sideEffects {
            if case .appendToFile(let path, _) = sideEffect { return path }
        }
        return nil
    }
}
```

- [x] **Step 5: Run reducer tests**

Run:

```bash
swift test --package-path SliceAIKit --filter SettingsUITests.ToolPlaygroundStateTests
```

Expected: pass after adding test helper factories.

- [x] **Step 6: Commit**

```bash
git add SliceAIKit/Package.swift SliceAIKit/Sources/SettingsUI/ToolPlaygroundState.swift SliceAIKit/Tests/SettingsUITests/ToolPlaygroundStateTests.swift
git commit -m "feat: add tool playground state reducer"
```

## Task 7: Settings UI Integration

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/ToolPlaygroundView.swift`
- Create: `SliceAIKit/Sources/SettingsUI/ToolEditorV2View.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Actions.swift`
- Test: `SliceAIKit/Tests/SettingsUITests/ToolEditorDraftStateTests.swift`

- [x] **Step 1: Add Playground runner to SettingsViewModel**

Modify `SettingsViewModel` imports and initializer:

```swift
import Orchestration
```

```swift
    /// Settings Playground runner；nil 时隐藏 Playground 运行按钮。
    @Published public var playgroundRunner: (any ToolPlaygroundRunning)?
```

```swift
        skillRegistry: any SkillRegistryProtocol = MockSkillRegistry(),
        playgroundRunner: (any ToolPlaygroundRunning)? = nil
```

Assign:

```swift
        self.playgroundRunner = playgroundRunner
```

- [x] **Step 2: Create ToolPlaygroundView**

Create `SliceAIKit/Sources/SettingsUI/ToolPlaygroundView.swift`:

```swift
import DesignSystem
import Orchestration
import SliceCore
import SwiftUI

/// ToolEditor 右侧 Playground 视图。
struct ToolPlaygroundView: View {
    let tool: Tool
    let runner: (any ToolPlaygroundRunning)?
    let validateBeforeRun: () -> [ToolDraftValidationError]
    @Binding var state: ToolPlaygroundState

    @State private var runTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.base) {
            header
            inputs
            controls
            output
        }
        .frame(minWidth: 280, minHeight: 360)
    }

    private var header: some View {
        HStack {
            Text("Playground")
                .font(SliceFont.headline)
            Spacer()
            Text("side effects dry-run")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textSecondary)
        }
    }

    private var inputs: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.sm) {
            PromptTextEditor(
                label: "Selection",
                placeholder: "输入本次试跑的选区文本",
                required: true,
                text: $state.selectionText,
                minHeight: 88
            )
            Toggle("允许本次运行调用 MCP tools", isOn: $state.allowMCPToolCalls)
                .font(SliceFont.caption)
        }
    }

    private var controls: some View {
        HStack {
            PillButton("Run", icon: "play.fill", style: .primary) { startRun() }
                .disabled(runner == nil || state.selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            PillButton("Cancel", icon: "stop.fill", style: .secondary) { cancelRun() }
                .disabled(runTask == nil)
            PillButton("Clear", icon: "xmark", style: .secondary) { state = ToolPlaygroundState() }
        }
    }

    private var output: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SliceSpacing.sm) {
                if !state.promptPreview.isEmpty {
                    Text(state.promptPreview)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                        .textSelection(.enabled)
                }
                ForEach(Array(state.permissionRows.enumerated()), id: \.offset) { _, row in
                    Text(row).font(SliceFont.caption).foregroundColor(SliceColor.warning)
                }
                if let errorMessage = state.errorMessage {
                    Text(errorMessage).font(SliceFont.caption).foregroundColor(SliceColor.error)
                }
                Text(state.streamedText.isEmpty ? state.displayPreview.summary : state.streamedText)
                    .font(SliceFont.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(state.toolCallRows.enumerated()), id: \.offset) { _, row in
                    Text(row).font(SliceFont.caption).foregroundColor(SliceColor.textSecondary)
                }
                ForEach(Array(state.skippedSideEffects.enumerated()), id: \.offset) { _, row in
                    Text(row).font(SliceFont.caption).foregroundColor(SliceColor.textSecondary)
                }
                if !state.reportSummary.isEmpty {
                    Text(state.reportSummary).font(SliceFont.caption).foregroundColor(SliceColor.textSecondary)
                }
            }
            .padding(SliceSpacing.base)
        }
        .frame(minHeight: 180)
        .background(SliceColor.background)
        .clipShape(RoundedRectangle(cornerRadius: SliceRadius.control))
    }

    /// 启动一次 Playground 运行。
    private func startRun() {
        guard let runner else { return }
        let validationErrors = validateBeforeRun()
        guard validationErrors.isEmpty else {
            let message = validationErrors.map { $0.localizedDescription }.joined(separator: "\n")
            state.status = .failed(message)
            state.errorMessage = message
            print("[ToolPlaygroundView] startRun blocked by validation errors count=\(validationErrors.count)")
            return
        }
        runTask?.cancel()
        state.status = .running
        let request = ToolPlaygroundRunRequest(
            tool: tool,
            selectionText: state.selectionText,
            appName: state.appName,
            windowTitle: state.windowTitle.isEmpty ? nil : state.windowTitle,
            url: URL(string: state.urlText),
            allowMCPToolCalls: state.allowMCPToolCalls
        )
        runTask = Task { @MainActor in
            do {
                for try await event in runner.run(request) {
                    state.reduce(event, tool: tool)
                }
            } catch {
                state.status = .failed(error.localizedDescription)
            }
            runTask = nil
        }
    }

    /// 取消当前 Playground 运行。
    private func cancelRun() {
        state.status = .cancelling
        runTask?.cancel()
        runTask = nil
    }
}
```

- [x] **Step 3: Create ToolEditorV2View**

Create `SliceAIKit/Sources/SettingsUI/ToolEditorV2View.swift`:

```swift
import DesignSystem
import Orchestration
import SliceCore
import SwiftUI

/// ToolEditor v2：左侧草稿编辑器，右侧 Playground。
struct ToolEditorV2View: View {
    @Binding var draft: ToolEditorDraft
    let providers: [Provider]
    let tools: [Tool]
    let availableSkills: [SliceCore.Skill]
    let runner: (any ToolPlaygroundRunning)?
    let validateDraft: (ToolEditorDraft) -> [ToolDraftValidationError]
    let onSave: () -> Void
    let onRevert: () -> Void

    @State private var playgroundState = ToolPlaygroundState()

    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.base) {
            toolbar
            HStack(alignment: .top, spacing: SliceSpacing.lg) {
                ToolEditorView(
                    tool: $draft.tool,
                    providers: providers,
                    tools: tools,
                    hotkeys: $draft.hotkeys,
                    availableSkills: availableSkills,
                    onHotkeyCommit: nil
                )
                .frame(minWidth: 300)

                ToolPlaygroundView(
                    tool: draft.tool,
                    runner: runner,
                    validateBeforeRun: { validateDraft(draft) },
                    state: $playgroundState
                )
            }
        }
    }

    private var toolbar: some View {
        HStack {
            Text("Unsaved draft")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textSecondary)
            Spacer()
            PillButton("Revert", icon: "arrow.uturn.backward", style: .secondary, action: onRevert)
            PillButton("Save", icon: "checkmark", style: .primary, action: onSave)
        }
    }
}
```

- [x] **Step 4: Replace direct binding in ToolsSettingsPage**

In `ToolsSettingsPage`, replace `expandedId` with:

```swift
    @State var editingSession: ToolEditorDraftSession?
    @State var validationErrors: [ToolDraftValidationError] = []
```

Update row toggle:

```swift
if case .editingExisting(let original, _) = editingSession, original.id == tool.id {
    editingSession = nil
} else {
    editingSession = .existing(
        original: tool,
        hotkeys: viewModel.configuration.hotkeys
    )
    validationErrors = []
}
```

Add a creation editor directly under `actionRow` so Add Prompt / Add Agent can open a draft without mutating `configuration.tools`:

```swift
if case .creating = editingSession {
    toolEditorV2(fallbackTool: nil)
}
```

Render editor:

```swift
if isEditing(tool.id) {
    toolEditorV2(fallbackTool: tool)
}
```

Add the editing predicate:

```swift
private func isEditing(_ toolId: String) -> Bool {
    guard case .editingExisting(let original, _) = editingSession else { return false }
    return original.id == toolId
}
```

Implement `toolEditorV2(fallbackTool:)` with a local binding to the current session draft. The fallback avoids array-out-of-bounds crashes during SwiftUI transient re-render after a session closes:

```swift
private func toolEditorV2(fallbackTool: Tool?) -> some View {
    let binding = Binding<ToolEditorDraft>(
        get: {
            if let editingSession {
                return editingSession.draft
            }
            let tool = fallbackTool ?? viewModel.configuration.tools.first ?? makeEmptyPromptDraftTool()
            return ToolEditorDraft(tool: tool, hotkeys: viewModel.configuration.hotkeys)
        },
        set: { newDraft in
            editingSession?.draft = newDraft
        }
    )
    return ToolEditorV2View(
        draft: binding,
        providers: viewModel.configuration.providers,
        tools: viewModel.configuration.tools,
        availableSkills: viewModel.availableAgentSkills,
        runner: viewModel.playgroundRunner,
        validateDraft: validateDraftForRun,
        onSave: saveEditingSession,
        onRevert: revertEditingSession
    )
    .padding(SliceSpacing.xl)
}
```

Render validation errors near the editor so Save failures are visible:

```swift
private var validationErrorList: some View {
    VStack(alignment: .leading, spacing: SliceSpacing.xs) {
        ForEach(Array(validationErrors.enumerated()), id: \.offset) { _, error in
            Text(error.localizedDescription)
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.error)
        }
    }
}
```

Call `validationErrorList` inside the editor container when `validationErrors` is not empty.

Add the shared validation closure used by both Save and Playground Run:

```swift
private func validateDraftForRun(_ draft: ToolEditorDraft) -> [ToolDraftValidationError] {
    ToolDraftValidator.validate(
        draft: draft,
        existingTools: viewModel.configuration.tools,
        availableSkills: viewModel.availableAgentSkills,
        originalToolId: editingSession?.originalToolId
    )
}
```

Replace all remaining `expandedId` usages:

```swift
private func clearEditingSessionIfNeeded(toolId: String) {
    if case .editingExisting(let original, _) = editingSession, original.id == toolId {
        editingSession = nil
    }
}
```

Use this helper in `performDelete(id:)` and set `editingSession = nil` when a drag starts, preserving the current behavior that collapses an open editor before reordering.

Add the fallback draft factory:

```swift
private func makeEmptyPromptDraftTool() -> Tool {
    let providerId = viewModel.configuration.providers.first?.id ?? ""
    return Tool(
        id: makeNewToolID(prefix: "tool"),
        name: "新工具",
        icon: "wand.and.stars",
        description: nil,
        kind: .prompt(PromptTool(
            systemPrompt: nil,
            userPrompt: "{{selection}}",
            contexts: [],
            provider: .fixed(providerId: providerId, modelId: nil),
            temperature: 0.7,
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
        labelStyle: .icon,
        tags: []
    )
}
```

- [x] **Step 5: Implement Save/Revert actions**

Add in `ToolsSettingsPage+Actions.swift`:

```swift
/// 保存当前 ToolEditor 草稿。
func saveEditingSession() {
    guard let session = editingSession else { return }
    let previousHotkeys = viewModel.configuration.hotkeys
    let errors = validateDraftForRun(session.draft)
    guard errors.isEmpty else {
        validationErrors = errors
        print("[ToolsSettingsPage] saveEditingSession: validation failed count=\(errors.count)")
        return
    }

    switch session {
    case .editingExisting(let original, let draft):
        guard let index = viewModel.configuration.tools.firstIndex(where: { $0.id == original.id }) else { return }
        viewModel.configuration.tools[index] = draft.tool
        viewModel.configuration.hotkeys = draft.hotkeys
        if original.id != draft.tool.id {
            viewModel.configuration.hotkeys.tools.removeValue(forKey: original.id)
        }
    case .creating(let draft):
        guard !viewModel.configuration.tools.contains(where: { $0.id == draft.tool.id }) else {
            validationErrors = [.duplicateToolId(draft.tool.id)]
            print("[ToolsSettingsPage] saveEditingSession: duplicate creating id=\(draft.tool.id)")
            return
        }
        viewModel.configuration.tools.append(draft.tool)
        viewModel.configuration.hotkeys = draft.hotkeys
    }
    validationErrors = []
    editingSession = nil
    if previousHotkeys != viewModel.configuration.hotkeys {
        print("[ToolsSettingsPage] saveEditingSession: hotkeys changed, reloading registrations")
        Task {
            await viewModel.saveHotkeys()
        }
    } else {
        scheduleDebouncedSave()
    }
}

/// 放弃当前草稿。
func revertEditingSession() {
    print("[ToolsSettingsPage] revertEditingSession")
    validationErrors = []
    editingSession = nil
}
```

Update Add Prompt / Add Agent to create `.creating` sessions instead of immediately appending:

```swift
// Remove the existing `viewModel.configuration.tools.append(newTool)` call.
// Remove the old `expandedId = newId` animation block.
editingSession = .creating(draft: ToolEditorDraft(tool: newTool, hotkeys: viewModel.configuration.hotkeys))
validationErrors = []
```

After this change, clicking Add Prompt / Add Agent must not mutate `viewModel.configuration.tools` and must not trigger the `.onChange(of: viewModel.configuration.tools)` debounced save hook. The only write path for a newly created tool is `saveEditingSession()`.

- [x] **Step 6: Run SettingsUI tests**

Run:

```bash
swift test --package-path SliceAIKit --filter SettingsUITests
```

Expected: pass.

- [x] **Step 7: Run App build**

Run:

```bash
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected: BUILD SUCCEEDED. Increase the `SettingsScene` frame from `720×520` to `980×620` in this task because ToolEditor v2 intentionally uses a two-column editor + Playground layout; document the sizing change in the task detail.

- [x] **Step 8: Commit**

```bash
git add SliceAIKit/Sources/SettingsUI SliceAIKit/Tests/SettingsUITests SliceAIKit/Package.swift SliceAIApp/AppContainer.swift
git commit -m "feat: add tool editor playground ui"
```

## Task 8: Documentation And Final Gate

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `docs/v2-refactor-master-todolist.md`
- Modify: `docs/Task_history.md`
- Modify: `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`
- Modify: `docs/Module/Orchestration.md`
- Create: `docs/Module/SettingsUI.md`

- [x] **Step 1: Update module docs**

Update `docs/Module/Orchestration.md` with:

```markdown
### Playground Run Policy

Phase 3 增加 `ExecutionRunPolicy`：

- production：生产触发，输出走生产 sink，side effects 由 `isDryRun` 决定是否执行。
- playground：Settings Playground 触发，真实 LLM，side effects dry-run，输出走 preview sink。
- Playground MCP 默认 disabled；用户显式允许后才进入 allowlist + PermissionBroker + MCP client。

`ExecutionEngine.execute(tool:seed:)` 仍是唯一执行入口；Playground 通过专用 runner 和专用 output dispatcher 复用同一执行链。
```

Create or update `docs/Module/SettingsUI.md` with:

```markdown
# SettingsUI

## ToolEditor v2

ToolEditor v2 使用 `ToolEditorDraftSession` 保存未提交草稿。左侧编辑器修改 draft，不直接写 `Configuration.tools`；点击 Save 后通过 `ToolDraftValidator` 校验并写回配置。Revert 丢弃草稿。

右侧 Prompt Playground 使用 `ToolPlaygroundView` 和 `ToolPlaygroundState` 消费 Orchestration `ExecutionEvent`。Playground run 的 LLM 可真实调用，side effects 只 dry-run，MCP tool call 默认禁用，必须由用户显式打开本次运行开关。
```

- [x] **Step 2: Update project status docs**

Update `README.md` Current Features after implementation:

```markdown
- ToolEditor v2 + Prompt Playground MVP：支持在 Settings 中编辑未保存 Tool 草稿并试跑；Prompt / Agent Tool 复用真实 ExecutionEngine，输出进入右侧 preview，side effects dry-run，MCP tool call 默认禁用并需本次运行显式确认。
```

Update `AGENTS.md` current facts and unfinished list:

```markdown
- Phase 3 ToolEditor v2 + Prompt Playground MVP 已完成首个实现切片。
- 样本持久化、A/B 对比、版本历史、原生 Anthropic / Gemini / Ollama、Memory 和 Cost Panel 仍未实现。
```

Update `docs/v2-refactor-master-todolist.md` dashboard:

```markdown
| 当前 Milestone | **Phase 3 ToolEditor v2 + Prompt Playground MVP implementation** |
| 下一个动作 | 做 Phase 3 Playground 真实 App smoke，确认后评估样本管理 / A-B / 原生 provider 的下一切片 |
```

- [x] **Step 3: Run final gate**

Run:

```bash
swift test --package-path SliceAIKit
swiftlint lint --strict
git diff --check
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected:

- SwiftPM tests pass.
- SwiftLint reports 0 violations when `swiftlint` is available in the local environment. On the 2026-05-28/29
  implementation machine, `swiftlint` was not in `PATH`; the attempted gate and environment gap are recorded in
  `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md` and the compliance audit.
- `git diff --check` prints no output.
- Xcode build prints `** BUILD SUCCEEDED **`.

- [x] **Step 4: Commit**

```bash
git add README.md AGENTS.md docs SliceAIKit SliceAIApp
git commit -m "docs: record phase 3 playground implementation"
```

## Self-Review

Spec coverage:

- ToolEditor draft semantics: Task 5 and Task 7.
- Prompt / Agent Tool Playground: Task 4, Task 6, Task 7.
- Real LLM via existing execution chain: Task 4 uses dedicated `ExecutionEngine`.
- MCP explicit confirmation: Task 3 and Task 7.
- Disabled MCP cannot consume tool-call budget: Task 3 regression test and pre-`recordExecution` guard.
- Side effects dry-run: Task 1, Task 2, Task 4, Task 6.
- Preview output and no production ResultPanel/Bubble/replace/file writes: Task 2 and Task 6.
- Run-before-save validation: Task 4 guards core `Tool.validate()` and Task 7 uses `ToolDraftValidator` before Playground run.
- Hotkey validation / registration: Task 5 reuses `HotkeyBindingValidator`; Task 7 calls `saveHotkeys()` after hotkey-changing saves.
- Playground prompt / permission / error / cost display: Task 6 state reducer and Task 7 right-side view.
- Telemetry/cost compatibility: Task 1.
- No new config schema: plan only adds runtime/telemetry state, not `Configuration` fields.
- Non-goals preserved: no provider expansion, Memory, Cost Panel, A/B, sample persistence, version history, scripts execution, marketplace, or pipeline executor.

Execution notes:

- Do not implement this plan on `main`. Use `codex/phase3-tool-editor-playground`.
- Keep commits task-sized. Each task above ends with a commit boundary.
- Do not weaken permission behavior to make Playground easier. MCP real calls must require both the UI switch and the existing allowlist / PermissionBroker path.
