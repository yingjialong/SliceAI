# Phase 0 M3 · 切换 + 删旧 + 端到端回归 Mini-Spec

> **本文档定位**：M3 启动前的设计冻结文档，按 M1 plan 顶部 §A 的硬约束（plan:24）+ master todolist §3.3 的 entry criteria 撰写。**Codex review 通过后**才允许进入 `superpowers:writing-plans` 出实施 plan。

- **状态**：Draft（初稿，待用户初审 + Codex review loop）
- **作者**：Claude（基于 v2 spec §4.2.3 / §4.2.5 + M1 plan 顶部 §A/§B/§C + M2 Task-detail §7.6）
- **日期**：2026-04-28
- **承接**：Phase 0 M1 PR #1（commit `5cdf0f7`） + M2 PR #2（commit `3a5437d`），main 已 clean
- **输出 PR**：`feature/phase-0-m3-switch-to-v2`
- **预估人天**：M3.0 rename pass 3–5 + M3.1–M3.6 切换链路 4.5 = **8.5–10.5 人天**（注：master todolist:267 写"M3: 3–5 人天"是 spec §4.2.3 原始估算，未包含 M3.0 rename pass；M1 plan:24 已明文修正"M3 单独约 3–5 人天 ⋯ 但落地后重点完全不同"，本 mini-spec 按"M3.0 + M3.1–6 合并"重新校准）

---

## 0. 评审与修订（每轮 Codex review verdict 在此追加）

> 起始版本：本 mini-spec 撰写时 main HEAD `3a5437d`（M2 PR #2 merge commit），worktree `feature/phase-0-m3-switch-to-v2` baseline 等同。

| 轮次 | 日期 | Verdict | 处理 |
|---|---|---|---|
| Initial | 2026-04-28 | Draft | 起草初稿 610 行（待用户初审） |
| User R1 | 2026-04-28 | Accept | 用户初审：三个 Open Questions 全部接受 Claude 推荐——Q1=A（M3 PR merge 后立即发 v0.2 tag + DMG）/ Q2=A（Codex review 不设硬上限，每 5 轮回 sync 进度）/ Q3=A（M3.0 Step 1 保持单 commit 不拆）。本轮无范围 / 架构修订；§0 / §6 / §11.2 / D-26 / D-31 同步更新决议状态后进 Codex review loop |
| Codex R1 | 2026-04-28 | needs-attention（5 findings：1 critical + 4 high） | **5 findings 全部 accept**——根源全部是"mini-spec 草稿凭印象写，未对照真实 M1+M2 代码"。Fix（已落地）：① F1.1（critical, M3.0 Step 1 不可编译）→ §3.1.1/§3.1.2/§3.1.7/§3.2/§M3.0/§M3.1/§M3.2/D-26/D-28 大改：**SelectionPayload 不删**（M3 期间作为触发层包装类型与 SelectionSnapshot 共存），AppDelegate 显式从 SelectionPayload 提取 SelectionSnapshot + AppSnapshot + screenAnchor + timestamp 给 ExecutionSeed；② F1.2（high, D-27 wiring 表错）→ D-27 重写：10 个依赖（含 mcpClient + skillRegistry 漏写）+ 真实 init 签名（PermissionBroker(store:) / PermissionGraph(providerRegistry:) / DefaultProviderResolver 接 closure / PromptExecutor(keychain:llmProviderFactory:) / CostAccounting(dbURL:) throws / JSONLAuditLog(fileURL:) throws）；③ F1.3（high, D-30 事件契约错）→ D-30 + §3.2 重写：execute 真实返回 AsyncThrowingStream<ExecutionEvent, any Error>；事件 case 改为 .llmChunk / .finished(report:) / .failed(SliceError) / .notImplemented(reason:) / .permissionWouldBeRequested / .sideEffectSkippedDryRun / 等 14 个真实 case；不存在的 .streamChunk / .completed / .permissionDenied / .invocationCompleted 移除；④ F1.4（high, D-29 违反 Settings 无变化硬约束）→ D-29 重写：保留 v1 已有的 variables UI（PromptTool.variables 字段存在）+ 展示模式 Picker（V2Tool.displayMode 字段存在）；只隐藏 v2 新增的 ToolKind 三态 / contexts / sideEffects / advanced capabilities；§4.2.5 加"编辑 variables 后写入 config-v2.json 且执行生效"项；⑤ F1.5（high, config 首启语义错）→ §3.3/§M3.3 重写：V2ConfigurationStore.load() 真实在 both-missing 时只 return default 不写盘；M3 决策选方案 (a) 改 store 在 both-missing 时 writeV2(default) + 单测 |
| Codex R2 | 2026-04-28 | needs-attention（4 findings：2 critical + 2 high） | **4 findings 全部 accept**——R1 修订暴露出更深层的真实代码 / 框架边界问题。Fix（已落地）：① F2.1（critical, Xcode target 漏 Orchestration/Capabilities 依赖）→ §3.1.3 加"Modify SliceAI.xcodeproj/project.pbxproj：把 Orchestration + Capabilities packageProductDependencies 加入 SliceAI app target"+ §M3.1 Exit DoD 加 xcodebuild 验证作为强制门禁；② F2.2（critical, §3.2/§M3.2 伪代码字段错）→ 大改：SelectionPayload 真实字段是 text/appBundleID/appName/url/screenPoint/source(`SelectionPayload.Source` 内嵌 enum)/timestamp（无 language/contentType）；AppSnapshot 真实 init 是 `bundleId:name:url:windowTitle:`（小写 d + 多 windowTitle 字段）；payload.source 需通过 explicit mapping helper 转 SelectionOrigin；M3.0 Step 1 引入 `SelectionPayload.toExecutionSeed(...)` extension 替代散在各处的字段拷贝；③ F2.3（high, displayMode 保留导致 v1 行为回归）→ §2.3 + D-29 + D-30 + §4.2.5 增加 v0.2 兼容规则：OutputDispatcher 在 non-window mode 时**降级 fallback 到 .window** 并 log deprecation；保持"v1 AppDelegate 总开 ResultPanel"行为不变；§4.2.5 加 bubble/replace 旧配置回归项；④ F2.4（high, AppContainer.bootstrap throws 没落到 SwiftUI 边界）→ D-27 + §M3.1 + §M3.3 重写：AppDelegate `override init()` 内 do/catch 调 `AppContainer.bootstrap()`，失败时存 startupError；`applicationDidFinishLaunching(_:)` 检查 startupError → NSAlert + NSApp.terminate(nil)；CostAccounting/JSONLAuditLog/configStore.current() 错误统一进同一 UX |
| Codex R3 | 2026-04-28 | needs-attention（2 findings：1 critical + 1 high） | **2 findings 全部 accept**——R2 修订引入 2 个新缺陷。Fix（已落地）：① F3.1（critical, sync init + async configStore.current() 不可编译）→ D-27 + §M3.1 + §M3.3 重写第二轮：`AppContainer.bootstrap()` 改为 `static func bootstrap() async throws -> AppContainer`；AppDelegate.init() 同步只初始化空状态（`container: AppContainer? = nil; startupTask: Task<Void, Never>? = nil`）；`applicationDidFinishLaunching(_:)` 启动 `Task { @MainActor in ... }` 调 `try await AppContainer.bootstrap()` → 设 container → 注册 hotkey/menu/onboarding；catch → NSAlert + NSApp.terminate(nil)；启动期间 UI 处于"启动中"（菜单栏 icon 暗 / 划词不响应直至 Task 完成）；② F3.2（high, ResultPanel 双写 chunk）→ D-30 重写：删除 `.llmChunk(delta:) → ResultPanel.append(delta)` 映射；chunk 写入路径**唯一通过** `ExecutionEngine → output.handle → WindowSink.append → ResultPanel.append`；EventConsumer 在 .llmChunk 仅记日志（chunk 长度 / 频率），不调 ResultPanel；plan 阶段加 spy sink + spy panel 测试断言每 chunk 只 append 一次 |
| Codex R4 | 2026-04-28 | needs-attention（3 findings：1 critical + 2 high） | **3 findings 全部 accept**——前几轮修订让任务边界漂移 + 上层范围段没跟 Decisions 段同步。Fix（已落地）：① F4.1（critical, M3.0 Step 1 依赖 M3.1 未完成的装配）→ **重新对齐 M3 任务序列**：把"AppContainer 装配 + Xcode target deps + async bootstrap UX"提前为 **M3.1 先行**（独立 commit）；M3.0 rename pass 在 M3.1 之后做（Step 1 切 AppDelegate.execute 时 container.executionEngine 已就绪）；M3.4 删 ToolExecutor 单独保留作最后 commit；§M3.0/§M3.1/§M3.4 / §1.2 任务顺序段全部重写明确依赖；② F4.2（high, §1.2/§2.2 范围段反向保留已修复结论）→ §1.2 删除"SelectionPayload 删除"措辞改为"SelectionPayload 保留到 Phase 2"；§2.2 删除"不暴露 displayMode 选择器"改为"OutputBinding sideEffects UI 留 Phase 2，displayMode Picker 保留 v1 视觉但运行时 fallback 到 .window"；显式标注"mini-spec 覆盖 master todolist 旧描述"；③ F4.3（high, 回归门禁仍按 8 项签收）→ §M3.5 目标 / Exit DoD / §8 总 DoD 全部把"8 项"改为"12 项"，并显式列新增 4 项（variables / 全新安装写盘 / displayMode fallback / 启动失败 UX） |
| Codex R5 | 2026-04-28 | needs-attention（3 findings：1 critical + 2 high） | **3 findings 全部 accept**——R5 在用户根因反馈下专门审"R1~R4 fix 是 root cause vs symptom"。Codex 明确表态：F2.2 toExecutionSeed = root-cause 边界修复 ✅；F2.3/D-30b = symptom 妥协但标注已诚实 ✅；F3.1 startupError 已 stateless ✅；F3.2 chunk 单一写入路径已 root-cause ✅。新发现 3 finding：① F5.1（critical, root cause 级，M3.1 文字仍写"替换"v1 装配）→ **§3.1.3 表 + §M3.1 + D-27 + Step 1 全部重写为 additive**：M3.1 装配 v2 同时保留 v1 `configStore: FileConfigurationStore` + `toolExecutor: ToolExecutor`；M3.1 Exit DoD 加"v1 触发链仍正常工作"硬约束；D-27 加 v2ConfigStore + v1 keep 行 + 命名规则段（M3.1 时用 V2*/PresentationMode）+ bootstrap 伪代码反映 additive；§M3.0 Step 1 改为 caller 切换 + 移除 v1 装配字段；② F5.2（high, symptom 但文档自洽）→ §M3.0 Step 2 + D-26 Step 2 + §3.1.1/§3.1.7 表 + §M3.4 Entry 全部把"v1 SliceCore 7 个文件"改"6 个文件"，明确 ToolExecutor.swift / ToolExecutorTests.swift 由 M3.4 单独删；③ F5.3（high, root cause 但 API 描述错）→ D-30b 决策段对照真实 OutputDispatcherProtocol 重写：方法名 `dispatch(chunk:mode:)` → `handle(chunk:mode:invocationId:) async throws -> DispatchOutcome`；non-window 分支 `await windowSink.append → return .delivered`（不返回 .notImplemented）；首 chunk 节流 deprecation log（actor `loggedInvocations: Set<UUID>` state）；plan 期单测覆盖 5 个 mode case + 窗口模式回归保护；mode 类型在 M3.0 Step 4 前后是 PresentationMode/DisplayMode。**R5 自查 fix（非 Codex finding）**：发现 OpenAIProviderFactory M2 已落地无参 init / PromptExecutor 内有 toV1Provider helper；§3.1.5 重写 + D-27 promptExecutor 行 + Step 1 加第⑧条 LLMProviderFactory 升级动作 |
| Codex R6 | 2026-04-28 | needs-attention（3 findings：1 critical + 2 high；**全部 root cause level，证明根因审视有效**） | **3 findings 全部 accept**。Fix（已落地）：① F6.1（critical, R4/R5 的"M3.4 单独删 ToolExecutor"是 symptom fix，破坏"每步可编译"硬约束——ToolExecutor.swift 内部 import & 引用 ConfigurationProviding/Tool/Provider，M3.0 Step 2 删这些时 ToolExecutor 不能继续存在）→ **撤销 F4.1/F5.2 的 M3.4 物理删除决策**：ToolExecutor.swift / ToolExecutorTests.swift 在 M3.0 Step 2 与 v1 类型族 6 文件同 commit 删（共 7 个）；M3.4 改为 grep 收尾验证 task（不做物理删除）；§M3.0 Step 2 / D-26 Step 2 / §3.1.1 / §3.1.7 / §M3.4 全部回滚 + 重写；② F6.2（high, root cause 级 API 描述错）→ D-27 装配表 + bootstrap 伪代码用真实 init：`V2ConfigurationStore(fileURL:legacyFileURL:)` 不是 `(directory:)`；`OpenAIProviderFactory()` 无参不是 `(keychain:)`；`FileConfigurationStore(fileURL:)` 不是 `(directory:)`；D-27 决策段清掉 `DefaultPermissionBroker` 旧名残留；③ F6.3（high, F1.5 修改时机错位 → M3.1 Exit DoD 不可达）→ §M3.1 Entry + 改造点加 sub-step A~E 顺序明确"Sub-step A 是 SliceCore F1.5 前置修订"；§3.3 + §3.1.1 V2ConfigurationStore Modify 行 + §M3.3 Entry 全部标注"F1.5 修改在 M3.1 Sub-step A 完成"。**Codex R6 trend**：连续 2 轮 Codex 找的都是 root cause level finding（R5 = 2/3 root, R6 = 3/3 root），证明用户根因反馈让 review 走深；R5 自查也验证有用 |
| Codex R7 | 2026-04-28 | needs-attention（**2 findings：0 critical + 2 high；趋势收敛**） | **2 findings 全部 accept**。Fix（已落地）：① F7.1（high, root cause 级 API 描述错）→ D-27 装配表 + bootstrap 伪代码用真实 init：`ToolExecutor(configurationProvider:providerFactory:keychain:)`（漏 providerFactory 参数）；`ContextProviderRegistry(providers: [String: any ContextProvider])`（M2 真实是 struct + 显式 dict，没默认工厂）；v0.2 ContextProviderRegistry 传空 dict（builtin selection 由 ExecutionEngine 内部组装 ResolvedExecutionContext.selection 提供，不走 registry）；llmProviderFactory 在 v1 toolExecutor + v2 promptExecutor 间复用同一 instance；② F7.2（high, root cause 级 verification invariant 错）→ §M3.4 grep 列表删除 `\\bDefaultConfiguration\\b`（M3.0 Step 3 把 DefaultV2Configuration rename 为 canonical DefaultConfiguration，rename 后是合法 v2 名）；§2.1 M3.4 label 改为 "v1 → v2 切换收尾验证（grep-only validation）"。**Codex R7 trend**：finding 数从 R6=3 降到 R7=2，且 0 critical——R6 后 fix 在收敛，R8 大概率接近 approve |
| Codex R8 | 2026-04-28 | needs-attention（3 findings：1 critical + 2 high；**全部 root cause level**——R6/R7 fix 后又暴露更深层 ordering / API 边界问题） | **3 findings 全部 accept**。Fix（已落地）：① F8.1（critical, M3.0 Step 1 升级 LLMProviderFactory 让 ToolExecutor.swift 编译失败）→ **撤销 R5 自查的"Step 1 第⑧条 LLMProviderFactory 升级"**；移到 **M3.0 Step 2** 与 v1 类型族 + ToolExecutor 同 commit 升级（v1 Provider 删除 + protocol 升级 + OpenAIProviderFactory 改 + PromptExecutor.toV1Provider 删除 4 处必须同 commit）；§M3.0 Step 1 / Step 2 / D-26 Step 1/Step 2 / §3.1.5 ⚠ 段时机段 全部重写；② F8.2（high, configStore.current() 7 处 callsite 没规定 try await + 错误策略）→ §M3.0 Step 1 加第⑧条 sub-task：audit MenuBarController:67 / AppDelegate:89/159/229/309 / SettingsViewModel:85 改 `try await` + 错误策略（UI 路径 catch 跳过；ViewModel 暴露 loadError state，禁止 default 覆盖内存态）+ Step 1 Exit DoD 加 grep 人工核查命令；③ F8.3（high, ResultPanel 必须先 open 后 stream 的 ordering invariant 没在 §M3.2 写）→ §M3.2 改造点加详细伪代码（先 resultPanel.open + onDismiss callback 挂载 → 再 stream init → 再 streamTask 消费）+ D-30 顶部加 ordering invariant 段；plan 期加 spy test `test_immediateChunk_isNotLostByOpenReset`（mock 立即返回 chunk 验证不被 open reset）+ §M3.2 Exit DoD 加 ordering 验证项 |
| Codex R9 | 2026-04-28 | needs-attention（2 findings：0 critical + 2 high；**全部 root cause level**——R8 修订后暴露的 doc-wide 漂移与 invocation 生命周期缺口） | **2 findings 全部 accept**。Fix（已落地）：① F9.1（high, R8 改 §M3.0 Step 1/Step 2 + D-26 时漏改 §3.1.5 标题 + D-27 装配表 promptExecutor 行 + bootstrap 伪代码注释里的 "M3.0 Step 1 升级 LLMProviderFactory" → 三处 doc-wide 不一致 → implementer 按这些残留文字会在 Step 1 升级 protocol 让 ToolExecutor.swift 编译失败）→ §3.1.5 标题（line 172）+ D-27 装配表 promptExecutor 行（line 370）+ bootstrap 伪代码 llmProviderFactory 注释（line 407）三处 "Step 1" 全部改 "Step 2"；标注 F9.1 修订；② F9.2（high, root cause 级 invocation 隔离契约缺失——真实 WindowSinkProtocol（OutputDispatcherProtocol.swift:49）注释明文要求 "按 invocationId 隔离不同 invocation 的 chunk 流"，但 mini-spec 仅说注入 `ResultPanelWindowSinkAdapter(panel:)` 没规定 adapter 怎么实现 invocation 生命周期；当用户在 invocation A 未结束时触发 B，A 的延迟 chunk 仍可写到已 reset 为 B 的 ResultPanel）→ §M3.2 改造点新增 single-flight invocation 段：① AppDelegate.execute 入口先 `streamTask?.cancel()` 取消旧 stream；② adapter 维护 `activeInvocationId`，`append(chunk:invocationId:)` `guard invocationId == activeInvocationId else { return }`；③ 切换时机：execute 在 open 后 / stream 创建前调 `setActiveInvocation`，dismiss/finish/fail 调 `clearActiveInvocation`；新增 adapter 接口骨架（@MainActor final class）；§M3.2 Exit DoD 加 plan 期 2 个 spy test（test_overlappingInvocations_dropStaleChunks / test_dismissBeforeFirstChunk_doesNotAppendToClosedPanel）+ 手工 stress 验证（连续 5 次触发 cancel）；D-30 顶部加 single-flight invocation 契约段；D-27 装配表 outputDispatcher 行加 adapter 契约说明 |
| **Codex R10** | 2026-04-28 | **APPROVE**（0 findings；首次 zero finding，loop 收敛终止） | Codex 原文："SHIP：R9 两个修订已闭合到可进入 implementation plan 的程度。F9.1 的可执行段已统一到 M3.0 Step 2；剩余 Step 1/LLMProviderFactory 命中只在历史评审记录或解释段，不构成实施指令漂移。F9.2 已覆盖 cancel、setActive、clearActive、stale chunk drop、spy tests 和手工 stress，并同步到 §M3.2/D-30/D-27。未发现新的 critical/high root-cause blocker；残留风险属于 plan 或 implementation 阶段可处理的细节。"无 fix（本轮零 finding）。**Codex Next steps**："进入 implementation plan 编写阶段，确保把 §M3.2 的 single-flight invocation 测试项逐条落到子任务验证清单中。" **Loop 终止**——10 轮 max_iterations 用满；DoD 1+2+3+4 全满足；进入 task #6 归档 mini-spec + 新建 implementation plan |
| Plan Alignment R11 | 2026-04-29 | Align | 与 implementation plan fresh review 对齐：① M3.5 手工回归从 12 项扩为 13 项，新增"ToolEditorView 切 Provider 清空 modelId"回归；② release tag 口径从裸 `v0.2` 统一为 SemVer `v0.2.0`（v0.2 仍作为里程碑语义）；③ M3.1 C+D 明确为同一原子实现 / 提交单元，避免 C 完成但 D 未完成的不可编译中间态被当作可完成 task |
| Plan Optimization R12 | 2026-04-30 | Align | 与当前 implementation plan Step 4 对齐 Accessibility 回归语义：原"关闭 Accessibility 后验证 Cmd+C fallback"不可达；修正为两个子场景——AX revoke 时验证失败 UX / onboarding 提示且不走 startupError，AX 已授权但目标 app 不暴露 AX 文本时验证 Cmd+C fallback 命中。该修订消除 plan/spec drift |

