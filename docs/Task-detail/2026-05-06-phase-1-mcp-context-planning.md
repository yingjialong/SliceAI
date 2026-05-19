# Phase 1 MCP + Context 主干设计与计划准备

## 任务背景

Phase 0 / v0.2.0 已发布，`main` 已同步到最新远端。进入 Phase 1 前，需要先复核 MCP + Context + Permission + AgentExecutor 的主干设计，再按 `superpowers:writing-plans` 产出 implementation plan，避免直接进入实现后把 Phase 0 留下的 mock、窄类型或 UI gate 缺口带入主线。

## 实施方案

- 使用 `superpowers:brainstorming` 先确认设计，再写 design spec。
- Phase 1 采用完整 v0.3 DoD 总范围，不缩成最小 vertical slice。
- 总 plan 内部拆为 M1-M4：MCP 配置与 stdio、Context 与 Permission、AgentExecutor 与工具调用 UI、HTTP transport / Per-Tool Hotkey / 5 server E2E / 发布准备。
- 当前 MCP 官方最新协议把标准传输定义为 `stdio` 与 `Streamable HTTP`，旧 `HTTP+SSE` 是兼容路径；Phase 1 文档需要修正原 roadmap 中"SSE"的执行口径。
- 在用户 review design spec 后，再写 `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md` 并做 plan review。

## ToDoList

- [x] 读取 README、master todolist、v2 roadmap spec、Phase 1 相关代码主干。
- [x] 确认 Phase 1 范围采用完整 v0.3 DoD，总 plan 内部拆 M1-M4。
- [x] 确认推荐方案为"主干先行 + 里程碑验收"。
- [x] 起草 Phase 1 MCP + Context design spec。
- [x] 运行 Claude review loop 审查 design spec，并修订到 Round 3 `approve`。
- [x] 用户 review design spec。
- [x] 起草 Phase 1 implementation plan。
- [x] 运行 Claude review loop 审查 implementation plan（8 rounds，19 findings accepted/fixed，最终 `approve`）。
- [x] 对 implementation plan 做完整 review 并修订到 APPROVED / COMMENT。

## 当前设计结论

- `SliceCore` 保持稳定模型与协议边界，`Capabilities` 实现 MCP / Context / Grant store，`Orchestration` 实现执行编排，`SliceAIApp` 承接 Settings、权限弹窗、ResultPanel 和 Hotkey 注册。
- `SliceCore/MCPDescriptor.swift` 是唯一 MCP descriptor 来源，不能继续保留 `Capabilities/MCP/MCPClientProtocol.swift` 中的重复定义。
- MCP 参数与结果需要结构化 JSON 类型，不能继续使用 `[String: String]` 和 `[String]` 这类窄类型。
- Permission 默认 fail closed；MCP tool call 默认需要用户确认，provenance 只影响 UX 文案，不能降低确认级别。
- `ContextProvider` 先实现 `selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read` 五个 DoD 要求项。
- Claude review loop 修订后补充明确：MCP tool call 永不写入 `PermissionGrantStore`；`MCPTransport` 在 M4 新增 `.streamableHTTP`，旧 `.sse` 仅作兼容；MCP JSON value / content item canonical 类型归属 `SliceCore`；PermissionGraph 的 `⊆` 必须升级为 case-aware coverage，而不是字面 `Set.subtracting`。

## 变动文件

- `docs/Task_history.md`
- `README.md`
- `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
- `docs/Task-detail/claude-loop-phase-1-mcp-context-design.md`
- `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`
- `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- `docs/v2-refactor-master-todolist.md`

## 测试与验证

- 文档 placeholder / scope / ambiguity 自审：通过，结果已写入 design spec §10。
- Claude review loop：Round 1 `needs_attention`（1 high / 3 medium），Round 2 `needs_attention`（1 medium），Round 3 `approve`（0 findings）。审查记录见 `docs/Task-detail/claude-loop-phase-1-mcp-context-design.md`。
- Plan Claude review loop：Round 1-8 共 19 条 finding，全部 `accept` 并修复；Round 8 返回 `approve`（0 findings）。审查记录见 `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`。
- Phase 1 implementation plan 红旗词扫描：通过，未命中 `TBD` / `TODO` / `placeholder` / `...` 等 writing-plans 禁用占位模式。
- `git diff --check`：通过。

## 下一步

Phase 1 design spec 与 implementation plan 均已通过 Claude review。下一步按计划选择执行方式：推荐使用 `superpowers:subagent-driven-development` 从 Task 1 开始实施，或使用 `superpowers:executing-plans` 在当前会话内按 milestone 执行。
