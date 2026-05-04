---
slug: phase-0-m3-plan-fresh-review
created: 2026-04-28T16:10:13Z
last_updated: 2026-04-28T16:10:13Z
status: converged-with-disagreement
total_rounds: 7
max_iterations: 7
---

# Codex Review Loop — phase-0/m3 plan v2 全新审查（不接 R1~R9）

## Goal Contract

**Task.** 对 `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（M3 v1→v2 类型切换实施计划，4122 行）执行一次**全新**的 codex 对抗式 review-fix 循环。**Why**：plan 已经过 R1~R9 codex review + 用户主导的 audit-fix pass（修补了 codex 9 轮全程未捕获的 13 项 substantive issue），用户希望以"全新视角"再做一次 review，验证 plan 是否真的已收敛，避免被 R1~R9 历史路径锚定（fresh codex 视角下可能暴露 audit-fix 也漏掉的问题，或反过来证实 plan 已成熟）。

**Reference Documents.** Codex should read these for full context.
- Spec / motivation: `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（mini-spec，已 R10 codex approve 锁定，30 finding 全 accept；含 D-26 ~ D-31 决议）
- Implementation plan (review target): `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体）
- Related code (M1+M2 已合 main，plan 中所有真实 API 引用必须对照真): `SliceAIKit/Sources/SliceCore/`（V2Tool / V2Provider / V2Configuration / SliceError / Tool.swift PromptTool）+ `SliceAIKit/Sources/Orchestration/`（ExecutionEngine / ExecutionEvent / InvocationGate / OutputDispatcher）+ `SliceAIApp/AppContainer.swift` + `SliceAIApp/AppDelegate.swift` + `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`
- Project README: `CLAUDE.md`（项目顶层规范、Swift 6 严格并发约定、错误模型 / 无自由日志规范）

**In-scope.**
- `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（唯一可被本 loop 修改的文件）

