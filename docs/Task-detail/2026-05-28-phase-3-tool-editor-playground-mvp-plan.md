# 2026-05-28 · Phase 3 ToolEditor v2 + Prompt Playground MVP Plan

## 背景

用户要求使用 `writing-plans` 继续为 Phase 3 首个冻结切片生成 implementation plan。前置 spec `docs/superpowers/specs/2026-05-28-phase-3-tool-editor-playground-mvp.md` 已完成 Codex review 修订，当前任务只产出实现计划，不写业务代码。

## 任务目标

生成一份可由后续 Codex / subagent 逐任务执行的 Phase 3 ToolEditor v2 + Prompt Playground MVP implementation plan。计划必须覆盖 run policy、telemetry 兼容、Playground preview output、MCP 显式确认、ToolEditor draft 保存语义、Settings UI 集成和最终验证。

## ToDoList

- [x] 读取 `writing-plans` skill。
- [x] 读取 README、master todolist、Task_history 和 Phase 3 spec。
- [x] 读取 SettingsUI / ExecutionEngine / AgentExecutor / telemetry / output 关键源码接口。
- [x] 生成 implementation plan。
- [x] 更新 Task_history 和 master todolist。
- [x] 使用 `claude-review-loop` 对 plan 做 3 轮只读评审并拿到 Round 3 approve。
- [x] 按 Codex plan review 修复实现计划中的安全 / 校验 / UI 展示缺口。
- [x] 用户确认执行方式并完成 Task 1-7 实现。
- [x] Task 8 更新模块文档和项目状态文档。
- [x] Task 8 运行 final gate 并记录结果。
- [x] Task 8 准备收尾 commit。

## 实施内容

计划文件：

- `docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md`

核心拆分：

1. Run policy 和 telemetry foundation：新增 `ExecutionRunPolicy`，标记 Playground source，补 CostRecord source 迁移。
2. Playground output dispatcher：所有 DisplayMode 进入 preview，不触发生产 UI 或文件 / 剪贴板 / AX 副作用。
3. Agent MCP run policy：默认禁用 Playground MCP；用户显式打开后才进入 allowlist + PermissionBroker。
4. ToolEditor draft state：编辑草稿不直接写 `Configuration.tools`，Save 时校验并提交。
5. Playground state reducer 和 UI：右侧输入、Run / Cancel / Clear、tool-call lifecycle、DisplayMode preview。
6. AppContainer wiring：专用 Playground `ExecutionEngine` 复用真实执行链。
7. 文档和 final gate。

## 2026-05-28 Plan Review 修复

根据 Codex 对 implementation plan 的复审，已在计划中补齐以下内容：

1. Playground Runner 在进入 `ExecutionEngine` 前先调用 `Tool.validate()`，非法 draft 只产出 `.failed` 事件，不调用 LLM / MCP。
2. ToolEditor v2 的 Playground Run 与 Save 共用 `ToolDraftValidator`，Run 前会拦截 disabled skill、无效 Tool、重复 id 和热键问题。
3. `ToolDraftValidator` 改为复用 `HotkeyBindingValidator`，覆盖命令面板冲突、其它工具冲突、非法热键和旧 `Tool.hotkey` fallback。
4. Agent MCP disabled 模式在 `AgentToolCallRunState.recordExecution(...)` 前返回受控拒绝，避免禁用状态消耗 tool-call budget / duplicate fingerprint。
5. Playground state / view 补充 prompt preview、权限提示、错误消息、tokens / cost / flags report summary 展示。
6. Save 草稿时如果 hotkeys 发生变化，计划要求调用 `SettingsViewModel.saveHotkeys()` 触发 Carbon 热键重新注册。

## 验证

Plan 生成阶段只修改文档，验证范围：

- `git diff --check`：通过，无输出。
- `rg -n "[ \t]+$" ...`：通过，未发现新增文档行尾空白。
- `rg -n "<<<<<<<|>>>>>>>|=======" ...`：通过，未发现冲突标记。
- `claude-review-loop`：Round 1 `needs_attention`，Round 2 `needs_attention`，Round 3 `approve` 且 `findings: []`。Loop log: `docs/Task-detail/claude-loop-phase3-tool-editor-playground-plan.md`。
- Codex plan review fixes：已更新 plan 文档；尚未运行 Swift / Xcode，因为本轮仍只修改文档和计划片段。
- Swift / Xcode 测试未运行，因为本任务没有改生产代码，测试文件仅在计划中描述，尚未创建。

### 2026-05-28 Task 8 Final Gate

Task 8 是 Phase 3 ToolEditor v2 + Prompt Playground MVP 的文档收尾和 final gate；Task 1-7 已完成实现并通过两轮 review。本节记录最终验证，不额外创建无关 task detail。

- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task8-full-tests`：通过。执行 882 tests，1 skipped，0 failures；构建阶段出现既有 `MCPServerStoreTests.swift:196` unused-result warning，不影响退出码。
- `swiftlint lint --strict`：未运行成功。失败原因为本机环境缺失，`zsh:1: command not found: swiftlint`；按任务约束未安装工具。
- `git diff --check`：通过，无输出。
- `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过，输出 `** BUILD SUCCEEDED **`；Xcode 选择多个 matching destinations 中的第一个 My Mac，为非阻塞 warning。

## 变动文件清单

- `docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md`
- `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`
- `docs/Task_history.md`
- `docs/v2-refactor-master-todolist.md`

Task 8 追加变动：

- `README.md`
- `AGENTS.md`
- `docs/Module/Orchestration.md`
- `docs/Module/SettingsUI.md`
- `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`
- `docs/Task_history.md`
- `docs/v2-refactor-master-todolist.md`

## 下一步

Task 8 完成后，下一步做 Phase 3 Playground 真实 App smoke，确认后再评估样本管理 / A-B / 原生 provider 的后续切片。样本持久化、A/B 对比、版本历史、原生 Anthropic / Gemini / Ollama、Memory 和 Cost Panel 仍是技术债务 / 后续切片，不属于本次 MVP 收尾。

## 2026-05-28 Review Fix

### 背景

最终 code review 发现 4 个问题：Playground preflight permission gate 错误复用 side-effect dry-run，`ExecutionEvent.promptRendered` 没有生产者，Playground UI 缺少 app / window / URL 输入入口，以及 Cancel 后 UI 可能永久停在 cancelling。

### ToDoList

- [x] 先写 Playground preflight、Prompt / Agent `promptRendered`、Cancel 终态回归测试。
- [x] 运行 focused tests 确认红灯。
- [x] 修复 Playground preflight：只 gate `fromContexts ∪ fromBuiltins`，并强制 `isDryRun = false`。
- [x] 修复 Prompt / Agent prompt preview 生产与 ExecutionEngine 转发。
- [x] 修复 Playground UI：补 App / Window / URL 输入、状态展示和 cancelled 终态。
- [x] 更新 Orchestration / SettingsUI 模块文档和 Task_history。
- [x] 运行 focused / full tests 与 `git diff --check`。

### 修改逻辑

- `ExecutionEngine` 新增 preflight helper。生产路径仍 gate `effective.union`，生产 dry-run 仍保留 `.wouldRequireConsent` 语义；Playground 只对 LLM 前真实使用的 context / builtin 权限做真实 gate，side effects 继续在 finish 阶段 dry-run，MCP tool call 继续由 `AgentExecutor` 的 per-call gate 控制。
- `PromptExecutor` 在渲染 messages 后、读取 Keychain 和调用 LLM 前 yield `.promptRendered`；`ExecutionEngine.runPromptStream` 转发为 `ExecutionEvent.promptRendered`。
- `AgentExecutor` 在构造首轮 messages 后、第一轮 LLM 前 yield `.promptRendered`。
- 新增 `PromptPreviewRenderer`，把 `[ChatMessage]` 渲染为 `role: content` 多行预览，并通过 `Redaction.scrub` 脱敏和截断。
- `ToolPlaygroundView` 增加 App / Window / URL 输入字段，Header 展示 run status；Cancel 调用后从 `.cancelling` 落到 `.cancelled`。

### 变动文件清单

- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`
- `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
- `SliceAIKit/Sources/Orchestration/Internal/PromptPreviewRenderer.swift`
- `SliceAIKit/Sources/SettingsUI/ToolPlaygroundState.swift`
- `SliceAIKit/Sources/SettingsUI/ToolPlaygroundView.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/PromptExecutorTests.swift`
- `SliceAIKit/Tests/SettingsUITests/ToolPlaygroundStateTests.swift`
- `docs/Module/Orchestration.md`
- `docs/Module/SettingsUI.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`

### TDD 红绿过程

