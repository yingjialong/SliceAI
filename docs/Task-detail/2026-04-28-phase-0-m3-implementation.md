---
task: Phase 0 M3 — Switch to V2 implementation
date: 2026-04-30
status: in_progress
---

# Phase 0 M3 — Switch to V2 implementation

## 背景

根据已对齐的 mini-spec 与 implementation plan，M3 负责把 V2 类型族、Orchestration、Capabilities 接入真实 app 启动链路，删除 v1 冲突类型族，完成 rename pass、端到端回归与 v0.2.0 unsigned DMG release。

实施计划文件：

- `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`
- `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`

## 执行方式

本轮按用户要求采用 Subagent-Driven 模式：

- 主线程负责任务拆解、跨 worker 集成、验证、提交与文档更新。
- worker 按 disjoint ownership 修改文件，禁止互相覆盖或 revert 他人改动。
- 每个可提交单元按 plan 跑 4 关 gate：SwiftPM build / SwiftPM test / xcodebuild / SwiftLint。

## ToDoList

- [x] 提交 plan/spec 口径对齐修复。
- [x] M3.1.A：`V2ConfigurationStore.load()` both-missing 写默认 config-v2.json + XCTest。
- [x] M3.1.B：SliceAI app target 加 Orchestration / Capabilities 依赖 + CI 增加 xcodebuild gate。
- [x] M3.1.C-1：新增 `InvocationGate` + `ResultPanelWindowSinkAdapter`。
- [x] M3.1.C+D：AppContainer additive 装配 + AppDelegate async bootstrap UX 原子提交。
- [ ] M3.1.E：冒烟验证（自动化部分完成；命令面板 / TextEdit 浮条 / 真实 LLM 子集已通过；Safari / 启动失败弹窗待人工确认）。
- [x] M3.0 Step 1：caller 切换 + ExecutionEventConsumer + SettingsUI binding + automated tests/gates。
- [ ] M3.0 Step 1 手工 smoke：命令面板 + TextEdit 浮条已通过；Safari 划词 / 启动失败弹窗待人工确认。
- [x] M3.0 Step 2：删除 v1 类型族 + SelectionReader + LLMProviderFactory 升级。
- [x] M3.0 Step 3：V2* rename 回 spec 正名。
- [x] M3.0 Step 4：PresentationMode → DisplayMode。
- [x] M3.0 Step 5：SelectionOrigin → SelectionSource。
- [x] M3.2/M3.3/M3.4：CLI 自动化验收完成（4 关 gate、targeted tests、grep validation）。
- [ ] M3.2/M3.3：手工 GUI / 真实 LLM 子集已通过；真实启动场景待人工确认。
- [ ] M3.5：13 项手工回归（安全子集已部分通过；破坏性/权限类场景待确认后执行）。
- [ ] M3.6：文档归档 + v0.2.0 release。

## 当前实施记录

### 2026-04-30

- 已提交文档口径修复：`c1cf5bb docs(m3): align plan with mini-spec before implementation`。
- 已启动两个 worker 并行处理：
  - M3.1.A：`V2ConfigurationStore.swift` / `V2ConfigurationStoreTests.swift`
  - M3.1.B：`SliceAI.xcodeproj/project.pbxproj` / `.github/workflows/ci.yml`
- 已提交 M3.1.A：`f86693e fix(slicecore): persist default v2 config on first launch`。
  - `V2ConfigurationStore.load()` 在 v2/v1 都不存在时，写入 `DefaultV2Configuration.initial()` 到 `config-v2.json` 后返回。
  - 新增并补强 `test_load_withNeither_writesDefaultToV2Path`，覆盖返回默认配置、只创建 v2 文件、不创建 v1 文件，以及写出的 JSON 可解码且等于返回值。
  - 注意：全量 SwiftPM 第一次执行时 `OrchestrationTests.ExecutionEngineTests/test_execute_cancellationDuringPromptStream_skipsLaterChunkDispatch` 曾间歇失败；单独复跑该用例通过，随后按原命令重跑全量通过。该失败不在本次 M3.1.A 修改模块内。
- 已提交 M3.1.B：`4cacde6 chore(xcodeproj+ci): add Orchestration + Capabilities deps + xcodebuild PR CI gate`。
  - `SliceAI` app target 显式链接 `Orchestration` 与 `Capabilities` 两个 SwiftPM product。
  - GitHub Actions 在 SwiftPM test 后、SwiftLint 前新增 `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`。
  - `xcodebuild` 输出确认 `SliceAI` target dependency graph 已包含 `Orchestration` 与 `Capabilities`。
- 已提交 M3.1.C-1：`48dcdd5 feat(orchestration+sliceaiapp): add InvocationGate + ResultPanelWindowSinkAdapter`。
  - 新增 `InvocationGate`，把 active invocation state、`ifCurrent` 清理 guard、`gatedAppend` chunk gating 收敛为 Orchestration target 内唯一 single-flight 状态来源。
  - 新增 `InvocationGateTests`，直接测试真实 gate；TDD RED 为 `cannot find InvocationGate in scope`，GREEN 后 8 tests / 0 failures。
  - 新增 `ResultPanelWindowSinkAdapter`，实现 `WindowSinkProtocol`，只委托 `InvocationGate.gatedAppend` 后调用 `ResultPanel.append`，adapter 自身不复制 `shouldAccept` 分支。
  - `SliceAI.xcodeproj/project.pbxproj` 已注册 adapter 到 app target Sources；grep gate 四处计数均满足要求。
