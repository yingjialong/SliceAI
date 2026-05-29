# 2026-05-29 · Phase 3 Plan Compliance Audit

## 背景

用户要求逐项检查 Phase 3 ToolEditor v2 + Prompt Playground MVP implementation 是否与
`docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md` 一致；按 Task 1-8 逐项核对，发现不一致则修复，直到全部检查完毕。

## 范围

- 核对 plan 中 Task 1-8 的源码、测试、文档和 final gate 要求。
- 修复 implementation 与 plan 的实际不一致。
- 同步 plan checklist / 项目文档中因后续 review-fix 产生的状态漂移。

## ToDo

- [x] 提取 plan Task 1-8 的文件、行为和测试要求。
- [x] Task 1：Run Policy And Telemetry Foundation 一致性核对。
- [x] Task 2：Playground Output Dispatcher 一致性核对。
- [x] Task 3：Agent MCP Run Policy 一致性核对。
- [x] Task 4：Tool Playground Runner 一致性核对。
- [x] Task 5：ToolEditor Draft State 一致性核对。
- [x] Task 6：Playground State Reducer 一致性核对。
- [x] Task 7：Settings UI Integration 一致性核对。
- [x] Task 8：Documentation And Final Gate 一致性核对。
- [x] 修复发现的不一致并补充验证。
- [x] 运行最终验证并记录结果。

## 审计记录

### 逐 Task 核对

| Task | plan 要求 | 当前证据 | 结论 |
| --- | --- | --- | --- |
| Task 1 | 新增 `ExecutionRunPolicy`、`.playground` source、telemetry source 字段和 ExecutionEngine policy 传递 | `ExecutionRunPolicy.swift`、`ExecutionSeed.effectiveRunPolicy`、`TriggerSource.playground`、`FlowContext.runPolicy`、`InvocationFlag.playground`、`CostRecord.source`、`CostAccounting` source 列迁移、`ExecutionEngine+Steps` report / cost / permission dry-run 逻辑均已落地；focused tests 通过 | 一致 |
| Task 2 | 新增 Playground preview output dispatcher，所有 DisplayMode 不触发生产 UI / 文件 / 剪贴板 / 替换副作用 | `PlaygroundOutputDispatcher.swift` 只记录 begin / chunk / finish / fail snapshot；`PlaygroundOutputDispatcherTests` 覆盖 window、file、replace、bubble、structured、silent | 一致 |
| Task 3 | Agent MCP 默认禁用；显式允许后才走 allowlist + PermissionBroker；disabled MCP 不消耗 tool budget | `AgentExecutor.run(... runPolicy:)`、`AgentExecutor+ToolCalls` disabled-mode guard 和 non-dry PermissionBroker gate 已实现；`AgentExecutorTests` 覆盖默认禁用、预算不消耗和显式允许路径 | 一致 |
| Task 4 | 新增 `ToolPlaygroundRunner`，先校验 Tool 草稿，再用专用 Playground engine 复用真实执行链 | `ToolPlaygroundRunner.swift` 在进入 engine 前调用 `Tool.validate()`；`AppContainer` 注入专用 engine，复用生产 context / permission / provider / MCP / skill / cost / audit，替换 preview output 并禁用 side-effect executor；runner smoke tests 通过 | 一致 |
| Task 5 | ToolEditor draft session 和保存前校验，Save 前不污染正式配置 | `ToolEditorDraftState.swift` 提供 draft/session/validator；测试覆盖未保存不变更原配置、重复 id、disabled/unknown skills、热键冲突、command palette disabled、Save/Run 共用校验等 | 一致 |
| Task 6 | SettingsUI state reducer 消费 `ExecutionEvent`，展示 streaming、prompt、权限、tool-call、DisplayMode preview、report 和错误 | `ToolPlaygroundState.swift` 已实现 reducer；`SettingsUI` / `SettingsUITests` 已依赖 `Orchestration`；`ToolPlaygroundStateTests` 覆盖 streaming、structured/file preview、权限提示、结束/失败、取消和 validation failure | 一致 |
| Task 7 | Settings Tools 页面接入 ToolEditor v2 + Playground，支持 draft Save/Revert、Run/Cancel/Clear、MCP 显式开关和 App/Window/URL 输入 | `ToolEditorV2View.swift`、`ToolPlaygroundView.swift`、`ToolsSettingsPage.swift`、`ToolsSettingsPage+Actions.swift` 已替代直接 production binding；`SettingsScene` 调整为 `980×620`；review-fix 已补 App/Window/URL 输入、run status 和 cancelled 终态 | 一致 |
| Task 8 | 更新模块 / 项目状态文档并运行 final gate | `README.md`、`AGENTS.md`、`docs/v2-refactor-master-todolist.md`、`docs/Module/Orchestration.md`、`docs/Module/SettingsUI.md` 和 Task detail 均已记录 MVP、review hardening、non-goals 和后续技术债；SwiftPM / Xcode / diff gate 已有记录，SwiftLint 因本机缺失无法运行 | 一致，含环境例外 |

### 发现并修复的不一致

1. `docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md` 的 Task 1-8 步骤仍全部停留在 `- [ ]`，但实现 commit、Task_history、测试和模块文档均显示这些步骤已完成。本次已把 52 个步骤同步为 `- [x]`。
2. plan 的 final gate 原文只写了 “SwiftLint reports 0 violations”，但当前实施机器没有 `swiftlint`。本次在 plan 中补充环境例外说明，避免后续审计误判为实现遗漏；仍保留安装了 SwiftLint 的环境应跑 strict lint 的要求。

### 技术债务确认

- ToolEditor v2 小宽度响应式布局未做，已记录在 `docs/v2-refactor-master-todolist.md` 和 `docs/Module/SettingsUI.md`。
- 样本持久化、expected output 管理、A/B 双栏对比、版本历史、原生 Anthropic / Gemini / Ollama provider、Memory、Cost Panel、scripts execution、marketplace、pipeline executor 均仍是后续切片 / 技术债，不属于本次 MVP。

### 当前验证

- Focused compliance tests：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-plan-audit-tests --filter 'SliceCoreTests.ExecutionRunPolicyTests|SliceCoreTests.ExecutionSeedTests|SliceCoreTests.TriggerSourceTests|OrchestrationTests.InvocationReportTests|OrchestrationTests.CostAccountingTests|OrchestrationTests.PlaygroundOutputDispatcherTests|OrchestrationTests.AgentExecutorTests|OrchestrationTests.ExecutionEngineTests|SettingsUITests.ToolEditorDraftStateTests|SettingsUITests.ToolPlaygroundStateTests|SettingsUITests.ToolEditorSkillsBindingTests|SettingsUITests.ToolEditorAgentAllowlistCodecTests'`，136 tests / 0 failures。
- `git diff --check`：通过，无输出。
- `swiftlint lint --strict`：未运行成功，`zsh:1: command not found: swiftlint`；本机仍缺少 SwiftLint。
- SwiftPM full tests：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-plan-audit-full-tests`，887 tests / 1 skipped / 0 failures。
- App Debug build：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`，`** BUILD SUCCEEDED **`。
