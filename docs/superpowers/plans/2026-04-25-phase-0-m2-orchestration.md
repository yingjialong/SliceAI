# Phase 0 M2 · Orchestration + Capabilities 骨架 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.
>
> **Plan 状态**：第一稿（2026-04-25 起草，未过 Codex 评审）。当前覆盖 **Header + Architecture + 全部文件清单 + 全部 14 个 Task 的标题/文件/目标 + Task 0 / Task 1 完整 TDD 步骤**；Task 2–14 的详细 TDD 步骤待 plan 评审通过后展开。

**Goal:** 把 SliceAI v2.0 spec §3.4（执行引擎）+ §3.9.6.5（权限闭环）+ §3.9.2 / §3.9.3 / §3.9.5（安全下限 / 路径沙箱 / 日志脱敏）+ §3.3.6（OutputBinding）落地为 `Orchestration` + `Capabilities` 两个 SwiftPM target 的可独立单测的骨架，**完全不接入 app 启动链路**——`AppContainer` / `ToolExecutor` / 触发链 / `FileConfigurationStore` 全部零触及，app 行为保持 v0.1 + M1 现状不变。M3 才做"切到 ExecutionEngine + 删除 ToolExecutor"。

**Architecture（M2 落地约束，沿用 M1 命名偏离）：**

新目录布局——所有新代码限定在 `Orchestration/` + `Capabilities/` 两个 M1 已建好的空 target 下，零触及现有 8 个模块：

```
SliceAIKit/Sources/Orchestration/                      （M1 已建空 target，M2 填实）
  ├─ Events/                                            （执行事件 + 报告）
  │   ├─ ExecutionEvent.swift                           Task 1
  │   └─ InvocationReport.swift                         Task 1
  ├─ Engine/                                            （执行引擎 + 依赖接口）
  │   ├─ ExecutionEngine.swift                          Task 3 / 4
  │   ├─ ProviderResolver.swift                         Task 2
  │   └─ ProviderResolutionError.swift                  Task 2
  ├─ Context/                                           （上下文采集）
  │   ├─ ContextCollector.swift                         Task 5
  │   └─ ContextCollectorError.swift                    Task 5
  ├─ Permissions/                                       （权限闭环）
  │   ├─ PermissionBrokerProtocol.swift                 Task 6
  │   ├─ PermissionBroker.swift                         Task 6
  │   ├─ PermissionGrantStore.swift                     Task 6
  │   ├─ EffectivePermissions.swift                     Task 7
  │   ├─ PermissionGraph.swift                          Task 7
  │   └─ PermissionDecisionError.swift                  Task 6 / 7
  ├─ Telemetry/                                         （成本 + 审计）
  │   ├─ CostAccounting.swift                           Task 8
  │   ├─ CostRecord.swift                               Task 8
  │   ├─ AuditLogProtocol.swift                         Task 9
  │   └─ JSONLAuditLog.swift                            Task 9
  ├─ Output/                                            （结果分派）
  │   ├─ OutputDispatcherProtocol.swift                 Task 10
  │   └─ OutputDispatcher.swift                         Task 10
  ├─ Executors/                                         （三态 executor）
  │   └─ PromptExecutor.swift                           Task 11
  └─ Internal/
      └─ Redaction.swift                                Task 9（共享脱敏工具）

SliceAIKit/Sources/Capabilities/                       （M1 已建空 target，M2 填实）
  ├─ SecurityKit/
  │   ├─ PathSandbox.swift                              Task 12
  │   └─ PathSandboxError.swift                         Task 12
  ├─ MCP/
  │   ├─ MCPClientProtocol.swift                        Task 13
  │   └─ MockMCPClient.swift                            Task 13（仅 SkillRegistryTests / OrchestrationTests 使用，类型在 Capabilities 但仅供测试注入）
  └─ Skills/
      ├─ SkillRegistryProtocol.swift                    Task 13
      └─ MockSkillRegistry.swift                        Task 13
```

**对应测试**（每个组件一个 test file，Capabilities 与 Orchestration 各自独立）：

```
SliceAIKit/Tests/OrchestrationTests/
  ├─ ExecutionEventTests.swift                          Task 1
  ├─ InvocationReportTests.swift                        Task 1
  ├─ ProviderResolverTests.swift                        Task 2
  ├─ ExecutionEngineTests.swift                         Task 3 / 4
  ├─ ContextCollectorTests.swift                        Task 5
  ├─ PermissionBrokerTests.swift                        Task 6
  ├─ PermissionGraphTests.swift                         Task 7
  ├─ CostAccountingTests.swift                          Task 8
  ├─ JSONLAuditLogTests.swift                           Task 9
  ├─ OutputDispatcherTests.swift                        Task 10
  ├─ PromptExecutorTests.swift                          Task 11
  └─ Helpers/
      ├─ MockProvider.swift                             Task 2 / 3 / 4
      ├─ MockContextProvider.swift                      Task 5
      └─ MockOutputDispatcher.swift                     Task 10

SliceAIKit/Tests/CapabilitiesTests/
  ├─ PathSandboxTests.swift                             Task 12
  ├─ MCPClientProtocolTests.swift                       Task 13
  └─ SkillRegistryProtocolTests.swift                   Task 13
```

**Tech Stack:** Swift 6.0 / XCTest / `swift build` / `swift test --parallel --enable-code-coverage` / SwiftLint strict / Foundation only（Orchestration / Capabilities 都是零 UI、零 AppKit；Capabilities 允许触碰 sqlite C lib 但通过 Foundation `SQLite` 包装，MVP 阶段用 `FileHandle` jsonl 与 sqlite3 C API 即可）。

**References:**
- Spec: `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md` §3.4 / §3.3.5 / §3.3.6 / §3.9 / §4.2.3 M2
- M1 落地文件: `SliceAIKit/Sources/SliceCore/` 下 19 个 V2* / 领域类型（M1 plan 顶部"评审修正索引 A"——M2 一律使用 `V2Tool` / `V2Provider` / `V2Configuration` / `PresentationMode` / `SelectionOrigin` 等 M1 实际落地名，**不**用 spec 中的 `Tool` / `Provider` / `DisplayMode` / `SelectionSource` 原始名）
- 决策：D-17（平铺并发非 DAG）/ D-22（能力下限不可由 Provenance 突破）/ D-24（PermissionGraph 静态闭环）/ D-25（Provenance 只调 UX 文案）
- v1 zero-touch 范围: `LLMProviders` / `SelectionCapture` / `HotkeyManager` / `DesignSystem` / `Windowing` / `Permissions` / `SettingsUI` / `SliceAIApp` 一律不动；`SliceCore` 也不动（M1 已就绪，M2 仅消费 V2* 类型）
- M1 PR / merge commit 基线: `5cdf0f7`（main HEAD as of 2026-04-25）

---

## 评审修正索引（Review Amendments）

> 与 M1 plan 体例一致；当前为第一稿，索引段先占位，后续每轮 Codex 评审在此追加 Round 章节。
>
> **代码块快照约定（沿用 M1）**：plan 正文里的 Swift 代码块是"实施期路径指南"，记录该 Task 那一刻的实现蓝本，**不会**回填后续 fix commit 的更新。后续 worker 需要**最终源码**时应读 `SliceAIKit/Sources/Orchestration/` / `SliceAIKit/Sources/Capabilities/` 下的对应文件，而非 plan 里的代码块。当落地代码与本 plan 叙述/代码块不一致时，**以本索引 + 最终源码为准**。

### A. 实施期改名（已知）

> 第一稿暂无新改名；M1 已记录的 `PresentationMode` / `SelectionOrigin` 在 M2 中**继续沿用**——M2 不做命名修复，M3 rename pass 才统一回归 spec 原始意图。

### B. Codex 评审回合记录

#### Round 1（2026-04-25，第一稿）

**Verdict**: REWORK_REQUIRED → 接受所有 8 条 finding 并落地修订（本次提交，**不接受任何 finding 的反驳**）。

| Finding | 问题 | 修复落地 |
|---|---|---|
| **P1-1** dry-run 绕过 PermissionBroker 下限 | 第一稿 Task 6 写 `isDryRun=true` 时所有 gate 直接 `.approved`，违反 spec §3.9.2 "下限只依赖 tier" + D-22；dry-run 仍跑 context resolution / LLM，需要 readonly-local / readonly-network 权限 | Task 6 关键设计点重写：dry-run 仅由 ExecutionEngine Step 7 跳过副作用**实际执行**，broker 入口不豁免；新增 `GateOutcome.wouldRequireConsent(uxHint:)` 给 Playground UI 显示"如果实际执行需要 X / Y / Z 权限"，但**不静默 .approved** |
| **P1-2** 失败/拒绝路径未写 AuditLog | spec §3.9.7 明确"任何 execute 调用都至少产生一条 InvocationReport，成功/失败/被拒都记录"；第一稿 Task 4 仅 happy path 写 audit，permission-deny / context-fail 直接 yield `.failed` 退出 | Task 4 关键设计点重写：引入私有 helper `finishFailure(error:invocationId:declared:effective:flags:)` —— 构造 InvocationReport → `AuditLog.append` → 才 yield `.failed`；ExecutionEngineTests 4 条失败路径全部断言 audit.entries.count == 1 |
| **P2-1** PermissionBroker 测试矩阵不全（D-25 漏 firstParty 部分） | 第一稿 Task 6 写"至少抽样 12 cell"；D-25 / spec §3.9.1 要求 firstParty 对所有 4 tier 都不能跳过首次确认 | Task 6 关键设计点：5 tier × 4 provenance = **20 cell 全覆盖**（不抽样）；单列 firstParty 对 readonly-network / local-write 不跳过首次确认（D-25）+ firstParty 对 network-write / exec 每次都要确认（D-22）的断言 |
| **P2-2** PermissionGraph 缺 pipeline 测试 + provider 推导来源不清 | 第一稿 Task 7 测试矩阵只覆盖 prompt / agent / empty；`compute(tool:)` 如何从 `ContextRequest.providerId` 找到 provider 的 `inferredPermissions(for:)` 未说明 | Task 7 关键设计点：`PermissionGraph(providerRegistry: ContextProviderRegistry)` 构造期注入注册表（不硬编码 provider 名字）；测试矩阵补 2 条 pipeline 用例 + 1 条 `unknownProvider` 错误用例 |
| **P2-3** OutputDispatcher 主展示来源与 M1 R-B 修正冲突 | 第一稿 Task 10 写"根据 `V2Tool.outputBinding.primary` 派发"；M1 plan R-B / commit `d141c05` 已锁定 `displayMode` 是 primary truth、`outputBinding.primary` 仅作 decoder 一致性校验的冗余字段 | Task 10 标题 + 关键设计点全部改为"根据 `V2Tool.displayMode` 派发"；ExecutionEngine 始终传 `tool.displayMode`，**不读** `outputBinding?.primary`；OutputBinding.sideEffects 仍由 ExecutionEngine Step 7 直接读，与 displayMode 解耦 |
| **P2-4** Task 0 编号 33 与 Task_history 当前最大值冲突 | M1 PR merge 后 `docs/Task_history.md:7` 已是 "## Task 33 · Phase 0 M1"；plan Task 0 多处仍硬编码 Task 33 / 提到 "Task 32 在第 5 行" | Task 0 全部硬编码 Task 33 → Task 34；Step 3 插入位置改为"在 Task 33 之前"；Step 1 grep 期望从 "Task 32/31/30，下一个 33" → "Task 33/32/31，下一个 34"；Step 4 commit message 同步 |
| **P3-1** Task 3 "init 接受 7 个依赖" | 实际列了 8 个（contextCollector / permissionBroker / providerResolver / mcpClient / skillRegistry / costAccounting / auditLog / output） | 改为 "init 接受 8 个依赖" |
| **P3-2** Task 1 测试数量混用 4 / 5 | Step 9 备注同时写 "4 tests passing" 与 "5 tests pass" | 统一为 "5 tests pass"（ExecutionEventTests × 2 + InvocationReportTests × 3） |

**未做修订**：无。Codex 8 条 finding 全部接受落地（评审报告全文见 commit message 引用 + 对话记录）。

#### Round 2（2026-04-25，Round 1 修订后）

**Verdict**: REWORK_REQUIRED → Round 1 全 8 finding 验证 ✅；新发现 6 条 finding（3 P1 + 3 P2）全部接受并落地（本次提交，**不接受任何反驳**）。