- 已提交 M3.1.C+D：`de823eb feat(sliceaiapp): wire v2 runtime with async bootstrap`。
  - `AppContainer.bootstrap()` 改为 async throwing composition root，启动时 eager load `V2ConfigurationStore.current()`，确保迁移 legacy 或首次写入默认 `config-v2.json`。
  - `AppContainer` 保留 v1 `configStore` / `toolExecutor`，新增 v2 `v2ConfigStore` / `executionEngine` / `outputDispatcher` / `invocationGate` / `resultPanelAdapter` / `llmProviderFactory`，M3.1 阶段只装配不接 caller。
  - `AppDelegate` 改为异步启动：bootstrap 成功后再完成菜单栏、AX monitor、onboarding/runtime wiring；bootstrap 失败时弹出 "SliceAI 启动失败" NSAlert 并退出。
  - 为降低 `bootstrap()` 复杂度，把装配拆为 `makeLegacyDependencies()`、`makeV2RuntimeDependencies()`、`makeExecutionEngine(dependencies:)`，通过 `swiftlint function_body_length/function_parameter_count` 约束。
  - 子代理短审未发现阻塞问题；记录两个非阻塞风险：菜单栏 app 的启动失败 alert 需要手工验证前台可见性；v2 config/cost/audit 初始化失败会按 spec 阻断 v1 app 启动。
- 已完成 M3.1.E 自动化 smoke。
  - v1 字段保留检查通过：`configStore: FileConfigurationStore` 与 `toolExecutor: ToolExecutor` 均存在。
  - v2 字段新增检查通过：`v2ConfigStore` / `executionEngine` / `outputDispatcher` / `resultPanelAdapter` 均存在。
  - v2 caller 检查通过：`rg "container\\.executionEngine|container\\.outputDispatcher|container\\.v2ConfigStore" SliceAIApp` 0 命中。
  - v1 caller 检查确认当前触发链仍走 `container.toolExecutor.execute(...)`。
  - 当前 app support 目录只有既有 `config.json`；因为未启动本次 Debug app，`config-v2.json` / `cost.sqlite` / `audit.jsonl` 创建验证待手工 GUI smoke。
  - 未执行 Safari 划词/命令面板实机流式验证，未执行 chmod 模拟启动失败弹窗验证；原因是这两步会真实操作菜单栏 app / 全局权限 / 用户桌面状态，不能用自动命令伪造通过。
- 已完成 M3.0 Step 1 代码切换与自动化 gate。
  - `AppContainer` 移除 v1 `FileConfigurationStore` / `ToolExecutor` 装配，启动链路只暴露 `V2ConfigurationStore`、`ExecutionEngine`、`OutputDispatcher`、`InvocationGate` 与 `ResultPanelWindowSinkAdapter`。
  - `AppDelegate` 的浮条、命令面板与执行入口改为读取 `V2Configuration`、传递 `V2Tool`，并通过 `ExecutionEngine.execute(seed:tool:)` 消费 `ExecutionEvent` 流。
  - 新增 `ExecutionEventConsumer` 与 `AppDelegate+Execution`，把 started / llmChunk / failed / finished / sideEffect / permission / notImplemented 等事件翻译为 `ResultPanel` 行为；`.notImplemented` 失败不会再被后续 `.finished` 覆盖。
  - `SettingsUI` / `Windowing` 改为绑定 V2 类型；Provider 编辑改为 debounce 自动保存，配置加载失败时阻止即时保存覆盖损坏文件；非 prompt 工具只显示基础字段与暂不支持提示，避免可编辑字段 setter no-op。
  - `SelectionPayload.toExecutionSeed(...)`、`SliceError.execution(...)`、`InvocationOutcome.ErrorKind.execution` 补齐 app caller 所需 API；`OutputDispatcher` 非 window presentation mode 在 Phase 0 统一 fallback 到 window sink，并限制 fallback 日志去重缓存为 128 条。
  - 新增/补强 `SelectionPayloadTests`、`SliceErrorTests`、`InvocationReportTests`、`OutputDispatcherFallbackTests`、`SingleWriterContractTests`、`ExecutionStreamOrderingTests` 等测试，覆盖 caller seed 映射、错误分类、fallback 行为与 single-writer gating 顺序。
  - 质量短审提出的 6 个问题已逐项修复：Provider 编辑丢失、notImplemented 被 finished 覆盖、loadError 即时保存防护、非 prompt 编辑器 no-op、fallback 日志无界增长、ordering test sleep/Task 不稳定。
  - 聚焦复审结论：`APPROVED`；复审仅检查上述 6 个问题及直接相关回归，未发现新的阻塞问题。

## 变动文件清单

