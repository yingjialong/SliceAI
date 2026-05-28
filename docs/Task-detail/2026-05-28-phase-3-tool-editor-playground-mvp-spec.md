# 2026-05-28 · Phase 3 ToolEditor v2 + Prompt Playground MVP Spec

## 背景

用户已确认跳过 Phase 2 release，不打 `v0.4.0` tag，不构建或发布 DMG，直接进入 Phase 3。Phase 3 roadmap 仍是 Directional outline，不能直接进入实现；本任务负责先冻结首个可实施切片的 spec。

## 任务目标

为 Phase 3 首个 MVP 产出完整规格：ToolEditor v2 + Prompt Playground MVP。该 MVP 聚焦未保存草稿试跑、Prompt / Agent Tool 覆盖、真实 LLM、权限闭环下真实 MCP、side effects dry-run、右侧 Playground 预览，以及技术债务登记。

## 范围

包含：

- 冻结首个 MVP spec。
- 明确 MVP 包含 / 排除项。
- 明确 UI 信息架构、运行策略、权限安全、错误处理、测试策略。
- 记录后续 Phase 3 技术债务。

不包含：

- 业务代码实现。
- Phase 3 implementation plan。
- `v0.4.0` tag、DMG、release。
- 原生 Anthropic / Gemini / Ollama、Memory、Cost Panel、A/B、版本历史、样本持久化。

## ToDoList

- [x] 阅读 handoff、README、AGENTS、CLAUDE、master todolist、Task_history、roadmap §4.5 和 Phase 2 completion 文档。
- [x] 通过 brainstorming 收敛 MVP 范围。
- [x] 确认采用 ToolEditor 左编辑 + 右 Playground 布局。
- [x] 确认支持未保存草稿试跑。
- [x] 确认 Playground 覆盖 Prompt Tool 和 Agent Tool。
- [x] 确认 Agent Playground 允许权限闭环下真实 MCP tool call。
- [x] 确认 side effects 默认 dry-run。
- [x] 确认样本不持久化。
- [x] 确认不新增持久化模型。
- [x] 写入完整 spec。
- [ ] 用户 review spec。
- [ ] 用户确认后进入 implementation plan。

## 当前实施方案

Spec 文件：

- `docs/superpowers/specs/2026-05-28-phase-3-tool-editor-playground-mvp.md`

核心结论：

1. MVP 不冻结完整 Phase 3，只冻结 ToolEditor v2 + Prompt Playground。
2. Playground 不创建第二条执行链，应复用 `ExecutionEngine.execute(tool:seed:)`。
3. ToolEditor v2 必须引入草稿层，否则“未保存草稿试跑”会被当前直接 binding 配置的实现破坏。
4. MVP 需要比 `ExecutionSeed.isDryRun` 更清晰的 run policy，表达真实 LLM、真实 MCP、side effects dry-run、Playground output routing。
5. 不新增 sample/history/version 持久化 schema，相关能力记录为技术债务。

## 验证

本任务只修改文档，验证边界为：

- 未完成标记扫描：无命中。
- `git diff --check`：通过。
- 自审结论：spec 范围聚焦首个 MVP；明确记录 non-goals、run policy 风险、ToolEditor 草稿层风险和 Phase 3 后续技术债务；未发现范围矛盾。

## 变动文件清单

- `docs/superpowers/specs/2026-05-28-phase-3-tool-editor-playground-mvp.md`
- `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-spec.md`
- `docs/Task_history.md`

## 下一步

用户 review spec。若用户要求修改，则更新同一份 spec 和本任务文档；用户批准后再进入 `superpowers:writing-plans`，产出 implementation plan。