| Finding | 问题 | 修复落地 |
|---|---|---|
| **B-1** finishFailure 字段不闭合 | Round 1 修订自己引入的 bug：finishFailure 签名提到 `errorKind` / `startedAt`，但 Task 1 InvocationReport struct 不含 `errorKind` 字段；helper 签名也没有 `startedAt` 入参 | Task 1 InvocationReport 加 `outcome: InvocationOutcome` 字段（含 `.success` / `.failed(errorKind:)` / `.dryRunCompleted`）+ 新增 `InvocationOutcome` enum；Task 4 finishFailure 签名 `finishFailure(error:invocationId:toolId:declared:effective:flags:startedAt:)`；finishSuccess 同步补 outcome 入参 |
| **B-2** wouldRequireConsent 状态机 Task 4 / Task 6 矛盾 | Task 6 说"caller 跳过执行继续主流程"；Task 4 Step 2.5 说"转 `.notImplemented` 事件"——两处描述自相矛盾 | Task 1 ExecutionEvent 新增 2 case：`.permissionWouldBeRequested(permission:uxHint:)`（Step 2.5 dry-run 时 yield 单条事件继续主流程）+ `.sideEffectSkippedDryRun(SideEffect)`（Step 7 dry-run 时 yield 替代实际执行）；Task 4 Step 2.5 / Step 7 / Task 6 描述统一为 "continue main flow，但 yield 上述 2 case 标记 dry-run skip" |
| **B-3** GateOutcome 4 态未要求 exhaustive switch | 新增 `.wouldRequireConsent` 后，4 态 GateOutcome 若实现用 `default` 处理，未来加 case 会漏 | Task 4 关键设计点新增 "实现必须用无 `default` 的 `switch outcome` 覆盖全 4 case；Task 14 集成验证 step 增加 grep `default:` 在 PermissionBroker.swift / ExecutionEngine.swift 的反向断言（grep 返回非零=合格）" |
| **B-4** OutputDispatcher 每 chunk 调用语义未锁定 | 非 `.window` 模式可能产生与 chunk 数量等比的 `.notImplemented` 调用，污染流；测试未约束 | Task 10 关键设计点：`.window` 测试断言 3 chunks → `InMemoryWindowSink.received.count == 3` + 顺序 `["a", "b", "c"]`；非 `.window` 模式 ExecutionEngine **只在第一个 chunk 时 yield 一次 `.notImplemented` ExecutionEvent**（用 `var notImplementedYielded = false` 守卫），后续 chunks dispatch 仍调用但不再 yield 重复事件 |
| **B-5** PermissionGraph.compute 改 async throws 后调用漏 try | Task 4 Step 2 / Task 7 章节都写 `await compute(...)`，缺 `try`，直接编译错误 | Task 4 Step 2 改 `try await permissionGraph.compute(...)` + 加 `do { ... } catch let e as PermissionGraph.Error where case .unknownProvider = e { finishFailure(.configuration(.invalidTool(...))) }`；Task 7 关键设计点同步注明 caller 必须 `try await` |
| **B-6.1** Task 2 `.fixed(providerId:)` 漏 modelId 入参 | M1 落地 `case fixed(providerId: String, modelId: String?)`（`SliceAIKit/Sources/SliceCore/ProviderSelection.swift:9` verified）；plan 写 `.fixed(providerId:)` 漏 modelId | Task 2 关键设计点：`.fixed(providerId:, modelId:)` 形态；`.resolve(_)` 解析时优先 modelId，若 nil 回落 `provider.defaultModel`（V2Provider 字段，M1 已就绪） |
| **B-6.2** Task 5 ContextCollector failures 类型不对齐 | M1 `ResolvedExecutionContext.failures: [ContextKey: SliceError]`（`SliceAIKit/Sources/SliceCore/ResolvedExecutionContext.swift:24` verified）；plan 写 `[String: Error]` | Task 5 关键设计点：`failures: [ContextKey: SliceError]`（与 M1 类型对齐）；`ContextCollectorError.requiredFailed(key: ContextKey, underlying: SliceError)`（参数类型同步）；非 SliceError 的底层错误由 collector 包装为 SliceError 后再写入 |
| **B-6.3** AuditLog.append 接口与 Task 4 调用不对齐 | Task 4 调 `auditLog.append(report)`（report = InvocationReport）；Task 9 定义 `append(_ entry: AuditEntry)`；类型不匹配 | Task 9 关键设计点：`AuditEntry` 是 enum，含 `.invocationCompleted(InvocationReport)` / `.sideEffectTriggered(invocationId:UUID, sideEffect:SideEffect, executedAt:Date)` / `.logCleared(at:Date)` 三 case；Task 4 改用 `auditLog.append(.invocationCompleted(report))`；finishFailure 内部同样用 `.invocationCompleted(report)` 写入（success / failure 都走 invocationCompleted，区分由 `report.outcome`） |
| **B-6.4** Task 12 PathSandbox `standardizedFileURL` 不 resolve symlink | spec §3.9.3:989 措辞 "URL(fileURLWithPath:).standardizedFileURL 消除 .. / symlink" 与 Foundation API 实际行为不符（standardizedFileURL 只消除 `..` 不 resolve symlink） | Task 12 关键设计点：`PathSandbox.normalize(_:role:)` 实现链改为 `URL(fileURLWithPath:).resolvingSymlinksInPath().standardizedFileURL`（先 resolve symlink，再 standardize）；plan 注：spec §3.9.3 措辞错误本 plan 按 Foundation API 真实语义实现，spec 修订留下一轮 spec 评审；测试矩阵补 symlink 攻击：在 `~/Documents` 下 `ln -s` 指向 `~/Library/Keychains` → normalize 应返回 throw `.escapesWhitelist` |

**未做修订**：无。Codex 6 条 finding 全部接受落地。Round 2 修订后跑了 verify pass：grep `await compute(` 无残留无 `try` 调用 / grep `auditLog.append(report)` 已替换为 `auditLog.append(.invocationCompleted(report))` / grep `[String: Error]` 已无 / grep `.fixed(providerId:)` 已含 modelId 形态。

#### Round 3（2026-04-25，Round 2 修订后）

**Verdict**: REWORK_REQUIRED → Round 2 全部 9 子 finding 落地（B-3 部分落地：Task 14 缺 grep `default:` 反向断言）；新发现 1 P1 + 4 P2 + 2 P3 = 7 条 finding 全部接受并落地（本次提交）。

| Finding | 问题 | 修复落地 |
|---|---|---|
| **R3-P1** ContextRequest.providerId 与 M1 源码不一致 | M1 `SliceCore/Context.swift:11` 字段是 `provider: String`（非 `providerId`）；plan Task 5 line 820 + Task 7 line 882 / 895 都写 `request.providerId` → 直接编译错误 | 全部修正为 `request.provider`；Task 5 / Task 7 修订段加 verified 标注 |
| **R3-P2.a** PermissionGraph.Error 定义位置不明 | plan 多处用 `PermissionGraph.Error.unknownProvider(id:)` 但未明示是 nested enum 还是 SliceCore PermissionError 的 case；Codex 建议改用统一 `PermissionError` | **接受 finding 但 push back Codex 建议的命名**——sanity check 发现 M1 `SliceError.swift:141` 已定义 `public enum PermissionError`（系统权限错误如 `accessibilityDenied / inputMonitoringDenied`），与 v2 工具权限决策错误语义不同；同名跨模块会让代码读者混淆。最终落地：新建独立 `PermissionDecisionError` enum（Task 6 Create + Task 7 Modify 追加 .unknownProvider）；废弃 `PermissionGraph.Error` 嵌套；**废弃 Codex 建议的 PermissionError 命名** |
| **R3-P2.b** ErrorKind.map(_:) 未定义 | `finishFailure` 调用 `ErrorKind.map(error)` 但 plan 未说明定义位置 / 签名 | 改名为 `ErrorKind.from(_:)` 静态 helper；明确签名 `static func from(_ error: SliceError) -> ErrorKind`；定义放在 `Orchestration/Events/InvocationReport.swift` 中 `extension InvocationOutcome.ErrorKind`；按 SliceError 4 顶层 case 映射 |
| **R3-P2.c** notImplementedYielded 生命周期歧义 | Task 10 写 "ExecutionEngine 内部用 var notImplementedYielded 守卫" 未明确是 actor field 还是 local var；做成 actor field 会跨 invocation 污染 | Task 10 关键设计点明确 "**必须是 execute(tool:seed:) 函数内 local var**"；测试矩阵补一条"同一 engine 实例连续 execute 两次，每次都独立产出 1 条 .notImplemented" 的跨 invocation 隔离断言 |
| **R3-P2.d** MCPCallResult 类型未定义 | Task 13 protocol 引用 `MCPCallResult` 但 M1 SliceCore 没定义（grep verified），plan 也没给结构 | Task 13 关键设计点新增 `MCPCallResult` struct 定义（content: [String] / isError: Bool / meta: [String: String]?，放在 Capabilities/MCP/MCPClientProtocol.swift 同文件）+ 测试覆盖 round-trip |
| **R3-P3.a** Task 4 catch pattern 缺正确语法示例 | 旧 plan / Codex 原话写 `catch let e as PermissionGraph.Error where case .unknownProvider = e` —— Swift catch 子句不支持 `where case` 联用 | Task 4 Step 2 / Task 7 关键设计点统一改为 `catch PermissionDecisionError.unknownProvider(let id) { ... }`（Swift catch pattern 直接匹配 case 关联值的标准写法；`PermissionDecisionError` 独立命名见 R3-P2.a 行的 push back 说明）；plan 显式写"严禁 where case 联用" |
| **R3-P3.b** dry-run vs 非 dry-run 测试缺对照 | dry-run 路径已覆盖，但未单独测试非 dry-run + `.requiresUserConsent` → finishFailure 的对照路径，caller 可能误把 `.permissionWouldBeRequested` 当作 `.failed` 信号 | Task 4 测试矩阵从 5 条扩展到 6 条：新增 "non-dry-run + .requiresUserConsent → finishFailure(.permission(.notGranted))" 路径，断言 audit 1 条 `.invocationCompleted` outcome `.failed(.permission)` + yield `.failed`；与 dry-run 形成显式对照 |
| **R3-补**：Round 2 B-3 部分落地补全 | Round 2 落地 Task 4 关键设计点的 "无 default switch outcome" 约束，但承诺的 Task 14 grep `default:` 反向断言未真正写出 | Task 14 新增 Step 5.5：`grep -c "^[[:space:]]*default:" PermissionBroker.swift / ExecutionEngine.swift / InvocationReport.swift` 三处期望 0；非零则失败 |

**未做修订 / Push back（Round 3 receiving-code-review skill 应用）**：

- **R3-P2.a 命名建议被 push back**：Codex 建议改用统一 `PermissionError`，但 sanity check 发现 M1 `SliceError.swift:141` 已定义 `public enum PermissionError`（含 `accessibilityDenied / inputMonitoringDenied`，系统权限错误命名空间），与 v2 工具权限决策错误（`undeclared / denied / sandboxViolation / unknownProvider`）**语义完全不同**；同名跨模块会让代码读者混淆。改用独立 `PermissionDecisionError` 解决。**接受 finding（命名歧义需 fix），push back 修复方案的命名选择**——这是依据 M1 源码事实的判断，不是盲信评审建议（receiving-code-review skill：technical rigor not performative agreement）
- 其他 7 条 finding 全部接受 Codex 修复方案直接落地

修订后 verify：grep `request.providerId` 无残留（仅历史表）/ grep `PermissionGraph.Error` 仅在 Round 1+2 历史表残留 / grep `PermissionError\.\(unknownProvider\|undeclared\|sandboxViolation\)` 在 Task 设计点段无残留（已全部改为 `PermissionDecisionError`）/ grep `ErrorKind.map` 已替换为 `ErrorKind.from` / grep `MCPCallResult` 在 Task 13 有完整 struct 定义 / grep `PermissionDecisionError` 在 Task 6/7 Files 段 + Task 4/7 catch / throw 处共 6+ 处引用一致。

---

## 关键架构约束（M2 不变量，所有 Task 必须满足）

### C-1：v1 + M1 双重 zero-touch

**M2 期间 git diff 必须可证明**：除 `SliceAIKit/Package.swift`（仅可能因新增 testTarget 而修改） + `SliceAIKit/Sources/Orchestration/`（M1 placeholder 替换）+ `SliceAIKit/Sources/Capabilities/`（同）+ `SliceAIKit/Tests/OrchestrationTests/`（M1 placeholder 替换）+ `SliceAIKit/Tests/CapabilitiesTests/`（同）+ `docs/`（plan / Task-detail）外，**任何文件不得有改动**。

```bash
# DoD 验证命令
git diff origin/main..HEAD -- \
  SliceAIKit/Sources/SliceCore \
  SliceAIKit/Sources/LLMProviders \
  SliceAIKit/Sources/SelectionCapture \
  SliceAIKit/Sources/HotkeyManager \
  SliceAIKit/Sources/DesignSystem \
  SliceAIKit/Sources/Windowing \
  SliceAIKit/Sources/Permissions \
  SliceAIKit/Sources/SettingsUI \
  SliceAIApp \
  | wc -l
# 期望: 0
```

`Package.swift` 的修改也仅限于"删 Orchestration / Capabilities 的 placeholder testTarget 行（如有）+ 新增 Orchestration / Capabilities testTarget 依赖"，不得修改任何已存在的 target 配置。

### C-2：使用 M1 实际落地的 V2* 类型签名

spec §3.4 的伪代码用 `tool: Tool` / `provider: Provider`，M1 命名偏离后 M2 必须用 `V2Tool` / `V2Provider`。`ExecutionEngine.execute` 的真实签名是：

```swift
public func execute(
    tool: V2Tool,                       // M1 命名偏离：spec 写的 Tool
    seed: ExecutionSeed
) -> AsyncThrowingStream<ExecutionEvent, Error>
```

OutputBinding 字段类型也是 `PresentationMode`（M1 命名偏离），不是 `DisplayMode`。

### C-3：平铺并发，非 DAG（D-17）

