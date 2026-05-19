---
topic: phase-1-mcp-context
title: Phase 1 MCP + Context 主干
branch: feature/phase-1-mcp-context
status: release-prep-pending
created: 2026-05-08 21:01
last_updated: 2026-05-19 17:05
---

# Phase 1 MCP + Context 主干

## Goal

Phase 1 的目标是把 Phase 0 已落地的 `ContextProvider` / `MCPClient` / `PermissionBroker` / `ExecutionEngine` 主干填实到 v0.3 可用状态：用户可以配置 MCP server，真实采集核心上下文，通过权限 gate 调用工具，并交付 `web-search-summarize`、基础自定义 Agent Tool、Per-Tool Hotkey、Streamable HTTP 和 5-server E2E。

当前代码主干和自动化 gate 已完成；filesystem / postgres / brave-search / git / sqlite 五个 MCP server 已完成直接 JSON-RPC E2E。基础 Agent Tool 编辑器、MCP allowlist 文本配置和独立 MCP tool-call policy 已完成代码实现。用户已基本复测真实 App 场景且未反馈阻塞问题；剩余缺口是合并到 `main` 后执行最终 release gate / review loop，并准备 `v0.3` release notes 与 tag。

## Session history

- **2026-05-19 Task 56 Agent Tool Config And MCP Policy**: 纠正 Task 17 中把 MCP 总预算临时绑到 `maxSteps` 的方案。新增 `AgentToolCallPolicy`，`maxSteps` 只表示 LLM ReAct 轮数；执行器按 policy 控制总调用数、单轮调用数、单工具调用数、重复参数和 rate limit 停止。Tools 设置页支持新增 Agent、编辑 prompt / provider / LLM 轮数 / MCP allowlist / 调用策略。本机 `config-v2.json` 已同步 `web-search-summarize` policy。验证通过 focused tests 72、全量 SwiftPM 756、SwiftLint strict、`git diff --check`、Xcode Debug build 和 `build/e2e` Debug build；Debug App 已重启，进程 `13394`。
- **2026-05-19 用户基本复测通过**: 用户反馈当前版本已基本测试无问题；文档已将 Task 17 状态从 App E2E pending 调整为 release prep pending。该反馈未附逐项截图 / 日志证据，发布前仍建议在 `main` 上跑最终 gate 和 review loop。
- **2026-05-19 Task 17 App 实测缺陷修复**: 已搭建五项本地 MCP server 并完成直接 `tools/list` / 安全 tool call；已补丁本机 `config-v2.json` 使 `web-search-summarize` 可见。修复五项 App 实测缺陷：DeepSeek V4 thinking-mode follow-up 丢失 `reasoning_content`、Brave 搜索 MCP 权限弹窗缺 session/persistent 授权、Agent 达到 `maxSteps` 后无最终回答、最终回合 DSML 工具调用标记误作为正文输出、过量顺序 Brave 搜索触发限流。上轮验证通过 full SwiftPM 749 tests、full SwiftLint strict、`git diff --check`、App Debug build。
- **2026-05-10 10:04 session handoff**: Task 16 已完成并提交 3 个 commit：`873aa1d` release readiness 文档和脚本、`ab05c8f` 修复 E2E 脚本配置摘要泄漏风险、`a1a1763` 记录 Claude review approve。当前分支除本 handoff 外无未提交代码。下一步应开 Task 17 做真实 release E2E。
- **2026-05-09 M4 Task 16**: 完成 release-readiness 收口。修复全仓 strict SwiftLint 历史 blocker，`swiftlint lint --strict` 当前 170 files / 0 violations；`swift build`、735 tests with coverage、App Debug build 通过；新增 `scripts/phase1-mcp-e2e.sh`、`docs/Module/MCPClient.md`、`docs/Module/ContextProviders.md`；真实 5-server / App E2E 因本机缺 `mcp.json`、API key 和测试数据源而记录为 blocker。Claude review Round 1 接受并修复脚本泄漏 `args/url` 原值风险；Round 2 approve。
- **2026-05-09 M4 Task 15**: 完成 per-tool hotkeys：`HotkeyBindings.tools`、冲突检测、Settings UI、AppDelegate 多热键注册和 tool id 直达执行。Claude review Round 2 approve。
- **2026-05-09 M4 Task 14**: 完成 Streamable HTTP MCP transport：MCP 2025-06-18 HTTP POST、session id、JSON / SSE response、redirect 阻断、404 session retry；`.sse` / `.websocket` 继续 fail-fast。Claude review Round 2 approve。
- **2026-05-08 M3 Task 10-13**: 完成 OpenAI-compatible tool calling contract、AgentExecutor ReAct loop、ResultPanel tool-call lifecycle、首个内置 Agent tool `web-search-summarize`。每个 Task 均完成 Claude review。
- **2026-05-08 M2 Task 6-9**: 完成 case-aware `PermissionGraph` coverage、五个核心 `ContextProvider`、permission consent/grant model、AppContainer 生产 wiring。
- **2026-05-06/07 M1 Task 1-5**: 完成 MCP JSON/data contract、canonical descriptor、`MCPServerStore` + Claude Desktop import、stdio JSON-RPC client、Settings MCP Servers page；旧 HTTP+SSE 明确弃用且不实现，M4 只做 Streamable HTTP。

