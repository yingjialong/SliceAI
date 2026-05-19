---
topic: phase-0-m3-plan-aligned-review
title: M3 plan 与 mini-spec 对齐后的 codex review
branch: feature/phase-0-m3-switch-to-v2
status: in-progress
created: 2026-04-29 17:20
last_updated: 2026-04-29 17:20
previous_handoff: null
---

# M3 plan 与 mini-spec 对齐后的 codex review

## Goal

下一会话用 `codex-review-loop` skill 对 `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（M3 v1→v2 类型切换实施计划，4459 行）做新一轮对抗式 review-fix。本 plan 与 `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（mini-spec，1036 行）刚刚完成口径对齐——本轮 review 是验证对齐后的 plan 是否真的可进入 implementation，并在 plan 仍可能存在的剩余 alignment 漏洞上找到落点。

**Why this is the third codex-review-loop on the same plan**：
1. 第一次（前次 session）跑了 R1~R9 codex review + audit-fix pass（修补 13 项 codex 全程未捕获的 substantive issue），log: `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`。
2. 第二次（本 session）跑了 R1~R7 fresh codex review（不接 R1~R9 历史，每轮发现 1 high finding，全 accept fix，用户 accept-and-stop），log: `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`。
3. 第二次结束后，用户做了 plan/spec 口径对齐工作（统一 13 项手工回归 / SemVer v0.2.0 / Task 1-3 的 4 关 CI gate / subshell 形式 / mktemp 备份等），记录在 `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`。
4. **本次 handoff 移交的工作 = 第三次 codex-review-loop**：在 mini-spec 也被改过的状态下，对 plan 做 fresh review，看对齐过程是否引入新漏洞 / 漏掉哪些角落。

## This session

- **Window**: 2026-04-28 16:10 – 2026-04-29 17:20（跨 /autocompact 续接；plan/spec 对齐发生在 compact 之后的小段会话内）
- **What got done**:
  - 完成第二次 codex-review-loop（fresh，R1~R7），plan 7 个高严重度 alignment finding 全 in-place fix（trajectory 1/1/1/1/1/1/1 high，无 walking back，无 stagnation）
  - 用户在 R5/R7 触达 cap 时分别选择 extend → R7 后 accept-and-stop
  - /autocompact 之后的小段会话内完成 plan/spec 口径对齐（详见 `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`）：
    - mini-spec "12 项" → "13 项" 同步
    - mini-spec release tag → SemVer `v0.2.0` 同步
    - plan Task 1/2/3 commit 前补齐 4 关 CI gate
    - plan 多行 gate 命令改 subshell 形式 `(cd SliceAIKit && ...)`
    - plan 手工回归备份命令改 `mktemp -d` + 原权限恢复
    - plan AppContainer additive 装配 + AppDelegate async bootstrap 视为同一原子单元
- **Predecessor**: first handoff for this workstream（M2 handoff `2026-04-27-2055-phase-0-m2-pr-prep.md` 是不同 topic）

## Current code state

- Branch: `feature/phase-0-m3-switch-to-v2`
- Recent relevant commits (only 1 ahead of main):
  - `2e1019b` docs(phase-0/m3): seed M3 mini-spec (user R1 approved Q1/Q2/Q3)
- Uncommitted changes:
  - `docs/Task_history.md`: modified — 加入 alignment task 索引
  - `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`: modified — R1~R10 codex review + 本次 alignment 累积修订（diff stat: +610/-178）
  - `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`: untracked — 对齐工作 task-detail 记录（status: completed）
  - `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`: untracked — 第一次 review-fix loop log（R1~R9 + audit-fix）
  - `docs/Task-detail/codex-loop-phase-0-m3-mini-spec.md`: untracked — mini-spec R1~R10 review loop log
  - `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`: untracked — 第二次 review-fix loop log（R1~R7 fresh）
  - `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`: untracked — plan 主体（4459 行；含两次 review-fix + alignment 累积修订）
- Key files (next session must read in order):
  - `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（1036 行；spec 决议；D-26 ~ D-31）
  - `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（4459 行；review 对象）
  - `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`（最近对齐工作总结，了解上一段会话改了哪些 plan/spec 段落）
  - `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`（第二次 loop log，含 R1~R7 决议 + final summary）
  - `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`（第一次 loop log，了解前次 R1~R9 + audit-fix 历史，避免新轮重复发现已 fix 问题）

## Decisions and rationale

1. **本 workstream 是"第三次 codex-review-loop"，不是"继续第二次"**：第二次 fresh loop 已写 final summary 并标 `status: converged-with-disagreement`。新会话应当作新 loop 启动（新 Goal Contract + 新 loop log slug，例如 `codex-loop-phase-0-m3-plan-aligned-review.md`），prior_round_decisions 块按本次自己的 round 来填，**不接** R1~R7 历史。但 focus 中可声明前次 fix 已落地、本次以"对齐后的 plan"为新基线。
2. **mini-spec 不再是"R10 approve 锁定"状态**：alignment 工作期间 mini-spec 被修改（统一 13 项 / v0.2.0），所以本次 review 的 in-scope 决策**仍应**保持"plan-only"（mini-spec 视为 Reference Documents 而非 review 对象，新对齐不应再被 codex 评论）；但明确告诉 codex mini-spec 已被对齐修改过，避免它发现"plan 12 项 vs spec 13 项"伪 finding。
3. **scope 选 branch --base main**：与第二次 fresh loop 一致；让 codex 看完整 working-tree（plan + spec + 对齐 task-detail + 4 个 loop log）的故事。
4. **max_iterations 默认 5**：第二次跑 7 轮且 trajectory 1 high/round 不收敛到 approve，揭示 codex single-point review 在 4459 行 plan 上 noise floor 持续。第三次默认 5 轮 + accept-and-stop 是合理配方，避免为追 approve verdict 与 codex quirk 赛跑。
5. **不要先 commit**：当前 working tree 5 个 untracked + 2 modified 文件均与 M3 workstream 强相关，commit slicing 由用户最终决定（见 fresh loop log 末尾的 commit message 建议）。本 handoff 不主动 commit。

