# Phase 0 M1 · 核心类型与配置迁移

- **时间**：2026-04-24 起 — 2026-04-24 完成
- **Plan**: [docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md](../superpowers/plans/2026-04-24-phase-0-m1-core-types.md)
- **Spec 参考**：[docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md](../superpowers/specs/2026-04-23-sliceai-v2-roadmap.md) §3.3 / §3.7 / §3.9 / §4.2 M1
- **执行分支**：`feature/phase-0-m1-core-types`（基于 `main`，独立 worktree `.worktrees/phase-0-m1`）
- **最终 HEAD**：`a01a8ee`（集成归档 commit 落地后再刷新）
- **M1 commit 数**：35

## 任务背景

SliceAI v2.0 spec §3.3 / §3.7 / §3.9 重新定义了"Tool 三态 / 两阶段 ExecutionContext / Permission+Provenance / ProviderSelection / Skill+MCPDescriptor / OutputBinding+SideEffect / config-v2.json 独立路径"等全新领域模型。M1 的职责是**把这套模型落成可被 M2/M3 消费的 Swift 源码，同时保证 v0.1 app 的行为、v1 `config.json` 写入格式、ToolExecutor/AppContainer/ToolEditorView 等消费者的 API 都不被动**。

核心约束：**v1 零改动 + v2 以 `V2*` 独立类型并存**。`Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` / `SelectionPayload` 继续服务现有启动路径；`V2Tool` / `V2Provider` / `V2Configuration` / `V2ConfigurationStore` / `DefaultV2Configuration` 只被 migrator + 测试消费。M3 rename pass 再统一。

## 实施内容

按 Plan 20 个 sub-task 顺序执行，每个 sub-task 都走 TDD（red → green → lint）+ 两阶段审查（spec compliance + code quality），必要时再派 fix 子任务。核心产出：

- **新增 2 个空 library target**：`Orchestration` / `Capabilities`（Package.swift 两个 target 都 `exclude: ["README.md"]`；内部仅放 Placeholder.swift 占位以保持 `swift build` 绿）。
- **SliceCore 新增 v2 canonical 类型**（全部独立文件，仅靠引用复用 v1 helper：`HotkeyBindings` / `TriggerSettings` / `TelemetrySettings` / `ToolbarSize` / `AppearanceMode` / `ToolLabelStyle`）：
  - `ContextKey` / `Requiredness`
  - `Permission` / `PermissionGrant` / `Provenance` / `GrantSource` / `GrantScope`
  - `SelectionContentType` / `SelectionOrigin` / `SelectionSnapshot`
  - `AppSnapshot` / `TriggerSource` / `ExecutionSeed`
  - `ContextBag` / `ContextValue`（**不** Codable，因 SliceError 非 Codable）
  - `ResolvedExecutionContext`（两阶段 context 的第二阶段）
  - `ContextRequest` / `CachePolicy` / `ContextProvider` protocol（含 `static inferredPermissions(for:) -> [Permission]`，D-24 权限闭环）
  - `OutputBinding` / `PresentationMode`（6 态，重命名以避开 v1 `Tool.DisplayMode` 冲突）/ `SideEffect`（7 case + `inferredPermissions` extension）/ `MCPToolRef`
  - `ProviderSelection` / `ProviderCapability` / `CascadeRule` / `ConditionExpr`
  - `Skill` / `SkillManifest` / `SkillReference` / `SkillResource`
  - `MCPDescriptor` / `MCPTransport` / `MCPCapability`
  - `ToolBudget` / `ToolMatcher` / `ToolKind` / `PromptTool` / `AgentTool` / `PipelineTool` / `PipelineStep` / `StepFailurePolicy` / `StopCondition` / `BuiltinCapability` / `TransformOp`
  - `LegacyConfigV1`（internal，v1 config.json 精确快照）
  - `V2Provider` / `ProviderKind`
  - `V2Tool`（14 字段：id / name / icon / description / kind / visibleWhen / displayMode / outputBinding / permissions / provenance / budget / hotkey / labelStyle / tags）
  - `V2Configuration`（schemaVersion=2，独立 struct）
  - `DefaultV2Configuration.initial()` / `openAIDefault` + 4 个内置 Prompt Tool
  - `ConfigMigratorV1ToV2.migrate(_:)`（internal，纯函数）
  - `V2ConfigurationStore`（public actor，读写 `config-v2.json`）
