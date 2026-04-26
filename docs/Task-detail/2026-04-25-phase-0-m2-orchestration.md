# Task 34 · Phase 0 M2 · Orchestration + Capabilities 骨架

> **状态**：实施中
> **plan**：[docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md](../superpowers/plans/2026-04-25-phase-0-m2-orchestration.md)
> **基线 commit**：`5cdf0f7`（main HEAD，M1 PR #1 merge commit）
> **worktree**：`.worktrees/phase-0-m2/`
> **分支**：`feature/phase-0-m2-orchestration`
> **plan HEAD**：`5cfac70`（13 轮 Codex review-fix loop 完成的最终蓝本）

## 1. 任务背景

承接 M1（PR #1 已 merge 入 main，merge commit `5cdf0f7`，2026-04-25）。M1 落地了 SliceCore 中的 19 个 V2* / 领域类型 + ConfigMigratorV1ToV2 + 341 SliceCoreTests，但 `Orchestration` / `Capabilities` 两个 SwiftPM target 仍是 M1 留下的空 placeholder。M2 的目标是把 spec §3.4（执行引擎）+ §3.9.6.5（权限闭环）+ §3.9.2 / §3.9.3 / §3.9.5（安全下限 / 路径沙箱 / 日志脱敏）+ §3.3.6（OutputBinding）落地为这两个 target 的可独立单测的骨架，**完全不接入 app 启动链路**——`AppContainer` / `ToolExecutor` / 触发链 / `FileConfigurationStore` 全部零触及，app 行为保持 v0.1 + M1 现状不变。M3 才做"切到 ExecutionEngine + 删除 ToolExecutor + rename pass"。

## 2. 现有问题

无（M1 zero-touch 验证通过；M2 在 M1 已建好的两个空 target 中独立实现，配合 SliceCore 白名单 3 文件纯增）。M2 的所有改动都受 §C-1 zero-touch 边界约束（v1 8 模块严格 git diff = 0；SliceCore 仅允许 `SliceError.swift` Modify + `ContextError.swift` Create + `ToolPermissionError.swift` Create 三文件纯增）。

## 3. 实施方案

完整实施蓝本见 plan `docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`（2232 行，13 轮 Codex review-fix loop 后定稿）。关键约束摘要：

- **Architecture**：所有新代码限定在 `Orchestration/` + `Capabilities/` 两个 M1 已建好的空 target 下，零触及现有 8 个模块
- **§C-1 zero-touch（Round 4 放宽）**：v1 模块严格 diff = 0；SliceCore 仅白名单 3 文件纯增（追加 SliceError 顶层 case `.context` / `.toolPermission`，不改既有 case 字段顺序 / Codable 形状）
- **§C-7 PromptExecutor 复制非替换**：从 `SliceCore/ToolExecutor.swift` 复制 prompt 渲染逻辑到 `Orchestration/Executors/PromptExecutor.swift`，**`SliceCore/ToolExecutor.swift` 原封保留**直至 M3
- **§C-10 Swift 6 Actor Isolation 一致性 Audit**：plan §C-10.1 表锁定全部 12 个 Orchestration / Capabilities 依赖类型的 isolation 与方法签名；§C-10.3 锁定 ExecutionEngine 主流程 9 行调用点的 await/try 形态；实施时不可偏离
- **Task 实施顺序约束（R5-P1.4）**：Task 编号保留按 spec M2.1.d 为 Task 4，但实际执行序列调整为 **Task 0 → 1 → 2 → 3 → 5 → 6 → 7 → 8 → 9 → 10 → 11 → 4 → 12 → 13 → 14**（Task 4 排到第 11 位执行，因为它依赖 Task 5/6/7/11 的具体类型）

## 4. ToDoList

按 plan 中 Task 0 – Task 14 顺序执行；每个 Task 内勾选项独立追踪。