---

## 1. 任务背景

### 1.1 当前状态

- **M1（PR #1，merge `5cdf0f7`）**：SliceCore 中以独立 V2* 命名（`V2Tool` / `V2Provider` / `V2Configuration` / `V2ConfigurationStore` / `DefaultV2Configuration`）落地了 v2 数据模型 + ConfigMigratorV1ToV2，v1 类型族（`Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `DefaultConfiguration` / `SelectionPayload` / `ToolExecutor` / SelectionCapture 中 `protocol SelectionSource`）保持原封不动。M1 落地时为避命名冲突，引入两个临时改名：
  - `DisplayMode`（v2 六态枚举）→ `PresentationMode`
  - `SelectionSource`（v2 枚举）→ `SelectionOrigin`
- **M2（PR #2，merge `3a5437d`）**：Orchestration / Capabilities 两个 SwiftPM target 落地为可独立单测的执行引擎骨架（`ExecutionEngine` actor + 9 个上游依赖 + PathSandbox + MCP/Skill 接口），**不接入 app 启动链路**。`SliceCore/ToolExecutor.swift` 自 baseline 起 0 行 diff（§C-7 复制非替换）。
- **App 当前行为**：仍是 v0.1 + M1 现状——`AppContainer` 装配的是 v1 `FileConfigurationStore` + `ToolExecutor`，触发链 `mouseUp / ⌥Space → SelectionService.capture() → SelectionPayload → AppDelegate.execute(tool:payload:) → ToolExecutor.execute(...)`。V2 类型族与 Orchestration 引擎对真实启动路径**完全无影响**。

### 1.2 M3 的目标