`ContextCollector.resolve(seed:requests:)` 用 `withTaskGroup` 把每个 `ContextRequest` 并发拉取，**不实现 provider-to-provider 的依赖图**。失败的 request 进入 `ResolvedExecutionContext.failures`，可选 request 失败不阻断主流程，必填 request 失败让整个 ExecutionEngine 主流程 `yield .failed(.context(.required(...)))`。

### C-4：PermissionGraph 是纯静态校验（D-24）

`PermissionGraph.compute(tool:)` 只读 `tool.contexts` / `tool.outputBinding.sideEffects` / `tool.kind.agent.mcpAllowlist` 等**静态字段**，不做 I/O、不依赖运行时 seed。`ExecutionEngine` 的 Step 2（PermissionGraph 校验）必须在 Step 3（ContextCollector.resolve）**之前**执行——访问永远不能早于校验。

### C-5：能力下限硬编码于 PermissionBroker 默认实现（D-22）

M2 的 `PermissionBroker` 默认实现允许 `firstParty` 工具 readonly-local 操作直接通过，但 `network-write` / `exec` 永远要求每次确认（无论 provenance）。M2 的"放行"通过 `MockPermissionBroker` 在测试中模拟，生产路径下默认实现产出"待确认"状态——但因为 M2 不接入 app，这条策略仅由 `PermissionBrokerTests` 的 §3.9.2 表覆盖测试矩阵，不会真的弹 UI。

### C-6：OutputDispatcher 仅实现 .window 分支

`PresentationMode` 六态中 M2 只实现 `.window`（落到一个测试用 sink）；`.bubble` / `.replace` / `.file` / `.silent` / `.structured` 全部返回 `.notImplemented` 事件。Phase 2 才填实其他分支。

### C-7：PromptExecutor 是 ToolExecutor 的"复制"而非"替换"

`PromptExecutor.swift` 从 `SliceCore/ToolExecutor.swift` 把"prompt 渲染 + 取 API Key + 调 LLMProvider"逻辑**逐行复制**到 Orchestration/Executors/，但消费 `V2Tool` / `V2Provider` 类型而非 v1 `Tool` / `Provider`。**`SliceCore/ToolExecutor.swift` 原封保留**，M3 rename pass 才删除。两份逻辑短暂共存是 zero-touch 的代价。

### C-8：日志脱敏在 AuditLog 入口统一处理（§3.9.5）

`JSONLAuditLog.append(_:)` 在写入前对所有 string payload 跑一次 `Redaction.scrub(_:)`，落盘的 jsonl **永远不含**：
- Selection 原文（只写 sha256 + length + language）
- API Key / Token / Cookie / Secret 等敏感字段（key 名匹配 regex 即替换为 `<redacted>`）
- promptRendered.preview 超过 200 字符的部分（`… <truncated N chars>`）

Settings → Privacy 的 "记录选区原文" opt-in 由 Phase 2 实现，M2 阶段默认关闭。

### C-9：Capabilities 只放接口 + Mock，不放真实实现

`MCPClientProtocol` / `SkillRegistryProtocol` 仅提供接口签名 + 一个返回固定 mock 数据的实现（用于 OrchestrationTests 注入）。**Phase 1 才实现真实 MCPClient（stdio / SSE）+ SkillRegistry（fs scan）**。M2 做这件事的目的是：让 Phase 1 实施者打开 Capabilities 目录，一眼能看到要做什么；让 ExecutionEngine 的 Agent / Pipeline 分支至少在编译期可参照接口（即便 M2 只展开 .prompt 分支）。

---

## 文件清单（File Structure）

| 类型 | 路径 | 责任 | Task |
|---|---|---|---|
| Modify | `SliceAIKit/Package.swift` | 移除 placeholder testTarget 行（如有），新增 OrchestrationTests / CapabilitiesTests 真正的 testTarget 依赖 | Task 1 |
| Delete | `SliceAIKit/Sources/Orchestration/Placeholder.swift` | M1 placeholder（M2 起 Orchestration 有真实代码后删除） | Task 1 |
| Delete | `SliceAIKit/Sources/Capabilities/Placeholder.swift` | 同上 | Task 12 |
| Delete | `SliceAIKit/Tests/OrchestrationTests/PlaceholderTests.swift` | M1 placeholder | Task 1 |
| Delete | `SliceAIKit/Tests/CapabilitiesTests/PlaceholderTests.swift` | 同上 | Task 12 |
| Keep | `SliceAIKit/Sources/Orchestration/README.md` | M1 留下；M2 内容更新（不改文件名） | Task 14 |
| Keep | `SliceAIKit/Sources/Capabilities/README.md` | 同上 | Task 14 |
| Create | `SliceAIKit/Sources/Orchestration/Events/ExecutionEvent.swift` | `ExecutionEvent` enum + `Sendable` | Task 1 |
| Create | `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift` | `InvocationReport` struct（含 declared/effective permissions diff） | Task 1 |
| Create | `SliceAIKit/Sources/Orchestration/Engine/ProviderResolver.swift` | `ProviderResolver` protocol + 默认实现 | Task 2 |
| Create | `SliceAIKit/Sources/Orchestration/Engine/ProviderResolutionError.swift` | provider lookup 错误 | Task 2 |
| Create | `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift` | `ExecutionEngine` actor + dispatch by `ToolKind` | Task 3 / 4 |
| Create | `SliceAIKit/Sources/Orchestration/Context/ContextCollector.swift` | 平铺并发 resolve | Task 5 |
| Create | `SliceAIKit/Sources/Orchestration/Context/ContextCollectorError.swift` | timeout / required-failed | Task 5 |
| Create | `SliceAIKit/Sources/Orchestration/Permissions/PermissionBrokerProtocol.swift` | broker 接口 + GrantScope / GrantSource | Task 6 |
| Create | `SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift` | 默认实现 + §3.9.2 下限硬编码 | Task 6 |
| Create | `SliceAIKit/Sources/Orchestration/Permissions/PermissionGrantStore.swift` | session/persistent grant 存储 | Task 6 |
| Create | `SliceAIKit/Sources/Orchestration/Permissions/EffectivePermissions.swift` | aggregated permissions struct（spec §3.9.6.5 骨架） | Task 7 |
| Create | `SliceAIKit/Sources/Orchestration/Permissions/PermissionGraph.swift` | `compute(tool:) -> EffectivePermissions` | Task 7 |
| Create | `SliceAIKit/Sources/Orchestration/Permissions/PermissionDecisionError.swift` | undeclared / denied / sandboxViolation / unknownProvider（**改名避开 SliceCore.PermissionError 冲突**——M1 SliceError.swift:141 已有 `PermissionError` = 系统权限错误命名空间） | Task 6 / 7 |
| Create | `SliceAIKit/Sources/Orchestration/Telemetry/CostAccounting.swift` | sqlite append + 查询 | Task 8 |
| Create | `SliceAIKit/Sources/Orchestration/Telemetry/CostRecord.swift` | 计费记录 struct | Task 8 |
| Create | `SliceAIKit/Sources/Orchestration/Telemetry/AuditLogProtocol.swift` | append-only 接口 | Task 9 |
| Create | `SliceAIKit/Sources/Orchestration/Telemetry/JSONLAuditLog.swift` | 默认实现 + 脱敏调用 | Task 9 |
| Create | `SliceAIKit/Sources/Orchestration/Output/OutputDispatcherProtocol.swift` | dispatch 接口 | Task 10 |
| Create | `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift` | 默认实现（仅 .window 分支） | Task 10 |
| Create | `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift` | 从 ToolExecutor 复制；消费 V2Tool/V2Provider | Task 11 |
| Create | `SliceAIKit/Sources/Orchestration/Internal/Redaction.swift` | `Redaction.scrub(_:)` + key regex | Task 9 |
| Create | `SliceAIKit/Sources/Capabilities/SecurityKit/PathSandbox.swift` | 路径规范化 + 白名单 + 硬禁止前缀 | Task 12 |
| Create | `SliceAIKit/Sources/Capabilities/SecurityKit/PathSandboxError.swift` | 硬禁止 / 越界错误 | Task 12 |
| Create | `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift` | MCP client 接口（stdio / SSE） | Task 13 |
| Create | `SliceAIKit/Sources/Capabilities/MCP/MockMCPClient.swift` | 测试桩 | Task 13 |
| Create | `SliceAIKit/Sources/Capabilities/Skills/SkillRegistryProtocol.swift` | skill 加载接口 | Task 13 |
| Create | `SliceAIKit/Sources/Capabilities/Skills/MockSkillRegistry.swift` | 测试桩 | Task 13 |
| Create | 14 个测试文件 + 3 个 Helpers | 见各 Task 内 | Task 1 – 13 |
| Create | `docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md` | 实施过程归档 | Task 0 + Task 14 |
| Modify | `docs/Task_history.md` | 追加 M2 索引行 | Task 0 + Task 14 |

---

## Task 0: 文档初始化（前置；项目规则要求）

> **必须在任何代码 Task 之前执行**——CLAUDE.md "1.2 文档创建时机"明确要求"每一个任务开始执行前，必须创建 docs/Task-detail/xxxxxx.md，并在 Task_history.md 中记录该任务的索引"。

**Files:**
- Create: `docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md`
- Modify: `docs/Task_history.md`（在最顶部 `## Task 33 · Phase 0 M1` 之前插入 `## Task 34 · Phase 0 M2`）

**步骤：**

- [ ] **Step 1：检查 Task 编号**

```bash
# 在主仓库根目录跑（worktree 内也可）
grep "^## Task " docs/Task_history.md | head -3
# 期望输出：Task 33 / Task 32 / Task 31（M1 PR #1 merge 后已索引到 Task 33）
# 下一个可用编号为 34；本 plan 用 Task 34（按"grep 取下一个可用值"原则，不硬编码——若实施时已被其他 commit 占用 34，按实际 +1 取号）
```

- [ ] **Step 2：创建 Task-detail 骨架文件**

写入 `docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md`：

```markdown
# Task 34 · Phase 0 M2 · Orchestration + Capabilities 骨架

> **状态**：实施中
> **plan**：`docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`
> **基线 commit**：`<填入开始实施时的 main HEAD>`
> **worktree**：`.worktrees/phase-0-m2/`
> **分支**：`feature/phase-0-m2-orchestration`

## 1. 任务背景

承接 M1（PR #1 已 merge 入 main，merge commit `5cdf0f7`）。M1 落地了 SliceCore 中的 19 个 V2* + 领域类型 + ConfigMigratorV1ToV2，但 Orchestration / Capabilities 仍是空 placeholder。M2 把这两个 target 填实，但**不接入 app 启动链路**——M3 才做切换。

## 2. 现有问题

无（M1 zero-touch 验证通过；M2 在新 target 中独立实现）。

## 3. 实施方案

见 plan `docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`。

## 4. ToDoList

按 plan 中 Task 1 – Task 14 顺序执行；每个 Task 内勾选项独立追踪。

## 5. 变动文件清单

待实施完成后填充。

## 6. 测试结果

待实施完成后填充。
```

- [ ] **Step 3：在 Task_history.md 顶部追加索引（Task 34）**

在第 7 行 `## Task 33 · Phase 0 M1 · 核心类型与配置迁移` 之前插入：

```markdown
## Task 34 · Phase 0 M2 · Orchestration + Capabilities 骨架

- **时间**：2026-04-25
- **描述**：把 v2.0 spec §3.4 / §3.9 描述的执行引擎 + 权限闭环 + 安全模型骨架落地为 `Orchestration` + `Capabilities` 两个 target 的可独立单测代码；**不接入 app 启动链路**（M3 才切）。10 个 spec 子任务（M2.1 ExecutionEngine / M2.2 ContextCollector / M2.3 PermissionBroker / M2.3a PermissionGraph / M2.4 CostAccounting / M2.5 AuditLog / M2.6 OutputDispatcher / M2.7 PromptExecutor / M2.8 PathSandbox / M2.9 MCP/Skill 接口）拆为 14 个 implementation Task
- **详情**：[docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md](Task-detail/2026-04-25-phase-0-m2-orchestration.md)
- **结果**：实施中

---
```

- [ ] **Step 4：Commit 文档骨架**

```bash
git add docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md docs/Task_history.md
git commit -m "$(cat <<'EOF'
docs(phase-0/m2): seed Task-detail + Task_history index

- Add docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md skeleton
- Index Task 34 in docs/Task_history.md

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 1: M2.1.a · ExecutionEvent + InvocationReport + Package wiring

> 把 spec §3.4 的 `ExecutionEvent` enum 与 `InvocationReport` struct 落地为 `Orchestration/Events/`；同时完成 Package.swift 的真实 testTarget 注册（删除 M1 留下的 PlaceholderTests）。
>
> **依赖关系**：本 Task 不消费 Capabilities 任何类型；Task 2 / 3 / 4 都依赖本 Task 输出的 `ExecutionEvent`。

**Files:**
- Modify: `SliceAIKit/Package.swift`（OrchestrationTests testTarget 加 Helpers / Events / Engine path 配置——但 swift package manager 默认会扫描 `Tests/OrchestrationTests/` 全目录，**实际不需要改 Package.swift 的 testTarget 路径**；只需要确认 `OrchestrationTests` 已声明 `dependencies: ["Orchestration", "SliceCore"]`）
- Delete: `SliceAIKit/Sources/Orchestration/Placeholder.swift`
- Delete: `SliceAIKit/Tests/OrchestrationTests/PlaceholderTests.swift`
- Create: `SliceAIKit/Sources/Orchestration/Events/ExecutionEvent.swift`
- Create: `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/ExecutionEventTests.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/InvocationReportTests.swift`

### 1.1 Step 1: 写第一个 failing test：ExecutionEvent.started 等价

```swift
// SliceAIKit/Tests/OrchestrationTests/ExecutionEventTests.swift
import XCTest
@testable import Orchestration