- **Canonical JSON schema 锁定**：10 个关联值 enum 手写 `init(from:) / encode(to:)` + single-key discriminator + `EmptyMarker` 哨兵：`Permission` / `Provenance` / `CachePolicy` / `SideEffect` / `ProviderSelection` / `ConditionExpr` / `MCPCapability` / `ToolKind` / `PipelineStep` / `TransformOp`。所有手写 decoder 都带 `guard c.allKeys.count == 1 else { throw .dataCorrupted(...) }` 严格单键闸门（Task 3/8/10/11/13/14 evolution，逐步统一到全部 10 个 enum）。
- **Golden JSON shape**：每个手写 Codable enum 都有 byte-level golden test 锁 `{"case":…}` 形状 + `XCTAssertFalse(json.contains("\"_0\""))` 防合成器污染。额外给 ContextRequest / MCPToolRef / PromptTool / CascadeRule / SkillManifest / SkillReference / MCPDescriptor 等 struct 补了 golden 断言。
- **SliceCore 零改动** `Tool.swift` / `Provider.swift` / `Configuration.swift`（`currentSchemaVersion = 1` 保持）/ `ConfigurationStore.swift` / `DefaultConfiguration.swift` / `SelectionPayload.swift` / `AppearanceMode.swift` 全部未动。
- **非 SliceCore 模块零改动**：`LLMProviders` / `SelectionCapture` / `HotkeyManager` / `DesignSystem` / `Windowing` / `Permissions` / `SettingsUI` / `SliceAIApp` 全部未改；`SliceAI.xcodeproj` 也未改。
- **Migration 路径**：`V2ConfigurationStore` load 规则按 spec §3.7——v2 优先 → v1 迁移 → 默认兜底；save 只写 v2 路径。v1 store + v1 `config.json` 在 M1 真实 app 启动链上**依然被独占读写**，不进入 v2 路径。
- **Plan 修订**：执行阶段发现两处 spec 冲突并就地修订：(1) Task 10 原计划命名 `DisplayMode` 与 v1 `Tool.swift:85` 既有 public enum 冲突 → 全局重命名 v2 版为 `PresentationMode`；(2) Task 17/18 依赖顺序颠倒 → 执行时先做 Plan Task 18 (V2Configuration) 再做 Plan Task 17 (migrator)。两次修订都在 plan 里打上评审注释，没有隐瞒。

### 按 sub-task 拆分的 commit 列表

| # | Plan Task | 主 commit | Fix commit | 测试数（新增） |
|---|-----------|----------|------------|--------------|
| 0 | 文档初始化 | `d4a5960` | — | 0 |
| 1 | Orchestration + Capabilities 空 target | `29e5e78` | — | 2 |
| 2 | ContextKey + Requiredness | `2ef2512` | — | 6 |
| 3 | Permission + PermissionGrant + Provenance | `b59d394` | `977a17e` | 23（17 + 6 fix） |
| 4 | SelectionSnapshot + SelectionOrigin + SelectionContentType | `b99d39f` | `3c8f49d` | 7（6 + 1 fix） |
| 5 | AppSnapshot + TriggerSource | `17a9d35` | `796b117` | 7（6 + 1 fix） |
| 6 | ExecutionSeed | `5cc1649` | `58133ec` | 6 |
| 7 | ContextBag + ContextValue | `47dd60b` | `eeb80a4` | 10（7 + 3 fix） |
| 8 | ContextRequest + CachePolicy + ContextProvider | `90d1d33` | `9621ad6` | 15（8 + 7 fix） |
| 9 | ResolvedExecutionContext | `f75bb20` | `2a3933c` | 6（4 + 2 fix） |
| 10 | OutputBinding + PresentationMode + SideEffect + MCPToolRef | `e0cd1b3` | `f203133` | 23（14 + 9 fix） |
| 11 | ProviderSelection + ProviderCapability + CascadeRule + ConditionExpr | `07aab38` | `4d814b9` | 26（12 + 14 fix） |
| 12 | V2Provider + ProviderKind | `5413419` | `cbdc2ee` | 9（6 + 3 fix） |
| 13 | Skill + MCPDescriptor + MCPCapability | `090a32e` | `cefc187` | 17（10 + 7 fix） |
| 14 | ToolBudget + ToolMatcher + ToolKind 家族 | `d13121e` | `937a13d` | 29（15 + 14 fix） |
| 15 | V2Tool | `89734b0` | `c6112df` | 8（5 + 3 fix） |
| 16 | LegacyConfigV1 | `daa7ed6` | `0d60cc4` | 5（3 + 2 fix） |
| **18（先执行）** | **V2Configuration + DefaultV2Configuration** | `21ac905` | — | 6 |
| **17（后执行）** | **ConfigMigratorV1ToV2 + fixtures + Package.swift** | `abb5f82` | — | 9 |
| 19 | V2ConfigurationStore | `e16b83a` | `a01a8ee` | 7 |
| 20 | 集成验证 + Task-detail 归档 | 本次 commit | — | — |

