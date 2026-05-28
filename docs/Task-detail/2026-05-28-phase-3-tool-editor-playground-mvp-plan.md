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
- [ ] 用户确认执行方式。

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

## 验证

本任务只修改文档，验证范围：

- `git diff --check`：通过，无输出。
- `rg -n "[ \t]+$" ...`：通过，未发现新增文档行尾空白。
- `rg -n "<<<<<<<|>>>>>>>|=======" ...`：通过，未发现冲突标记。
- `claude-review-loop`：Round 1 `needs_attention`，Round 2 `needs_attention`，Round 3 `approve` 且 `findings: []`。Loop log: `docs/Task-detail/claude-loop-phase3-tool-editor-playground-plan.md`。
- Swift / Xcode 测试未运行，因为本任务没有改生产代码，测试文件仅在计划中描述，尚未创建。

## 变动文件清单

- `docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md`
- `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`
- `docs/Task_history.md`
- `docs/v2-refactor-master-todolist.md`

## 下一步

用户选择执行方式：

1. Subagent-Driven：按 plan 每个 task 一个新 subagent，完成后 review。
2. Inline Execution：在当前会话使用 executing-plans 顺序执行。