- `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift`
- `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift`
- `SliceAI.xcodeproj/project.pbxproj`
- `.github/workflows/ci.yml`
- `SliceAIKit/Sources/Orchestration/Output/InvocationGate.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/InvocationGateTests.swift`
- `SliceAIApp/ResultPanelWindowSinkAdapter.swift`
- `SliceAIApp/AppContainer.swift`
- `SliceAIApp/AppDelegate.swift`
- `SliceAIApp/AppDelegate+Execution.swift`
- `SliceAIApp/ExecutionEventConsumer.swift`
- `SliceAIApp/MenuBarController.swift`
- `SliceAIKit/Sources/SliceCore/SelectionPayload.swift`
- `SliceAIKit/Sources/SliceCore/SliceError.swift`
- `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`
- `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift`
- `SliceAIKit/Sources/Orchestration/Output/OutputDispatcherProtocol.swift`
- `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ProvidersSettingsPage.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Row.swift`
- `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Bindings.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Support.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Variables.swift`
- `SliceAIKit/Sources/Windowing/CommandPalettePanel.swift`
- `SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift`
- `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/SliceErrorTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/InvocationReportTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/OutputDispatcherTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/OutputDispatcherFallbackTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/AdapterContractTests/SingleWriterContractTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/AdapterContractTests/ExecutionStreamOrderingTests.swift`
- `SliceAIKit/Sources/SliceCore/ConfigurationComponents.swift`
- `SliceAIKit/Sources/SliceCore/ToolLabelStyle.swift`
- `SliceAIKit/Package.swift`
- `SliceAIKit/Sources/SliceCore/LLMProvider.swift`
- `SliceAIKit/Sources/SliceCore/V2Configuration.swift`
- `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift`
- `SliceAIKit/Sources/SliceCore/V2Provider.swift`
- `SliceAIKit/Sources/SliceCore/V2Tool.swift`
- `SliceAIKit/Sources/SliceCore/SelectionContentType.swift`
- `SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift`
- `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`
- `SliceAIKit/Sources/SelectionCapture/SelectionReader.swift`
- `SliceAIKit/Sources/SelectionCapture/AXSelectionSource.swift`
- `SliceAIKit/Sources/SelectionCapture/ClipboardSelectionSource.swift`
- `SliceAIKit/Sources/SelectionCapture/SelectionService.swift`
- `SliceAIKit/Tests/LLMProvidersTests/OpenAIProviderFactoryTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Helpers/MockLLMProvider.swift`
- `SliceAIKit/Tests/OrchestrationTests/PromptExecutorTests.swift`
- `SliceAIKit/Tests/SelectionCaptureTests/SelectionServiceTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ConfigMigratorV1ToV2Tests.swift`
- `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationTests.swift`
- 已删除 v1 文件：`SliceAIKit/Sources/SliceCore/Tool.swift`、`Provider.swift`、`Configuration.swift`、`ConfigurationStore.swift`、`ConfigurationProviding.swift`、`DefaultConfiguration.swift`、`ToolExecutor.swift`、`SliceAIKit/Sources/SelectionCapture/SelectionSource.swift`。
- 已删除 v1-only tests：`ConfigurationAppearanceTests.swift`、`ConfigurationStoreTests.swift`、`ConfigurationTests.swift`、`DefaultConfigurationTests.swift`、`ToolExecutorTests.swift`、`ToolTests.swift`。

## 测试结果

- `swift build`：通过。
- `swift test --filter "SliceCoreTests.V2ConfigurationStoreTests"`：15 tests / 0 failures。
- `swift test --parallel --enable-code-coverage`：第二次全量重跑通过；第一次出现一次非本模块取消流用例间歇失败，单独复跑通过。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：`** BUILD SUCCEEDED **`。
- `swiftlint lint --strict`：0 violations / 0 serious。
- M3.1.B 恢复 Xcode/CI 改动后再次执行四关：`swift build` 通过；`swift test --parallel --enable-code-coverage` 通过；`xcodebuild ... Debug build` 通过且 dependency graph 包含 `Orchestration` / `Capabilities`；`swiftlint lint --strict` 通过。
- M3.1.C-1：`swift test --filter "OrchestrationTests.InvocationGateTests"`：8 tests / 0 failures。
- M3.1.C-1：adapter pbxproj 注册 grep gate：PBXFileReference=3、PBXBuildFile=2、Group children=1、Sources build phase=1，均通过期望。
- M3.1.C-1：四关 gate：`swift build` 通过；`swift test --parallel --enable-code-coverage` 通过（575 tests）；`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过；`swiftlint lint --strict` 通过（0 violations / 0 serious）。
- M3.1.C+D：`swift build` 通过。
- M3.1.C+D：`swift test --parallel --enable-code-coverage` 通过（575 tests）。
- M3.1.C+D：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过。
- M3.1.C+D：`swiftlint lint --strict` 通过（0 violations / 0 serious）。
- M3.1.E 自动化 smoke：v1/v2 装配字段 grep 通过；v2 caller grep 0 命中；v1 caller 仍指向 `toolExecutor.execute`。
- M3.0 Step 1：`swift test --filter 'OrchestrationTests.ExecutionStreamOrderingTests|OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.OutputDispatcherTests|SliceCoreTests.SliceErrorTests|SliceCoreTests.SelectionPayloadTests|OrchestrationTests.InvocationReportTests'` 通过（43 tests）。
- M3.0 Step 1：`swift test --parallel --enable-code-coverage` 通过（592 tests，退出码 0）。
- M3.0 Step 1：`xcodebuild -quiet -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过。
- M3.0 Step 1：`swiftlint lint --strict` 通过（142 files，0 violations / 0 serious）。
- M3.0 Step 1：`git diff --check` 通过。
- M3.0 Step 1：v1 caller 静态残留 grep 在 `SliceAIApp` / `SettingsUI` / `Windowing` 范围内 0 命中；`configStore.current()` 调用均为 `try await`。

## M3.0 Step 2（Task 8）实施方案

### 背景

