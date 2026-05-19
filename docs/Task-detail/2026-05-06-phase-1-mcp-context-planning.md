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
- [x] 完成 Phase 1 M1-M4 主干实施、Task 16 release readiness gate、Task 17 真实 MCP E2E 主体验证和 Task 56 Agent Tool 配置 / MCP 调用策略收口。

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
- Phase 1 M1-M4 implementation：已完成并记录到各 Task-detail；Task 17 完成 filesystem / postgres / brave-search / git / sqlite 直接 MCP JSON-RPC E2E，用户已基本复测 App 场景且未反馈阻塞问题。
- `git diff --check`：通过。

## Phase 1 实施收口状态

- M1 已完成 MCP 数据契约、store/importer、stdio client 和 MCP Servers 设置页。
- M2 已完成五个核心 ContextProvider、PermissionGraph case-aware coverage、permission consent/persistent grant store 和 AppContainer 生产 wiring。
- M3 已完成 OpenAI-compatible tool calling contract、AgentExecutor ReAct loop、ResultPanel tool-call lifecycle 和 `web-search-summarize` Agent tool。
- M4 已完成 Streamable HTTP transport、per-tool hotkeys、Task 16 release readiness 文档 / 自动化 gate、Task 17 真实 MCP E2E 主体验证和 Task 56 基础自定义 Agent Tool 配置 / MCP 调用策略。
- Task 57 已在 `main` 上完成最终 release gate / Claude review loop、本地 DMG 预检和 `v0.3` release notes / tag checklist；剩余发布动作是用户确认后的远端 push、`v0.3.0` tag 和 GitHub Release 发布流程。

## 下一步

用户确认后推送 `main`，创建并推送 `v0.3.0` tag，等待 GitHub Actions 生成 draft release，再人工校验 artifact 和 SHA 后发布。