**Out-of-scope (won't touch even if Codex flags).**
- `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（mini-spec 本体已 R10 approve 锁定，决议冻结；plan 内若与 mini-spec 矛盾，以修 plan 为准，绝不动 mini-spec）
- `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`（前一次 R1~R9 + audit-fix loop log，是历史记录不可改）
- `docs/Task-detail/codex-loop-phase-0-m3-mini-spec.md`（mini-spec loop log，同上）
- 任何真实 .swift / .pbxproj / Tests 代码（plan 是文档，不在本阶段写代码；若 codex 提议改代码视为 [ADVISORY]）
- 其他 docs/ 下文件（Task_history.md / 其他模块 docs）

**Definition of Done.** 任一条件满足即可退出循环：
1. Codex 返回 `approve` verdict（无 blocker；plan 可直接进入 implementation 阶段）
2. Codex 返回 `needs-attention` 但所有残留 finding 都是 `low` severity AND 都 `reject`-with-stable-reason 或 `defer`（双方各自陈述完毕，再跑一轮也不会改变结论）
3. 跨连续 2 轮所有 `accept`-d finding 已 fix AND 当前轮 0 新 accept finding（净增缺陷率为零）

**Severity caps.** 任一轮触发以下任意条件 → 暂停循环 + AskUserQuestion：
- `critical > 3`，OR
- `(critical + high) > 5`，OR
- `total findings > 8`

**Max iterations.** 5（默认；可由用户在 round cap 触发时延长）

**Review scope.** branch (--base main)
（理由：mini-spec 已 commit ahead of main 1 个，plan + 2 loop log 都是 untracked working tree changes；branch scope 让 codex 看完整故事，包括前一次 codex review loop 留下的 mini-spec 改动 + 本次要 review 的 plan）

## Design decisions summary (可选 — 供 Codex framed evaluation)

按 skill `references/codex-focus-prompt.md` 的硬性 max 3 条规则，本 loop 第一轮注入以下 3 条：

1. **plan 切 v2 类型采用单 commit 5 步 rename pass（D-26）**——M3.1 additive 装配 → M3.0 5 步 rename → M3.2/M3.3 验收 → M3.4 grep validation → M3.5 12 项手工回归 → M3.6 v0.2 release；中间状态保持可编译，避免 git log 噪音。
2. **single-flight invocation 用 InvocationGate 集中（F9.2 R3+R4+R7 决议）**——@MainActor class 同步 setActive/clearActive；adapter 仅 1 行委托；chunk + 终态事件 + catch 段全部走 shouldAccept(invocationId:) gate；clearActiveInvocation 必须带 ifCurrent: label。
3. **plan 内所有 fallback 默认值优先非空字符串**（D-29 视觉等价 + audit-fix）——modelLabel = "default" 不是 ""，避免 ResultPanel 渲染零宽 badge 与 v1 行为不一致。

## Loop strategy 备忘（不发给 codex）

- 本 loop 是用户主动要求的"全新审查"，不依赖 R1~R9 + audit-fix 的 finding 历史。
- 但 plan 文件本身已含 R1~R9 决议注解 + audit-fix 注解 — codex 看到 plan 时会读到 "F9.1 R9 walking back R8 fix"、"audit-fix 2026-04-28" 等历史标记。这是 plan 文件的固有内容，不是 prior_round_decisions（prior_round_decisions 仅指本 loop 内的轮次决议）。
- Round 1 的 prior_round_decisions block 留空（这是 fresh loop 的第一轮）。

---

## Rounds

### Round 1 · 2026-04-28 · 16:10~16:26

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 1 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| 1 | high | ToolEditorView 切 V2 漏改 provider/displayMode 绑定 | docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md:2290-2358 | accept | 经 grep 验证完全真实：ToolEditorView.swift:168 真存在 `Picker("", selection: $tool.providerId)`；line 214-216 真用 `$tool.displayMode + DisplayMode.allCases`；line 393-401 真有 `private extension DisplayMode.displayLabel`。V2Tool 无顶层 providerId（仅 PromptTool.provider 内嵌）+ V2Tool.displayMode 是 `PresentationMode` 不是 v1 `DisplayMode`。Fix: 扩 §F2 binding 表加 providerId / displayMode 行；F2 给 providerIdBinding / modelIdBinding / temperatureBinding / variablesAccessor 完整 extractor 模板（不止文字描述）；F3 改 Picker `PresentationMode.allCases` + 加本地 `PresentationMode.displayLabel` extension；§J0 加 gate 8（grep ToolEditorView 不再含 `tool.providerId` / `DisplayMode.allCases`）。 |

- **Fix applied.** 在 plan §Iteration F2 binding 表扩展至 9 个字段（含 providerId / displayMode）+ 给出 5 个 binding 模板（providerIdBinding / modelIdBinding / temperatureBinding / variablesAccessor + helper functions）；§Iteration F3 把 displayMode Picker 类型改为 PresentationMode.allCases + 文件末尾追加 `private extension PresentationMode.displayLabel`；§Iteration J Step J0 新增 grep gate 8 (a/b 双子项) 兜底。
- **Files touched.** `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体；3 段插入 / 修改：§F2 binding 表 + extractor 模板 + 增量替换清单、§F3 Picker 改造 + extension、§J0 gate 8）。
- **Drift.** in-scope-only（仅 plan 文件被修改；mini-spec / 真实代码 / 历史 loop log 未触动）
- **Status.** continue（Round 1 finding 已 fix；DoD 未满足；进 Round 2）

### Round 2 · 2026-04-28 · 16:26~16:32

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 1 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| 1 | high | PresentationMode.allCases 与 3-case displayLabel 不匹配 + 暴露 v0.2 未实装模式 | docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md:2483-2515 | accept | 经 Read 验证：OutputBinding.swift:29-41 真实有 6 个 case（window/bubble/replace + file/silent/structured），不是 3 个。Round 1 fix 给的 displayLabel switch 只覆盖 3 case，会编译失败（Swift exhaustive switch）；即使 implementer 补全标签，PresentationMode.allCases 仍会让 Picker 暴露 file/silent/structured 三个 v0.2 D-30b 全 fallback 到 window 的模式，破坏 D-29 视觉/行为等价边界。Fix: §F3 Picker 数据源改为静态白名单 `editablePresentationModes: [PresentationMode] = [.window, .bubble, .replace]`；displayLabel switch 改 6-case exhaustive（v0.2 不暴露的 3 case 返回内部标签兜底）；§J0 加 gate 9 (a/b 双子项) 兜底（禁止 PresentationMode.allCases + 强制 editablePresentationModes 白名单存在）。 |

- **Fix applied.** 在 plan §F3：Picker `ForEach` 数据源从 `PresentationMode.allCases` 改为 `Self.editablePresentationModes` 静态白名单；ToolEditorView struct 内新增 `editablePresentationModes: [PresentationMode] = [.window, .bubble, .replace]` 静态字段；文件末尾的 `private extension PresentationMode.displayLabel` switch 改为 6-case exhaustive（v0.2 不暴露的 file/silent/structured 返回内部标签）。§J0 新增 grep gate 9 (a) 禁止 PresentationMode.allCases 直接用于 ToolEditorView + (b) 强制 editablePresentationModes 白名单声明存在。
- **Files touched.** `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体；2 段修改：§F3 Picker + extension、§J0 gate 9）。
- **Drift.** in-scope-only
- **Status.** continue（Round 2 finding 已 fix；R2 是 R1 fix 的二阶问题不算 stagnation；DoD 未满足；进 Round 3）

### Round 3 · 2026-04-28 · 16:32~16:38

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 1 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| 1 | high | providerIdBinding 切 provider 时保留旧 modelId 会写入对新 provider 无效的模型 | docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md:2363-2370 | accept | 经 grep 验证 codex 描述完全真实：PromptExecutor.swift:267 `if case .fixed(_, let modelId) = selection, let modelId { return modelId }` 优先用 modelId；ProviderResolver.swift:55 用 `case .fixed(let providerId, _):` 显式忽略 modelId；ProviderResolver.swift:11 文档明示 "selection.modelId 在 M2 阶段不被本协议消费"。Round 1 fix 注释里"Provider.defaultModel 兜底"假设错了——modelId 非 nil 时 PromptExecutor 直接发旧 modelId 给新 provider，跨供应商时会请求失败。Fix: providerIdBinding setter 切 provider 时 modelId = nil；删错误注释；§M3.5 加 Step 13 验收手工回归。 |

- **Fix applied.** 修订 plan §F2 providerIdBinding setter 把 `modelId: existingModelId` 改为 `modelId: nil`（删除原 existingModelId 闭包）；改 doc comment 反映正确行为；§M3.5 §4.2.5 在 Step 12 之后插入新 Step 13（providerId 切换 + config-v2.json 验证 modelId == null + 实际触发用 defaultModel）；原 Step 13/14 编号顺移到 Step 14/15；plan 多处 "12 项" → "13 项" 同步（5 处：Task 15 标题 / 目标段 / 不通过段 / 测试结果 / DoD 清单 / TOC 矩阵）。
- **Files touched.** `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体；4 段修改：§F2 providerIdBinding setter、§M3.5 §4.2.5 Step 13/14/15、§Task 15 标题 + 目标段、TOC 矩阵）。
- **Drift.** in-scope-only
- **Status.** continue（Round 3 finding 已 fix；DoD 未满足；进 Round 4）

### Round 4 · 2026-04-28 · 16:38~16:46

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 1 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| 1 | high | gate 3 grep pattern 漏掉 multi-line + 不带 await 的 Task wrapper | docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md:2965-2979 | accept | 真实漏洞：InvocationGate 改成 @MainActor 同步方法后，在 @MainActor closure 里调用不需要 await。错误实现可写成 `Task { @MainActor in container.invocationGate.setActiveInvocation(id) }` —— 多行 + 无 await，绕过 gate 3a 当前的单行 `[^}]*\bawait\b...` pattern。setActive 延后到异步 Task 后，stream 首 chunk 时 active 仍 nil → 丢首段；clear 晚到 → 误清新 invocation。重新打开 R2/R3 已修过的 race window。Fix: 3a 改 `rg -U`（multi-line PCRE）抽取整个 Task block，发现内部含 `.setActiveInvocation(` / `.clearActiveInvocation(` 即 fail，不依赖 await；新增 3d 检查 setActive/clearActive 调用上下文 ±8 行必须含 execute/onDismiss/defer 关键词。 |

- **Fix applied.** 修订 plan §Iteration J Step J0 gate 3：（1）3a 由单行 `Task[^{]*\{[^}]*\bawait\b...` 改为 multi-line `rg -nU "Task\b[^{]*\{[^}]*\.(setActiveInvocation\|clearActiveInvocation)\("` 模式（不依赖 await，跨行匹配 Task block）+ 改进失败提示文字明示三种绕过形态；（2）3b/3c 保留；（3）新增 3d 用 sed ±8 行抽取上下文，判断 setActive/clearActive 调用是否在 execute / onDismiss / defer 关键词附近，缺失即 fail；（4）头部加 Round-4 R4.1 修订背景注释。
- **Files touched.** `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体；1 段修改：§J0 gate 3 — 3a 改写 + 3d 新增）。
- **Drift.** in-scope-only
- **Status.** continue（Round 4 finding 已 fix；DoD 未满足；进 Round 5）

### Round 5 · 2026-04-28 · 16:46~16:52

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 1 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| 1 | high | Task 12 Step 4 cancellation 验收要求 audit 记录与真实 ExecutionEngine "cancel 不写 audit" 语义相反 | docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md:3834-3842 | accept | 经 grep 验证：ExecutionEngine.swift:163 明示"isCancelled=true → 本路径不写 audit、不 yield failed"；+Steps.swift:59/151/260 三处"静默退出，防止 cancel 后仍走 finishFailure 写'取消但记 .failed' 歧义 audit"。plan Step 4 期望"audit log 含 cancel 记录或 stream 提前结束记录"按真实代码必然失败；implementer 为通过验收可能给取消路径补写 audit → 破坏现有审计语义。Fix: Step 4 改成验证 UI/流行为（关闭无 alert / 无后续 chunk / 旧 invocation 不污染新面板）+ **反向 assertion** 检查 audit.jsonl 行数差值为 0（cancel 路径不应新增 success/failed），明确 v0.2 不暴露 cancel 独立 outcome。 |

- **Fix applied.** 重写 plan Task 12 Step 4：（1）头部加 Round-5 R5.1 修订背景注释 + 引用 ExecutionEngine 真实 4 处 source；（2）拆分操作步骤（触发 → 立即 cancel → 观察 3-5 秒）；（3）UI/流期望 3 项（panel 立即关闭 / 关闭后无 chunk / 重新触发新 panel 不含旧残留）；（4）audit.jsonl 反向 assertion shell snippet（BEFORE/AFTER 行数比较，差值 ≠ 0 → FAIL）；（5）Why audit 反向验证段说明 v0.2 不暴露 cancel outcome 的设计原因。
- **Files touched.** `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体；1 段重写：§Task 12 Step 4 cancellation 验收）。
- **Drift.** in-scope-only
- **Status.** loop-cap-reached（Round 5 = max_iterations；R5 finding 已 fix；trajectory 1/1/1/1/1 connecting needs-attention 全 fix；触发 termination 3.2 → AskUserQuestion）

> **User decision after R5**：选择 "再跑 R6 + R7 (Recommended)" → max_iterations 5 → 7 ；继续观察是否收敛到 approve 或 finding 退化为 low。

### Round 6 · 2026-04-28 · 16:52~17:22 (extended round)

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 1 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| 1 | high | Task 16 release tag `v0.2` 与 build-dmg.sh 0.2.0 + release.yml 版本剥离逻辑不一致，会让 CI 产 `SliceAI-0.2.dmg` 与本地预检 `SliceAI-0.2.0.dmg` 文件名错位 | docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md:4248-4304 | accept | 经 `cat .github/workflows/release.yml` 验证：line 23 `version=${GITHUB_REF_NAME#v}` 把 `v0.2` 转成 `0.2`；line 26 `scripts/build-dmg.sh "0.2"` 产 `build/SliceAI-0.2.dmg`；line 32 SHA256 / line 38 upload artifact / line 47 release body 全用 `0.2`。但 plan Step 10 用 `0.2.0` 预检产 `SliceAI-0.2.0.dmg`。三方版本不一致，CI 上传的产物名与下载方期待名不匹配，下载链接 / SHA256 / Release notes 全部错位。Fix: tag 改 `v0.2.0`，符合 SemVer，让 release.yml 剥前缀后得到 `0.2.0` 与本地预检完全一致。 |

- **Fix applied.** 修订 plan §Task 16 Step 13：（1）头部加 Round-6 R6.1 修订背景注释 + 引用 release.yml line 23 的 tag→version 转换逻辑；（2）`git tag v0.2` 改为 `git tag v0.2.0`、`git push origin v0.2` 改为 `git push origin v0.2.0`；（3）末尾加 note 显式说明 release.yml 触发后会重建 `SliceAI-0.2.0.dmg` 与本地预检同名 + 警告误推 `v0.2` 的后果。
- **Files touched.** `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体；1 段重写：§Task 16 Step 13）。
- **Drift.** in-scope-only
- **Status.** continue（Round 6 finding 已 fix；DoD 未满足；进 Round 7）

### Round 7 · 2026-04-28 · 17:22~17:25 (extended cap, final)

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 1 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| 1 | high | Task 16 Step 13 后半段手动 release fallback 仍用 `v0.2` 绕过 R6 fix | docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md:4313-4323 | accept | R6 改了 Step 13 前半段（`git tag v0.2.0` / `git push origin v0.2.0`），但 Step 13 后半段"如未自动触发"的手动 fallback 仍是 `gh release create v0.2 --title "SliceAI v0.2 — Phase 0 完成"` + release notes 用 `v0.2` 字符串。Actions 自动 release 失败时 fallback 会绑错 tag、release title/notes 不一致，重新引入 R6 已修过的版本错位。Fix: 把 fallback `gh release create v0.2` 改为 `v0.2.0`、title 改 `v0.2.0` SemVer、notes 改 `v0.2.0` 字符串；加 grep 兜底命令 `rg "gh release create v0\.2\b\|git tag v0\.2\b\|git push origin v0\.2\b"` 让 implementer 验证 0 命中再执行 Step 13。 |

- **Fix applied.** 修订 plan §Task 16 Step 13 后半段 fallback：（1）`gh release create v0.2` 改为 `gh release create v0.2.0`；（2）`--title "SliceAI v0.2 — Phase 0 完成"` 改为 `v0.2.0`；（3）notes 内 `v0.2 = M1+M2+M3` 改为 `v0.2.0 = M1+M2+M3`；（4）末尾加 R7.1 grep 兜底（implementer 跑 rg pattern 验证 0 命中再执行 Step 13）。`rg` 验证后剩 3 处合法引用（R6 注释回顾旧值 + 修复后的 v0.2.0 命令）；0 处裸 v0.2 命令残留。
- **Files touched.** `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体；1 段重写：§Task 16 Step 13 后半段 + grep 兜底）。
- **Drift.** in-scope-only
- **Status.** loop-cap-reached-extended（Round 7 = extended max_iterations；R7 finding 已 fix；trajectory 1/1/1/1/1/1/1 全部 high all-accept-all-fixed；触发 termination 3.2 → AskUserQuestion）

---

## Final summary

**Termination reason.** loop-cap-extended-accepted（用户两次 termination 3.2 决策：第一次 R5 → extend R6+R7；第二次 R7 → accept current state and stop）

**Total rounds.** 7 (5 base + 2 extended)

**Final Codex verdict on last round.** needs-attention（R7.1 已 fix，但 codex verdict 仍是 needs-attention 而非 approve；按 trajectory 持续 7 轮 1 high/round 全 accept 模式，进一步轮次 ROI 递减，用户决策 accept-and-stop）

**Net findings across all rounds.**
- Accepted and fixed: 7（R1.1 / R2.1 / R3.1 / R4.1 / R5.1 / R6.1 / R7.1）
- Rejected (with reasons that held): 0
- Deferred (out-of-scope): 0
- Partial (accepted root, rejected over-reach): 0

每轮 trajectory：1/1/1/1/1/1/1 high finding，severity 完全一致，全 accept 全 fix；无 walking back（所有 R1-R7 fix 都是 in-place 修订未触动其他轮次决议）；无 stagnation（finding 全在不同 plan 区域不重复）；无 mutation（每轮 codex 转向新区域 audit）。

**Findings 区域分布**：
| Round | Severity | Plan 区域 | 修订核心 |
|---|---|---|---|
| R1.1 | high | §F2/F3 ToolEditorView binding | 9-字段表 + providerId/displayMode 完整 extractor + §J0 gate 8 |
| R2.1 | high | §F3 PresentationMode Picker | 6-case displayLabel exhaustive + editablePresentationModes 白名单 + §J0 gate 9 |
| R3.1 | high | §F2 providerIdBinding setter | 切 provider 清空 modelId（PromptExecutor:267 直接用 modelId 不兜底）+ §M3.5 Step 13 |
| R4.1 | high | §J0 gate 3 (Task wrapper grep) | 3a 改 rg -U multi-line + 3d 上下文检查（execute/onDismiss/defer） |
| R5.1 | high | §Task 12 Step 4 cancel 验收 | 改 UI/流验证 + audit 反向 assertion（ExecutionEngine:163 cancel 不写 audit） |
| R6.1 | high | §Task 16 Step 13 release tag 前半段 | tag `v0.2` → `v0.2.0` SemVer 一致（release.yml:23 剥前缀逻辑） |
| R7.1 | high | §Task 16 Step 13 后半段 fallback | 手动 `gh release create v0.2` → `v0.2.0` + grep 兜底 |

**Files changed (cumulative).**
- `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（plan 主体；7 轮累积修订共 ~13 段插入 / 修改 / 重写；plan 行数从 4122 → ~4350）
- `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`（本 loop log；Goal Contract + 7 轮 entry + final summary）

**未触动文件（按 Goal Contract Out-of-scope）**：
- `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（mini-spec 已 R10 approve 锁定不动）
- `docs/Task-detail/codex-loop-phase-0-m3-implementation-plan.md`（前一次 R1~R9 + audit-fix loop log，是历史不可改）
- `docs/Task-detail/codex-loop-phase-0-m3-mini-spec.md`（mini-spec loop log，同上）
- 任何真实 .swift / .pbxproj / Tests 代码

**Deferred follow-ups for the user to consider later.** 无 deferred 项。7 轮所有 finding 都是 in-place fix。

**One-paragraph closing note.** 本 loop 是用户主动要求的 fresh codex review（不接前一次 R1~R9 + audit-fix 历史）。trajectory 揭示 codex single-point adversarial review 的内在性质：在大文档（4150 行）上每轮总能定位 1 个真实 alignment 漏洞，但 finding 在不同区域非重复——这意味着无穷轮 review 不收敛到 approve（因为单点扫描 noise floor 决定每轮 ROI 都是正的，但绝对值递减）。trajectory 1/1/1/1/1/1/1 是 codex 输出长度限制（focus prompt 强制 "prefer one strong finding"）+ plan 信息密度的乘积，不是 plan 真实漏洞数量的反映。**实质效果**：7 个 finding 都暴露真实代码 / release.yml / build-dmg.sh / ExecutionEngine cancel 语义的 alignment 漏洞，按本 loop fix 后 plan 比起点显著更接近 implementation-ready；但绝对收敛（codex approve verdict）需要的轮数远超 user ROI 阈值。**给未来类似 loop 的建议**：在大文档 plan review 上，max_iterations 5-7 + accept-and-stop 是合理配方；继续追求 approve verdict 是与 codex 输出 quirk 而非真实质量赛跑。

---

## 给用户的 commit slicing 建议

按 codex-review-loop skill termination 3.1，本 loop **无 walking back**（R1-R7 全 accept 全 fix，每轮在新区域，无 reject、无 partial、无后轮回退前轮）；plan 是单文件文档变更；建议 **Option A — single commit referencing the loop log**。

理由：
- 文档 plan 没有"refactor + fix" 二分（不适用 Option B）
- 7 个 fix 全是 plan 文档段落修订（添加 binding 模板 / 加 grep gate / 改 release tag 等），单 commit 引用本 loop log 让阅读者一次拿到完整 trace
- 每个 fix 单独 commit（Option C）会让 7 个 commit 都是"docs(plan): fix X"，git log 可读性反而下降

最终 commit 内容（非草稿）：
- `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（本 loop fix 累积 ~13 段修订）
- `docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md`（本 loop log；Goal Contract + 7 round entry + final summary）

建议 commit message（用户自定）：

```
docs(phase-0/m3): plan fresh codex review-fix R1~R7 (7 high findings fixed)

7-round fresh codex adversarial review on M3 plan (4122→~4350 行)，
不接前次 R1~R9 + audit-fix 历史；trajectory 1/1/1/1/1/1/1 high finding
全 accept 全 fix，无 walking back，无 stagnation。

修订区域：
- §F2/F3 ToolEditorView V2 binding（providerId/modelId/temperature/
  variables/displayMode 完整 extractor；PresentationMode 6-case
  displayLabel exhaustive + editablePresentationModes 白名单）
- §F2 providerIdBinding setter 切 provider 清空 modelId（与 PromptExecutor
  实际 modelId 优先逻辑对齐）
- §J0 grep gate 3 multi-line 化 + gate 8/9 新增（编号 6 跳过保留 R8 历史槽位）
- §Task 12 Step 4 cancel 验收 UI/流验证 + audit 反向 assertion
- §Task 16 Step 13 release tag SemVer v0.2.0 + fallback / grep 兜底
- §M3.5 13 项手工回归（新增 Step 13 切 provider modelId 清空验收）

trace: docs/Task-detail/codex-loop-phase-0-m3-plan-fresh-review.md

🤖 Generated with [Claude Code](https://claude.com/claude-code)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
```

> **note**：上述 commit message 是建议；实际 commit 由用户决定（codex-review-loop skill 强制：loop 不主动 git commit / push / PR；用户保留全部 git slice 控制权）。注意 worktree 当前还有 mini-spec modified（589 ins / 169 del）+ 前次 R1~R9 + audit-fix log 三个 untracked，那些是前一次 loop 留下的，与本次 fresh loop 无关，commit 时按用户自己的策略决定要不要一起带上。