Step 1 已把 app caller 切到 v2 execution engine，但仓库中仍保留 v1 SliceCore 类型族与 SelectionSource 命名，且 `PromptExecutor` 仍通过 `toV1Provider` helper 把 `V2Provider` 降级给 `LLMProviderFactory`。Task 8 的目标是删除 v1 类型族、把 selection 读取抽象改名为 `SelectionReader`，并让 LLM provider 工厂直接消费 `V2Provider`。

### ToDoList

- [x] 先修改保留测试：`MockLLMProviderFactory` 改为捕获 `V2Provider`，`PromptExecutorTests` 改为验证 factory 直接收到 V2Provider；SelectionCapture 测试改用 `SelectionReader`。
- [x] 迁移 `ToolLabelStyle` 到独立文件，避免删除 v1 `Tool.swift` 后 `V2Tool`/SettingsUI 编译失败。
- [x] `git rm` 删除 v1 SliceCore 7 文件与 `SelectionSource.swift`，新建 `SelectionReader.swift`，保持 `SelectionReadResult` 真实 v1 字段结构。
- [x] 修改 `ClipboardSelectionSource` / `AXSelectionSource` / `SelectionService` conformance 与存在类型。
- [x] 修改 `LLMProviderFactory.make`、`OpenAIProviderFactory.make`、`PromptExecutor.runInternal` 与所有 mock 实现，删除 `PromptExecutor.toV1Provider`。
- [x] 删除 v1-only 测试文件，修正 V2 tests 中仍依赖 v1 Swift 类型的断言。
- [x] 执行 `swift build`，可行则继续执行 targeted tests / full tests。

### 初始风险

- `ToolLabelStyle` 当前定义在 v1 `Tool.swift`，必须先迁移，否则 `V2Tool` 与 SettingsUI 会因符号缺失失败。
- `V2ConfigurationStoreTests` 仍有 v1 `FileConfigurationStore` 隔离断言；删除 v1 store 后需要改为硬编码 legacy JSON 路径级不变量。
- `PromptExecutorTests` 仍把非 openAI kind / nil baseURL 的失败归因于 executor 内部 adapter；Task 8 后该校验应由 `OpenAIProviderFactory` 承担，测试语义需同步。

### 实施结果

- 已用 `git rm` 删除 v1 SliceCore 7 文件：`Tool.swift`、`Provider.swift`、`Configuration.swift`、`ConfigurationStore.swift`、`ConfigurationProviding.swift`、`DefaultConfiguration.swift`、`ToolExecutor.swift`。
- 已用 `git rm` 删除 `SelectionCapture/SelectionSource.swift`，新增 `SelectionReader.swift`；`SelectionReadResult` 保持原字段结构，未新增 timestamp 或错误枚举。
- `ClipboardSelectionSource` / `AXSelectionSource` 改为 conform `SelectionReader`，`SelectionService` 改为持有 `any SelectionReader`。
- `LLMProviderFactory.make` 改为接收 `V2Provider`；`OpenAIProviderFactory` 只接受 `.openAICompatible` 且 `baseURL != nil`，否则抛固定、不拼接用户配置的 `.configuration(.validationFailed(...))` 诊断文案。
- `LLMProviderFactory` 新增 `validate(provider:)` preflight；`PromptExecutor` 在读取 Keychain 前先调用该校验，避免 unsupported provider kind 被误报为 API Key 缺失。
- `PromptExecutor` 删除 `toV1Provider` helper，直接使用 `V2Provider.keychainAccount`、`provider.defaultModel` 和 `llmProviderFactory.make(for: provider, apiKey:)`。
- `PromptExecutorTests` 增加 production `OpenAIProviderFactory + MockKeychain()` 组合用例，覆盖 unsupported kind / nil baseURL 在空 Keychain 场景下仍返回配置校验错误。
- `ToolLabelStyle` 从被删除的 v1 `Tool.swift` 迁移到独立 `ToolLabelStyle.swift`；`HotkeyBindings`、`TriggerSettings`、`ToolbarSize`、`TelemetrySettings` 从被删除的 v1 `Configuration.swift` 迁移到独立 `ConfigurationComponents.swift`。
- 删除 v1-only 测试：`DefaultConfigurationTests.swift`、`ConfigurationStoreTests.swift`、`ToolExecutorTests.swift`、`ToolTests.swift`、`ConfigurationTests.swift`、`ConfigurationAppearanceTests.swift`。
- `ConfigMigratorV1ToV2Tests` 保持通过，仍通过 `LegacyConfigV1` + fixture / hardcoded JSON 触发迁移，不依赖 v1 Swift 类型。

### Step 2 验证结果