把 V2 类型族 + Orchestration / Capabilities 真正接入 app 启动链路：
1. 删除 v1 冲突类型族（`Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `ConfigurationProviding` / `DefaultConfiguration` / `ToolExecutor` / `protocol SelectionSource`）。**`SelectionPayload` 不删**——它是触发层包装类型，含 `appBundleID/appName/url/screenPoint/timestamp` 5 个 SelectionSnapshot 不含的字段，保留到 Phase 2 ExecutionSeed 直接由触发层构造时再处理（详见 D-28 修订版 + master todolist 旧描述被本 mini-spec 覆盖）。
2. 把 `V2Tool` → `Tool` 等 V2* 命名 rename 回 spec 原始意图；恢复 `PresentationMode → DisplayMode` / `SelectionOrigin → SelectionSource`。
3. `AppContainer` 装配 `ExecutionEngine` + 10 个依赖；触发链切到 `ExecutionEngine.execute(tool:seed:)`。
4. 配置文件路径切到 `~/Library/Application Support/SliceAI/config-v2.json`；首启 migrator 自动从 `config.json` 迁移；**v1 `config.json` 永不被修改**；全新安装时 ConfigurationStore 自动写入默认 config-v2.json。
5. 4 个内置工具（翻译 / 润色 / 总结 / 解释）在实机行为与 v0.1 等价；**§4.2.5 spec 原 8 项 + 本 mini-spec 新增 4 项 + plan fresh review 新增 1 项，共 13 项手工回归全过**（新增 5 项：variables 编辑写盘 / 全新安装写盘 / displayMode 降级 fallback / 启动失败 UX / ToolEditorView 切 Provider 清空 modelId）。
6. 发布 v0.2.0 tag（v0.2 archival milestone，无用户可见新功能；底层重构完成）。

> **任务执行顺序**（见 §2.1 + §4 各 task Entry）：M3.1 → M3.0 → M3.2 → M3.3 → M3.4 → M3.5 → M3.6。M3.1（AppContainer 装配 + Xcode deps + async bootstrap UX）必须**先于** M3.0（rename / 删 v1 / 切 caller），因为 M3.0 Step 1 把 AppDelegate 切到 `container.executionEngine.execute` 时 executionEngine 必须已装配可用。详见 §2.1 注释 + §M3.0 / §M3.1 Entry 段。

### 1.3 为什么需要一个 mini-spec

M1 plan:24 + master todolist:207 都明文要求："spec §4.2 M3 的任务清单需要在 M3 启动前独立 spec 一次"。原因：

- **M3 风险比 M1/M2 高一个数量级**：M1 / M2 都受 §C-1 zero-touch 约束（v1 8 模块 + SliceAIApp 0 行 diff），错了也只影响新 target；M3 必须 **改 SliceAIApp + 删 v1 + rename V2***，错了就是 app 启动崩溃 / 用户配置丢失 / 4 个内置工具行为漂移。
- **spec §4.2.3 M3 任务清单只列了 6 项粗粒度任务（M3.1–M3.6），没展开 M3.0 rename pass**——M1 plan 落地时引入的"V2* 独立类型 + 实施期改名"两个决策让 M3 的工作量重心从"删 ToolExecutor + 切 AppContainer"转移到"rename 整个类型族 + 修 SettingsUI 数据 binding + 处理首启 migration"，必须独立 spec 一次。
- **跨 8 个模块的改动需要明确顺序**：v1 删除顺序错了会引入命名冲突 / 编译循环依赖；rename 顺序错了会让 V2* 名字临时被双方占用。Mini-spec 必须把"小步序列"写死，否则 implementer 容易踩坑。

---

## 2. 范围（In-scope / Out-of-scope）

### 2.1 In-scope（M3 必做）

> **执行顺序（按 §4 各 task Entry 依赖）**：M3.1 → M3.0 → M3.2 → M3.3 → M3.4 → M3.5 → M3.6。M3.1 先于 M3.0 是 **R4 修订（F4.1）**——M3.0 Step 1 切 caller 到 ExecutionEngine 时，executionEngine 必须已由 M3.1 装配；任务编号保持 spec §4.2.3 历史对齐。下方列表按**编号排序**保留可读性，**实际执行序列**以箭头注释为准。

- [x] M3.1 — `AppContainer` 装配 `ExecutionEngine` + 10 个依赖 + Xcode SliceAI app target 加 Orchestration / Capabilities 依赖 + async bootstrap UX → **第 1 个执行**
- [x] M3.0 — v1 文件删除 + V2* 类型 rename 回 spec 原意（含 `PresentationMode → DisplayMode` / `SelectionOrigin → SelectionSource`） → **第 2 个执行**
- [x] M3.2 — 触发通路（`mouseUp` / `⌥Space`）从 `ToolExecutor.execute` 切到 `ExecutionEngine.execute(tool:seed:)` → **第 3 个执行**（实质合入 M3.0 Step 1，作为验收 task）
- [x] M3.3 — `ConfigurationStore`（rename 后）启动按 §3.7 规则选 v1/v2 路径 + 跑 migrator → **第 4 个执行**（实质合入 M3.1 bootstrap，作为验收 task）
- [x] M3.4 — **【F7.2 修订】v1 → v2 切换收尾验证（grep-only validation）**——物理删除已合并到 M3.0 Step 2（F6.1）；M3.4 仅做 grep 残留验证 + README/CLAUDE.md 同步 → **第 5 个执行**
- [x] M3.5 — §4.2.5 spec 原 8 项 + mini-spec 新增 4 项 + plan fresh review 新增 1 项，共 13 项端到端手工回归全过（分工：单测部分由 Claude / 真机操作部分由用户） → **第 6 个执行**
- [x] M3.6 — 文档归档（`README.md` / `docs/Module/*.md` / Task-detail）+ 发 v0.2.0 release tag + 打 unsigned DMG → **第 7 个执行**

### 2.2 Out-of-scope（M3 明确不做）

> **本节描述 v0.2 主要 out-of-scope 边界。若与本 mini-spec 后续 Decisions（D-28 / D-29 / D-30b）冲突，以 Decisions 为准**——mini-spec 在 Codex review loop R1 ~ R4 中收敛过，Decisions 段反映最终设计，范围段是历史叙述线索；同理本 mini-spec **覆盖 master todolist §3.3 中"删除 SelectionPayload" / "不暴露 displayMode" 等旧描述**。

- ❌ **不加任何用户可见新功能**（spec §4.2.4 DoD 硬约束）。Settings UI 行为零变化，仅改数据 binding。
- ❌ **不暴露 ToolKind 三态编辑器**：v0.2 ToolEditorView 仅暴露 `.prompt` kind 编辑（与 v1 视觉等价）；`.agent` / `.pipeline` 编辑器留 Phase 2。
- ❌ **不暴露 ProviderSelection 全形态**：v0.2 仅暴露 `.fixed(providerId:modelId:)`（与 v1 picker 视觉等价）；`.capability` / `.cascade` 留 Phase 1。
- ❌ **不暴露 OutputBinding sideEffects 编辑器**：v0.2 outputBinding 默认 nil；sideEffects UI 留 Phase 2。**displayMode Picker 视觉保留**（v1 ToolEditorView 已有）——D-29 决议保持 binding，D-30b 决议运行时 OutputDispatcher 在 non-window mode **降级 fallback 到 .window** + log deprecation；用户视觉与 v1 等价。
- ❌ **不接入真实 MCPClient / SkillRegistry**：M2 已建 `MCPClientProtocol` / `SkillRegistryProtocol` + `MockMCPClient` / `MockSkillRegistry`，M3 装配时仍用 Mock；真实实现留 Phase 1 / Phase 2。
- ❌ **不接入真实 PermissionBroker UX**：M2 已建 `PermissionBroker` + `GateOutcome` 4-state，但当前 production 走 default-allow + provenance hint；真实弹窗 UX 留 Phase 1。
- ❌ **不做 v1 → v2 双写 / 降级**：v2 app 只写 `config-v2.json`，永不写 `config.json`（spec §3.7 明文）。
- ❌ **不删除 SelectionPayload**：详见 §1.2 第 1 项 + D-28 修订版（保留到 Phase 2）。

### 2.3 与其他 Phase 的边界

| 边界条件 | M3 处理 | 推到 Phase 1+ |
|---|---|---|
| `MCPClientProtocol` 真实接入 | Mock 装配 | Phase 1 真实 stdio/SSE client |
| `SkillRegistryProtocol` 真实接入 | Mock 装配 | Phase 2 真实 SkillRegistry + scanning |
| `PermissionBroker` 真实弹窗 | default-allow + audit log 写到 jsonl | Phase 1 真实 UX |
| `OutputDispatcher` 非 `.window` 分支 | **【F2.3 修订】**v0.2 把 `.bubble / .replace / .silent / .structured / .file` 等 non-window mode **降级 fallback 到 .window** 并记录 deprecation log；保持 v1 行为（v1 AppDelegate 总开 ResultPanel） | Phase 2 BubblePanel / InlineReplaceOverlay / StructuredResultView 等真实 sink |
| `ContextProvider` 真实 provider 实现 | M2 已注册"selection from seed"内置 provider；其他都是空实现 | Phase 1 5 个核心 provider（`app.windowTitle` / `app.url` / `clipboard.current` / `file.read`） |

---

## 3. 架构变更总览

### 3.1 rename / 删除 / 新建 文件清单

> **命名约定**：表格列出所有文件层操作。"Rename" 用 `git mv` 让 git 能 follow rename history（避免 git 把它识别为 delete + add）。"Modify" 列只列 import / 类型引用 / 数据 binding 的改动，不列纯 whitespace。

#### 3.1.1 SliceCore 层（M3.0）

| 操作 | 路径 | 说明 |
|---|---|---|
| Delete | `SliceAIKit/Sources/SliceCore/Tool.swift` | v1 Tool 整体删除（含 v1 `public enum DisplayMode`） |
| Delete | `SliceAIKit/Sources/SliceCore/Provider.swift` | v1 Provider 整体删除 |
| Delete | `SliceAIKit/Sources/SliceCore/Configuration.swift` | v1 Configuration 整体删除 |
| Delete | `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift` | v1 `FileConfigurationStore` actor 整体删除（实现 `ConfigurationProviding` protocol） |
| Delete | `SliceAIKit/Sources/SliceCore/ConfigurationProviding.swift` | v1 protocol 整体删除——使用方仅剩 SettingsViewModel；M3.0 期间改 SettingsViewModel 直接持有 `V2ConfigurationStore`（rename 后是 `ConfigurationStore`）；**【F6.1 修订】**ToolExecutor / FileConfigurationStore / 本 protocol 必须在 M3.0 Step 2 同 commit 删（避免任何分开删导致编译失败） |
| Delete | `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift` | v1 default 4 个内置工具整体删除 |
| Delete (in M3.0 Step 2) | `SliceAIKit/Sources/SliceCore/ToolExecutor.swift` | **【F6.1 修订，撤销 F5.2】**v1 ToolExecutor 整体删除——必须与 v1 类型族 6 个文件同 commit 删（ToolExecutor 依赖 ConfigurationProviding/Tool/Provider，分开删破坏"每步四关绿"）；M3.4 改为 grep 收尾验证 task，不再做物理删除 |
| **Keep** | `SliceAIKit/Sources/SliceCore/SelectionPayload.swift` | **【F1.1 修订】**v1 SelectionPayload 不删——它含 `appBundleID / appName / url / screenPoint / timestamp` 5 个字段，是触发层包装类型；SelectionSnapshot 仅含选区领域字段（text / source / length / language / contentType），无法接管这些；SelectionService.capture() 继续返回 `SelectionPayload?`（M3 不动签名），AppDelegate 在调 ExecutionEngine 前显式从 SelectionPayload 提取 `SelectionSnapshot + AppSnapshot + screenAnchor + timestamp` 给 ExecutionSeed。详见 D-28 修订版 |
| Rename | `SliceAIKit/Sources/SliceCore/V2Tool.swift` → `Tool.swift` | git mv + 类型名 `V2Tool` → `Tool` + `PromptTool` 等子类型不变 |
| Rename | `SliceAIKit/Sources/SliceCore/V2Provider.swift` → `Provider.swift` | git mv + 类型名 `V2Provider` → `Provider` + `ProviderKind` / `ProviderCapability` 不变 |
| Rename | `SliceAIKit/Sources/SliceCore/V2Configuration.swift` → `Configuration.swift` | git mv + 类型名 `V2Configuration` → `Configuration` |
| Rename | `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift` → `ConfigurationStore.swift` | git mv + 类型名 `V2ConfigurationStore` → `ConfigurationStore`；当前不实现 protocol，rename 后保持具体类型 |
| Rename | `SliceAIKit/Sources/SliceCore/DefaultV2Configuration.swift` → `DefaultConfiguration.swift` | git mv + 类型名 `DefaultV2Configuration` → `DefaultConfiguration` |
| Modify | `SliceAIKit/Sources/SliceCore/OutputBinding.swift` | `PresentationMode` → `DisplayMode`（类型 + 文件内全部引用） |
| Modify | `SliceAIKit/Sources/SliceCore/ToolKind.swift` | `PresentationMode` → `DisplayMode`（V2Tool / PromptTool / AgentTool / PipelineTool 的 displayMode 字段） |
| Modify | `SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift` | `SelectionOrigin` → `SelectionSource`（含 enum 定义 + 字段类型） |
| Modify | `SliceAIKit/Sources/SliceCore/SelectionPayload.swift` | `SelectionOrigin` → `SelectionSource`（payload.source 字段类型；本身保留） |
| Keep | `SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift` | 内部仍引用 `LegacyConfigV1` struct（不变）；引用 `Tool` / `Provider` / `Configuration` 时跟随 rename |
| Modify (in M3.1 Sub-step A) | `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift`（M3.1 时仍是 V2*，rename 在 M3.0 Step 3） | **【F1.5 + F6.3 修订】**`load()` 在"v2 / v1 都不存在"分支增加 `try writeV2(DefaultV2Configuration.initial())` 写盘 + 加单测 `test_load_withNeither_writesDefaultToV2Path`；理由是 mini-spec §3.3 + DoD "config-v2.json 实际生成" 在全新安装路径上必须为真。**实施时机 = M3.1 Sub-step A**（不是 M3.0/M3.3——M3.1 bootstrap 调 v2ConfigStore.current() 必须看到新行为）。详见 §3.3 + §M3.1 Sub-step A |

#### 3.1.2 SelectionCapture 层（M3.0）

| 操作 | 路径 | 说明 |
|---|---|---|
| Delete | `SliceAIKit/Sources/SelectionCapture/SelectionSource.swift`（v1 protocol 文件） | v1 `public protocol SelectionSource` 整体删除（含 `SelectionReadResult` struct；真实文件中没有额外错误枚举） |
| **Keep** | `SliceAIKit/Sources/SelectionCapture/SelectionService.swift`（签名不动） | **【F1.1 修订】**`capture()` 继续返回 `SelectionPayload?`——SelectionPayload 是触发层包装类型（含 `appBundleID/appName/url/screenPoint/timestamp`），SelectionSnapshot 仅含选区领域字段，无法替换；M3 不动 SelectionService 对外签名。仅内部 `payload.source: SelectionOrigin` → `SelectionSource`（rename 跟随 SelectionSnapshot） |
| Modify | `SliceAIKit/Sources/SelectionCapture/ClipboardSelectionSource.swift` | 实现新 `SelectionReader` protocol 替代旧 `SelectionSource` protocol；内部产出 `SelectionReadResult`（保持，下游 SelectionService 仍用它）的逻辑不变 |
| Modify | `SliceAIKit/Sources/SelectionCapture/AXSelectionSource.swift` | 同上 |
| Create | `SliceAIKit/Sources/SelectionCapture/SelectionReader.swift`（拟名） | 重新定义 v2 `protocol SelectionReader` 替代 v1 `SelectionSource` protocol（spec §3.3 已把 enum `SelectionSource` 升级为类型 case，v1 protocol 名应改避免与 enum 同名）；同文件内迁移 `SelectionReadResult` struct。真实 v1 文件没有额外错误枚举，M3 不新增该错误类型。**详见 D-28** |

> **注意命名冲突**：spec §3.3.x 设计的 `SelectionSource` 是 enum case 类型（`.accessibility` / `.clipboardFallback` / `.inputBox`），不是 protocol。v1 中的 `protocol SelectionSource` 是"两个 source 实现一个抽象"用的——M3.0 删掉它后必须重新命名 protocol 避免与 enum 同名。**预选名 `SelectionReader`**（理由：行为是"读"选区，不是"成为选区源"）。
>
> **【F1.1 修订】**：SelectionService.capture() 对外返回类型保持 `SelectionPayload?`。详细原因：SelectionSnapshot（M1 落地）仅含 `text / source / length / language / contentType` 5 个领域字段；v1 SelectionPayload 含 `appBundleID / appName / url / screenPoint / timestamp` 5 个触发上下文字段，是 AppDelegate 做 appBlocklist 过滤、定位浮条 / ResultPanel 锚点、构造 ExecutionSeed.frontApp / .screenAnchor / .timestamp 所必需的。两类型职责正交。M3 不删 SelectionPayload；AppDelegate 在调 ExecutionEngine 前显式从 SelectionPayload 提取数据组装 ExecutionSeed（详见 §3.2 修订版 + D-28 修订版）。SelectionPayload 何时删？答：留到 Phase 2 ExecutionSeed 直接由触发层构造时再讨论；M3 不在 scope。

#### 3.1.3 SliceAIApp 层（M3.1 + M3.0 + M3.2 + M3.3 + M3.4）【F2.1 + F2.4 + F5.1 修订版】

> **【F5.1 + F6.1 修订】M3.1 是 additive，不是替换**：M3.1 时 v1 触发链仍走 ToolExecutor + FileConfigurationStore，**不能删除 v1 装配**——v1 在 M3.0 Step 1 才被切换 caller + 移除 AppContainer 装配字段，在 M3.0 Step 2 物理删除文件（ToolExecutor.swift / FileConfigurationStore.swift / 等 7 个文件 + Tests）。表中"Modify" 列按 task 阶段拆分；同一文件可能在 M3.1（additive 装配）+ M3.0 Step 1（caller 切换 + 删 v1 装配字段）两次出现。

| 操作 | 路径 | 任务阶段 | 说明 |
|---|---|---|---|
| Modify (additive) | `SliceAIApp/AppContainer.swift` | **M3.1** | **保留** v1 `configStore: FileConfigurationStore` 装配 + `toolExecutor: ToolExecutor` 装配（v1 触发链仍工作）；**新增** v2 `v2ConfigStore: V2ConfigurationStore`（路径 = config-v2.json）+ `executionEngine: ExecutionEngine` + 10 个依赖（详见 D-27）+ `ResultPanelWindowSinkAdapter`；`bootstrap()` 改为 `static func bootstrap() async throws -> AppContainer`（async throws；CostAccounting / JSONLAuditLog / makeAppSupportDir / v2ConfigStore.current() throwing + async 上抛）；M3.1 Exit DoD = v1 触发链仍正常 + cost.sqlite/audit.jsonl/config-v2.json 创建 + Settings/命令面板可用 |
| Modify (replace) | `SliceAIApp/AppContainer.swift` | **M3.0 Step 1** | 切 `configStore` 引用从 `FileConfigurationStore` → `V2ConfigurationStore`（v1 store 装配删除）；删 `toolExecutor` 装配；删 v1 store 引用 |
| Modify (additive) | `SliceAIApp/AppDelegate.swift` | **M3.1** | `override init()` 同步只初始化空状态（`container: AppContainer? = nil; startupTask: Task<Void, Never>? = nil`）；`applicationDidFinishLaunching(_:)` 内启 `Task { @MainActor in let container = try await AppContainer.bootstrap(); ... }` 跑 bootstrap，成功后注册 hotkey / 装配 menu / 启动 onboarding；catch → NSAlert + NSApp.terminate(nil)；**触发链 execute(tool:payload:) 仍调 v1 toolExecutor**（M3.1 不动触发链） |
| Modify (replace) | `SliceAIApp/AppDelegate.swift` | **M3.0 Step 1** | 触发链 `execute(tool:payload:)` 内部改调 `payload.toExecutionSeed(triggerSource:isDryRun:)` extension 构造 ExecutionSeed + `container.executionEngine.execute(tool:seed:)` + 消费 `AsyncThrowingStream<ExecutionEvent, any Error>`（详见 §3.2 + §M3.2 修订版）；`tool` 参数类型从 v1 `Tool` 切到 V2* `V2Tool` |
| Keep | `SliceAIApp/MenuBarController.swift` | M3.0 Step 1 (caller 切) | 仅引用 `Configuration` 类型时跟随 rename，无逻辑改动 |
| Keep | `SliceAIApp/SliceAIApp.swift` | `@main` 入口，`@NSApplicationDelegateAdaptor(AppDelegate.self)` 不动；启动失败 UX 在 AppDelegate 内处理 |
| **Modify** | **`SliceAI.xcodeproj/project.pbxproj`** | **【F2.1 修订】**SliceAI app target 当前 `packageProductDependencies` 仅 7 个（HotkeyManager / LLMProviders / Permissions / SelectionCapture / SettingsUI / SliceCore / Windowing）；M3.1 必须加入 `Orchestration` + `Capabilities` 两个 productName 引用，否则 AppContainer.swift `import Orchestration` 会触发"No such module"链接错误。落地方式：plan 阶段给 Xcode UI 步骤（File > Add Package Dependencies → 选 SliceAIKit local package → 勾选 Orchestration / Capabilities）+ 给 .pbxproj 手改差异参考 |

#### 3.1.4 SettingsUI 层（M3.0 数据 binding）

| 操作 | 路径 | 说明 |
|---|---|---|
| Modify | `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift` | binding 从 `Tool.systemPrompt / .userPrompt / .providerId / .modelId / .temperature / .variables` 改为 `Tool.kind.prompt.systemPrompt / .userPrompt / .provider.fixed.providerId / .provider.fixed.modelId / .temperature` 等。**详见 D-29** |
| Modify | `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift` | 新增 `kind: ProviderKind` 字段（默认 `.openAICompatible`）+ `capabilities: [ProviderCapability]`（默认 `[]`）；其他字段保持视觉等价 |
| Modify | `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift` | `ConfigurationProviding` protocol 引用切到 v2 `ConfigurationStore`；`addTool` / `addProvider` / `setAPIKey` 等方法适配 v2 struct |
| Modify | `SliceAIKit/Sources/SettingsUI/SettingsScene.swift` | 同上，跟随 ViewModel 切换 |
| Keep | 其他 SettingsUI 页面（HotkeySettingsPage / TriggerSettingsPage / etc.） | 仅引用 `Configuration` 类型时跟随 rename，无逻辑改动 |

#### 3.1.5 LLMProviders 层 + LLMProviderFactory protocol 升级（M3.0 Step 2）【F5.1 自查发现 + F8.1/F9.1 修订】

> **【R5 自查发现】M2 已落地 `OpenAIProviderFactory` + `LLMProviderFactory` protocol（不是 M3 新建）**：
> - `SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift`（M2）：`public struct OpenAIProviderFactory: LLMProviderFactory; public init() { }; public func make(for provider: Provider, apiKey: String) throws -> any LLMProvider`
> - `SliceAIKit/Sources/SliceCore/LLMProvider.swift`（v1 既有 protocol）：`public protocol LLMProviderFactory: Sendable { func make(for provider: Provider, apiKey: String) throws -> any LLMProvider }`
> - **隐含 zero-touch 妥协**：M2 PromptExecutor 内有 `private func toV1Provider(_ v2: V2Provider) throws -> Provider`（line 280+）helper 把 V2Provider 转 v1 Provider 喂给工厂；M2 注释明确"M3 升级到 V2Provider 后本字段类型变更、`toV1Provider` helper 删除"
>
> **【F8.1 修订】LLMProviderFactory 升级时机 = M3.0 Step 2**（不是 Step 1——Step 1 升级会让仍存在的 ToolExecutor.swift 编译失败）：
> 1. 升级 `LLMProviderFactory.make` 签名：`(for provider: Provider, apiKey: String)` → `(for provider: V2Provider, apiKey: String)`（M3.0 Step 2 期间用 V2Provider 命名；Step 3 rename 后是 Provider）
> 2. 修改 `OpenAIProviderFactory.make` 实现：内部把 v1 Provider 字段提取改为 V2Provider 字段——校验 `provider.kind == .openAICompatible` + `guard let baseURL = provider.baseURL`（V2Provider.baseURL 是 Optional），构造 OpenAICompatibleProvider 时直接用 v2 字段
> 3. **删除 PromptExecutor.toV1Provider helper**（line 280-303）+ 调 callsite 改为 `let llm = try llmProviderFactory.make(for: provider, apiKey: apiKey)`（不再过 v1 中间形态）
> 4. **这三处 + ToolExecutor.swift 删除 + v1 Provider.swift 删除必须同 Step 2 commit 改完**——任一处分开都会让中间态编译失败
> 5. **为什么不能在 Step 1 做**：Step 1 完成时 ToolExecutor.swift 物理文件仍在 SliceCore（依赖 ConfigurationProviding/Tool/Provider，物理文件 Step 2 才删）；ToolExecutor.execute 内部调 `providerFactory.make(for: provider, ...)`——若 Step 1 升级 protocol 接收 V2Provider，ToolExecutor 仍调 v1 Provider 会类型不匹配编译失败

| 操作 | 路径 | 任务阶段 | 说明 |
|---|---|---|---|
| Modify | `SliceAIKit/Sources/SliceCore/LLMProvider.swift` | **M3.0 Step 2** | 【F8.1 修订】`LLMProviderFactory.make(for provider: Provider, ...)` → `make(for provider: V2Provider, ...)`（与 v1 Provider.swift 删除同 commit；Step 3 rename 后类型名变 Provider） |
| Modify | `SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift` | **M3.0 Step 2** | 【F8.1 修订】`make(for provider: Provider, ...)` → `make(for provider: V2Provider, ...)`；内部加 `provider.kind == .openAICompatible` 校验 + `guard let baseURL = provider.baseURL` 解包；构造 OpenAICompatibleProvider 用 V2Provider 字段 |
| Modify | `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift` | M3.0 Step 3 (rename 跟随) | `init(baseURL: URL, apiKey: String)` 不变（用 baseURL/apiKey 不直接读 Provider）；类型引用跟随 rename |
| Modify | `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift` | **M3.0 Step 2** | 【F8.1 修订】**删除 `toV1Provider` helper（line 280-303）**；line 171 `let v1Provider = try toV1Provider(provider)` 改为 `let v2Provider = provider`；line 211 `make(for: v1Provider, ...)` → `make(for: v2Provider, ...)`；line 197 `fallback: v1Provider.defaultModel` → `fallback: provider.defaultModel`；line 174 `keychainAccount` 提取改为 V2Provider 形式 |

#### 3.1.6 Windowing 层（M3.0 + M3.2）

| 操作 | 路径 | 说明 |
|---|---|---|
| Modify | `SliceAIKit/Sources/Windowing/ResultPanel.swift` | `append(_:)` / `finish()` / `fail(...)` callback 由 AppDelegate 适配层调用，**ResultPanel 内部 API 不动**——AppDelegate 把 `ExecutionEvent` 翻译为 ResultPanel 的现有方法调用。**详见 D-30** |
| Modify | `SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift` | 仅 `Tool` 类型引用跟随 rename，无逻辑改动 |
| Modify | `SliceAIKit/Sources/Windowing/CommandPalettePanel.swift` | 同上 |

#### 3.1.7 Tests 层（M3.0）

| 操作 | 路径 | 说明 |
|---|---|---|
| Delete | `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift`（v1） | 与 V2ToolTests rename 后撞名，先删 v1 |
| Delete | `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`（v1，若存在） | 同上 |
| Delete (in M3.0 Step 2) | `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift`（若存在） | **【F6.1 修订，撤销 F5.2】**跟随 ToolExecutor 删除——必须与 ToolExecutor.swift 同 commit |
| **Keep** | `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift`（若存在） | **【F1.1 修订】**SelectionPayload 保留，测试同步保留；仅修 `SelectionOrigin` → `SelectionSource` 引用 |
| Rename | `SliceAIKit/Tests/SliceCoreTests/V2ToolTests.swift` → `ToolTests.swift` | git mv + class 名 `V2ToolTests` → `ToolTests` + 测试方法名内的 `V2Tool` 替换 |
| Rename | `SliceAIKit/Tests/SliceCoreTests/V2ProviderTests.swift` → `ProviderTests.swift` | 同上 |
| Rename | `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationTests.swift` → `ConfigurationTests.swift` | 同上 |
| Rename | `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift` → `ConfigurationStoreTests.swift` | 同上 + **加 `test_load_withNeither_writesDefaultToV2Path` 单测**覆盖 F1.5 修订 |
| Modify | `SliceAIKit/Tests/SliceCoreTests/ConfigMigratorV1ToV2Tests.swift` | 引用 `V2*` → 正名（migrator 类型名本身不动） |
| Modify | `SliceAIKit/Tests/SliceCoreTests/SelectionSnapshotTests.swift` | `SelectionOrigin` → `SelectionSource` |
| Modify | `SliceAIKit/Tests/SliceCoreTests/OutputBindingTests.swift` | `PresentationMode` → `DisplayMode` |
| Modify | `SliceAIKit/Tests/SliceCoreTests/SliceErrorTests.swift` | 跟随类型 rename |
| Modify | OrchestrationTests / CapabilitiesTests / SelectionCaptureTests / SettingsUITests / WindowingTests / LLMProvidersTests | 全部跟随 V2* → 正名 + PresentationMode → DisplayMode + SelectionOrigin → SelectionSource |

### 3.2 触发链改造（M3.2）【F1.1 + F1.3 修订版】

```
v0.1 + M2 当前：
  mouseUp / ⌥Space
    → SelectionService.capture() : SelectionPayload?
    → AppDelegate.execute(tool: SliceCore.Tool, payload: SelectionPayload)
    → toolExecutor.execute(tool:payload:) → AsyncThrowingStream<String, Error>
    → ResultPanel.append(_:) / .finish() / .fail(error:onRetry:onOpenSettings:)

M3 后：
  mouseUp / ⌥Space
    → SelectionService.capture() : SelectionPayload?              // 签名不动
    → AppDelegate.execute(tool: Tool, payload: SelectionPayload)
        → 调 SelectionPayload.toExecutionSeed(tool:, triggerSource:, isDryRun:) 扩展方法（M3.0 Step 1 引入；详见下文）
            → 内部映射：
                ⓐ source 映射：payload.source: SelectionPayload.Source（v1 内嵌 enum, "primary" / "fallback" 等）
                  → SelectionOrigin（M1 SliceCore 定义；rename 后是 SelectionSource）
                  通过 SelectionPayload.Source.toSelectionOrigin() 单方向 helper（在 SelectionPayload.swift 文件内）
                ⓑ selection: SelectionSnapshot(text: payload.text, source: <映射后>, length: payload.text.count, language: nil, contentType: nil)
                  注：v1 SelectionPayload 不含 language / contentType 字段；v0.2 一律置 nil；Phase 1 加 ContextProvider 后填
                ⓒ frontApp: AppSnapshot(bundleId: payload.appBundleID, name: payload.appName, url: payload.url, windowTitle: nil)
                  注：AppSnapshot.init 真实参数名是 bundleId（小写 d）；windowTitle v0.2 暂不读 AX 一律 nil；Phase 1 接 app.windowTitle ContextProvider 后填
                ⓓ ExecutionSeed(invocationId: UUID(), selection:, frontApp:, screenAnchor: payload.screenPoint, timestamp: payload.timestamp, triggerSource:, isDryRun: false)
        → executionEngine.execute(tool: Tool, seed: ExecutionSeed) : AsyncThrowingStream<ExecutionEvent, any Error>
        → 【F3.2】**双消费路径（单一写入所有者）**：
            ⓪ chunk 写入路径（ExecutionEngine 自驱动，AppDelegate 不参与）：
               ExecutionEngine.runPromptStream → 每 chunk 调 output.handle(chunk:mode:invocationId:)
               → OutputDispatcher 按 displayMode 路由（D-30b：non-window mode 降级 fallback 到 .window）
               → WindowSink.append(chunk:invocationId:) → ResultPanelWindowSinkAdapter.append → ResultPanel.append(chunk)
            ① 流控制事件路径（AppDelegate 启 Task 消费）：
               for try await event in stream → ExecutionEventConsumer 按 D-30 表翻译为 ResultPanel API 调用
                .started(invocationId:) → 仅记日志（ResultPanel 已在 stream 启动前 open）
                .contextResolved(key:valueDescription:) → 仅记日志
                .promptRendered(preview:) → 仅记日志
                .llmChunk(delta:) → 【F3.2】仅记日志（chunk 长度 / 频率），**不调 ResultPanel.append**——chunk 写入唯一走 OutputDispatcher 路径
                .stepCompleted(step:total:) → 仅记日志
                .sideEffectTriggered(_) → 仅记日志（v0.2 prompt-only tool 不应 yield 此事件）
                .sideEffectSkippedDryRun(_) → 仅记日志
                .toolCallProposed / .toolCallApproved / .toolCallResult → 仅记日志（v0.2 prompt-only 不应 yield；Phase 1 agent loop 接入时再 UI 化）
                .permissionWouldBeRequested(permission:uxHint:) → 仅记日志（v0.2 默认全放行 + dry-run 不到达；真实弹窗留 Phase 1）
                .notImplemented(reason:) → ResultPanel.fail(.execution(.notImplemented(reason)), onRetry: nil, onOpenSettings: nil)
                .finished(report:) → ResultPanel.finish()
                .failed(SliceError) → ResultPanel.fail(error, onRetry: { regenerate(...) }, onOpenSettings: { openSettings() })
        → catch { let sliceError = SliceError.from(error); ResultPanel.fail(sliceError, ...) }   // stream throw（cancellation 静默退出，其他错误显示）
```

**Cancellation 链路**（D-30 风险点澄清）：
- ResultPanel.onDismiss → streamTask.cancel()
- Task body 处于 `for try await event in stream` 循环；cancel 让 stream 内部的 ExecutionEngine actor 收到 `Task.isCancelled = true`
- M2 codex-loop R10 fix（commit `577ca38`）已在 ExecutionEngine.runMainFlow 内用 `withTaskCancellationHandler { ... } onCancel: { continuation.finish(throwing: CancellationError()) }` 把 cancel 级联到 ContextCollector / PromptExecutor / OutputDispatcher
- 翻译层 catch CancellationError 静默退出（与 v0.1 一致）：
  ```
  do { for try await event in stream { ... } }
  catch is CancellationError { /* silent */ }
  catch let urlErr as URLError where urlErr.code == .cancelled { /* silent */ }
  catch { ResultPanel.fail(SliceError.from(error), ...) }
  ```

### 3.3 配置启动（M3.3）【F1.5 修订版】

```
启动流程（AppContainer 内）：
  1. 创建 ConfigurationStore(v2)（path = ~/Library/Application Support/SliceAI/config-v2.json）
  2. try await configStore.current()：
     - 成功 → 注入 AppContainer，继续启动
     - 抛 .schemaTooNew / .corruptedV2 / .corruptedLegacy / .validationFailed → 弹 alert + NSApp.terminate(nil)
       理由（M1 plan §B 第七轮 P1 指明）：M3 接入时**绝不能**静默回退到 default，否则下一次 update() 永久覆盖用户文件 = 数据丢失
  3. ConfigurationStore.load() 内部 first-launch 行为（M1 已落地一部分；M3 必须补完）：
     - 若 config-v2.json 存在 → readV2 → 返回                             ✓ M1 已落地
     - 若 config-v2.json 不存在但 config.json 存在 → migrator → writeV2(v2) → 返回    ✓ M1 已落地
     - **【F1.5 修订】两份都不存在** → 当前 M1 仅 `return DefaultV2Configuration.initial()` **不写盘**；
        M3 必须改为 `try writeV2(default)` 写盘后返回，使 mini-spec §8 DoD "config-v2.json 实际生成" 在全新安装路径上为真