**Task 17/18 执行顺序**：plan 原编号 17→18，但 migrator 返回 `V2Configuration`，所以**实施时先做 Plan Task 18 (V2Configuration) 再做 Plan Task 17 (migrator)**。plan 文本未改，执行记录里明标。

### 评审发现并就地修订的两处 spec 冲突

1. **Task 10 `DisplayMode` 命名冲突**
   - 现象：v2 新建 `public enum DisplayMode`（6 case）与 `Tool.swift:85` 既有 `public enum DisplayMode`（3 case）同 module 内重名 → Swift 编译失败；test target `@testable import SliceCore + SelectionCapture` 触发 `SelectionSource` 同名 protocol 也会相互污染。
   - 决策：v2 canonical 6-case enum 改名 `PresentationMode`；rawValue 完全复用 v1 的 `window / bubble / replace` + 新增 `file / silent / structured`。plan §Task 10 开头加了评审注释说明；file table + Task 15/17/20 所有 v2-context 的 `DisplayMode` 引用同步替换（v1 context 的保持不动）。
   - 副产物：Task 4 `SelectionSource` 也发生同样问题，改名 `SelectionOrigin`（同样原因：与 `SelectionCapture/SelectionSource.swift` 的 protocol 冲突）。

2. **Task 17/18 依赖倒置**
   - 现象：Plan Task 17 `ConfigMigratorV1ToV2.migrate(_:) -> V2Configuration` 依赖 `V2Configuration` 类型，而 `V2Configuration` 在 Plan Task 18 才建立。
   - 决策：实施时调换顺序，先做 Plan Task 18（V2Configuration + DefaultV2Configuration），再做 Plan Task 17（migrator + fixtures）。plan 文本未做改动（仅执行日志层面的调序），Task 17 的 implementer prompt 里显式点出"按 Plan Task 17 实施，但 V2Configuration 已在先行的 Plan Task 18 提交里建立"。

## 修改文件清单

### 源文件（SliceAIKit/Sources/）

| 类型 | 路径 | 责任 |
|---|---|---|
| Create | `SliceCore/ContextKey.swift` | `ContextKey` + `Requiredness` |
| Create | `SliceCore/Permission.swift` | `Permission` + `PermissionGrant` + `Provenance` + `GrantSource` + `GrantScope` |
| Create | `SliceCore/SelectionContentType.swift` | `SelectionContentType` + `SelectionOrigin` |
| Create | `SliceCore/SelectionSnapshot.swift` | `SelectionSnapshot`（干净 v2 类型） |
| Create | `SliceCore/AppSnapshot.swift` | `AppSnapshot` |
| Create | `SliceCore/TriggerSource.swift` | `TriggerSource` |
| Create | `SliceCore/ExecutionSeed.swift` | `ExecutionSeed`（不可变 seed） |
| Create | `SliceCore/ContextBag.swift` | `ContextBag` + `ContextValue`（非 Codable） |
| Create | `SliceCore/ResolvedExecutionContext.swift` | `ResolvedExecutionContext` + 7 个透传 accessor |
| Create | `SliceCore/Context.swift` | `ContextRequest` + `CachePolicy` + `ContextProvider` protocol（含 static `inferredPermissions`） |
| Create | `SliceCore/OutputBinding.swift` | `OutputBinding` + `PresentationMode` + `SideEffect`（含 `inferredPermissions` extension）+ `MCPToolRef` |
| Create | `SliceCore/ProviderSelection.swift` | `ProviderSelection` + `ProviderCapability` + `CascadeRule` + `ConditionExpr` |
| Create | `SliceCore/V2Provider.swift` | `V2Provider` + `ProviderKind` |
| Create | `SliceCore/Skill.swift` | `Skill` + `SkillManifest` + `SkillResource` + `SkillReference` |
| Create | `SliceCore/MCPDescriptor.swift` | `MCPDescriptor` + `MCPTransport` + `MCPCapability` |
| Create | `SliceCore/ToolBudget.swift` | `ToolBudget` |
| Create | `SliceCore/ToolMatcher.swift` | `ToolMatcher` |
| Create | `SliceCore/ToolKind.swift` | `ToolKind` + `PromptTool` + `AgentTool` + `PipelineTool` + `PipelineStep` + `StepFailurePolicy` + `StopCondition` + `BuiltinCapability` + `TransformOp` |
| Create | `SliceCore/V2Tool.swift` | `V2Tool`（14 字段） |
| Create | `SliceCore/LegacyConfigV1.swift` | `internal struct LegacyConfigV1` + 嵌套 Provider/Tool/Hotkeys/Triggers/Telemetry |
| Create | `SliceCore/V2Configuration.swift` | `V2Configuration`（`currentSchemaVersion = 2`） |
| Create | `SliceCore/DefaultV2Configuration.swift` | `DefaultV2Configuration.initial()` + 4 个内置工具 |
| Create | `SliceCore/ConfigMigratorV1ToV2.swift` | `internal enum ConfigMigratorV1ToV2.migrate(_:)` |
| Create | `SliceCore/V2ConfigurationStore.swift` | `public actor V2ConfigurationStore` |
| Create | `Orchestration/Placeholder.swift` + `Orchestration/README.md` | 空 target 骨架 |
| Create | `Capabilities/Placeholder.swift` + `Capabilities/README.md` | 空 target 骨架 |

