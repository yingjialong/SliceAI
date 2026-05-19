---
slug: phase-0-m3-mini-spec
created: 2026-04-28T15:00:00+08:00
last_updated: 2026-04-28T19:15:00+08:00
status: completed
total_rounds: 10
max_iterations: 10
---

# Codex Review Loop — Phase 0 M3 mini-spec adversarial review

## Goal Contract

**Task.** 评审 `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（610 行 mini-spec 草稿，commit `2e1019b` on `feature/phase-0-m3-switch-to-v2`），找出 (a) 与 v2 spec / M1+M2 plan / master todolist 不一致 / 矛盾的地方；(b) M3.0 5 步 rename / AppContainer 9 依赖装配 / 触发链改造 / 配置启动这 4 条改动主线的实施风险（例如 Swift 6 严格并发、git rename follow、命名冲突中间态、Settings UI 数据 binding 漂移）；(c) DoD / §4.2.5 回归清单的可执行性。**为什么做**：M3 改动跨 8 模块、风险比 M1/M2 高一个数量级（M1 plan:24 + master todolist:207 都明文要求 mini-spec 必须独立 spec + Codex review），mini-spec 是实施前的最后一道闸门，若设计层面有矛盾必须现在修订，不能带进 plan 阶段。

**Reference Documents.** Codex 应读以下文件做 alignment review（不仅 correctness）：
- v2 roadmap spec：`docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（§3.3 / §3.4 / §3.7 / §3.8 / §3.9 / §4.2.3 / §4.2.4 / §4.2.5）
- M1 plan：`docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（顶部 §A 实施期改名 / §B 第七轮评审 / §C 第八轮评审）
- M2 plan：`docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`（spec §3.4 step 对照表 / §C-1 zero-touch / §C-7 复制非替换）
- M2 Task-detail：`docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md`（§7.3 实施期偏离 plan / §7.6 M3 承接 backlog）
- Master todolist：`docs/v2-refactor-master-todolist.md`（§3.3 M3 + §8 SOP）
- mini-spec 自身：`docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（review 对象）
- 项目根 `CLAUDE.md`（项目通用规则 + 架构总览 + 模块依赖不变量）
- 真实代码（M1+M2 已合入 main）：`SliceAIKit/Sources/SliceCore/V2*.swift` / `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift` / `SliceAIApp/AppContainer.swift` / `SliceAIApp/AppDelegate.swift`（用于 sanity check mini-spec 描述的当前状态是否准确）

