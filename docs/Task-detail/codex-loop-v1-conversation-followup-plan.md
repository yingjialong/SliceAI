# Codex Review Loop — v1 续聊+历史 实施 Plan

## Goal Contract

**Task**：用 Codex 对抗式 review 这份实施 plan，直到 approve。
**What**：被 review 的是 plan 文档 `docs/superpowers/plans/2026-05-30-v1-conversation-followup-and-history.md`（不是已实现的代码——代码尚未开始写）。
**Why**：plan 对现有代码做了大量具体断言（如"`resolved.seed` 在 renderMessages 可达，无需改 run 签名"、"`appendSkillMetadata` 现有 helper"、"`ExecutionSeed` 合成 Codable 向后兼容"、"`MCPServerStore` 的 actor + update{inout} 落盘模式"）。这些断言若错，整个 plan 会在实施时崩。需要 Codex 对照真实源码核查 plan 的**正确性 + 可实施性 + 与冻结 spec 的一致性**，避免照着错的 plan 写代码。

**Reference Documents**（Codex 应读，用于 alignment review）：
- 冻结 spec（plan 的上游依据）：`docs/superpowers/specs/2026-05-30-v1-scope-and-conversation-followup-design.md`
- 被 review 的 plan：`docs/superpowers/plans/2026-05-30-v1-conversation-followup-and-history.md`
- plan 断言的现有源码（核查 plan 对代码的描述是否属实）：
  - `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift`（plan 新增 `followUp` 字段 + `withFollowUp` helper）
  - `SliceAIKit/Sources/SliceCore/ResolvedExecutionContext.swift`（plan 称其透传 `seed`，故 executor 可读 `resolved.seed.followUp`）
  - `SliceAIKit/Sources/SliceCore/ChatTypes.swift`（plan 复用 `ChatMessage`/`Role`）
  - `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`（plan 改 `renderMessages` 分支）
  - `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`（plan 改 `buildInitialMessages`；称有 `appendContextBag`/`appendSkillMetadata` 私有 helper）
  - `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`（plan 称 `run` 签名含 `resolved`、catalog 由 agent 重建）
  - `SliceAIKit/Sources/Windowing/ResultViewModel.swift` / `ResultPanel.swift` / `ResultContentView.swift`（plan 加 `onSubmitFollowUp`/`contextNotice`/`beginFollowUpTurn` + FollowUpInputBar，称续聊绝不调 `reset()`）
  - `SliceAIKit/Sources/Capabilities/MCP/MCPServerStore.swift`（plan 照其模式写 `ConversationStore`）
  - `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift`（落盘/原子写/App Support 路径模式参照）
  - `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`（plan 称注册新页改 5 处）
  - `SliceAIApp/AppDelegate+Execution.swift` / `AppContainer.swift` / `AppContainer+Factories.swift`（App 层续聊编排 + 装配 + pbxproj 断言）

**In-scope**：
- `docs/superpowers/plans/2026-05-30-v1-conversation-followup-and-history.md`（plan 的正确性、可实施性、内部一致性、与 spec 一致性、对现有代码断言的真实性）。
- 修复方式 = 编辑该 plan 文档（必要时同步修 spec 仅当出现 plan↔spec 不可调和的不一致）。

**Out-of-scope**（即便 Codex 提到也不在本 loop 改，最多记 ADVISORY）：
- 实际实现 feature 代码（本 loop 只 review plan，不写实现）。
- 用户已批准的产品决策：D2（续聊上下文只带用户可见轮次、不带 agent 内部 tool 消息）、D4（10 轮窗口、质量优先不激进裁剪）、D5（历史默认常开、不做开关、不 bump config schema v4）、D6（多轮 transcript 追加而非气泡）、未签名分发、Phase 4/5 移出 v1.0。这些是 spec 里用户拍板的范围，不是 plan 正确性问题。Codex 可标 ADVISORY，但不据此"修" plan。
- 修改 spec 的产品范围（spec 已经用户 review 通过）。

**Definition of Done**：
- Codex 对 plan 返回 `verdict: approve`；或
- 仅剩 low severity 且双方稳定分歧/deferred（agreed-disagreement）。

**Severity caps**（默认）：任一轮 `critical > 3` 或 `critical+high > 5` 或 `total > 8` → 暂停问用户。

**Max iterations**：5（安全上限，非目标；首个 approve / 收敛 / 逃生阀触发即退出）。

---

## Round Log

### Round 1 — 2026-05-31

- **Scope**：`--scope branch --base main`（plan 1516 行 + spec 153 行）
- **Verdict**：needs-attention
- **Summary（Codex）**：不应按此 plan 开工——historystore 并发、App 接线、若干现有 API 形状假设错误，会引导出不可编译或丢/复活历史数据的实现。
- **Severity 计数**：critical 0 / high 1 / medium 5 / low 0（total 6）→ 逃生阀未触发。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | high | accept | 两个 ConversationStore 实例指向同一文件，actor 仅保护单实例 → App upsert 与 Settings 删除并发丢更新/复活 | 改共享单例注入：HistoryViewModel 去掉默认 store、HistoryPage(init store)、SettingsScene 加 conversationStore 参、AppDelegate.showSettings 传入（Task 11/12/13）；范式 A→B |
| 2 | med | accept | `tool.effectiveProviderId/Model` 不存在（在 tool.kind 内）；`makeConversationStore` 应 static | Task 10：providerId/model v1.0 传 nil；`static func makeConversationStore` |
| 3 | med | accept | assistant 全文捕获不可行（.llmChunk 只记长度、panel.viewModel 私有）；读 panel 文本会污染整段 transcript | Task 10：AppDelegate per-invocation `currentAssistantText` 累积器，.llmChunk 追加、.finished 落盘后清零，不读 panel |
| 4 | med | accept | ResultViewModel 是 internal 类，加 public 成员无法编译 | Task 7：新增成员改 internal + 加说明 |
| 5 | med | accept | 测试片段 AppSnapshot init 标签错、actor run 缺 await | Task 1/5/6：`AppSnapshot(bundleId:name:url:windowTitle:)` + `let stream = await executor.run(...)` |
| 6 | med | accept | HistoryViewModel 缺 import SwiftUI；多处 import 未按 sorted_imports 排序 | 全部新建文件 import 重排；test 头逐字镜像 MCPServerStoreTests / MCPServersViewModelTests |