final class ExecutionEventTests: XCTestCase {
    func test_executionEvent_started_carriesInvocationId() {
        let id = UUID()
        let event = ExecutionEvent.started(invocationId: id)
        guard case .started(let extracted) = event else {
            XCTFail("expected .started case")
            return
        }
        XCTAssertEqual(extracted, id)
    }
}
```

- [ ] **Step 2: 跑测试，验证 fail**

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.ExecutionEventTests/test_executionEvent_started_carriesInvocationId
# 期望：编译失败 "no such module 'Orchestration'" 或 "type 'ExecutionEvent' has no member 'started'"
```

- [ ] **Step 3: 删除 M1 placeholder，写最小 ExecutionEvent**

先删除 placeholder：
```bash
rm SliceAIKit/Sources/Orchestration/Placeholder.swift
rm SliceAIKit/Tests/OrchestrationTests/PlaceholderTests.swift
```

再创建 `SliceAIKit/Sources/Orchestration/Events/ExecutionEvent.swift`：

```swift
import Foundation
import SliceCore

/// `ExecutionEngine.execute(...)` 流式产出的事件。
///
/// 每条事件都是不可变值类型；调用方按 `AsyncThrowingStream<ExecutionEvent, Error>`
/// 顺序消费。事件字段尽量 `Sendable` + 简单 struct，便于跨 actor 流转。
///
/// 注意：`promptRendered` 的 `preview` **必须**经过 `Redaction.scrub` 后再传入；
/// `toolCallProposed` / `toolCallResult` 中的字典也必须脱敏。脱敏责任在事件**生产者**
/// （PromptExecutor / AgentExecutor），事件本身不再做二次过滤。
public enum ExecutionEvent: Sendable {
    /// 主流程已启动；invocationId 用于关联 AuditLog / CostAccounting / 后续事件
    case started(invocationId: UUID)

    /// ContextCollector 解析出某个 ContextRequest 的结果（仅成功路径产出，
    /// 失败的请求统一在 `failed` 或最终 report.flags 里体现）
    case contextResolved(key: ContextKey, valueDescription: String)

    /// 渲染好的 prompt 预览（已截断 + 脱敏）；用于 Playground / DryRun
    case promptRendered(preview: String)

    /// LLM provider 流式输出片段
    case llmChunk(delta: String)

    /// Agent loop 提议调用 MCP tool（M2 仅声明，AgentExecutor 由 Phase 1 实现）
    case toolCallProposed(ref: MCPToolRef, argsDescription: String)

    /// PermissionBroker 同意 tool call
    case toolCallApproved(id: UUID)

    /// MCP tool 返回（脱敏后的简短摘要，避免污染日志）
    case toolCallResult(id: UUID, summary: String)

    /// Pipeline 进度（M2 仅声明，PipelineExecutor 由 Phase 5 实现）
    case stepCompleted(step: Int, total: Int)

    /// OutputBinding.sideEffects 的副作用已触发（含 inferredPermissions 已 gate 通过）
    case sideEffectTriggered(SideEffect)

    /// 主流程成功结束
    case finished(report: InvocationReport)

    /// 主流程失败（任何 step 错误统一收敛到此 case）
    case failed(SliceError)

    /// M2 范围 placeholder：还未实现的 PresentationMode / ToolKind 分支返回此事件
    case notImplemented(reason: String)

    /// **Round 2 B-2 修订**：dry-run 路径下 PermissionBroker.gate 返回 `.wouldRequireConsent` 时 yield；
    /// caller 收到此事件后跳过实际执行但**继续主流程**；用于 Playground UI 显示
    /// "如果实际执行会需要 X 权限"。**严禁** 与 `.approved` 混淆（Round 1 P1-1 修订防回归）
    case permissionWouldBeRequested(permission: Permission, uxHint: String)

    /// **Round 2 B-2 修订**：Step 7 dry-run 时替代 `.sideEffectTriggered` 的事件，
    /// 标记该 sideEffect 仅 gate 通过但**未实际执行**；不写 AuditLog（Task 9 audit 仅在真正执行时写）
    case sideEffectSkippedDryRun(SideEffect)
}
```

注意点：
1. `valueDescription` / `argsDescription` / `summary` 是 **String**——不是 `ContextValue` / `[String: Any]`——是为了让事件本身 Sendable 简单可序列化；具体 ContextValue 由 ResolvedExecutionContext 持有，事件只送描述给 UI。
2. `MCPToolRef` 来自 `SliceCore`（M1 已就绪）；`SliceError` 同。

- [ ] **Step 4: 跑测试验证 pass**

```bash
swift test --filter OrchestrationTests.ExecutionEventTests/test_executionEvent_started_carriesInvocationId
# 期望: PASS
```

- [ ] **Step 5: 写第二个 test：ExecutionEvent 多 case 模式匹配 + Sendable 验证**

追加到 `ExecutionEventTests.swift`：

```swift
func test_executionEvent_allCases_canBeBuilt() {
    let cases: [ExecutionEvent] = [
        .started(invocationId: UUID()),
        .contextResolved(key: ContextKey(rawValue: "selection"), valueDescription: "<82 chars>"),
        .promptRendered(preview: "Translate the following text to English: …"),
        .llmChunk(delta: "Hello"),
        .toolCallProposed(
            ref: MCPToolRef(server: "fs", tool: "read"),
            argsDescription: "{\"path\":\"~/Documents/foo.md\"}"
        ),
        .toolCallApproved(id: UUID()),
        .toolCallResult(id: UUID(), summary: "<file contents 1234 bytes>"),
        .stepCompleted(step: 1, total: 3),
        .sideEffectTriggered(.copyToClipboard),
        .finished(report: .stub()),
        .failed(.configuration(.validationFailed("test"))),
        .notImplemented(reason: "PresentationMode.bubble not in M2 scope")
    ]
    XCTAssertEqual(cases.count, 12)
}

func test_executionEvent_isSendable() {
    // 编译期检查：ExecutionEvent 必须 Sendable
    let event: any Sendable = ExecutionEvent.started(invocationId: UUID())
    _ = event
}
```

`InvocationReport.stub()` 是测试 helper，需要在 InvocationReport 实现里加 `#if DEBUG` 段（见下一步）。

- [ ] **Step 6: 写 InvocationReport struct + stub helper**

创建 `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`：

```swift
import Foundation
import SliceCore

/// 一次 `ExecutionEngine.execute(...)` 的完整审计快照——成功 / 失败 / 被拒都产出。
///
/// 由 `ExecutionEngine` 在 Step 9 写入 `AuditLog`；同时作为 `.finished(report:)` 事件
/// 的 payload 暴露给调用方。
///
/// **D-24 闭环字段**：`declaredPermissions` 与 `effectivePermissions` 的 diff
/// 用于审计实际访问与声明的偏差；即便 ⊆ 校验通过，diff 仍然记录。
public struct InvocationReport: Sendable, Equatable {
    /// 与 `.started(invocationId:)` 一致
    public let invocationId: UUID

    /// 触发的 V2Tool 标识（不存原 manifest，避免敏感字段进 AuditLog）
    public let toolId: String

    /// V2Tool.permissions 静态声明
    public let declaredPermissions: Set<Permission>

    /// 实际触发（PermissionGraph.compute 聚合后的并集）
    public let effectivePermissions: Set<Permission>

    /// effective - declared；非空时表示有"未声明的实际访问"，会触发 .permissionUndeclared flag
    public var undeclaredPermissions: Set<Permission> {
        effectivePermissions.subtracting(declaredPermissions)
    }

    /// 关键事件标记：unauthorized access / dry-run / partial-failure / ...
    public let flags: Set<InvocationFlag>

    /// 起止时间 + 总 token + 估算成本
    public let startedAt: Date
    public let finishedAt: Date
    public let totalTokens: Int
    public let estimatedCostUSD: Decimal

    /// **Round 2 B-1 修订**：执行结果（success / failed(errorKind:) / dryRunCompleted 三态）
    /// 让 AuditLog 查询能按 errorKind 过滤；finishFailure / finishSuccess helper 通过此字段区分
    public let outcome: InvocationOutcome

    public init(
        invocationId: UUID,
        toolId: String,
        declaredPermissions: Set<Permission>,
        effectivePermissions: Set<Permission>,
        flags: Set<InvocationFlag>,
        startedAt: Date,
        finishedAt: Date,
        totalTokens: Int,
        estimatedCostUSD: Decimal,
        outcome: InvocationOutcome
    ) {
        self.invocationId = invocationId
        self.toolId = toolId
        self.declaredPermissions = declaredPermissions
        self.effectivePermissions = effectivePermissions
        self.flags = flags
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.outcome = outcome
    }
}

public enum InvocationFlag: String, Sendable, Codable, Equatable {
    case dryRun
    case permissionUndeclared
    case partialFailure
    case sandboxViolation
}

/// **Round 2 B-1 修订**：InvocationReport 的 outcome 字段类型；
/// 区分成功 / 失败 / dry-run 完成三种终态。
///
/// `failed` case 携带 `errorKind: ErrorKind`——SliceError 四大类的简化映射，
/// 让 AuditLog 按错误类型聚合查询。**不**直接携带 SliceError 因为 SliceError 关联值
/// 多含敏感字符串、Codable / 脱敏复杂度高，errorKind 抽象层兼顾审计与隐私。
public enum InvocationOutcome: Sendable, Codable, Equatable {
    case success
    case failed(errorKind: ErrorKind)
    case dryRunCompleted

    /// 错误大类（与 SliceError 四大类对齐：selection / provider / configuration / permission）
    public enum ErrorKind: String, Sendable, Codable, Equatable {
        case selection
        case provider
        case configuration
        case permission
    }
}

#if DEBUG
extension InvocationReport {
    /// 单测 / Playground 用——固定 stub 值
    public static func stub(
        invocationId: UUID = UUID(),
        toolId: String = "test.tool",
        declared: Set<Permission> = [],
        effective: Set<Permission> = [],
        flags: Set<InvocationFlag> = [],
        outcome: InvocationOutcome = .success
    ) -> InvocationReport {
        InvocationReport(
            invocationId: invocationId,
            toolId: toolId,
            declaredPermissions: declared,
            effectivePermissions: effective,
            flags: flags,
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 1),
            totalTokens: 0,
            estimatedCostUSD: 0,
            outcome: outcome
        )
    }
}
#endif
```

- [ ] **Step 7: 跑两个测试都 pass**

```bash
swift test --filter OrchestrationTests.ExecutionEventTests
# 期望: 2 tests, all pass
```

- [ ] **Step 8: 写 InvocationReport 的独立测试**

`SliceAIKit/Tests/OrchestrationTests/InvocationReportTests.swift`：

```swift
import XCTest
import SliceCore
@testable import Orchestration

final class InvocationReportTests: XCTestCase {

    func test_undeclaredPermissions_returnsEmptySetWhenEffectiveIsSubsetOfDeclared() {
        let declared: Set<Permission> = [.fileRead(path: "~/Documents/**")]
        let effective: Set<Permission> = [.fileRead(path: "~/Documents/**")]
        let report = InvocationReport.stub(declared: declared, effective: effective)
        XCTAssertTrue(report.undeclaredPermissions.isEmpty)
    }

    func test_undeclaredPermissions_returnsDifferenceWhenEffectiveExceedsDeclared() {
        let declared: Set<Permission> = [.fileRead(path: "~/Documents/**")]
        let effective: Set<Permission> = [
            .fileRead(path: "~/Documents/**"),
            .fileWrite(path: "~/Library/Application Support/SliceAI/**")
        ]
        let report = InvocationReport.stub(declared: declared, effective: effective)
        XCTAssertEqual(
            report.undeclaredPermissions,
            [.fileWrite(path: "~/Library/Application Support/SliceAI/**")]
        )
    }

    func test_invocationFlag_codable_roundtrips() throws {
        let flag = InvocationFlag.permissionUndeclared
        let data = try JSONEncoder().encode(flag)
        let decoded = try JSONDecoder().decode(InvocationFlag.self, from: data)
        XCTAssertEqual(decoded, flag)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"permissionUndeclared\"")
    }
}
```

- [ ] **Step 9: 跑完整 OrchestrationTests，确认 5 tests pass**

```bash
swift test --filter OrchestrationTests
# 期望: 5 tests pass（ExecutionEventTests x 2 + InvocationReportTests x 3）
```

- [ ] **Step 10: 跑 swiftlint --strict，0 violations**

```bash
# 在主仓库根目录跑
swiftlint lint --strict --path SliceAIKit/Sources/Orchestration SliceAIKit/Tests/OrchestrationTests
# 期望: 0 violations / 0 serious
```