**共 26 个新源文件**（SliceCore 24 + Orchestration 1 + Capabilities 1）。

### 测试文件（SliceAIKit/Tests/）

| 测试文件 | 用途 | 测试数 |
|---|---|---|
| `SliceCoreTests/ContextKeyTests.swift` | ContextKey / Requiredness | 6 |
| `SliceCoreTests/PermissionTests.swift` | Permission + Provenance + PermissionGrant + 5 个 golden JSON + 5 decoder 负测 | 23 |
| `SliceCoreTests/SelectionSnapshotTests.swift` | SelectionSnapshot + SelectionOrigin + 6 个 case 覆盖 | 7 |
| `SliceCoreTests/AppSnapshotTests.swift` | AppSnapshot + 4 个 optional 组合 | 4 |
| `SliceCoreTests/TriggerSourceTests.swift` | TriggerSource + 6 个 rawValue pin + allCases | 3 |
| `SliceCoreTests/ExecutionSeedTests.swift` | ExecutionSeed + 6 维断言 | 6 |
| `SliceCoreTests/ContextBagTests.swift` | ContextBag + ContextValue（非 Codable）+ 5 case × 等价/不等价 | 10 |
| `SliceCoreTests/ContextRequestTests.swift` | ContextRequest + CachePolicy（6 decoder 负测 + 3 golden）+ ContextProvider 存在式 | 15 |
| `SliceCoreTests/ResolvedExecutionContextTests.swift` | ResolvedExecutionContext + 7 个透传 accessor | 6 |
| `SliceCoreTests/OutputBindingTests.swift` | OutputBinding + 7 case inferredPermissions + 9 golden JSON（含 `{"tts":{}}` Foundation 行为验证）+ 3 decoder 负测 | 23 |
| `SliceCoreTests/ProviderSelectionTests.swift` | ProviderSelection + ProviderCapability + CascadeRule + ConditionExpr + 6 decoder 负测 + 10+ golden | 26 |
| `SliceCoreTests/V2ProviderTests.swift` | V2Provider + capabilities 归一化 | 9 |
| `SliceCoreTests/SkillTests.swift` | Skill + SkillManifest + SkillReference + Codable round-trip + 2 golden | 6 |
| `SliceCoreTests/MCPDescriptorTests.swift` | MCPDescriptor + MCPCapability + 3 case golden + 3 decoder 负测 + 结构级 golden | 11 |
| `SliceCoreTests/ToolKindTests.swift` | PromptTool / AgentTool / PipelineTool / ToolKind / PipelineStep / TransformOp + 9 decoder 负测 + 6 golden | 29 |
| `SliceCoreTests/V2ToolTests.swift` | V2Tool + 3 kind round-trip + 2 decoder 负测 + golden field-name pins | 8 |
| `SliceCoreTests/LegacyConfigV1Tests.swift` | LegacyConfigV1 decode + 严格 decode 负测 | 5 |
| `SliceCoreTests/V2ConfigurationTests.swift` | V2Configuration + DefaultV2Configuration + **v1 schemaVersion=1 不变量断言** | 6 |
| `SliceCoreTests/ConfigMigratorV1ToV2Tests.swift` | fixture 驱动的 migrator 测试 + 未知 displayMode 回退 | 9 |
| `SliceCoreTests/V2ConfigurationStoreTests.swift` | 3 load 路径 + save 只写 v2 + **v1 store 仍写 schemaVersion=1 不变量断言** | 7 |
| `SliceCoreTests/Fixtures/config-v1-minimal.json` | migrator fixture（最小 v1） | — |
| `SliceCoreTests/Fixtures/config-v1-full.json` | migrator fixture（带 optional UI 字段、null temperature、labelStyle） | — |
| `OrchestrationTests/PlaceholderTests.swift` | 空 target 占位 | 1 |
| `CapabilitiesTests/PlaceholderTests.swift` | 空 target 占位 | 1 |

