# Phase 0 M3 · 切换 + 删旧 + 端到端回归 Mini-Spec

> **本文档定位**：M3 启动前的设计冻结文档，按 M1 plan 顶部 §A 的硬约束（plan:24）+ master todolist §3.3 的 entry criteria 撰写。**Codex review 通过后**才允许进入 `superpowers:writing-plans` 出实施 plan。

- **状态**：Draft（初稿，待用户初审 + Codex review loop）
- **作者**：Claude（基于 v2 spec §4.2.3 / §4.2.5 + M1 plan 顶部 §A/§B/§C + M2 Task-detail §7.6）
- **日期**：2026-04-28
- **承接**：Phase 0 M1 PR #1（commit `5cdf0f7`） + M2 PR #2（commit `3a5437d`），main 已 clean
- **输出 PR**：`feature/phase-0-m3-switch-to-v2`
- **预估人天**：M3.0 rename pass 3–5 + M3.1–M3.6 切换链路 4.5 = **8.5–10.5 人天**（注：master todolist:267 写"M3: 3–5 人天"是 spec §4.2.3 原始估算，未包含 M3.0 rename pass；M1 plan:24 已明文修正"M3 单独约 3–5 人天 ⋯ 但落地后重点完全不同"，本 mini-spec 按"M3.0 + M3.1–6 合并"重新校准）

---

## 0. 评审与修订（每轮 Codex review verdict 在此追加）

> 起始版本：本 mini-spec 撰写时 main HEAD `3a5437d`（M2 PR #2 merge commit），worktree `feature/phase-0-m3-switch-to-v2` baseline 等同。

| 轮次 | 日期 | Verdict | 处理 |
|---|---|---|---|
| Initial | 2026-04-28 | Draft | 起草初稿 610 行（待用户初审） |
| User R1 | 2026-04-28 | Accept | 用户初审：三个 Open Questions 全部接受 Claude 推荐——Q1=A（M3 PR merge 后立即发 v0.2 tag + DMG）/ Q2=A（Codex review 不设硬上限，每 5 轮回 sync 进度）/ Q3=A（M3.0 Step 1 保持单 commit 不拆）。本轮无范围 / 架构修订；§0 / §6 / §11.2 / D-26 / D-31 同步更新决议状态后进 Codex review loop |

---

## 1. 任务背景

### 1.1 当前状态

- **M1（PR #1，merge `5cdf0f7`）**：SliceCore 中以独立 V2* 命名（`V2Tool` / `V2Provider` / `V2Configuration` / `V2ConfigurationStore` / `DefaultV2Configuration`）落地了 v2 数据模型 + ConfigMigratorV1ToV2，v1 类型族（`Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `DefaultConfiguration` / `SelectionPayload` / `ToolExecutor` / SelectionCapture 中 `protocol SelectionSource`）保持原封不动。M1 落地时为避命名冲突，引入两个临时改名：
  - `DisplayMode`（v2 六态枚举）→ `PresentationMode`
  - `SelectionSource`（v2 枚举）→ `SelectionOrigin`
- **M2（PR #2，merge `3a5437d`）**：Orchestration / Capabilities 两个 SwiftPM target 落地为可独立单测的执行引擎骨架（`ExecutionEngine` actor + 9 个上游依赖 + PathSandbox + MCP/Skill 接口），**不接入 app 启动链路**。`SliceCore/ToolExecutor.swift` 自 baseline 起 0 行 diff（§C-7 复制非替换）。
- **App 当前行为**：仍是 v0.1 + M1 现状——`AppContainer` 装配的是 v1 `FileConfigurationStore` + `ToolExecutor`，触发链 `mouseUp / ⌥Space → SelectionService.capture() → SelectionPayload → AppDelegate.execute(tool:payload:) → ToolExecutor.execute(...)`。V2 类型族与 Orchestration 引擎对真实启动路径**完全无影响**。

### 1.2 M3 的目标