| 顺序 | Task # | 标题 | 状态 |
|---|---|---|---|
| 1 | 0 | 文档初始化（Task-detail 骨架 + Task_history 索引） | 已完成 |
| 2 | 1 | M2.1.a · ExecutionEvent + InvocationReport + Package wiring | 已完成 |
| 3 | 2 | M2.1.b · ProviderResolverProtocol + DefaultProviderResolver + ProviderResolutionError | 已完成 |
| 4 | 3 | M2.1.c · ExecutionEngine actor 骨架 + execute 入口签名 + 10 依赖装配 | 已完成 |
| 5 | 5 | M2.2 · ContextCollector 平铺并发 + ContextProviderRegistry + SliceCore.ContextError 新建 | 已完成 |
| 6 | 6 | M2.3 · PermissionBroker 接口 + 默认实现 + §3.9.2 下限硬编码 + GateOutcome 4 态 | 已完成 |
| 7 | 7 | M2.3a · EffectivePermissions + PermissionGraph + SliceCore.ToolPermissionError 新建 | 已完成 |
| 8 | 8 | M2.4 · CostAccounting actor + sqlite append + CostRecord | 已完成 |
| 9 | 9 | M2.5 · AuditLogProtocol + JSONLAuditLog actor + Redaction 脱敏 + AuditEntry enum | 已完成 |
| 10 | 10 | M2.6 · OutputDispatcherProtocol + 默认实现（仅 .window 分支） | 已完成 |
| 11 | 11 | M2.7 · PromptExecutor actor（从 ToolExecutor 复制 + 改 V2 类型 + PromptStreamElement） | 已完成 |
| 12 | 4 | M2.1.d · ExecutionEngine 主流程集成（Step 1-10 全部）— 排到第 11 位执行 | 已完成 |
| 13 | 12 | M2.8 · PathSandbox + PathSandboxError | 已完成 |
| 14 | 13 | M2.9 · MCPClientProtocol + SkillRegistryProtocol + Mock 实现 | 已完成 |
| 15 | 14 | 集成验证 + 覆盖率检查 + Task-detail 归档 + PR | 进行中 |

## 5. 变动文件清单

实测自 baseline `5cdf0f7` 至 HEAD 共 39 个 commit，65 个文件改动（**A=57 / M=4 / D=4**），总插入/删除 **+11362 / -45**。

### 5.1 Sources/Orchestration（21 新增，1 删除）

| 子目录 | 新增文件 | 备注 |
|---|---|---|
| Engine/ | `ExecutionEngine.swift` + `ExecutionEngine+Steps.swift` + `ProviderResolutionError.swift` + `ProviderResolver.swift` | actor 主流程拆 2 文件（FlowContext class + 6 step helper），避免单文件触发 swiftlint function_body 80 行硬限 |
| Events/ | `ExecutionEvent.swift` + `InvocationReport.swift` | 流式事件 enum + 终态报告（含 declared/effective 权限差异 + flags + outcome） |
| Context/ | `ContextCollector.swift` | 平铺并发（withTaskGroup + raceWithTimeout）+ ContextProviderRegistry 同文件 |
| Permissions/ | `PermissionBrokerProtocol.swift` + `PermissionBroker.swift` + `PermissionGrantStore.swift` + `EffectivePermissions.swift` + `PermissionGraph.swift` | 4 态 GateOutcome + §3.9.2 下限硬编码 + D-24 静态闭环 |
| Telemetry/ | `AuditLogProtocol.swift` + `JSONLAuditLog.swift` + `CostAccounting.swift` + `CostRecord.swift` | sqlite append + JSON Lines + Redaction 脱敏 |
| Output/ | `OutputDispatcherProtocol.swift` + `OutputDispatcher.swift` + `InMemoryWindowSink.swift` | 6-mode dispatcher（M2 仅 `.window` 真实分发） |
| Executors/ | `PromptExecutor.swift` | 从 v1 ToolExecutor 复制（**§C-7 复制非替换**）+ V2 类型 + PromptStreamElement enum + UsageStats |
| Internal/ | `Redaction.swift` | 4 模式脱敏（Bearer / sk- / Authorization / Cookie） |
| 删除 | `Placeholder.swift` | M1 占位被真实模块取代 |

### 5.2 Sources/Capabilities（5 新增 + 2 修改 stub，1 删除）