- **Reject/Defer**：无（6 条全 accept，均为 plan 可实施性缺陷，未触及用户已批准产品决策）。
- **Files touched**：`docs/superpowers/plans/2026-05-30-v1-conversation-followup-and-history.md`（仅 plan 文档，无源码改动）。
- **Drift**：in-scope only（全部修在 plan 文档内）。
- **Convergence**：continue → round 2（验证修复是否到位、是否有新发现）。

### Round 2 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1 的 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-1 主修复大多落地，但仍有会编译失败 / 破坏既有 Agent prompt / 误显示错误历史详情的实质缺陷。
- **Severity 计数**：critical 0 / high 1 / medium 4 / low 0（total 5）→ 逃生阀未触发；趋势 6→5 收敛中。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | high | accept | Task 6 buildInitialMessages 替换体丢了 makeVariables+PromptTemplate.render，既有 agent 模板占位符会泄漏 | 重写 Task 6：保留 makeVariables+render 与非 follow-up 分支原样，只加 follow-up 早返回分支；appendContextBag/appendSkillMetadata 用真实 String-返回签名；boundSkills:[Skill] |
| 2 | med | accept | App 接线用了不存在的 payload.selection.text + 错误 startExecutionStream 签名 | Task 10 按真实签名重写：payload.text；startExecutionStream(tool:payload:triggerSource:seed:invocationId:)+isFollowUp/followUpUserText；shouldAccept(invocationId:)；activeTool/activePayload/activeTriggerSource；复用 triggerSource 不加 .followUp case |
| 3 | med | accept | HistoryPage 缺 import Capabilities；IdentifiedString 行长 126>120 strict 失败 | 补 import Capabilities（排序）；IdentifiedString 拆多行 |
| 4 | med | accept | loadDetail 异步未清空 → 详情可能显示上一条会话明文（串话） | loadDetail 开头 selectedRecord=nil；HistoryDetailSheet 按 selectedRecord?.id==id 校验，否则"加载中" |
| 5 | med | accept | 续聊输入框未按 displayMode 门控，structured 也会出现，违反 D7 window-only | ResultViewModel 加 canFollowUp（reset=false）；bar 门控 canFollowUp&&finished；setFollowUpHandler 置 canFollowUp；App 仅 window 绑定 |

- **Reject/Defer**：无（5 条全 accept，均为可实施性/对齐缺陷，未触及用户已批准产品决策）。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan，141+/83-）。
- **Drift**：in-scope only。
- **Convergence**：continue → round 3（趋势 6→5，全 accept 无 reject；预期 round 3 验证 Task 6/10 完整签名后收敛）。

### Round 3 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1+2 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-2 的 Task 6/10 主修复方向基本对，但仍有两个测试编译 blocker + 一个让旧续聊入口错误驱动非 window 工具副作用的状态泄漏。
- **Severity 计数**：critical 0 / high 1 / medium 3 / low 0（total 4）→ 逃生阀未触发；趋势 6→5→4。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | high | accept | 非 window 执行不清旧续聊入口 + 单 coordinator session 被覆盖 → 旧输入框对新工具提交触发副作用，违反 D7 | **walk-back**（而非堆护栏）：History 改为**仅 window 会话**；非 window 执行 `setFollowUpHandler(nil)` 清入口、不记历史；ExecutionStreamContext 加 `recordsHistory`，门控累积与 finishTurn；continueConversation 加 window 防御 guard |
| 2 | med | accept | Task 1 测试 `AppSnapshot(bundleId: nil)`，但 bundleId 是非可选 String | 改 `bundleId: "com.apple.Safari"` |
| 3 | med | accept | Task 7 测试 `reset(model: nil)`，但 model 是非可选 String | 改 `model: ""` |
| 4 | med | accept | spec §4.1 要求 History 显示 provider/model，但 plan 传 nil 且行不渲染 | Task 10 加 `conversationProviderMetadata(for:)` 从 `ProviderSelection.fixed` 捕获；HistoryRow 渲染 model |

- **Reject/Defer**：无（4 条全 accept）。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan）。
- **Drift**：in-scope only。Finding 1 的 walk-back 收窄了 History 范围（仅 window）——属内部 scope 细化，非用户产品决策；已在 plan + 终态向用户标注。
- **Convergence**：continue → round 4（趋势 6→5→4，全 accept；round 4 验证 walk-back 的一致性后预期收敛）。

