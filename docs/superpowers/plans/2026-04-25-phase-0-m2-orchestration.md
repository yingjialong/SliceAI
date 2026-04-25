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
  │   └─ PermissionError.swift                          Task 6 / 7
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

> Round 1 / 2 / ... 在每轮评审落地后填充。第一稿尚未过评审。

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
| Create | `SliceAIKit/Sources/Orchestration/Permissions/PermissionError.swift` | undeclared / denied / sandboxViolation | Task 6 / 7 |
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
- Modify: `docs/Task_history.md`（在最顶部 Task 33 之前插入 Task 34）

**步骤：**

- [ ] **Step 1：检查 Task 编号**

```bash
# 在主仓库根目录跑（worktree 内也可）
grep "^## Task " docs/Task_history.md | head -3
# 期望输出：Task 32 / Task 31 / Task 30（M1 收尾时已写到 Task 32）
# 下一个可用编号为 33；本 plan 用 Task 33（按"grep 取下一个可用值"原则，不硬编码）
```

- [ ] **Step 2：创建 Task-detail 骨架文件**

写入 `docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md`：

```markdown
# Task 33 · Phase 0 M2 · Orchestration + Capabilities 骨架

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

- [ ] **Step 3：在 Task_history.md 顶部追加索引（Task 33）**

在第 5 行 `## Task 32 · 基于 Codex 第七轮评审...` 之前插入：

```markdown
## Task 33 · Phase 0 M2 · Orchestration + Capabilities 骨架

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
- Index Task 33 in docs/Task_history.md

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

    public init(
        invocationId: UUID,
        toolId: String,
        declaredPermissions: Set<Permission>,
        effectivePermissions: Set<Permission>,
        flags: Set<InvocationFlag>,
        startedAt: Date,
        finishedAt: Date,
        totalTokens: Int,
        estimatedCostUSD: Decimal
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
    }
}

public enum InvocationFlag: String, Sendable, Codable, Equatable {
    case dryRun
    case permissionUndeclared
    case partialFailure
    case sandboxViolation
}

#if DEBUG
extension InvocationReport {
    /// 单测 / Playground 用——固定 stub 值
    public static func stub(
        invocationId: UUID = UUID(),
        toolId: String = "test.tool",
        declared: Set<Permission> = [],
        effective: Set<Permission> = [],
        flags: Set<InvocationFlag> = []
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
            estimatedCostUSD: 0
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

- [ ] **Step 9: 跑完整 OrchestrationTests，确认 4 tests pass**

```bash
swift test --filter OrchestrationTests
# 期望: 4 tests passing（ExecutionEventTests x 2 + InvocationReportTests x 3 = 5...）
# 实际：3 tests in InvocationReportTests + 2 in ExecutionEventTests = 5 tests pass
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
- `.fixed(providerId:)` → 在 `current().providers` 找；找不到 throw `ProviderResolutionError.notFound(providerId)`
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
- init 接受 7 个依赖（与 spec §3.4 完全对齐）：`contextCollector` / `permissionBroker` / `providerResolver` / `mcpClient` / `skillRegistry` / `costAccounting` / `auditLog` / `output`——M2 阶段全部接受 protocol，便于测试注入 Mock
- `execute(tool:seed:)` 返回 `AsyncThrowingStream<ExecutionEvent, Error>`；本 Task 内部只 yield `.started` + `.notImplemented` + `.finished(stub)` 三件事，让 ExecutionEngineTests 能验证流框架
- 主流程的 Step 2 / Step 2.5 / Step 3 / Step 4 / Step 5 在 Task 4 / 6 / 7 才接入

---

## Task 4: M2.1.d · ExecutionEngine 主流程 happy path（PermissionGraph + ContextCollector + PromptExecutor 接入）

> 把 Task 7（PermissionGraph）+ Task 5（ContextCollector）+ Task 11（PromptExecutor）拼成 ExecutionEngine.execute 的真实主流程，覆盖 spec §3.4 Step 1–10。本 Task 是 M2 最大的 task；预计 1.5 人天的核心。