把 V2 类型族 + Orchestration / Capabilities 真正接入 app 启动链路：
1. 删除全部 v1 冲突类型（`Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `DefaultConfiguration` / `SelectionPayload` / `ToolExecutor` / `protocol SelectionSource`）。
2. 把 `V2Tool` → `Tool` 等 V2* 命名 rename 回 spec 原始意图；恢复 `PresentationMode → DisplayMode` / `SelectionOrigin → SelectionSource`。
3. `AppContainer` 装配 `ExecutionEngine` + 9 个依赖；触发链切到 `ExecutionEngine.execute(tool:seed:)`。
4. 配置文件路径切到 `~/Library/Application Support/SliceAI/config-v2.json`；首启 migrator 自动从 `config.json` 迁移；**v1 `config.json` 永不被修改**。
5. 4 个内置工具（翻译 / 润色 / 总结 / 解释）在实机行为与 v0.1 等价；`spec §4.2.5` 8 项手工回归全过。
6. 发布 v0.2 tag（archival milestone，无用户可见新功能；底层重构完成）。

### 1.3 为什么需要一个 mini-spec

M1 plan:24 + master todolist:207 都明文要求："spec §4.2 M3 的任务清单需要在 M3 启动前独立 spec 一次"。原因：

- **M3 风险比 M1/M2 高一个数量级**：M1 / M2 都受 §C-1 zero-touch 约束（v1 8 模块 + SliceAIApp 0 行 diff），错了也只影响新 target；M3 必须 **改 SliceAIApp + 删 v1 + rename V2***，错了就是 app 启动崩溃 / 用户配置丢失 / 4 个内置工具行为漂移。
- **spec §4.2.3 M3 任务清单只列了 6 项粗粒度任务（M3.1–M3.6），没展开 M3.0 rename pass**——M1 plan 落地时引入的"V2* 独立类型 + 实施期改名"两个决策让 M3 的工作量重心从"删 ToolExecutor + 切 AppContainer"转移到"rename 整个类型族 + 修 SettingsUI 数据 binding + 处理首启 migration"，必须独立 spec 一次。
- **跨 8 个模块的改动需要明确顺序**：v1 删除顺序错了会引入命名冲突 / 编译循环依赖；rename 顺序错了会让 V2* 名字临时被双方占用。Mini-spec 必须把"小步序列"写死，否则 implementer 容易踩坑。

---

## 2. 范围（In-scope / Out-of-scope）

### 2.1 In-scope（M3 必做）

- [x] M3.0 — v1 文件删除 + V2* 类型 rename 回 spec 原意（含 `PresentationMode → DisplayMode` / `SelectionOrigin → SelectionSource`）
- [x] M3.1 — `AppContainer` 装配 `ExecutionEngine` + 9 个依赖
- [x] M3.2 — 触发通路（`mouseUp` / `⌥Space`）从 `ToolExecutor.execute` 切到 `ExecutionEngine.execute(tool:seed:)`
- [x] M3.3 — `ConfigurationStore`（rename 后）启动按 §3.7 规则选 v1/v2 路径 + 跑 migrator
- [x] M3.4 — 删除 `SliceCore/ToolExecutor.swift`
- [x] M3.5 — §4.2.5 端到端手工回归 8 项全过（分工：单测部分由 Claude / 真机操作部分由用户）
- [x] M3.6 — 文档归档（`README.md` / `docs/Module/*.md` / Task-detail）+ 发 v0.2 release tag + 打 unsigned DMG

### 2.2 Out-of-scope（M3 明确不做）

- ❌ **不加任何用户可见新功能**（spec §4.2.4 DoD 硬约束）。Settings UI 行为零变化，仅改数据 binding。
- ❌ **不暴露 ToolKind 三态编辑器**：v0.2 ToolEditorView 仅暴露 `.prompt` kind 编辑（与 v1 视觉等价）；`.agent` / `.pipeline` 编辑器留 Phase 2。
- ❌ **不暴露 ProviderSelection 全形态**：v0.2 仅暴露 `.fixed(providerId:modelId:)`（与 v1 picker 视觉等价）；`.capability` / `.cascade` 留 Phase 1。
- ❌ **不暴露 OutputBinding / DisplayMode 选择器**：v0.2 默认 `.window`；其他 mode 留 Phase 2。
- ❌ **不接入真实 MCPClient / SkillRegistry**：M2 已建 `MCPClientProtocol` / `SkillRegistryProtocol` + `MockMCPClient` / `MockSkillRegistry`，M3 装配时仍用 Mock；真实实现留 Phase 1 / Phase 2。
- ❌ **不接入真实 PermissionBroker UX**：M2 已建 `PermissionBroker` + `GateOutcome` 4-state，但当前 production 走 default-allow + provenance hint；真实弹窗 UX 留 Phase 1。
- ❌ **不做 v1 → v2 双写 / 降级**：v2 app 只写 `config-v2.json`，永不写 `config.json`（spec §3.7 明文）。

### 2.3 与其他 Phase 的边界

| 边界条件 | M3 处理 | 推到 Phase 1+ |
|---|---|---|
| `MCPClientProtocol` 真实接入 | Mock 装配 | Phase 1 真实 stdio/SSE client |
| `SkillRegistryProtocol` 真实接入 | Mock 装配 | Phase 2 真实 SkillRegistry + scanning |
| `PermissionBroker` 真实弹窗 | default-allow + audit log 写到 jsonl | Phase 1 真实 UX |
| `OutputDispatcher` 非 `.window` 分支 | 仅 `.window` 走真实 sink；其他 throw `.kindNotImplemented(...)` | Phase 2 BubblePanel / InlineReplaceOverlay / StructuredResultView |
| `ContextProvider` 真实 provider 实现 | M2 已注册"selection from seed"内置 provider；其他都是空实现 | Phase 1 5 个核心 provider（`app.windowTitle` / `app.url` / `clipboard.current` / `file.read`） |

---

## 3. 架构变更总览

### 3.1 rename / 删除 / 新建 文件清单

> **命名约定**：表格列出所有文件层操作。"Rename" 用 `git mv` 让 git 能 follow rename history（避免 git 把它识别为 delete + add）。"Modify" 列只列 import / 类型引用 / 数据 binding 的改动，不列纯 whitespace。

#### 3.1.1 SliceCore 层（M3.0）

| 操作 | 路径 | 说明 |
|---|---|---|
| Delete | `SliceAIKit/Sources/SliceCore/Tool.swift` | v1 Tool 整体删除（含 v1 `public enum DisplayMode`） |
| Delete | `SliceAIKit/Sources/SliceCore/Provider.swift` | v1 Provider 整体删除 |
| Delete | `SliceAIKit/Sources/SliceCore/Configuration.swift` | v1 Configuration 整体删除 |
| Delete | `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift` | v1 `ConfigurationProviding` protocol + `FileConfigurationStore` actor 整体删除 |
| Delete | `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift` | v1 default 4 个内置工具整体删除 |
| Delete | `SliceAIKit/Sources/SliceCore/SelectionPayload.swift` | v1 SelectionPayload 整体删除 |
| Delete | `SliceAIKit/Sources/SliceCore/ToolExecutor.swift` | v1 ToolExecutor 整体删除（M3.4） |
| Rename | `SliceAIKit/Sources/SliceCore/V2Tool.swift` → `Tool.swift` | git mv + 类型名 `V2Tool` → `Tool` + `PromptTool` 等子类型不变 |
| Rename | `SliceAIKit/Sources/SliceCore/V2Provider.swift` → `Provider.swift` | git mv + 类型名 `V2Provider` → `Provider` + `ProviderKind` / `ProviderCapability` 不变 |
| Rename | `SliceAIKit/Sources/SliceCore/V2Configuration.swift` → `Configuration.swift` | git mv + 类型名 `V2Configuration` → `Configuration` |
| Rename | `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift` → `ConfigurationStore.swift` | git mv + 类型名 `V2ConfigurationStore` → `ConfigurationStore` + `ConfigurationStoring` protocol（若有）保留 |
| Rename | `SliceAIKit/Sources/SliceCore/DefaultV2Configuration.swift` → `DefaultConfiguration.swift` | git mv + 类型名 `DefaultV2Configuration` → `DefaultConfiguration` |
| Modify | `SliceAIKit/Sources/SliceCore/OutputBinding.swift` | `PresentationMode` → `DisplayMode`（类型 + 文件内全部引用） |
| Modify | `SliceAIKit/Sources/SliceCore/ToolKind.swift` | `PresentationMode` → `DisplayMode`（V2Tool / PromptTool / AgentTool / PipelineTool 的 displayMode 字段） |
| Modify | `SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift` | `SelectionOrigin` → `SelectionSource`（含 enum 定义 + 字段类型） |
| Keep | `SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift` | 内部仍引用 `LegacyConfigV1` struct（不变）；引用 `Tool` / `Provider` / `Configuration` 时跟随 rename |

#### 3.1.2 SelectionCapture 层（M3.0）

| 操作 | 路径 | 说明 |
|---|---|---|
| Delete | `SliceAIKit/Sources/SelectionCapture/SelectionSource.swift`（v1 protocol 部分） | v1 `public protocol SelectionSource` 整体删除 |
| Modify | `SliceAIKit/Sources/SelectionCapture/SelectionService.swift` | `capture()` 返回类型 `SelectionPayload?` → `SelectionSnapshot?`；内部组合两个 source 的逻辑保持不变 |
| Modify | `SliceAIKit/Sources/SelectionCapture/ClipboardSelectionSource.swift` | 改 protocol 实现签名（产出 `SelectionReadResult` → `SelectionSnapshot` 的 helper 也跟着改） |
| Modify | `SliceAIKit/Sources/SelectionCapture/PrimarySelectionSource.swift` | 同上 |
| Create | `SliceAIKit/Sources/SelectionCapture/SelectionReader.swift`（拟名） | 重新定义 v2 `protocol SelectionReader` 替代 v1 `SelectionSource` protocol（spec §3.3 已把 enum `SelectionSource` 升级为类型 case，v1 protocol 名应改避免与 enum 同名）。**详见 D-28** |

> **注意命名冲突**：spec §3.3.x 设计的 `SelectionSource` 是 enum case 类型（`.accessibility` / `.clipboardFallback` / `.inputBox`），不是 protocol。v1 中的 `protocol SelectionSource` 是"两个 source 实现一个抽象"用的——M3.0 删掉它后必须重新命名 protocol 避免与 enum 同名。**预选名 `SelectionReader`**（理由：行为是"读"选区，不是"成为选区源"）。

#### 3.1.3 SliceAIApp 层（M3.1 / M3.2 / M3.3）

| 操作 | 路径 | 说明 |
|---|---|---|
| Modify | `SliceAIApp/AppContainer.swift` | 装配 `ExecutionEngine` + 9 个依赖（详见 D-27）；`ConfigurationStore`（v2）替代 `FileConfigurationStore`；删除 `ToolExecutor` 装配 |
| Modify | `SliceAIApp/AppDelegate.swift` | `execute(tool:payload:)` → `execute(tool:seed:)`；构造 `ExecutionSeed` 替代 `SelectionPayload`；消费 `AsyncStream<ExecutionEvent>` 替代原 `AsyncThrowingStream<String, Error>` |
| Keep | `SliceAIApp/MenuBarController.swift` | 仅引用 `Configuration` 类型时跟随 rename，无逻辑改动 |
| Keep | `SliceAIApp/SliceAIApp.swift` | `@main` 入口，无改动 |

#### 3.1.4 SettingsUI 层（M3.0 数据 binding）

| 操作 | 路径 | 说明 |
|---|---|---|
| Modify | `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift` | binding 从 `Tool.systemPrompt / .userPrompt / .providerId / .modelId / .temperature / .variables` 改为 `Tool.kind.prompt.systemPrompt / .userPrompt / .provider.fixed.providerId / .provider.fixed.modelId / .temperature` 等。**详见 D-29** |
| Modify | `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift` | 新增 `kind: ProviderKind` 字段（默认 `.openAICompatible`）+ `capabilities: [ProviderCapability]`（默认 `[]`）；其他字段保持视觉等价 |
| Modify | `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift` | `ConfigurationProviding` protocol 引用切到 v2 `ConfigurationStore`；`addTool` / `addProvider` / `setAPIKey` 等方法适配 v2 struct |
| Modify | `SliceAIKit/Sources/SettingsUI/SettingsScene.swift` | 同上，跟随 ViewModel 切换 |
| Keep | 其他 SettingsUI 页面（HotkeySettingsPage / TriggerSettingsPage / etc.） | 仅引用 `Configuration` 类型时跟随 rename，无逻辑改动 |

#### 3.1.5 LLMProviders 层（M3.0）

| 操作 | 路径 | 说明 |
|---|---|---|
| Modify | `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift` | 接收 `Provider`（v2，含 `kind: ProviderKind` / `capabilities`）替代 v1 `Provider`；逻辑只用 `baseURL` / `apiKeyRef` / `defaultModel`，所以不变；构造器签名跟随 rename |

#### 3.1.6 Windowing 层（M3.0 + M3.2）

| 操作 | 路径 | 说明 |
|---|---|---|
| Modify | `SliceAIKit/Sources/Windowing/ResultPanel.swift` | `append(_:)` / `finish()` / `fail(...)` callback 由 AppDelegate 适配层调用，**ResultPanel 内部 API 不动**——AppDelegate 把 `ExecutionEvent` 翻译为 ResultPanel 的现有方法调用。**详见 D-30** |
| Modify | `SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift` | 仅 `Tool` 类型引用跟随 rename，无逻辑改动 |
| Modify | `SliceAIKit/Sources/Windowing/CommandPalettePanel.swift` | 同上 |

#### 3.1.7 Tests 层（M3.0）

| 操作 | 路径 | 说明 |
|---|---|---|
| Delete | `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift`（v1） | 与 V2ToolTests rename 后撞名，先删 v1 |
| Delete | `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`（v1，若存在） | 同上 |
| Delete | `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift`（若存在） | 跟随 SelectionPayload 删除 |
| Delete | `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift`（若存在） | 跟随 ToolExecutor 删除 |
| Rename | `SliceAIKit/Tests/SliceCoreTests/V2ToolTests.swift` → `ToolTests.swift` | git mv + class 名 `V2ToolTests` → `ToolTests` + 测试方法名内的 `V2Tool` 替换 |
| Rename | `SliceAIKit/Tests/SliceCoreTests/V2ProviderTests.swift` → `ProviderTests.swift` | 同上 |
| Rename | `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationTests.swift` → `ConfigurationTests.swift` | 同上 |
| Rename | `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift` → `ConfigurationStoreTests.swift` | 同上 |
| Modify | `SliceAIKit/Tests/SliceCoreTests/ConfigMigratorV1ToV2Tests.swift` | 引用 `V2*` → 正名（migrator 类型名本身不动） |
| Modify | `SliceAIKit/Tests/SliceCoreTests/SelectionSnapshotTests.swift` | `SelectionOrigin` → `SelectionSource` |
| Modify | `SliceAIKit/Tests/SliceCoreTests/OutputBindingTests.swift` | `PresentationMode` → `DisplayMode` |
| Modify | `SliceAIKit/Tests/SliceCoreTests/SliceErrorTests.swift` | 跟随类型 rename |
| Modify | OrchestrationTests / CapabilitiesTests / SelectionCaptureTests / SettingsUITests / WindowingTests / LLMProvidersTests | 全部跟随 V2* → 正名 + PresentationMode → DisplayMode + SelectionOrigin → SelectionSource |

### 3.2 触发链改造（M3.2）

```
v0.1 + M2 当前：
  mouseUp / ⌥Space
    → SelectionService.capture() : SelectionPayload?
    → AppDelegate.execute(tool: SliceCore.Tool, payload: SelectionPayload)
    → toolExecutor.execute(tool:payload:) → AsyncThrowingStream<String, Error>
    → ResultPanel.append(_:) / .finish() / .fail(error:onRetry:onOpenSettings:)

M3 后：
  mouseUp / ⌥Space
    → SelectionService.capture() : SelectionSnapshot?
    → AppDelegate.execute(tool: Tool, snapshot: SelectionSnapshot)
        → 构造 ExecutionSeed(invocationId:, selection: snapshot, app:, hotkeyTrigger:, ts:)
        → executionEngine.execute(tool: Tool, seed: ExecutionSeed) → AsyncStream<ExecutionEvent>
        → for await event in stream: 翻译为 ResultPanel API 调用
            .started(_) → ResultPanel.open(...)（已在 stream 启动前调用，用 .started 仅记日志）
            .streamChunk(_, delta) → ResultPanel.append(delta)
            .completed(report) → ResultPanel.finish()
            .failed(report, error) → ResultPanel.fail(error, onRetry:, onOpenSettings:)
            .permissionDenied(_) → ResultPanel.fail(.permission(.userDenied), onRetry:, ...)
            .invocationCompleted(report) → CostAccounting / AuditLog 已在 ExecutionEngine 内写完
```

### 3.3 配置启动（M3.3）

```
启动流程（AppContainer 内）：
  1. 创建 ConfigurationStore(v2)（path = ~/Library/Application Support/SliceAI/config-v2.json）
  2. await configStore.current() → throws：
     - 成功 → 注入 AppContainer，继续启动
     - 抛 .schemaTooNew / .corruptedV2 / .corruptedLegacy → 弹 alert + NSApp.terminate(nil)
       理由（M1 plan §B 第七轮 P1 指明）：M3 接入时**绝不能**静默回退到 default，否则下一次 update() 永久覆盖用户文件 = 数据丢失
  3. ConfigurationStore.current() 内部已含首启 migration 逻辑（M1 已落地）：
     - 若 config-v2.json 存在 → 读
     - 若 config-v2.json 不存在但 config.json 存在 → 跑 migrator 写 config-v2.json（不改 config.json）
     - 都不存在 → 写 DefaultConfiguration.initial() 到 config-v2.json
```

---

## 4. 任务拆解

> 本节给出**任务级粒度**（不是 sub-task，sub-task 在 plan 阶段细化）。每个 M3.x 任务的 entry/exit/交付物按 spec §4.2.3 + master todolist §3.3 锚定。

### M3.0 — v1 删除 + V2 rename pass（一等主任务，3–5 人天）

**目标**：所有 v1 类型族删除；V2* 类型 rename 回 spec 原名；`PresentationMode → DisplayMode` / `SelectionOrigin → SelectionSource` 恢复；CI gate 全绿。

**Entry**：worktree 干净，baseline = main HEAD `3a5437d`。

**5 步小 commit 序列（D-26）**：

| Step | Commit | 内容 | 验证 |
|---|---|---|---|
| Step 1 | `refactor(slicecore): switch all v1 callers to V2*` | 把 SettingsUI / AppContainer / AppDelegate / Windowing / LLMProviders / SelectionCapture / 全部 Tests 中所有 v1 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `DefaultConfiguration` / `SelectionPayload` / `ToolExecutor` 类型引用切到 V2*；同步更新 SettingsUI 的数据 binding 适配 V2Tool / V2Provider 结构（D-29）；更新 SelectionService.capture() 返回 SelectionSnapshot（D-28） | swift build 通过；swift test 全绿；xcodebuild 通过；swiftlint --strict 0 violations |
| Step 2 | `refactor(slicecore): delete v1 Tool/Provider/Configuration/FileConfigurationStore/DefaultConfiguration/SelectionPayload + v1 protocol SelectionSource` | 删除 v1 SliceCore 6 个文件 + v1 SelectionCapture protocol；新建 `SelectionReader` protocol 替代 v1 `SelectionSource` protocol；删除对应 v1 Tests 文件（ToolTests / ConfigurationTests / SelectionPayloadTests 等若存在） | 同上四关 |
| Step 3 | `refactor(slicecore): rename V2* types and files to canonical names` | git mv 5 个 V2* 文件到正名（`Tool.swift` / `Provider.swift` / `Configuration.swift` / `ConfigurationStore.swift` / `DefaultConfiguration.swift`）；类型名 `V2Tool` → `Tool` 等同步全局替换；测试 V2*Tests rename 为 *Tests | 同上四关 |
| Step 4 | `refactor(slicecore): rename PresentationMode to DisplayMode` | `PresentationMode` → `DisplayMode`（OutputBinding.swift / ToolKind.swift / 全部测试 / 全部引用）；v1 `DisplayMode` 已在 Step 2 删除，命名空间已腾出 | 同上四关 |
| Step 5 | `refactor(selectioncapture): rename SelectionOrigin to SelectionSource` | `SelectionOrigin` → `SelectionSource`（SelectionSnapshot.swift / 全部测试 / 全部引用）；v1 `protocol SelectionSource` 已在 Step 2 删除并改名 SelectionReader，命名空间已腾出 | 同上四关 |

**Exit (DoD)**：
- [ ] `swift build` / `swift test --parallel --enable-code-coverage` / `swiftlint lint --strict` / `xcodebuild ... SliceAI` 全绿
- [ ] `grep -rn "V2Tool\|V2Provider\|V2Configuration\|V2ConfigurationStore\|DefaultV2Configuration\|PresentationMode\|SelectionOrigin" SliceAIKit/ SliceAIApp/` **0 匹配**
- [ ] `git mv` 让 git follow rename 工作（用 `git log --follow Tool.swift` 能跟踪到 commit `cd34835` 之前的 V2Tool.swift 历史）

**注意事项**：
- Step 1 是最大的 commit（要改 30+ 文件），但**不删任何东西**，纯 caller 切换；这一步如果跑通就锁住了"v1 已无 production 引用"
- Step 2 删 v1 后，原 v1 测试也要删，否则编译失败
- Step 3 是双重 rename（文件名 + 类型名），git 会识别 `git mv` 触发的 rename；类型名替换用 `sed -i '' 's/\bV2Tool\b/Tool/g'` 但要小心 `V2ToolTests` 这类合成名（用 `\b` boundary）
- Step 4 / Step 5 是单字段重命名，相对安全
- **5 步必须严格按顺序**——颠倒会引入命名冲突或编译循环

### M3.1 — AppContainer 装配 ExecutionEngine + 9 个依赖（1 人天）

**目标**：`AppContainer` 装配执行引擎闭环；启动冒烟测试通过（app 启动后能调出 Settings / 命令面板，但暂不真正触发执行——M3.2 才切触发链）。

**Entry**：M3.0 完成；ExecutionEngine 已在 Orchestration target 可用。

**装配方案（D-27）**：

| 依赖 | 类型 | 装配 | 备注 |
|---|---|---|---|
| `permissionGraph` | `PermissionGraph` actor | `PermissionGraph()` 实例化 | M2 已实现，无 mock |
| `permissionBroker` | `any PermissionBrokerProtocol` | `DefaultPermissionBroker(grantStore: InMemoryGrantStore())` | v0.2 默认全放行 + audit log；真实弹窗留 Phase 1 |
| `contextCollector` | `ContextCollector` actor | `ContextCollector(registry: ContextProviderRegistry.builtin())` | M2 已实现，registry 默认仅 selection provider |
| `providerResolver` | `any ProviderResolverProtocol` | `DefaultProviderResolver(configStore: configStore)` | M2 已实现 |
| `promptExecutor` | `PromptExecutor` actor | `PromptExecutor(providerFactory: { ... new OpenAICompatibleProvider($0, key: ...) })` | factory 闭包从 keychain 读 key + 构造 LLMProvider |
| `outputDispatcher` | `OutputDispatcher` actor | `OutputDispatcher(windowSink: ResultPanelWindowSinkAdapter(panel: container.resultPanel))` | adapter 把 `WindowSink.write(_:)` 翻译为 ResultPanel 调用（详见 D-30） |
| `costAccounting` | `CostAccounting` actor | `CostAccounting(dbPath: appSupport.appendingPathComponent("cost.sqlite"))` | M2 已实现 |
| `auditLog` | `any AuditLogProtocol` | `JSONLAuditLog(path: appSupport.appendingPathComponent("audit.jsonl"))` | M2 已实现 |
| `executionEngine` | `ExecutionEngine` actor | 注入上述 8 个依赖 + `clock: ContinuousClock()` | M2 已实现 |

**Exit (DoD)**：
- [ ] `AppContainer.swift` 编译通过；`xcodebuild ... SliceAI` 启动 app 不崩（手工启动验证）
- [ ] `cost.sqlite` / `audit.jsonl` 在 `~/Library/Application Support/SliceAI/` 自动创建（首次启动后）
- [ ] `swift test --filter SliceAIKit` 全绿（不跑 app target 的 UI 测试，因为没有）

**注意事项**：
- AppContainer 当前 114 行，加 9 个依赖 + adapter 后预估 ~200 行；不超 swiftlint warning 500
- `ResultPanelWindowSinkAdapter` 是新增类型（在 SliceAIApp/ 而非 Windowing/，因为它跨 Windowing + Orchestration 两层依赖，放 SliceAIApp 是合适的 composition root 位置）

### M3.2 — 触发通路切到 ExecutionEngine（1 人天）

**目标**：`AppDelegate.execute(tool:payload:)` 切到 `execute(tool:snapshot:)` → `ExecutionEngine.execute(tool:seed:)` → 消费 `AsyncStream<ExecutionEvent>` → 翻译为 ResultPanel API 调用。

**Entry**：M3.1 完成；ExecutionEngine 已装配。

**改造点**：
- `AppDelegate.execute(tool:payload:)` 签名改为 `execute(tool: Tool, snapshot: SelectionSnapshot)`
- 构造 `ExecutionSeed`：
  ```swift
  let seed = ExecutionSeed(
      invocationId: UUID(),
      selection: snapshot,
      app: AppDescriptor(bundleID: snapshot.appBundleID, name: snapshot.appName, url: snapshot.url),
      hotkeyTrigger: triggerSource,  // mouseUp / commandPalette
      timestamp: Date()
  )
  ```
- 调 `await container.executionEngine.execute(tool: tool, seed: seed)` 拿 `AsyncStream<ExecutionEvent>`
- `for await event in stream`：按 D-30 表翻译为 ResultPanel API
- `streamTask.cancel()` 仍由 ResultPanel onDismiss 调用；ExecutionEngine 内 `withTaskCancellationHandler` 已在 M2 落地（codex-loop R10 fix），cancel 会级联到 ContextCollector / PromptExecutor

**Exit (DoD)**：
- [ ] AppDelegate 单元逻辑（不含 UI）编译通过
- [ ] 手工启动 app + 划词触发 → 浮条出现 → 点工具 → ResultPanel 流式出 token（与 v0.1 视觉等价）

**注意事项**：
- AppDelegate 当前 445 行；改造后预估 ~500 行（接近 swiftlint warning 500），可能需要把 ExecutionEvent 翻译逻辑抽到独立 `ExecutionEventConsumer` helper 类
- `triggerSource: TriggerSource` 是 SliceCore enum（M1 已落地），有 `.mouseUp` / `.commandPalette` 等 case；当前 v1 没用，M3 接入时要传

### M3.3 — ConfigurationStore 启动按 §3.7 加载 + migrator（0.5 人天）

**目标**：app 启动时按"v2 → v1 migrate → default" 三步加载配置；v1 文件永不被修改。

**Entry**：M3.0 完成（ConfigurationStore 已 rename）；M3.1 装配 configStore 时已传入。

**改造点**：
- `ConfigurationStore.current()` 是 `async throws`（M1 plan §B 第七轮 P1 已落地）
- AppContainer 启动时 `try await configStore.current()`：
  ```swift
  do {
      let config = try await configStore.current()
      // ... 装配其他依赖
  } catch {
      // 弹 alert + 中止启动（M1 plan §B 建议）
      let alert = NSAlert()
      alert.messageText = "SliceAI 配置文件损坏"
      alert.informativeText = "\(error.userMessage)\n\n建议：备份并删除 ~/Library/Application Support/SliceAI/config-v2.json 后重启"
      alert.runModal()
      NSApp.terminate(nil)
  }
  ```

**Exit (DoD)**：
- [ ] 启动时若 config-v2.json 存在 → 直接读
- [ ] 启动时若仅 config.json 存在 → 跑 migrator 写 config-v2.json；diff 验证 v1 字段无丢失
- [ ] 启动时若都不存在 → 写 DefaultConfiguration.initial() 到 config-v2.json
- [ ] 启动时若 config-v2.json 损坏 → 弹 alert + 中止启动（不静默覆盖）
- [ ] 单测覆盖：M1 已有 `V2ConfigurationStoreTests`（rename 后 `ConfigurationStoreTests`）含 `test_load_*` 系列

**注意事项**：
- 此 task 大部分代码已在 M1 落地，M3.3 主要是把 AppContainer 启动逻辑接对
- 如果 M3.1 装配时已写好"`try await configStore.current()` + alert 中止启动" 的逻辑，M3.3 实际只是验收 task

### M3.4 — 删除 SliceCore/ToolExecutor.swift（0.5 人天）

**目标**：物理删除 v1 ToolExecutor。

**Entry**：M3.2 完成（触发链已切到 ExecutionEngine，ToolExecutor 已无 caller）。

**改造点**：
- `git rm SliceAIKit/Sources/SliceCore/ToolExecutor.swift`
- 删除对应 `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift`（若存在）

**Exit (DoD)**：
- [ ] `grep -rn "ToolExecutor" SliceAIKit/ SliceAIApp/` 0 匹配
- [ ] swift build / test / xcodebuild / swiftlint 全绿

**注意事项**：
- 这个 task 看似简单，但要确保 M3.2 真的把所有 caller 切完了；否则编译会失败
- M3.0 Step 2 也可以一并删 ToolExecutor，但**不推荐**——M3.0 期间 ToolExecutor 还在 AppDelegate 被引用，删了会编译不过；按 spec §4.2.3 把 ToolExecutor 删除单独标 M3.4 是合理的边界

### M3.5 — 端到端手工回归（1.5 人天）

**目标**：spec §4.2.5 8 项手工清单全过 + 4 个内置工具实机行为与 v0.1 等价。

**Entry**：M3.4 完成；CI gate 全绿。

**分工**：

| 项 | 执行人 | 验证方式 |
|---|---|---|
| Safari 划词翻译 → 弹浮条 → 点 "Translate" → ResultPanel 流式 | 用户 | 截图 / 录屏 / 报告"通过 / 不通过" |
| ⌥Space → 命令面板 → 搜索 → 选工具 → 同上 | 用户 | 同上 |
| Regenerate / Copy / Pin / Close / Retry / Open Settings | 用户 | 同上 |
| Accessibility 权限 revoke 后的降级提示 | 用户 | 临时去 System Settings 关 SliceAI 权限 → 触发 → 验证降级 fallback |
| 无 API Key 时的错误提示 | 用户 | Settings 清空 OpenAI key → 触发 → 验证 ResultPanel.fail UX |
| 修改 Tool / Provider 后配置立即生效并写入 config-v2.json | Claude（自动化） + 用户（人工 spot check） | 单测：`ConfigurationStore.update()` 写入路径断言；用户：手工改一次 Tool prompt 后 cat config-v2.json |
| 删除 config-v2.json 后重启：app 能从 config.json 重新 migrate | 用户 | 备份 config-v2.json + 删除 → 重启 → 验证迁移 + diff config.json 仍未变 |
| 同一机器切回旧分支 / 旧 build：旧 app 读取原 config.json 仍正常 | 用户 | 切到 main pre-M3 commit + 重 build + 启动 → 验证 |

**Exit (DoD)**：
- [ ] 8 项全部"通过"
- [ ] 4 个内置工具（Translate / Polish / Summarize / Explain）的输出与 v0.1 在相同 prompt 下肉眼等价（不要求 token-by-token，仅要求"功能正常 + 流式正常"）

**注意事项**：
- Claude 不能跑真机回归（需要 GUI / Safari / 真实 OpenAI API）；plan 阶段必须明确"用户拿到 PR 后跑回归 + 反馈"
- 如果某项不通过 → 回到 implementation；reset task status

### M3.6 — 文档归档 + v0.2 release（1 人天）

**目标**：归档 M3 实施过程；发 v0.2 tag + 打 unsigned DMG。

**改造点**：
- `README.md` 项目模块表更新（V2* 命名 → 正名；新增 Orchestration / Capabilities 模块说明）
- `CLAUDE.md` 架构总览段更新（同上）
- `docs/Module/` 目录新建并补：`SliceCore.md` / `Orchestration.md` / `Capabilities.md`（按 user CLAUDE.md §1.1 项目文档规范）
- `docs/Task-detail/2026-04-28-phase-0-m3-mini-spec.md`（本 mini-spec 的实施过程归档）+ `docs/Task-detail/2026-04-XX-phase-0-m3-implementation.md`（implementation plan 的 Task-detail）
- `docs/Task_history.md` 加 M3 索引
- `docs/v2-refactor-master-todolist.md` 把 M3 状态从 ⏳ 改为 ✅

**v0.2 release 时机**：M3 PR merge 后**立即**发 v0.2 tag + DMG（用户 R1 决策 A，见 Q1 / D-31）。具体顺序：① §4.2.5 8 项手工回归全过 → ② xcodebuild Debug build SUCCEEDED → ③ scripts/build-dmg.sh 0.2.0 验证产物 → ④ git tag v0.2 + push → ⑤ GitHub Release（draft）创建

**Exit (DoD)**：
- [ ] README / CLAUDE.md / docs/Module/* 更新
- [ ] Task_history.md 加 Task 35 + Task 36（M3 mini-spec + M3 implementation）
- [ ] master todolist M3 状态 → ✅
- [ ] git tag v0.2 + push + scripts/build-dmg.sh 0.2.0 生成 build/SliceAI-0.2.0.dmg
- [ ] GitHub Release（draft）创建（按 .github/workflows/release.yml 规则触发）

---

## 5. 关键设计决策（Decisions）

> 接续 v2 spec §5.2 + M1 plan / M2 plan 的 D-1 ~ D-31 决策序列。本 mini-spec 引入 D-26 ~ D-31。

### D-26 · M3.0 rename pass 用 5 步小 commit 序列

- **决策**：M3.0 rename 不打成单 commit，按"caller 切 V2* / 删 v1 / rename V2* → 正名 / rename PresentationMode / rename SelectionOrigin" 5 步推进，每步独立验证 4 关 CI gate。**Step 1（caller 切 V2*）保持单 commit 不再细拆**——用户初审 Q3 已确认。
- **理由**：
  - 单大 commit 不可 review；中途 CI 挂掉无法定位是哪个 rename 引入的。5 步小 commit 让 reviewer 能按"先 caller 切换 → 再删 v1 → 再 rename"的依赖顺序逐步验证；Codex review 也可以按 step 反向 audit
  - Step 1 虽然涉及 30+ 文件，但**零删除 + 零 rename**，纯 caller 切换；这是"v1 仍在但已无 production 引用"的最小风险窗口，CI gate 一次验证就够；按模块拆 5 个 sub-commit 反而让"切完一半"的中间态不可编译
- **风险**：5 个 commit 比 1 个慢 4 倍。但 M3 风险高，慢比错好。

### D-27 · AppContainer 装配 9 个依赖的 wiring 方案

- **决策**：见 §M3.1 表格。`PermissionBroker` / `WindowSink` 等 protocol 类型用 v0.2 production 实现（DefaultPermissionBroker / ResultPanelWindowSinkAdapter）；MCP / Skill 仍用 M2 落地的 Mock；其他 actor 直接 `()` 实例化或注入工厂。
- **理由**：v0.2 不引入真实 MCP / Skill / 弹窗 UX（spec §4.2.2 out-of-scope 明确）；用 Mock + Default 装配让 ExecutionEngine 主流程能在不阻塞 Phase 1 实施的前提下生效。
- **风险**：Mock MCP / Skill 在 production binary 内，理论上 dead-code-strip 应清掉（M2 Task-detail §7.6 已记此 audit 项）。M3 不重新 audit；Phase 1 接真实 client 时再统一处理。

### D-28 · SelectionService.capture() 返回类型迁移 + protocol 改名

- **决策**：
  1. `SelectionService.capture()` 返回类型由 `SelectionPayload?` 改为 `SelectionSnapshot?`
  2. v1 `protocol SelectionSource`（SelectionCapture/SelectionSource.swift）整体删除 + 改名为 `protocol SelectionReader`（避免与 spec §3.3 的 enum `SelectionSource` 同名）
  3. `ClipboardSelectionSource` / `PrimarySelectionSource` 实现 `SelectionReader` 而非旧 `SelectionSource`；类型名保持原状（仅协议名改）
- **理由**：
  - SelectionPayload 删除是 M3.0 必做；下游 capture() 必须返回 SelectionSnapshot
  - v1 protocol `SelectionSource` 与 v2 enum `SelectionSource`（spec §3.3 设计）同名冲突；rename 是恢复 spec 原意的前提
  - protocol 新名 `SelectionReader` 比 `SelectionSourceProtocol` 更短更准（行为是"读"选区）
- **风险**：实现类名 `ClipboardSelectionSource` / `PrimarySelectionSource` 跟 enum case `SelectionSource.clipboardFallback` / `.accessibility` 仍有语义偏移，但属于命名美学问题；Phase 1+ 再考虑统一

### D-29 · SettingsUI 数据 binding "零行为变化" 策略

- **决策**：
  - ToolEditorView 仍展示 `systemPrompt` / `userPrompt` / `temperature` / `provider picker` / `model 输入` 5 个字段，**视觉 100% 等价 v1**
  - 数据 binding 适配 V2Tool：
    - `tool.systemPrompt` → `tool.kind.prompt.systemPrompt`（用 PromptTool extractor）
    - `tool.userPrompt` → `tool.kind.prompt.userPrompt`
    - `tool.providerId` / `tool.modelId` → `tool.kind.prompt.provider.fixed.providerId` / `.modelId`
    - `tool.temperature` → `tool.kind.prompt.temperature`
    - `tool.variables`（v1 自定义变量字典）→ Phase 1 才支持（v2 用 `contexts`）；v0.2 暂时**隐藏**这个字段，addTool 默认空
  - ProviderEditorView 加 `kind: ProviderKind` 字段：默认 `.openAICompatible`，用户**不可见**（隐藏 picker）；`capabilities: [ProviderCapability]` 默认 `[]`，同样隐藏
  - SettingsViewModel.addTool() 默认创建 `Tool(kind: .prompt(PromptTool(...)))`；不暴露 `.agent` / `.pipeline`
- **理由**：
  - Spec §4.2.4 DoD 硬约束 "Settings 界面无功能变化"
  - 用户感知零变化是 Phase 0 的核心承诺
  - 隐藏 `kind` / `capabilities` UI 让 Phase 1 加 ToolKind 三态编辑器时有改动空间
- **风险**：
  - 部分 V2Tool / V2Provider 字段（contexts / outputBinding / displayMode / capabilities）在 UI 层"不可见但底层已存在"，可能让用户手改 config-v2.json 后 UI 无法识别——但这是 Phase 1 提供 advanced UI 的入口，不阻塞 v0.2

### D-30 · ResultPanel 消费 ExecutionEvent 的适配方式

- **决策**：在 SliceAIApp 层（不是 Windowing 层）写一个 `ExecutionEventConsumer` helper，把 `AsyncStream<ExecutionEvent>` 翻译为 ResultPanel 的现有方法调用；ResultPanel API 不变。
- **翻译表**：
  ```
  .started(invocationId)         → 仅记日志（ResultPanel 已在 stream 启动前 open）
  .streamChunk(_, delta)         → ResultPanel.append(delta)
  .completed(report)             → ResultPanel.finish()
  .failed(report, error)         → ResultPanel.fail(error, onRetry:, onOpenSettings:)
  .permissionDenied(...)         → ResultPanel.fail(.permission(.userDenied), ...)
  .invocationCompleted(report)   → ignore（已在 ExecutionEngine 内写 audit / cost）
  ```
- **理由**：
  - 把 ExecutionEvent 翻译职责放在 SliceAIApp（composition root 层）让 Windowing 不依赖 Orchestration（保持 Windowing 仅依赖 DesignSystem）
  - 复用现有 ResultPanel API 避免 v0.2 重构 Windowing
  - Phase 2 加 BubblePanel / InlineReplaceOverlay 时再考虑 OutputDispatcher 直接持有多种 sink
- **风险**：双向翻译让 SliceAIApp 多 ~50 行 helper；可接受

### D-31 · v0.2 release tag 时机

- **决策**：M3 PR merge 后**立即**发 v0.2 tag + scripts/build-dmg.sh 0.2.0 打 unsigned DMG。用户初审 Q1 已确认。
- **理由**：
  - Phase 0 是底层重构，**无用户可见新功能**；早发 tag 作为 archival milestone 的成本极低
  - Phase 1 自然演进到 v0.3（MCP + 5 个 ContextProvider 接入），如果 v0.2 不发，Phase 1 实施期间会出现"main 已经走到 Phase 1 一半但没有可回退的 baseline tag"的窘境
  - "稳定 1 周再发"对一个 unsigned DMG + 当前唯一用户（作者本人）+ §4.2.5 已含手工回归的项目意义不大
- **风险**：merge 后立即发，若发现回归不能 roll back tag（GitHub Release 可 delete + recreate，但 git tag 已分发就是公开的）。**缓解**：scripts/build-dmg.sh 验证通过 + §4.2.5 8 项手工回归全过 + xcodebuild Debug build SUCCEEDED 之后再 tag；若发现回归，发 v0.2.1 patch 而非 retag

---

## 6. 已拍板的 Open Questions

> 用户初审 R1（2026-04-28）三个 Open Questions 全部接受 Claude 推荐。本节保留问题原文 + 决策，便于日后 trace。

### Q1：v0.2 release tag + unsigned DMG 时机 — **决策 A**

- **背景**：spec §4.2.4 DoD 含"发布 v0.2 tag（Release Notes 按 scripts/build-dmg.sh 打包 unsigned DMG）"，但没说时机。
- **选项**：
  - A. M3 PR merge 后立即发 v0.2（archival mark；Phase 1 自然演进到 v0.3）
  - B. merge 后等 1 周稳定再发（多 1 周缓冲发现回归）
- **决策**：**A**（用户 R1 接受）。落地见 D-31 + M3.6。

### Q2：mini-spec 自身的 Codex review loop 上限 — **决策 A**

- **背景**：M2 跑了 11 轮 Codex review loop 才 APPROVE；M3 改动覆盖面更广（rename 跨 8 模块 + AppContainer 装配 + 触发链改造），review 轮次可能更多。
- **选项**：
  - A. 不设上限，跑到 APPROVE 为止（M2 模式），但每 5 轮回到用户简短 sync 进度
  - B. 设硬上限 10 / 15 / 20 轮，超出则用户人工 sync
- **决策**：**A**（用户 R1 接受）。落地见 §11.2。

### Q3：M3.0 Step 1 是否拆得更细 — **决策 A**

- **背景**：M3.0 Step 1 一次切 30+ 文件 caller 引用，commit 体积偏大。
- **选项**：
  - A. 保持单 commit（已是"零删除 + 零 rename"的最小风险窗口）
  - B. 按模块拆：SettingsUI / AppContainer / Windowing / SelectionCapture / Tests 5 个 sub-commit
- **决策**：**A**（用户 R1 接受）。落地见 D-26。

---

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| **R1** rename 跨 8 模块导致 git history 跟丢 | 用 `git mv` 让 git follow rename；commit message 显式写"git mv X to Y" 让 reviewer 能搜索 |
| **R2** Swift 6 严格并发跨 actor 边界出 Sendable 警告 | M2 已踩坑（FlowContext class 处理）；M3 接 AppContainer 时 ExecutionEngine 是 actor，AppDelegate `@MainActor`，调用必须 `await container.executionEngine.execute(...)`；ResultPanel 也是 `@MainActor`，事件翻译 helper 必须在 `@MainActor` 内消费 stream |
| **R3** SourceKit "No such module" 假阳骚扰 | M2 Task-detail §Known traps 已记；M3 期间统一以 `swift build` / `swift test` / `xcodebuild` / `swiftlint --strict` 4 关 CI gate 为唯一真值，忽略 SourceKit warning |
| **R4** xcodebuild 必须每个子任务后跑 | M2 仅最后 task 跑；M3 改动 SliceAIApp 后每个 step 都必须跑（启动崩溃不会被 SwiftPM 测试发现）；plan 在每个 task 的 verification 步骤里写明 |
| **R5** 用户现有 config.json 在 migrator 跑出错 | M1 已落地 ConfigMigratorV1ToV2 + 10+ fixture 单测；但**真实用户 config 边界形态未必都覆盖**——M3 mini-spec 要求实施期跑一次 dry-run（用真实 ~/Library/Application Support/SliceAI/config.json 输入 migrator，diff 输出验证） |
| **R6** PermissionBroker default-allow 与 audit log 配合不当导致刷屏 | M2 已落地 audit log + 脱敏；v0.2 PermissionBroker 走 default-allow 但**仍写 audit**——日志在 `~/Library/Application Support/SliceAI/audit.jsonl`，不在 stdout，不刷屏 |
| **R7** 4 个内置工具的 ProviderSelection.fixed 适配错误 | DefaultV2Configuration 已在 M1 用 `.fixed(providerId: openAIDefault.id, modelId: nil)` 装配；migrator 也对 v1 Tool.providerId / modelId → `.fixed(providerId, modelId)`；M3 不动这部分逻辑 |
| **R8** ToolEditorView 数据 binding 改写后 UI bug 难发现 | 单测覆盖不到 SwiftUI binding；M3.5 用户手工回归"修改 Tool / Provider 后配置立即生效"作为兜底 |

---

## 8. DoD（spec §4.2.3 M3 + master todolist §3.3 合并）

- [ ] `swift build` 成功（全 10 个 target）
- [ ] `swift test --parallel --enable-code-coverage` 全绿；覆盖率：SliceCore ≥ 90% / Orchestration ≥ 75% / Capabilities ≥ 60%
- [ ] `swiftlint lint --strict` 0 violations
- [ ] `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` BUILD SUCCEEDED
- [ ] §4.2.5 8 项手工回归全部通过（用户报告）
- [ ] 4 个内置工具（Translate / Polish / Summarize / Explain）实机行为与 v0.1 等价
- [ ] `config-v2.json` 实际生成；旧 `config.json` 未被修改
- [ ] 同一机器切回旧分支 / 旧 build：旧 app 读取原 `config.json` 仍正常
- [ ] **V2 命名已回归 spec 原名**：`grep -rn "V2Tool\|V2Provider\|V2Configuration\|V2ConfigurationStore\|DefaultV2Configuration\|PresentationMode\|SelectionOrigin"` 在 SliceAIKit/ + SliceAIApp/ 0 匹配
- [ ] PR 不引入任何 TODO / FIXME 注释（要做的留成 Issue）
- [ ] `docs/Task-detail/2026-04-28-phase-0-m3-mini-spec.md`（mini-spec 归档）+ `docs/Task-detail/2026-04-XX-phase-0-m3-implementation.md`（implementation 归档）
- [ ] master todolist M3 状态 → ✅
- [ ] v0.2 release tag + DMG（M3 PR merge 后立即发，决策 D-31）

---

## 9. Phase 0 整体 DoD（M1 + M2 + M3 全部合入后，spec §4.2.4）

> 本节抄自 spec §4.2.4，作为 M3 PR merge 时一并验证的总收口。

- [ ] `swift build` 成功（全 10 个 target）
- [ ] `swift test --parallel --enable-code-coverage` 全绿；覆盖率：SliceCore ≥ 90% / Orchestration ≥ 75% / Capabilities ≥ 60%
- [ ] `swiftlint lint --strict` 0 violations
- [ ] 原 4 个内置工具在实机上与 v0.1 行为等价（翻译 / 润色 / 总结 / 解释）
- [ ] 老 `config.json` 经 migrator 产出 `config-v2.json`；**旧 `config.json` 未被修改**；切回旧分支 app 仍正常
- [ ] Settings 界面无功能变化（不要误加 UI）
- [ ] PR 不引入任何 TODO / FIXME 注释
- [ ] `docs/Task-detail/phase-0-*.md` 归档 M1/M2/M3 各自的实施过程
- [ ] 发布 **v0.2** tag（Release Notes 按 `scripts/build-dmg.sh` 打包 unsigned DMG）

---

## 10. References

- **Spec**：`docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md` §3.3 / §3.4 / §3.7 / §3.8 / §3.9 / §4.2.3 / §4.2.4 / §4.2.5
- **M1 plan**：`docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（顶部 §A 实施期改名 / §B 第七轮评审 / §C 第八轮评审）
- **M2 plan**：`docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`（spec §3.4 step 对照表 / §C-1 zero-touch / §C-7 复制非替换）
- **M2 Task-detail**：`docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md` §7.3（实施期偏离 plan）/ §7.6（M3 承接 backlog）
- **Master todolist**：`docs/v2-refactor-master-todolist.md` §3.3 M3 + §8 SOP
- **决策索引**：spec §5.2 D-1 ~ D-25；本 mini-spec 引入 D-26 ~ D-31
- **CLAUDE.md**：项目通用规则 + 架构总览 + 模块依赖不变量

---

## 11. 评审执行说明

### 11.1 用户初审

mini-spec 草稿写完后，用户先初审：
- 范围是否合适（in-scope / out-of-scope 是否漏 / 多）
- M3.0 5 步小 commit 序列是否可行
- D-26 ~ D-31 是否有反对意见
- Q1 / Q2 / Q3 三个 open question 拍板

### 11.2 Codex review loop

用户初审通过后（R1 已通过，2026-04-28），进入 `superpowers:codex-review-loop`：
- **节奏（Q2 决策 A）**：不设硬上限轮数，跑到 APPROVE 为止；但**每 5 轮**回到用户做一次简短 sync（汇报本批 5 轮收敛了哪些 finding / 还剩哪些争议 / 是否要调整方向），避免 30+ 轮无人监督跑飞
- 每轮 Codex review verdict 写到 §0 评审与修订表
- 接受的 finding 直接修订 mini-spec
- 拒绝的 finding 写"已 defer / 不接受"理由 + 留在表内便于 trace
- APPROVE 后进入 `superpowers:writing-plans` 出 implementation plan

### 11.3 implementation plan

mini-spec APPROVE 后，下一个 task：
- 创建 `docs/superpowers/plans/2026-04-XX-phase-0-m3-switch-to-v2.md`
- 按 mini-spec 的任务拆解（M3.0 ~ M3.6）展开为 sub-task 级粒度
- 含每个 sub-task 的代码示例 / 验证命令 / 回滚方案
- 实施期再走一次 Codex review loop（仅针对代码 + 实测结果）

---

> **本 mini-spec 完成 = Phase 0 M3 真正进入实施前的最后一道闸门**。
> 写到这里 ~ 700 行；M3 implementation plan 预估 ~1500 行（参照 M2 plan 2232 行体量，但 M3 任务数较少）。