| 子目录 | 改动 | 备注 |
|---|---|---|
| SecurityKit/ | `PathSandbox.swift` (A) + `PathSandboxError.swift` (A) | spec §3.9.3：路径规范化 + 默认白名单 + 硬禁止表（含 macOS `/private/etc` 兜底） |
| MCP/ | `MCPClientProtocol.swift` (M, Task 3 stub → 5 类型同文件) + `MockMCPClient.swift` (A) | production-side public Mock；MCPCallResult / MCPClientError / MCPDescriptor / MCPToolRef |
| Skills/ | `SkillRegistryProtocol.swift` (M, Task 3 stub → 含 Skill 类型) + `MockSkillRegistry.swift` (A) | production-side public Mock |
| 删除 | `Placeholder.swift` | 同上 |

### 5.3 Sources/SliceCore（白名单 3 文件，§C-1 zero-touch 严格遵守）

| 文件 | 改动 | 内容 |
|---|---|---|
| `SliceError.swift` | M | 加 `.context(ContextError)` + `.toolPermission(ToolPermissionError)` 顶层 case + `ConfigurationError.invalidTool` + 各自 userMessage / developerContext 脱敏分支 |
| `ContextError.swift` | A | spec §3.3.3 上下文采集失败 enum（requiredFailed / providerNotFound / timeout） |
| `ToolPermissionError.swift` | A | spec §3.9.6.5 权限决策失败 enum（undeclared / denied / notGranted / unknownProvider / sandboxViolation） |

**未触碰**：v1 8 模块（LLMProviders / SelectionCapture / HotkeyManager / DesignSystem / Windowing / Permissions / SettingsUI）+ SliceAIApp + `SliceCore/ToolExecutor.swift` 自 baseline 起共 **0 行 diff**（git diff 验证）。

### 5.4 Tests（17 + 4 + 2 共 23 个新增，3 删除）

- **OrchestrationTests**（17 新增 + 1 删除）：`ExecutionEngineTests` (8 tests) / `ExecutionEventTests` / `InvocationReportTests` / `ContextCollectorTests` / `PermissionBrokerTests` (33) / `PermissionGrantStoreTests` (6) / `PermissionGraphTests` (16) / `CostAccountingTests` (8) / `JSONLAuditLogTests` (15) / `RedactionTests` (14) / `OutputDispatcherTests` (10) / `PromptExecutorTests` (10) / `ProviderResolverTests`；`Helpers/` 8 个共享 Mock（MockKeychain / MockLLMProvider / MockProvider / MockContextProvider / MockPermissionBroker / MockOutputDispatcher / MockAuditLog / MockProviderResolver）；删除占位 + Task 3 临时 MCP/Skill Mock（被 Capabilities production Mock 取代）
- **CapabilitiesTests**（3 新增 + 1 删除）：`PathSandboxTests` (16) / `MCPClientProtocolTests` (10) / `SkillRegistryProtocolTests` (5)
- **SliceCoreTests**（2 新增）：`ContextErrorTests` (11) + `ToolPermissionErrorTests` (17)

### 5.5 其他 Modify

- `SliceAIKit/Package.swift`：Capabilities target wiring（Orchestration / OrchestrationTests 加 Capabilities 依赖；移除 placeholder testTarget；改动 22 行）
- `docs/Task_history.md`：M2 任务索引追加
- `docs/v2-refactor-master-todolist.md`：M2 完成状态更新
- `docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md` (新增)：plan 第 13 轮 Codex review-fix loop 后定稿（2232 行）
- `docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md` (新增, 即本文)
- `README.md`：项目修改变动记录追加 M2 完成段

## 6. 测试结果

### 6.1 CI gate 全绿

| 验证项 | 命令 | 结果 |
|---|---|---|
| build | `cd SliceAIKit && swift build` | ✅ Build complete (0.20s) |
| test | `cd SliceAIKit && swift test --parallel --enable-code-coverage` | ✅ **545 / 545 passed** (0.48s) |
| lint | `swiftlint lint --strict` (worktree 根) | ✅ 133 files / **0 violations / 0 serious** |
| xcodebuild | `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` | ✅ **BUILD SUCCEEDED** |