### Round 4 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..3 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-3 修复大体落地，但 provider/model 仍未真实锁定/完整展示，续聊可能把同一会话历史发到配置变更后的不同模型/endpoint。
- **Severity 计数**：critical 0 / high 1 / medium 1 / low 0（total 2）→ 逃生阀未触发；趋势 6→5→4→2，强收敛。
- **关键事实核查**：`InvocationReport`（Events/InvocationReport.swift）**不含 provider/model**；`ProviderSelection.fixed(providerId, modelId: String?)` 的 modelId 可空，默认工具多用 nil → 执行回落 `provider.defaultModel`。两条 finding 都需"捕获 resolved provider+model"。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | high | accept（待用户定范围） | 续聊未锁定发起时 provider/model，中途改配置会把历史发到不同 endpoint，违反 spec §7 锁定要求 | 需捕获首轮 resolved provider+model 并锁定 follow-up；实现需改 InvocationReport |
| 2 | med | accept（待用户定范围） | History 未满足 spec §4.1 provider/model 展示；.fixed.nil model 显示不出真实模型；line 1593 旧"传 nil"自相矛盾 | 需 resolved 值入 ConversationSummary/HistoryRow；删除 line 1593 旧口径 |

- **Pause 原因（Operating Principle #3：load-bearing + ~50/50 决策）**：两条都要求"把 resolved provider/model 浮出来"（InvocationReport +2 字段 + 锁定 follow-up + History 展示），是真实范围增量；与用户强调的"最小可闭环 v1.0"存在张力，且"简化"路径需修改用户已批准的 spec §4.1/§7。已暂停问用户选范围（实现完整锁定+展示 / 只锁定不展示 / 都推后并改 spec）。所有 plan 修复已落工作区，未提交。
- **用户决策**：选 **Option A「完整：锁定 + 展示」**——忠于已批准的 spec §7（会话内锁定）+ §4.1（History 展示 provider/model），不削 spec。
- **实施（plan 内）**：
  - **根因机制**：核查确认 `.finished(report: InvocationReport)` 是唯一携带终态快照的事件，且 `recordCostAndFinishSuccess(tool:provider:usage:context:)` 是 prompt + agent **两条**流水线共用的成功收口、其作用域同时持有 `provider.id` 与 `resolveSelectedModel(...)` 解析出的 model（与 `CostRecord` 同源）。故把 resolved 值补进 `InvocationReport` 即可一处覆盖两路。
  - **Task 10 新增 Step 0（Orchestration，含 OrchestrationTests TDD）**：`InvocationReport` 加 `resolvedProviderId/resolvedModel: String?`（`= nil` 默认，向后兼容，stub 同步）；`makeReport` 加同名可选形参并透传；`recordCostAndFinishSuccess` 在 `makeReport` 处传 `provider.id` / `model`；`JSONLAuditLog.scrubEntry` 透传（provider id/model 是稳定非 PII 标识，与已保留的 Permission host/bundleId 同类）。
  - **会话锁定**：`ConversationSession` 加 `lockedProviderId/lockedModel`（`recordAssistantTurn(…providerId:model:)` lock-once）；`ConversationCoordinator.startConversation` 去掉 provider/model 形参、`finishTurn(…providerId:model:)` 在首轮 `.finished` 注入；续聊 `lockingProvider(in:providerId:model:)` 把 tool 的 `ProviderSelection` 覆写为 `.fixed(锁定值)`（依赖 Tool.kind / PromptTool.provider / AgentTool.provider 均为 var，已核对）。
  - **展示**：`ConversationSummary` 加 `providerId`；`HistoryRow` 渲染 `工具 · N 轮 · provider · model`；Task 2 加 record→summary 透传断言。
  - **清理**：删除 round-3 引入的静态 `conversationProviderMetadata(for:)`（被运行时 resolved 捕获取代）；删除 self-review 中"provider/model v1.0 传 nil"旧口径；修正 Step 8 `git add` 清单（去掉未改的 TriggerSource.swift，纳入 Step 0 四个 Orchestration 文件 + ExecutionEngineTests）。
  - **边界**：会话中途删除被锁定 provider → 续聊以 `.configuration(.referencedProviderMissing)` 失败提示（锁定语义的正确结果，v1.0 不做迁移），已在 plan 标注。
- **Convergence**：continue → round 5（验证 round-4 完整锁定+展示实现的可实施性与自洽性；趋势 6→5→4→2）。

### Round 5 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..4 累计 plan 修复，重点验证 round-4 锁定+展示链）
- **Verdict**：needs-attention
- **Summary（Codex）**：No-ship——round-4 的 History 展示链未闭合，照 plan 写会在 SliceCore 类型定义处直接编译失败。
- **Severity 计数**：critical 0 / high 1 / medium 0 / low 0（total 1）→ 逃生阀未触发；趋势 6→5→4→2→1，持续强收敛。
- **Codex 核查范围（命令日志可见）**：通读了 round-4 断言的全部真实源码——`ExecutionEvent.swift`(.finished 携带 report)、`ExecutionEngine+PromptPipeline/Steps/Terminal.swift`(两路共用 recordCostAndFinishSuccess + provider.id/model 同源)、`JSONLAuditLog.swift`(scrubEntry memberwise 重建)、`Tool.swift`/`ToolKind.swift`(kind/provider 均 var)、`ProviderSelection.swift`(.fixed 标签)、`ExecutionEngineTests.swift`+`MockProvider.swift`+`MockProviderResolver.swift`(openAIStub id/defaultModel)、App 装配链。**均未报问题**——即 Step 0 机制、锁定、tool override 经真实源码核验成立。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | high | accept | `ConversationSummary` 结构体未声明 `providerId`，但 round-4 已让 `ConversationRecord.summary` 构造 `ConversationSummary(…providerId:model:)`、Task 2 测试断言 `s.providerId`、Task 12 `HistoryRow` 读 `summary.providerId` → 定义缺失，照 plan 写会在 ConversationRecord.swift/测试/HistoryPage 同时编译失败 | 给 `ConversationSummary` 补 `public let providerId: String?` + init 形参（顺序 `…updatedAt:providerId:model:`，与既有调用点一致）|