- TDD RED：`swift test --filter 'PromptExecutorTests/test_run_factoryReceivesV2ProviderDirectly|OpenAIProviderFactoryTests|SelectionServiceTests/test_prefersPrimarySourceWhenSuccess'` 初次失败，失败点为 `OpenAIProviderFactory.make` 仍接收 v1 `Provider`、`SelectionReader` 未定义。
- TDD GREEN：同一 targeted tests 通过，5 tests / 0 failures。
- Step 2 targeted regression：`swift test --filter 'LLMProvidersTests.OpenAIProviderFactoryTests|OrchestrationTests.PromptExecutorTests|SelectionCaptureTests.SelectionServiceTests|SliceCoreTests.V2ConfigurationStoreTests|SliceCoreTests.V2ConfigurationTests|SliceCoreTests.ConfigMigratorV1ToV2Tests'` 通过，58 tests / 0 failures。
- Provider preflight targeted regression：`swift test --filter 'OrchestrationTests.PromptExecutorTests/test_run_openAIProviderFactoryUnsupportedKind_validatesBeforeKeychain|OrchestrationTests.PromptExecutorTests/test_run_openAIProviderFactoryNilBaseURL_validatesBeforeKeychain|LLMProvidersTests.OpenAIProviderFactoryTests'` 通过，5 tests / 0 failures。
- `swift build`：通过，最后一次复跑 `Build complete! (3.94s)`。
- `swift test --parallel --enable-code-coverage`：通过，569 tests / 0 failures。期间 `ExecutionEngineTests/test_execute_cancellationDuringPermissionGate_skipsAuditAndLLM` 曾出现一次取消时序失败；单独复跑通过，随后全量复跑通过。
- `xcodebuild -quiet -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过。
- `git diff --check`：通过。
- 静态删除检查：v1 7 个 SliceCore 文件与 `SelectionSource.swift` 均不存在；`toV1Provider` / `func make(for provider: Provider` / `capturedProvider: Provider` / `SelectionSource` 关键残留 grep 为 0。
- `swiftlint lint --strict`（从 worktree 根目录执行）：通过，137 files，0 violations / 0 serious。
- Step 2 spec review：`APPROVED`，无 blocking finding；提示提交时必须包含新增 `SelectionReader.swift` / `ConfigurationComponents.swift` / `ToolLabelStyle.swift` / `OpenAIProviderFactoryTests.swift`，并排除历史未跟踪 docs/handoff。
- Step 2 code quality review：先给出 `CHANGES_REQUESTED`，指出 unsupported provider kind 会被 Keychain 状态误报；修复 preflight 后聚焦复审 `APPROVED`。

## M3.0 Step 3（Task 9）实施记录

### 背景

Step 2 已删除 v1 `Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` 等冲突文件，当前 V2 类型族可以回到 spec canonical 名称。Task 9 只做 rename pass，不提前执行 Step 4 `PresentationMode -> DisplayMode` 或 Step 5 `SelectionOrigin -> SelectionSource`。

### ToDoList

- [x] 用 `git mv` 把 SliceCore 源文件从 `V2*` / `DefaultV2Configuration` 改回 canonical 文件名。
- [x] 用 `git mv` 把 SliceCore 测试文件从 `V2*Tests` 改回 canonical 文件名。
- [x] 用 `perl` word boundary 对 Swift 代码执行长前缀优先类型替换。
- [x] 复查 `LegacyConfigV1` 未被误改，且 `PresentationMode` / `SelectionOrigin` 未被提前替换。
- [x] 执行 `swift build`，可行后继续 targeted tests、full tests 与 app target build。

### 实施结果

- 源文件 rename：
  - `V2Tool.swift` -> `Tool.swift`
  - `V2Provider.swift` -> `Provider.swift`
  - `V2Configuration.swift` -> `Configuration.swift`
  - `V2ConfigurationStore.swift` -> `ConfigurationStore.swift`
  - `DefaultV2Configuration.swift` -> `DefaultConfiguration.swift`
- 测试文件 rename：
  - `V2ToolTests.swift` -> `ToolTests.swift`
  - `V2ProviderTests.swift` -> `ProviderTests.swift`
  - `V2ConfigurationTests.swift` -> `ConfigurationTests.swift`
  - `V2ConfigurationStoreTests.swift` -> `ConfigurationStoreTests.swift`
- Swift 类型引用已替换为 canonical 名称：`Tool`、`Provider`、`Configuration`、`ConfigurationStore`、`DefaultConfiguration`；测试 class 名同步改为 `ToolTests`、`ProviderTests`、`ConfigurationTests`、`ConfigurationStoreTests`。
- 额外发现并修正 app 内部 helper 类型 `V2RuntimeDependencies` -> `RuntimeDependencies`，避免 Step 3 后继续保留 V2-prefixed Swift 类型。
- `ConfigMigratorV1ToV2` 与 `LegacyConfigV1` 保留原名；这是 v1 -> v2 迁移边界，不属于本轮 canonical 类型族 rename。
- `PresentationMode` 与 `SelectionOrigin` 未改动，留给 Step 4 / Step 5。
- 质量短审指出测试方法名 / helper 中仍有旧 `V2Provider` / `V2Tool` / `V2Configuration` 语义残留；已同步改为 `test_tool_*`、`test_provider_*`、`test_configuration_*`、`makeOpenAIProvider` 等 canonical 口径。

### Step 3 验证结果

- `rg '\b(V2ConfigurationStore|DefaultV2Configuration|V2Configuration|V2Provider|V2Tool|V2RuntimeDependencies|V2ConfigurationStoreTests|V2ConfigurationTests|V2ProviderTests|V2ToolTests)\b' --glob '*.swift'`：0 命中。
- 扩展命名残留 grep：`rg 'v2tool|V2Tool|v2Provider|V2Provider|v2Configuration|V2Configuration|defaultV2Configuration|DefaultV2Configuration|makeOpenAIV2Provider|OpenAICompatibleV2Provider|V2 链路' SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift`：0 命中。
- `swift build`：通过，最后一次复跑 `Build complete! (3.76s)`。
- Targeted tests：`swift test --filter 'SliceCoreTests.ConfigurationStoreTests|SliceCoreTests.ConfigurationTests|SliceCoreTests.ProviderTests|SliceCoreTests.ToolTests|SliceCoreTests.ConfigMigratorV1ToV2Tests|LLMProvidersTests.OpenAIProviderFactoryTests|OrchestrationTests.PromptExecutorTests|OrchestrationTests.ProviderResolverTests|OrchestrationTests.ExecutionEngineTests'`：106 tests / 0 failures。
- Full tests：`swift test --parallel --enable-code-coverage`：569 tests / 0 failures。
- App target：`xcodebuild -quiet -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过；仅有 Xcode 目的地选择 warning。
- `swiftlint lint --strict`（从 worktree 根目录执行）：通过，137 files，0 violations / 0 serious。
- `git diff --check`：通过。
- Step 3 spec review：`APPROVED`，无 blocking finding。
- Step 3 code quality review：初审 `CHANGES_REQUESTED`，指出暂存区不完整与测试命名残留；修复并重建暂存区后复审 `APPROVED`。

### 残留风险

- 仍保留 `ConfigMigratorV1ToV2`、`LegacyConfigV1`、`config-v2.json` 等版本边界命名；这些是迁移 / 文件 schema 语义，不属于 canonical 类型族残留。
- 提交前必须重建暂存区：此前 index 只记录了 9 个纯 rename，类型替换仍在 unstaged 工作区；最终提交必须用精确 pathspec stage 本轮 tracked 文件，避免漏提替换或误加入历史未跟踪 docs/handoff。

## M3.0 Step 4（Task 10）实施记录

### 背景

Step 3 已把 V2 类型族正名为 `Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration`。Step 4 只处理 M1 临时命名 `PresentationMode`，恢复 spec canonical 名称 `DisplayMode`。本 step 不执行 Step 5，`SelectionOrigin` 与 `SelectionPayload.Source.toSelectionOrigin()` 保持不变；SelectionCapture reader 命名也保持 `SelectionReader` / `AXSelectionSource` / `ClipboardSelectionSource`。

### ToDoList

- [x] 用 `rg -n "\bPresentationMode\b" SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift` 盘点 Swift 精确命中。
- [x] 用 word-boundary `perl` 把 Swift 类型引用、注释、测试断言从 `PresentationMode` 改为 `DisplayMode`。
- [x] 同步测试方法名与 SettingsUI helper 命名：`test_presentationMode_*` -> `test_displayMode_*`，`editablePresentationModes` -> `editableDisplayModes`。
- [x] 手工修正 `OutputBinding.swift` 的历史命名说明，避免 Step 4 后注释仍描述 v1/v2 同名冲突。
- [x] 执行 Step 4 自查 grep、SwiftPM build、targeted tests、full tests、xcodebuild、swiftlint、`git diff --check`。

### 实施结果

- `OutputBinding.primary` 与 `Tool.displayMode` 类型改为 `DisplayMode`，enum raw values 保持 `window` / `bubble` / `replace` / `file` / `silent` / `structured` 不变。
- `ConfigMigratorV1ToV2` 仍从 legacy JSON 的 `displayMode` 字符串解码到 canonical `DisplayMode`，未知值 fallback 到 `.window` 的语义不变。
- `OutputDispatcherProtocol` / `OutputDispatcher` / orchestration mocks 和 fallback tests 改为接收 `DisplayMode`，v0.2 non-window fallback 到 window sink 的行为不变。
- SettingsUI 的展示模式 Picker 仍只暴露 `.window` / `.bubble` / `.replace` 三个可编辑模式，未暴露 `.file` / `.silent` / `.structured`。
- JSON wire shape 保持不变：`Tool.displayMode` 字段名未改，`DisplayMode` raw values 未改。

### Step 4 验证结果

- `rg -n "\bPresentationMode\b" SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift`：0 命中。
- `rg -n "\bSelectionOrigin\b" SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift`：10 行命中，确认 Step 5 未提前执行。
- `rg -n "\bDisplayMode\b" SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift`：33 行命中。
- `cd SliceAIKit && swift build`：通过，最后一次复跑 `Build complete! (4.56s)`。
- Targeted tests：`swift test --filter 'SliceCoreTests.OutputBindingTests|SliceCoreTests.ToolTests|SliceCoreTests.ConfigMigratorV1ToV2Tests|OrchestrationTests.OutputDispatcherTests|OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.PromptExecutorTests|OrchestrationTests.ExecutionEngineTests|OrchestrationTests.ExecutionEventTests'` 通过，104 tests / 0 failures。
- `cd SliceAIKit && swift test --parallel --enable-code-coverage`：通过，569/569 tests，退出码 0。
- `xcodebuild -quiet -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过，退出码 0；仅有 Xcode destination 选择 warning。
- `swiftlint lint --strict`（repo 根目录）：通过，137 files，0 violations / 0 serious；保留既有 `unused_import` analyzer_rules 配置 warning。
- `git diff --check`：通过。
- Step 4 spec review：`APPROVED`，无 blocking finding。
- Step 4 code quality review：`APPROVED`，无 finding；提醒提交时精确 stage tracked 文件，避免混入历史未跟踪 docs/handoff。

### Step 4 残留风险

- Step 4 完成时 `SelectionOrigin` 仍作为下一步命名残留存在；该项已在下方 M3.0 Step 5 处理完成。
- `ConfigMigratorV1ToV2`、`LegacyConfigV1`、`config-v2.json` 仍保留版本边界命名，属于迁移语义，不是 Step 4 残留。

## M3.0 Step 5（Task 11）实施记录

### 背景

Step 4 已把 `PresentationMode` 恢复为 spec canonical `DisplayMode`。Step 5 只处理 M1 临时命名 `SelectionOrigin`，恢复为 spec canonical `SelectionSource`；不修改 `SelectionReader` 读取器协议，不修改 `AXSelectionSource` / `ClipboardSelectionSource` 实现类，也不修改 `SelectionPayload.Source` 内嵌 enum 名称或 JSON/raw values。

### ToDoList

- [x] 用 `rg -n "\bSelectionOrigin\b|\btoSelectionOrigin\b" SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift` 盘点 Swift 精确命中。
- [x] 按 word-boundary 顺序替换 `toSelectionOrigin` -> `toSelectionSource`，再替换 `SelectionOrigin` -> `SelectionSource`。
- [x] 手工复查 `SelectionContentType.swift` 命名说明，明确 `SelectionSource` 是 canonical 来源枚举且与 `SelectionReader` 读取器接口正交。
- [x] 同步测试方法名与注释：`test_toSelectionOrigin_clipboardFallback` -> `test_toSelectionSource_clipboardFallback`，`test_selectionOrigin_rawValues` -> `test_selectionSource_rawValues`。
- [x] 执行静态 grep、SwiftPM build、targeted tests、full coverage tests、xcodebuild、SwiftLint strict、`git diff --check`。

### 实施结果

- `SelectionSnapshot.source` 字段和 init 参数类型从 `SelectionOrigin` 改为 `SelectionSource`。
- `SelectionContentType.swift` 中来源枚举定义从 `SelectionOrigin` 改为 `SelectionSource`，保留 raw values：`accessibility` / `clipboardFallback` / `inputBox`。
- `SelectionPayload.toExecutionSeed(...)` 改为调用 `source.toSelectionSource()`。
- `SelectionPayload.Source` 内嵌 enum 名称保持不变，仅 mapping helper 从 `toSelectionOrigin()` 改为 `toSelectionSource()`，输出类型改为 `SelectionSource`。
- `SelectionSnapshotTests` / `SelectionPayloadTests` 同步 canonical 命名断言，继续覆盖 raw values 稳定性与 clipboard fallback 映射。
- `SelectionReader`、`AXSelectionSource`、`ClipboardSelectionSource` 均保持原名；SelectionCapture 范围未引入 `SelectionSource` 协议/存在类型。

### Step 5 验证结果

- `rg -n "\bSelectionOrigin\b|\btoSelectionOrigin\b" SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift`：0 命中。
- `rg -n "\bSelectionSource\b|\btoSelectionSource\b" SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift`：有命中，覆盖 `SelectionContentType.swift`、`SelectionSnapshot.swift`、`SelectionPayload.swift`、相关 tests，以及既有 `AppDelegate` 注释。
- `rg -n "\bSelectionReader\b" SliceAIKit/Sources SliceAIKit/Tests SliceAIApp --type swift`：仍有命中，确认读取器协议保留。
- `rg -n ":\s*SelectionSource\b|any SelectionSource\b" SliceAIKit/Sources/SelectionCapture SliceAIKit/Tests/SelectionCaptureTests --type swift`：0 命中，确认未把 SelectionCapture reader protocol 改回旧名。
- `cd SliceAIKit && swift build`：通过，`Build complete! (4.58s)`。
- Targeted tests：`swift test --filter 'SliceCoreTests.SelectionSnapshotTests|SliceCoreTests.SelectionPayloadTests|SelectionCaptureTests.SelectionServiceTests'` 通过，17 tests / 0 failures。
- `cd SliceAIKit && swift test --parallel --enable-code-coverage`：通过，569 tests / 0 failures，退出码 0。
- `xcodebuild -quiet -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过，退出码 0；仅有 Xcode destination 选择 warning。
- `swiftlint lint --strict`（repo 根目录）：通过，137 files，0 violations / 0 serious；保留既有 `unused_import` analyzer_rules 配置 warning。
- `git diff --check`：通过。

### Step 5 变动文件

- `SliceAIKit/Sources/SliceCore/SelectionContentType.swift`
- `SliceAIKit/Sources/SliceCore/SelectionPayload.swift`
- `SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift`
- `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/SelectionSnapshotTests.swift`

### Step 5 残留风险

- 本轮只做 canonical rename，不改变 selection 捕获、payload wire shape、raw values 或业务分支；因此未增加运行时日志，避免为了改名引入无意义行为变化。
- `SelectionPayload.Source` 仍是 v1 触发层边界类型，按本轮要求保留内嵌 enum 名称；后续若要彻底移除 v1 语义，需要单独设计迁移边界，不能混入本次 rename。

## M3.2/M3.3/M3.4 自动化验收记录

### 执行边界

- 本轮只执行 CLI 自动化验收，不运行真实调用 LLM provider 的 GUI 流式操作。
- 本轮未访问或修改用户真实 `~/Library/Application Support/SliceAI/` 配置文件。
- 验收开始时执行 `git status --short`，工作区存在既有未跟踪 `docs/Task-detail/codex-loop-phase-0-m3-*.md` 与 `docs/handoffs/...` 文件。按 worker 边界，本轮未触碰这些未跟踪文件。

### M3.4 grep validation

- `grep -rn "\bToolExecutor\b\|\bFileConfigurationStore\b\|\bConfigurationProviding\b\|\bV2Tool\b\|\bV2Provider\b\|\bV2Configuration\b\|\bV2ConfigurationStore\b\|\bDefaultV2Configuration\b\|\bPresentationMode\b\|\bSelectionOrigin\b" SliceAIKit/Sources/ SliceAIKit/Tests/ SliceAIApp/`：输出为空。`grep` 在 0 命中时返回 exit 1，符合本项预期。

### M3.2 Step 6 targeted tests

- `(cd SliceAIKit && swift test --filter "OrchestrationTests.InvocationGateTests")`：8 tests / 0 failures，exit 0。
- `(cd SliceAIKit && swift test --filter "OrchestrationTests.ExecutionStreamOrderingTests")`：4 tests / 0 failures，exit 0。
- `(cd SliceAIKit && swift test --filter "OrchestrationTests.OutputDispatcherFallbackTests")`：6 tests / 0 failures，exit 0。
- `(cd SliceAIKit && swift test --filter "OrchestrationTests.SingleWriterContractTests")`：1 test / 0 failures，exit 0。
- `(cd SliceAIKit && swift test --filter "SliceCoreTests.SelectionPayloadToExecutionSeedTests")`：exit 0，但 SwiftPM 输出 `warning: No matching test cases were run`，实际 0 tests。当前测试列表中对应真实用例为 `SliceCoreTests.SelectionPayloadTests/test_toExecutionSeed_mapsFields`。
- 追加核验 `(cd SliceAIKit && swift test --filter "SliceCoreTests.SelectionPayloadTests/test_toExecutionSeed_mapsFields")`：1 test / 0 failures，exit 0。
- 已同步修正 implementation plan 的 Task 12 Step 6，后续直接运行真实 XCTest filter，避免 0-test 假阳性。

### M3.3 Step 5 targeted tests

- `(cd SliceAIKit && swift test --filter "SliceCoreTests.ConfigurationStoreTests")`：15 tests / 0 failures，exit 0。

### 4 关 gate

- `(cd SliceAIKit && swift build)`：Build complete，exit 0。
- `(cd SliceAIKit && swift test --parallel --enable-code-coverage)`：测试进度完成到 569/569，exit 0。
- `xcodebuild -quiet -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：exit 0；仅输出 Xcode destination 选择 warning。
- `swiftlint lint --strict`：137 files，0 violations / 0 serious，exit 0；保留既有 `unused_import` analyzer_rules 配置 warning。

### 手工未覆盖项

- M3.2：Safari 划词真实触发链、取消流式输出、single-flight stress 未执行；`⌥Space` 命令面板与 TextEdit 浮条真实触发已在 2026-05-04 安全子集中通过。
- M3.3：启动场景 A-D 涉及真实 app 与真实 config 文件，未执行，避免改动用户真实配置状态。
- 真实 LLM provider GUI 流式调用已在 2026-05-04 通过 DeepSeek 安全子集覆盖；破坏性配置 / 启动场景仍未执行。

## M3.5 安全子集手工回归记录

### 2026-05-04

执行环境：用户已启动 Debug `SliceAI.app`，并在 Settings → Providers 手工保存 DeepSeek 兼容 Provider；API Key 未写入文档、命令或仓库文件。

已验证通过：

- Provider 配置：Settings → Providers 中新增 `deepSeek`，Base URL 为 `https://api.deepseek.com/v1`，默认模型为 `deepseek-v4-flash`；用户反馈“测试连接成功”。
- Tool 配置即时生效：Settings → Tools → `中译英` 的 Provider 从 `oneApi` 切到 `deepSeek`；`config-v2.json` 中 `translate.kind.prompt.provider.fixed.providerId = provider-1777873129`，`modelId = null`，旧 `config.json` 未出现 `deepSeek` / `api.deepseek` / `provider-1777873129` 字样。
- `⌥Space` 命令面板：在 TextEdit 选中 `Hello SliceAI regression test.` 后，通过系统事件触发 `option+space`，命令面板正确展示选中文本与 6 个工具；选择 `中译英` 后 ResultPanel 正常显示结果。
- TextEdit 浮条路径：鼠标拖拽选中文本后浮条显示 `英译中` / `中译英` / `语法检查` / `解释` / More；点击 `中译英` 后 ResultPanel 正常显示结果。
- 真实 LLM 调用链：三次调用均写入 `audit.jsonl` 与 `cost.sqlite`，记录均为 `tool_id = translate`、`provider_id = provider-1777873129`、`model = deepseek-v4-flash`、`input_tokens = 46`、`output_tokens = 7`、`usd = 0.000053`。
- ResultPanel 成功态操作子集：Copy 写入剪贴板内容 `Hello SliceAI regression test.`；Pin / Unpin 图标和 Help 文案正确切换；Regenerate 触发第二条独立 invocation 且结果区域重置后重新显示；Close 点击后结果窗关闭。

未标记全过的原因：

- Step 1 仍未在 Safari 中验证，当前只覆盖 TextEdit 浮条。
- Step 3 的 Retry / Open Settings 未覆盖；Close 点击后 Computer Use 返回 `noWindowsAvailable`，视觉上符合“窗口已关闭”，但工具层返回值需后续复核，不作为失败。
- Step 4 / 5 / 7 / 8 / 10 / 11 / 12 涉及关闭 AX、清空或删除配置、切旧 build、移动 app support、修改目录权限等本地破坏性或权限类操作，需在 action-time 获得用户确认后再执行。
- Step 9 自定义变量编辑尚未执行；当前仅验证了既有 `language = English` 变量参与 prompt。
- Step 13 provider switch 清空 modelId 只覆盖了“切换后 modelId 为 null”的结果，未覆盖“先设置旧 modelId 再切换 provider”的完整场景。