## Next steps (ordered by priority)

1. **新会话第一动作：读 Required reading + 读 mini-spec / plan 顶层 + alignment task-detail，理解三次 loop 的全貌**。Done when: 能口述 R1~R7 fresh loop 的 7 个 finding 区域 + alignment 工作的 6 项调整 + 当前 plan/spec 的版本号一致状态。
2. **启动 codex-review-loop skill**（slug: `phase-0-m3-plan-aligned-review`）。用户的 message 指定了 review 对象 + 基础 spec，可以直接进 Phase 0 preflight。Done when: codex-companion runtime 定位 + setup 健康 + Goal Contract 写到 `docs/Task-detail/codex-loop-phase-0-m3-plan-aligned-review.md` 并向用户确认开跑。
3. **Goal Contract 关键字段**：
   - In-scope: `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`
   - Out-of-scope: mini-spec 本体（已对齐到 plan，不再动）、真实 .swift 代码、4 个历史 loop log
   - DoD: approve OR 残留全 low+stable OR 跨连续 2 轮净新增 accept=0
   - max_iterations: 5（默认；与第二次 trajectory 对照后用户可决定 extend）
   - Reference Documents 必填：列出 mini-spec / 真实代码目录 / CLAUDE.md / 上一次 alignment task-detail
4. **focus 块 round 1 内容**：明确告诉 codex 这是第三次 loop，前两次产出已落地（plan 4459 行），mini-spec 也已与 plan 对齐过；让 codex 在剩余 plan 区域找漏洞而不是重复 R1~R7 已 fix 的问题。可在 prior_round_decisions 块（round 1 留空）的注释里说明这点，或在 design_decisions_to_evaluate 块里列出"alignment 工作 6 项调整是否完整"作为可被 challenge 的设计决策。
5. **每轮 fix 落地前必跑真实代码 grep 验证**：第二次 loop 的高质量来自每轮先 grep / Read 真实代码再 accept，避免 plan 凭印象写。

## Known traps / do not touch

- **mini-spec 已被对齐修改**，状态不再是 R10 approve 锁定。新 loop 在 codex 提示中要明确这点，否则 codex 会因为"mini-spec frontmatter 写了 R10 approve 但内容已被改"产生伪 finding。建议在 Reference Documents 注释里写一句"mini-spec 已与 plan 同步对齐（见 alignment task-detail），本 loop 仍视 mini-spec 为参考不在 in-scope".
- **plan 内已含两次 review-fix 的注解**（"R1~R9 walking back" / "audit-fix 2026-04-2x" / "Round-1 R1.1 修订" / ... / "Round-7 R7.1 修订"），全是历史标注，**不是 prior_round_decisions**。新 loop 的 prior_round_decisions 块只追踪本 loop 自己的轮次决议，第一轮该字段留空。
- **codex-review-loop skill 强制不主动 git commit**：所有 fix 累积在 working tree；commit slicing 由用户在 loop 终止后决定。
- **gate 编号约定**：plan §J0 现有 grep gate 编号 1/2/3/4/5/7/8/9（编号 6 是 R8 walking back 删除的历史槽位特意跳过；R7.1 加的 grep 兜底是手工跑命令，未占编号）。新 loop 如要加 gate，从 10 开始，不要复用 6。
- **plan 内多个 v0.2 文档引用是合法**（指 v0.2 版本号语义而非 tag 字符串），别因为 R6+R7 修过 release tag 就以为所有 v0.2 都要改。R7.1 的 grep pattern `\bv0\.2\b` 边界 + 命令前缀限定 是有意为之的精确 pattern。
- **Task 14/15 编号**：fresh loop R3.1 修订时把 §M3.5 §4.2.5 原 Step 13/14 顺移到 14/15（因为新加了 Step 13 切 provider 验收）；alignment 工作中可能又有调整，新 loop 看 plan 时以最终行号为准。
- **R7 verdict 仍是 needs-attention 不是 approve**——第二次 loop trajectory 揭示在 4459 行大文档上 codex 不收敛是性质而非缺陷；第三次 loop 用户应有同样心理预期，不要为追 approve 死磕。

## Required reading (in order)

1. `CLAUDE.md`（项目顶层规范、Swift 6 严格并发约定、错误模型 / 无自由日志规范）
2. `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（M3 mini-spec；理解 D-26 ~ D-31 决议；含 alignment 修订）
3. `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（review 对象 plan 主体 4459 行；按 §M3.0~§M3.6 逐 task 通读；含两次 review-fix + alignment 修订）
4. `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`（最近对齐工作总结，6 项 ToDoList 全 done；理解最近一段会话改了什么）
5. `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`（第二次 loop log；R1~R7 决议表 + final summary + commit slicing 建议）
6. `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`（第一次 loop log；R1~R9 + audit-fix；用于避免新 loop 重复发现已 fix 问题）
7. `~/.claude/skills/codex-review-loop/SKILL.md`（review-loop skill 流程；前两次 loop 的 trace 已经把工作流走过两次，新 loop 直接按 skill workflow 跑）

## Minor changes (side work outside the main thread)

- `docs/Task_history.md`: 已加入 alignment task 索引（modified）
- alignment task-detail 文件本身（`2026-04-29-phase-0-m3-plan-spec-alignment.md`）记录了具体改动逻辑，新 loop 不需要再重复这部分背景，只需要把"对齐已完成"作为 baseline。