- **Reject/Defer**：无（1 条 accept）。这是上一会话 round-4 收尾时的自伤遗漏：只改了 `summary` 计算属性 + 测试 + HistoryRow（消费方），漏改了 `ConversationSummary` struct 定义（生产方）。Codex 精准抓出"消费方已动、定义方未动"的不对称。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan）。
- **Drift**：in-scope only。
- **Convergence**：continue → round 6（已补全 struct 定义，展示链 struct→computed→test→HistoryRow 现已一致；Codex 本轮已核验 Step 0/锁定/override 全部成立，仅差此 1 处定义；预期 round 6 收敛到 approve）。

### Round 6 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..5 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：`ConversationSummary` provider/model 链已闭合、无旧签名残留；但仍有 1 个编译 blocker + 2 个实质验收缺口。
- **Severity 计数**：critical 0 / high 1 / medium 2 / low 0（total 3）→ 逃生阀未触发；趋势 6→5→4→2→1→3（round-6 因 round-4 大改新引入面，略回升属正常，3 条全可定位修复）。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | high | accept | Task 12 `HistoryPage.list` 是普通计算属性却返回 `SectionCard` + `Button` 两个 sibling view，无 `@ViewBuilder` 也无容器 → 首个表达式被当未使用、列表静默消失（更严上下文直接编译失败） | 用 `VStack(alignment:.leading, spacing:8)` 包裹两者（返回单一视图，不依赖 `SettingsPageShell` 内部布局）|
| 2 | med | accept（alignment）| spec §4.1 要求每条 History 显示「时间·来源工具·首条输入摘要·provider/model」，但 `HistoryRow` 未渲染 `summary.updatedAt`（注释却写了"时间"，自相矛盾）| caption 前置 `summary.updatedAt.formatted(date:.abbreviated, time:.shortened)`，凑齐 时间·工具·轮数·provider·model（title=首条输入摘要）|
| 3 | med | accept（根因）| `startExecutionStream` 的 consumer `onRetry` 写死 `execute(tool:payload:triggerSource:)`（首轮入口，已核 AppDelegate+Execution.swift:127）；续聊复用它 → 续聊失败点 Retry 会用原 selection 重开**首轮**会话，丢 FollowUpContext + 覆盖 session + 污染 History | mode-aware retry：抽 `runFollowUpStream`（首次提交与重试唯一入口，不重复追加用户块/不重调 makeFollowUp）；`startExecutionStream` 加可选 `retry` 形参，首轮不传（保原语义），续聊传"重跑同一 follow-up+锁定 tool+新 invocationId"的递归闭包；onRetry 改 `retry ?? { 首轮 execute }` |

- **Reject/Defer**：无（3 条全 accept，均对照真实源码核实：finding 1 看 plan 1550-1562 + body 用法；finding 2 看 spec §4.1 line 93；finding 3 看 AppDelegate+Execution.swift:111-129 + ExecutionEventConsumer onRetry 类型）。
- **line-length 复核**：新增进入 `included`（Sources/SliceAIApp）的注释行按字符计均 <120（CJK 1 字符/个，非字节）；测试文件在 `.swiftlint.yml` `excluded: SliceAIKit/Tests` 内不被 lint。无 strict 隐患。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan）。
- **Drift**：in-scope only。finding 3 选根因修（mode-aware retry）而非"禁用续聊 retry"的护栏式简化——符合用户质量优先 + 操作原则 #2。
- **Convergence**：continue → round 7（3 项修复 Codex 均未见过、尚无 approve；retry 重构为最大新面，round 7 验证其自洽 + 展示链时间字段 + list 容器后预期收敛到 approve）。

### Round 7 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..6 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：list 容器 + 时间展示已闭合；但 follow-up 接线仍有 1 个 App 编译 blocker + retry 路径会污染/卡住结果面板状态。
- **Severity 计数**：critical 0 / high 1 / medium 1 / low 0（total 2）→ 逃生阀未触发；趋势 …→3→2，再次收敛。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | high | accept | AppDelegate 续聊状态（activeTool/activePayload/activeTriggerSource/currentAssistantText）只在 extension 展示用且写"私有"——Swift 不允许 extension 加存储属性，且 `private` 文件级会挡跨文件 extension 访问 → 编译失败 | 核 `AppDelegate.swift:54 var streamTask`（主类、internal、被 +Execution extension 跨文件用）。改 plan：这些字段声明在 `AppDelegate.swift` 主类、用 internal（无修饰符，沿用 streamTask）；`AppDelegate.swift` 纳入 Task 10 Files + git add |
| 2 | med | accept（根因）| 续聊 mid-stream 失败后点 Retry：`append` 只 `.thinking→.streaming`、不从 `.error` 恢复，`fail` 保留 text → 新答案拼到失败轮 partial 后、面板卡 `.error`，可见 transcript 与落盘 History 不一致（核 ResultViewModel.swift：append/fail/reset 行为）| 镜像首轮"retry 走 reset"：ResultViewModel 加 `followUpCheckpoint`（beginFollowUpTurn 捕获本轮答案前 transcript）+ `retryFollowUpTurn()`（回滚到 checkpoint、清错误/工具/结构化、状态回 .thinking）；ResultPanel 转发；runFollowUpStream 加 `isRetry`，重试前先 `retryFollowUpTurn()`。补 1 条 Windowing 测试 |