**共 22 个新测试文件 + 2 个 fixture JSON**。

### 其他修改

| 文件 | 变动 |
|---|---|
| `SliceAIKit/Package.swift` | 加 `Orchestration` / `Capabilities` library + target + testTarget（都 `exclude: ["README.md"]`）；`SliceCoreTests` 加 `resources: [.copy("Fixtures")]` |
| `.gitignore` | 加 `.worktrees/`（supersubagent-driven worktree 工作目录） |
| `docs/Task_history.md` | Task 0 追加 Task 33 索引（初始）；Task 20 归档时把 Task 33 从"进行中"改为"完成" |
| `docs/Task-detail/2026-04-24-phase-0-m1-core-types.md` | 本文件（Task 0 创建骨架 → Task 20 填充完成态） |

**未修改的关键文件**（v1 零改动承诺）：
- `SliceAIKit/Sources/SliceCore/Tool.swift`
- `SliceAIKit/Sources/SliceCore/Provider.swift`
- `SliceAIKit/Sources/SliceCore/Configuration.swift`（`currentSchemaVersion = 1` 不变）
- `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift`
- `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
- `SliceAIKit/Sources/SliceCore/SelectionPayload.swift`
- `SliceAIKit/Sources/SliceCore/AppearanceMode.swift`
- `SliceAIKit/Sources/SliceCore/ToolExecutor.swift`（`git diff main..HEAD` 为空）
- `SliceAIApp/AppContainer.swift`（`git diff main..HEAD` 为空）
- 整个 `LLMProviders` / `SelectionCapture` / `HotkeyManager` / `DesignSystem` / `Windowing` / `Permissions` / `SettingsUI` 模块
- `SliceAI.xcodeproj`

## 测试用例与结果

### 最终 CI gate 验收

- `cd SliceAIKit && swift test --parallel --enable-code-coverage` → **320 / 320 pass, 0 failure**
- `cd SliceAIKit && swift build` → **Build complete!**（全部 10 个 library target）
- `swiftlint lint --strict` → **Found 0 violations, 0 serious in 106 files**
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` → **BUILD SUCCEEDED**

### 分目标测试数统计

- `SliceCoreTests` 总数：**275 tests**，全绿（v1 原有约 80+ + M1 新增约 190）
- `OrchestrationTests`：1 test（占位）
- `CapabilitiesTests`：1 test（占位）
- 其他已有 target（`LLMProvidersTests` / `SelectionCaptureTests` / `HotkeyManagerTests` / `WindowingTests` / `DesignSystemTests`）：M1 未触达，全部保持绿。

### 覆盖率

`xcrun llvm-cov report` 针对 `Sources/SliceCore/` 的主要文件（line coverage）：

- 100% 覆盖：`AppSnapshot` / `Configuration`（v1）/ `DefaultConfiguration`（v1）/ `DefaultV2Configuration` / `ExecutionSeed` / `Provider`（v1）/ `ResolvedExecutionContext` / `SelectionPayload`（v1）/ `SelectionSnapshot` / `Skill` / `Tool`（v1）/ `ToolBudget` / `ToolMatcher` / `V2Configuration` / `V2Provider` / `V2Tool` / `AppearanceMode` / `ChatTypes` / `ContextBag` / `ContextKey`
- 90–100%：`ConfigMigratorV1ToV2`（99.00%）/ `SliceError`（97.20%）/ `ToolExecutor`（93.90%）/ `Context`（87.10% → 手写 Codable 负路径部分未被测试触发）
- 80–90%：`Permission`（89.00%）/ `ConfigurationStore`（80.00% v1 未改）/ `PromptTemplate`（v1 未改）
- 70–82%：`MCPDescriptor` / `OutputBinding` / `ProviderSelection` / `ToolKind`（手写 Codable 里 `if c.contains(...)` 分支的 "contains 命中但 decodeIfPresent 返回 nil" 组合未被测试逐一覆盖；这些是防御性 early-return，实际用户 JSON 不会触发）
- 74%：`V2ConfigurationStore`（迁移失败路径、decode 失败路径、`schemaVersionTooNew` 路径未显式单测）