- [ ] **Step 11: Commit**

```bash
git add SliceAIKit/Sources/Orchestration SliceAIKit/Tests/OrchestrationTests
git commit -m "$(cat <<'EOF'
feat(orchestration): add ExecutionEvent + InvocationReport (M2.1.a)

- New: Orchestration/Events/ExecutionEvent.swift (12 cases incl. .notImplemented)
- New: Orchestration/Events/InvocationReport.swift + InvocationFlag
- Test: 5 tests cover started case, all-cases construct, Sendable bound,
        undeclared diff, flag codable round-trip
- Drop M1 PlaceholderTests + Placeholder.swift in Orchestration target

Refs spec §3.4 (ExecutionEvent) / §3.9.6.5 (declared vs effective permissions diff)

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: M2.1.b · ProviderResolver protocol + Mock 实现 + ProviderResolutionError

> ExecutionEngine 通过 ProviderResolver 把 `ProviderSelection`（fixed / capability / cascade）解析到具体 V2Provider。M2 实现：fixed 形态走 `V2Configuration.providers` 查找；capability / cascade 形态返回 `.notImplemented`（Phase 1 / Phase 5 才填实）。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Engine/ProviderResolver.swift`
- Create: `SliceAIKit/Sources/Orchestration/Engine/ProviderResolutionError.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockProvider.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/ProviderResolverTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点（先记录，避免后期偏离）：**
- `ProviderResolver` 是 protocol；默认实现 `DefaultProviderResolver` 接受 `() async throws -> V2Configuration` 闭包（不直接持有 V2ConfigurationStore，便于测试注入）
- `resolve(_ selection: ProviderSelection) async throws -> V2Provider` 签名
- `.fixed(providerId:, modelId:)` **（Round 2 B-6.1 修订：补 modelId 入参；M1 落地 `case fixed(providerId: String, modelId: String?)` SliceCore/ProviderSelection.swift:9 verified）** → 在 `current().providers` 按 providerId 找 V2Provider；找不到 throw `ProviderResolutionError.notFound(providerId)`；返回时若 selection 的 `modelId == nil`，回落 `provider.defaultModel`（V2Provider 字段，M1 已就绪）；ProviderResolver 不强制 modelId 必须在 `provider.modelIds` 列表内（v2 spec 允许用户跳出预设模型，由 PromptExecutor 调 LLM 时若 modelId 不被 provider 支持再报错）
- `.capability(requires:)` → throw `ProviderResolutionError.notImplemented(.capabilityRouting)` (Phase 1)
- `.cascade(rules:)` → throw `ProviderResolutionError.notImplemented(.cascadeRouting)` (Phase 5)
- `MockProvider` Helpers 提供 `MockProvider.openAIStub` / `.anthropicStub` 便于 Engine 测试注入

---

## Task 3: M2.1.c · ExecutionEngine actor 骨架 + execute 入口签名 + AsyncThrowingStream 框架

> 仅创建 actor + init 装配 + `execute(tool:seed:)` 返回流，**不实现**实际主流程逻辑——主流程逻辑在 Task 4 写。本 Task 完成时，调用 execute 立刻 yield `.notImplemented` + 单测能跑通。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`（先写 init + notImplemented 测试）
- Create: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockOutputDispatcher.swift`（最小 sink）
- Create: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockAuditLog.swift`（in-memory）
- Create: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockPermissionBroker.swift`（默认全放行）
- Create: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockContextCollector.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockMCPClient.swift`（与 Capabilities Mock 共用接口，但放 OrchestrationTests/Helpers 隔离 import）
- Create: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockSkillRegistry.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点：**
- `ExecutionEngine` 是 `actor`（满足 spec §3.4 + Swift 6 strict concurrency）
- init 接受 **8 个依赖**（与 spec §3.4 完全对齐）：`contextCollector` / `permissionBroker` / `providerResolver` / `mcpClient` / `skillRegistry` / `costAccounting` / `auditLog` / `output` —— M2 阶段全部接受 protocol，便于测试注入 Mock
- `execute(tool:seed:)` 返回 `AsyncThrowingStream<ExecutionEvent, Error>`；本 Task 内部只 yield `.started` + `.notImplemented` + `.finished(stub)` 三件事，让 ExecutionEngineTests 能验证流框架
- 主流程的 Step 2 / Step 2.5 / Step 3 / Step 4 / Step 5 在 Task 4 / 6 / 7 才接入

---

## Task 4: M2.1.d · ExecutionEngine 主流程 happy path（PermissionGraph + ContextCollector + PromptExecutor 接入）

> 把 Task 7（PermissionGraph）+ Task 5（ContextCollector）+ Task 11（PromptExecutor）拼成 ExecutionEngine.execute 的真实主流程，覆盖 spec §3.4 Step 1–10。本 Task 是 M2 最大的 task；预计 1.5 人天的核心。