- **Reject/Defer**：无（2 条全 accept，均对照真实源码核实：finding 1 看 AppDelegate.swift streamTask 模式；finding 2 看 ResultViewModel append/fail/reset + Task 7/9 续聊追加模型）。
- **预防性根因修复（同 finding 2 一类，Codex 未点名但同源）**：`beginFollowUpTurn`/`retryFollowUpTurn` 原 `toolCalls = []` 只清已发布数组、不重置私有 `toolCallStore` → agent 续聊轮 propose 新 tool call 时 store 会把上一轮旧调用一并 republish（旧行复现）。两处统一改 `toolCallStore.reset(); toolCalls = toolCallStore.calls`（镜像既有 `reset()` line 77-78）。属同一文件/同一 task、令我的 retry 修复自洽，非 drift。
- **line-length 复核**：新增进入 Sources/SliceAIApp 的注释/代码按字符计 <120；测试在 `excluded` 内。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan）。
- **Drift**：in-scope only。finding 2 选根因（checkpoint+rewind，镜像首轮 reset 语义）而非"禁用续聊 retry"护栏，符合用户质量优先 + 操作原则 #2。
- **Convergence**：continue → round 8（2 项 + 预防修复 Codex 均未见过、尚无 approve；retry 状态恢复为最大新面，round 8 验证 checkpoint/rewind 自洽 + AppDelegate 状态落点后预期收敛到 approve）。

### Round 8 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..7 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-7 两处修复已闭合；但 header「重新生成」按钮仍走首轮 execute 语义，是真实的 stale callback / 重入风险。
- **Severity 计数**：critical 0 / high 0 / medium 1 / low 0（total 1）→ 逃生阀未触发；趋势 …→2→1，high 归零。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | med | accept（用户定范围）| header「重新生成」`viewModel.onRegenerate` 在 `openResultPanel.open(onRegenerate:)` 绑死首轮 `execute`（核 AppDelegate+Execution.swift:93-100 + ResultContentView.swift:136-139）；续聊中/后点它重跑首轮、reset 面板、覆盖 session、History 多一条首轮记录。与 round-6 retry 同根的第 3 个 re-trigger 入口 | **暂停问用户**（load-bearing UX/范围）：禁用 vs 完整多轮重新生成。用户选**窗口模式禁用**。Task 8 加 Step 3：header 重新生成按钮 `if !viewModel.canFollowUp` 门控（窗口隐藏、非窗口不变）；smoke 加验收项；正确的多轮重新生成推后 1.0 之后 |

- **Pause + 用户决策（Operating Principle #3：load-bearing + UX/范围，用户全程亲自拍板范围）**：问"窗口模式禁用 vs 实现完整多轮重新生成"。完整版需给 `ConversationSession` 加"丢弃最后一轮"并区分"失败重试(未记录,不丢) vs 成功后重生成(已记录,丢)"——对精简 v1.0 偏重，且会再引出若干轮 review。用户选 **窗口模式禁用（推荐）**：一刀消除整类 re-trigger bug（错路由/覆盖会话/重复记录），续聊轮"重做"由 mode-aware 失败 Retry 承担。
- **walk-back 记录**：round-6(retry 退回首轮)→round-7(retry UI 状态恢复)→round-8(regenerate 同问题) 是同一根因（窗口模式下所有 re-trigger 默认走首轮 execute）的逐个暴露。round-8 不再逐个打补丁，而是用"窗口模式禁用 regenerate" + "已有的 mode-aware retry"两招收口整个 re-trigger 面。
- **Reject/Defer**：无（1 条 accept，对照真实源码核实）。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan）。
- **Drift**：in-scope only；"窗口禁用 regenerate"是用户拍板的 v1.0 范围细化。
- **Convergence**：continue → round 9（regenerate 门控 Codex 未见过、尚无 approve；这是 re-trigger 面的最后一个入口，收口后预期 approve）。

### Round 9 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..8 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-8 的 regenerate 门控仍有漏口——非窗口执行会把仍可见的（被钉）窗口会话面板切回"可重新生成"。
- **Severity 计数**：critical 0 / high 0 / medium 1 / low 0（total 1）→ 趋势稳定在 1，high 持续归零。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | med | accept（根因/walk-back）| `canFollowUp` 被复用为"续聊入口"+"regenerate 门控"两义。非 window 执行 `setFollowUpHandler(nil)` 置 canFollowUp=false；若用户钉住 window 会话再触发 bubble/replace/file/silent（不开 ResultPanel），被钉面板 canFollowUp 翻 false → Task 8 的 `!canFollowUp` 门控让旧面板重现「重新生成」，onRegenerate 仍是旧首轮 execute → 重开 re-trigger 洞 | **解耦 + 收敛**：ResultViewModel 加独立 `allowsRegenerate`（默认 true）；ResultPanel 加 `setAllowsRegenerate`；门控改 `if viewModel.allowsRegenerate`（Task 8）。面板续聊入口 + regenerate 门控统一在 `openResultPanel`（仅 window/structured 运行）按打开模式设定（window→handler+regenerate=false / structured→nil+regenerate=true）；**移除** (b) 非 window 分支的 `setFollowUpHandler(nil)`（round-3 关心的 structured 复用清理改由 (c) 的 else 承担）。非面板模式不再 mutate 共享面板 |

