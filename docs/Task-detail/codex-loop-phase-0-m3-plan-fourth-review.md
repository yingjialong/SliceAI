---
slug: phase-0-m3-plan-fourth-review
created: 2026-04-29T23:35:00+08:00
last_updated: 2026-04-30T01:25:00+08:00
status: terminating-converged
total_rounds: 3
max_iterations: 5
---

# Codex Review Loop — phase-0/m3 plan 第四次 codex review-fix

## Goal Contract

**Task.** 对 `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（M3 v1→v2 类型切换实施计划，~4730 行；已经过 3 次 codex review loop + alignment 工作累积 fix）执行**第四次** codex 对抗式 review-fix 循环。**Why**：用户在第三次 loop（slug `phase-0-m3-plan-aligned-review`）R7 cap 时没选标准 termination 4 选项（accept-and-stop / extend / pause-rescope / abort），而是选择"重新开始 5 轮 review-fix"——按 fresh restart 模式新开 loop，不接前三次 loop 的 prior_round_decisions（避免 prior decisions block 太长稀释 codex 注意力 + 给 codex fresh 视角）。本 loop 验证：plan 在前三次 loop + alignment 共累积 ~30+ fix 之后，是否已可作为 implementation-ready 文档进入 §M3.0 ~ §M3.6 实施。

**Why this is the fourth codex-review-loop on the same plan**：
1. 第一次（implementation-plan loop，2026-04-28）：R1~R9 codex review + 用户主导 audit-fix pass（13 项 substantive issue）；log: `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`。
2. 第二次（fresh review loop，2026-04-28）：R1~R7 fresh，trajectory 1/1/1/1/1/1/1 high 全 accept；log: `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`；status `converged-with-disagreement`（用户 R7 accept-and-stop）。
3. 第二次结束后（2026-04-29）：用户主导 plan/spec 口径对齐工作（13 项手工回归 / SemVer v0.2.0 / Task 1-3 4 关 CI gate / 多行命令 subshell / mktemp 备份 / M3.1 C+D 原子化 6 项），log: `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`。
4. 第三次（aligned review loop，2026-04-29）：R1~R7（5 base + 2 extended），trajectory 1h / 1h+2m / 1h / 1h / 1h / 1m partial-doc / 1h，9 findings = 8 accept+fix + 1 partial doc-only；log: `docs/Task-detail/codex-loop-phase-0-m3-plan-aligned-review.md`；status `terminated-user-requested-restart`。
5. **本次 = 第四次 codex-review-loop**：用户要求 fresh restart 5 轮，在前三次 loop + alignment 累积 plan 状态上做 review。

## This session

- **Window**: 2026-04-29 23:35~（本 loop 启动；同一 Claude Code session 续接第三次 loop 的 termination 决策）
- **What got done**: 起草 Goal Contract；前三次 loop + alignment 工作的 plan/spec 修订状态作为本 loop 起点 baseline
- **Predecessor**: `docs/Task-detail/codex-loop-phase-0-m3-plan-aligned-review.md`（第三次 loop log，status terminated-user-requested-restart）

## Current code state

- Branch: `feature/phase-0-m3-switch-to-v2`
- Recent relevant commits (only 1 ahead of main):
  - `2e1019b` docs(phase-0/m3): seed M3 mini-spec (user R1 approved Q1/Q2/Q3)
- Uncommitted changes:
  - `docs/Task_history.md`: modified — alignment task 索引
  - `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`: modified — R1~R10 codex review + R11 alignment 累积修订
  - `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`: untracked — alignment 工作 task-detail
  - `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`: untracked — 第一次 loop log
  - `docs/Task-detail/codex-loop-phase-0-m3-mini-spec.md`: untracked — mini-spec review loop log
  - `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`: untracked — 第二次 loop log
  - `docs/Task-detail/codex-loop-phase-0-m3-plan-aligned-review.md`: untracked — 第三次 loop log（含 R1~R7 + final summary + commit slicing 建议）
  - `docs/handoffs/2026-04-29-1720-phase-0-m3-plan-aligned-review.md`: untracked — workstream handoff
  - `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`: untracked — plan 主体（~4730 行；含三次 loop + alignment + 本 loop 待加修订）

## Goal Contract

**Task.** 对 plan 做第四次 codex 对抗式 review-fix。**Why**：用户在第三次 loop R7 cap 时选 user-requested-restart，本 loop 在前三次 loop + alignment 累积 plan 状态上做 review；不接前三次 prior_round_decisions（fresh 视角让 codex 不被 prior history 锚定）；目标是验证 plan 是否真的 implementation-ready 或继续暴露 R1-R7 未触及区域（§M3.0 Task 7-11 5 步 rename pass / §M3.1 Sub-step C-D Task 3-5 装配 / §M3.2 Task 6 触发链验收 / §M3.3 Task 13 4 启动场景 / §M3.4 Task 14 grep validation / §J0 早期 gate 1-5/7）的真实漏洞。

**Reference Documents.** Codex should read these for full context.
- Spec / motivation: `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（M3 mini-spec；R10=approve + R11=alignment；含 D-26 ~ D-31 决议；本 loop 不动 mini-spec）
- Implementation plan (review target): `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体 ~4730 行；本 loop 唯一可改文件）
- Alignment work summary: `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`（最近 alignment 6 项调整 baseline）
- **Prior third-loop log (close summary)**: `docs/Task-detail/codex-loop-phase-0-m3-plan-aligned-review.md`（第三次 loop R1~R7 决议表 + final summary + Findings 区域分布表；**本 loop codex 必读以避免重复发现 R1~R7 已 fix 区域**）
- Prior fresh-review log: `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`（第二次 loop R1~R7 决议；用于避免重复发现）
- Prior implementation-plan log: `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`（第一次 loop R1~R9 + audit-fix；同上目的）
- Real code (source of truth): `SliceAIKit/Sources/SliceCore/`, `SliceAIKit/Sources/Orchestration/`, `SliceAIKit/Sources/SelectionCapture/`, `SliceAIKit/Sources/Permissions/`, `SliceAIKit/Sources/Windowing/`, `SliceAIKit/Sources/SettingsUI/`, `SliceAIApp/AppContainer.swift`, `SliceAIApp/AppDelegate.swift`
- CI / release toolchain: `.github/workflows/ci.yml`, `.github/workflows/release.yml`, `scripts/build-dmg.sh`
- Project README: `CLAUDE.md`

> **Note for Codex on prior loops' fix coverage**：前三次 loop + alignment 累积 ~30+ fix 已 landed plan，覆盖区域：§M3.5 Step 4 (R1.1)、§F3 ToolEditorView (R2.1)、§Task 2 ci.yml gate (R2.2)、§Task 16 Step 10/13/13.5 release (R2.3+R7.1)、§Iteration C ExecutionEventConsumer + Step C1.4 caseName helper (R3.1+R4.1)、§Task 1 Step 5 (R5.1)、§Iteration A OutputDispatcher loggedInvocations (R6.1 partial doc-only)、§J0 gate 8/9/10/11；以及 fresh loop R1~R7 + alignment 6 项 + impl loop R1~R9 + audit-fix 13 项的修订（详见各 loop log final summary 区域分布表）。**本 loop 优先关注前三次未触及的 plan 区域**（见 design decisions），避免重复发现已 fix 区域。

**In-scope.**
- `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（唯一可被本 loop 修改的文件）