```

**M3 决策（F1.5）【F6.3 修订：实施时机】**：选方案 (a) 修改 `ConfigurationStore.load()` 在 both-missing 分支显式 `try writeV2(default)`，而非方案 (b) AppContainer bootstrap 后显式 `update(default)`。理由：
- 方案 (a) 把"first-launch 写盘"内聚在 store 自身——单测能直接覆盖（`test_load_withNeither_writesDefaultToV2Path`）
- 方案 (b) 把语义分散到 AppContainer，store 自身的 `current()` 行为不一致（同一调用，两种磁盘副作用），未来加入 CLI / MCP server 入口时还要重复写一次 bootstrap 逻辑
- 修改 store 的 default 写盘单测含三条断言：① 返回值 == DefaultV2Configuration.initial() ② FileManager.fileExists(config-v2.json) == true ③ config.json 不存在保持不存在
- M1 既有 `test_load_withNeither_returnsDefaultV2` 测试要随之改名 / 加断言

**【F6.3 实施时机】**：本修改放在 **M3.1 Sub-step A**（M3.1 内部第一步）实施——而**不是** M3.0 / M3.3。原因：M3.1 bootstrap 内会调 `try await v2ConfigStore.current()`，若 V2ConfigurationStore.load() 行为还是 M2 当前的"return default 不写盘"，M3.1 Exit DoD "config-v2.json 自动创建"不可达；M3.0 / M3.3 都在 M3.1 之后，无法补救。详见 §M3.1 Sub-step A 段。

**首启错误恢复路径**（M3 mini-spec 不展开，留 plan 阶段细化）：
- "弹 alert + 中止启动" 的 alert 文案样例（plan 期定）："SliceAI 配置文件损坏：\(error.userMessage)\n\n建议：① 备份 ~/Library/Application Support/SliceAI/config-v2.json；② 删除该文件；③ 重新启动 SliceAI（v0.2 会从 config.json 重新迁移，或写入默认配置）"
- 不引入 GUI 文件浏览 / 自动备份 —— v0.2 用户基数 = 作者本人，过度工程

---

## 4. 任务拆解

> 本节给出**任务级粒度**（不是 sub-task，sub-task 在 plan 阶段细化）。每个 M3.x 任务的 entry/exit/交付物按 spec §4.2.3 + master todolist §3.3 锚定。

### M3.0 — v1 删除 + V2 rename pass（一等主任务，3–5 人天）

**目标**：所有 v1 类型族删除；V2* 类型 rename 回 spec 原名；`PresentationMode → DisplayMode` / `SelectionOrigin → SelectionSource` 恢复；CI gate 全绿。

**Entry【F4.1 修订】**：M3.1 完成（`AppContainer.executionEngine` 已就绪 / Xcode SliceAI app target 已加 Orchestration + Capabilities deps / async bootstrap UX 链路已落地）；worktree 干净；baseline = main HEAD `3a5437d`。**为什么 M3.0 排在 M3.1 之后**：M3.0 Step 1 把 AppDelegate 切到 `container.executionEngine.execute(...)`，executionEngine 必须由 M3.1 先装配；颠倒顺序会让 Step 1 编译失败。

**5 步小 commit 序列（D-26）【F1.1 + F4.1 修订版】**：

| Step | Commit | 内容 | 验证 |
|---|---|---|---|
| Step 1 | `refactor(slicecore): switch app callers to V2* + drop v1 AppContainer wiring + audit configStore.current() callsites` | **【F5.1 + F8.1 + F8.2 修订】M3.1 已 additive 装配 v2，本 step 完成 caller 切换 + 移除 v1 装配 + audit throwing API callsites**（**LLMProviderFactory 升级移到 Step 2**——必须与 ToolExecutor 删除同 commit）：① 把 SettingsUI / AppContainer / AppDelegate / Windowing / 全部 Tests 中所有 v1 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `ConfigurationProviding` / `DefaultConfiguration` 类型引用切到 V2*（**LLMProviders / Orchestration target 不切——LLMProviderFactory.make 仍接收 v1 Provider，PromptExecutor.toV1Provider helper 仍工作；这两个 target 在 Step 2 才升级**）；② 同步更新 SettingsUI 的数据 binding 适配 V2Tool / V2Provider 结构（D-29 修订版：保留 variables + displayMode UI binding）；③ **AppDelegate.execute** 改为：(a) 接收 `tool: V2Tool, payload: SelectionPayload` (b) 内部调 `payload.toExecutionSeed(triggerSource:isDryRun:)` extension 组装 ExecutionSeed (c) 调 `container.executionEngine.execute(tool:seed:) → AsyncThrowingStream<ExecutionEvent, any Error>`（M3.1 已装配 executionEngine；D-28 修订版 + D-30 修订版）；④ AppContainer 删除 v1 字段：`configStore: FileConfigurationStore` / `toolExecutor: ToolExecutor`；保留并 rename `v2ConfigStore` → `configStore`（类型名 V2ConfigurationStore 不变，Step 3 才 rename 类型）；⑤ SettingsViewModel 改为持有 `V2ConfigurationStore` 直接引用替代 `any ConfigurationProviding`（v1 protocol 还在但已无 production caller，由 Step 2 物理删除）；⑥ **SelectionPayload 不切**（保持现状作为触发层包装）；⑦ **【F6.1 修订】**ToolExecutor.swift / ToolExecutorTests.swift 物理文件**不在 Step 1 删**（Step 1 仅删 AppContainer 字段引用），由 **Step 2 与 v1 类型族 6 个文件同 commit 删**（共 7 个；M3.4 改为 grep 收尾验证 task）；⑧ **【F8.2 新增】audit 所有 `configStore.current()` callsite（7 处）改 `try await` + 错误策略**：MenuBarController:67 + AppDelegate:89/159/229/309 + SettingsViewModel:85（v2 V2ConfigurationStore.current() 是 `async throws`，v1 ConfigurationProviding.current() 是 `async`——切到 v2 后必须 `try await`）；错误策略：UI 路径（MenuBarController/AppDelegate）catch 后记日志 + 跳过当前 UI 动作（不弹 alert，避免抢屏）；SettingsViewModel.reload 失败 → 暴露 `loadError: SliceError?` state 给 UI 显示，**严禁**用 default 覆盖内存态（避免静默写回损坏配置） | swift build 通过；swift test 全绿；xcodebuild 通过；swiftlint --strict 0 violations；**【F8.2】**`grep -n "await .*configStore\\.current\\(\\|await .*store\\.current\\(" SliceAIApp/ SliceAIKit/Sources/SettingsUI/`：所有命中必须是 `try await`；触发链 v1 → v2 切换后实机验证：划词触发能出 ResultPanel 流式（与 v0.1 等价） |
| Step 2 | `refactor(slicecore): delete v1 7 files + upgrade LLMProviderFactory protocol` | **【F6.1 + F8.1 修订】**删除 v1 SliceCore **7 个文件**：Tool / Provider / Configuration / FileConfigurationStore / ConfigurationProviding / DefaultConfiguration / **ToolExecutor**（**必须同 commit 删**——ToolExecutor.swift 内部 import & 引用 ConfigurationProviding / Tool / Provider，分开删会让其中一个 commit 编译失败）；同时 **【F8.1 升级】LLMProviderFactory protocol + OpenAIProviderFactory + PromptExecutor 一并改**：升级 `LLMProviderFactory.make(for: Provider, ...)` → `make(for: V2Provider, ...)`（v1 Provider 在本 commit 删除，protocol 必须同 commit 升级）；同步改 `OpenAIProviderFactory.make` 实现接收 V2Provider；**删除 `PromptExecutor.toV1Provider` helper（line 280-303）**；改 callsite line 171/197/211 用 `provider`（V2Provider）替代 `v1Provider`；详见 §3.1.5 修订表（**3 处必须同 commit**——分开改任一处都会让另一处编译失败）；删除 v1 SelectionCapture/SelectionSource.swift；新建 `SelectionCapture/SelectionReader.swift` 含 `protocol SelectionReader` + `SelectionReadResult` struct（真实 v1 文件没有额外错误枚举，不新增）；删除对应 v1 Tests 文件（ToolTests / ConfigurationTests / **ToolExecutorTests** 等若存在）；**SelectionPayload.swift 与 SelectionPayloadTests.swift 保留** | 同上四关 |
| Step 3 | `refactor(slicecore): rename V2* types and files to canonical names` | git mv 5 个 V2* 文件到正名（`Tool.swift` / `Provider.swift` / `Configuration.swift` / `ConfigurationStore.swift` / `DefaultConfiguration.swift`）；类型名 `V2Tool` → `Tool` 等同步全局替换；测试 V2*Tests rename 为 *Tests | 同上四关 |
| Step 4 | `refactor(slicecore): rename PresentationMode to DisplayMode` | `PresentationMode` → `DisplayMode`（OutputBinding.swift / ToolKind.swift / 全部测试 / 全部引用）；v1 `DisplayMode` 已在 Step 2 删除，命名空间已腾出 | 同上四关 |
| Step 5 | `refactor(selectioncapture): rename SelectionOrigin to SelectionSource` | `SelectionOrigin` → `SelectionSource`（SelectionSnapshot.swift / SelectionPayload.swift / 全部测试 / 全部引用）；v1 `protocol SelectionSource` 已在 Step 2 删除并改名 SelectionReader，命名空间已腾出 | 同上四关 |

**Exit (DoD)**：
- [ ] `swift build` / `swift test --parallel --enable-code-coverage` / `swiftlint lint --strict` / `xcodebuild ... SliceAI` 全绿
- [ ] `grep -rn "V2Tool\|V2Provider\|V2Configuration\|V2ConfigurationStore\|DefaultV2Configuration\|PresentationMode\|SelectionOrigin" SliceAIKit/ SliceAIApp/` **0 匹配**
- [ ] `git mv` 让 git follow rename 工作（用 `git log --follow Tool.swift` 能跟踪到 commit `cd34835` 之前的 V2Tool.swift 历史）

**注意事项**：
- Step 1 是最大的 commit（要改 30+ 文件），但**不删任何东西**，纯 caller 切换；这一步如果跑通就锁住了"v1 已无 production 引用"
- Step 2 删 v1 后，原 v1 测试也要删，否则编译失败
- Step 3 是双重 rename（文件名 + 类型名），git 会识别 `git mv` 触发的 rename；类型名替换用 `sed -i '' 's/\bV2Tool\b/Tool/g'` 但要小心 `V2ToolTests` 这类合成名（用 `\b` boundary）
- Step 4 / Step 5 是单字段重命名，相对安全
- **5 步必须严格按顺序**——颠倒会引入命名冲突或编译循环

### M3.1 — AppContainer additive 装配 ExecutionEngine + 10 个依赖（1 人天）【F4.1：M3 第 1 个执行的 task；F5.1：additive 而非替换】

**目标**：`AppContainer` **以 additive 方式**装配 v2 执行引擎闭环（**不动 v1 装配**）；Xcode SliceAI app target 加 Orchestration + Capabilities packageProductDependencies；async bootstrap UX 链路落地；启动冒烟测试通过。

**冒烟成功定义【F5.1 修订】**：app 启动后 ① v1 触发链仍正常工作（划词 + ⌥Space 触发都走 v1 ToolExecutor → ResultPanel，与 v0.1 等价）；② Settings / 命令面板可用；③ `~/Library/Application Support/SliceAI/` 下自动创建 `cost.sqlite` / `audit.jsonl` / `config-v2.json`（v2 装配生效证据）；④ executionEngine / outputDispatcher / configStore (v2) 等 10 依赖在 container 中可访问但**未被任何 caller 调用**（caller 切换在 M3.0 Step 1）。

**M3.1 实施 sub-step 顺序【F6.3 + R11 修订】**（M3.1 内部按此序实施；每个可提交 sub-step / commit 都必须让 4 关 CI gate 全绿。Sub-step C + D 是同一原子实现单元：C 改完但 D 未改完时不允许视为完成、不允许 commit、不要求中间态可编译）：
1. **Sub-step A — SliceCore F1.5 前置修订**：改 `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift` `load()` 在 both-missing 分支加 `try writeV2(DefaultV2Configuration.initial())`；加单测 `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift::test_load_withNeither_writesDefaultToV2Path`（断言 returns default + config-v2.json 存在 + config.json 不存在保持不存在）。**为什么先做**：M3.1 bootstrap 内调 `try await v2ConfigStore.current()`，若 store 行为还是 M2 当前的"return default 不写盘"，M3.1 Exit DoD 第 ③ 项"config-v2.json 自动创建"不可达。
2. **Sub-step B — Xcode app target 加 deps**：`SliceAI.xcodeproj/project.pbxproj` 加 Orchestration + Capabilities `packageProductDependencies`（Xcode UI: File > Add Package Dependencies → SliceAIKit local package → 勾选 Orchestration / Capabilities）。验证：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` BUILD SUCCEEDED。
3. **Sub-step C — AppContainer additive 装配（与 D 原子合并）**：按 D-27 装配表 + bootstrap 伪代码加 v2 字段（保留 v1 字段不动）。本 sub-step 只允许作为 C+D 合并提交的一部分落地。
4. **Sub-step D — AppDelegate async bootstrap UX（与 C 原子合并）**：`override init()` 同步只初始化空状态；`applicationDidFinishLaunching(_:)` 启 Task 跑 bootstrap；catch → NSAlert + terminate（详见 D-27 启动失败 UX 段）。C+D 完成后统一跑 4 关 CI gate 并提交。
5. **Sub-step E — 冒烟验证**：跑 4 关 CI gate + 实机启动测试（v1 触发链 / Settings / 文件创建）。

**Entry【F4.1 + F6.3 修订】**：无前置任务（M3 第 1 个执行的 task）；M2 已落地 ExecutionEngine + 10 依赖（在 Orchestration / Capabilities target）；v1 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `ToolExecutor` / `SelectionPayload` 全部存在并工作中。worktree 干净，baseline = main HEAD `3a5437d`。**M3.1 内部按 sub-step A → B → C → D → E 顺序实施**（A 是 SliceCore 前置修订，必须先于 C 装配）。

**装配方案（D-27）【F1.2 + F5.1 修订版，对照真实 init 签名 + additive 命名】**：

> **【F5.1 命名规则】M3.1 时 v2 → spec 原名 rename **未做**——所以装配表全用 V2* 命名（`V2Tool` / `V2Provider` / `V2Configuration` / `V2ConfigurationStore` / `DefaultV2Configuration`）+ `PresentationMode`（M1 临时改名）+ `SelectionOrigin`（M1 临时改名）。M3.0 Step 3 / 4 / 5 完成 rename 后类型名才变为 `Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` / `DisplayMode` / `SelectionSource`——D-27 装配表的代码片段都按 M3.1 时刻的实际可用名书写。
>
> **装配顺序**（依赖链）：先建无依赖的 leaf（providerRegistry / grantStore），再建 actor（contextCollector / permissionGraph / promptExecutor / output / cost / audit），最后构造 executionEngine。`CostAccounting` / `JSONLAuditLog` 是 throwing init，需在 AppContainer.bootstrap throwing 上下文内调；`OutputDispatcher` 接收 `WindowSinkProtocol`，需要先建 `ResultPanelWindowSinkAdapter`。
>
> **Additive 约束**：装配 v2 的同时**不删除 v1 装配**——AppContainer 在 M3.1 期间同时持有：① 旧 v1 `configStore: FileConfigurationStore` + `toolExecutor: ToolExecutor`（v1 触发链仍依赖）；② 新 v2 `v2ConfigStore: V2ConfigurationStore` + `executionEngine: ExecutionEngine` + 10 依赖（M3.0 Step 1 切 caller 后才被使用）。M3.0 Step 1 完成 caller 切换后才删 v1 装配。

| 依赖 | 类型（M3.1 时实名） | 真实构造 | 备注 |
|---|---|---|---|
| `providerRegistry` | `ContextProviderRegistry` | `ContextProviderRegistry(providers: [:])` | **【F7.1 修订】**真实 init 是 `(providers: [String: any ContextProvider])`（M2 已建 struct，无默认工厂）；v0.2 传空 dict（builtin 仅 selection 由 ExecutionEngine.runMainFlow 内部组装 ResolvedExecutionContext.selection 提供，不走 registry）；Phase 1 加 5 个 ContextProvider（app.windowTitle / app.url / clipboard.current / file.read / etc）时填 dict |
| `contextCollector` | `ContextCollector` actor | `ContextCollector(registry: providerRegistry)`（默认 timeout 5s，沿用） | M2 已落地。M3 接入时 builtin providers = selection only；其他 5 个 ContextProvider 留 Phase 1 |
| `permissionGraph` | `PermissionGraph` actor | `PermissionGraph(providerRegistry: providerRegistry)` | M2 已落地，**真实 init 需要 providerRegistry 参数**（mini-spec 初稿漏写） |
| `permissionBroker` | `any PermissionBrokerProtocol` | `PermissionBroker(store: PermissionGrantStore())` | M2 已落地，**真实类型是 `PermissionBroker`，不是 `DefaultPermissionBroker`**；`store` 默认值 `PermissionGrantStore()` 即可（v0.2 默认全放行 + audit log；真实弹窗 + persistent grant 留 Phase 1） |
| `providerResolver` | `any ProviderResolverProtocol` | `DefaultProviderResolver(configurationProvider: { [v2ConfigStore] in try await v2ConfigStore.current() })` | M2 已落地，**真实参数名是 `configurationProvider`，类型是 `@Sendable @escaping () async throws -> V2Configuration` closure**；M3.1 时 closure 捕获 v2ConfigStore（V2ConfigurationStore），M3.0 Step 1 后 closure 内类型名变为 ConfigurationStore（rename 跟随） |
| `promptExecutor` | `PromptExecutor` actor | `PromptExecutor(keychain: keychain, llmProviderFactory: OpenAIProviderFactory())` | M2 已落地，**真实 init 接收 `keychain: any KeychainAccessing` + `llmProviderFactory: any LLMProviderFactory`**；**【F5.1 自查】`OpenAIProviderFactory` M2 已落地**（不是 M3 新建；`SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift`），无参数 init；M3.1 直接用 `OpenAIProviderFactory()` 装配；**【F8.1/F9.1 修订】M3.0 Step 2** 升级 `LLMProviderFactory.make` 接收 V2Provider + 删 PromptExecutor.toV1Provider helper（与 v1 Provider/ToolExecutor 删除同 commit；不可在 Step 1 做——Step 1 ToolExecutor.swift 物理仍在），详见 §3.1.5 修订表 |
| `mcpClient` | `any MCPClientProtocol` | `MockMCPClient()` | **【F1.2 新增】**M2 已落地 production-side Mock；v0.2 仍用 Mock；Phase 1 真实 stdio/SSE client 接入 |
| `skillRegistry` | `any SkillRegistryProtocol` | `MockSkillRegistry()` | **【F1.2 新增】**M2 已落地 production-side Mock；v0.2 仍用 Mock；Phase 2 真实 SkillRegistry 接入 |
| `costAccounting` | `CostAccounting` actor | `try CostAccounting(dbURL: appSupport.appendingPathComponent("cost.sqlite"))` | M2 已落地，**真实 init throwing**（sqlite open 失败时抛 `SliceError.configuration(.validationFailed)`）；AppContainer.bootstrap 必须在 throwing 上下文内 |
| `auditLog` | `any AuditLogProtocol` | `try JSONLAuditLog(fileURL: appSupport.appendingPathComponent("audit.jsonl"))` | M2 已落地，**真实 init throwing**（父目录创建失败时抛）；同上 |
| `outputDispatcher` | `any OutputDispatcherProtocol` | `OutputDispatcher(windowSink: ResultPanelWindowSinkAdapter(panel: resultPanel))` | M2 已落地；adapter 是 M3 新增类型（在 SliceAIApp/，不在 Windowing/——D-30 修订版）；**【F9.2 修订】adapter 必须实现 single-flight invocation 隔离契约**（`activeInvocationId` actor state + `setActiveInvocation` / `clearActiveInvocation` API）以满足 `WindowSinkProtocol` 协议注释（OutputDispatcherProtocol.swift:49）"按 invocationId 隔离不同 invocation 的 chunk 流"要求；接口骨架见 §M3.2 改造点 + D-30 |
| `executionEngine` | `ExecutionEngine` actor | `ExecutionEngine(contextCollector:permissionBroker:permissionGraph:providerResolver:promptExecutor:mcpClient:skillRegistry:costAccounting:auditLog:output:)` | **真实 init 含 10 个依赖**（mini-spec 初稿写 8 个） |
| **`v2ConfigStore`** (additive) | `V2ConfigurationStore` | `V2ConfigurationStore(fileURL: appSupport.appendingPathComponent("config-v2.json"), legacyFileURL: appSupport.appendingPathComponent("config.json"))` | **【F5.1 + F6.2 修订】**真实 init 是 `(fileURL: URL, legacyFileURL: URL?)`——legacyFileURL 必须传 v1 `config.json` 路径以激活 first-launch migrator 路径（详见 V2ConfigurationStore.swift line 28）；M3.1 期间与 v1 `configStore: FileConfigurationStore` 共存；M3.0 Step 1 删 v1 + rename `v2ConfigStore` → `configStore` + 类型 V2ConfigurationStore → ConfigurationStore（M3.0 Step 3 完成）|
| **v1 `configStore` (keep)** | `FileConfigurationStore` (v1) | （M3.1 不动；M3.0 Step 1 才删） | **【F5.1 保留】**v1 触发链仍依赖；删除时机 = M3.0 Step 1 caller 切完后 |
| **v1 `toolExecutor` (keep)** | `ToolExecutor` (v1) | （M3.1 不动；M3.0 Step 1 移除 AppContainer 字段；**M3.0 Step 2 git rm 物理文件**） | **【F5.1 + F6.1 修订】**v1 触发链仍依赖；M3.0 Step 1 移除装配字段；M3.0 Step 2 与 v1 类型族同 commit 物理删除文件（不再保留到 M3.4） |