- **Reject/Defer**：无（1 条 accept，对照真实源码核实：ResultPanel 单例共享、shouldOpenResultPanelInitially 仅 window+structured、bubble 等不开 ResultPanel）。
- **walk-back 记录**：这是 re-trigger 面 round-6→9 的收口——根因是"窗口模式下面板状态被 execute() 各分支零散 mutate"。round-9 把面板模式状态（续聊入口 + regenerate 门控）收敛到 `openResultPanel` 单一写入点，非面板模式不碰共享面板。比"再加一个 canFollowUp 判断"更根因：消除了状态来源分散。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan）。
- **Drift**：in-scope only。
- **Convergence**：continue → round 10（解耦 + 收敛 Codex 未见过、尚无 approve；这是 re-trigger/面板状态面的根因收口，预期 round 10 approve；若仍有同区 finding 则考虑是否 App-wiring 层过细需向用户报告）。

### Round 10 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..9 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-9 状态收敛仍漏了非面板执行的事件消费路径——`consumer.handle` 对所有模式无条件写共享 ResultPanel。
- **Severity 计数**：critical 0 / high 0 / medium 1 / low 0（total 1）→ 同子系统持续收敛。
- **关键架构核查**：`ExecutionEventConsumer.handle` 对 `.failed`→panel.fail、tool-call→showToolCall*、`.finished`→finish **无条件**写传入的 ResultPanel；`.llmChunk` 文本则走 OutputDispatcher 的 displayMode-aware sink（bubble→BubblePanel）。`consumeExecutionStream` 全模式传 resultPanel。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | med | **accept-narrow + defer** | 我 round-9 prose 声称"非面板模式不 mutate 共享面板"，但 `consumer.handle` 对 `.failed`/tool-call/`.finished` 全模式写 ResultPanel → 被钉 window 会话遇后续非 window 工具失败/tool-call 时 transient 内容（error/tool-call/streamingState）被污染 | **accept-narrow**：收窄我 round-9 的过度声明——真实成立的不变量是"续聊入口 + regenerate 门控（canFollowUp/allowsRegenerate）只在 open 时按模式设、不被非面板执行改写"（consumer.handle 不碰这两项，故 round-9 的 regenerate-重现修复仍有效）。收窄 (b)/(c)/辅助改动 prose + smoke #6c。**defer**：transient 内容污染走 consumer.handle，是改动前就有的 ResultPanel-as-primary 架构（全模式写 ResultPanel、pin 都早于会话特性），非本切片引入；彻底修需 gate consumer.handle + 给非 window 失败另接独立呈现（否则 gate 掉会让 bubble/replace 失败无 UI＝回归），属"非 window 失败呈现"重构，与"续聊+History"正交 → 记"已知限制"，1.0 之后单独处理 |

- **Reject/Defer 理由（稳定）**：defer 的根据是 (1) 预存在（非本切片引入）(2) 彻底修会回归非 window 失败 UI 且需读/改大量预存在架构 (3) 与会话/History 正交 (4) 影响有界（仅 pin+非 window 失败的边角；续聊/regenerate/落盘均不受影响）。已在 plan「已知限制」明确记录，非掩盖。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan：收窄过度声明 + 加"已知限制" + 修 smoke #6c）。
- **Drift**：in-scope only（修正 plan 内不准确声明 = 内部一致性，in-scope；重构 consumer.handle = out-of-scope，defer）。
- **Convergence**：continue → round 11（已收窄声明 + 文档化限制；预期 approve。若 round 11 仍坚持 gate consumer.handle，则属 out-of-scope 项的 agreed-disagreement → 据此退出并向用户报告；若另有新实质 finding 且仍在 App-wiring 区，则向用户报告该层细密度）。

### Round 11 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..10 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-10 的 transient defer 论证**基本成立**（agreed）；但 plan 仍有一个会让用户已删除的明文 History 被活动会话写回的隐私/删除缺陷。
- **Severity 计数**：critical 0 / high 1 / medium 0 / low 0（total 1）。
- **重要进展**：Codex 明确认可 round-10 的 consumer.handle transient defer（"保留为已知限制即可"）→ **re-trigger/面板状态子系统正式收口（agreed-disagreement 已转为 agreed）**。本轮 finding 在全新领域（数据删除）。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | high | accept（根因）| `ConversationCoordinator.finishTurn` 无条件 `store.upsert(s.toRecord())`；用户在面板仍开/首轮流式时于 Settings 删除会话或清空，HistoryViewModel 只清磁盘，内存 session 仍持旧明文 → 下轮 finishTurn（或清空发生在首轮 finish 前）把已删 record 写回 → 撤销用户删除，违反 spec「必须给删除权」+ D8 | **store-level 防复活**（单一序列化 actor 处收口，coordinator 无需改）：ConversationStore 加 `deletedIDs: Set<String>`（tombstone）+ `clearedAt: Date?`（清空水位）；`upsert` 忽略 tombstoned id 或 `createdAt ≤ clearedAt` 的写回；`delete(id)` 插 tombstone；`clear()` 记水位。仅进程内（重启后磁盘已正确、内存 session 也没了，生命周期恰好匹配）。补 3 测试（delete/clear 后旧会话不复活、clear 后新会话仍可存）|