### 6.2 覆盖率（行覆盖；`-ignore-filename-regex=".*Tests.*|.*Mock.*"` 排除测试与 Mock）

| Target | 实测 | 目标 | 余量 |
|---|---|---|---|
| Orchestration | **89.12%** | ≥75% | +14.12 pp |
| Capabilities (excl Mock) | **97.64%** | ≥60% | +37.64 pp |
| Capabilities (incl Mock) | 98.08% | — | — |
| SliceCore | **92.73%** | ≥90% | +2.73 pp |

### 6.3 §C-1 / §C-7 Zero-touch 三条断言

```
# v1 8 模块 + SliceAIApp + ToolExecutor.swift
$ git diff 5cdf0f7..HEAD -- SliceAIKit/Sources/{LLMProviders,SelectionCapture,HotkeyManager,DesignSystem,Windowing,Permissions,SettingsUI} SliceAIApp SliceAIKit/Sources/SliceCore/ToolExecutor.swift | wc -l
0   ✅

# SliceCore 仅白名单 3 文件
$ git diff --name-only 5cdf0f7..HEAD -- SliceAIKit/Sources/SliceCore/
SliceAIKit/Sources/SliceCore/ContextError.swift
SliceAIKit/Sources/SliceCore/SliceError.swift
SliceAIKit/Sources/SliceCore/ToolPermissionError.swift   ✅
```

### 6.4 enum-switch `default:` 反向断言（C-3 / C-10 不变量）

PermissionBroker / ExecutionEngine / ExecutionEngine+Steps / InvocationReport 共 4 个文件 grep `default:` 出现次数全部为 **0**（spec §3.9 系列要求枚举改动必须 exhaustive switch，不允许 default 兜底）。

### 6.5 M1 既有 SliceCoreTests 全绿

`swift test --filter SliceCoreTests` → **324 / 324 pass**（M1 baseline 实测 324，含 M1 已落地的 V2 类型测试；本 M2 在 SliceCore 上新增 28 个测试覆盖新加的 ContextError + ToolPermissionError）。

### 6.6 plan / round 元数据残留扫描

`grep -rnE '(Round [0-9]+|R[0-9]+-P|R[0-9]+-B|B-[0-9]+\.|评审第|plan R-)' Sources/{Orchestration,Capabilities} Tests/{OrchestrationTests,CapabilitiesTests}` → **0 匹配**（公开 API 文档不含内部 plan-evolution 元数据，符合项目 polish 标准）。

## 7. 修改逻辑总结

### 7.1 总体架构

M2 在 Orchestration / Capabilities 两个 M1 已建好的空 SwiftPM target 内独立落地 spec §3.4（执行引擎）+ §3.9（权限闭环 + 安全模型）+ §3.3.3（上下文采集）的骨架。所有改动严格受 **§C-1 zero-touch** 约束（v1 8 模块 + SliceAIApp 自 baseline 起 0 行 diff），**完全不接入 app 启动链路**——`AppContainer` / `ToolExecutor` / 触发链 / `FileConfigurationStore` 全部零触及，app 行为保持 v0.1 + M1 现状不变。M3 才做"切到 ExecutionEngine + 删除 ToolExecutor + rename pass"。

### 7.2 ExecutionEngine 主流程（Step 1-10）