**Files:**
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`（替换 Task 3 的占位 yield 为真实 step 编排）
- Modify: `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`（追加 4 条主路径测试）

**完整 TDD 步骤：待第二轮展开**

**关键设计点：**
- 严格按 spec §3.4 流程：Step 1 yield `.started` → Step 2 PermissionGraph.compute + ⊆ 校验 → Step 2.5 PermissionBroker.gate → Step 3 ContextCollector.resolve → Step 4 ProviderResolver.resolve → Step 5 dispatch by tool.kind（**M2 仅展开 .prompt，.agent / .pipeline 全部 yield `.notImplemented` + finished**）→ Step 6 PromptExecutor.run 流式转 .llmChunk 给调用者 → Step 7 OutputDispatcher 处理 sideEffects（每个 sideEffect 前再过 PermissionBroker）→ Step 8 CostAccounting.record → Step 9 AuditLog.append → Step 10 yield .finished(report)
- 测试矩阵覆盖 4 条 prompt-kind 路径：
  - **happy**: 全 mock 放行 → 流式 yield delta → finished(report)
  - **context-fail**: required ContextRequest 失败 → yield .failed(.context(.required(...)))
  - **permission-deny**: PermissionBroker.gate 拒绝 → yield .failed(.permission(.denied(...)))
  - **dry-run**: seed.isDryRun=true → 仍走 LLM but 跳过所有 sideEffect；report.flags 含 .dryRun
- 每个测试用 OrchestrationTests/Helpers 注入完整 Mock 套件

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
- `ContextCollector(providers: [String: any ContextProvider])` 按 `ContextRequest.providerId` 路由
- `resolve(seed: ExecutionSeed, requests: [ContextRequest]) async throws -> ResolvedExecutionContext`
- 每个 request 有独立的 `timeout: Duration`（默认 5s，由 request 自己声明）
- 必填 `Requiredness.required` 失败 → throw `ContextCollectorError.requiredFailed(key:underlying:)`
- 可选 `Requiredness.optional` 失败 → 进 `ResolvedExecutionContext.failures: [String: Error]`，主流程继续
- 测试矩阵：5 个 mock provider 并发跑、其中 1 个 required 失败 vs 1 个 optional 失败、timeout 触发
- ContextProvider 默认实现已在 SliceCore (M1)；此处只编 Collector

---

## Task 6: M2.3 · PermissionBroker 接口 + 默认实现 + §3.9.2 下限硬编码

> 实现 spec §3.9.2 的能力下限矩阵 + §3.9.1 Provenance UX hint 合并；M2 默认实现走 in-memory grant store，gate 默认按下限要求确认（测试用 MockPermissionBroker 全放行）。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBrokerProtocol.swift`
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift`
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionGrantStore.swift`
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionError.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/PermissionBrokerTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点：**
- `PermissionBrokerProtocol.gate(effective: Set<Permission>, provenance: Provenance, scope: GrantScope, isDryRun: Bool) async throws -> GateOutcome`
- `GateOutcome = .approved | .denied(reason: String) | .requiresUserConsent(uxHint: ConsentUXHint)`
- 下限决策：把 Permission 映射到 5 个 tier（readonly-local / readonly-network / local-write / network-write / exec），每个 tier 对应 lowerBound policy
- `firstParty` provenance 不能放行 `network-write` / `exec`：测试矩阵覆盖 spec §3.9.2 全表（5 tier × 4 provenance = 20 cell，至少抽样 12 cell）
- `isDryRun=true` 时所有 gate 直接返回 .approved（dry-run 不实际执行副作用）
- `PermissionGrantStore` 是 actor；M2 仅 in-memory 实现，session-scoped grant 持久化到 Phase 1 才做

---

## Task 7: M2.3a · EffectivePermissions + PermissionGraph.compute（D-24 静态闭环）

> 实现 spec §3.9.6.5 的 PermissionGraph：聚合 tool.contexts / outputBinding.sideEffects / kind.agent.mcpAllowlist / kind.agent.builtinCapabilities 的 inferredPermissions，与 tool.permissions 做 ⊆ 校验。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Permissions/EffectivePermissions.swift`
- Create: `SliceAIKit/Sources/Orchestration/Permissions/PermissionGraph.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionError.swift`（追加 `.undeclared(missing:)`）
- Create: `SliceAIKit/Tests/OrchestrationTests/PermissionGraphTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点：**
- 完全照抄 spec §3.9.6.5 的 `EffectivePermissions` struct（fromContexts / fromSideEffects / fromMCP / fromBuiltins / declared / union / undeclared computed）
- `PermissionGraph.compute(tool: V2Tool) -> EffectivePermissions`：纯函数，不做 I/O
- 测试矩阵：
  - prompt 工具，contexts 含 `file.read` 但 tool.permissions 缺 `.fileRead` → undeclared 非空
  - prompt 工具，sideEffects 含 `appendToFile` 但 tool.permissions 缺 `.fileWrite` → undeclared 非空
  - agent 工具，mcpAllowlist 含 `["fs.read"]` 但 tool.permissions 缺 `.mcp(server:"fs", tools:["fs.read"])` → undeclared 非空
  - 全部声明覆盖 → undeclared 空
  - empty tool（无 contexts / sideEffects / mcp）→ effective.union 空集