- **Reject/Defer**：无（1 条 accept）。round-10 的 transient defer 经本轮 Codex 认可，正式 closed。
- **为何 store-level 而非 coordinator-notify**：store 是所有写的单一序列化 actor，在此 gate 同时覆盖"delete 后 follow-up 写回"与"clear 早于首轮 finish 的写回"两种竞态，无需 SettingsScene→Coordinator 跨组件回调，也不引入"删除活动会话后续聊如何"的 UX 歧义。tombstone/watermark 仅进程内：重启后磁盘已是删除态、能复活的内存 session 也不存在 → 生命周期精确匹配，无需持久化、无无界增长隐患。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan：Task 4 store + 测试；smoke #4 + Spec 覆盖）。
- **Drift**：in-scope only（History 删除权是 v1.0 核心 spec 边界）。
- **Convergence**：continue → round 12（防复活修复 Codex 未见过、尚无 approve；数据删除面已收口。预期 round 12 approve；若另有新实质 finding 则评估是否向用户报告 plan 深度）。

### Round 12 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..11 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-11 防复活主路径成立；但 `clear()` 失败路径会留下错误的进程内水位。
- **Severity 计数**：critical 0 / high 0 / medium 1 / low 0（total 1）→ 已降到对自身上一轮修复的失败路径精炼，处于收敛尾部。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | med | accept（根因，对 round-11 的精炼）| `clear()` 先 `clearedAt = Date()` 再 `try write(.empty)`；若写盘失败抛错，HistoryVM 报"清空失败"但 store 已进入"已清空"水位 → 后续活动会话 upsert 被静默吞。失败操作改变了持久化语义 | 改顺序：`let watermark = Date(); try write(.empty); clearedAt = watermark`——仅 durable 写盘成功后才提交水位（抛错时赋值行不执行，水位不变）。补 `test_clear_writeFailure_throws`（不可写路径 → clear 抛错传播）+ 代码注释说明顺序保证 |

- **附带核查**：`delete(id:)` 已是正确顺序（`try update {...}` 成功后才 `deletedIDs.insert(id)`），Codex 未 flag，无需改。
- **Reject/Defer**：无（1 条 accept）。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan：Task 4 clear 顺序 + 1 测试）。
- **Drift**：in-scope only（失败路径数据一致性，属 round-11 防复活同一面）。
- **Convergence**：continue → round 13（clear 顺序修复 Codex 未见过、尚无 approve；防复活面成功+失败路径均已收口。强烈预期 round 13 approve——findings 已收敛到"对上一轮修复的失败路径精炼"这一尾部，无法预名新的实质 finding，但仍需 Codex 实际看到此修复才能发 approve）。

### Round 13 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..12 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：clear 顺序修复已闭合；但 plan 漏掉"非 window 失败路径会再次改写 pinned window 会话的续聊/regenerate 状态"——本切片新增的持久模式状态回归。
- **Severity 计数**：critical 0 / high 0 / medium 1 / low 0（total 1）。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理 |
|---|---|---|---|---|
| 1 | med | accept（根因，修我 round-9 引入的回归）| 我 round-9 把会话状态设置（setFollowUpHandler/setAllowsRegenerate）+ endConversation-onDismiss 放进 openResultPanel，并假设它仅 window/structured 初次开窗运行。但 `showExecutionFailure`（AppDelegate+Execution.swift:183-209）对**非 window 失败** `if !shouldOpenResultPanelInitially { openResultPanel(...) }` 也调它 → 被钉 window 会话遇非 window 工具失败会被清续聊入口 / allowsRegenerate 设回 true / 被 endConversation。本切片新增的持久状态回归（非 round-10 的 transient 污染）| openResultPanel 加 `configuresConversationState: Bool = true`：仅 true 时配置会话状态 + 装 endConversation onDismiss；execute 初次开窗传默认 true，showExecutionFailure 非 window 失败传 false（(c-2)）。已核 openResultPanel 恰 2 调用点（execute line56 / showExecutionFailure line191）+ resultPanel.open 仅其内部 line85，无第三路径，覆盖穷尽。扩"已知限制"（非 window 失败仍经 open() 接管面板**内容**＝预存在，本切片只保护**状态**）+ smoke #6c 覆盖失败场景 |

- **Reject/Defer**：无（1 条 accept）。
- **panel-state 收敛轨迹**：round-9（消除 (b) 散乱 mutation，收敛到 openResultPanel）→ round-10（consumer.handle transient over-claim，收窄 + defer）→ round-13（openResultPanel 的第二调用点=失败面板，加 configuresConversationState gate）。至此会话**模式状态**（续聊入口/regenerate/session）在 success+failure、window+非 window、pinned 各组合下均不被错误改写；面板**内容**层共享为已记录的 pre-existing 已知限制。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan；showExecutionFailure 在已列入的 AppDelegate+Execution.swift 内，Files/git add 无需改）。
- **Drift**：in-scope only（修我前几轮引入的回归）。
- **Convergence**：continue → round 14（configuresConversationState 修复 + 穷尽性核查 Codex 未见过、尚无 approve；panel-state 面已系统收口。预期 round 14 approve）。

### Round 14 — 2026-05-31

- **Scope**：`--scope working-tree`（round-1..13 累计 plan 修复）
- **Verdict**：needs-attention
- **Summary（Codex）**：round-13 的 configuresConversationState gate 还没真正保护会话状态——`ResultPanel.open()` 调 `viewModel.reset()`，reset 无条件 `canFollowUp=false`，在 gate 之前就清掉了被钉会话续聊入口。
- **Severity 计数**：critical 0 / high 0 / medium 1 / low 0（total 1）。
- **walk-back 升级 + 用户决策**：这是 rounds 9/10/13/14 **同一根因第 4 次暴露**（共享 ResultPanel 被其他执行/失败复用并 reset，会话状态被各路径改写）。我一直在逐路径加 guard 保护"被钉会话跨执行存活"，而 `reset-on-open` 是面板基础机制——典型"加 guard 只位移 bug"（skill §2）。按操作原则 #3（load-bearing 设计模型）暂停问用户选会话生命周期模型。**用户选「瞬态会话（推荐）」**。
- **Decision Ledger**：

