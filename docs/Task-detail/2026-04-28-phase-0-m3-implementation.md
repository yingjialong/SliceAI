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
- [ ] M3.1.E：冒烟验证（自动化部分完成；手工 GUI 触发链 / 启动失败弹窗待人工确认）。
- [ ] M3.0 Step 1：caller 切换 + ExecutionEventConsumer + SettingsUI binding + tests。
- [ ] M3.0 Step 2：删除 v1 类型族 + SelectionReader + LLMProviderFactory 升级。
- [ ] M3.0 Step 3：V2* rename 回 spec 正名。
- [ ] M3.0 Step 4：PresentationMode → DisplayMode。
- [ ] M3.0 Step 5：SelectionOrigin → SelectionSource。
- [ ] M3.2/M3.3/M3.4：触发链、配置启动场景、grep validation 验收。
- [ ] M3.5：13 项手工回归。
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
