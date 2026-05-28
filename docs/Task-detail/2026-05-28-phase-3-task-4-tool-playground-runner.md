# 2026-05-28 · Phase 3 Task 4 Tool Playground Runner

## 背景

用户要求作为 Phase 3 ToolEditor v2 + Prompt Playground MVP 的实现 worker，执行 Task 4：新增 Tool Playground Runner，并在 AppContainer 中创建 Playground 专用 `ExecutionEngine`，让 Settings 后续 UI 能用未保存 Tool 草稿试跑。

本任务承接 Task 1 的 run policy / telemetry、Task 2 的 `PlaygroundOutputDispatcher` 和 Task 3 的 Agent MCP run policy；只实现 runner 与最小 App wiring，不创建 `ToolPlaygroundView`、不创建 `ToolEditorV2View`、不做 UI 集成。

## 任务目标

- 新增 `ToolPlaygroundRunRequest`、`ToolPlaygroundRunning` 和默认 `ToolPlaygroundRunner`。
- Playground runner 在进入 `ExecutionEngine` 前校验 Tool 草稿，非法配置直接产出失败事件，避免调用 LLM / MCP。
- Playground runner 构造 `.playground` trigger、dry-run seed 和 `.playground(allowMCPToolCalls:)` run policy。
- `AppContainer` 创建第二个专用 `ExecutionEngine`，复用生产上下文、权限、provider、prompt、MCP、skill、cost 和 audit 依赖，只替换 output 为 `PlaygroundOutputDispatcher()`，并禁用 side effect executor。
- 为修正 plan 前置依赖，提前给 `SettingsViewModel` 增加最小 `playgroundRunner` 注入点；不提前展开 Task 6 / Task 7 UI。

## ToDoList

- [x] Step 1：扩展 `ExecutionEngineTests` 本地 helper，写 Playground runner smoke 测试。
- [x] Step 2：运行指定 focused test，确认当前缺口红灯。
- [x] Step 3：新增 `ToolPlaygroundRunner.swift`。
- [x] Step 4：在 `AppContainer` 中接线 Playground 专用 engine。
- [x] Step 4a：若 `SettingsViewModel` 尚无 runner 属性，做最小属性 / initializer 适配。
- [x] Step 5：运行 focused tests 与 App Debug build。
- [x] Step 6：更新任务文档并提交 `feat: add tool playground runner`。

## 设计边界

- KISS：runner 只负责请求到 `ExecutionSeed` 的转换和 Tool 校验，不复制 prompt / agent 执行逻辑。
- 单一入口：Playground 继续调用 `ExecutionEngine.execute(tool:seed:)`，不另建执行链。
- 安全：所有 side effects 仍由 dry-run 跳过；Agent MCP 是否允许由 run policy 控制。
- 输出隔离：Playground 使用 `PlaygroundOutputDispatcher`，不触发生产 ResultPanel、Bubble、文件写入、替换或剪贴板输出。
- 前置依赖偏差：Task 4 需要把 runner 注入 Settings，但原 plan 把 `SettingsViewModel.playgroundRunner` 放到 Task 7。为保证 App build 真实通过，本任务只提前加入该属性和依赖声明，不创建 UI。

## 实施记录

1. `ExecutionEngineTests` 的 `makeStubTool` 新增 `displayMode` 参数，让测试能构造不同主输出模式；`makeEngine` 新增 `outputDispatcher` 可选参数，同时保留旧 `output` 返回字段，避免影响既有 `bundle.output` 断言。
2. 新增 runner smoke 测试：Playground dry-run 使用 `PlaygroundOutputDispatcher` 时，report 标记 `.playground` / `.dryRun`，终态为 `.dryRunCompleted`，并跳过 `copyToClipboard` side effect。
3. 新增 runner 防御测试：`ToolPlaygroundRunner` 在非法 `outputBinding.primary != displayMode` 草稿进入 engine 前返回 `.failed(.configuration(.validationFailed))`，不产生 `.llmChunk`。
4. 新增 `ToolPlaygroundRunRequest`、`ToolPlaygroundRunning` 和 `ToolPlaygroundRunner`。runner 会先调用 `Tool.validate()`，再构造 `.inputBox` selection、`com.sliceai.playground` app snapshot、`.playground` trigger、`isDryRun: true` 和 `.playground(allowMCPToolCalls:)` run policy。
5. `ToolPlaygroundRunner` 只记录 tool id、selection 长度、MCP 开关和脱敏错误，不记录用户 selection 原文。
6. `AppContainer` 在生产 engine 之外创建 Playground 专用 engine：复用同一套 `ContextProviderRegistry`、`PermissionBroker`、`ProviderResolver`、`PromptExecutor`、`AgentExecutor`、MCP client、SkillRegistry、CostAccounting 和 AuditLog；只替换 output 为 `PlaygroundOutputDispatcher()`，并把 `sideEffectExecutor` 设为 nil。
7. `RuntimeDependencies` 增加 `playgroundRunner`，`bootstrap()` 在 `v2Runtime` 创建后赋值给 `ui.settingsViewModel.playgroundRunner`。
8. 为修正 plan 的前置依赖，`SettingsViewModel` 提前新增最小 `playgroundRunner` 属性和 initializer 参数；`SettingsUI` target 增加 `Orchestration` 依赖。本任务未创建 `ToolPlaygroundView`、`ToolEditorV2View`，未做 UI 集成。

## 实现结果

已完成 Task 4 范围。Settings 后续 UI 可以通过注入的 `ToolPlaygroundRunning` 对未保存 Tool 草稿进行 dry-run 试跑；非法草稿会在 runner 层失败，不会进入 LLM / MCP 执行链。Playground 专用 engine 与生产执行链共享权限、上下文、provider、MCP、skill、成本和审计依赖，但输出和 side effects 与生产 UI / 系统副作用隔离。

## 变动文件清单

- `SliceAIKit/Sources/Orchestration/Playground/ToolPlaygroundRunner.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- `SliceAIApp/AppContainer.swift`
- `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`
- `SliceAIKit/Package.swift`
- `docs/Module/Orchestration.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-28-phase-3-task-4-tool-playground-runner.md`

## 测试记录

- Red cache issue：首次运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'OrchestrationTests.ExecutionEngineTests/test_playgroundRun_marksReportAndSkipsSideEffects|OrchestrationTests.ExecutionEngineTests/test_toolPlaygroundRunner_rejectsInvalidToolBeforeEngineRun'` 被旧 `.build` 中 Swift 6.2.3 产物阻塞，错误为 Swift 6.3.2 无法导入旧 `LLMProviders.swiftmodule`。
- Red：改用 `--scratch-path /tmp/sliceai-task4-red-20260528-02` 后，focused test 编译失败，符合预期；缺少 `ToolPlaygroundRunner` 和 `ToolPlaygroundRunRequest`。
- Green：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task4-green-20260528-01 --filter 'OrchestrationTests.ExecutionEngineTests/test_playgroundRun_marksReportAndSkipsSideEffects|OrchestrationTests.ExecutionEngineTests/test_toolPlaygroundRunner_rejectsInvalidToolBeforeEngineRun'` 通过，2 tests，0 failures。
- Focused：日志行调整后重跑 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task4-focused-20260528-02 --filter 'OrchestrationTests.ExecutionEngineTests|OrchestrationTests.PlaygroundOutputDispatcherTests'` 通过，26 tests，0 failures。
- App build：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过，`BUILD SUCCEEDED`。
- Whitespace：`git diff --check` 通过。
- SwiftLint：尝试运行 `swiftlint lint --strict`，本机当前 shell 返回 `command not found: swiftlint`，未完成 lint 验证。