```
execute(tool, seed) -> AsyncThrowingStream<ExecutionEvent, Error>
  Step 1  yield .started(invocationId)
  Step 2  permissionGraph.compute(tool) → effective: EffectivePermissions
          if !effective.undeclared.isEmpty → finishFailure(.toolPermission(.undeclared))
  Step 2.5 permissionBroker.gate(effective.union, provenance, scope, isDryRun) → GateOutcome
          .denied / .requiresUserConsent → finishFailure
          .wouldRequireConsent → yield .permissionWouldBeRequested 后继续
  Step 3  contextCollector.resolve(seed, requests) → ResolvedExecutionContext
          .requiredFailed → finishFailure(.context(.requiredFailed))
  Step 4  providerResolver.resolve(providerSelection) → V2Provider
          .notFound → finishFailure(.configuration(.referencedProviderMissing))
  Step 5  switch tool.kind:
            .prompt → 进入 Step 6
            .agent / .pipeline → finishNotImplementedKind（M2 不展开，Phase 1+ 才实现）
  Step 6  promptExecutor.run(promptTool, resolved, provider) → AsyncThrowingStream<PromptStreamElement>
          for each .chunk → yield .llmChunk + output.handle(chunk, mode, invocationId)
            非 .window mode → yield 一次 .notImplemented（notImplementedYielded 守卫）
          .completed(stats) → 收 promptUsage（不向外发独立事件）
  Step 7  for each sideEffect in tool.outputBinding.sideEffects:
            permissionBroker.gate(sideEffect.inferredPermissions, ...) 单独 gate
            .approved + isDryRun → yield .sideEffectSkippedDryRun
            .approved + 非 dry-run → yield .sideEffectTriggered + auditLog.append(.sideEffectTriggered)
            .denied / .requiresUserConsent → 标记 partialFailure（不中断主流程）
            .wouldRequireConsent → yield .sideEffectSkippedDryRun
  Step 8  costAccounting.record(CostRecord(invocationId, toolId, providerId, model, tokens, usd, recordedAt))
  Step 9  finishSuccess(report, continuation)：
            auditLog.append(.invocationCompleted(report))
            yield .finished(report)
            continuation.finish()
```

**关键不变量**：
- **统一审计**：所有终态路径（finishFailure / finishSuccess / finishNotImplementedKind）都通过 `auditLog.append(.invocationCompleted(report))` 写入 AuditEntry，spec §3.9.7"不可绕过"硬约束
- **D-24 静态闭环**：Step 2 PermissionGraph 在 Step 3 ContextCollector 之前执行，访问永远不能早于校验
- **D-22 / D-25 能力下限**：PermissionBroker.gate 的 lowerBound 仅依赖 tier，与 provenance 无关；provenance 只调节 UX hint 文案
- **dry-run 不豁免下限**：`isDryRun=true` 时 broker 仍正常计算下限；只在 Step 7 跳过实际副作用执行
- **PromptStreamElement enum 而非 callback**：Swift 6 严格并发不允许 `@Sendable` 闭包捕获 `var promptUsage`，故用 enum stream 替代 onCompletion 回调
- **OutputDispatcher .notImplemented 一次性 yield**：非 .window mode 即便有 5 chunks 也只 yield 1 条 `.notImplemented` ExecutionEvent（notImplementedYielded local var 守卫）

### 7.3 关键设计决策（实施期偏离 plan 的合理判断）

| 项 | plan 期望 | 实施 | 理由 |
|---|---|---|---|
| ExecutionEngine 单文件 | plan §1258-1635 给单文件可编译代码块 | 拆为 `ExecutionEngine.swift` + `ExecutionEngine+Steps.swift`（含 FlowContext class） | runMainFlow 单函数会触发 swiftlint function_body 80 行硬限；FlowContext class 在 actor-isolated scope 内串行使用，无 Sendable 警告 |
| `escapesWhitelist` 错误 case | plan / spec §3.9.3 措辞 | 改名为 `escapesAllowlist` | swiftlint `inclusive_language` rule 默认 enabled 拒绝 `whitelist`；中文注释保留"白名单"术语 |
| MCPCallResult / MCPClientError 设计 | plan §1979 / §1991 写在 plan 文档 | 5 类型同文件 + `MCPClientError.developerContext` 脱敏 | 与 SliceError.developerContext 对带 String payload 的 case 一律 `<redacted>` 同口径 |
| MCP/Skill Mock 位置 | plan §1966 / §1968 写"Sources/Capabilities/" | 实际放 Sources/Capabilities/MCP/ + Sources/Capabilities/Skills/ + 删除 OrchestrationTests Helpers 占位 | 让多个测试 target 可共享同一个 production-side public Mock；Phase 1 demo/CLI 入口可复用 |
| ContextCollector / PermissionGraph / PromptExecutor / CostAccounting Mock | plan §1658 列了 10 个 Mock | 4 个 concrete actor 不能 mock —— 沿用 makeEngine() "真实 actor + 控制上游 fakes" 模式 | Swift 6 actor 不能被 protocol mock；plan 设想与 §C-10.1 audit 表落地的 actor 实施现实有偏差，沿用现有 fixture 模式 |
| PathSandbox `/private/etc` 硬禁止 | plan §1949 仅列 `/etc/` | 新增 `/private/etc/` + `/private/var/db/` 兜底 | macOS 系统级 symlink `/etc → /private/etc`；用户 allowlist `/private/etc/` 加进来即可绕过原 `/etc/` 硬禁止——code-quality reviewer 抓出的真实安全漏洞 |
| Token 估算公式 | spec §4.4.2 `count / 4` | 同 + `max(1, …)` 兜底 + `?? .zero` 替代 force unwrap | spec 没说空 prompt 估 0 还是 1；选 max(1, …) 让空 prompt 也算 1 token，避免 CostAccounting 永远写 0；swiftlint --strict 禁 `!` 解包 |

