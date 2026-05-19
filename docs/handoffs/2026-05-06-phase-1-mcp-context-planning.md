---
topic: phase-1-mcp-context-planning
title: Phase 1 MCP Context 计划
branch: main
status: needs-review
created: 2026-05-06 18:47
last_updated: 2026-05-06 18:47
---

# Phase 1 MCP Context 计划

## Goal

本工作流负责把 SliceAI v2 Phase 1 从"设计冻结但未计划"推进到"spec 已确认、implementation plan 已完成 review，可进入实现"。Phase 1 覆盖完整 v0.3 DoD：MCP 配置与调用、5 个核心 ContextProvider、真实 Permission UI gate、AgentExecutor、ResultPanel 工具调用展示、Per-Tool Hotkey、5 个 MCP server E2E 与 v0.3 发布准备。

当前不是实现阶段。下一步必须先让用户 review 已提交的 design spec，再进入 `superpowers:writing-plans`。

## Session history

- **2026-05-06 18:47 session 1**：按 `superpowers:brainstorming` 完成 Phase 1 范围确认与设计复核。用户选择完整 Phase 1 总计划（方案 A），并确认采用"主干先行 + M1-M4 里程碑验收"。已写入并提交 `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`，commit `f73d09b docs: add phase 1 mcp context design`。同时更新 `docs/Task_history.md`、`docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`、`docs/v2-refactor-master-todolist.md`。

## Current code state

- Branch: `main`
- Recent relevant commits:
  - `f73d09b` docs: add phase 1 mcp context design
  - `c8bba69` Merge pull request #5 from yingjialong/docs/pre-phase1-closeout
  - `0a54c07` docs: close pre phase1 setup
- Uncommitted changes:
  - Audit before writing this handoff was clean.
  - After this handoff, only `docs/handoffs/2026-05-06-phase-1-mcp-context-planning.md` is expected to be uncommitted unless the next session or user commits it.
- Key files (next session must read):
  - `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`: current Phase 1 design spec; user must review this before plan writing.
  - `docs/v2-refactor-master-todolist.md`: project-level state dashboard and Phase 1 entry criteria.
  - `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`: task-local planning record and checklist.
  - `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`: upstream v2 roadmap and Phase 1 DoD.
  - `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`: canonical MCP descriptor source.
  - `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`: currently has a duplicate simplified `MCPDescriptor`; Phase 1 plan must address this.
  - `SliceAIKit/Sources/Orchestration/Context/ContextCollector.swift`: existing context collection mainline.
  - `SliceAIKit/Sources/Orchestration/Permission/PermissionBroker.swift`: currently returns `requiresUserConsent` without real UI gate.
  - `SliceAIApp/AppContainer.swift`: composition root where Phase 1 real providers / MCP client eventually attach.

## Decisions and rationale

Phase 1 scope is full v0.3 DoD, not a minimal vertical slice. The accepted structure is one overall Phase 1 plan split into M1-M4 milestones:

1. M1：MCP 配置、Claude Desktop import、stdio client、Settings MCPServersPage。
2. M2：5 个 ContextProvider、PermissionBroker UI gate、PermissionGrantStore 持久化。
3. M3：AgentExecutor ReAct loop、tool call approval、ResultPanel lifecycle、`web-search-summarize`。
4. M4：MCP `Streamable HTTP`、旧 `HTTP+SSE` 兼容、Per-Tool Hotkey、5 server E2E、v0.3 发布准备。

设计里修正了一个重要口径：当前 MCP 官方最新规范（2025-11-25）标准传输是 `stdio` 与 `Streamable HTTP`，旧 `HTTP+SSE` 是兼容路径。因此后续 plan 不应继续把旧 SSE 当成远程传输主线。

设计还固定了几个主干约束：

- `SliceCore/MCPDescriptor.swift` 是唯一 MCP descriptor 来源，不能保留 Capabilities 内的重复定义。
- MCP 参数和结果必须升级为结构化 JSON / content item 类型，不能继续用 `[String: String]` 和 `[String]`。
- Provenance 只影响风险文案，不能降低权限确认级别。
- Permission 默认 `oneTime`，弹窗允许 `session`，`persistent` 只在 Settings 中管理。
- `selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read` 是 Phase 1 必交付 ContextProvider。

## Next steps (ordered by priority)

1. 等用户 review `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md` 并明确确认或提出修改。Done when: 用户明确说 spec 可以继续，或给出需要修改的点且已修订。
2. 若用户确认 spec，读取 `superpowers:writing-plans` skill，并起草 `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`。Done when: plan 文件存在，覆盖 M1-M4，每个任务有文件清单、测试命令、验收标准。
3. 对新 plan 做完整 review，重点检查 spec 对齐、MCP transport 口径、权限安全、自动化验证、5 server E2E、Subagent-Driven 可拆分性。Done when: review 结论为 APPROVED / COMMENT，或所有 REWORK_REQUIRED findings 已修复。
4. 更新 `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md` 与 `docs/v2-refactor-master-todolist.md`。Done when: Task checklist 标记 plan/review 状态，Dashboard 下一个动作指向实现前准备。
5. 只有在 plan review 通过后，才进入实现；实现时应使用 `superpowers:subagent-driven-development` 并先建隔离 worktree。Done when: 用户明确要求开始实现。

## Known traps / do not touch

- 不要跳过用户 spec review gate。当前只完成 design spec，不能直接写代码。
- 不要把 MCP 远程传输继续写成"SSE 主线"。新计划应写 `Streamable HTTP` 主线、旧 `HTTP+SSE` 兼容。
- 不要泄露或记录用户曾在旧会话里提供的 API key；handoff 和 docs 中只能写 provider 类型，不写密钥。
- 不要删除旧 worktree / archive branch，除非用户明确要求。
- `main` 当前比 `origin/main` 领先 `f73d09b` 这个 docs commit；下一 session 若要共享远端，需要先确认是否 push。
- 仓库本地没有 `AGENTS.md` 文件，但用户在会话中提供过约束：中文沟通、macOS、每次开发前读 README、文档及时更新、代码函数级中文注释、必要中文日志、KISS、`.env` 与 `.env.example` 同步。

## Required reading (in order)

1. `CLAUDE.md`（项目约定）
2. `README.md`（项目背景与当前状态）
3. `docs/handoffs/2026-05-06-phase-1-mcp-context-planning.md`（本交接）
4. `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`（当前最重要）
5. `docs/v2-refactor-master-todolist.md`
6. `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
7. `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`

## Minor changes (side work outside the main thread)

- 无。当前会话只做 Phase 1 design spec、任务记录、master todolist 更新与本 handoff。