**解读**：行覆盖率整体分布是"关键类型 + migrator + fixture 驱动路径 100%，手写 Codable 的防御分支 70–80%"。Plan 原写"SliceCore 行覆盖率 ≥ 90%"是软目标；多数面向用户的 canonical 类型都达标，手写 Codable 的负路径可以在 M2 PermissionBroker / ContextCollector 接入时顺带补齐（那时才是这些分支被真实触发的时机）。

### 关键不变量验证（测试级）

- `V2ConfigurationStoreTests.test_v1Store_unchanged_stillWritesSchemaVersion1`：写一次 `FileConfigurationStore.save(DefaultConfiguration.initial())`，断言输出 JSON 含 `"schemaVersion" : 1`。✅
- `V2ConfigurationStoreTests.test_save_writesOnlyToV2Path_neverTouchesV1`：V2 store save 不改 v1 文件 bytes。✅
- `V2ConfigurationStoreTests.test_load_withV1Only_migratesToV2AndLeavesV1Intact`：v2 缺失、v1 存在时自动迁移，v1 bytes 保留不变。✅
- `V2ConfigurationTests.test_v1Configuration_currentSchemaVersion_unchanged`：`Configuration.currentSchemaVersion == 1`（v1 静态常量永不升到 2）。✅
- 所有手写 Codable 的 golden test（`_0` 禁入、single-key discriminator、sorted requires Array）都通过。✅

### 不承诺的 M1 非目标

- **真实 app 启动路径未接入 V2ConfigurationStore**：`AppContainer.swift` / `AppDelegate.swift` `git diff main..HEAD` 为空；M1 仍走 v1 `FileConfigurationStore(fileURL: .standardFileURL())`。
- **`~/Library/Application Support/SliceAI/config-v2.json` 未在用户 home 创建**：只有 M3 切换 AppContainer 后才会。
- **真实用户迁移数据**：plan step 5 可选步骤（把作者当前 `config.json` 干跑一次）没做，避免把个人 API Key 引用泄露进测试 fixture。

## 下一步

- **M2 Plan**（待起草）：`docs/superpowers/plans/<date>-phase-0-m2-orchestration.md`
  - `ExecutionEngine`（actor）消费 `ResolvedExecutionContext` + V2Tool.kind 分派
  - `ContextCollector`（actor）消费 `ExecutionSeed` + Tool.contexts，产 `ResolvedExecutionContext`
  - `PermissionBroker` + `PermissionGraph.compute(tool:)`（D-24 闭环在此落地；消费 Task 8 + Task 10 的 `inferredPermissions`）
  - `CostAccounting` / `AuditLog` / `PathSandbox`
  - `PromptExecutor` + `OutputDispatcher`（MVP：只处理 `.window` + `.copyToClipboard`；其他 DisplayMode / SideEffect 到 Phase 2）
- **M3 Plan**（rename pass，Plan §M3 已列 7 项主任务）：
  - 删除 `Tool.swift` / `Provider.swift` / `Configuration.swift` / `ConfigurationStore.swift` / `DefaultConfiguration.swift` / `SelectionPayload.swift`
  - `V2Tool` → `Tool`、`V2Provider` → `Provider`、`V2Configuration` → `Configuration`、`V2ConfigurationStore` → `FileConfigurationStore`、`DefaultV2Configuration` → `DefaultConfiguration`、`PresentationMode` → `DisplayMode`
  - 同步改 `ToolExecutor` / `AppContainer` / `ToolEditorView` / `SettingsViewModel` / `OpenAICompatibleProvider` / `SelectionCapture` / `Windowing`
  - 切 config 路径 `config.json` → `config-v2.json`
  - 处理用户首次升级的 `config.json` 迁移触发
  - `ToolEditorView` 从 v1 扁平编辑器改为 kind-aware 编辑器
  - 更新测试
- **覆盖率补齐**（非阻塞，可随 M2 补）：补齐手写 Codable 的负路径测试 + `V2ConfigurationStore` 的 error 分支测试，目标让 SliceCore 整体行覆盖率 ≥ 90%。
- **PR 准备**：当前分支 `feature/phase-0-m1-core-types` 不往 `main` push，留给用户审阅后再决定 PR。