**Files:**
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`（替换 Task 3 的占位 yield 为真实 step 编排）
- Modify: `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`（追加 4 条主路径测试）

**完整 TDD 步骤：待第二轮展开**

**关键设计点（Round 1 P1-2 修订 + Round 2 B-1 / B-2 / B-3 / B-5 修订）：**

- **统一审计**（Round 1 P1-2）：所有 `execute(...)` 路径（成功 / 失败 / 被拒 / not-implemented）至少产生**一条** `AuditEntry.invocationCompleted(InvocationReport)` 进 `AuditLog`（**Round 2 B-6.3 修订**：用 enum case 而非 raw report）。
- **finishFailure / finishSuccess helper**（**Round 2 B-1 修订**完整签名）：
  - `finishFailure(error: SliceError, invocationId: UUID, toolId: String, declared: Set<Permission>, effective: Set<Permission>, flags: Set<InvocationFlag>, startedAt: Date)`（**B-1 新增 startedAt 入参**——失败路径需要计算耗时）→ 构造 `InvocationReport(... outcome: .failed(errorKind: InvocationOutcome.ErrorKind.from(error)))` → `await auditLog.append(.invocationCompleted(report))` → `yield .failed(error)` → 流结束。**`ErrorKind.from(_:)` 是定义在 InvocationOutcome.ErrorKind 上的 static helper**（**Round 3 P2 修订**），签名 `static func from(_ error: SliceError) -> ErrorKind`，按 SliceError 顶层 case 映射：`.selection(_) → .selection` / `.provider(_) → .provider` / `.configuration(_) → .configuration` / `.permission(_) → .permission`（覆盖 SliceError 当前 4 个顶层 case，`SliceError` 加新 case 时此 helper 必须 exhaustive switch 强制更新——见 Task 14 grep `default:` 反向断言）。Helper 定义放在 Task 1 同文件 `Orchestration/Events/InvocationReport.swift` 里，作为 `extension InvocationOutcome.ErrorKind { ... }`
  - `finishSuccess(report: InvocationReport)` → `await auditLog.append(.invocationCompleted(report))` → `yield .finished(report)` → 流结束（report 由 caller 构造时 outcome = .success 或 .dryRunCompleted）
- 成功路径（spec §3.4 Step 1–10）：
  - Step 1：`yield .started(invocationId)`（`invocationId = UUID()` 在入口生成）；同时 `let startedAt = Date()`（后续 finishFailure / finishSuccess 都用此值）
  - Step 2：`do { let effective = try await permissionGraph.compute(tool: tool); if !effective.undeclared.isEmpty { finishFailure(error: .permission(.undeclared(missing: effective.undeclared)), ...); return } } catch PermissionDecisionError.unknownProvider(let id) { finishFailure(error: .configuration(.invalidTool(id)), ...); return }`（**Round 2 B-5 + Round 3 P2/P3 修订 + push back**：catch pattern 用 `catch <enum>.<case>(let payload)` 直接匹配；**严禁** `catch let e as ... where case ... = e`（Swift 不支持 `where + case` 联用）；类型名用独立 `PermissionDecisionError` 避开 M1 SliceCore.PermissionError 命名冲突——见 Task 6 / 7 Files 段说明）
  - Step 2.5：`let outcome = await permissionBroker.gate(effective.union, provenance: tool.provenance, scope: .session, isDryRun: seed.isDryRun)`；**实现必须用无 `default` 的 `switch outcome`** 覆盖全 4 case（**Round 2 B-3 修订**——确保未来加 case 时编译器报错而非静默漏处理）：
    - `.approved` → 继续 Step 3
    - `.denied(reason:)` → `finishFailure(.permission(.denied(reason:)))`
    - `.requiresUserConsent(uxHint:)` → `finishFailure(.permission(.notGranted))`（M2 测试中 MockPermissionBroker 直接 `.approved` / `.wouldRequireConsent`，无真实 UI 触发）
    - `.wouldRequireConsent(uxHint:)` → **Round 2 B-2 修订**：`yield .permissionWouldBeRequested(permission: ..., uxHint: ...)` 一条事件后**继续 Step 3**（dry-run 是合法终态，不 finishFailure）；后续 Step 9 finishSuccess 时 `outcome = .dryRunCompleted` + flags 含 `.dryRun`
  - Step 3：`let resolved = try await contextCollector.resolve(seed: seed, requests: tool.kind.contexts)` → 必填失败 throw → catch → `finishFailure(.context(.required(key:underlying:)))`
  - Step 4：`let provider = try await providerResolver.resolve(tool.kind.provider)` → 失败 → `finishFailure(.provider(.notFound(id:)))`
  - Step 5：`switch tool.kind { case .prompt: ...; case .agent, .pipeline: yield .notImplemented(...) ; finishSuccess(stub with outcome: .success) }`（M2 仅展开 `.prompt` 真实路径；M2.5 / M2.7 的 PromptExecutor 在 Step 6 调用）
  - Step 6：`for try await chunk in promptExecutor.run(tool, resolved, provider) { yield .llmChunk(delta: chunk); await output.handle(chunk: chunk, mode: tool.displayMode, invocationId: invocationId) }`（**Round 1 P2-3 修订**：传 `tool.displayMode` 不传 `tool.outputBinding?.primary`）
  - Step 7（**Round 2 B-2 修订**）：`for sideEffect in tool.outputBinding?.sideEffects ?? [] { let g = await permissionBroker.gate(Set(sideEffect.inferredPermissions), provenance: tool.provenance, scope: .session, isDryRun: seed.isDryRun); switch g { case .approved: if seed.isDryRun { yield .sideEffectSkippedDryRun(sideEffect) } else { /* execute - Phase 1 才填 */; yield .sideEffectTriggered(sideEffect); await auditLog.append(.sideEffectTriggered(invocationId:, sideEffect:, executedAt: Date())) } case .denied: continue（拒绝某副作用不影响其他副作用，记 partialFailure flag）; case .requiresUserConsent: continue（M2 不弹 UI）; case .wouldRequireConsent: yield .sideEffectSkippedDryRun(sideEffect)（dry-run 时此态等价于 .approved + skip 执行，不再额外 yield permissionWouldBeRequested）}`
  - Step 8：`await costAccounting.record(...)`
  - Step 9：构造 `InvocationReport(... outcome: seed.isDryRun ? .dryRunCompleted : .success, flags: ..., startedAt: startedAt, finishedAt: Date())` → `finishSuccess(report)`
- **失败路径全部走 finishFailure helper**——保证 audit 永远记录；report.outcome.errorKind 提供错误大类便于查询（**Round 2 B-1 修订**）
- 测试矩阵覆盖 5 条 prompt-kind 路径，**全部断言 `mockAuditLog.entries.count == 1` 且 entry case == `.invocationCompleted(_)`**（**Round 2 B-6.3 修订**）：
  - **happy**: 全 mock 放行 → 流式 yield delta → finished(report)；audit 1 条 `.invocationCompleted` with outcome `.success`
  - **context-fail**: required ContextRequest 失败 → audit 1 条 `.invocationCompleted` with outcome `.failed(.context)` → yield `.failed`
  - **permission-deny**: PermissionBroker.gate 拒绝 → audit 1 条 `.invocationCompleted` with outcome `.failed(.permission)` → yield `.failed`
  - **permission-undeclared**: PermissionGraph 检测到 effective ⊄ declared → audit 1 条 `.invocationCompleted` with outcome `.failed(.permission)` → yield `.failed`
  - **dry-run（Round 2 B-2 修订）**: seed.isDryRun=true → Step 2.5 若 .wouldRequireConsent yield `.permissionWouldBeRequested`；Step 7 副作用全 yield `.sideEffectSkippedDryRun`；audit 1 条 `.invocationCompleted` with outcome `.dryRunCompleted` + flags `.dryRun`；额外断言 stream 中**不**包含 `.sideEffectTriggered` 事件（dry-run 时只能 skipped）
  - **non-dry-run + .requiresUserConsent 对照（Round 3 P3 新增）**: seed.isDryRun=**false** + MockPermissionBroker 在 Step 2.5 返回 `.requiresUserConsent` → finishFailure(.permission(.notGranted)) → audit 1 条 `.invocationCompleted` with outcome `.failed(errorKind: .permission)` → yield `.failed`；与 dry-run 路径形成对照，**证明 caller 能区分两种 consent 信号**（`.requiresUserConsent` = 实际执行前的"用户拒绝"等价信号 vs `.wouldRequireConsent` = dry-run 期间的"如果实际执行需要确认"提示信号），避免误读
- 每个测试用 OrchestrationTests/Helpers 注入完整 Mock 套件（MockPermissionBroker / MockContextCollector / MockOutputDispatcher / MockAuditLog / MockProvider 等）

---

## Task 5: M2.2 · ContextCollector 平铺并发实现

> 实现 spec §3.3.3 + §3.4 Step 3 的 ContextCollector：用 `withTaskGroup` 平铺并发拉取所有 ContextRequest，必填失败立刻 throw、可选失败进 failures 列表。**严禁 DAG**（D-17）。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Context/ContextCollector.swift`
- Create: `SliceAIKit/Sources/Orchestration/Context/ContextCollectorError.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockContextProvider.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/ContextCollectorTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点：**
- `ContextCollector(providers: [String: any ContextProvider])` 按 `ContextRequest.provider` 字符串路由（**Round 3 P1 修订**：M1 `SliceCore/Context.swift:11` 字段名是 `provider: String`，**不是** `providerId`；plan 中所有 `request.providerId` 引用全部修正为 `request.provider`）
- `resolve(seed: ExecutionSeed, requests: [ContextRequest]) async throws -> ResolvedExecutionContext`
- 每个 request 有独立的 `timeout: Duration`（默认 5s，由 request 自己声明）
- 必填 `Requiredness.required` 失败 → throw `ContextCollectorError.requiredFailed(key: ContextKey, underlying: SliceError)`（**Round 2 B-6.2 修订**：参数类型 `ContextKey` / `SliceError` 与 M1 落地的 `ResolvedExecutionContext.failures` 类型完全对齐——SliceCore/ResolvedExecutionContext.swift:24 verified）
- 可选 `Requiredness.optional` 失败 → 进 `ResolvedExecutionContext.failures: [ContextKey: SliceError]`（**Round 2 B-6.2 修订**：从 `[String: Error]` 改为 M1 实际类型），主流程继续
- 非 SliceError 的底层错误（URLError / IO / Foundation 错误）由 ContextCollector 在 catch 里包装为 `SliceError.context(...)` 后再写入 failures（保持类型边界干净，调用方无需判别 underlying error 类型）
- 测试矩阵：5 个 mock provider 并发跑、其中 1 个 required 失败 vs 1 个 optional 失败、timeout 触发；optional 失败用例显式断言 `failures[key]` 是 `SliceError` 而非裸 `Error`（编译期就由 `[ContextKey: SliceError]` 类型保证，但仍在测试里 `XCTAssertNotNil(failures[key])` + 模式匹配检查 case）
- ContextProvider 默认实现已在 SliceCore (M1)；此处只编 Collector

---

## Task 6: M2.3 · PermissionBroker 接口 + 默认实现 + §3.9.2 下限硬编码

> 实现 spec §3.9.2 的能力下限矩阵 + §3.9.1 Provenance UX hint 合并；M2 默认实现走 in-memory grant store，gate 默认按下限要求确认（测试用 MockPermissionBroker 全放行）。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBrokerProtocol.swift`
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift`
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionGrantStore.swift`
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionDecisionError.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/PermissionBrokerTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点（Round 1 P1-1 + P2-1 修订）：**

- `PermissionBrokerProtocol.gate(effective: Set<Permission>, provenance: Provenance, scope: GrantScope, isDryRun: Bool) async throws -> GateOutcome`
- `GateOutcome` 现为 **4 态**：
  - `.approved`：通过（已有 grant 或 tier 不需要确认）
  - `.denied(reason: String)`：拒绝（用户曾经显式拒绝过 / 黑名单等）
  - `.requiresUserConsent(uxHint: ConsentUXHint)`：需要弹 UI 确认（M2 测试中 MockPermissionBroker 不会返回此态；生产路径 M3 才接 UI）
  - `.wouldRequireConsent(uxHint: ConsentUXHint)` **（Round 1 P1-1 新增）**：dry-run 路径下，本应弹确认的 permission——给 Playground UI 显示"如果实际执行需要 X / Y / Z 权限"用，**不静默 .approved**；caller 应识别此态后跳过实际副作用执行但继续主流程
- 下限决策：把 Permission 映射到 5 个 tier（readonly-local / readonly-network / local-write / network-write / exec），每个 tier 对应 lowerBound policy；**lowerBound 仅依赖 tier，与 provenance 完全无关**（spec §3.9.2 关键性质，D-22）
- **dry-run 不豁免下限（Round 1 P1-1 修订）**：spec §3.9.2 明确"下限只依赖 tier"，dry-run 仅由 ExecutionEngine Step 7 跳过副作用**实际执行**（P1-2 Step 7 修订对齐），broker 入口必须正常计算 gate：
  - 对 readonly-local / readonly-network / local-write 的 permission（context resolution / LLM 路径所需）：**仍走完整 gate 流程**，dry-run 不允许跳
  - 对 network-write / exec 的 permission（仅来自 sideEffect，dry-run 跳过执行）：返回 `.wouldRequireConsent(uxHint:)` 让 Playground 提示，**严禁返回 .approved 静默放行**
- **§3.9.2 全表测试矩阵 5 tier × 4 provenance = 20 cell 全覆盖（不抽样）（Round 1 P2-1 修订）**——测试代码最低断言数下限：
  - **D-22 子集**：所有 4 provenance 对 network-write / exec **每次**都返回 `.requiresUserConsent` 或 `.wouldRequireConsent`（共 8 cell），firstParty 也不例外
  - **D-25 子集**：firstParty 对 readonly-network / local-write **首次**也返回 `.requiresUserConsent`（共 2 cell）—— 不允许跳过首次确认
  - **readonly-local 子集**：所有 4 provenance 默认 `.approved`（无 grant 也通过）（共 4 cell）
  - **其余 6 cell**：non-firstParty provenance × non-readonly-local tier 的组合按 spec §3.9.1 表显式断言 UX hint 文案差异
- `PermissionGrantStore` 是 actor；M2 仅 in-memory 实现，session-scoped grant 持久化到 Phase 1 才做

---

## Task 7: M2.3a · EffectivePermissions + PermissionGraph.compute（D-24 静态闭环）

> 实现 spec §3.9.6.5 的 PermissionGraph：聚合 tool.contexts / outputBinding.sideEffects / kind.agent.mcpAllowlist / kind.agent.builtinCapabilities 的 inferredPermissions，与 tool.permissions 做 ⊆ 校验。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Permissions/EffectivePermissions.swift`
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionGraph.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionDecisionError.swift`（追加 `.unknownProvider(id: String)` case；Task 6 已建该文件含 `.undeclared(missing: Set<Permission>) / .denied / .sandboxViolation`；**Round 3 P2 修订 + push back**：使用独立 `PermissionDecisionError` 而非 SliceCore `PermissionError`——M1 `SliceError.swift:141` 已定义 `public enum PermissionError`（系统权限错误如 `accessibilityDenied / inputMonitoringDenied`），与 v2 工具权限决策错误语义不同；同名跨模块会让代码读者混淆，改名解决）
- Create: `SliceAIKit/Tests/OrchestrationTests/PermissionGraphTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点（Round 1 P2-2 修订：注入 ContextProviderRegistry + 补 pipeline 测试 + unknownProvider 错误）：**

- 完全照抄 spec §3.9.6.5 的 `EffectivePermissions` struct（fromContexts / fromSideEffects / fromMCP / fromBuiltins / declared / union / undeclared computed）
- `PermissionGraph(providerRegistry: ContextProviderRegistry)` 构造期注入注册表 **（Round 1 P2-2 新增）**——`ContextProviderRegistry` 是 SliceCore 中 M1 已就绪的 `[String: any ContextProvider.Type]` 简单封装；**严禁** PermissionGraph 内部硬编码 provider 名字字符串
- `compute(tool: V2Tool) async throws -> EffectivePermissions`（actor 上的 async 方法但**不做 I/O**）：
  - 对每个 `ContextRequest` 通过 registry 按 `request.provider` 字符串查 provider type（**Round 3 P1 修订**：M1 字段名 `provider`，SliceCore/Context.swift:11 verified）；找不到 → `throw PermissionDecisionError.unknownProvider(id: request.provider)`（**Round 3 P2 修订 + push back**：使用独立 `PermissionDecisionError` 而非 SliceCore.PermissionError——后者已被 M1 SliceError.swift:141 占用为系统权限错误命名空间；`.unknownProvider(id:)` 作为 `PermissionDecisionError` 新 case 与 `.undeclared / .denied / .sandboxViolation` 同源，见本 Task Files 段 `PermissionDecisionError.swift Modify` 项追加此 case）
  - 找到 → 调静态方法 `providerType.inferredPermissions(for: request.args)` 取 permissions 进 `fromContexts`
  - 对每个 `SideEffect` 调 `.inferredPermissions` 进 `fromSideEffects`
  - 对 `tool.kind.agent.mcpAllowlist` 展开为 `[.mcp(server:tools:)]` 进 `fromMCP`
  - 对 `tool.kind.agent.builtinCapabilities` 映射为 `.shellExec(commands:)` 等进 `fromBuiltins`
  - 对 `tool.kind.pipeline.steps` 递归聚合每个 step（**Round 1 P2-2 新增**：pipeline step 含 inline `.mcp` / inline prompt with contexts 时同样累积到对应 from* set）
- 测试矩阵（**Round 1 P2-2 修订**：补 pipeline 与 unknownProvider）：
  - prompt 工具 + contexts 含 `file.read` 但 tool.permissions 缺 `.fileRead` → undeclared 非空
  - prompt 工具 + sideEffects 含 `appendToFile` 但 tool.permissions 缺 `.fileWrite` → undeclared 非空
  - agent 工具 + mcpAllowlist 含 `["fs.read"]` 但 tool.permissions 缺 `.mcp(server:"fs", tools:["fs.read"])` → undeclared 非空
  - agent 工具 + builtinCapabilities 含 `.shellExec(["git status"])` 但 tool.permissions 缺 `.shellExec(commands:)` → undeclared 非空
  - **pipeline 工具 + step 含 inline `.callMCP(ref:)` sideEffect 但 tool.permissions 缺 `.mcp(...)` → undeclared 非空**（P2-2 新增）
  - **pipeline 工具 + step 含 inline prompt with contexts 引用 `file.read` 但 tool.permissions 缺 `.fileRead` → undeclared 非空**（P2-2 新增）
  - **registry 缺 provider id**（tool.contexts 引用 "nonexistent.foo"，registry 没注册）→ throw `PermissionDecisionError.unknownProvider(id: "nonexistent.foo")`（P2-2 新增；**Round 3 P2 修订 + push back**：错误类型用独立 `PermissionDecisionError` 避开 M1 SliceCore.PermissionError 命名冲突）
  - 全部声明覆盖（prompt / agent / pipeline 各跑一次） → undeclared 空
  - empty tool（无 contexts / sideEffects / mcp / builtin） → effective.union 空集
- ExecutionEngine 在 Step 2 调 `try await permissionGraph.compute(tool: tool)` **（Round 2 B-5 修订：`try await` 不可缺，否则 async throws 编译错误）**；如 `effective.undeclared` 非空 → 走 `finishFailure(.permission(.undeclared(missing: ...)))`（与 Task 4 P1-2 修订对齐），**不进 Step 3**；如 throw `PermissionDecisionError.unknownProvider(let id)` → 走 `finishFailure(.configuration(.invalidTool(id)))`（**Round 3 P2/P3 修订 + push back**：caller 用 Swift catch pattern `catch PermissionDecisionError.unknownProvider(let id) { ... }` 直接匹配 case 关联值；**不**写 `catch let e as ... where case ... = e`（Swift 不支持 `where + case` 联用）；类型名用独立 `PermissionDecisionError` 避开 SliceCore.PermissionError 命名冲突）

---

## Task 8: M2.4 · CostAccounting actor + sqlite append + 查询

> 落地 spec §4.4.2 / §4.5.2 隐含的"每次 invocation 写一条 cost record"机制；用 sqlite3 C API（Swift 标准做法）做 append。M2 仅 schema + 写入 + 简单按 toolId 查询；可视化 / Cost Panel 是 Phase 3。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Telemetry/CostAccounting.swift`
- Create: `SliceAIKit/Sources/Orchestration/Telemetry/CostRecord.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/CostAccountingTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点：**
- `CostAccounting` 是 `actor`；构造时接受 `dbURL: URL`（测试用 `URL(fileURLWithPath: "/tmp/sliceai-cost-test-\(UUID()).db")`）
- 启动时建 schema：`CREATE TABLE IF NOT EXISTS cost_records (invocation_id TEXT PRIMARY KEY, tool_id TEXT, provider_id TEXT, model TEXT, input_tokens INTEGER, output_tokens INTEGER, usd REAL, recorded_at INTEGER)`
- API：`record(_ record: CostRecord) async throws` / `findByToolId(_ toolId: String) async throws -> [CostRecord]` / `totalUSD(since: Date) async throws -> Decimal`
- 测试用临时 db 文件，每个 test 用 `tearDown` 删除
- M2 范围内 sqlite 错误统一抛 `SliceError.configuration(.validationFailed(...))`（M2 不为 sqlite 单独建 error case；M3 / Phase 1 再细化）

---

## Task 9: M2.5 · AuditLogProtocol + JSONLAuditLog actor + 脱敏 + logCleared 事件

> 落地 spec §3.9.5 + §3.9.7 的审计要求：append-only jsonl + 自动脱敏 + 清空动作本身写一条 logCleared 事件。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Telemetry/AuditLogProtocol.swift`
- Create: `SliceAIKit/Sources/Orchestration/Telemetry/JSONLAuditLog.swift`
- Create: `SliceAIKit/Sources/Orchestration/Internal/Redaction.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/JSONLAuditLogTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点（Round 2 B-6.3 修订：AuditEntry 改为 enum 与 Task 4 接口对齐）：**

- `AuditLogProtocol`：`append(_ entry: AuditEntry) async throws` / `clear() async throws`（清空写 `.logCleared(at:)` 作为新文件第一条）/ `read(limit: Int) async throws -> [AuditEntry]`
- **`AuditEntry` 是 enum（Round 2 B-6.3 修订）**，三 case 与 Task 4 调用对齐：
  - `case invocationCompleted(InvocationReport)` —— 成功 / 失败 / dry-run 完成都用此 case；区分由 `report.outcome`（`.success` / `.failed(errorKind:)` / `.dryRunCompleted`）；Task 4 finishFailure / finishSuccess 都通过此 case 写入；这是绝大多数 audit 写入的 case
  - `case sideEffectTriggered(invocationId: UUID, sideEffect: SideEffect, executedAt: Date)` —— 每个**实际执行**的副作用单独 1 条 entry（dry-run 时 ExecutionEngine yield `ExecutionEvent.sideEffectSkippedDryRun` 但**不**写 audit；Round 2 B-2 修订对齐）
  - `case logCleared(at: Date)` —— `clear()` 调用时新文件第一条
- `AuditEntry: Codable` 用单键 discriminator 模板（与 SliceCore 的 ToolKind / Permission 等同款手写 Codable，避免 `_0` 泄漏；模板参考 M1 plan §"Canonical JSON Schema"）
- `Redaction.scrub(_ s: String) -> String`：API key / token / cookie / authorization 等正则匹配 → `<redacted>`；超过 200 字符截断
- **scrub 在 `append(_:)` 入口统一调用**（C-8 + Round 2 B-6.3）：先按 entry case 模式匹配遍历所有 String payload（如 InvocationReport.toolId / SideEffect 关联值里的 String 字段）做 scrub；不依赖生产者主动调用——避免遗漏
- selection 原文**永不**入 jsonl：InvocationReport struct 不带 selectionText 字段（schema 层就不允许）；只通过 `ExecutionSeed.selection` 在内存里持有，audit 层接触不到
- 测试矩阵：
  - 1000 条 `.invocationCompleted` 顺序 append + read（FIFO 验证：read 顺序 == append 顺序）
  - **AuditEntry 三 case 全 round-trip（Round 2 B-6.3 新增）**：构造 `.invocationCompleted(.stub(outcome: .success))` / `.invocationCompleted(.stub(outcome: .failed(errorKind: .permission)))` / `.invocationCompleted(.stub(outcome: .dryRunCompleted))` / `.sideEffectTriggered(invocationId: UUID(), sideEffect: .copyToClipboard, executedAt: Date())` / `.logCleared(at: Date())`，全部 encode → write → read → decode 等价（含 ISO8601 Date 编解码）
  - 触发 `Redaction.scrub`：构造 entry 含 `toolId = "tool-Bearer-sk-1234567890abcdef"` 类似的 mock API key string → 落盘文件 `XCTAssertFalse(fileContent.contains("sk-1234567890abcdef"))`
  - `clear()` 清空文件后第一条是 `.logCleared(at:)` 事件
  - **schema 防泄漏 sanity check**：构造 `InvocationReport.stub(toolId: "test")` 后 append → 通过 `Mirror(reflecting: report).children` 反射断言无 `selectionText` / `selection_text` / `original_text` 等字段名，作为 schema 层防回归

---

## Task 10: M2.6 · OutputDispatcherProtocol + 默认实现（仅 .window 分支）

> 落地 spec §3.3.6 + §3.4 Step 6/7 的 OutputDispatcher：**根据 `V2Tool.displayMode` 派发**到对应 sink（**Round 1 P2-3 修订**——M1 plan R-B / commit `d141c05` 已锁定 `displayMode` 是 primary truth、`outputBinding.primary` 仅作 V2Tool decoder/validate 的一致性校验冗余字段；ExecutionEngine 与 OutputDispatcher **都不读 outputBinding.primary**）。M2 只实现 `.window` 分支（落到 in-memory MockWindowSink），其余 5 个 PresentationMode 直接返回 `.notImplemented`。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Output/OutputDispatcherProtocol.swift`
- Create: `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/OutputDispatcherTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点（Round 1 P2-3 修订）：**

- `OutputDispatcherProtocol.handle(chunk: String, mode: PresentationMode, invocationId: UUID) async throws -> DispatchOutcome`
- ExecutionEngine 调用时**始终**传 `tool.displayMode`，**严禁**传 `tool.outputBinding?.primary`（**Round 1 P2-3 修订**——遵循 M1 plan R-B 锁定的"displayMode 是 primary truth"决议；`outputBinding.primary` 在 V2Tool decoder 处已与 displayMode 校验过一致性，运行时只读 displayMode）
- `DispatchOutcome = .delivered | .notImplemented(reason: String)`
- `.window` 分支：把 chunk 投递到 `WindowSinkProtocol`（M2 测试用 `InMemoryWindowSink` 收集，生产路径 M3 才接入 ResultPanel）
- `.bubble` / `.replace` / `.file` / `.silent` / `.structured` 一律返回 `.notImplemented(reason: "...")`，让 ExecutionEngine 把这条事件转发为 `.notImplemented` ExecutionEvent
- **OutputBinding.sideEffects 处理路径**：仍由 ExecutionEngine Step 7 直接读 `tool.outputBinding?.sideEffects`，与 `tool.displayMode` **完全解耦**——sideEffect 与 displayMode 是正交维度，不依赖 outputBinding.primary 这个冗余字段
- 测试矩阵：
  - **`.window` 模式 chunk 顺序与计数（Round 2 B-4 修订）**：driver 推 3 个 chunk `["a", "b", "c"]` → 断言 `InMemoryWindowSink.received == ["a", "b", "c"]`（数量 3 + 顺序一致；用 Array == 而非 Set 比较）
  - **非 .window 模式只 yield 一次 .notImplemented ExecutionEvent（Round 2 B-4 修订）**：守卫变量 `var notImplementedYielded = false` **必须是 ExecutionEngine.execute(tool:seed:) 函数内的 local var**（**Round 3 P2 修订**：严禁做成 actor field——actor 实例跨 invocation 复用时会污染状态，第二次调用 execute 时第一个 chunk 不再 yield .notImplemented）；driver 推 5 chunks 给 `.bubble` 模式 → OutputDispatcher 被调用 5 次（每次都返回 `.notImplemented`），但 ExecutionEvent stream 只含 1 条 `.notImplemented`；断言 `events.filter { if case .notImplemented = $0 { true } else { false } }.count == 1`；测试矩阵补一条**跨 invocation 隔离验证**：用同一个 ExecutionEngine 实例连续 execute 两次（都是 .bubble 模式 + 各 3 chunks），每次 stream 独立产出 1 条 `.notImplemented`，验证 local var 不跨 invocation 污染
  - **OutputDispatcher 调用次数验证（Round 2 B-4 修订）**：MockOutputDispatcher 用 actor 计数 `var handleCallCount = 0`；上面"非 .window 5 chunks"用例同时断言 `await mockOutput.handleCallCount == 5`（验证非 .window 模式仍逐 chunk 调用，只是不重复 yield 事件）
  - 构造 V2Tool 让 `displayMode != outputBinding.primary`（理论上 V2Tool decoder 会拒绝，但单测可绕过 decoder 直接构造）→ OutputDispatcher 仍按 displayMode 派发，验证不会读 outputBinding.primary

---

## Task 11: M2.7 · PromptExecutor（从 ToolExecutor 复制 + 改 V2 类型）

> 把现有 `SliceAIKit/Sources/SliceCore/ToolExecutor.swift` 的 prompt 渲染 + 取 API Key + 调 LLMProvider 流式逻辑**复制**到 `Orchestration/Executors/PromptExecutor.swift`，所有类型改为 V2*。**ToolExecutor.swift 不动**。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/PromptExecutorTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点：**
- `PromptExecutor` 是 `actor`；接受 `keychain: any KeychainAccessing` / `llmProvider: any LLMProvider`（M2 用 mock）
- `run(tool: V2Tool, resolved: ResolvedExecutionContext, provider: V2Provider) -> AsyncThrowingStream<String, Error>`
- 接受 `V2Tool.kind == .prompt` 形态；其他 kind throw `assertionFailure`（防御性，调用方应在 ExecutionEngine Step 5 dispatch 前过滤）
- 渲染 prompt 时使用 V2Tool.kind 关联值里的 `PromptTool.systemPrompt` / `userPrompt`，**不**走 v1 扁平字段
- 复制 ToolExecutor 的 mustache 渲染逻辑（如 spec §3.3.1 / §3.7 涉及）
- 测试用 MockLLMProvider 验证流式输出 + API key 取 + retry-after

---

## Task 12: M2.8 · PathSandbox（路径规范化 + 白名单 + 硬禁止）

> 落地 spec §3.9.3 的路径策略；放在 Capabilities 而非 Orchestration（因为 SecurityKit 是跨执行引擎的基础设施）。M2 实现纯静态 API，Phase 1 / 2 才接入 ContextCollector / OutputDispatcher 真实路径输入。

**Files:**
- Create: `SliceAIKit/Sources/Capabilities/SecurityKit/PathSandbox.swift`
- Create: `SliceAIKit/Sources/Capabilities/SecurityKit/PathSandboxError.swift`
- Delete: `SliceAIKit/Sources/Capabilities/Placeholder.swift`
- Delete: `SliceAIKit/Tests/CapabilitiesTests/PlaceholderTests.swift`
- Create: `SliceAIKit/Tests/CapabilitiesTests/PathSandboxTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点（Round 2 B-6.4 修订：Foundation API 真实语义对齐）：**

- `PathSandbox.normalize(_ raw: String, role: AccessRole) throws -> URL`：实现链 `URL(fileURLWithPath: raw).resolvingSymlinksInPath().standardizedFileURL`（**Round 2 B-6.4 修订**：spec §3.9.3:989 措辞 "URL(fileURLWithPath:).standardizedFileURL 消除 .. / symlink" 与 Foundation API 实际行为不符——`standardizedFileURL` **只**消除 `..` 与重复 `/`，**不** resolve symlink；必须先 `resolvingSymlinksInPath()` 后 `standardizedFileURL`，顺序不可换。spec 修订留下一轮 spec 评审）
- 默认白名单：`~/Documents` `~/Desktop` `~/Downloads` `~/Library/Application Support/SliceAI/**`
- 硬禁止前缀（永远拒绝，无视用户配置）：`~/Library/Keychains/**` `~/.ssh/**` `~/Library/Cookies/**` `/etc/**` `/var/db/**` `/Library/Keychains/**`
- 用户附加白名单 = `[String]`，构造时注入；M2 仅静态默认值（用户配置加白名单是 Phase 1 Settings UX）
- `AccessRole` enum：`.read` / `.write`（write 只允许 `~/Library/Application Support/SliceAI/**` + 用户附加）
- 测试矩阵（**Round 2 B-6.4 补 symlink 攻击用例**）：
  - `..` traversal: `~/Documents/../Library/Keychains/foo` → throw `.escapesWhitelist`
  - **symlink 攻击（Round 2 B-6.4 新增）**：测试用 `FileManager.default.createSymbolicLink(at:withDestinationURL:)` 在临时白名单目录（如 `~/Documents/test-sandbox-\(UUID()).link`）下建一个指向硬禁止前缀（如 `~/Library/Keychains`）的 symlink → `normalize(...)` 应 throw `.escapesWhitelist`（因为 `resolvingSymlinksInPath()` 会展开 symlink 后变成硬禁止前缀，被 prefix 检查拦下）；测试 tearDown 删除 symlink
  - **symlink resolved 顺序 sanity（Round 2 B-6.4 新增）**：构造一个 symlink 指向白名单内合法路径 → `normalize(...)` 应返回展开后的真实路径而非 symlink 路径本身（验证 resolvingSymlinksInPath 真生效）
  - 硬禁止前缀直接拒绝（即便加进 user allowlist 也拒绝）

---

## Task 13: M2.9 · MCPClientProtocol + SkillRegistryProtocol + Mock 实现

> 仅落接口签名 + Mock 实现，让 OrchestrationTests 可以注入。**Phase 1 才实现真实 MCPClient（stdio/SSE）+ SkillRegistry（fs scan）**。

**Files:**
- Create: `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- Create: `SliceAIKit/Sources/Capabilities/MCP/MockMCPClient.swift`
- Create: `SliceAIKit/Sources/Capabilities/Skills/SkillRegistryProtocol.swift`
- Create: `SliceAIKit/Sources/Capabilities/Skills/MockSkillRegistry.swift`
- Create: `SliceAIKit/Tests/CapabilitiesTests/MCPClientProtocolTests.swift`
- Create: `SliceAIKit/Tests/CapabilitiesTests/SkillRegistryProtocolTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点（Round 3 P2 修订：MCPCallResult 类型在本 Task 落地，M1 SliceCore 未定义 verified）：**

- `MCPClientProtocol.tools(for descriptor: MCPDescriptor) async throws -> [MCPToolRef]` / `.call(ref: MCPToolRef, args: [String: String]) async throws -> MCPCallResult`
- **`MCPCallResult` 是新增类型，定义在 `Capabilities/MCP/MCPClientProtocol.swift` 同文件**（**Round 3 P2 修订**：M1 SliceCore 没有 `MCPCallResult`，grep verified；M2 在 Capabilities 层落地）：
  ```swift
  public struct MCPCallResult: Sendable, Equatable, Codable {
      /// 返回内容；MCP 协议允许多块（text / image / blob），M2 仅约定 text，
      /// Phase 1 真实 MCPClient 才扩展（届时把此 struct 移到 SliceCore 或 expose 更细的 ContentItem enum）
      public let content: [String]
      /// 是否 server 端报错（区别于 transport / parse 错误，后者由 client 直接 throw）
      public let isError: Bool
      /// MCP server 透传的 metadata（脱敏责任在 server 端；scrub 在 AuditLog 入口兜底）
      public let meta: [String: String]?
  }
  ```
- `MockMCPClient` 接受构造期注入的 `tools: [MCPToolRef]` / `responses: [MCPToolRef: MCPCallResult]` 字典，按 ref 路由；未命中 ref → throw `MCPClientError.toolNotFound(ref:)`
- `SkillRegistryProtocol.findSkill(id: String) async throws -> Skill?` / `.allSkills() async throws -> [Skill]`
- `MockSkillRegistry` 接受 `[Skill]` 直接返回
- 测试覆盖 mock 行为正确（empty registry → nil；populated → 返回；call 错误传播）；MCPCallResult round-trip Codable 测试（encode/decode 等价）

---

## Task 14: 集成验证 + 覆盖率检查 + Task-detail 归档

> 全部 Task 1–13 完成后，跑全套 verification + 写 Task-detail 实施总结 + 更新 Task_history / README / Module 文档。

**Files:**
- Modify: `docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md`（填充实施过程 + 变动文件清单 + 测试结果）
- Modify: `SliceAIKit/Sources/Orchestration/README.md`（M1 placeholder 替换为真实组件介绍）
- Modify: `SliceAIKit/Sources/Capabilities/README.md`（同）

**步骤：**

- [ ] **Step 1: 全套 CI gate（在 worktree 主目录）**

```bash
cd SliceAIKit && swift build && swift test --parallel --enable-code-coverage
# 期望: 全 Orchestration / Capabilities / SliceCore / Capabilities Tests + 已有 testTarget 全绿
# 期望: SliceCore 覆盖率 ≥ 90%（M1 已达成）；Orchestration ≥ 75%；Capabilities ≥ 60%
```

- [ ] **Step 2: 在主仓库根目录跑 swiftlint**

```bash
swiftlint lint --strict
# 期望: 0 violations / 0 serious
```

- [ ] **Step 3: zero-touch 验证**

```bash
git diff origin/main..HEAD -- \
  SliceAIKit/Sources/SliceCore \
  SliceAIKit/Sources/LLMProviders \
  SliceAIKit/Sources/SelectionCapture \
  SliceAIKit/Sources/HotkeyManager \
  SliceAIKit/Sources/DesignSystem \
  SliceAIKit/Sources/Windowing \
  SliceAIKit/Sources/Permissions \
  SliceAIKit/Sources/SettingsUI \
  SliceAIApp \
  | wc -l
# 期望: 0
```

- [ ] **Step 4: xcodebuild app 仍能编译**

```bash
# 在主仓库根目录跑（worktree 不一定有完整 .xcodeproj/xcworkspace 状态，按需切回主目录）
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
# 期望: BUILD SUCCEEDED
```

- [ ] **Step 5: 覆盖率详细报告**

```bash
# Orchestration 覆盖率
xcrun llvm-cov report .build/debug/SliceAIKitPackageTests.xctest/Contents/MacOS/SliceAIKitPackageTests \
  -instr-profile=.build/debug/codecov/default.profdata \
  -ignore-filename-regex=".*Tests.*|.*Mock.*" \
  SliceAIKit/Sources/Orchestration
# 期望: Orchestration line coverage ≥ 75%
```

- [ ] **Step 5.5: GateOutcome / Outcome enum exhaustive switch 反向断言（Round 2 B-3 + Round 3 修订补全）**

```bash
# 验证 Round 2 B-3 锁定的"无 default"约束在 PermissionBroker / ExecutionEngine 真正落地
# grep -c 返回 default: 出现次数；期望 0 + 0
echo "PermissionBroker default count:"
grep -c "^[[:space:]]*default:" SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift
echo "ExecutionEngine default count:"
grep -c "^[[:space:]]*default:" SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift
# 也包括 ErrorKind.from / Permission tier 计算等 enum 关键 switch
echo "InvocationReport (ErrorKind.from) default count:"
grep -c "^[[:space:]]*default:" SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift
# 期望全部为 0；非零则失败（说明实现里漏了某些 case 用 default 兜底）
```

- [ ] **Step 6: 填充 Task-detail 实施总结**

完整填 `docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md` 的 §5（变动文件清单）、§6（测试结果含覆盖率）、§7（修改逻辑总结）

- [ ] **Step 7: 更新 README.md 项目修改变动记录**

在 `README.md` 顶部追加 "2026-XX-XX · Phase 0 M2 完成"段落（沿用 M1 merge 后的格式）

- [ ] **Step 8: Commit + push + open PR**

```bash
git add docs SliceAIKit/Sources/Orchestration/README.md SliceAIKit/Sources/Capabilities/README.md README.md
git commit -m "docs(phase-0/m2): finalize Task-detail + module README"
git push -u origin feature/phase-0-m2-orchestration
gh pr create --base main --head feature/phase-0-m2-orchestration --title "Phase 0 M2: Orchestration + Capabilities 骨架" --body "$(cat <<'EOF'
## Summary

落地 v2.0 spec §3.4 / §3.9 的执行引擎 + 权限闭环 + 安全模型骨架；新增 ~30 个文件 / ~3000 行；零触及 v1 + M1 v2 类型。

## What's in scope

- Orchestration: ExecutionEngine / ContextCollector / PermissionBroker / PermissionGraph / CostAccounting / JSONLAuditLog / OutputDispatcher / PromptExecutor
- Capabilities: PathSandbox / MCPClientProtocol + Mock / SkillRegistryProtocol + Mock

## What's NOT in scope

- AppContainer 接入（M3）
- ToolExecutor 删除（M3）
- 真实 MCPClient（Phase 1）
- 真实 SkillRegistry（Phase 2）
- PresentationMode 非 .window 分支（Phase 2）

## Test plan

- [ ] swift test --parallel --enable-code-coverage 全绿
- [ ] swiftlint lint --strict 0 violations
- [ ] Orchestration 覆盖率 ≥ 75%
- [ ] Capabilities 覆盖率 ≥ 60%
- [ ] zero-touch 验证（v1 + M1 SliceCore git diff = 0）
- [ ] xcodebuild app 仍能编译

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

---

## Self-Review Checklist（Plan 内置；每完成一轮修订都要重跑）

> 按 superpowers:writing-plans skill 的 Self-Review 段执行。

### 1. Spec 覆盖

- [ ] M2.1 ExecutionEngine 骨架 + ExecutionEvent → Task 1（事件）+ Task 3（actor 骨架）+ Task 4（主流程）
- [ ] M2.2 ContextCollector → Task 5
- [ ] M2.3 PermissionBroker → Task 6
- [ ] M2.3a PermissionGraph → Task 7
- [ ] M2.4 CostAccounting → Task 8
- [ ] M2.5 AuditLog → Task 9
- [ ] M2.6 OutputDispatcher（仅 .window 分支） → Task 10
- [ ] M2.7 PromptExecutor → Task 11
- [ ] M2.8 PathSandbox → Task 12
- [ ] M2.9 MCPClientProtocol / SkillRegistryProtocol → Task 13

### 2. Placeholder 扫描

- [ ] 无 "TBD / TODO / 待补充 / Similar to Task N"——所有 task 都给出 file path + key design points
- [ ] **第一稿例外**：Task 2–13 的"完整 TDD 步骤：待第二轮展开"是**主动声明**的展开节奏，不算 placeholder（参考 M1 plan 第七轮评审"渐进展开"的 P2-3 处理）

### 3. 类型一致性

- [ ] `V2Tool` / `V2Provider` / `V2Configuration` 全程使用（不写 spec 原始的 `Tool` / `Provider` / `Configuration`）
- [ ] `PresentationMode` 而非 `DisplayMode`；`SelectionOrigin` 而非 `SelectionSource`
- [ ] `ExecutionEngine.execute(tool:seed:)` 的签名在 Task 3 / Task 4 一致
- [ ] `EffectivePermissions` struct 字段在 Task 7 与 spec §3.9.6.5 完全对齐（fromContexts / fromSideEffects / fromMCP / fromBuiltins / declared / union / undeclared）

### 4. 关键不变量复盘

- [ ] **C-1 zero-touch**：每个 task 的 Files 段都明确只在 `Sources/Orchestration/` `Sources/Capabilities/` `Tests/Orchestration*Tests/` `Tests/Capabilities*Tests/` 下；无对 `SliceCore/` `LLMProviders/` 等的 Modify
- [ ] **C-3 平铺并发**：Task 5 的关键设计点明确 "withTaskGroup 不实现 DAG"
- [ ] **C-4 PermissionGraph 静态校验**：Task 7 关键设计点明确 "纯函数不做 I/O"，且 Task 4 主流程顺序 Step 2 PermissionGraph → Step 3 ContextCollector
- [ ] **C-5 firstParty 不能放行 network-write/exec**：Task 6 测试矩阵覆盖此条
- [ ] **C-6 OutputDispatcher 仅 .window**：Task 10 关键设计点明确其余 5 mode `.notImplemented`
- [ ] **C-7 PromptExecutor 复制非替换**：Task 11 关键设计点明确 "ToolExecutor.swift 不动"
- [ ] **C-8 日志脱敏在 AuditLog 入口**：Task 9 关键设计点明确 "Redaction.scrub 在 append 前调用"

---

## 执行选项（Plan 评审通过后填入）

> 按 superpowers:writing-plans skill 的 Execution Handoff 段。
>
> 执行前提：本 plan 第一稿过 Codex 评审至少一轮（直到 APPROVED 或 CONDITIONAL_APPROVE 收尾）；评审同时把 Task 2 – Task 13 的"完整 TDD 步骤：待第二轮展开"展开为 M1 同等粒度的 step-by-step。

**选项 1（推荐）：subagent-driven-development**
- 每个 Task 派发一个 fresh subagent，主对话做 code review checkpoint
- 优点：快、上下文窗口隔离、并行能力（独立 task 可同时跑）
- 缺点：subagent 之间无法看到彼此 patch，必须靠 plan 自身规约确保接口一致

**选项 2：executing-plans inline**
- 主对话顺序执行所有 task，checkpoint 在每个 task 之后
- 优点：上下文连贯，类型一致性更强
- 缺点：上下文窗口压力大，到后期 task 时容易触发 compaction

> 默认选 1；M1 用的是 1 + 8 轮 Codex review 跑通的，M2 沿用同模式。

---

## 附录：与 spec §3.4 ExecutionEngine 流程的逐 Step 落地对照

| Step | spec 描述 | M2 落地 Task | 备注 |
|---|---|---|---|
| 1 | yield .started(invocationId) | Task 4 | invocationId = UUID() 在 execute 入口生成 |
| 2 | PermissionGraph.compute + ⊆ 校验 | Task 4 + Task 7 | 失败 → yield .failed(.permission(.undeclared)) |
| 2.5 | PermissionBroker.gate（按下限 + provenance） | Task 4 + Task 6 | 失败 → yield .failed(.permission(.denied)) |
| 3 | ContextCollector.resolve | Task 4 + Task 5 | 必填失败 → yield .failed(.context(.required)) |
| 4 | ProviderResolver.resolve | Task 4 + Task 2 | M2 仅 .fixed 形态；其他 throw .notImplemented |
| 5 | dispatch by tool.kind | Task 4 + Task 11 | M2 仅 .prompt；.agent / .pipeline → yield .notImplemented + finished |
| 6 | LLM stream → OutputDispatcher | Task 4 + Task 10 + Task 11 | OutputDispatcher 仅 .window 真实分发 |
| 7 | sideEffects 触发（每个前再 gate） | Task 4 + Task 6 + Task 10 | 副作用前调 PermissionBroker.gate 走 §3.9.2 下限 |
| 8 | CostAccounting.record | Task 4 + Task 8 | 入参 = invocationId / toolId / providerId / model / usage / usd |
| 9 | AuditLog.append(report) | Task 4 + Task 9 | report 含 declared/effective/diff，进 jsonl |
| 10 | yield .finished(report) | Task 4 | 流结束 |

---

**第一稿 EOF（Task 2 – Task 13 完整 TDD 步骤待第二轮展开）**