- ExecutionEngine 在 Step 2 调 `PermissionGraph.compute(tool: tool)`；如 `effective.undeclared` 非空 → yield `.failed(.permission(.undeclared(missing: ...)))` 并结束流，**不进 Step 3**

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

**关键设计点：**
- `AuditLogProtocol`：`append(_ entry: AuditEntry) async throws` / `clear() async throws`（清空写 `.logCleared` 事件作为新文件第一条）/ `read(limit: Int) async throws -> [AuditEntry]`
- `AuditEntry`：含 `invocationId` / `toolId` / `eventType: AuditEventType`（started / finished / failed / sideEffect / logCleared）/ `payload: [String: AuditValue]`
- `Redaction.scrub(_ s: String) -> String`：API key / token / cookie / authorization 等正则匹配 → `<redacted>`；超过 200 字符截断
- selection 原文不入 jsonl：append 前由 entry 构造方设定 `payload["selection_sha256"]` + `payload["selection_length"]`（生产者责任）；jsonl 写入层不再重复 hash
- 测试矩阵：
  - 1000 条 append + read（FIFO/LIFO 验证）
  - 触发 `Redaction.scrub`：API key 字段被 redact
  - clear() 清空文件后第一条是 `logCleared` 事件
  - selection 原文未泄漏（grep 测试 fixture 中"超过 200 字符的中文 paragraph"不出现在落盘文件中）

---

## Task 10: M2.6 · OutputDispatcherProtocol + 默认实现（仅 .window 分支）

> 落地 spec §3.3.6 + §3.4 Step 6/7 的 OutputDispatcher：根据 V2Tool.outputBinding.primary 派发到对应 sink。M2 只实现 `.window` 分支（落到 in-memory MockWindowSink），其余 5 个 PresentationMode 直接 yield `.notImplemented`。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Output/OutputDispatcherProtocol.swift`
- Create: `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift`
- Create: `SliceAIKit/Tests/OrchestrationTests/OutputDispatcherTests.swift`

**完整 TDD 步骤：待第二轮展开**

**关键设计点：**
- `OutputDispatcherProtocol.handle(chunk: String, mode: PresentationMode, invocationId: UUID) async throws -> DispatchOutcome`
- `DispatchOutcome = .delivered | .notImplemented(reason: String)`
- `.window` 分支：把 chunk 投递到 `WindowSinkProtocol`（M2 测试用 `InMemoryWindowSink` 收集，生产路径 M3 才接入 ResultPanel）
- `.bubble` / `.replace` / `.file` / `.silent` / `.structured` 一律返回 `.notImplemented(reason: "...")`，让 ExecutionEngine 把这条事件转发为 `.notImplemented` ExecutionEvent

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

**关键设计点：**
- `PathSandbox.normalize(_ raw: String, role: AccessRole) throws -> URL`：先 `URL(fileURLWithPath:).standardizedFileURL`，再判断
- 默认白名单：`~/Documents` `~/Desktop` `~/Downloads` `~/Library/Application Support/SliceAI/**`
- 硬禁止前缀（永远拒绝，无视用户配置）：`~/Library/Keychains/**` `~/.ssh/**` `~/Library/Cookies/**` `/etc/**` `/var/db/**` `/Library/Keychains/**`
- 用户附加白名单 = `[String]`，构造时注入；M2 仅静态默认值（用户配置加白名单是 Phase 1 Settings UX）
- `AccessRole` enum：`.read` / `.write`（write 只允许 `~/Library/Application Support/SliceAI/**` + 用户附加）
- 测试矩阵：
  - `..` traversal: `~/Documents/../Library/Keychains/foo` → throw `.escapesWhitelist`
  - symlink resolved before check
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

**关键设计点：**
- `MCPClientProtocol.tools(for descriptor: MCPDescriptor) async throws -> [MCPToolRef]` / `.call(ref: MCPToolRef, args: [String: String]) async throws -> MCPCallResult`
- `MockMCPClient` 接受构造期注入的 `tools` / `responses` 字典，按 ref 路由
- `SkillRegistryProtocol.findSkill(id: String) async throws -> Skill?` / `.allSkills() async throws -> [Skill]`
- `MockSkillRegistry` 接受 `[Skill]` 直接返回
- 测试覆盖 mock 行为正确（empty registry → nil；populated → 返回；call 错误传播）

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