## Current code state

- Branch: `feature/phase-1-mcp-context`
- Worktree: `/Users/majiajun/workspace/SliceAI/.worktrees/phase-1-mcp-context`
- Code status before latest Task 17 fix: worktree already had Task 17 docs/config-validation changes from this E2E session.
- Current status: uncommitted code + docs for DeepSeek reasoning-content, Brave MCP grant UX, Agent maxSteps finalization, DSML finalization guard, Brave search rate-limit mitigation, basic Agent Tool editor, MCP allowlist text config, and independent Agent tool-call policy. Do not revert unrelated user changes.
- Recent relevant commits:
  - `a1a1763` docs: record task 16 review approval
  - `ab05c8f` fix(scripts): redact mcp e2e config summary
  - `873aa1d` docs: record phase 1 mcp release readiness
  - `dc11c4e` docs: record task 15 review approval
  - `b76ae5f` fix(app): keep tool hotkey validation in sync
  - `1834288` feat(app): add per-tool hotkeys
  - `e2d318a` docs: record task 14 review approval
  - `f6afd5d` fix(core): harden streamable http sessions
  - `b4486b1` feat(core): add streamable http mcp transport
  - `7306342` docs: record task 13 review approval

Key files next session must read:

- `docs/Task-detail/2026-05-10-phase-1-release-e2e-validation.md`: current Task 17 state, direct MCP E2E evidence, App bug fixes, and remaining manual App regression checklist.
- `docs/Task-detail/2026-05-19-phase-1-agent-tool-config-policy.md`: Task 56 implementation record for basic Agent editor and `AgentToolCallPolicy`.
- `docs/Task-detail/2026-05-09-phase-1-m4-task-16-five-server-e2e-release-readiness.md`: exact Task 16 evidence, blockers, tests, and review result.
- `docs/Task-detail/claude-loop-phase-1-m4-task-16-five-server-e2e-release-readiness.md`: Task 16 Claude review ledger; includes accepted script redaction finding and approval.
- `scripts/phase1-mcp-e2e.sh`: release E2E prerequisite checklist; intentionally does not print `mcp.json` args / URL / env values.
- `docs/Module/MCPClient.md`: current MCP client design, store path, transports, permission boundary, E2E matrix.
- `docs/Module/ContextProviders.md`: five provider names, args schema, inferred permissions, cancellation requirements, `file.read` sandbox behavior.
- `docs/v2-refactor-master-todolist.md`: canonical dashboard; currently says Phase 1 M4 automation/review done but real E2E blocked by environment.
- `README.md`: current project status and Task 16 change record.

## Decisions and rationale