**伪代码骨架**（plan 阶段细化；本 mini-spec 仅展示结构）：
```
// 【F5.1 修订】伪代码反映 M3.1 时刻状态：v1 装配仍在；v2 装配 additive 加入；类型用 V2* / PresentationMode（rename 在 M3.0 Step 3~5 才做）
@MainActor
final class AppContainer {
    // === v1 既有装配（M3.1 不动；M3.0 Step 1 才删） ===
    let configStore: FileConfigurationStore                 // v1，M3.0 Step 1 删
    let toolExecutor: ToolExecutor                          // v1，M3.0 Step 1 移除装配字段；M3.0 Step 2 git rm 物理文件（与 v1 类型族同 commit）
    let resultPanel: ResultPanel
    let selectionService: SelectionService
    let keychain: any KeychainAccessing
    // ... 其他既有依赖（hotkeyRegistrar / themeManager 等）

    // === v2 additive 装配（M3.1 新增） ===
    let v2ConfigStore: V2ConfigurationStore                 // M3.0 Step 1 rename → configStore；M3.0 Step 3 类型 → ConfigurationStore
    let executionEngine: ExecutionEngine
    let outputDispatcher: any OutputDispatcherProtocol
    // 注：providerRegistry / contextCollector / permissionGraph / permissionBroker / providerResolver / promptExecutor / mcpClient / skillRegistry / costAccounting / auditLog 也都是 instance fields；
    // 仅展示骨架，完整字段表 plan 阶段细化

    static func bootstrap() async throws -> AppContainer {  // 【F3.1】async throws — 因含 try await v2ConfigStore.current()
        let appSupport = try makeAppSupportDir()

        // --- v1 既有装配 ---
        let configStore = FileConfigurationStore(fileURL: appSupport.appendingPathComponent("config.json"))  // v1 真实 init 是 (fileURL: URL)；M3.0 Step 1 删
        let keychain = KeychainStore()
        let llmProviderFactory = OpenAIProviderFactory()                        // 【F6.2 + F7.1 + F9.1 修订】M2 已落地无参 init；v1 ToolExecutor + v2 PromptExecutor 共用一个 instance（factory 是无状态的，复用安全）；**M3.0 Step 2** 升级 protocol 接收 V2Provider 后内部实现改（不在 Step 1 做——Step 1 ToolExecutor.swift 物理仍在；详见 §3.1.5 时机段）
        let toolExecutor = ToolExecutor(configurationProvider: configStore, providerFactory: llmProviderFactory, keychain: keychain)  // 【F7.1 修订】真实 init 含 providerFactory；v1，M3.0 Step 1 移除 AppContainer 字段，Step 2 git rm 文件

        // --- v2 additive 装配（M3.1 新增）【F6.2 + F7.1 修订：用真实 init 签名】 ---
        let v2URL = appSupport.appendingPathComponent("config-v2.json")
        let legacyURL = appSupport.appendingPathComponent("config.json")
        let v2ConfigStore = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: legacyURL)  // 真实 init 是 (fileURL: URL, legacyFileURL: URL?)
        _ = try await v2ConfigStore.current()                                   // 触发 first-launch 写盘（含 §3.3 修订的 default 写盘 + 自动 migrator）
        let providerRegistry = ContextProviderRegistry(providers: [:])         // 【F7.1 修订】真实 init 是 (providers:[String:any ContextProvider])；v0.2 空 dict
        let contextCollector = ContextCollector(registry: providerRegistry)
        let permissionGraph = PermissionGraph(providerRegistry: providerRegistry)
        let permissionBroker = PermissionBroker(store: PermissionGrantStore())
        let providerResolver = DefaultProviderResolver(
            configurationProvider: { [v2ConfigStore] in try await v2ConfigStore.current() }
        )
        let promptExecutor = PromptExecutor(keychain: keychain, llmProviderFactory: llmProviderFactory)  // 复用 v1 已构造的 llmProviderFactory
        let mcpClient = MockMCPClient()
        let skillRegistry = MockSkillRegistry()
        let costAccounting = try CostAccounting(dbURL: appSupport.appendingPathComponent("cost.sqlite"))
        let auditLog = try JSONLAuditLog(fileURL: appSupport.appendingPathComponent("audit.jsonl"))
        let outputDispatcher = OutputDispatcher(
            windowSink: ResultPanelWindowSinkAdapter(panel: resultPanel)
        )
        let engine = ExecutionEngine(
            contextCollector: contextCollector,
            permissionBroker: permissionBroker,
            permissionGraph: permissionGraph,
            providerResolver: providerResolver,
            promptExecutor: promptExecutor,
            mcpClient: mcpClient,
            skillRegistry: skillRegistry,
            costAccounting: costAccounting,
            auditLog: auditLog,
            output: outputDispatcher
        )

        // M3.1 时同时持有 v1 + v2；触发链 caller 仍调 toolExecutor；M3.0 Step 1 才切到 executionEngine 并删 v1 字段
        return AppContainer(
            configStore: configStore, toolExecutor: toolExecutor,               // v1 既有
            v2ConfigStore: v2ConfigStore, executionEngine: engine,              // v2 additive
            outputDispatcher: outputDispatcher,
            resultPanel: resultPanel, selectionService: selectionService, keychain: keychain
        )
    }
}
```

**【F2.4 + F3.1 修订】启动失败 UX**（SwiftUI `@NSApplicationDelegateAdaptor` 边界 + async bootstrap）：

- **F3.1 backstory**：R2 落第一版"sync init + 延迟 alert"方案时漏考虑 `AppContainer.bootstrap()` 内含 `try await configStore.current()`（V2ConfigurationStore.current() 是 `async throws`）—— sync init 内调 async 函数要么编译失败要么强迫用 blocking Task hack；正确做法是把 bootstrap 整体改 async，启动 Task 在 applicationDidFinishLaunching 内跑
- **bootstrap 签名**：`static func bootstrap() async throws -> AppContainer`（async throws）
- **AppDelegate 启动顺序**：init 同步只初始化空状态 → applicationDidFinishLaunching 启 Task 跑 bootstrap → 成功后注册 hotkey/menu/onboarding；失败弹 alert + terminate
  ```swift
  @MainActor
  final class AppDelegate: NSObject, NSApplicationDelegate {
      private(set) var container: AppContainer?
      private var startupTask: Task<Void, Never>?

      override init() {
          // sync init：仅初始化空状态；不调任何 async / throwing 代码
          super.init()
      }

      func applicationDidFinishLaunching(_ notification: Notification) {
          // 启动期 UI 状态："启动中"——菜单栏 icon 暗 / 划词不响应 / Settings 不可开
          // 这段时间通常 < 1s（sqlite open + jsonl 创建 + config-v2.json 读盘）；超过 5s 是异常
          startupTask = Task { @MainActor in
              do {
                  let container = try await AppContainer.bootstrap()
                  self.container = container
                  // 启动完成：注册 hotkey / 装配 menu / 启动 onboarding（按需）
                  registerHotkey()
                  setupMenuBar()
                  if shouldShowOnboarding() { showOnboarding() }
              } catch {
                  showStartupErrorAlertAndExit(error)
              }
          }
      }

      private func showStartupErrorAlertAndExit(_ error: Error) {
          let alert = NSAlert()
          alert.messageText = "SliceAI 启动失败"
          alert.informativeText = (error as? SliceError)?.userMessage ?? error.localizedDescription
          alert.addButton(withTitle: "退出")
          alert.runModal()
          NSApp.terminate(nil)
      }
  }
  ```
- **错误来源统一进同一 UX**：`AppContainer.bootstrap()` 把 `makeAppSupportDir` / `CostAccounting` / `JSONLAuditLog` / `configStore.current()` 任一 throwing 都向上抛；`SliceError` 及其子类型有 `.userMessage` 给用户友好文案
- **禁止 try! / fatalError**：任何 startup-time 错误都必须走 alert + terminate 链路，不能让用户对着 crashing dock icon 无所适从
- plan 阶段加单测 / 集成测：通过注入失败的 `KeychainAccessing` mock + 不可写 appSupport 路径，验证 startupTask 的 catch 分支触达 NSAlert（alert 可 stub）
- **启动时长监控**：plan 期 instrument bootstrap 各 step 的耗时（sqlite open / jsonl 创建 / config-v2 读盘），写到 audit log；如果发现 P50 > 500ms 就需要在 plan 后期回过头来评估异步并行（但 v0.2 单 sqlite + 单 json 文件，时间通常可控）

**Exit (DoD)【F2.1 + F2.4 + F5.1 修订版】**：
- [ ] `AppContainer.swift` + `AppDelegate.swift` 编译通过；**v1 装配（FileConfigurationStore / ToolExecutor）保留**未删
- [ ] **【F2.1】**`SliceAI.xcodeproj/project.pbxproj` 含 `Orchestration` + `Capabilities` packageProductDependencies；`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` BUILD SUCCEEDED 是**强制门禁**（M3.1 完成 = 此命令绿灯）
- [ ] **【F5.1 critical】v1 触发链仍正常工作**——手工启动 + Safari 划词触发 → 浮条 → 点工具 → ResultPanel 流式（与 v0.1 等价）；⌥Space 命令面板 → 选工具 → 同上。**M3.1 不允许破坏 v1 触发链；只能 additive 加 v2 装配**
- [ ] 启动 app 不崩；手工启动 + 5s 内能 invoke Settings 菜单
- [ ] `cost.sqlite` / `audit.jsonl` / `config-v2.json` 在 `~/Library/Application Support/SliceAI/` 自动创建（首次启动后；config-v2.json 走 §3.3 修订的 default 写盘路径）
- [ ] **【F2.4】**启动失败 UX 链路就绪：实施期通过临时把 appSupport 路径改为不可写 → 启动 → 验证 NSAlert 弹出 + app 退出（v0.2 不留这个测试在 production，仅 plan 期一次性手工验证）
- [ ] `swift test --filter SliceAIKit` 全绿（不跑 app target 的 UI 测试，因为没有）
- [ ] **【F5.1】**`grep -n "container.executionEngine\|container.outputDispatcher\|container.v2ConfigStore" SliceAIApp/`：除装配 / 持有点外**0 caller 调用**（caller 切换在 M3.0 Step 1，不在 M3.1）

**注意事项【F5.1 修订】**：
- AppContainer 当前 114 行，**M3.1 additive** 后预估 ~250 行（v1 装配 + v2 装配同时持有），M3.0 Step 1 删 v1 后回落到 ~200 行；不超 swiftlint warning 500
- AppDelegate 当前 445 行；**M3.1 不动 execute(tool:payload:) 触发链**（仍调 v1 toolExecutor），仅加 startupTask Task 块；预估 ~470 行
- M3.0 Step 1 才把 AppDelegate.execute 切到 ExecutionEngine + 加 ExecutionEvent 翻译适配 + payload.toExecutionSeed 调用，预估 ~560 行（接近 swiftlint warning 500，可能需要把 ExecutionEvent 翻译抽到 `ExecutionEventConsumer` helper 类——D-30 已规划）
- `ResultPanelWindowSinkAdapter` 是新增类型（在 SliceAIApp/ 而非 Windowing/，因为它跨 Windowing + Orchestration 两层依赖，放 SliceAIApp 是合适的 composition root 位置）；M3.1 时构造但不被任何路径调用（adapter 持有 panel ref + 等 M3.0 Step 1 接通后才有 chunk 流入）

### M3.2 — 触发通路切到 ExecutionEngine（1 人天）【F4.1：实质合入 M3.0 Step 1 + 本 task 作为验收 task】

**目标**：`AppDelegate.execute(tool:payload:)` 内部调 `payload.toExecutionSeed(triggerSource:isDryRun:)` 构造 ExecutionSeed → `container.executionEngine.execute(tool:seed:)` → 消费 `AsyncThrowingStream<ExecutionEvent, any Error>` → ExecutionEventConsumer 翻译为 ResultPanel API 调用（仅流控制事件；chunk 写入唯一走 OutputDispatcher 路径，详见 D-30 + §3.2）。

**Entry【F4.1 修订】**：M3.0 Step 1 完成（caller 切换 + AppDelegate.execute 已调 ExecutionEngine + payload.toExecutionSeed extension 已落地）。本 task **实质上**已被 M3.0 Step 1 完成，单列为独立 task 是为了：① 在 §4 任务清单上保留可追溯条目（master todolist §3.3 中 M3.2 是显式条目）；② 用户/审阅者把它当作"触发链端到端验收 task"——跑一次手工触发 + 验证 ResultPanel 流式正常 + 验证 cancellation 链路工作。

**改造点【F1.1 + F1.3 修订版】**：
- `AppDelegate.execute(tool:payload:)` 签名 **保持** `execute(tool: Tool, payload: SelectionPayload)`——SelectionPayload 是触发层包装类型，AppDelegate 仍以它为入参
- 内部构造 `SelectionSnapshot + AppSnapshot + ExecutionSeed`（**【F2.2 修订版】用 `SelectionPayload.toExecutionSeed(...)` extension 单一入口**，避免散在多处的字段拷贝偏离真实 init 签名）：
  ```swift
  // M3.0 Step 1 引入到 SelectionPayload.swift（同文件 extension）：
  public extension SelectionPayload {
      /// 把 v1 触发层包装翻译成 v2 ExecutionSeed
      /// - 注：language / contentType / windowTitle 在 v0.2 一律 nil；Phase 1 加 ContextProvider 后填
      func toExecutionSeed(triggerSource: TriggerSource, isDryRun: Bool = false) -> ExecutionSeed {
          let snapshot = SelectionSnapshot(
              text: text,
              source: source.toSelectionOrigin(),     // SelectionPayload.Source → SelectionOrigin（rename 后 SelectionSource）
              length: text.count,
              language: nil,
              contentType: nil
          )
          let appSnapshot = AppSnapshot(
              bundleId: appBundleID,                  // 真实参数名是 bundleId 小写 d
              name: appName,
              url: url,
              windowTitle: nil                         // v0.2 暂不读 AX；Phase 1 接 app.windowTitle ContextProvider
          )
          return ExecutionSeed(
              invocationId: UUID(),
              selection: snapshot,
              frontApp: appSnapshot,
              screenAnchor: screenPoint,
              timestamp: timestamp,
              triggerSource: triggerSource,           // mouseUp | commandPalette，TriggerSource enum (M1 落地)
              isDryRun: isDryRun
          )
      }
  }

  // M3.0 Step 1 引入到 SelectionPayload.swift Source 内嵌 enum：
  public extension SelectionPayload.Source {
      /// 单方向映射 v1 触发层 source → v2 SelectionOrigin（rename 后是 SelectionSource）
      /// 真实 case 对照 plan 阶段补全；M3.0 Step 1 sub-task 必须列在 plan
      func toSelectionOrigin() -> SelectionOrigin { /* exhaustive switch */ }
  }

  // AppDelegate.execute 内调用：
  let seed = payload.toExecutionSeed(triggerSource: triggerSource)
  ```
- 调 `container.executionEngine.execute(tool: tool, seed: seed)` 拿 `AsyncThrowingStream<ExecutionEvent, any Error>`（**`execute` 是 `nonisolated`，调用无需 `await`**——M2 落地的 actor public API 约束）
- **【F8.3 修订】严格 ordering：先 open ResultPanel 再启动 stream consumer Task**——`ExecutionEngine.execute` 在 `AsyncThrowingStream` 初始化时就启动 producer task；`ResultPanel.open(...)` 内部会 reset viewModel；若沿用 v1 顺序"先启动 stream task 再 open panel"，快路径 chunk 可能在 open reset 前 append，造成首段丢失或空窗竞态。**正确顺序伪代码**：
  ```swift
  // ① 先 open panel（含 onDismiss callback 挂载）
  resultPanel.open(at: payload.screenPoint, onDismiss: { [weak self] in
      self?.streamTask?.cancel()
  })
  // ② 再创建 stream（producer task 启动）
  let stream = container.executionEngine.execute(tool: tool, seed: seed)
  // ③ 启动 consumer Task 消费 events
  streamTask = Task { @MainActor [weak self] in
      do {
          for try await event in stream {
              await self?.consumer.handle(event, panel: resultPanel)  // 按 D-30 翻译
          }
      } catch is CancellationError { /* silent */ }
        catch let urlErr as URLError where urlErr.code == .cancelled { /* silent */ }
        catch let sliceError as SliceError {
          await resultPanel.fail(sliceError, ...)
      } catch {
          await resultPanel.fail(.execution(.unknown(error.localizedDescription)), ...)
      }
  }
  ```
