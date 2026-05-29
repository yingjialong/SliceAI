---
topic: phase-3-prompt-ide-local-models
title: Phase 3 Prompt IDE 与本地模型
branch: codex/phase3-tool-editor-playground
status: needs-review
created: 2026-05-27 17:28
last_updated: 2026-05-29 09:34
---

# Phase 3 Prompt IDE 与本地模型

## Goal

用户已明确选择跳过 Phase 2 release，不做 `v0.4.0` tag、DMG 构建或发布收口，直接进入 Phase 3。
Phase 3 的路线图主题是 Prompt IDE + 本地模型；首个冻结切片已经收敛为 ToolEditor v2 + Prompt Playground MVP。
当前分支已完成该 MVP 的 spec、implementation plan、实现、review-fix 和 plan compliance audit；下一台机器应从审查 / 真实 App smoke 继续，而不是重新从 roadmap 直接写实现。

## Session history

- **2026-05-29 09:34 session 3**：Phase 3 ToolEditor v2 + Prompt Playground MVP 已完成实现、两轮 review-fix、layout debt 记录和 plan compliance audit。最新提交 `c481ed7` 已把 implementation plan 的 52 个步骤标记为完成，新增逐 Task 审计文档，并记录 SwiftLint 本机缺失的 gate 例外。当前分支已推送到 `origin/codex/phase3-tool-editor-playground`。
- **2026-05-28 00:00 session 2**：发现另一台机器把 Phase 3 spec 推到了 Phase 2 分支；当前会话已将 Phase 2 completion 合回 `main`，并把 Phase 3 workstream 迁移到 `codex/phase3-tool-editor-playground`。
- **2026-05-27 17:28 session 1**：用户决定跳过 Phase 2 发布并换另一台机器继续 Phase 3；本会话新增本 handoff，更新项目状态文档到 Phase 3 kickoff 口径，并已推送 `codex/phase2-completion` 到 `origin/codex/phase2-completion`。

## Current code state

- Branch: `codex/phase3-tool-editor-playground`
- Remote to use on another machine: `origin/codex/phase3-tool-editor-playground`
- Recent relevant commits:
  - `c481ed7` docs: audit phase 3 plan compliance
  - `1e7b7b8` docs: record playground layout debt
  - `75b8f4f` fix: fail closed on invalid permission dry-run outcome
  - `5d5654a` fix: harden playground review findings
  - `9a3d525` docs: align phase 3 playground status
  - `9a04a1a` docs: record phase 3 playground implementation
  - `1e0a9ee` fix: clear playground validation failures
  - `60c3c37` fix: harden tool editor playground ui
  - `8c53683` feat: add tool editor playground ui
  - `8cb5959` fix: clear failed playground state
  - `edff426` feat: add tool playground state reducer
  - `c111d44` fix: tighten tool draft validation
  - `dc2a299` feat: add tool editor draft state
  - `67921b0` feat: add tool playground runner
  - `0c92380` feat: add playground run policy telemetry
- Uncommitted changes:
  - 无。提交并推送本 handoff 后，另一台机器应看到干净工作区。
- Key files (next session must read):
  - `AGENTS.md`: Codex 工作入口、架构不变量、当前 Phase 状态和常用验证命令。
  - `CLAUDE.md`: 项目约定与历史开发规则。
  - `README.md`: 项目当前功能清单和最近 Phase 3 变更记录。
  - `docs/v2-refactor-master-todolist.md`: 跨 Phase dashboard、Phase 3 后续切片和技术债务。
  - `docs/superpowers/specs/2026-05-28-phase-3-tool-editor-playground-mvp.md`: 已冻结并 review 过的 MVP spec。
  - `docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md`: 已执行并完成勾选的 implementation plan。
  - `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`: Task 8 final gate、review-fix 和验证记录。
  - `docs/Task-detail/2026-05-29-phase-3-plan-compliance-audit.md`: 逐 Task plan compliance audit。
  - `docs/Module/Orchestration.md`: Playground run policy、preflight gate、runner 和 output dispatcher 设计。
  - `docs/Module/SettingsUI.md`: ToolEditor v2、draft state、Prompt Playground UI 和 layout debt。

## Decisions and rationale