**Out-of-scope (won't touch even if Codex flags).**
- `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（mini-spec；本 loop reference-only，与 plan 矛盾时 plan 必须 converge 到 mini-spec 或真实代码）
- `docs/Task-detail/codex-loop-phase-0-m3-plan-aligned-review.md`（第三次 loop log，历史不可改）
- `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`（第二次 loop log，历史不可改）
- `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`（第一次 loop log，历史不可改）
- `docs/Task-detail/codex-loop-phase-0-m3-mini-spec.md`（mini-spec 自身 review loop log，历史不可改）
- `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`（alignment task-detail，历史不可改）
- `docs/handoffs/2026-04-29-1720-phase-0-m3-plan-aligned-review.md`（workstream handoff，历史不可改）
- 任何真实 `.swift` / `.pbxproj` / `Tests` 代码（plan review 不写代码；codex 提议改代码视作 [ADVISORY]）
- `.github/workflows/*` / `scripts/*` 真实文件（仅作为对照引用；plan 内引用错才改 plan）
- 其他 `docs/` 下文件（README.md / CLAUDE.md / Task_history.md 等）

**Definition of Done.** 任一条件满足即可退出循环：

1. Codex 返回 `approve` verdict（无 blocker；plan 可直接进入 implementation 阶段）；OR
2. Codex 返回 `needs-attention` 但所有残留 finding 都是 `low` severity AND 都 `reject`-with-stable-reason 或 `defer`（双方各自陈述完毕，再跑一轮也不会改变结论）；OR
3. 跨连续 2 轮所有 `accept`-d finding 已 fix AND 当前轮 0 新 accept finding（净增缺陷率为零）。

**Severity caps.** 任一轮触发以下任意条件 → 暂停循环 + AskUserQuestion：

- `critical > 3`，OR
- `(critical + high) > 5`，OR
- `total findings > 8`

**Max iterations.** 5（默认；用户可在 round cap 触达时延长）

**Review scope.** branch (--base main)
（理由：worktree 1 commit ahead of main 含 mini-spec seed；plan / 5 个 task-detail / handoff / 6 份 untracked + 2 modified 全是 working tree 累积；branch scope 让 codex 看完整故事——前三次 loop 全部修订 + alignment 修订 + 本 loop 当前 plan 状态都可见。）

## Design decisions summary（round 1 注入 codex 的 ≤3 条）

按 skill `references/codex-focus-prompt.md` 硬性 max 3 条规则，本 loop 第一轮注入以下 3 条**前三次 loop 未触及 plan 区域**作为 codex 优先关注点（每条都标注真实代码 / spec 锚点让 codex 直接 grep 验证）：

1. **§M3.0 5 步 rename pass（Task 7-11）的实施顺序与 commit 边界**——Task 7 (M3.0 Step 1 caller switch)、Task 8 (Step 2 v1 类型族删除)、Task 9 (Step 3 V2*→canonical name rename)、Task 10 (Step 4 PresentationMode→DisplayMode rename)、Task 11 (Step 5 SelectionOrigin→SelectionSource rename)。Task 7 commit 单元已累积 R2.1+R3.1+R4.1+R6.1 多次修订（§F3 ToolEditorView + §Iteration C ExecutionEventConsumer + §Iteration A OutputDispatcher loggedInvocations）；Task 7 commit message 模板 / Exit DoD / Step J1-J4 是否同步反映这些累积修订？Task 8-11 各 step 的 commit 边界 / 临时编译态 / `git mv` 命令是否与真实 V2*/PresentationMode/SelectionOrigin 类型对齐（避免 rename 期间命名空间冲突 / 命令时序错位）？plan 内任何 rename 顺序假设违反 v1 删除→V2* rename→子枚举 rename 的依赖关系？
2. **§M3.1 Sub-step C-D 装配链路（Task 3-5）的伪代码 vs 真实代码 alignment**——Task 3 (M3.1.C-1 InvocationGate + ResultPanelWindowSinkAdapter 创建)、Task 4 (M3.1.C AppContainer additive 装配)、Task 5 (M3.1.D AppDelegate async bootstrap startupError UX)。这些 task 的伪代码（class 签名 / init 参数 / 状态机 / actor 边界）是否与 `SliceAIApp/AppContainer.swift` + `SliceAIApp/AppDelegate.swift` + `SliceAIKit/Sources/Orchestration/Output/{InvocationGate,OutputDispatcher,WindowSinkProtocol}.swift` 真实代码完全对齐？mini-spec D-27 装配表 10 个依赖（含 mcpClient / skillRegistry / permissionBroker / contextProviderRegistry / configStore / costAccounting / auditLog / providerResolver / outputDispatcher / executionEngine）的真实 init 签名 / 类型 / Sendable 约束是否与 plan 描述一致？M3.1 C+D 原子化（alignment R11 决议）在 §3.1.3 / §M3.1 Sub-step 表 / Exit DoD / commit 节点四处口径是否一致？
3. **§J0 早期 grep gate 1/2/3/4/5/7 的 pattern 与真实代码对齐**——前三次 loop 加了 gate 8/9/10/11，但 gate 1（exhaustive switch）/2（exhaustive enum）/3（InvocationGate setActive/clearActive 调用约束）/4（SliceError validationFailed 必带 String）/5（pbxproj 注册）/7（showCommandPalette triggerSource）的 grep pattern 是否与真实 SliceCore SliceError / Orchestration InvocationGate / AppDelegate showCommandPalette / 新加 ResultPanelWindowSinkAdapter / ExecutionEventConsumer.swift 路径完全对齐？是否有 grep pattern 因前三次 loop 的 fix 引入新文件 / 改变 method 名 而错位？

## Loop strategy 备忘（不发给 codex）

- 本 loop 是**第四次** codex-review-loop on plan，**不接**前三次 prior_round_decisions（fresh restart 用户决策）。Round 1 prior_round_decisions 留空。
- plan 文件本身已含三次 loop 的修订注解 + alignment 修订注解（"Round-N R*.X 修订（2026-04-28 / 2026-04-29 本 loop = M3 plan 第 N 次 codex review）"）——这是 plan 文件固有内容，不是 prior_round_decisions。新 loop 的 R*.X 用 "本 loop = M3 plan 第四次 codex review" disambiguator + 时间戳避免与第三次 R*.X 字面冲突（两次都是 2026-04-29 日期）。
- skill 新版 review_constraints 强制 codex "Report ALL independent same-severity material findings in this round"——一次性返回所有同 severity 的 root-cause 漏洞，避免每轮 trickle 1 finding 不收敛模式。本 loop 期望几轮内收敛到 approve 或 stable-low（vs 第三次 loop 7 轮仍 1 high/round noise floor 模式）。
- 每轮 fix 落地前**必跑**真实代码 grep / Read 验证，避免 plan 凭印象写。前三次 loop 的高质量 finding 都来自代码对照而非凭空。
- gate 编号约定：plan §J0 现有 grep gate 编号 1/2/3/4/5/7/8/9/10/11（编号 6 是 fresh loop R8 walking back 删除的历史槽位特意跳过；前三次 loop 加了 8/9/10/11）。本 loop 如要加 gate，从 12 开始，不要复用 6 / 8-11。
- mini-spec D-30b（loggedInvocations Set<UUID> 不清理）是已知 v0.2 KISS 妥协边界，第三次 loop R6 已 partial-reject codex 推 "加 cleanup 协议"——本 loop 不重复挑战该决议；如 codex round 1 仍提该 finding，accept doc warning 已落地的事实，reject logic over-reach。

---

## Rounds

### Round 1 — 2026-04-30 00:00~00:25 (≈25 min)

**Codex verdict.** `needs-attention`（2 findings, both high）

**Findings.**

| # | Severity | Region | Title (codex 概述) |
|---|---|---|---|
| F1.1 | high | plan:91-125 (§Task 1 Step 1) | Task 1 Step 1 新单测用 Swift Testing `@Test` / `#expect` 风格，与既有 `V2ConfigurationStoreTests.swift`（XCTest 风格 + `XCTestCase`）不兼容；implementer 复制粘贴会 compile-fail 或被 swift test 静默跳过，Task 1 TDD 链路（Step 2 验证失败 → Step 3 修 load() → Step 4 验证通过）整段失效。 |
| F2.1 | high | plan:2841-2890 (§Iteration H Step H1 子步骤 3) | Iteration H Step H1 子步骤 3 示例代码写 `SettingsViewModel(store: configStore, keychain: keychain)`，但子步骤 3 完成时 v1 局部 `configStore` 已删除 + v2 `v2ConfigStore` 还没改名，`configStore` symbol 在子步骤 3 → 4 之间不存在 → swift build 报 `cannot find 'configStore' in scope`，整个 H1 步骤分裂顺序失效。 |

**Decision ledger.**

| # | Decision | Reason | Action |
|---|---|---|---|
| F1.1 | accept | 真实 `V2ConfigurationStoreTests.swift:1` `import XCTest` + line 86-95 既有 14 个 `func test_*` 全是 `XCTAssertEqual` 风格；plan 用 Swift Testing 与文件其余测试不兼容；codex 报的 root cause 准确，且 plan 内已声称"既有 test 不需修改"，则新增 test 必须保持 XCTest 同模式才能 compile。 | 改写 §Task 1 Files 描述 + Step 1 整段代码块为 XCTest 风格（`func test_load_withNeither_writesDefaultToV2Path() async throws` + `XCTAssertFalse` / `XCTAssertTrue` / `XCTAssertEqual`），复用既有 `tempDir` setUp/tearDown fixture（不再手动 createDirectory + defer removeItem）；加 R1.1 修订背景注释 + 末尾 note 解释既有 test 与新 test 的覆盖差。 |
| F2.1 | accept | 真实 `SliceAIApp/AppContainer.swift:26 / 51 / 95` v1 baseline `let configStore: FileConfigurationStore` 已存在；plan 在 Iteration H 子步骤 1 删 v1 字段 + 子步骤 2 rename `v2ConfigStore`→`configStore` 字段，但**没有同步更新 bootstrap() 局部变量的 rename 顺序**——子步骤 3 删除 v1 装配局部块时若仍引用 `configStore` 名称，编译期会报找不到 symbol；codex 找到 ordering bug 准确。 | 改写 §Iteration H Step H1 子步骤 3 把 `SettingsViewModel(store: configStore, ...)` 改为 `SettingsViewModel(store: v2ConfigStore, ...)`（加 R1 修订内联注释解释顺序约束）；扩展子步骤 4 加显式 rename 表（6 行覆盖：声明 / current() 触发 / SettingsViewModel 装配 / themeManager.onModeChange 闭包内 / `return AppContainer(...)` 主 init / 任何残留），并加 grep gate `grep -n "v2ConfigStore" SliceAIApp/AppContainer.swift` Expected 0 命中验证。 |

**Drift status.** in-scope（仅修改 `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md` 的 §Task 1 + §Iteration H 两处；未触及 mini-spec / 真实代码 / 其他 task-detail）。

**Real-code anchors verified.**

- F1.1：`SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift:1` `import XCTest` + line 5 `final class V2ConfigurationStoreTests: XCTestCase`；line 86-95 `test_load_withNeither_returnsDefaultV2` 用 `XCTAssertEqual(cfg.schemaVersion, 2)` + `XCTAssertEqual(cfg.tools.count, 4)`。
- F2.1：`SliceAIApp/AppContainer.swift:26 let configStore: FileConfigurationStore`（v1 类字段）+ line 51 `configStore = FileConfigurationStore(...)`（init 装配）+ line 95 `settingsViewModel = SettingsViewModel(store: configStore, keychain: keychain)`（v1 装配 caller）；plan §Task 4 line 815-938 bootstrap() 是 Task 7 起点 baseline，line 856 `SettingsViewModel(store: configStore, keychain: keychain)` 仍引用 v1，line 868 同时存在 `let v2ConfigStore = V2ConfigurationStore(...)` 平行装配，两者并存到 Iteration H。

**Stagnation gauge.** N/A (round 1)

**Severity caps.** 未触发（critical 0 / critical+high = 2 / total = 2，三条阈值均未达上限 3 / 5 / 8）

**New skill prompt observation.** Round 1 的 2 finding 同时返回印证 `references/codex-focus-prompt.md` 新版 review_constraints "Report ALL independent same-severity material findings in this round" 修订生效——前三次 loop 普遍 1 high/round trickle 模式（trajectory 1/1/1/1/1/1/1），本 loop 首轮直接 2 high；如后续轮次仍维持同 severity 多 finding，几轮内可收敛到 approve 或 stable-low。

**Status.** continue → Round 2

**Round 2 prior_round_decisions block（Round 2 注入 codex 的 prior 摘要）.**

- R1.1 = accept-and-fixed (high, plan §Task 1 Step 1)：新单测改写为 XCTest 风格（与既有 `V2ConfigurationStoreTests.swift` 14 个测试同模式）；复用 `tempDir` fixture；既有 `test_load_withNeither_returnsDefaultV2`（line 86-95）保持原状不动。
- R1.2 = accept-and-fixed (high, plan §Iteration H Step H1)：子步骤 3 改 `SettingsViewModel(store:)` 引用为 `v2ConfigStore`；子步骤 4 加显式 rename 表（6 行 + grep gate `v2ConfigStore` Expected 0 命中）。

### Round 2 — 2026-04-30 00:30~00:55 (≈25 min)

**Codex verdict.** `needs-attention`（5 findings：1 critical + 4 high；**全部锚定 mini-spec 行号，0 条命中 plan 行号**）。

**Findings.**

| # | Codex Severity | Codex Region (literal) | In-scope? | Title (codex 概述) |
|---|---|---|---|---|
| F2.1 | critical | mini-spec:104-133 | **out-of-scope** | 删除 SelectionPayload 会切断触发上下文并让 AppDelegate 方案不可编译。SelectionSnapshot 字段不含 appBundleID/appName/url/screenPoint/timestamp，按 mini-spec "delete SelectionPayload + AppDelegate 从 snapshot 构造 ExecutionSeed" 实施会编译失败/丢上下文。 |
| F2.2 | high | mini-spec:259-271 | **out-of-scope** | D-27 ExecutionEngine 装配表只列 8 deps + clock（用 PermissionGraph()/DefaultPermissionBroker/ContextProviderRegistry.builtin()/CostAccounting(dbPath:) 构造），与真实 init 10 deps（无 clock，含 mcpClient/skillRegistry/output）不一致；按表落地 AppContainer 编译失败。 |
| F2.3 | high | mini-spec:463-474 | **out-of-scope** | mini-spec 把 execute 写成 AsyncStream<ExecutionEvent> 并消费 .streamChunk/.completed/.failed(report,error)/.permissionDenied/.invocationCompleted；真实 execute 返回 AsyncThrowingStream，case 是 .llmChunk/.finished(report:)/.failed(SliceError)/.notImplemented/.permissionWouldBeRequested。按 mini-spec 写 EventConsumer 编译失败。 |
| F2.4 | high | mini-spec:444-453 | **out-of-scope** | Phase 0 "Settings 零行为变化" 与 D-29 "tool.variables 推到 Phase 1 + 不暴露 DisplayMode 选择器" 自相矛盾；ToolEditorView 已有 variables 卡片 + DisplayMode Picker，按 D-29 隐藏会丢用户功能。 |
| F2.5 | high | mini-spec:204-216 | **out-of-scope** | mini-spec 称 first-launch 写 default 到 config-v2.json + DoD 列 v2 文件实际生成；真实 V2ConfigurationStore.load() both-missing 分支只返回 default 不写盘；DoD 永远不达。 |

**Decision ledger.**

| # | Decision | Reason | Action |
|---|---|---|---|
| F2.1 | reject (out-of-scope) | Goal Contract 显式列 mini-spec 为 out-of-scope（"plan 与 mini-spec 不一致 → flag plan 不符 mini-spec，不 flag mini-spec 自身"）；codex 锚点 mini-spec:104-133 不在 plan 范围。**关键反验证**：plan 实际并未删除 SelectionPayload——`grep -n "SelectionPayload" docs/superpowers/plans/*.md` 返回 plan §Iteration B (line 1255+) 显式 **保留** SelectionPayload，新增 `toExecutionSeed` extension + `Source.toSelectionOrigin` mapping，**正是 codex Recommendation 推荐的 adapter pattern**（"M3 保留 SelectionPayload 作为触发层 envelope，新增单一 adapter/extension 把 SelectionPayload 映射为 SelectionSnapshot + AppSnapshot + screenAnchor + timestamp"）。Plan line 34 "不再回看 master todolist 的 '删 SelectionPayload' 等旧描述——mini-spec §2.2 + D-28 + D-29 已显式覆盖"明确防御此误读。Plan 已收敛。 | 不修改 plan。 |
| F2.2 | reject (out-of-scope) | 同上 mini-spec out-of-scope。**关键反验证**：plan §Task 4 line 906-916 实际 ExecutionEngine 装配代码使用 10 deps（contextCollector / permissionBroker / permissionGraph / providerResolver / promptExecutor / mcpClient / skillRegistry / costAccounting / auditLog / output），与真实 `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift:68-79` init 签名 100% 吻合（亲查代码已确认）；plan 未引用 mini-spec D-27 8 deps + clock 表。Plan 已收敛到真实代码。Mini-spec D-27 表是 mini-spec 自身 misalignment，与 plan implementation 无关。 | 不修改 plan。 |
| F2.3 | reject (out-of-scope) | 同上 mini-spec out-of-scope。**关键反验证**：`grep -n "AsyncStream<ExecutionEvent>\|streamChunk\|invocationCompleted\|permissionDenied" docs/superpowers/plans/*.md` 返回 0 命中——plan 完全没有引用 mini-spec 那 5 个错误 case 名。Plan §Iteration C Step C1.4 caseName helper（第三轮 R3.1+R4.1 修订）使用真实 `.llmChunk` / `.finished(report:)` / `.failed(SliceError)` / `.notImplemented` / `.permissionWouldBeRequested` 等 case。Plan 已收敛。 | 不修改 plan。 |
| F2.4 | reject (out-of-scope) | 同上 mini-spec out-of-scope（Phase 0 scope decision 由 mini-spec D-29 + 用户 alignment 工作冻结）。**关键反验证**：plan §F3 Step F2（line 2449+，第三轮 R2.1 R1.1 修订）显式扩展 binding 表至 9 个字段（**含 providerId / displayMode**），并保留 ToolEditorView variables 卡片 + DisplayMode Picker UI（line 2284 `displayMode: .window` default + Step F2 Picker 改造）。Plan 实际 implementation 与 codex 担忧的"隐藏功能"相反——plan 保留 v1 已暴露的 UI，绑定到 V2Tool 等价字段。Mini-spec D-29 措辞含混（"variables 推到 Phase 1" vs "不暴露 DisplayMode 选择器"），但 plan 第三轮已基于真实代码做出"保留 UI"决策。Plan 已收敛。 | 不修改 plan。 |
| F2.5 | reject (codex 漏读 plan) | 同上 mini-spec out-of-scope。**关键反验证**：plan §Task 1（line 83-183）整个任务 = M3.1 Sub-step A，即 V2ConfigurationStore.load() both-missing 分支加 `try writeV2(defaultCfg)` + 新增 `test_load_withNeither_writesDefaultToV2Path` 验证。R1.1 刚刚修订过 Step 1 测试风格（XCTest + tempDir fixture）。Codex 只读了 V2ConfigurationStore.swift 当前状态（确实没写盘），完全没读 plan §Task 1（这正是修复路径）。Plan 已是 mini-spec ↔ 真实代码 mismatch 的 fix 本身，本 finding 是 codex 误判。 | 不修改 plan。 |

**Drift status.** in-scope（**0 plan 修改**；本 round 仅日志条目落盘）。

**Real-code anchors verified.**

- F2.1 反验证：`grep -n "SelectionPayload" docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md` 命中 plan line 34 / 1255 / 1584 / 1593 (`public extension SelectionPayload`) / 3504 (envelope 字段说明) — plan 保留 SelectionPayload + 加 adapter，反向证明 codex Recommendation 已被 plan 采纳。
- F2.2 反验证：`SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift:28-79` 真实 init 10 deps（actor + 9 stored property），无 clock；plan §Task 4 line 906-916 装配 10 deps 命名一致。
- F2.3 反验证：`grep -n "AsyncStream<ExecutionEvent>\|streamChunk\|invocationCompleted\|permissionDenied" docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md` 返回 0 命中。
- F2.4 反验证：plan line 2449-2455 第三轮 R2.1 R1.1 修订背景注释 + line 2284 默认 `displayMode: .window` + Step F2 binding 表扩展至 9 字段含 displayMode/variables/providerId。
- F2.5 反验证：plan line 83 task title `V2ConfigurationStore.load both-missing 写盘 + 单测` + line 145 修改片段 `try writeV2(defaultCfg)` + Step 4 expected PASS。

**Stagnation gauge.** Round 2 vs Round 1：R1 = 2 high accept→fix；R2 = 5 finding 全 reject (out-of-scope)；**净增 in-scope 缺陷 = 0**；**累计已 fix in-scope 缺陷 = 2 (R1.1 + R1.2)**。这是 plan 已收敛到 R1 fix 之后，codex 找不到 in-scope 漏洞、转而 flag mini-spec 的强信号。

**Severity caps.** 未触发（critical 1 / critical+high 5 / total 5；全部 reject as out-of-scope，不计入 in-scope 缺陷统计；in-scope 缺陷 0 / 0 / 0 三阈值全部空载）。

**DoD assessment.**

- DoD #1 (codex approve)：未达——codex 给 needs-attention（基于 out-of-scope mini-spec issues）。
- DoD #2 (needs-attention 但残留 finding 全 low + reject/defer)：严格读不达——R2 残留 5 findings 是 high+critical 而非 low；放宽读（"out-of-scope reject 等价于不计入"）则达。
- **DoD #3 (跨连续 2 轮所有 accept-d finding 已 fix AND 当前轮 0 新 accept finding)**：**满足**——R1 的 R1.1 + R1.2 两条 accept 在 R1 当轮已 fix；R2 当轮 0 新 accept finding（全 reject）。R2 满足"净增缺陷率 0 + 历史 accept 全 fix"。

**Convergence signal.** Plan 已实质收敛到 implementation-ready：
1. R1 修订 2 个真实 plan-level 不可编译路径（Task 1 Step 1 测试风格 + Iteration H Step H1 顺序）。
2. R2 codex 用真实代码 grep 后无法在 plan 内定位新 in-scope 漏洞；只能转而 flag mini-spec（已被 Goal Contract 显式 out-of-scope）。
3. Codex 的 5 条 mini-spec 诊断对 plan 验收 **0 影响**——plan 在 Iteration B / Task 4 / Iteration C / F3 Step F2 / Task 1 五处已分别走在了正确路径（即 codex Recommendation 推荐方向），plan implementation 与 mini-spec 漂移之间 plan 已自洽。

**Status.** continue → Round 3（保险一轮：以 DoD #3 严格读"跨连续 2 轮"为锚——R2 是首次 0 净增，R3 若再次 0 净增 + 0 新 accept，则双重确认 plan 收敛；R3 用更紧的 focus prompt 强调 mini-spec 完全 out-of-scope，迫使 codex 要么 verdict=approve 要么 surface plan-level 真漏洞，避免 mini-spec 噪声占满 5 round budget）。

**Round 3 prior_round_decisions block（Round 3 注入 codex 的 prior 摘要）.**

- R1.1 = accept-and-fixed (high, plan §Task 1 Step 1)：XCTest 风格统一。
- R1.2 = accept-and-fixed (high, plan §Iteration H Step H1)：子步骤 3 引用顺序 + 子步骤 4 显式 rename 表 + grep gate。
- R2.1 = reject-out-of-scope (critical, mini-spec:104-133)：plan §Iteration B 已实现 SelectionPayload→ExecutionSeed adapter，与 codex Recommendation 一致。
- R2.2 = reject-out-of-scope (high, mini-spec:259-271)：plan §Task 4 line 906-916 装配 10 deps 与真实 ExecutionEngine init 100% 吻合。
- R2.3 = reject-out-of-scope (high, mini-spec:463-474)：plan 完全未引用 mini-spec 那 5 个虚假 ExecutionEvent case。
- R2.4 = reject-out-of-scope (high, mini-spec:444-453)：plan §F3 Step F2 显式保留 displayMode Picker + variables UI（V2Tool 字段映射）。
- R2.5 = reject-codex-misread (high, mini-spec:204-216)：plan §Task 1 即此 mismatch 的 fix 本身；codex 漏读 plan §Task 1。

> **Round 3 focus prompt 调整**：把"mini-spec 是 out-of-scope" 提到第 1 段开头并加粗；明确告诉 codex "如果你只能找到 mini-spec 行号的 finding，请 verdict=approve 并 finding=空"；给 plan-only 区域的暗示更具体（§M3.0 Task 7-11 / §M3.1 Sub-step C-D Task 3-5 / §J0 早期 grep gate）。

### Round 3 — 2026-04-30 00:58~01:20 (≈22 min)

**Codex verdict.** `needs-attention`（5 findings：1 critical + 4 high；**与 R2 完全相同的 5 条**——同样全部锚定 mini-spec 行号，0 条命中 plan 行号；codex 完全无视 focus prompt 里 "若只找到 mini-spec 锚点 → verdict=approve" 的强约束）。

**Findings.**

| # | Codex Severity | Codex Region (literal) | In-scope? | R2 vs R3 比对 |
|---|---|---|---|---|
| F3.1 | critical | mini-spec:189-195 (R2: 104-133) | **out-of-scope** | 与 R2 F2.1 内容相同（删 SelectionPayload）；行号不同因 codex 锚到了 mini-spec 内不同段；推荐 fix 也相同（保留 SelectionPayload + adapter）。 |
| F3.2 | high | mini-spec:259-271 (R2: 同) | **out-of-scope** | 与 R2 F2.2 完全相同（D-27 9 deps vs 真实 10 deps；这次 codex 写"9 个依赖"略不同于 R2 的"8 个依赖加 clock"，但根因相同）。 |
| F3.3 | high | mini-spec:463-474 (R2: 同) | **out-of-scope** | 与 R2 F2.3 完全相同（ExecutionEvent contract / AsyncStream vs AsyncThrowingStream）。 |
| F3.4 | high | mini-spec:446-453 (R2: 444-453) | **out-of-scope** | 与 R2 F2.4 完全相同（Settings 零变化 vs D-29 隐藏 variables/displayMode）。 |
| F3.5 | high | mini-spec:213-216 (R2: 204-216) | **out-of-scope** | 与 R2 F2.5 完全相同（first-launch 写盘 DoD vs V2ConfigurationStore.load 现状）。 |

**Decision ledger.**

| # | Decision | Reason | Action |
|---|---|---|---|
| F3.1 ~ F3.5 | reject (out-of-scope) | 同 R2 reject 理由：Goal Contract 显式列 mini-spec 为 out-of-scope；plan 已分别在 §Iteration B / §Task 4 / §Iteration C / §F3 Step F2 / §Task 1 五处实现 codex Recommendation 推荐的修法；plan 与 mini-spec 的不一致是 mini-spec 自身需要修，与 plan implementation 无关。R3 codex 锚点 + 推荐 + 内容均与 R2 重复，且 codex 无视 "若只能找到 mini-spec 锚点 → verdict=approve" 的强约束——说明 codex 在 plan 级别已找不到漏洞可报、强行返回 mini-spec 重复 finding 来满足 reviewer 模板的"必须返回 verdict ≠ approve" 默认行为。 | 不修改 plan。 |

**Drift status.** in-scope（**0 plan 修改**；本 round 仅日志条目落盘）。

**Real-code anchors verified.** 同 R2（plan §Iteration B / §Task 4 / §Iteration C / §F3 Step F2 / §Task 1 五处与真实代码 / mini-spec 已自洽）。R3 不重复贴。

**Stagnation gauge.** Round 3 vs Round 2：findings 内容完全重复（5 个 mini-spec 锚点 finding）；codex 行为表明它**已无法在 plan 内找到新 finding**，连尝试都没尝试——整轮 47 步 grep / sed / read（output line 1-63）全部用于探测真实代码 + mini-spec，对 plan 文件本身只在 R1 修订附近做了少量 grep。这是**plan 实质收敛的双重确认**信号。

**Severity caps.** 未触发（同 R2，全部 reject as out-of-scope；in-scope 缺陷统计 0/0/0）。

**DoD assessment.**

- DoD #1 (codex approve)：未达——codex 给 needs-attention（连续 R2+R3 两轮基于相同 out-of-scope mini-spec issues）。codex 的 reviewer 模板似乎不允许它在 "needs-attention" 模式下返回 0 finding，所以即使 plan 收敛它也会 fall back 到 mini-spec 重复 finding。
- DoD #2 (needs-attention 但残留 finding 全 low + reject/defer)：严格读不达（severity 是 high+critical 而非 low）；放宽读（"out-of-scope reject 等价于不计入"）则达。
- **DoD #3 (跨连续 2 轮所有 accept-d finding 已 fix AND 当前轮 0 新 accept finding)**：**严格满足**——R2: 0 新 accept；R3: 0 新 accept；R1 的 R1.1 + R1.2 两条 accept 已在 R1 当轮 fixed。R2 + R3 跨连续 2 轮 0 净增 in-scope 缺陷，DoD #3 严格读达成。

**Convergence signal.** Plan 已确认 implementation-ready：
1. R1 修订 2 个真实 plan-level 不可编译路径。
2. R2 codex 用真实代码 grep 后无法在 plan 内定位新 in-scope 漏洞；只能转而 flag mini-spec。
3. R3 codex 即使被显式告知"不要 flag mini-spec → 若只能找到则 verdict=approve"，仍重复返回与 R2 完全相同的 5 条 mini-spec finding——证明这是 codex 在 plan 已收敛后的**默认 fallback 行为**，不是 plan 真有 5 个 high 级别漏洞被 codex 反复发现。
4. DoD #3 严格满足（R2 + R3 跨连续 2 轮 0 净增）。

**Status.** **terminating-converged**（DoD #3 严格满足；plan implementation-ready）。

> **Mini-spec 缺陷作为 deferred 后续工作流**：codex R2 + R3 反复 flag 的 5 个 mini-spec 漂移（SelectionPayload deletion / D-27 9 vs 10 deps / D-30 ExecutionEvent contract / D-29 Settings 隐藏 / first-launch 写盘 DoD）虽然在本 loop out-of-scope，但**确实是 mini-spec 自身存在的真实漂移**——mini-spec 部分文字描述与真实代码 / plan implementation 不一致。Plan 已通过五处修订 implementation 走在了正确路径（与 codex Recommendation 一致），但 mini-spec 文档本身仍可在未来单独 review loop 中订正以保持 mini-spec ↔ 真实代码 / plan ↔ implementation 三者的文字一致性。这不阻塞本 loop 的 plan 收敛 / M3 implementation 启动。

---

## Final summary

**Loop result.** `terminating-converged`（DoD #3 严格满足；3 rounds / 5 max；plan implementation-ready）。

**Trajectory.**

| Round | Codex verdict | Findings (sev) | In-scope decisions | Plan modified? | 净增 in-scope 缺陷 |
|---|---|---|---|---|---|
| R1 (00:00~00:25) | needs-attention | 2 high | 2 accept-fixed (R1.1 + R1.2) | yes (§Task 1 Step 1 + §Iteration H Step H1) | -2 (净修复 2 条) |
| R2 (00:30~00:55) | needs-attention | 1 critical + 4 high (全 mini-spec) | 5 reject-out-of-scope | no | 0 |
| R3 (00:58~01:20) | needs-attention | 1 critical + 4 high (与 R2 完全相同) | 5 reject-out-of-scope | no | 0 |

**Convergence pattern.**
- R1 一次性返回 2 个真 plan-level high 不可编译漏洞（验证 skill 新版 prompt "Report ALL same-severity findings" 修订生效）。
- R2 + R3 codex 在 plan 级别找不到漏洞，回退到固定 5 条 mini-spec 锚点 finding（行号微移内容相同），无视 R3 focus prompt 里 "若只能 found mini-spec → verdict=approve" 的强约束——证明这是 codex reviewer 模板默认 fallback 行为，不是 plan 真漏洞反复被发现。

**Region distribution（in-scope decisions only）.**

| Region | R1 修订 | R2 | R3 | 累积 |
|---|---|---|---|---|
| §Task 1 Step 1 | R1.1 (XCTest 风格) | — | — | 1 fix |
| §Iteration H Step H1 子步骤 3-4 | R1.2 (rename ordering + 显式 rename 表 + grep gate) | — | — | 1 fix |
| §M3.0 5 步 rename pass (Task 7-11) | — | 0 | 0 | 已收敛 |
| §M3.1 Sub-step C-D (Task 3-5) | — | 0 | 0 | 已收敛 |
| §J0 早期 grep gate 1-5/7 | — | 0 | 0 | 已收敛 |

**Plan-level cumulative status (4 loops + alignment 共 30+ fix landed)：**
- 第一次 loop (impl-plan)：R1~R9 + audit-fix 13 项
- 第二次 loop (fresh-review)：R1~R7 + alignment 6 项
- 第三次 loop (aligned-review)：R1~R7 (5 base + 2 extended) = 8 accept-fix + 1 partial doc-only = 9 决议 / 8 fix landed
- **第四次 loop (本 loop)**：R1 = 2 accept-fix；R2 + R3 = 5+5 reject-out-of-scope = **2 fix landed + 0 in-scope 残留**

**Out-of-scope deferred concerns（mini-spec 漂移，留待未来单独 mini-spec review loop）.**

| codex finding (R2/R3) | mini-spec 行 | 内容 | 当前 plan 已采纳的对应 fix（codex Recommendation 方向） |
|---|---|---|---|
| F2.1 / F3.1 critical | 104-133 / 189-195 | 删 SelectionPayload 会失上下文 | plan §Iteration B (line 1255+) 保留 SelectionPayload + 加 toExecutionSeed extension |
| F2.2 / F3.2 high | 259-271 | D-27 装配表 9 deps + clock vs 真实 10 deps | plan §Task 4 line 906-916 装配 10 deps 与真实 init 100% 吻合 |
| F2.3 / F3.3 high | 463-474 | ExecutionEvent contract AsyncStream + 错误 case 名 | plan §Iteration C Step C1.4 caseName helper 用真实 case (.llmChunk / .finished / .failed / .notImplemented / .permissionWouldBeRequested) |
| F2.4 / F3.4 high | 444-453 / 446-453 | Settings 零变化 vs D-29 隐藏 variables/displayMode | plan §F3 Step F2 (line 2449+) 保留 displayMode Picker + variables UI 绑定 V2Tool 等价字段 |
| F2.5 / F3.5 high | 204-216 / 213-216 | first-launch 写盘 DoD 不可达 | plan §Task 1 (line 83-183) 即此 mismatch 的 fix 本身（V2ConfigurationStore.load both-missing 加 try writeV2(default) + 单测） |

**Recommendation to user.**

1. **本 loop 可终止**——DoD #3 严格满足，plan 已 implementation-ready，可直接进入 M3.1 ~ M3.6 实施。
2. **Mini-spec 单独 review loop（可选）**——若希望保持 mini-spec ↔ 真实代码 / plan ↔ implementation 三者文字一致，可在另一个 review session 内对 mini-spec 跑 codex review loop（slug 建议 `phase-0-m3-mini-spec-second-review`）订正 5 处漂移。**这不阻塞本 loop 收敛 / M3 实施启动**。
3. **Commit slicing 建议**——本 loop R1 的 2 处 plan 修订（§Task 1 Step 1 XCTest + §Iteration H Step H1 rename ordering）+ 第三次 loop 9 处修订 + alignment 6 处修订 + 第二次 loop 修订 + 第一次 loop 修订 = 累积一组 plan 文档 fix。建议作为单一 docs commit（subject: `docs(phase-0/m3): converge implementation plan via 4 codex review loops + alignment`）落地，不必按 round 切分。第三次 loop final summary 已给出 Option A "single commit" 详细 commit message 模板，可直接复用。