- `for try await event in stream`：按 D-30 修订版表翻译为 ResultPanel API（详见 §3.2）
- `streamTask.cancel()` 由 ResultPanel onDismiss 调用；ExecutionEngine 内 `withTaskCancellationHandler` 已在 M2 落地（codex-loop R10 fix，commit `577ca38`），cancel 会级联到 ContextCollector / PromptExecutor / OutputDispatcher
- **【F9.2 修订】single-flight invocation 契约（与 ordering 不变量配对）**：仅 ordering 解决"快路径首 chunk 不被 open reset"，但还有 **stale invocation 跨流污染** 风险——用户在 invocation A 未结束时触发 B（Retry / 新划词 / 命令面板），A 的 producer 仍可能通过 OutputDispatcher 把延迟到达的 chunk 写到已 reset 为 B 的 ResultPanel 上。**契约**：
  1. **AppDelegate.execute 入口**：每次新触发先 `streamTask?.cancel()` 取消旧 stream，再 open + 创建新 stream（防止旧 stream 仍 producing 时新 stream 已开始）
  2. **`ResultPanelWindowSinkAdapter`** 维护 `private var activeInvocationId: UUID?` actor state；`append(chunk:invocationId:)` 实现内 `guard invocationId == activeInvocationId else { return }`——只接受当前 active invocation 的 chunk，过期 invocation 的 append 静默丢弃（不抛错，不阻塞 producer）
  3. **active invocation 切换时机**：`AppDelegate.execute` 在 `resultPanel.open(...)` 之后、`stream` 创建之前显式调 `await adapter.setActiveInvocation(seed.invocationId)`；`ResultPanel.dismiss / finish / fail` 调用 `await adapter.clearActiveInvocation()`
  4. **理由**：真实 `WindowSinkProtocol` 已经在 protocol 注释（OutputDispatcherProtocol.swift:49）规定"按 invocationId 隔离不同 invocation 的 chunk 流，避免跨窗口窜流"；adapter 不实现这个契约 = ResultPanel 共享同一 viewModel 时跨 invocation 串流；ResultPanel 单实例 + 复用 viewModel 是 v1 既有架构，不能改

**【F9.2 新增】`ResultPanelWindowSinkAdapter` 接口骨架**（plan 期细化；mini-spec 仅展示结构）：
```swift
@MainActor
public final class ResultPanelWindowSinkAdapter: WindowSinkProtocol {
    private let panel: ResultPanel
    private var activeInvocationId: UUID?       // 仅 active id 的 chunk 可写

    public init(panel: ResultPanel) { self.panel = panel }

    /// AppDelegate.execute 在 open 后 / stream 创建前调
    public func setActiveInvocation(_ id: UUID) { activeInvocationId = id }

    /// ResultPanel.dismiss / finish / fail 时调（清空让任何后续 chunk 都被 drop）
    public func clearActiveInvocation() { activeInvocationId = nil }

    /// `WindowSinkProtocol` 实现：仅 active 的 invocation chunk 写入 ResultPanel
    public func append(chunk: String, invocationId: UUID) async throws {
        guard invocationId == activeInvocationId else { return }   // F9.2 隔离契约
        panel.append(chunk)
    }
}
```
- **note**：actor vs `@MainActor final class` 选择留 plan 期：考虑到 ResultPanel 是 `@MainActor`，adapter 用 `@MainActor` class 跑在主线程更省去 actor hop；WindowSinkProtocol 是 Sendable + async，`@MainActor` class 满足

**Exit (DoD)【F8.3 + F9.2 修订】**：
- [ ] AppDelegate 单元逻辑（不含 UI）编译通过
- [ ] 手工启动 app + 划词触发 → 浮条出现 → 点工具 → ResultPanel 流式出 token（与 v0.1 视觉等价）
- [ ] **【F8.3】**ordering 验证：plan 期加 spy test `test_immediateChunk_isNotLostByOpenReset`——构造一个立即返回首 chunk 的 mock executionEngine，断言 ResultPanel.viewModel 在收到 chunk 后不会被 .open() reset 掉（即先 open 再 stream 顺序正确）
- [ ] **【F9.2 新增】single-flight invocation 验证**：plan 期加 spy test `test_overlappingInvocations_dropStaleChunks`——构造 invocation A producing → 切换到 invocation B（adapter.setActiveInvocation(B.id) + open(B)）→ A 仍 emit chunk → 断言 ResultPanelSpy 不收到 A 的过期 chunk（仅收 B 的）
- [ ] **【F9.2 新增】dismiss-before-first-chunk 验证**：plan 期加 spy test `test_dismissBeforeFirstChunk_doesNotAppendToClosedPanel`——open(A) → dismiss(A)（adapter.clearActiveInvocation()）→ A 后续 emit chunk → 断言 ResultPanelSpy.appendCalls = 0
- [ ] **【F9.2 新增】手工 stress 验证**：连续触发 5 次（A→cancel→B→cancel→C→cancel→D→cancel→E）；E 的 ResultPanel 内容仅含 E 的 chunk，无 A/B/C/D 残留

**注意事项**：
- AppDelegate 当前 445 行；改造后预估 ~500 行（接近 swiftlint warning 500），可能需要把 ExecutionEvent 翻译逻辑抽到独立 `ExecutionEventConsumer` helper 类
- `triggerSource: TriggerSource` 是 SliceCore enum（M1 已落地），有 `.mouseUp` / `.commandPalette` 等 case；当前 v1 没用，M3 接入时要传

### M3.3 — ConfigurationStore 启动按 §3.7 加载 + migrator（0.5 人天）【F4.1：实质合入 M3.1 bootstrap + 本 task 作为验收 task；F6.3：F1.5 修改在 M3.1 Sub-step A 而非这里】

**目标**：app 启动时按"v2 → v1 migrate → default" 三步加载配置；v1 文件永不被修改；全新安装时写默认配置到 config-v2.json（F1.5 修改在 M3.1 Sub-step A 完成；本 task 仅做端到端验收）。

**Entry【F4.1 + F6.3 修订】**：M3.1 完成（Sub-step A 已改 V2ConfigurationStore.load() both-missing 写盘 + 单测；bootstrap 内 `try await v2ConfigStore.current()` 已 trigger first-launch；CostAccounting / JSONLAuditLog / makeAppSupportDir 等 throwing 已统一进 NSAlert + terminate UX）+ M3.0 完成（ConfigurationStore 类型已 rename，路径切到 v2 文件）。本 task **实质上**已被 M3.1 + M3.0 + M1（V2ConfigurationStore.load 三分支） 共同完成，单列为独立 task 是为了：① 跟 spec §3.7 + master todolist §3.3 显式条目对齐；② 作为"配置启动端到端验收 task"——跑 4 个启动场景（v2 存在 / 仅 v1 / 都不在 / v2 损坏）逐一验证。

**改造点【F2.4 + F3.1 修订版】**：
- `ConfigurationStore.current()` 是 `async throws`（M1 plan §B 第七轮 P1 已落地）
- `AppContainer.bootstrap()` 整体改 `async throws`（F3.1 修订）；内含 `try await configStore.current()` 上抛 throwing 错误
- `AppDelegate.init()` 同步只初始化空状态；`applicationDidFinishLaunching(_:)` 启 `Task { @MainActor in try await AppContainer.bootstrap() ... }` 跑 bootstrap；catch → NSAlert + NSApp.terminate(nil)（详见 §M3.1 D-27 修订版的"启动失败 UX"段）
- 不再在 §M3.3 单独写 alert 代码——所有 startup-time throwing 错误（CostAccounting / JSONLAuditLog / makeAppSupportDir / configStore.current()）走**同一 UX 链路**

**Exit (DoD)**：
- [ ] 启动时若 config-v2.json 存在 → 直接读
- [ ] 启动时若仅 config.json 存在 → 跑 migrator 写 config-v2.json；diff 验证 v1 字段无丢失
- [ ] 启动时若都不存在 → 写 DefaultConfiguration.initial() 到 config-v2.json
- [ ] 启动时若 config-v2.json 损坏 → 弹 alert + 中止启动（不静默覆盖）
- [ ] 单测覆盖：M1 已有 `V2ConfigurationStoreTests`（rename 后 `ConfigurationStoreTests`）含 `test_load_*` 系列

**注意事项**：
- 此 task 大部分代码已在 M1 落地，M3.3 主要是把 AppContainer 启动逻辑接对
- 如果 M3.1 装配时已写好"`try await configStore.current()` + alert 中止启动" 的逻辑，M3.3 实际只是验收 task

### M3.4 — v1 → v2 切换收尾验证（0.3 人天）【F6.1 修订，撤销 F4.1/F5.2 的"M3.4 物理删除"决策】

> **【F6.1 修订背景】**R4 把"M3.4 单独删 ToolExecutor"作为最后 commit 是为了 git history 漂亮——但 R6 指出 ToolExecutor.swift 内部 `import` & 引用 `ConfigurationProviding` / `Tool` / `Provider`，**M3.0 Step 2 删这些 v1 类型时，ToolExecutor.swift 不能继续存在**（编译失败，破坏"每步四关绿"硬约束）。撤销原决策：ToolExecutor.swift 与 ToolExecutorTests.swift 在 M3.0 Step 2 与 v1 类型族 6 个文件**同 commit 删**（共 7 个文件）。M3.4 改为"grep 收尾验证"task，不做物理删除。
>
> **为什么仍保留 M3.4 作为独立 task**（不直接合并到 M3.5）：① 与 spec §4.2.3 + master todolist §3.3 中 M3.4 显式独立条目对齐（不删除任务编号防止索引错位）；② 给 v1 → v2 切换一个明确的"收尾门禁"——grep 命中 0 才算 v2 切换真正完成（避免 §M3.5 手工回归时被 v1 残留干扰）。

**目标**：grep 验证 v1 类型族 + V2* 命名 + PresentationMode + SelectionOrigin 在源码 / 测试中残留 = 0。

**Entry**：M3.0 Step 5 完成（5 步 rename 全绿）；M3.2 / M3.3 验收通过（触发链 / 配置启动行为正常）。

**改造点**（无代码改动；仅 grep 验证 + plan 期发现残留时回 M3.0 修）：
- `grep -rn "\\bToolExecutor\\b\\|\\bFileConfigurationStore\\b\\|\\bConfigurationProviding\\b\\|\\bV2Tool\\b\\|\\bV2Provider\\b\\|\\bV2Configuration\\b\\|\\bV2ConfigurationStore\\b\\|\\bDefaultV2Configuration\\b\\|\\bPresentationMode\\b\\|\\bSelectionOrigin\\b" SliceAIKit/Sources/ SliceAIKit/Tests/ SliceAIApp/`：源码 / 测试目录命中 0（仅允许 docs/ 历史归档文件出现）
- 注：v1 `Tool` / `Provider` / `Configuration` / `DefaultConfiguration` / `DisplayMode` / `SelectionSource` 这些**短名**不能直接 grep（rename 后是合法的 v2 类型名——M3.0 Step 3 把 `DefaultV2Configuration` rename 为 `DefaultConfiguration`，Step 4 把 `PresentationMode` rename 回 `DisplayMode`，Step 5 把 `SelectionOrigin` rename 回 `SelectionSource`）；grep 用 `\\b<v1唯一前缀>\\b` 锁定真删的 v1 类型 + 临时改名标识。**【F7.2 修订】**`DefaultConfiguration` 已从 grep 列表移除（rename 后是合法 v2 名）

**Exit (DoD)【F6.1 修订】**：
- [ ] `grep -rn` 命中数 0（v1 + V2* + PresentationMode + SelectionOrigin 全部清零；仅 docs/ 历史归档文件允许）
- [ ] swift build / test / xcodebuild / swiftlint 全绿（实际上 M3.0 Step 5 已绿；本 task 不动代码不会让它变红）

**注意事项**：
- 此 task 不做物理删除（已在 M3.0 Step 2 完成）；仅做收尾 grep 验证
- 如果 grep 命中残留引用：要么是 M3.0 Step 1/2/3/4/5 漏切（回 M3.0 修），要么是注释 / docs（清掉）
- M3.6 才发 v0.2.0 release tag + DMG（M3.4 不发 tag；M3.5 也不发；只 M3.6）

### M3.5 — 端到端手工回归（1.5 人天）【F4.3 + R11 修订】

**目标**：**spec §4.2.5 原 8 项 + 本 mini-spec 在 R1+R2 修订引入的 4 项 + plan fresh review Round 3 新增 1 项，共 13 项手工清单全过** + 4 个内置工具实机行为与 v0.1 等价。

**13 项明细**（详见下方分工表）：
- spec §4.2.5 原 8 项：Safari 划词翻译 / ⌥Space 命令面板 / Regenerate 等 6 个 panel 操作 / Accessibility 权限降级行为 / 无 API Key / 修改 Tool / Provider 配置生效 / 删除 config-v2.json 重启 / 切回旧分支 build
- mini-spec 新增 4 项：① F1.4 编辑自定义变量（variables）→ 写盘 + 占位符替换；② F1.5 全新安装（删除整个 SliceAI app support 目录）→ 自动写默认 config-v2.json；③ F2.3 v1 含 displayMode = .bubble / .replace 的 tool 配置经 migrator 后能正常出 ResultPanel（不报 .notImplemented，运行时 fallback 到 .window）；④ F2.4 启动失败 UX（appSupport 目录不可写时弹 NSAlert + 退出，不留 hung dock icon）
- plan fresh review 新增 1 项：⑤ ToolEditorView 切 Provider 时必须清空旧 modelId，避免旧 provider 的模型 id 被发给新 provider

**Entry**：M3.4 完成；CI gate 全绿。

**分工**：

| 项 | 执行人 | 验证方式 |
|---|---|---|
| Safari 划词翻译 → 弹浮条 → 点 "Translate" → ResultPanel 流式 | 用户 | 截图 / 录屏 / 报告"通过 / 不通过" |
| ⌥Space → 命令面板 → 搜索 → 选工具 → 同上 | 用户 | 同上 |
| Regenerate / Copy / Pin / Close / Retry / Open Settings | 用户 | 同上 |
| Accessibility 权限降级行为（R12 修订） | 用户 | 分两段验证：① 关闭 SliceAI Accessibility 权限后重启并触发，鼠标划词不弹虚假浮条，⌥Space 命令面板可打开但选区捕获失败时不应走"启动失败"NSAlert，Permissions Onboarding / AccessibilityMonitor 提示仍可见；② 恢复 Accessibility 权限后，在 Figma / Slack / VSCode 等不暴露 AX 文本的 app 中划词，验证 AX 主路径取不到时 Cmd+C fallback 命中并能正常弹浮条 / ResultPanel |
| 无 API Key 时的错误提示 | 用户 | Settings 清空 OpenAI key → 触发 → 验证 ResultPanel.fail UX |
| 修改 Tool / Provider 后配置立即生效并写入 config-v2.json | Claude（自动化） + 用户（人工 spot check） | 单测：`ConfigurationStore.update()` 写入路径断言；用户：手工改一次 Tool prompt 后 cat config-v2.json |
| **【F1.4 新增】**编辑工具的"自定义变量"后写入 config-v2.json，且执行时 prompt 占位符 `{{key}}` 被替换 | Claude（自动化） + 用户（手工） | 单测：①ToolEditorView 改 variables → SettingsViewModel.update() → V2ConfigurationStore.save() 写盘后 JSON 含新 variables；②PromptExecutor 渲染 systemPrompt/userPrompt 时 `{{key}}` 被 variables[key] 替换。用户：手工加一个 `{{custom}}` 占位符 + 配置变量 + 触发执行 → 验证模型收到的 prompt 含替换值 |
| **【F1.5 新增】**全新安装（删除 ~/Library/Application Support/SliceAI/ 整个目录后重启）→ app 自动写入默认 config-v2.json | 用户 | 用 `mktemp -d /tmp/sliceai-backup.XXXXXX` 备份原 SliceAI 目录 → 删除原目录 → 重启 → 验证 `~/Library/Application Support/SliceAI/config-v2.json` 存在且包含 4 个内置工具默认配置 → 验证后按备份路径恢复 |
| **【F2.3 新增】**v1 含 displayMode = .bubble / .replace 的 tool 配置经 migrator 迁移后，触发执行能正常出 ResultPanel 流式（不报 .notImplemented） | 用户 | 临时手改 ~/Library/Application Support/SliceAI/config.json 把某个工具的 displayMode 改为 "bubble" → 删除 config-v2.json → 重启触发 migrator → 在 Safari 划词触发该工具 → 验证 ResultPanel 出现并正常流式（log 有 "fallback to .window sink" 警告但 UX 与 v0.1 等价） |
| **【F2.4 新增】**启动失败 UX：appSupport 目录不可写时 → app 弹 NSAlert 后退出，**不**留 hung dock icon | 用户 | 先用 `stat -f '%Lp'` 记录原权限，再临时 `chmod 555 ~/Library/Application\ Support/SliceAI/` 或把 cost.sqlite 替换为目录 → 重启 app → 验证弹 NSAlert "SliceAI 启动失败" + 描述 + 点击退出后 dock icon 立即消失（**不**进入正常状态）→ 按原权限恢复 |
| **【R11 新增】**ToolEditorView 切 Provider 清空 modelId | 用户 | Settings → Tools → 给某个 prompt tool 填非空模型覆写 → Provider Picker 切到另一个 provider → 关闭保存 → `config-v2.json` 中对应 `modelId` 为 `null` 或字段缺省；实际执行使用新 provider 的 defaultModel，不沿用旧模型 id |
| 删除 config-v2.json 后重启：app 能从 config.json 重新 migrate | 用户 | 备份 config-v2.json + 删除 → 重启 → 验证迁移 + diff config.json 仍未变 |
| 同一机器切回旧分支 / 旧 build：旧 app 读取原 config.json 仍正常 | 用户 | 切到 main pre-M3 commit + 重 build + 启动 → 验证 |

**Exit (DoD)【F4.3 修订】**：
- [ ] **13 项全部"通过"**（spec §4.2.5 原 8 项 + mini-spec F1.4/F1.5/F2.3/F2.4 新增 4 项 + R11 provider 切换清空 modelId 新增 1 项）
- [ ] 4 个内置工具（Translate / Polish / Summarize / Explain）的输出与 v0.1 在相同 prompt 下肉眼等价（不要求 token-by-token，仅要求"功能正常 + 流式正常"）

**注意事项**：
- Claude 不能跑真机回归（需要 GUI / Safari / 真实 OpenAI API）；plan 阶段必须明确"用户拿到 PR 后跑回归 + 反馈"
- 如果某项不通过 → 回到 implementation；reset task status
- **新增 5 项不可省略**——前 4 项直接对应 R1+R2 修订引入的设计变更（variables 必须可编辑、全新安装必须能用、v1 displayMode 配置必须不报错、启动失败必须有 UX）；第 5 项来自 plan fresh review Round 3，防止切 Provider 后旧 modelId 污染新 provider；签收时少一项 = 设计未落地

### M3.6 — 文档归档 + v0.2.0 release（1 人天）

**目标**：归档 M3 实施过程；发 v0.2.0 tag + 打 unsigned DMG。

**改造点**：
- `README.md` 项目模块表更新（V2* 命名 → 正名；新增 Orchestration / Capabilities 模块说明）
- `CLAUDE.md` 架构总览段更新（同上）
- `docs/Module/` 目录新建并补：`SliceCore.md` / `Orchestration.md` / `Capabilities.md`（按 user CLAUDE.md §1.1 项目文档规范）
- `docs/Task-detail/2026-04-28-phase-0-m3-mini-spec.md`（本 mini-spec 的实施过程归档）+ `docs/Task-detail/2026-04-XX-phase-0-m3-implementation.md`（implementation plan 的 Task-detail）
- `docs/Task_history.md` 加 M3 索引
- `docs/v2-refactor-master-todolist.md` 把 M3 状态从 ⏳ 改为 ✅

**v0.2 release 时机**：M3 PR merge 后**立即**发 v0.2.0 tag + DMG（用户 R1 决策 A，见 Q1 / D-31；v0.2 是里程碑语义，tag/产物版本统一 SemVer 三段）。具体顺序：① §M3.5 13 项手工回归全过（spec §4.2.5 原 8 项 + mini-spec 新增 4 项 + R11 新增 1 项） → ② xcodebuild Debug build SUCCEEDED → ③ scripts/build-dmg.sh 0.2.0 验证产物 → ④ git tag v0.2.0 + push → ⑤ GitHub Release（draft）创建