- 跳过 Phase 2 release 是用户在 2026-05-27 的明确产品决策。不要自动打 `v0.4.0` tag、不要构建/发布 DMG，除非用户重新明确要求。
- Phase 3 原路线图仍是 Directional；本分支只冻结并实现了首个切片 ToolEditor v2 + Prompt Playground MVP。不要把 Anthropic、Gemini、Ollama、Memory、Cost Panel、A/B、版本历史等后续方向混入当前 MVP。
- MVP 的核心设计是：Settings 中编辑未保存 Tool 草稿，Run 时复用真实 `ExecutionEngine`，真实 LLM 调用，输出进入 preview，side effects dry-run，MCP tool call 默认禁用且必须由用户本次运行显式打开后才走 allowlist + PermissionBroker。
- Playground preflight 不能用 side-effect dry-run 放行上下文读取。review-fix 后只对 LLM 前真实会读取的 context / builtin 权限做真实 gate；side effects 仍在 finish 阶段 dry-run，MCP 由 `AgentExecutor` 每次按 run policy 控制。
- plan compliance audit 已确认 Task 1-8 源码、测试和文档与 plan 一致。发现并修复的是文档状态漂移，不是代码行为缺口。

## Next steps (ordered by priority)

1. 在新机器同步并核对分支：`git fetch origin && git checkout -B codex/phase3-tool-editor-playground origin/codex/phase3-tool-editor-playground && git status -sb`。Done when: 当前分支为 `codex/phase3-tool-editor-playground`，工作区干净，HEAD 为最新远端提交。
2. 读取 required reading 后先向用户复述状态，不要直接改代码。Done when: 用户确认下一步是 review、真实 App smoke、merge 准备，还是进入下一个 Phase 3 spec。
3. 做 Phase 3 Playground 真实 App smoke：启动 App，打开 Settings Tools，验证已有 Tool 编辑不会 Save 前污染配置，Add Prompt / Add Agent 不直接写 `configuration.tools`，Run 使用右侧 App / Window / URL / selection 输入，Cancel 能落到 cancelled，Save/Revert 行为正确。Done when: smoke 结果记录到 task detail 或新的 Task_history 条目。
4. 如真实 App smoke 发现问题，先写 focused regression test，再最小修复，并更新 `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md` 或新建对应 bugfix task detail。Done when: regression test 转绿，full SwiftPM tests / App build / `git diff --check` 通过。
5. 如果 smoke 通过，和用户确认集成路径：开 PR / 合 main / 保持分支继续下个切片。Done when: 用户明确选择，并且不把未 spec 的后续能力直接塞进当前 MVP。

## Known traps / do not touch

- 不要回到旧分支 `origin/codex/phase2-completion` 做 Phase 3；当前正确远端分支是 `origin/codex/phase3-tool-editor-playground`。
- 不要执行 Phase 2 release：不打 `v0.4.0` tag，不构建 / 发布 DMG，除非用户重新明确要求。
- 不要把 plan 中早期 “Expected: compile failure” 误解为当前失败状态；implementation plan 已执行完成，52 个步骤已勾选。
- `swiftlint` 在本机不在 PATH，因此最近 final gate 记录为环境缺失。若新机器装有 SwiftLint，应正常跑 `swiftlint lint --strict`；若没有，不要把 command-not-found 当成代码缺陷。
- MCP safety 不要弱化：Playground MCP 默认 disabled；用户打开本次运行开关后仍必须经过 Agent allowlist 和 PermissionBroker。
- Playground side effects 必须保持 dry-run。不要为了 smoke 方便而让 file / replace / clipboard / bubble / notify 走生产副作用。
- ToolEditor v2 小宽度响应式布局仍是技术债，已记录在 `docs/v2-refactor-master-todolist.md` 和 `docs/Module/SettingsUI.md`；不要在无用户确认时扩大到 UI polish。
- 真实 App smoke 依赖新机器自己的 Accessibility 权限、App Support 配置和 Keychain API Key；不要把本机配置、Keychain account 或临时 provider 写进 repo。

## Required reading (in order)

1. `CLAUDE.md`
2. `AGENTS.md`
3. `README.md`
4. `docs/handoffs/2026-05-27-phase-3-prompt-ide-local-models.md`
5. `docs/v2-refactor-master-todolist.md`
6. `docs/Task_history.md`
7. `docs/superpowers/specs/2026-05-28-phase-3-tool-editor-playground-mvp.md`
8. `docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md`
9. `docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md`
10. `docs/Task-detail/2026-05-29-phase-3-plan-compliance-audit.md`
11. `docs/Module/Orchestration.md`
12. `docs/Module/SettingsUI.md`
13. `docs/Module/SliceCore.md`

## Minor changes (side work outside the main thread)

- `docs/Task-detail/2026-05-29-phase-3-plan-compliance-audit.md`: 新增 plan compliance audit，按 Task 1-8 记录实现证据和验证结果。
- `docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md`: 52 个步骤由未完成同步为完成，并补充 SwiftLint 本机缺失说明。
- `docs/Task_history.md`: 新增 Task 76，记录 plan audit 完成。