### 7.4 §C-7 PromptExecutor 复制非替换

`SliceCore/ToolExecutor.swift` 自 baseline 起 0 行 diff（`git diff 5cdf0f7..HEAD` 验证）；新增 `Orchestration/Executors/PromptExecutor.swift` 是 ToolExecutor 的 V2 升级版（`PromptTool` 替代 `Tool`、`V2Provider` 替代 `Provider`、`PromptStreamElement` enum 替代回调）。M3 才执行"切到 ExecutionEngine + 删除 ToolExecutor + rename pass"。这一约束让 v0.1 行为在 M2 期间完全保留——CI / 用户测试都能验证 v0.1 链路无任何改动。

### 7.5 与 spec 的 step-by-step 落地对照

| Step | spec 描述 | M2 实现入口 |
|---|---|---|
| 1 | yield .started(invocationId) | `ExecutionEngine.runMainFlow` line 起首 `continuation.yield(.started(invocationId:))` |
| 2 | PermissionGraph.compute + ⊆ 校验 | `ExecutionEngine+Steps.runPermissionGraph` |
| 2.5 | PermissionBroker.gate | `runPermissionGate` |
| 3 | ContextCollector.resolve | `runContextCollection` |
| 4 | ProviderResolver.resolve | `runProviderResolution` |
| 5 | dispatch by tool.kind | runMainFlow 直接 switch |
| 6 | LLM stream → OutputDispatcher | `runPromptStream` |
| 7 | sideEffects 触发（每个前再 gate） | `runSideEffects` |
| 8 | CostAccounting.record | `recordCostAndFinishSuccess` |
| 9 | AuditLog.append(.invocationCompleted(report)) | `finishFailure` / `finishSuccess` 各自写 |
| 10 | yield .finished(report) | `finishSuccess` |

### 7.6 后续清理项（M2 后期 polish backlog，留 M3+ 一并处理）

- `MCPCallResult.meta` 类型 `[String: String]?` → Phase 1 升级为 `[String: AnyCodable]?` / 自定义 ContentValue enum 时，调用方需迁移
- `MockMCPClient` / `MockSkillRegistry` 命名 → 项目其他 production-side stub 用 `InMemory*` 风格（如 `InMemoryWindowSink`），Phase 1 真实 client 落地时改名为 `InMemoryMCPClient` / `InMemorySkillRegistry`
- `extractContextRequests` 在 ExecutionEngine+Steps 与 PermissionGraph 各自实现（按 tool.kind 分派），M3 rename pass 时统一抽到 V2Tool 自身的 `var allContextRequests: [ContextRequest]` 属性
- `estimateCostUSD` `0.000001` magic number → 抽 `private static let placeholderCostPerToken: Decimal`，Phase 1 接 real provider rate 时统一替换
- ExecutionEngine+Steps.swift 444 行 → 接近 swiftlint file_length warning 500，未来加 step 时考虑拆 `+Termination.swift`
- FlowContext class 加 invariant header 注释明确"严禁在 detached Task / Sendable closure 中捕获本类型"
- PathSandbox `init(userAllowlist:)` 加输入校验（fail-fast 拒绝 `~/.ssh/` 等硬禁止前缀），Phase 1 接 Settings UX 前必须加