**Exit (DoD)**：
- [ ] README / CLAUDE.md / docs/Module/* 更新
- [ ] Task_history.md 加下一个可用 Task 编号（当前 Task 35 已用于 plan/spec 口径对齐修复；M3 mini-spec + M3 implementation 归档预计从 Task 36 起，实际以 Task_history 当前最高编号 + 1 为准）
- [ ] master todolist M3 状态 → ✅
- [ ] git tag v0.2.0 + push + scripts/build-dmg.sh 0.2.0 生成 build/SliceAI-0.2.0.dmg
- [ ] GitHub Release（draft）创建（按 .github/workflows/release.yml 规则触发）

---

## 5. 关键设计决策（Decisions）

> 接续 v2 spec §5.2 + M1 plan / M2 plan 的 D-1 ~ D-31 决策序列。本 mini-spec 引入 D-26 ~ D-31。

### D-26 · M3.0 rename pass 用 5 步小 commit 序列【F1.1 修订版】

- **决策**：M3.0 rename 按 5 步推进，每步独立验证 4 关 CI gate：
  1. `Step 1` — 切 v1 caller 到 V2* + audit throwing API**【F5.1 + F8.1 + F8.2 修订】**：app 层（SettingsUI / AppContainer / AppDelegate / Windowing）caller 切到 V2*；**LLMProviders / Orchestration target 不动**——LLMProviderFactory.make 仍接收 v1 Provider，PromptExecutor.toV1Provider helper 仍工作（这两个 target 的 protocol 升级移到 Step 2 与 v1 Provider.swift 删除同 commit）；同时**删除 AppContainer 中的 v1 装配字段**（`configStore: FileConfigurationStore` + `toolExecutor: ToolExecutor`）；audit 7 处 `configStore.current()` callsite 改 `try await` + 错误策略；**零文件删除 + 零 rename**；中间态完全可编译（v1 Provider/Tool/Configuration 仍在 SliceCore，只是 app 层不再用）
  2. `Step 2` — 删 v1 7 个文件 + LLMProviderFactory 升级**【F6.1 + F8.1 修订】**：Tool / Provider / Configuration / FileConfigurationStore / ConfigurationProviding / DefaultConfiguration / **ToolExecutor**（必须同 commit 删——ToolExecutor 依赖前 6 个，分开删破坏"每步四关绿"）；**同 commit 升级 LLMProviderFactory.make 接收 V2Provider + 改 OpenAIProviderFactory 实现 + 删 PromptExecutor.toV1Provider helper**（必须同 commit——v1 Provider 在本 commit 删除，protocol 也必须升级否则 LLMProviderFactory 引用 dangling）+ v1 SelectionSource protocol 文件 + 对应 Tests（含 ToolExecutorTests）；新建 SelectionReader protocol 文件
  3. `Step 3` — git mv V2* 文件 → 正名（5 个文件 + 类型名同步全局替换）
  4. `Step 4` — `PresentationMode` → `DisplayMode`
  5. `Step 5` — `SelectionOrigin` → `SelectionSource`
- **Step 1 单 commit 不细拆**：用户初审 Q3 确认。事实证明 Step 1 能保持中间态可编译的**前提**是：把"caller 切 V2* 类型"和"调用切 V2 接口（ExecutionEngine.execute 替 ToolExecutor.execute、ConfigurationStore 替 ConfigurationProviding 等）"合在一起做——单独切 caller 类型而不切 ExecutionEngine 入口会让 ToolExecutor 仍接收 v1 Tool 参数（编译失败）；单独切 ExecutionEngine 入口而不切 caller 类型会让 AppDelegate.execute 入参类型错（编译失败）。Codex R1 F1.1 已坐实这点。
- **理由**：
  - 单大 commit 不可 review；中途 CI 挂掉无法定位是哪个 rename 引入的。5 步小 commit 让 reviewer 能按"先 caller 切换 → 再删 v1 → 再 rename"的依赖顺序逐步验证；Codex review 也可以按 step 反向 audit
  - Step 1 涉及 30+ 文件、跨 SettingsUI / AppContainer / AppDelegate / Windowing / LLMProviders / 全部 Tests 6 个模块，但所有改动同根（"v1 类型 / API → V2*"），是不可拆的最小可编译单元
- **风险**：① 5 个 commit 比 1 个慢 4 倍——但 M3 风险高，慢比错好；② Step 1 体积大（30+ 文件）——通过 plan 阶段把"V2 类型字段对照表"、"AppDelegate 触发链伪代码"、"SettingsViewModel binding 适配清单"全部写到 sub-task 级粒度来缓解。

### D-27 · AppContainer 装配 10 个依赖的 wiring 方案

- **决策**：见 §M3.1 表格。`PermissionBroker` / `WindowSink` 等 protocol 类型用 v0.2 production 实现（**`PermissionBroker(store: PermissionGrantStore())` 真实类型，不是 `DefaultPermissionBroker`** / `ResultPanelWindowSinkAdapter`）；MCP / Skill 仍用 M2 落地的 Mock；其他 actor 直接 `()` 实例化或注入工厂。
- **理由**：v0.2 不引入真实 MCP / Skill / 弹窗 UX（spec §4.2.2 out-of-scope 明确）；用 Mock + Default 装配让 ExecutionEngine 主流程能在不阻塞 Phase 1 实施的前提下生效。
- **风险**：Mock MCP / Skill 在 production binary 内，理论上 dead-code-strip 应清掉（M2 Task-detail §7.6 已记此 audit 项）。M3 不重新 audit；Phase 1 接真实 client 时再统一处理。

### D-28 · SelectionPayload 保留 + SelectionReader protocol 新建【F1.1 修订版】

- **决策**：
  1. `SelectionPayload`（v1 触发层包装类型）**M3 不删**——它含 `appBundleID / appName / url / screenPoint / timestamp` 5 个触发上下文字段，是 AppDelegate 做 appBlocklist 过滤、定位浮条 / ResultPanel 锚点、构造 `ExecutionSeed.frontApp / .screenAnchor / .timestamp` 所必需的；SelectionSnapshot（M1 落地）仅含选区领域字段（text / source / length / language / contentType），无法替换
  2. `SelectionService.capture()` 返回类型 **保持** `SelectionPayload?`——M3 不动签名
  3. AppDelegate 在调 ExecutionEngine 前**显式**从 SelectionPayload 提取 `SelectionSnapshot + AppSnapshot + screenAnchor + timestamp` 给 ExecutionSeed（详见 §3.2 + §M3.2 修订版）
  4. v1 `protocol SelectionSource`（SelectionCapture/SelectionSource.swift）整体删除 + 改名为 `protocol SelectionReader`（避免与 spec §3.3 的 enum `SelectionSource` 同名）；同文件内迁移 `SelectionReadResult` struct。真实 v1 文件没有额外错误枚举，M3 不新增该错误类型
  5. `ClipboardSelectionSource` / `AXSelectionSource` 实现 `SelectionReader` 而非旧 `SelectionSource`；类型名保持原状（仅协议名改）
- **为什么不删 SelectionPayload**：
  - 原 M1 plan §A 决策 "SelectionPayload 原封保留" 是 M1 的策略；spec §3.8 表格写"重命名为 SelectionSnapshot"是 v2 spec 起草期的过简描述，未考虑触发上下文字段的归属
  - 真实架构理解：`SelectionSnapshot = 选区领域类型`（SliceCore 纯领域）/ `AppSnapshot = app 领域类型`（SliceCore）/ `SelectionPayload = 触发层包装`（含选区 + app + 屏幕坐标 + 时间戳，平铺）/ `ExecutionSeed = 含 selection / frontApp / screenAnchor / timestamp 的执行种子`；SelectionPayload 与 SelectionSnapshot 职责正交
  - SelectionPayload 何时删？答：留到 Phase 2 ExecutionSeed 直接由触发层构造（移除"先 SelectionPayload 再拆"的中间步）时再讨论；M3 不在 scope
- **为什么新建 SelectionReader protocol**：
  - v1 protocol `SelectionSource` 与 v2 enum `SelectionSource`（spec §3.3 设计）同名冲突；rename 是恢复 spec 原意的前提
  - protocol 新名 `SelectionReader` 比 `SelectionSourceProtocol` 更短更准（行为是"读"选区）
- **风险**：
  - 实现类名 `ClipboardSelectionSource` / `AXSelectionSource` 跟 enum case `SelectionSource.clipboardFallback` / `.accessibility` 仍有语义偏移，但属于命名美学问题；Phase 1+ 再考虑统一
  - SelectionPayload 与 SelectionSnapshot 共存可能让未来开发者困惑——必须在 SelectionPayload.swift 顶部加注释说明"触发层包装，与 SliceCore 领域类型 SelectionSnapshot 共存到 Phase 2"

### D-29 · SettingsUI 数据 binding "零行为变化" 策略【F1.4 修订版】

- **决策**：
  - ToolEditorView 保留 v1 现有 **6 大块** UI（基础信息 / 提示词 / Provider / 自定义变量 / 展示模式 / 标签）100% 视觉等价；只是底层 binding 切到 V2Tool / PromptTool 字段
  - 数据 binding 适配（保留 v1 已有控件）：
    - `tool.systemPrompt` → `tool.kind.prompt.systemPrompt`（用 PromptTool extractor）
    - `tool.userPrompt` → `tool.kind.prompt.userPrompt`
    - `tool.providerId` → `tool.kind.prompt.provider.fixed.providerId`（v0.2 ProviderSelection 仅 .fixed）
    - `tool.modelId` → `tool.kind.prompt.provider.fixed.modelId`
    - `tool.temperature` → `tool.kind.prompt.temperature`
    - **`tool.variables` → `tool.kind.prompt.variables`**（v2 PromptTool.variables 字段已存在；v1 已有 variablesCard UI 必须保留，否则破坏既有功能）
    - **`tool.displayMode` → `tool.displayMode: DisplayMode`**（v2 V2Tool.displayMode 字段已存在；v1 已有展示模式 Picker UI 必须保留）
  - **隐藏（不暴露 UI）的 v2 新增字段**：
    - `tool.kind` 三态切换器（v0.2 写死 .prompt；Phase 2 加三态编辑器）
    - `tool.kind.prompt.contexts: [ContextRequest]`（v0.2 不接 ContextProvider；Phase 1 接入时加 UI）
    - `tool.kind.prompt.provider.cascade / .capability`（v0.2 写死 .fixed 形态；Phase 1 加高级 picker）
    - `tool.outputBinding: OutputBinding?`（v0.2 默认 nil；Phase 2 加 sideEffect UI）
    - `tool.permissions: [Permission]`（v0.2 默认空数组；Phase 1 加权限编辑器）
    - `tool.provenance: Provenance`（v0.2 默认 .firstParty；Phase 1 接 Pack/Skill 安装流程时填）
  - ProviderEditorView：
    - 保留 v1 已有 UI（id / name / baseURL / apiKeyRef / defaultModel）
    - **隐藏（不暴露 UI）**：`provider.kind: ProviderKind`（v0.2 写死 `.openAICompatible`；Phase 1 加 picker 支持 .anthropic / .gemini / .ollama）+ `provider.capabilities: [ProviderCapability]`（v0.2 默认 `[]`；Phase 1 加 multi-select）
  - SettingsViewModel.addTool() 默认创建 `Tool(kind: .prompt(PromptTool(...)))`；不暴露 `.agent` / `.pipeline`
  - SettingsViewModel.addProvider() 默认创建 `Provider(kind: .openAICompatible, capabilities: [], ...)`；apiKeyRef 仍为 `keychain:<provider.id>` 形式
- **理由**：
  - Spec §4.2.4 DoD 硬约束 "Settings 界面无功能变化"——variables / displayMode 是 v1 已有的 UI 控件，**不能**因为"v2 推到 Phase 1"就在 v0.2 隐藏，否则用户既有 tool 配置无法编辑（破坏 §4.2.4）
  - mini-spec 初稿错误地把 variables / displayMode 列入"隐藏"——实际 v2 PromptTool.variables + V2Tool.displayMode 字段都存在且语义与 v1 完全等价；只是"还没在 prompt 渲染期实际注入 variables / 还没按 displayMode 路由 OutputBinding"——这两件事的实施在 M2 PromptExecutor + OutputDispatcher 中已落地（PromptExecutor 用 variables 替换 `{{key}}` 占位符；OutputDispatcher 按 displayMode 路由 sink），M3 接入后即可工作
  - 真正应该隐藏的是"v2 新增的高级字段"（ToolKind 三态 / contexts / sideEffects / advanced ProviderSelection / capabilities）——这些 v0.2 没接入完整执行路径
- **风险**：
  - 部分 v2 高级字段（contexts / outputBinding / capabilities / kind 三态）在 UI 层"不可见但底层已存在"，可能让用户手改 config-v2.json 后 UI 无法识别——但这是 Phase 1+ 提供 advanced UI 的入口，不阻塞 v0.2
  - PromptTool.variables 与 v1 Tool.variables 必须语义完全一致（M1 ConfigMigratorV1ToV2 已保证 v1 → v2 平移；M3 plan 期需测试 ToolEditorView 编辑 → 写入 config-v2.json → PromptExecutor 渲染时占位符替换的端到端链路）
- **§4.2.5 回归追加项（F1.4）**：在 §M3.5 / §8 DoD 中加"编辑自定义变量后写入 config-v2.json 且执行时 prompt 占位符正确替换"项

### D-30 · ResultPanel 消费 ExecutionEvent 的适配方式【F1.3 + F3.2 修订版】

- **决策**：在 SliceAIApp 层（不是 Windowing 层）写一个 `ExecutionEventConsumer` helper，把 `AsyncThrowingStream<ExecutionEvent, any Error>` 翻译为 ResultPanel 的现有方法调用；ResultPanel API 不变。
- **【F8.3 关键修订】ordering invariant：先 open ResultPanel 再启动 stream consumer Task**——`ExecutionEngine.execute` 在 `AsyncThrowingStream` init 时就启动 producer task；`ResultPanel.open` reset viewModel；若顺序颠倒，快路径首 chunk 可能在 open reset 前 append，造成丢首段或空窗竞态。**正确顺序见 §M3.2 改造点伪代码**；plan 期加 `test_immediateChunk_isNotLostByOpenReset` spy test。
- **【F9.2 关键修订】single-flight invocation 隔离契约（与 ordering 不变量配对）**：仅 ordering 不解决 stale invocation 跨流污染——延迟到达的旧 invocation chunk 会写到已 reset 为新 invocation 的 ResultPanel。**契约**：① AppDelegate.execute 入口先 cancel 旧 streamTask 再 open；② `ResultPanelWindowSinkAdapter` 维护 `activeInvocationId`，`append(chunk:invocationId:)` `guard invocationId == activeInvocationId else { return }`；③ 切换时机：execute 在 open 后 / stream 创建前调 `adapter.setActiveInvocation(seed.invocationId)`；ResultPanel.dismiss/finish/fail 调 `adapter.clearActiveInvocation()`；④ 这是真实 `WindowSinkProtocol` (OutputDispatcherProtocol.swift:49) 协议注释明确要求"按 invocationId 隔离不同 invocation 的 chunk 流，避免跨窗口窜流"——adapter 不实现这个契约 = 协议契约违约。**adapter 接口骨架与 plan 期 spy tests（test_overlappingInvocations_dropStaleChunks / test_dismissBeforeFirstChunk_doesNotAppendToClosedPanel）见 §M3.2 改造点。**
- **【F3.2 关键修订】单一写入所有者**：chunk 的 ResultPanel.append 写入路径**唯一通过** `ExecutionEngine.runPromptStream → output.handle(chunk:mode:invocationId:) → WindowSink.append(chunk:invocationId:) → ResultPanel.append(chunk)`。EventConsumer 在 `.llmChunk(delta:)` 事件**仅记日志**（chunk 长度 / 频率），**不再调 ResultPanel.append**；否则同一 chunk 会被 append 两次。
  - **背景**：M2 ExecutionEngine.runPromptStream 真实流程是每个 chunk 先 yield .llmChunk 再调 output.handle——这是 spec §3.4 Step 6/7 的设计（事件流给 audit / observer，OutputDispatcher 给 sink），两条路径各司其职；EventConsumer 只能选一条
  - **选择 OutputDispatcher 路径的理由**：① OutputDispatcher 已含 displayMode 路由 + non-window fallback（D-30b）；② WindowSink 是为"sink-backed"语义设计的；③ 把 EventConsumer 收紧到"流控制事件"（started / finished / failed / notImplemented / permission）让职责更清晰
- **真实 ExecutionEvent 14 个 case 翻译表**（M2 落地的 enum，对照 `SliceAIKit/Sources/Orchestration/Events/ExecutionEvent.swift`）：
  ```
  .started(invocationId:)                           → 仅记日志（ResultPanel 已在 stream 启动前 open）
  .contextResolved(key:valueDescription:)           → 仅记日志
  .promptRendered(preview:)                         → 仅记日志
  .llmChunk(delta:)                                 → 【F3.2】仅记日志（chunk 长度 / 频率）；**不调 ResultPanel.append**——chunk 写入唯一走 OutputDispatcher → WindowSink → ResultPanel.append
  .toolCallProposed(ref:argsDescription:)           → 仅记日志（v0.2 prompt-only tool 不应 yield；Phase 1 agent loop 接入时 UI 化）
  .toolCallApproved(id:)                            → 仅记日志（同上）
  .toolCallResult(id:summary:)                      → 仅记日志（同上）
  .stepCompleted(step:total:)                       → 仅记日志（多 step pipeline 才有意义；prompt-only 链路触发一次 step=1, total=1）
  .sideEffectTriggered(SideEffect)                  → 仅记日志（v0.2 prompt-only tool 不应 yield）
  .sideEffectSkippedDryRun(SideEffect)              → 仅记日志（dry-run 路径，v0.2 启动路径不走）
  .permissionWouldBeRequested(permission:uxHint:)   → 仅记日志（v0.2 PermissionBroker 默认全放行 + dry-run，不到达此事件）
  .notImplemented(reason:)                          → ResultPanel.fail(.execution(.notImplemented(reason)), onRetry: nil, onOpenSettings: nil)
  .finished(report:)                                → ResultPanel.finish()
  .failed(SliceError)                               → ResultPanel.fail(error, onRetry:{regenerate(...)}, onOpenSettings:{openSettings()})
  ```
- **stream 异常处理**（不同于 ExecutionEvent 显式 case）：
  ```
  do { for try await event in stream { ... } }
  catch is CancellationError              { /* silent；ResultPanel.onDismiss → cancel 链路触发 */ }
  catch let urlErr as URLError where urlErr.code == .cancelled  { /* silent */ }
  catch let sliceError as SliceError      { ResultPanel.fail(sliceError, ...) }
  catch let error                         { ResultPanel.fail(.execution(.unknown(error.localizedDescription)), ...) }
  ```
- **mini-spec 初稿误写澄清**：
  - 初稿写的 `.streamChunk / .completed / .permissionDenied / .invocationCompleted` 在真实 ExecutionEvent enum 中**都不存在**——`.invocationCompleted` 是 `AuditEntry` 的 case 而非 `ExecutionEvent`（在 ExecutionEngine 内部直接写 audit log，不通过 stream 出来）
  - 真实事件流的 `.failed(SliceError)` 仅含 SliceError 一个关联值，不像初稿写的 `(report, error)` 二元组——report 由 `.finished(report:)` 单独 yield
- **理由**：
  - 把 ExecutionEvent 翻译职责放在 SliceAIApp（composition root 层）让 Windowing 不依赖 Orchestration（保持 Windowing 仅依赖 DesignSystem 的不变量）
  - 复用现有 ResultPanel API 避免 v0.2 重构 Windowing
  - Phase 2 加 BubblePanel / InlineReplaceOverlay 时再考虑 OutputDispatcher 直接持有多种 sink
- **风险**：
  - SliceAIApp 多 ~80 行 helper（14 case 翻译 + cancellation 处理）；可接受
  - 翻译表需要严格匹配 ExecutionEvent enum exhaustively——若未来 enum 加新 case 必须同步更新翻译表（Swift exhaustive switch 编译时强制）；plan 阶段在 ExecutionEventConsumer 内用 switch + no-default 守住
  - **【F3.2 风险】单一写入测试是设计契约**：plan 阶段必须加 `test_eventConsumer_doesNotAppendChunkToResultPanel`（spy ResultPanel + 模拟 .llmChunk 事件 → 断言 ResultPanel.append 调用次数 = 0）+ `test_outputDispatcher_chunkAppendOnce_perChunk`（spy WindowSink + 模拟 N 个 chunk → 断言 sink.append 调用次数 = N）；防止未来 refactor 误把 EventConsumer 改回 chunk 写入路径

#### D-30b · OutputDispatcher v0.2 non-window 降级 fallback【F2.3 修订 + R5 前根因审视】

> **⚠ 这是 v0.2 显式承担的技术债，Phase 2 必须偿还。**
>
> **Root cause**：① v1 UI 暴露 `displayMode` Picker（.window / .bubble / .replace 等）但 v1 AppDelegate.execute **运行时忽略 displayMode 总是开 ResultPanel** —— v1 已经是 lying UI；② v2 spec §3.3 + §3.4 同时设计 `V2Tool.displayMode: DisplayMode`（工具默认 mode）+ `OutputBinding.displayMode`（per-invocation override）两处 mode 字段，设计上有重叠尚未澄清；③ v2 OutputDispatcher 在 non-window mode 走 `.notImplemented`，与 v1 lying UI 直接冲突。
>
> **当前 fix 是 KISS 妥协而非彻底 root cause fix**：fallback to .window 延续了 v1 lying UI 的现状（用户选了 .bubble 但运行时仍是 window），代价是用 deprecation log + Phase 2 必偿还约束换取 §4.2.4 "Settings 无变化"硬约束的满足。
>
> **Phase 2 偿还路径**（mini-spec 不展开，留给 Phase 1 / Phase 2 plan 阶段决策）：
> 1. v2 spec 决策 `V2Tool.displayMode` vs `OutputBinding.displayMode` 的优先级与合并语义（消除设计重叠）
> 2. 实现 BubbleSink / InlineReplaceSink / SilentSink / StructuredSink / FileSink 5 个真实 sink（Windowing 层新增 5 个 panel/overlay 类）
> 3. 改回 OutputDispatcher 按 displayMode 路由真实 sink，删 fallback + deprecation log
> 4. v0.2 → v0.3 / v0.4 升级时通过 §M3.5 #9 回归项 (F2.3) 验证：原 .bubble 配置不再 fallback，真实出 BubblePanel
>
> **为什么不在 v0.2 直接做 Phase 2 完整方案**：① BubbleSink/InlineReplaceSink/StructuredSink 是新 UI 组件，每个 ~200~400 行实现 + Windowing 测试，成本相当于 v0.2 整个 M3 的工作量；② v0.2 用户基数 = 作者本人 + 早期使用者，lying UI 影响面可控；③ Phase 1 优先级是 MCP + ContextProvider 接入，比 sink 多样化更重要；④ v0.2 加 deprecation log 的代价 ≈ 0，但能给 Phase 1+ 观察"用户实际使用了哪些 displayMode"的数据（log 频次统计）。

- **决策【F5.3 修订，对照真实 API 重写】**：v0.2 期间修改 `OutputDispatcher.handle(chunk:mode:invocationId:) async throws -> DispatchOutcome` 实现（**真实方法名是 `handle` 不是 `dispatch`**，由 `OutputDispatcherProtocol` 定义；ExecutionEngine.runPromptStream 在 ExecutionEngine+Steps.swift line 247+ 调用 `output.handle(chunk:mode:invocationId:)`）：
  - **当前 M2 行为**（要改）：`mode == .window` → `await windowSink.append(chunk:invocationId:) → return .delivered`；`mode != .window`（`.bubble / .replace / .silent / .structured / .file` 5 个 case） → `return .notImplemented(reason: "PresentationMode.<x> — M2 not implemented; awaits Phase 2 ...")`
  - **M3 v0.2 修订后行为**：所有 5 个 non-window mode 分支统一改为 `await windowSink.append(chunk:invocationId:) → return .delivered`；**首 chunk 节流**记录 deprecation 警告：`os_log(.info, "OutputDispatcher: mode \(mode) not yet implemented in v0.2; falling back to .window sink")`
  - **节流策略**：维护 `Set<UUID>` 记录已发警告的 invocationId；每个 invocationId 仅首次进入 non-window 分支时 log（避免高频 chunk 流刷屏）；invocation 结束时不主动清理（v0.2 内存影响 < 1MB / 1000 invocation，可接受）
  - **mode 类型名**：M3.0 Step 4 完成前是 `PresentationMode`（M1 临时改名），完成后是 `DisplayMode`（rename 回 spec 原名）；本决策的 5 个 case 不变（`.bubble / .replace / .silent / .structured / .file` 是 enum case 名，不受类型 rename 影响）
- **理由（F2.3 root cause）**：
  - v1 AppDelegate.execute 真实**忽略 displayMode 总是开 ResultPanel**（v1 line 332+ 验证）；用户在 v1 ToolEditorView 可以选 `.bubble / .replace`，但运行时永远展示在 ResultPanel
  - v2 真实 `OutputDispatcher.handle` 在 non-window mode 返回 `.notImplemented(reason:)`，ExecutionEngine 收到后 yield `.notImplemented` ExecutionEvent → ResultPanel.fail；用户从 v1 迁移过来含 `.bubble` 配置的 tool 会变成"执行失败"，**违反 spec §4.2.4 "Settings 界面无功能变化"硬约束**
  - 选项 A（迁移时强制把 displayMode 规范化为 .window）：丢失用户偏好，违反"配置即所见"
  - 选项 B（handle non-window 分支 fallback + invocation 节流 log）：保留用户 displayMode 设置 + 运行时与 v1 等价 + Phase 2 真实 sink 落地时仅改 OutputDispatcher 内部分支即可——最 KISS 妥协
  - 选项 C（v0.2 隐藏 displayMode UI）：违反"Settings 无变化"被 F1.4 推翻
- **落地位置**：
  - `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift` 修改 `handle(chunk:mode:invocationId:)` 5 个 non-window case 分支（替代当前 `return .notImplemented(reason:)`）+ 加 `private var loggedInvocations: Set<UUID>` actor state（OutputDispatcher 是 actor 已是 Sendable）
  - **plan 阶段加单测**：`OutputDispatcherTests.test_handle_<mode>_fallsBackToWindowSink_returnsDelivered`（5 个 mode case；spy WindowSink 断言每次 invocation 仅首 chunk log + 5 个 mode case 都 return `.delivered` + spy.appendCalls 包含每个 chunk）
  - **plan 阶段加单测**：`OutputDispatcherTests.test_handle_window_unchanged`（窗口模式仍正常走 windowSink + log 不触发 — 回归保护）
- **风险**：
  - 用户可能误以为 `.bubble` 真的工作——必须在 ToolEditorView "展示模式" Picker 旁加注释"v0.2 暂时全部以窗口模式展示，Phase 2 起 bubble / replace 等模式生效"（mini-spec 不展开此 UI 文案，留 plan 期定）；这条注释属于 UI **添加** 而非 **改动行为**——合规的"无功能变化"前提下的提示性文案
  - log 即使节流后仍可能在多 invocation 场景下产生 spam → plan 阶段评估是否需要全局 LRU 限制（v0.2 单用户 < 100 invocation/天，目前不需要）
  - **invocation 结束时不清理 `loggedInvocations` Set**：v0.2 用户基数小可接受；Phase 2 删除 fallback 后 Set 也跟着删，不留内存泄露隐患
- **§4.2.5 回归追加项（F2.3）**：在 §M3.5 / §8 DoD 中加"v1 含 displayMode = .bubble / .replace 的 tool 配置经 migrator 迁移后，触发执行能正常出 ResultPanel 流式（不报 .notImplemented）；Console 中能看到首 chunk 的 deprecation log"项

### D-31 · v0.2.0 release tag 时机

- **决策**：M3 PR merge 后**立即**发 v0.2.0 tag + scripts/build-dmg.sh 0.2.0 打 unsigned DMG。用户初审 Q1 已确认；plan fresh review R6/R7 已把裸 `v0.2` tag 修正为 SemVer `v0.2.0`，确保 release.yml 剥 `v` 后得到 `0.2.0`，与 DMG 文件名一致。
- **理由**：
  - Phase 0 是底层重构，**无用户可见新功能**；早发 tag 作为 archival milestone 的成本极低
  - Phase 1 自然演进到 v0.3（MCP + 5 个 ContextProvider 接入），如果 v0.2 不发，Phase 1 实施期间会出现"main 已经走到 Phase 1 一半但没有可回退的 baseline tag"的窘境
  - "稳定 1 周再发"对一个 unsigned DMG + 当前唯一用户（作者本人）+ §4.2.5 已含手工回归的项目意义不大
- **风险**：merge 后立即发，若发现回归不能 roll back tag（GitHub Release 可 delete + recreate，但 git tag 已分发就是公开的）。**缓解**：scripts/build-dmg.sh 验证通过 + §M3.5 13 项手工回归全过（spec §4.2.5 原 8 项 + mini-spec 新增 4 项 + R11 新增 1 项） + xcodebuild Debug build SUCCEEDED 之后再 tag；若发现回归，发 v0.2.1 patch 而非 retag

---

## 6. 已拍板的 Open Questions

> 用户初审 R1（2026-04-28）三个 Open Questions 全部接受 Claude 推荐。本节保留问题原文 + 决策，便于日后 trace。

### Q1：v0.2 release tag + unsigned DMG 时机 — **决策 A**

- **背景**：spec §4.2.4 DoD 含"发布 v0.2 tag（Release Notes 按 scripts/build-dmg.sh 打包 unsigned DMG）"，但没说时机。
- **选项**：
  - A. M3 PR merge 后立即发 v0.2（archival mark；Phase 1 自然演进到 v0.3）
  - B. merge 后等 1 周稳定再发（多 1 周缓冲发现回归）
- **决策**：**A**（用户 R1 接受）。落地见 D-31 + M3.6。

### Q2：mini-spec 自身的 Codex review loop 上限 — **决策 A**

- **背景**：M2 跑了 11 轮 Codex review loop 才 APPROVE；M3 改动覆盖面更广（rename 跨 8 模块 + AppContainer 装配 + 触发链改造），review 轮次可能更多。
- **选项**：
  - A. 不设上限，跑到 APPROVE 为止（M2 模式），但每 5 轮回到用户简短 sync 进度
  - B. 设硬上限 10 / 15 / 20 轮，超出则用户人工 sync
- **决策**：**A**（用户 R1 接受）。落地见 §11.2。

### Q3：M3.0 Step 1 是否拆得更细 — **决策 A**

- **背景**：M3.0 Step 1 一次切 30+ 文件 caller 引用，commit 体积偏大。
- **选项**：
  - A. 保持单 commit（已是"零删除 + 零 rename"的最小风险窗口）
  - B. 按模块拆：SettingsUI / AppContainer / Windowing / SelectionCapture / Tests 5 个 sub-commit
- **决策**：**A**（用户 R1 接受）。落地见 D-26。

---

## 7. 风险与缓解

| 风险 | 缓解 |
|---|---|
| **R1** rename 跨 8 模块导致 git history 跟丢 | 用 `git mv` 让 git follow rename；commit message 显式写"git mv X to Y" 让 reviewer 能搜索 |
| **R2** Swift 6 严格并发跨 actor 边界出 Sendable 警告 | M2 已踩坑（FlowContext class 处理）；M3 接 AppContainer 时 ExecutionEngine 是 actor，AppDelegate `@MainActor`，调用必须 `await container.executionEngine.execute(...)`；ResultPanel 也是 `@MainActor`，事件翻译 helper 必须在 `@MainActor` 内消费 stream |
| **R3** SourceKit "No such module" 假阳骚扰 | M2 Task-detail §Known traps 已记；M3 期间统一以 `swift build` / `swift test` / `xcodebuild` / `swiftlint --strict` 4 关 CI gate 为唯一真值，忽略 SourceKit warning |
| **R4** xcodebuild 必须每个子任务后跑 | M2 仅最后 task 跑；M3 改动 SliceAIApp 后每个 step 都必须跑（启动崩溃不会被 SwiftPM 测试发现）；plan 在每个 task 的 verification 步骤里写明 |
| **R5** 用户现有 config.json 在 migrator 跑出错 | M1 已落地 ConfigMigratorV1ToV2 + 10+ fixture 单测；但**真实用户 config 边界形态未必都覆盖**——M3 mini-spec 要求实施期跑一次 dry-run（用真实 ~/Library/Application Support/SliceAI/config.json 输入 migrator，diff 输出验证） |
| **R6** PermissionBroker default-allow 与 audit log 配合不当导致刷屏 | M2 已落地 audit log + 脱敏；v0.2 PermissionBroker 走 default-allow 但**仍写 audit**——日志在 `~/Library/Application Support/SliceAI/audit.jsonl`，不在 stdout，不刷屏 |
| **R7** 4 个内置工具的 ProviderSelection.fixed 适配错误 | DefaultV2Configuration 已在 M1 用 `.fixed(providerId: openAIDefault.id, modelId: nil)` 装配；migrator 也对 v1 Tool.providerId / modelId → `.fixed(providerId, modelId)`；M3 不动这部分逻辑 |
| **R8** ToolEditorView 数据 binding 改写后 UI bug 难发现 | 单测覆盖不到 SwiftUI binding；M3.5 用户手工回归"修改 Tool / Provider 后配置立即生效"作为兜底 |

---

## 8. DoD（spec §4.2.3 M3 + master todolist §3.3 合并）

- [ ] `swift build` 成功（全 10 个 target）
- [ ] `swift test --parallel --enable-code-coverage` 全绿；覆盖率：SliceCore ≥ 90% / Orchestration ≥ 75% / Capabilities ≥ 60%
- [ ] `swiftlint lint --strict` 0 violations
- [ ] `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` BUILD SUCCEEDED
- [ ] **§4.2.5 spec 原 8 项 + mini-spec 新增 4 项 + R11 新增 1 项，共 13 项手工回归全部通过**（用户报告；新增 5 项 = variables 编辑写盘 + 全新安装写盘 + displayMode 降级 fallback + 启动失败 UX + Provider 切换清空 modelId）
- [ ] 4 个内置工具（Translate / Polish / Summarize / Explain）实机行为与 v0.1 等价
- [ ] `config-v2.json` 实际生成；旧 `config.json` 未被修改
- [ ] 同一机器切回旧分支 / 旧 build：旧 app 读取原 `config.json` 仍正常
- [ ] **V2 命名已回归 spec 原名**：`grep -rn "V2Tool\|V2Provider\|V2Configuration\|V2ConfigurationStore\|DefaultV2Configuration\|PresentationMode\|SelectionOrigin"` 在 SliceAIKit/ + SliceAIApp/ 0 匹配
- [ ] PR 不引入任何 TODO / FIXME 注释（要做的留成 Issue）
- [ ] `docs/Task-detail/2026-04-28-phase-0-m3-mini-spec.md`（mini-spec 归档）+ `docs/Task-detail/2026-04-XX-phase-0-m3-implementation.md`（implementation 归档）
- [ ] master todolist M3 状态 → ✅
- [ ] v0.2.0 release tag + DMG（M3 PR merge 后立即发，决策 D-31；v0.2 是里程碑语义）

---

## 9. Phase 0 整体 DoD（M1 + M2 + M3 全部合入后，spec §4.2.4）

> 本节抄自 spec §4.2.4，作为 M3 PR merge 时一并验证的总收口。

- [ ] `swift build` 成功（全 10 个 target）
- [ ] `swift test --parallel --enable-code-coverage` 全绿；覆盖率：SliceCore ≥ 90% / Orchestration ≥ 75% / Capabilities ≥ 60%
- [ ] `swiftlint lint --strict` 0 violations
- [ ] 原 4 个内置工具在实机上与 v0.1 行为等价（翻译 / 润色 / 总结 / 解释）
- [ ] 老 `config.json` 经 migrator 产出 `config-v2.json`；**旧 `config.json` 未被修改**；切回旧分支 app 仍正常
- [ ] Settings 界面无功能变化（不要误加 UI）
- [ ] PR 不引入任何 TODO / FIXME 注释
- [ ] `docs/Task-detail/phase-0-*.md` 归档 M1/M2/M3 各自的实施过程
- [ ] 发布 **v0.2.0** tag（Release Notes 按 `scripts/build-dmg.sh 0.2.0` 打包 unsigned DMG）

---

## 10. References

- **Spec**：`docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md` §3.3 / §3.4 / §3.7 / §3.8 / §3.9 / §4.2.3 / §4.2.4 / §4.2.5
- **M1 plan**：`docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（顶部 §A 实施期改名 / §B 第七轮评审 / §C 第八轮评审）
- **M2 plan**：`docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`（spec §3.4 step 对照表 / §C-1 zero-touch / §C-7 复制非替换）
- **M2 Task-detail**：`docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md` §7.3（实施期偏离 plan）/ §7.6（M3 承接 backlog）
- **Master todolist**：`docs/v2-refactor-master-todolist.md` §3.3 M3 + §8 SOP
- **决策索引**：spec §5.2 D-1 ~ D-25；本 mini-spec 引入 D-26 ~ D-31
- **CLAUDE.md**：项目通用规则 + 架构总览 + 模块依赖不变量