- 真实 5-server E2E 不能伪造。Task 16 只记录了 environment blocker；下一步必须在有真实 `mcp.json` / API key / DB / safe directory 的机器上跑 tools/list 和至少一次安全 tool call。
- `scripts/phase1-mcp-e2e.sh` 是只读检查脚本。它可以输出 env key 名称、args 数量、是否存在 URL，但不能输出 args、URL、command 原值或 env 值；Claude review 已把这点作为 release security boundary。
- 旧 HTTP+SSE 不作为 Phase 1 支持目标；`.sse` / `.websocket` 继续 fail-fast。远程传输只支持 Streamable HTTP。
- `.network`、`.shellExec`、`.appIntents` 仍不缓存；MCP 默认不缓存，但 Task 17 明确对白名单内置只读 `brave-search.brave_web_search` 开启 session / persistent grant，避免 Web Search 每次重复弹窗。不要把该例外泛化到 filesystem、git、postgres、sqlite。
- `PermissionBroker` 必须保持 UI-free；AppKit 只能在 `SliceAIApp/AppPermissionConsentPresenter.swift`。
- Task 16 的 SwiftLint 修复是行为等价拆分：`MCPServersPage+Editor.swift`、`StdioMCPClient+Session.swift`、`PermissionBroker` helper 拆分，不应在下一步重构扩张。
- `maxSteps` must not be reused as MCP total-call budget. It is only the LLM ReAct round limit; MCP call budgeting belongs to `AgentToolCallPolicy`.

## Next steps (ordered by priority)

1. 将 `feature/phase-1-mcp-context` 合并到 `main`，同时保留根工作树已有的 Phase 1 planning review 文档变更。Done when: `main` 包含 Task 17 / Task 56 代码与文档，且无冲突残留。
2. 在 `main` 上运行最终 release gate：SwiftPM full test、SwiftLint strict、`git diff --check`、App Debug build；必要时补一轮 `claude-review-loop` / code review。Done when: gate 结果写入 Task 17 / release prep 文档。
3. 准备 `v0.3` release notes 和 tag checklist，记录 Brave Search npm 包 deprecated 风险、MCP secret 脱敏边界、用户基本复测但未沉淀逐项证据的事实。Done when: release prep 文档明确 go / no-go。
4. 若最终 gate 或 review 发现代码 bug，只做最小修复并复跑相关 focused tests + full gate。Done when: accepted findings 修复完，Claude approve 或低风险项有稳定理由。

## Known traps / do not touch

- 不要把 Task 16 的 checklist 输出当成真实 E2E pass。它只是前置条件检查和手工步骤清单。
- 不要把 secret 写入 handoff、Task docs、README、review log 或 shell 输出。Postgres URL、Brave API key、provider keychain 相关内容必须脱敏。
- `@modelcontextprotocol/server-brave-search` 当前 npm 可解析但 deprecated；release 前需要确认继续使用该包是否可接受，或记录替代方案。
- `@modelcontextprotocol/server-git` 在 npm registry 返回 404；当前可用入口是 `uvx --from mcp-server-git mcp-server-git`。
- 本机没有 `psql`，如果需要独立校验 Postgres 连接，先安装或用 server 自身只读 query 作为证据。
- `docs/handoffs/2026-05-08-phase-1-mcp-context.md` 是 developer scratch，当前未跟踪。之前明确不要提交 handoff，除非用户改变要求。
- 如果修改 `.env`，必须同步 `.env.example`；当前 Task 16/17 计划不需要改 `.env`。

## Required reading (in order)

1. `CLAUDE.md`（项目约定）
2. `README.md`（当前项目状态）
3. `docs/Task-detail/2026-05-10-phase-1-release-e2e-validation.md`
4. `docs/Task-detail/2026-05-09-phase-1-m4-task-16-five-server-e2e-release-readiness.md`
5. `docs/Task-detail/claude-loop-phase-1-m4-task-16-five-server-e2e-release-readiness.md`
6. `docs/Module/MCPClient.md`
7. `docs/Module/ContextProviders.md`
8. `docs/v2-refactor-master-todolist.md`
9. `scripts/phase1-mcp-e2e.sh`

## Minor changes (side work outside the main thread)

- `docs/handoffs/2026-05-08-phase-1-mcp-context.md`: updated for Task 17 latest App E2E bugfix state.