**In-scope.**
- `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（仅此一文件，review 对象）

**Out-of-scope（即使 Codex flag 也不动）.**
- 任何代码改动（mini-spec 阶段不写代码；implementation plan 阶段才写）
- v2 spec / M1 plan / M2 plan / 已合入 main 的 Task-detail / master todolist 内容（这些是 Reference Documents，不是 review 对象；不修改）
- v2 spec §5.2 D-1 ~ D-25 决策（不变；mini-spec 引入 D-26 ~ D-31 接续编号）
- M2 Task-detail §7.6 backlog 中已 defer 的 6 项（保持 defer 状态；mini-spec 不重新打开它们）
- v0.2 release tag 流程之外的 CI 配置（.github/workflows/ci.yml / release.yml 不动）

**Definition of Done.** 全部满足才退出循环：
1. Codex returns `approve` OR 所有残留 finding 都是 `low` 严重度且 reject reason 跨 2 轮稳定
2. 0 critical findings 处于 `accept` 但未修订状态
3. 所有 reject reasons 是 specific + falsifiable（不是 "I don't think so"）；且引用 spec / plan / 真实代码片段支撑
4. mini-spec 与 v2 spec / M1 plan / M2 plan / master todolist 之间所有 alignment 矛盾已修订（accept）或显式 deferred（含理由）

**Severity caps.** Pause loop 若任一轮：
- `critical > 3`，OR
- `(critical + high) > 5`，OR
- `total findings > 8`

**Max iterations.** 10（用户 R4 后 sync 决策：继续跑 R5 及后续几轮；从初始 5 提高到 10。Q2 原"每 5 轮 sync"原则保持——R10 后再 sync）

**Review scope.** branch (--base main)

## Design decisions summary

mini-spec 引入 6 个 design decisions（D-26 ~ D-31）+ 3 个用户初审 R1 已拍板的决议（Q1/Q2/Q3）。送给 Codex 的"应被攻击"清单（按 max-3 limit 选最有意义的 3 项）：

1. **D-26 · M3.0 rename 用 5 步小 commit 序列，Step 1 单 commit 不细拆**——Step 1 一次切 30+ 文件 caller 引用，是"零删除 + 零 rename"的最小风险窗口；按模块拆 5 个 sub-commit 反而让"切完一半"的中间态不可编译。
2. **D-29 · SettingsUI 数据 binding"零行为变化"策略**——v2 Tool / Provider 比 v1 多了 ToolKind / ProviderKind / capabilities / contexts / outputBinding 等字段；UI 层选择"100% 视觉等价 v1，新字段全部隐藏 + 默认值 + 不暴露"，把三态 / capability / context UI 推到 Phase 1+。
3. **D-30 · ResultPanel 消费 ExecutionEvent 在 SliceAIApp 层做适配，不动 Windowing**——把 ExecutionEvent 翻译为 ResultPanel 现有 API 调用的 helper 放在 composition root（SliceAIApp）而非 Windowing；好处是 Windowing 不依赖 Orchestration（保持 Windowing 仅依赖 DesignSystem 的不变量），坏处是 SliceAIApp 多 ~50 行 helper。

---

## Rounds

### Round 1 · 2026-04-28 · 15:05~15:15

- **Codex verdict.** needs-attention
- **Severity counts.** 1 critical · 4 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | critical | M3.0 Step 1 不是可编译的中间态 | mini-spec:231-247 | accept | Root cause: SelectionSnapshot 仅 5 字段（text/source/length/language/contentType），缺 v1 SelectionPayload 的 appBundleID/appName/url/screenPoint/timestamp；ExecutionSeed 真实用 frontApp:AppSnapshot + screenAnchor:CGPoint + timestamp，非 mini-spec 写的 AppDescriptor。Fix: §3.1.1/§3.1.2/§3.1.7/§3.2/§M3.0/§M3.1/§M3.2/D-26/D-28 大改；SelectionPayload 不删，AppDelegate 显式提取 SelectionSnapshot+AppSnapshot+screenAnchor+timestamp 给 ExecutionSeed |
| F1.2 | high | D-27 AppContainer wiring 表与真实 ExecutionEngine 构造器不匹配 | mini-spec:259-271 | accept | Root cause: ExecutionEngine.init 真实 10 依赖（mini-spec 漏 mcpClient + skillRegistry）；多 init 签名错（PermissionBroker(store:) / PermissionGraph(providerRegistry:) / DefaultProviderResolver(configurationProvider: closure) / PromptExecutor(keychain:llmProviderFactory:) / CostAccounting/JSONLAuditLog throwing）。Fix: D-27 表对照真实代码完全重写 + 加 bootstrap 伪代码 |
| F1.3 | high | D-30 事件适配表是旧契约 | mini-spec:463-473 | accept | Root cause: ExecutionEngine.execute 真实返回 AsyncThrowingStream<ExecutionEvent, any Error>；14 真实 case（.llmChunk/.finished/.failed(SliceError)/.notImplemented/.permissionWouldBeRequested/.sideEffectSkippedDryRun 等）；mini-spec 写的 .streamChunk/.completed/.permissionDenied/.invocationCompleted 都不存在。Fix: D-30 + §3.2 事件翻译表对照真实 enum 重写 + 加 stream 异常处理段 |
| F1.4 | high | D-29 违反 "Settings 界面无功能变化" 硬约束 | mini-spec:444-461 | accept | Root cause: v1 ToolEditorView 真实有 variables（variablesCard）+ displayMode Picker；v2 PromptTool.variables + V2Tool.displayMode 字段都存在；隐藏会破坏既有功能 + 违反 spec §4.2.4 DoD。Fix: D-29 重写——只隐藏 v2 新增高级字段（ToolKind 三态 / contexts / sideEffects / advanced ProviderSelection / capabilities），保留 v1 已有的 variables + displayMode UI binding；§4.2.5 加 variables 编辑回归项 |
| F1.5 | high | 配置首启语义误写（两份配置都不存在时 V2 store 不写盘） | mini-spec:204-217 | accept | Root cause: V2ConfigurationStore.load() 真实在 both-missing 时只 return DefaultV2Configuration.initial() 不写盘；mini-spec §3.3 写"都不存在 → 写 default 到 config-v2.json" 错误；DoD "config-v2.json 实际生成" 在全新安装路径不可执行。Fix: §3.3/§M3.3 重写真实状态 + M3 选方案 (a)（store 内聚，load 在 both-missing 时 try writeV2(default) + 单测 test_load_withNeither_writesDefaultToV2Path）；§4.2.5 加全新安装回归项 |

- **Fix applied.** 5 findings 全部 accept 并已落地修订 mini-spec：F1.1（SelectionPayload 不删 + AppDelegate 显式构造 ExecutionSeed）跨 8 段修订；F1.2（D-27 装配表对照真实 init 签名重写 + 加 bootstrap 伪代码）；F1.3（D-30 事件翻译表对照真实 14 case 重写 + 加 stream 异常处理）；F1.4（D-29 重写 binding 策略 + 区分 v1 已有 vs v2 新增 + 加 §4.2.5 variables 回归项）；F1.5（§3.3 重写 first-launch 真实行为 + M3 决策方案 a + §4.2.5 加全新安装回归项）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（610 行 → ~720 行；§0 评审表 / §1.2 / §2.1 / §3.1.1 / §3.1.2 / §3.1.3 / §3.1.7 / §3.2 / §3.3 / §M3.0 / §M3.1 / §M3.2 / §M3.3 / §M3.5 / D-26 / D-28 / D-29 / D-30 共 18 段修订）
- **Drift.** in-scope-only（所有修订仅在 mini-spec 文件内，未触及 spec / plan / 真实代码）
- **Status.** continue（进 R2 复查 5 处修订是否消除 alignment 漏洞，并扫一次新引入的不一致）

### Round 2 · 2026-04-28 · 15:25~15:36

- **Codex verdict.** needs-attention
- **Severity counts.** 2 critical · 2 high · 0 medium · 0 low
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| F2.1 | critical | App 接入新引擎漏掉 Xcode target 依赖 | mini-spec:305-322 | accept | Root cause: SliceAI app target 真实 packageProductDependencies 仅 7 个（HotkeyManager/LLMProviders/Permissions/SelectionCapture/SettingsUI/SliceCore/Windowing），无 Orchestration / Capabilities；AppContainer import 后 xcodebuild 必失败。Fix: §3.1.3 加 Modify SliceAI.xcodeproj/project.pbxproj 行；§M3.1 Exit DoD 把 xcodebuild 列为强制门禁 |
| F2.2 | critical | SelectionPayload→ExecutionSeed 伪代码字段 / init 标签错 | mini-spec:384-410 | accept | Root cause: ① SelectionPayload 真实字段 text/appBundleID/appName/url/screenPoint/source(SelectionPayload.Source 内嵌 enum)/timestamp，无 language/contentType；② AppSnapshot 真实 init 是 `bundleId:name:url:windowTitle:`（小写 d + 多 windowTitle）；③ payload.source: SelectionPayload.Source 不能直接喂 SelectionSnapshot.source（后者是 SelectionOrigin）。Fix: §3.2 + §M3.2 大改：language/contentType/windowTitle 一律 nil；引入 `SelectionPayload.toExecutionSeed(...)` extension 单一入口 + `Source.toSelectionOrigin()` 单方向 helper；M3.0 Step 1 加这两个 extension 到 SelectionPayload.swift |
| F2.3 | high | displayMode Picker 保留导致 v1 行为回归 | mini-spec:571-595 | accept | Root cause: v1 AppDelegate.execute 真实**忽略 displayMode 总开 ResultPanel**；v2 OutputDispatcher 在 non-window mode 走 .notImplemented；用户 v1 含 .bubble/.replace 的 tool 迁移后会执行失败 = 违反 spec §4.2.4 "Settings 无变化"硬约束。Fix: 新增 D-30b：v0.2 OutputDispatcher 在 non-window mode **降级 fallback 到 .window** + log deprecation；§2.3 表 OutputDispatcher 行更新；§4.2.5 加"v1 .bubble/.replace 配置迁移后触发不报 .notImplemented"回归项 |
| F2.4 | high | AppContainer.bootstrap throws 没落到 SwiftUI/AppDelegate 启动边界 | mini-spec:324-367 | accept | Root cause: SwiftUI @main 用 `@NSApplicationDelegateAdaptor(AppDelegate.self)` 创建 AppDelegate；AppDelegate.init() 是 `override init()` 不能 throws。mini-spec D-27 把 bootstrap 改 throws 但没说怎么进 SwiftUI 边界 → 实施期容易 try!/fatalError 失去用户可恢复 UX。Fix: D-27 末尾加"启动失败 UX"段：AppDelegate `override init()` 内 do/catch → 存 startupError → applicationDidFinishLaunching 检查 → NSAlert + NSApp.terminate(nil)；CostAccounting/JSONLAuditLog/configStore.current() 错误统一进同一 UX；§M3.3 不再单独写 alert 代码（指向 D-27）；§M3.1 Exit DoD 加启动失败 UX 验证；§4.2.5 加 appSupport 不可写场景回归项 |

- **Fix applied.** 4 findings 全部 accept 并已落地修订 mini-spec：F2.1（§3.1.3 加 Modify .pbxproj 行 + §M3.1 Exit DoD xcodebuild 门禁）；F2.2（§3.2 / §M3.2 / §3.1.3 修订 + 引入 toExecutionSeed extension + Source.toSelectionOrigin helper）；F2.3（新增 D-30b non-window 降级 fallback + §2.3 表 + §4.2.5）；F2.4（D-27 加启动失败 UX 段 + AppDelegate.init do/catch 模式 + §M3.1 Exit DoD + §M3.3 简化为指向 D-27 + §4.2.5 加 appSupport 不可写回归项）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~720 行 → ~830 行；§0 评审表 R2 / §2.3 / §3.1.3 / §3.2 / §M3.1 D-27 + Exit DoD / §M3.2 / §M3.3 / §M3.5 §4.2.5 / D-29 / D-30 / 新增 D-30b 共 11 段修订）
- **Drift.** in-scope-only（修订仅在 mini-spec 文件内；§4.2.5 加 3 项手工回归是 in-scope 测试用例扩展）
- **Status.** continue（进 R3 复查 4 处 R2 修订是否消除问题；重点 verify SelectionPayload extension + Source mapping helper + OutputDispatcher fallback + AppDelegate startupError 链路是否落得下去；同时扫 R1+R2 累计修订是否引入新不一致）

### Round 3 · 2026-04-28 · 15:48~15:58

- **Codex verdict.** needs-attention
- **Severity counts.** 1 critical · 1 high · 0 medium · 0 low（趋势收敛 R1=5 → R2=4 → R3=2）
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| F3.1 | critical | 同步 AppDelegate/bootstrap 设计无法承载 async 配置加载 | mini-spec:370-408 | accept | Root cause: R2 把 AppContainer.bootstrap 改 throws 留 sync init，但 bootstrap 内部含 try await configStore.current()（V2ConfigurationStore.current() 是 async throws）—— sync init 调 async 函数要么编译失败要么强迫 blocking Task hack。Fix: D-27 + §M3.1 + §M3.3 + §3.1.3 重写——bootstrap 改 `async throws`；AppDelegate.init 同步只初始化空状态；applicationDidFinishLaunching 启 `Task { @MainActor in try await AppContainer.bootstrap(); ... }`；catch → NSAlert + terminate；UI 在 Task 完成前是"启动中"状态 |
| F3.2 | high | ResultPanel 会同时从事件流和 OutputDispatcher 收到同一 chunk | mini-spec:659-675 | accept | Root cause: D-27 装 OutputDispatcher → ResultPanelWindowSinkAdapter；D-30 又把 .llmChunk → ResultPanel.append。真实 ExecutionEngine.runPromptStream 每 chunk 先 yield .llmChunk 后调 output.handle → 同 chunk append 两次 = 输出重复，破坏 v0.1 等价。Fix: D-30 关键修订段——chunk 写入路径**唯一通过** ExecutionEngine → output.handle → WindowSink.append → ResultPanel.append；EventConsumer 在 .llmChunk 仅记日志（不调 ResultPanel）；plan 阶段加 spy sink + spy panel 测试断言 chunk 只 append 一次；§3.2 触发链改造图加"双消费路径（单一写入所有者）"段；D-30 风险段加 `test_eventConsumer_doesNotAppendChunkToResultPanel` + `test_outputDispatcher_chunkAppendOnce_perChunk` |

- **Fix applied.** 2 findings 全部 accept 并已落地修订 mini-spec：F3.1（D-27 启动失败 UX 段重写为 async Task 模式 + AppDelegate 启动 Task 块伪代码 + bootstrap 签名 async throws + §3.1.3 AppContainer/AppDelegate Modify 行更新 + §M3.3 改造点指向 D-27）；F3.2（D-30 加"单一写入所有者"段 + 翻译表 .llmChunk 改为"仅记日志，不调 ResultPanel.append" + §3.2 触发链改造图加"双消费路径"图示 + plan 期 spy 测试要求）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~830 行 → ~870 行；§0 评审表 R3 / §3.1.3 AppContainer + AppDelegate 行 / §3.2 触发链 / §M3.1 D-27 启动失败 UX + 伪代码 / §M3.2 目标 / §M3.3 改造点 / D-30 主体 + 翻译表 .llmChunk + 风险段 共 8 段修订）
- **Drift.** in-scope-only（修订仅在 mini-spec 文件内）
- **Status.** continue（进 R4 复查 R3 修订是否消除问题：① async bootstrap + Task 启动模式是否引入新不一致 ② chunk 单一写入路径是否完整 ③ R1+R2+R3 累计 11 处修订是否引入隐式矛盾）

### Round 4 · 2026-04-28 · 16:08~16:18

- **Codex verdict.** needs-attention
- **Severity counts.** 1 critical · 2 high · 0 medium · 0 low（趋势：R1=5 → R2=4 → R3=2 → R4=3——不收敛但每轮 finding 类别不同）
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan |
|---|---|---|---|---|---|
| F4.1 | critical | M3.0 Step 1 依赖 M3.1 未完成的装配（任务边界漂移） | mini-spec §M3.0 Step 1 / §M3.1 Entry / §M3.4 Entry | accept | Root cause: 几轮修订让 M3.0 Step 1 包含"AppDelegate 切到 container.executionEngine.execute"和"删 ToolExecutor caller"，但当前 §M3.0 在 §M3.1（装配 ExecutionEngine）之前——Step 1 跑时 container.executionEngine 还不存在 = 不可编译。Fix: 重新对齐 M3 任务序列：§2.1 + §1.2 加执行顺序注，明确 M3.1 → M3.0 → M3.2 → M3.3 → M3.4 → M3.5 → M3.6；§M3.0 Entry 改"M3.1 完成（executionEngine 已就绪 + Xcode deps 加好 + async bootstrap UX 落地）"；§M3.0 Step 1 内文改"M3.1 已装配 executionEngine"+"ToolExecutor 物理文件不删（M3.4 单独删）"；§M3.1 Entry 改"无前置任务（M3 第 1 个执行的 task）"+ 加"v1 ToolExecutor / SelectionPayload / ConfigurationProviding 等仍存在并工作中"；§M3.2/§M3.3 标注"实质合入 M3.0 Step 1 / M3.1 + 单列为验收 task"；§M3.4 Entry 加"为什么单独成 task"段（git history 标记 v2 切换收尾） |
| F4.2 | high | §1.2/§2.2 范围段反向保留已修复结论（与 D-28/D-29/D-30b 矛盾） | mini-spec §1.2 第 1 项 / §2.2 第 4 项 | accept | Root cause: §1.2 第 1 项写"删除 SelectionPayload"——D-28 决议保留；§2.2 第 4 项写"不暴露 displayMode 选择器"——D-29 + D-30b 决议保留 v1 视觉 + 运行时 fallback。范围段是 mini-spec 顶部"权威概述"，未跟 Decisions 段同步会让 reviewer / implementer 按错误描述执行。Fix: §1.2 第 1 项删"SelectionPayload"+ 加"SelectionPayload 保留到 Phase 2，详见 D-28 修订版"；§2.2 第 4 项重写为"不暴露 OutputBinding sideEffects 编辑器；displayMode Picker 视觉保留 + OutputDispatcher 运行时 fallback 到 .window"；§2.2 顶部加注"若与 Decisions 冲突以 Decisions 为准；本 mini-spec 覆盖 master todolist 旧描述"；§2.2 末尾加"不删除 SelectionPayload"显式条目 |
| F4.3 | high | 回归门禁仍按 8 项签收（F1.4/F1.5/F2.3/F2.4 加的 4 项可被忽略） | mini-spec §M3.5 目标 + Exit DoD / §8 第 5 项 | accept | Root cause: §M3.5 目标和 Exit DoD 仍写"§4.2.5 8 项"；§8 第 5 项也写"§4.2.5 8 项"；F1.4/F1.5/F2.3/F2.4 加的 4 项虽已写入 §M3.5 表格，但 DoD 未加权——签收时按 8 项可"全过"但实际新增 4 项未验证 = R1/R2 修订引入的设计未被门禁守住。Fix: §1.2 第 5 项 / §2.1 第 6 项 / §M3.5 目标 / §M3.5 Exit DoD / §M3.6 release 顺序 / §7 D-31 风险注 / §8 第 5 项 全部把"8 项"改"12 项"；§M3.5 目标后加 12 项明细；§M3.5 Exit DoD 后加"新增 4 项不可省略"注；§8 第 5 项后加"新增 4 项 = variables / 全新安装 / displayMode fallback / 启动失败 UX" |

- **Fix applied.** 3 findings 全部 accept 并已落地修订 mini-spec：F4.1（§1.2 / §2.1 / §M3.0 Entry + Step 1 / §M3.1 Entry + 目标 + 冒烟成功定义 / §M3.2 Entry / §M3.3 Entry / §M3.4 Entry + 注意事项 共 9 段重写明确依赖序列）；F4.2（§1.2 第 1 项 + §2.2 顶部加注 + §2.2 第 4 项 + §2.2 末尾加 SelectionPayload 不删 共 4 段同步 Decisions）；F4.3（§1.2 第 5 项 + §2.1 第 6 项 + §M3.5 目标 + §M3.5 12 项明细 + §M3.5 Exit DoD + §M3.6 release 顺序 + §7 D-31 风险注 + §8 第 5 项 共 8 处"8 项"→"12 项"）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~870 行 → ~895 行；§0 评审表 R4 / §1.2 第 1+5 项 + 任务执行顺序注 / §2.1 列表 + 顺序注 / §2.2 顶部 + 第 4 项 + 新增条目 / §M3.0 Entry + Step 1 / §M3.1 Entry + 目标 + 冒烟段 / §M3.2 Entry / §M3.3 Entry / §M3.4 Entry + 注意事项 / §M3.5 目标 + 12 项明细 + Exit DoD / §M3.6 release 顺序 / §7 D-31 风险注 / §8 第 5 项 共 21 处编辑）
- **Drift.** in-scope-only（修订仅在 mini-spec 文件内）
- **Status.** **5-round sync milestone**——按用户 R1 Q2 决策"每 5 轮回 sync 进度"，R4 完成后停下汇报；max_iterations=5 已用 4 轮，R5 是最后一轮（APPROVE / 触发 Phase 3.2 termination 让用户决定 extend / pause）。**用户 sync 后决定**：继续跑 R5 + 后续几轮；**max_iterations 提高到 10**；同时给出根因反馈："修复必须从根因做，否则不收敛"——本轮起 Codex prompt 显式要求审 fix 是 root cause vs symptom。

### Round 5 · 2026-04-28 · 16:50~17:05

- **Codex verdict.** needs-attention
- **Severity counts.** 1 critical · 2 high · 0 medium · 0 low（趋势：R1=5 → R2=4 → R3=2 → R4=3 → R5=3）
- **Root-cause audit Codex 表态.**
  - F2.2 toExecutionSeed extension = **可接受 root-cause 边界修复**（v0.2 字段稀疏是 design intent，helper 没掩盖契约）
  - F2.3/D-30b OutputDispatcher fallback = **symptom 妥协但标注已诚实**——接受 v0.2 不立即偿还
  - F3.1 startupError 状态变量 = 已被 R3 推翻为 stateless async Task，**只在历史记录中残留**
  - F3.2 chunk 单一写入路径 = D-30 中已基本 root-cause 修复
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan | root cause / symptom |
|---|---|---|---|---|---|---|
| F5.1 | critical | M3.1 排到第一步但仍描述"替换" v1 AppContainer 依赖（与"v1 触发链仍工作"自相矛盾） | mini-spec §3.1.3 AppContainer.swift Modify 行 / §M3.1 / D-27 装配表 + bootstrap 伪代码 / §M3.0 Step 1 | accept | Root cause: R4 重排 task 顺序时只改了 §M3.0/§M3.1 Entry 段，没回看 §3.1.3 表 + D-27 + bootstrap 伪代码 + §M3.0 Step 1——这些段仍按"M3.0 → M3.1"次序写"M3.1 替换 v1"。M3.1 真实应是 **additive**（保留 v1 装配 + 新增 v2 装配），M3.0 Step 1 才删 v1 装配。Fix: §3.1.3 表把 AppContainer.swift / AppDelegate.swift 拆成 "Modify (additive) M3.1" + "Modify (replace) M3.0 Step 1" 两行；§M3.1 加冒烟 DoD "v1 触发链仍正常工作"硬约束 + grep 验收 caller=0；D-27 装配表加 v2ConfigStore 行 + v1 keep 行 + 命名规则段（M3.1 时仍用 V2*/PresentationMode）；bootstrap 伪代码彻底重写反映 additive；§M3.0 Step 1 描述加"删 AppContainer 内 v1 字段（FileConfigurationStore + ToolExecutor）"动作 | **root cause level finding** |
| F5.2 | high | §M3.0 Step 2 与 §M3.4 关于 ToolExecutor 删除时机互相冲突 | mini-spec §M3.0 Step 2 / D-26 Step 2 / §3.1.1 ToolExecutor 行 / §3.1.7 ToolExecutorTests 行 / §M3.4 Entry "7 个文件" | accept | Root cause: R4 把 ToolExecutor 物理删除留给 M3.4 单独 commit，但只改了 §M3.4 Entry 文字，没回看 §M3.0 Step 2 + D-26 Step 2 + §3.1.1/§3.1.7 表里仍写 "Step 2 删 ToolExecutor / 7 个文件"。Fix: §M3.0 Step 2 表改 "6 个文件"+ 显式 "ToolExecutor.swift / ToolExecutorTests.swift 不删"；D-26 Step 2 同步；§3.1.1 ToolExecutor 行改 "Delete (in M3.4)"；§3.1.7 ToolExecutorTests 行同；§M3.4 Entry "7 个文件" → "6 个文件" | **symptom level finding**（文档自洽性，不影响 design） |
| F5.3 | high | D-30b fallback 指向不存在的 `OutputDispatcher.dispatch(chunk:mode:)` API | mini-spec D-30b 决策段 / 落地位置段 | accept | Root cause: D-30b 凭印象写方法名 `dispatch(chunk:mode:)`，但真实 protocol 是 `OutputDispatcherProtocol.handle(chunk:mode:invocationId:) async throws -> DispatchOutcome`（OutputDispatcherProtocol.swift line 33-38；ExecutionEngine+Steps.swift line 247 调用 `output.handle`）；返回 `.notImplemented(reason:)` 不是 throw；mini-spec 当前文字会让 plan 阶段写错单测 / fallback 实现，F2.3 修订落不到真实运行路径。Fix: D-30b 决策段对照真实 API 重写——方法名 `handle`；返回 `DispatchOutcome` 二态；non-window 5 个分支 `await windowSink.append → return .delivered`；首 chunk 节流 log（actor `loggedInvocations: Set<UUID>` state）；plan 单测覆盖 5 个 PresentationMode case + 窗口回归保护；mode 类型 M3.0 Step 4 前后 PresentationMode/DisplayMode | **root cause level finding**（API 描述错，但 fallback 设计本身是合理 KISS 妥协；fix 后 root cause 已定位准确） |

- **Fix applied.** 3 findings 全部 accept 并已落地修订 mini-spec：F5.1（§3.1.3 表 AppContainer/AppDelegate 拆 additive vs replace 两行 + §M3.1 目标 + Entry + 冒烟成功定义 + Exit DoD 加 v1 触发链硬约束 + grep 验收 + 注意事项行数预估更新；D-27 装配表加 命名规则段 + v2ConfigStore 行 + v1 keep 行；bootstrap 伪代码彻底重写为 additive 模式；§M3.0 Step 1 描述加 "AppContainer 删 v1 字段 + rename v2ConfigStore → configStore" 动作）；F5.2（§M3.0 Step 2 表改 6 个文件 + 显式 "ToolExecutor 不删"；D-26 Step 2 同步；§3.1.1 ToolExecutor 行 + §3.1.7 ToolExecutorTests 行加 "Delete (in M3.4)" 标记；§M3.4 Entry "7 个文件" → "6 个文件"）；F5.3（D-30b 决策段对照真实 API 重写——方法名 / 返回类型 / 5 个 case fallback 实现 / 首 chunk 节流 / plan 单测要求 / mode 类型 rename 时序）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~895 行 → ~970 行；§0 评审表 R5 / §3.1.1 ToolExecutor 行 / §3.1.3 SliceAIApp 表整体重写 + 注 / §3.1.7 ToolExecutorTests 行 / §M3.0 Step 1 表 + Step 2 表 / §M3.1 目标 + Entry + 冒烟成功定义 + 装配方案 D-27 表头注 + 装配表 + bootstrap 伪代码 + Exit DoD + 注意事项 / §M3.4 Entry / D-26 Step 2 / D-30b 决策段 共 14 段编辑）
- **Drift.** in-scope-only（修订仅在 mini-spec 文件内）
- **Status.** continue（进 R6 复查 R5 修订是否消除问题：① M3.1 additive 描述是否 leak 到其他段 ② D-30b 真实 API 描述是否一致 ③ R1~R5 累计 17 处修订是否引入隐式矛盾；按 max_iterations=10 还有 5 轮预算）

### Round 6 · 2026-04-28 · 17:15~17:35

- **Codex verdict.** needs-attention
- **Severity counts.** 1 critical · 2 high · 0 medium · 0 low（趋势：R1=5 → R2=4 → R3=2 → R4=3 → R5=3 → R6=3；**R6 全 3 finding 都是 root cause level**，证明根因审视让评审走深）
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan | root cause / symptom |
|---|---|---|---|---|---|---|
| F6.1 | critical | ToolExecutor 保留到 M3.4 让 M3.0 Step 1/2 不可编译 | mini-spec §M3.0 Step 1/2 + D-26 + §3.1.1/§3.1.7 + §M3.4 | accept | Root cause: R4/R5 把 "M3.4 单独删 ToolExecutor" 当作 task 边界优化（git history 漂亮），但 ToolExecutor.swift 内部 `import` & 引用 `ConfigurationProviding` / `Tool` / `Provider`——M3.0 Step 2 删这些时 ToolExecutor.swift 不能继续存在（编译失败破坏"每步四关绿"硬约束）。Fix: **撤销 F4.1/F5.2 的 M3.4 物理删除决策**——ToolExecutor.swift / ToolExecutorTests.swift 在 M3.0 Step 2 与 v1 类型族 6 个文件**同 commit 删**（共 7 个）；M3.4 改为 grep 收尾验证 task（不做物理删除）；§M3.0 Step 2 / D-26 Step 2 / §3.1.1 / §3.1.7 / §M3.4 全部回滚 + 重写 | **root cause level finding**（"为漂亮 git history 而牺牲可编译" = 经典的 task-edge symptom fix） |
| F6.2 | high | D-27 bootstrap 伪代码用不存在的构造签名 | mini-spec D-27 装配表 + bootstrap 伪代码 + 决策段 | accept | Root cause: R5 加 §3.1.5 ⚠ 段标注真实 API 时只改了那一段，没回看 D-27 同步——伪代码仍写 `V2ConfigurationStore(directory: appSupport)`（真实是 `(fileURL:legacyFileURL:)`）+ `OpenAIProviderFactory(keychain:)`（真实无参 init）+ D-27 决策段仍有 `DefaultPermissionBroker` 旧名残留。Fix: D-27 装配表 v2ConfigStore 行 + bootstrap 伪代码全部用真实 init 签名（V2ConfigurationStore(fileURL: appSupport.appendingPathComponent("config-v2.json"), legacyFileURL: appSupport.appendingPathComponent("config.json"))）+ OpenAIProviderFactory() 无参 + FileConfigurationStore(fileURL:) 真实签名 + D-27 决策段把 "DefaultPermissionBroker" 改 "PermissionBroker(store: PermissionGrantStore())" | **root cause level finding**（API 描述错 = 凭印象写真实代码的复发；"修订流程缺 doc-wide self-consistency check"） |
| F6.3 | high | F1.5 修改时机错位 → M3.1 Exit DoD 不可达 | mini-spec §M3.1 Exit DoD + §3.3 + §3.1.1 V2ConfigurationStore 行 + §M3.3 Entry | accept | Root cause: R4 把 M3.1 提前到 M3 第一执行 task，但 F1.5 的 V2ConfigurationStore.load() both-missing 写盘修改 listed in §M3.0/§M3.3 描述里——M3.0 在 M3.1 之后；M3.1 跑 bootstrap 调 `v2ConfigStore.current()` 时仍是 M2 当前的"return default 不写盘"行为 → M3.1 Exit DoD "config-v2.json 自动创建"不可达。Fix: §M3.1 改造点段加 sub-step A~E 顺序，明确 Sub-step A 是 SliceCore/V2ConfigurationStore.load() 改 + 单测；§3.3 决策段加"实施时机 = M3.1 Sub-step A"标注；§3.1.1 V2ConfigurationStore Modify 行加"in M3.1 Sub-step A"+ 实施时机解释；§M3.3 Entry 标注"F1.5 修改在 M3.1 Sub-step A 完成"+ §M3.3 改 entry 引用 | **root cause level finding**（task 序列重排时未同步前置依赖时机 = R4 重排后的连锁遗漏） |

- **Fix applied.** 3 findings 全部 accept 并已落地修订 mini-spec：F6.1（§M3.0 Step 2 表回滚到 7 个文件 + 显式 ToolExecutor 同 commit 删；D-26 Step 2 同步；§3.1.1 ToolExecutor 行 + §3.1.7 ToolExecutorTests 行回滚为 "Delete (in M3.0 Step 2)"；§M3.4 重写为"grep 收尾验证 task"+ 撤销原"物理删除"目标）；F6.2（D-27 装配表 v2ConfigStore 行 + bootstrap 伪代码 V2ConfigurationStore/OpenAIProviderFactory/FileConfigurationStore 三处用真实 init；D-27 决策段 DefaultPermissionBroker 旧名替换为 PermissionBroker(store:)）；F6.3（§M3.1 改造点加 sub-step A~E 顺序明确"A=SliceCore F1.5 前置修订"；§3.3 决策段 + §3.1.1 V2ConfigurationStore Modify 行 + §M3.3 Entry 全部加"F1.5 修改在 M3.1 Sub-step A"标注）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~970 行 → ~1010 行；§0 评审表 R6 / §3.1.1 V2ConfigurationStore + ToolExecutor 行 / §3.1.7 ToolExecutorTests 行 / §3.3 决策段 / §M3.0 Step 2 / §M3.1 改造点 sub-step + Entry / §M3.3 Entry / §M3.4 整段重写 / D-26 Step 2 / D-27 装配表 v2ConfigStore + promptExecutor + bootstrap 伪代码 + 决策段 共 12 段编辑）
- **Drift.** in-scope-only（修订仅在 mini-spec 文件内）
- **Status.** continue（进 R7 复查 R6 修订是否消除问题：① M3.0 Step 2 7 个文件同 commit 是否真无内部依赖循环 ② D-27 真实 init 与真实代码是否一致 ③ M3.1 Sub-step A~E 序列是否清晰 ④ R1~R6 累计 20 处修订是否引入隐式矛盾；按 max_iterations=10 还有 4 轮预算）

### Round 7 · 2026-04-28 · 17:40~17:55

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 2 high · 0 medium · 0 low（**趋势收敛**：R1=5 → R2=4 → R3=2 → R4=3 → R5=3 → R6=3 → R7=2，**0 critical** 是首次）
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan | root cause / symptom |
|---|---|---|---|---|---|---|
| F7.1 | high | D-27 bootstrap 仍用不可编译的构造器（ToolExecutor 漏 providerFactory 参数 / ContextProviderRegistry(...) 占位符不可编译） | mini-spec D-27 装配表 providerRegistry 行 + bootstrap 伪代码 line 403-413 | accept | Root cause: F6.2 修订真实 init 时只检查了 V2ConfigurationStore / OpenAIProviderFactory / FileConfigurationStore 三处，没回看 ToolExecutor / ContextProviderRegistry 的 init 签名——ToolExecutor 真实是 `init(configurationProvider:providerFactory:keychain:)` 漏了 providerFactory；ContextProviderRegistry 真实是 `init(providers: [String: any ContextProvider])` 而非 `(...)` 占位符。Sub-step C 按当前伪代码无法编译。Fix: D-27 装配表 providerRegistry 行改为 `ContextProviderRegistry(providers: [:])` 并加 v0.2 空 dict 备注；bootstrap 伪代码 ToolExecutor init 加 providerFactory 参数；llmProviderFactory 在 v1 toolExecutor + v2 promptExecutor 间复用同一 instance（factory 是无状态的） | **root cause level finding**（"凭印象写真实代码" 复发——审一个 init 修一个；下次必须 audit 所有 D-27 表中提到的 init 签名） |
| F7.2 | high | M3.4 grep gate 不可能（rename 后合法的 DefaultConfiguration 被列入 ban） | mini-spec §M3.4 改造点 grep 列表 + §2.1 M3.4 label | accept | Root cause: F6.1 重写 §M3.4 时 grep 列表把 `\\bDefaultConfiguration\\b` 加进 ban——但 M3.0 Step 3 故意把 `DefaultV2Configuration` rename 为 canonical `DefaultConfiguration`！rename 后源码必含 `DefaultConfiguration`，grep 命中 0 永远不可能。同时 §2.1 M3.4 label 仍写"删除 ToolExecutor"（应改为 grep-only 描述）。Fix: §M3.4 grep 列表删除 `\\bDefaultConfiguration\\b`；加注解释 v1/v2 同名情况——rename 后是合法 v2 名；§2.1 M3.4 label 改为"v1 → v2 切换收尾验证（grep-only validation）" | **root cause level finding**（verification invariant 本身错——rename 后哪些名字合法没列清；audit 应该跨 §M3.0 + §M3.4 一起做） |

- **Fix applied.** 2 findings 全部 accept 并已落地修订 mini-spec：F7.1（D-27 装配表 providerRegistry 行重写 `(providers: [:])` + 备注；bootstrap 伪代码 ToolExecutor init 加 providerFactory 参数 + llmProviderFactory 提前到 v1 装配前 + v2 装配复用同一 instance）；F7.2（§M3.4 grep 列表删 `DefaultConfiguration` + 加 rename 后合法名字段说明；§2.1 M3.4 label 改为 grep-only validation）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~1010 行 → ~1015 行；§0 评审表 R7 / §2.1 M3.4 label / D-27 装配表 providerRegistry 行 + bootstrap 伪代码 / §M3.4 grep 列表 共 4 段编辑）
- **Drift.** in-scope-only
- **Status.** continue（进 R8 复查 R7 修订是否消除问题：① bootstrap 伪代码现在是否完全可编译 ② §M3.4 grep 列表是否覆盖所有真删 v1 类型 + 临时改名 ③ R1~R7 累计 22 处修订是否引入隐式矛盾；按 max_iterations=10 还有 3 轮预算；趋势收敛若 R8 = 0~1 finding 可考虑 R8 后停下报告用户）

### Round 8 · 2026-04-28 · 18:00~18:25

- **Codex verdict.** needs-attention
- **Severity counts.** 1 critical · 2 high · 0 medium · 0 low（趋势：R1=5 → R2=4 → R3=2 → R4=3 → R5=3 → R6=3 → R7=2 → R8=3，**R8 critical 反弹**——R7 修订真实 init 时反而暴露出 R5 自查的"Step 1 第⑧条 LLMProviderFactory 升级"会让 ToolExecutor.swift 在 Step 1 末端编译失败；这是 R5 自查的复发症状，必须连根撤销）
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan | root cause / symptom |
|---|---|---|---|---|---|---|
| F8.1 | critical | M3.0 Step 1 第⑧条 LLMProviderFactory protocol 升级让 ToolExecutor.swift 编译失败 | mini-spec §M3.0 Step 1 第⑧条 + §3.1.5 ⚠ 段时机段 + D-26 Step 1 / Step 2 描述 | accept | Root cause: R5 自查发现 OpenAIProviderFactory 已在 M2 落地（M3 不新建）→ 把"LLMProviderFactory 协议升级 + OpenAIProviderFactory.make 改 + PromptExecutor.toV1Provider 删"打包放进 Step 1。但 ToolExecutor.swift 仍在 SliceCore 里活着，第 200+ 行的 `try providerFactory.make(for: provider)` 传的是 v1 `Provider`（来自 `Configuration.providers`）；Step 1 把 protocol upgrade 到 V2Provider 后类型不匹配 → ToolExecutor.swift 编译失败 → "每步四关绿"硬约束破裂。Fix: **撤销 R5 自查的"Step 1 第⑧条"** —— LLMProviderFactory protocol 升级 + OpenAIProviderFactory impl 改 + PromptExecutor.toV1Provider 删 + v1 Provider 类型删除 4 件事必须在 **M3.0 Step 2 同 commit 完成**（因为 4 件事互相牵引：v1 Provider 还在 → ToolExecutor 还在 → factory protocol 不能升 → executor 不能直接用 V2Provider）；§M3.0 Step 1 删除第⑧条；§M3.0 Step 2 表加 LLMProviderFactory.swift / OpenAIProviderFactory.swift / PromptExecutor.swift 三行（"同 commit 升级"）；D-26 Step 1 / Step 2 描述同步；§3.1.5 ⚠ 段时机段从 "Step 1" 改 "Step 2 与 v1 Provider 同 commit" | **root cause level finding**（R5 自查的复发——"先做能做的"反而违反了 task 内"四关绿"硬不变量；跨 task 的依赖链没在自查时跑通） |
| F8.2 | high | configStore.current() 7 处 callsite 没规定 try await + 错误策略 → Step 1 编译断裂或运行时丢失配置 | mini-spec §M3.0 Step 1 + Exit DoD + D-29 + 真实代码 MenuBarController:67 / AppDelegate:89/159/229/309 / SettingsViewModel:85 | accept | Root cause: §M3.0 Step 1 ⑦ "ConfigurationProviding rename V2 前缀去掉" 只描述 protocol 改名，没规定 7 个真实 callsite 的迁移策略——M2 的 V2ConfigurationStore.current() 是 `async throws`，但 7 处 callsite 当前用 `await configStore.current()`（无 try）；Step 1 改名后这些 callsite 编译失败（throws 没接）。即使加上 try，UI 路径（MenuBarController / AppDelegate）throws 后没策略 = 静默 default 覆盖内存态 → 用户配置丢失。Fix: §M3.0 Step 1 加第⑧条 sub-task：audit 7 处 callsite（MenuBarController:67 / AppDelegate:89 / 159 / 229 / 309 / SettingsViewModel:85）改 `try await configStore.current()` + 规定错误策略：UI 路径 catch + log skip（不 default 覆盖）；ViewModel 暴露 loadError state（禁止 default 覆盖内存态，触发用户重启 onboarding）；Step 1 Exit DoD 加 grep 人工核查命令 `grep -rn 'configStore.current()' SliceAIApp/ \| grep -v 'try await'` 应为空 | **root cause level finding**（rename task 只改 protocol 没 audit caller = symptom；real fix 必须 caller-side migration 同 commit） |
| F8.3 | high | ResultPanel.open 必须先于 stream consumer Task 启动（AsyncThrowingStream init 立即启动 producer task） | mini-spec §M3.2 改造点 + D-30 + Exit DoD | accept | Root cause: §M3.2 描述 "execute 返回 AsyncThrowingStream → consumer Task 处理 chunk → ResultPanel.append" 没规定 ordering 不变量——AsyncThrowingStream(unfolding:) 在 init 时就启动 producer task；如果 ResultPanel.open() 在 stream init 之后调用，open() 内部 reset viewModel.text = "" 会把已经到达的第一个 chunk reset 掉；用户看到第一个 chunk 永远丢失。Fix: §M3.2 改造点段加详细伪代码（① resultPanel.open(at: payload.screenPoint, onDismiss: { [weak self] in self?.streamTask?.cancel() }) → ② let stream = container.executionEngine.execute(...) → ③ streamTask = Task { for try await event in stream { ... } }）；D-30 顶部加 ordering invariant 段（强调 open MUST be before stream init）；plan 期加 spy test `test_immediateChunk_isNotLostByOpenReset`（mock provider 立即返回 chunk 验证不被 open reset 丢失）；§M3.2 Exit DoD 加 ordering 验证项 | **root cause level finding**（concurrency ordering invariant 没在 spec 写明 = 实施期靠"巧合正确"；下次必须 stream + UI lifecycle 同时审 ordering） |

- **Fix applied.** 3 findings 全部 accept 并已落地修订 mini-spec：F8.1（**撤销 R5 自查的"Step 1 第⑧条 LLMProviderFactory 升级"** ——§M3.0 Step 1 第⑧条删除；§M3.0 Step 2 表加 LLMProviderFactory.swift / OpenAIProviderFactory.swift / PromptExecutor.swift 三行+ "同 commit 升级"标注；D-26 Step 1 描述同步删；D-26 Step 2 描述加 LLMProviderFactory 升级；§3.1.5 ⚠ 段时机段从 "Step 1" 改 "Step 2 与 v1 Provider 同 commit"）；F8.2（§M3.0 Step 1 加第⑧条 audit + 错误策略 + Exit DoD grep gate；D-29 加 caller-side migration 段）；F8.3（§M3.2 改造点加 ordering 伪代码；D-30 顶部加 ordering invariant 段；§M3.2 Exit DoD 加 ordering 验证项 + plan 期 spy test 要求）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~1015 行 → ~1060 行；§0 评审表 R8 / §M3.0 Step 1 第⑧条删 + 新⑧条 audit / §M3.0 Step 2 表加 3 行 / §M3.0 Exit DoD / §M3.2 改造点 + Exit DoD / §3.1.5 ⚠ 段时机 / D-26 Step 1 / Step 2 / D-29 / D-30 顶部 共 11 段编辑）
- **Drift.** in-scope-only（修订仅在 mini-spec 文件内；spy test 要求是给 plan 阶段，不是给 mini-spec 加测试）
- **Status.** continue（进 R9 复查 R8 修订是否消除问题：① §M3.0 Step 1 / Step 2 task 边界现在是否真"每步四关绿"——Step 1 删第⑧条后是否还有跨 task 隐式依赖；② F8.2 7 处 callsite + 错误策略是否完整覆盖；③ F8.3 ordering 伪代码是否真能挡住 first-chunk 丢失；④ R1~R8 累计 25 处修订是否引入新隐式矛盾；按 max_iterations=10 还有 2 轮预算；若 R9 = 0 finding 或仅 nits 可立即终止 + 进入 archival）

### Round 9 · 2026-04-28 · 18:30~18:50

- **Codex verdict.** needs-attention
- **Severity counts.** 0 critical · 2 high · 0 medium · 0 low（趋势：R1=5 → R2=4 → R3=2 → R4=3 → R5=3 → R6=3 → R7=2 → R8=3 → **R9=2，0 critical** 第二次出现；finding 全部 root-cause level——R8 修订本身引入的 doc-wide 漂移 + 一个 R8 没覆盖的 invocation lifecycle 缺口）
- **Decision ledger.**

| # | severity | finding | file:line | decision | reason / fix plan | root cause / symptom |
|---|---|---|---|---|---|---|
| F9.1 | high | LLMProviderFactory 升级时机 doc-wide 漂移：§3.1.5 标题 + D-27 promptExecutor 行 + bootstrap 注释三处仍写"M3.0 Step 1 升级" | mini-spec line 172 (§3.1.5 标题) + line 370 (D-27 promptExecutor 行) + line 407 (bootstrap llmProviderFactory 注释) | accept | Root cause: R8 修订时只改了 §M3.0 Step 1 / Step 2 表 + D-26 Step 1 / Step 2 描述 + §3.1.5 内容段（line 179 ⚠ 段），没回看 §3.1.5 标题 / D-27 装配表的 promptExecutor 行 / bootstrap 伪代码注释——三处 "M3.0 Step 1" 残留。如果 implementer 按这些残留文字执行，Step 1 会再次升级 LLMProviderFactory protocol → ToolExecutor.swift 类型不匹配编译失败（与 R8 F8.1 完全相同的 root cause 复发）。Fix（已落地）：line 172 标题改 "（M3.0 Step 2）" + 加 F8.1/F9.1 修订标注；line 370 D-27 promptExecutor 行 "M3.0 Step 1 升级" → "【F8.1/F9.1 修订】M3.0 Step 2"；line 407 bootstrap 注释 "M3.0 Step 1 升级 protocol" → "M3.0 Step 2 升级 protocol"+ 加 F9.1 修订标注 | **root cause level finding**（R8 修订没做 doc-wide self-consistency check——经典 symptom fix 模式之一"改一处文字而不更新关联段"，跟 R4 的"8项→12项"是同类问题；这是用户 root cause 反馈中"修一处不 grep 全文 = symptom" 的复发） |
| F9.2 | high | ResultPanelWindowSinkAdapter 未定义 invocation 隔离契约 → 旧流可污染新面板 | mini-spec §M3.2 改造点 + D-30 + 真实 OutputDispatcherProtocol.swift:49 (WindowSinkProtocol 注释要求按 invocationId 隔离) | accept | Root cause: F8.3 修订只解决"快路径首 chunk 不被 open reset"的 ordering 不变量，没解决 stale invocation 跨流污染——真实 WindowSinkProtocol 在 protocol 注释（OutputDispatcherProtocol.swift:49）明文要求 "实现要求：按 `invocationId` 隔离不同 invocation 的 chunk 流，避免跨窗口窜流"，但 mini-spec 仅说注入 `ResultPanelWindowSinkAdapter(panel: resultPanel)` 没规定 adapter 怎么实现 invocation lifecycle。当用户在 invocation A 未结束（stream 还在 producing）时触发 B（Retry / 新划词 / 命令面板），ResultPanel.open(B) reset viewModel 后 A 仍可能通过 OutputDispatcher 把延迟到达的 chunk_A append 到已经显示 B 的 ResultPanel——chunk 跨流污染。F8.3 的 spy test test_immediateChunk_isNotLostByOpenReset 也只覆盖 open reset 顺序，不覆盖 stale invocation 串流。Fix（已落地）：§M3.2 改造点新增 single-flight invocation 段（① AppDelegate.execute 入口先 `streamTask?.cancel()` ② adapter 维护 `activeInvocationId` actor state，`append` 时 `guard invocationId == activeInvocationId else { return }` ③ 切换时机：execute 在 open 后 / stream 创建前调 `setActiveInvocation`，dismiss/finish/fail 调 `clearActiveInvocation`）+ 加 adapter 接口骨架（@MainActor final class with setActiveInvocation/clearActiveInvocation/append 实现）；§M3.2 Exit DoD 加 plan 期 2 个 spy test（test_overlappingInvocations_dropStaleChunks / test_dismissBeforeFirstChunk_doesNotAppendToClosedPanel）+ 手工 stress 验证（连续 5 次触发 cancel）；D-30 顶部加 single-flight invocation 契约段；D-27 装配表 outputDispatcher 行加 adapter 契约说明 | **root cause level finding**（concurrency invariant "ordering" 是 F8.3 的，但还有第二个 concurrency invariant "lifecycle isolation" 没在 spec 写明——同一类问题不同维度；下次修订必须把 stream 全生命周期所有 invariant 一次性 audit） |

- **Fix applied.** 2 findings 全部 accept 并已落地修订 mini-spec：F9.1（line 172 §3.1.5 标题改 Step 2 + F8.1/F9.1 修订标注；line 370 D-27 promptExecutor 行 Step 1 → Step 2；line 407 bootstrap llmProviderFactory 注释 Step 1 → Step 2）；F9.2（§M3.2 改造点加 single-flight invocation 段含 4 步契约 + adapter 接口骨架；§M3.2 Exit DoD 加 3 个验证项 + 2 个 spy test + 手工 stress；D-30 加 single-flight invocation 契约段；D-27 装配表 outputDispatcher 行加 adapter 契约说明）。
- **Files touched.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~1060 行 → ~1100 行；§0 评审表 R9 / §3.1.5 标题 / D-27 装配表 promptExecutor + outputDispatcher 行 / bootstrap 伪代码 llmProviderFactory 注释 / §M3.2 改造点 + Exit DoD / D-30 顶部 共 7 段编辑）
- **Drift.** in-scope-only（修订仅在 mini-spec 文件内；spy test 要求是给 plan 阶段，不是给 mini-spec 加测试代码）
- **Status.** continue（进 R10 = 最后一轮预算复查 R9 修订是否消除问题：① F9.1 三处 doc-wide 漂移是否真清零 grep "Step 1.*LLMProviderFactory|LLMProviderFactory.*Step 1" 仅命中 R8/R9 历史 ledger ② F9.2 single-flight invocation 契约是否完整覆盖所有 lifecycle 边界（execute 入口 cancel / setActiveInvocation 时机 / clearActiveInvocation 触发条件 3 处缺一不可） ③ R1~R9 累计 27 处修订是否引入新隐式矛盾 ④ 若 R10 = 0 finding 或仅 nits 立即 approve + archival；若 R10 仍 critical/high 触及新 root cause，hits max_iterations 后必须 sync 用户 + 进入 Phase 3.2 termination report）

### Round 10 · 2026-04-28 · 18:55~19:15 · **APPROVE — loop 收敛**

- **Codex verdict.** **approve**（"SHIP：R9 两个修订已闭合到可进入 implementation plan 的程度"）
- **Severity counts.** 0 critical · 0 high · 0 medium · 0 low（**首次 zero finding**；趋势：R1=5 → R2=4 → R3=2 → R4=3 → R5=3 → R6=3 → R7=2 → R8=3 → R9=2 → **R10=0**）
- **Codex 原文摘要.** "F9.1 的可执行段已统一到 M3.0 Step 2；剩余 Step 1/LLMProviderFactory 命中只在历史评审记录或解释段，不构成实施指令漂移。F9.2 已覆盖 cancel、setActive、clearActive、stale chunk drop、spy tests 和手工 stress，并同步到 §M3.2/D-30/D-27。未发现新的 critical/high root-cause blocker；残留风险属于 plan 或 implementation 阶段可处理的细节。"
- **Decision ledger.** 无 finding，无 decision；本轮纯复查通过。
- **Codex Next steps（推给 implementation plan 阶段）.** "进入 implementation plan 编写阶段，确保把 §M3.2 的 single-flight invocation 测试项逐条落到子任务验证清单中。"
- **Files touched.** 无（本轮只读 Codex 复查；mini-spec 文件无变更）
- **Drift.** 无
- **Status.** **terminated（approve）** — DoD 满足条件 1（Codex returns approve）；触发 Phase 3 archival → 进入 task #6 归档 mini-spec + 新建 Task-detail 索引

---

## Final summary

### Loop convergence

- **总轮次.** 10 轮（max_iterations=10 用满；最后一轮 R10 即 approve）
- **总 findings.** 30 个（R1=5 / R2=4 / R3=2 / R4=3 / R5=3 / R6=3 / R7=2 / R8=3 / R9=2 / R10=0）
  - 全部 accept + fix 落地，0 reject、0 defer
  - critical 累计 7（R1=1, R2=2, R3=1, R4=1, R6=1, R8=1）；high 累计 21
  - 后期 R6~R9 全部 root-cause level finding（用户 R4 后"必须根因审视" 反馈生效——loop 进入"修一个 root cause 就少一个症状家族"的真实收敛模式）
- **Trend interpretation.** finding 数没单调下降（R1=5 → R8=3），但严重度等级和性质演变明显：R1~R4 = "API 描述错 / 任务边界漂移" → R5~R7 = "additive 装配 / single-commit 边界 / API 真实签名" → R8~R9 = "task 内编译可行性 / concurrency lifecycle invariant" → R10 = approve。这是 Codex review loop skill 设计的"每修一个 root cause 就暴露下一层更深 root cause"螺旋——R10 终点说明已经触达 spec-level 设计完整性的边界。

### mini-spec 关键演变（R1 草稿 → R10 approve）

- **草稿** (~610 行) → **R10 终态** (~1032 行)；新增 ~422 行全部是 root-cause 修订内容（伪代码、API 真实签名、concurrency 契约、Exit DoD spy test 要求、ordering invariant、single-flight invocation 契约、错误策略 / caller migration）
- **决策段** D-26 ~ D-31（6 个）全部经历 ≥ 1 轮 Codex 修订；D-27 / D-30 经历 4+ 轮 ribbon-fix（每轮发现新 invariant）
- **任务序列** 经历 R4 大重排（M3.1 提前 / M3.0 在后 / M3.4 单删 ToolExecutor）+ R6 回滚（M3.4 改为 grep validation, ToolExecutor 回到 M3.0 Step 2）+ R8 修订（LLMProviderFactory upgrade 从 Step 1 移到 Step 2）= 任务边界经过 3 轮 root-cause 调整最终稳定
- **真实代码 alignment** 累计修正 ~12 处真实 init 签名 / 字段名 / 方法名 / 文件路径 / API 行号（V2ConfigurationStore / OpenAIProviderFactory / FileConfigurationStore / ContextProviderRegistry / ToolExecutor / SelectionPayload / AppSnapshot / SelectionSnapshot / OutputDispatcher / WindowSinkProtocol / ResultPanel / etc.）—— 草稿"凭印象写"vs 真实 main 代码的所有 deviation 已收敛

### Goal Contract DoD 满足情况

- ✅ DoD 1: Codex returns `approve`（R10 verdict = approve）
- ✅ DoD 2: 0 critical findings 处于 accept 但未修订状态（R10 = 0 finding）
- ✅ DoD 3: 所有 reject reasons 是 specific + falsifiable —— N/A，全部 accept
- ✅ DoD 4: mini-spec 与 v2 spec / M1 plan / M2 plan / master todolist 之间所有 alignment 矛盾已修订（accept）—— R1 ~ R9 共 30 findings 全部 accept + fix 落地

### Drift / scope guardrails

- **In-scope.** 全部修订仅在 `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md` 一个文件内，无 source code 改动、无 plan/Task-detail 改动、无 v2 spec / M1 plan / M2 plan 修订
- **Severity caps.** 全程未触发 critical>3 / (critical+high)>5 / total>8 任一上限——单轮最高 = R1 5 findings (1c+4h)
- **Operating Principle 2 验证.** R6/R8 两次"撤销前轮 fix" 决策（R6 撤销 R4/R5 的 M3.4 单删 / R8 撤销 R5 的 Step 1 LLMProviderFactory upgrade）证明 root-cause-vs-symptom 审视有效——若每轮只 patch 不撤销，loop 大概率不会收敛

### 进入 task #6 archival 的输入

- **mini-spec 文件路径.** `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~1032 行；状态 = approved）
- **关键 spy test 要求** (plan 阶段必须落到子任务验证清单——Codex Next steps 明确要求)：
  - `test_immediateChunk_isNotLostByOpenReset`（F8.3 ordering）
  - `test_overlappingInvocations_dropStaleChunks`（F9.2 single-flight）
  - `test_dismissBeforeFirstChunk_doesNotAppendToClosedPanel`（F9.2 lifecycle）
  - `test_eventConsumer_doesNotAppendChunkToResultPanel`（F3.2 单一写入）
  - `test_outputDispatcher_chunkAppendOnce_perChunk`（F3.2 计数验证）
  - `OutputDispatcherTests.test_handle_<5 个 mode>_fallsBackToWindowSink_returnsDelivered`（F5.3 / D-30b）
  - `OutputDispatcherTests.test_handle_window_unchanged`（D-30b 回归保护）
- **关键 §M3.0 sub-task 顺序** (plan 阶段必须 ToDoList 化)：M3.1（含 Sub-step A V2ConfigurationStore.load 修订）→ M3.0 Step 1（caller 切换 + audit configStore.current() 7 callsite）→ M3.0 Step 2（v1 类型族 7 文件 + LLMProviderFactory 升级 同 commit）→ M3.0 Step 3 / 4 / 5（rename V2 前缀 / DisplayMode 改名 / SelectionSource 改名）→ M3.2 / M3.3 / M3.4（验收 task）→ M3.5（v0.2 release）
- **下一步.** 进入 task #6：① 归档 mini-spec（status: approved；已嵌入 §0 评审表 R1~R10 完整 ledger，无需另写 archival doc）；② 新建 implementation plan `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`（基于 mini-spec 把 §M3.0~§M3.5 任务拆解为 ToDoList，含上述 spy test 要求）；③ 在 `docs/Task-detail/2026-04-28-phase-0-m3-switch-to-v2.md` 建任务索引（与 mini-spec + plan 关联）