- Red：新增测试后运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-review-fix-red-tests --filter 'OrchestrationTests.ExecutionEngineTests|OrchestrationTests.AgentExecutorTests|SettingsUITests.ToolPlaygroundStateTests|SliceCoreTests.ExecutionRunPolicyTests'`，按预期失败。失败点为 `ToolPlaygroundState.markCancelled()` / `.cancelled` 缺失。
- Green：实现最小修复后，focused suite 首次暴露旧测试固定事件下标问题；更新断言后通过 79 tests / 0 failures。
- PromptExecutor 回归：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-review-fix-prompt-tests --filter OrchestrationTests.PromptExecutorTests` 首次暴露新增 `.promptRendered` 后旧精确序列断言失效；更新断言后通过 21 tests / 0 failures。
- Full：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-review-fix-full-tests` 通过，886 tests，1 skipped，0 failures；构建阶段仍有既有 `MCPServerStoreTests.swift:196` unused-result warning。
- `git diff --check`：通过，无输出。
- `command -v swiftlint || true`：无输出；本机 `swiftlint` 不在 PATH，本轮未运行 SwiftLint。

## 2026-05-28 Second Review Fix

### 背景

第二轮 code quality review 发现两个小问题：`ExecutionEngine.runPermissionGate` 在非 dry-run 收到异常的 `.wouldRequireConsent` 时会继续进入 ContextCollector / LLM，未 fail closed；`PromptExecutor` 的 public doc 仍描述旧的 `[.chunk]* + .completed` 流契约。

### ToDoList

- [x] 先补 fail-closed 回归测试，并运行 focused filter 确认红灯。
- [x] 修改 `runPermissionGate`：dry-run 保留占位事件并继续，非 dry-run fail closed。
- [x] 更新 `PromptExecutor.run` 与 `PromptStreamElement.completed` public doc。
- [x] 运行 ExecutionEngine / PromptExecutor focused tests 与 `git diff --check`。
- [x] 提交本轮修复，不推送远端。

### 修改逻辑

- 新增 `ExecutionEngineTests.test_execute_wouldRequireConsentNonDryRun_failsClosedBeforeContextAndLLM`，让 mock broker 在非 dry-run 返回 `.wouldRequireConsent(.clipboard)`，并断言不会产出 `.permissionWouldBeRequested`、不会进入 PromptExecutor / LLM、ProviderResolver 不被调用，最终失败为 `.toolPermission(.notGranted(.clipboard))`。
- `ExecutionEngine.runPermissionGate` 对 `.wouldRequireConsent` 增加 `isDryRun` 分支：dry-run 继续产出 `.permissionWouldBeRequested` 并放行；非 dry-run 视为 broker 契约异常，调用 `finishFailure(error: .toolPermission(.notGranted(permission: permission)), effective: effective.union, context: context)` 后返回 `false`。
- `PromptExecutor` public doc 更新为 `.promptRendered? -> [.chunk]* -> .completed`，明确 prompt preview 在 LLM 前产出，`.completed` 仍为最后一个元素。

### 变动文件清单

- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`
- `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`

### TDD 红绿过程

- Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-review-fix2-tests --filter 'OrchestrationTests.ExecutionEngineTests'` 失败，新增测试确认当前实现会读取 clipboard context、产出 `.permissionWouldBeRequested` / `.promptRendered` / `.llmChunk`，并调用 ProviderResolver / LLM。
- Green：实现 fail-closed 后，重跑同一 ExecutionEngine filter 通过，26 tests / 0 failures。
- PromptExecutor focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-review-fix2-prompt-tests --filter 'OrchestrationTests.PromptExecutorTests'` 通过，21 tests / 0 failures。
- `git diff --check`：通过，无输出。

## 2026-05-30 Real App Smoke

### 背景

handoff 第 3 步要求做 Phase 3 Playground 真实 App smoke。在一台装有 SwiftLint 的机器上先补齐并通过 lint gate（见 `2026-05-29-phase-3-swiftlint-gate-fix.md`，commit `fc61869`），随后用 `xcodebuild` 构建 Debug app 并 `open` 启动，由用户在 GUI 中逐项手动验证。

### 环境

- Debug app（DerivedData Debug 产物），用户本机真实 provider + Keychain API Key。
- 本机 `config-v2.json` 首次启动时从 `schemaVersion 3` 迁移到 `4`，自动补入内置 `english-tutor` 工具——属预期迁移行为，非 Playground 污染。
- smoke 前抓取 config-v2.json 基线（tool ids + sha256），用于核对“编辑不保存不污染”。

### 结果（8 / 8 全部通过）

1. ToolEditor v2 左右双栏（编辑器 + Playground）正常展示。✓
2. 编辑已有 Tool 草稿、不点 Save 切走，弹 dirty guard 提示，正式配置不变。✓
3. Add Prompt / Add Agent 进入 creating 草稿，未 Save 前不写入 `configuration.tools`，Revert 丢弃。✓
4. Prompt Tool Playground 真实调用 LLM，streaming 输出进入右侧 preview，不弹生产 ResultPanel。✓
5. Agent Tool MCP 默认禁用生效：未勾选“允许本次运行调用 MCP tools”时不会真实执行 MCP tool call（用户已确认通过）。✓
6. side effects dry-run：`.replace` / `.bubble` / `.tts` 等只显示 `would …` 摘要，不真实替换前台选区、不弹真实气泡、不发声。✓
7. Run 过程中 Cancel 后状态落到 `cancelled`，不卡在 `cancelling`。✓
8. 点击 Save 后才写回 `config-v2.json`。✓

### 结论

Phase 3 ToolEditor v2 + Prompt Playground MVP 的 spec §16 Definition Of Done 已在真实 App 上验证通过；自动化 gate（SwiftPM 887 tests / SwiftLint strict / App build / `git diff --check`）此前已全绿。下一步交由用户选择集成路径（开 PR / 合 main / 保持分支继续下一个 Phase 3 切片）。