| # | 严重度 | 判定 | finding | 处理（采纳 Model 2 = 瞬态，净减代码）|
|---|---|---|---|---|
| 1 | med | accept（根因 walk-back）| open()→reset() 无条件清 canFollowUp，先于 round-13 gate；保护被钉会话的尝试在 reset 层失效 | **不再保护**——采纳瞬态会话模型：会话=面板当前占用者的多轮状态。`reset()` 无条件清会话状态（+ 补 `allowsRegenerate=true`）是**正确**的（每次开窗/接管面板清回无会话）；`openResultPanel` 按**当前** tool 模式重设。**移除** round-13 的 `configuresConversationState` 形参/gate/(c-2)（showExecutionFailure 回归原样不改）。非 window 成功不开面板→不影响被钉会话；接管面板的执行（structured/失败面板）按瞬态语义结束旧会话面板 UI（会话仍在 History）|

- **净效果**：代码**减少**（删 param/gate/(c-2)）。round-9/10/13/14 的 guard 链坍缩为"reset 清空 + 按当前占用者重设"无状态模型。
- **两条已知限制（重述）**：①瞬态代价——pin 会话后另一工具接管面板则不能在面板内续聊（会话在 History；reopen-from-history 是 spec §4.1 推后项）；②预存在内容层共享——consumer.handle 把任意执行的 tool-call/finish 写共享面板 transient 内容（不碰 canFollowUp/allowsRegenerate/session），post-1.0 多面板隔离重构。
- **Reject/Defer**：无（1 条 accept，转为采纳更简模型）。
- **Files touched**：`docs/superpowers/plans/...md`（仅 plan：Task 7 reset + Task 10 (c) 简化 + 已知限制重写 + smoke #6c + 辅助改动）。
- **Drift**：in-scope only（会话生命周期模型是用户拍板的 v1.0 范围决策）。
- **Convergence**：continue → round 15（瞬态模型简化 Codex 未见过、尚无 approve；这是 panel-state 子系统的根因坍缩。强预期 round 15 approve——会话状态不再需要"保护"，被接管即结束是设计本身）。

### Round 15 — 2026-05-31 ✅ APPROVE（循环终止）

- **Scope**：`--scope working-tree`（round-1..14 累计 plan 修复）
- **Verdict**：**approve** — "No material findings"
- **Summary（Codex）**：未找到会导致按 plan 实施后编译失败 / 测试失败 / 违反冻结 spec / 复活已删数据的新阻塞缺陷。瞬态会话模型自洽：reset 无条件清空符合"面板接管即清空旧会话 UI"语义，open 后按当前 displayMode 无条件重设 window/structured/失败面板状态，且无 `configuresConversationState`/gate 这类"保护被钉会话"的残留实现。
- **Decision Ledger**：无 finding。
- **退出判据命中**：`verdict == approve`（skill §7 终止信号）——不再跑确认轮。

---

## 循环总结（terminal）

- **轮次**：15 轮（Goal Contract 设安全上限 5，但用户指令"直到 approve"优先；循环全程健康——每轮真实 net-new finding、根因修复、无 reject-as-wrong/震荡/谄媚、severity 长期收敛）。
- **发现总数**：round1=6, r2=5, r3=4, r4=2, r5=1, r6=3, r7=2, r8=1, r9=1, r10=1, r11=1, r12=1, r13=1, r14=1, r15=0(approve)。共 **30 条 finding**，全部 accept 根因修复（含 2 次 walk-back）；**0 条 reject**；**1 条 defer**（consumer.handle transient 内容污染＝预存在已知限制，Codex round-10/11 认可）。
- **2 次暂停问用户（操作原则 #3）**：round-4 provider/model 范围（选"完整：锁定+展示"）、round-8 窗口 regenerate（选"窗口禁用"）、round-14 会话生命周期模型（选"瞬态会话"）——共 3 次 load-bearing 决策交用户拍板。
- **2 次 walk-back（skill §2，walk back abstraction 而非堆 guard）**：round-3 History 收窄为仅 window 会话；round-14 会话状态从"逐路径加 guard 保护被钉会话"坍缩为"瞬态模型（reset 清空 + 按当前占用者重设）"，净减代码。
- **关键修复面**：①InvocationReport 加 resolvedProviderId/Model（两路 recordCostAndFinishSuccess 同源）+ 会话内 provider/model 锁定 + History 展示；②mode-aware retry（runFollowUpStream + checkpoint/rewind）；③窗口禁用 regenerate + allowsRegenerate 与 canFollowUp 解耦；④ConversationStore 防复活（tombstone + clear-watermark，含 clear 失败路径顺序）；⑤瞬态会话生命周期模型；⑥若干编译 blocker（ConversationSummary.providerId、HistoryPage.list ViewBuilder、AppDelegate 存储属性落点）+ spec 对齐（History 显示时间）。
- **git**：循环全程**未提交**（fixes 累积在工作区，仅改 plan 文档 + 本 loop 日志）；提交切分由用户在循环终止后决定。
- **下一步**：plan 已获 Codex approve，可进入实施（writing-plans 的 Execution Handoff：subagent-driven 或 inline）。
