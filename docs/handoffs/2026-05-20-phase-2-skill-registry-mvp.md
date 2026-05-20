---
topic: phase-2-skill-registry-mvp
title: Phase 2 Skill Registry MVP
branch: main
status: in-progress
created: 2026-05-20 22:28
last_updated: 2026-05-20 22:28
---

# Phase 2 Skill Registry MVP

## Goal

用户已决定暂缓人工发布 `v0.3.0` draft release，继续做后续开发。Phase 2 当前仍是 Directional Outline，不能直接进入实现；本 workstream 的目标是先把 Skill Registry MVP 的规格设计清楚，再进入计划和代码。推荐切片是“本地 skill 包发现、`SKILL.md` 解析、Settings 可见性、Tool 引用关系和执行前指令注入”，为后续 DisplayMode、English Tutor 和更完整的 Skill runtime 打基础。

## Session history

- **2026-05-20 22:28 session 1**：`v0.3.0` draft release 已生成并校验通过，但用户明确选择暂缓人工发布；将 README、Task History、master TodoList 和 Task 57 release prep 文档更新到 Phase 2 启动口径；新增 Task 58 和本 handoff。没有业务代码修改。

## Current code state

- Branch: `main`
- Recent relevant commits:
  - `a578581` docs: record v0.3 draft release readiness
  - `4a32e30` fix(ci): satisfy release archive sendability
  - `810c21f` fix(agent): close v0.3 release prep blockers
  - `2d1df67` merge: phase 1 mcp context
- Uncommitted changes:
  - 交接完成后预期为无；下一会话仍必须先运行 `git status -sb`，如看到 docs-only diff，先确认是否是本 handoff 未提交完成。
- Key files (next session must read):
  - `README.md`：项目状态入口，已记录暂缓 `v0.3.0` 人工发布和 Phase 2 下一步。
  - `docs/v2-refactor-master-todolist.md`：跨 Phase 主进度表，§0 Dashboard 和 §5.1 是当前工作的主索引。
  - `docs/Task-detail/2026-05-20-phase-2-skill-registry-mvp-spec.md`：Task 58 任务详情和 ToDoList。
  - `docs/Task-detail/2026-05-19-v0.3-release-prep.md`：记录 `v0.3.0` draft release 技术状态和暂缓发布边界。
  - `SliceAIKit/Sources/Capabilities/Skills/SkillRegistryProtocol.swift`：当前 SkillRegistry 协议骨架。
  - `SliceAIKit/Sources/Capabilities/Skills/MockSkillRegistry.swift`：当前生产侧 mock，占位实现边界。
  - `SliceAIKit/Sources/SliceCore/Skill.swift`：Phase 0 落地的 Skill 数据模型。
  - `SliceAIKit/Sources/SliceCore/Tool.swift`、`SliceAIKit/Sources/SliceCore/Configuration.swift`：Tool / 配置如何引用未来 skill 的关键模型。
  - `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift` 和 `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`：现有 Tool 配置入口，后续 Skill 引用 UI 可能接在这里。

## Decisions and rationale

`v0.3.0` draft release 技术上可人工发布，但这是用户明确暂缓的产品决策。不要删除 draft、不要删除或重打 `v0.3.0` tag，也不要继续 release publish，除非用户重新明确要求。

Phase 2 不能直接实现。总 Todo 明确 Phase 2–5 是 Directional，进入前必须重新走 brainstorming / spec / plan。现在若直接做 English Tutor 或 DisplayMode，会把未冻结的 Skill Registry 抽象写死；先做 Skill Registry MVP 能最小化依赖面，并给后续功能一个稳定挂载点。

本轮推荐的 MVP 不包含 marketplace、远端安装、skill 内脚本执行、TTS、English Tutor 全流程，也不包含 `replace / bubble / structured / silent` DisplayMode 的完整 UI。那些能力应在 Skill Registry spec 确认后再分 milestone。

## Next steps (ordered by priority)

1. 按 `superpowers:brainstorming` 与用户对齐 Skill Registry MVP 的真实范围，尤其是 skill 目录来源、`SKILL.md` 最小解析规则、Settings 展示、Tool 引用方式和执行时注入边界。Done when: 用户确认 MVP scope / out-of-scope。
2. 创建 `docs/superpowers/specs/YYYY-MM-DD-phase-2-skill-registry-mvp.md`，把数据模型、扫描流程、错误模型、UI 入口、权限边界、测试策略写清楚。Done when: spec 无 TODO / TBD，且与 `docs/v2-refactor-master-todolist.md` 不矛盾。
3. 对 spec 做自检 / review，并请用户确认。Done when: 用户确认可以进入 plan。
4. 只有在 spec 确认后，使用 `superpowers:writing-plans` 产出 implementation plan；实现前建议开 `codex/phase-2-skill-registry-mvp` 分支或 worktree。Done when: plan 通过 review 且任务拆分可 TDD 执行。

## Known traps / do not touch

- 不要把“跳过发布”理解成 release 失败。`v0.3.0` draft release 已成功生成并校验；只是用户暂缓人工 publish。
- 不要在用户未确认前发布 GitHub Release、重打 `v0.3.0` tag 或删除 draft release。
- 不要直接实现 Phase 2 代码。第一步是 brainstorming + spec。
- 不要把 Skill support 当作 Phase 1 bugfix。Task 56 已明确 Skill 属于 Phase 2，不是 `v0.3` blocker。
- `main` 可能已经包含 `v0.3.0` tag 之后的文档提交；如果以后真的发布，需要注意 tag 指向和 release 内容边界。
- 当前 Brave Search MCP 依赖外部 npm 包，且 upstream 已标记 deprecated；这与 Skill Registry MVP 无直接关系，不要把它混进本轮 scope。

## Required reading (in order)

1. `CLAUDE.md`（项目约定）
2. `README.md`（项目当前状态）
3. `docs/v2-refactor-master-todolist.md`（§0 Dashboard、§5.1 Phase 2、§9 最新 snapshot）
4. `docs/Task-detail/2026-05-20-phase-2-skill-registry-mvp-spec.md`（Task 58）
5. `docs/Task-detail/2026-05-19-v0.3-release-prep.md`（release 暂缓边界）
6. `docs/Task-detail/2026-05-19-phase-1-agent-tool-config-policy.md`（Agent Tool 配置和 MCP policy 边界）
7. `docs/Module/MCPClient.md`、`docs/Module/ContextProviders.md`（Phase 1 能力边界，避免误把 MCP 问题塞进 Skill MVP）
8. `SliceAIKit/Sources/Capabilities/Skills/SkillRegistryProtocol.swift`
9. `SliceAIKit/Sources/Capabilities/Skills/MockSkillRegistry.swift`
10. `SliceAIKit/Sources/SliceCore/Skill.swift`
11. `SliceAIKit/Sources/SliceCore/Tool.swift`
12. `SliceAIKit/Sources/SliceCore/Configuration.swift`
13. `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`
14. `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`

## Minor changes (side work outside the main thread)

- `README.md`、`docs/v2-refactor-master-todolist.md`、`docs/Task_history.md`、`docs/Task-detail/2026-05-19-v0.3-release-prep.md`：只做状态对齐，未改变 release artifact 或代码。