---

## 11. 评审执行说明

### 11.1 用户初审

mini-spec 草稿写完后，用户先初审：
- 范围是否合适（in-scope / out-of-scope 是否漏 / 多）
- M3.0 5 步小 commit 序列是否可行
- D-26 ~ D-31 是否有反对意见
- Q1 / Q2 / Q3 三个 open question 拍板

### 11.2 Codex review loop

用户初审通过后（R1 已通过，2026-04-28），进入 `superpowers:codex-review-loop`：
- **节奏（Q2 决策 A）**：不设硬上限轮数，跑到 APPROVE 为止；但**每 5 轮**回到用户做一次简短 sync（汇报本批 5 轮收敛了哪些 finding / 还剩哪些争议 / 是否要调整方向），避免 30+ 轮无人监督跑飞
- 每轮 Codex review verdict 写到 §0 评审与修订表
- 接受的 finding 直接修订 mini-spec
- 拒绝的 finding 写"已 defer / 不接受"理由 + 留在表内便于 trace
- APPROVE 后进入 `superpowers:writing-plans` 出 implementation plan

### 11.3 implementation plan

mini-spec APPROVE 后，下一个 task：
- 创建 `docs/superpowers/plans/2026-04-XX-phase-0-m3-switch-to-v2.md`
- 按 mini-spec 的任务拆解（M3.0 ~ M3.6）展开为 sub-task 级粒度
- 含每个 sub-task 的代码示例 / 验证命令 / 回滚方案
- 实施期再走一次 Codex review loop（仅针对代码 + 实测结果）

---

> **本 mini-spec 完成 = Phase 0 M3 真正进入实施前的最后一道闸门**。
> 写到这里 ~ 700 行；M3 implementation plan 预估 ~1500 行（参照 M2 plan 2232 行体量，但 M3 任务数较少）。
