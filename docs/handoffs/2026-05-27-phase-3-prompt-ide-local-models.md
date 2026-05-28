---
topic: phase-3-prompt-ide-local-models
title: Phase 3 Prompt IDE 与本地模型
branch: codex/phase3-tool-editor-playground
status: in-progress
created: 2026-05-27 17:28
last_updated: 2026-05-28 00:00
---

# Phase 3 Prompt IDE 与本地模型

## Goal

用户已明确选择跳过 Phase 2 release，不做 `v0.4.0` 发布收口，直接进入 Phase 3。
Phase 3 的路线图主题是 Prompt IDE + 本地模型：ToolEditor v2、Prompt Playground、样本管理、A/B 对比、版本历史、原生 Anthropic / Gemini / Ollama provider、Memory、Cost Panel 和 local-only 隐私闭环。
当前 Phase 3 仍是 Directional outline，不能直接从 roadmap 开始写实现；下一台机器的第一步应是重新做 Phase 3 brainstorming / spec 收敛。

## Session history

- **2026-05-28 00:00 session 2**：发现另一台机器把 Phase 3 spec 推到了 Phase 2 分支；当前会话已将 Phase 2 completion 合回 `main`，并把 Phase 3 workstream 迁移到 `codex/phase3-tool-editor-playground`。
- **2026-05-27 17:28 session 1**：用户决定跳过 Phase 2 发布并换另一台机器继续 Phase 3；本会话新增本 handoff，更新项目状态文档到 Phase 3 kickoff 口径，并已推送 `codex/phase2-completion` 到 `origin/codex/phase2-completion`。

## Current code state

- Branch: `codex/phase3-tool-editor-playground`
- Remote to use on another machine: `origin/codex/phase3-tool-editor-playground`
- Recent relevant commits:
  - `7547dbf` docs: prepare phase 3 handoff
  - `bd00105` docs: record phase 2 app smoke
  - `19db1c8` docs: record phase 2 gate status
  - `4413e36` feat: add english tutor tool
  - `2f80b43` feat: add local tts side effect
  - `16da58c` feat: add bubble and structured display modes
  - `6affe29` feat: add replace display mode
- Uncommitted changes:
  - 无。推送完成后另一台机器应看到干净工作区。
- Key files (next session must read):
  - `AGENTS.md`: Codex 工作入口、已完成能力、不应误报能力和常用验证命令。
  - `README.md`: 项目当前状态、功能清单和最近变更记录。
  - `docs/v2-refactor-master-todolist.md`: 跨 Phase dashboard、Phase 3 路线图和从当前到 v1.0 的剩余任务总表。
  - `docs/superpowers/specs/2026-05-28-phase-3-tool-editor-playground-mvp.md`: Phase 3 首个冻结切片 spec，已完成 Codex review 修订。
  - `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`: Phase 3 方向性目标与 DoD，特别是 §4.5。
  - `docs/Task-detail/2026-05-26-phase-2-completion.md`: Phase 2 completion 的真实实现边界、验证结果和 smoke 证据。
  - `docs/superpowers/plans/2026-05-26-phase-2-completion.md`: Phase 2 implementation plan 与验证历史。

## Decisions and rationale

- 跳过 Phase 2 release 是用户在 2026-05-27 的明确产品决策。不要自动打 `v0.4.0` tag、不要构建/发布 DMG，除非用户重新明确要求。
- 另一台机器应基于远端分支 `origin/codex/phase3-tool-editor-playground` 继续 Phase 3。`main` 已包含 Phase 2 completion；Phase 3 spec / plan / implementation 不应继续放在 Phase 2 分支。
- Phase 3 是 Directional，不是冻结 spec。必须先用 brainstorming / spec / plan 流程重新收敛范围，再进入实现。
- 推荐优先切片是 ToolEditor v2 / Prompt Playground foundation，而不是一次性同时做 Anthropic、Gemini、Ollama、Memory 和 Cost Panel。原因是当前 SettingsUI、ExecutionEngine、Output lifecycle 和 dry-run / permission event 结构已经能支撑 Playground MVP，风险更可控。
- Phase 2 的 Skill diagnostics、scripts 策略、完整 app 成功率矩阵和 Phase 2 release 均未完成，但用户选择不把它们作为进入 Phase 3 的 blocker。

## Next steps (ordered by priority)

1. 在新机器 checkout 并核对分支：`git fetch origin && git checkout -B codex/phase3-tool-editor-playground origin/codex/phase3-tool-editor-playground`。Done when: `git status -sb` 显示在 `codex/phase3-tool-editor-playground` 且工作区干净。
2. 读取 required reading 后，先向用户复述当前状态，不要直接改代码。Done when: 用户确认继续 Phase 3。
3. 使用 `superpowers:brainstorming` 为 Phase 3 重新收敛第一个冻结切片，建议候选为 “ToolEditor v2 + Prompt Playground MVP”。Done when: 明确包含/排除项、DoD 和风险边界。
4. 创建 Phase 3 task detail 与 Task_history 索引，例如 `docs/Task-detail/2026-05-27-phase-3-prompt-playground-spec.md`。Done when: 文档包含实施前 ToDoList、验证策略和不做范围。
5. 用 `superpowers:writing-plans` 产出 Phase 3 第一个 implementation plan，并在计划通过 review 后再写代码。Done when: plan 拆成可验证任务、包含 focused tests 和最终 gate。

## Known traps / do not touch

- 不要把 Phase 2 release 当成仍需立即执行的 blocker；用户已经选择跳过。
- Phase 3 spec / plan / implementation 应留在 `codex/phase3-tool-editor-playground`；不要再把 Phase 3 文档提交到 Phase 2 分支。
- `config.schema.json` 当前对应 `Configuration.currentSchemaVersion = 4`；任何配置模型变更都必须同步 schema 和迁移测试。
- `writeMemory` 当前在 `SideEffectExecutor` 中明确 unsupported；Phase 3 如果做 Memory，必须重新 spec 权限、存储、注入 prompt 和审计边界。
- `.pipeline` 仍未实现真实 `PipelineExecutor`；这是 Phase 5 方向，不要混入 Phase 3 Playground MVP。
- Skill `scripts/` 不读取、不执行；`allowed-tools` 只是展示，不授权。不要在 Phase 3 无 spec 的情况下打开执行面。
- 不要把临时 smoke 用的 App Support 配置、Keychain account 或本地 SSE stub 当作可复用环境。真实用户状态仍只在本机 App Support / Keychain。
- 真实 App smoke 已恢复用户配置；新机器需要自己的 Accessibility 权限和 Keychain API Key。

## Required reading (in order)

1. `AGENTS.md`
2. `README.md`
3. `docs/v2-refactor-master-todolist.md`
4. `docs/Task_history.md`
5. `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md` 的 §4.5 Phase 3
6. `docs/Task-detail/2026-05-26-phase-2-completion.md`
7. `docs/superpowers/plans/2026-05-26-phase-2-completion.md`
8. 进入具体实现前，再读相关模块文档：`docs/Module/Orchestration.md`、`docs/Module/SliceCore.md`、`docs/Module/LLMProviders.md`、`docs/Module/SettingsUI.md`（若文件存在）

## Minor changes (side work outside the main thread)

- `docs/v2-refactor-master-todolist.md`: 更新 dashboard 到“跳过 Phase 2 release，进入 Phase 3 kickoff”。
- `README.md` / `AGENTS.md` / `CLAUDE.md`: 同步当前状态，避免另一台机器误以为下一步仍是 Phase 2 release 决策。
