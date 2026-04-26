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
| 7 | 7 | M2.3a · EffectivePermissions + PermissionGraph + SliceCore.ToolPermissionError 新建 | 待启动 |
| 8 | 8 | M2.4 · CostAccounting actor + sqlite append + CostRecord | 待启动 |
| 9 | 9 | M2.5 · AuditLogProtocol + JSONLAuditLog actor + Redaction 脱敏 + AuditEntry enum | 待启动 |
| 10 | 10 | M2.6 · OutputDispatcherProtocol + 默认实现（仅 .window 分支） | 待启动 |
| 11 | 11 | M2.7 · PromptExecutor actor（从 ToolExecutor 复制 + 改 V2 类型 + PromptStreamElement） | 待启动 |
| 12 | 4 | M2.1.d · ExecutionEngine 主流程集成（Step 1-10 全部）— 排到第 11 位执行 | 待启动 |
| 13 | 12 | M2.8 · PathSandbox + PathSandboxError | 待启动 |
| 14 | 13 | M2.9 · MCPClientProtocol + SkillRegistryProtocol + Mock 实现 | 待启动 |
| 15 | 14 | 集成验证 + 覆盖率检查 + Task-detail 归档 + PR | 待启动 |

## 5. 变动文件清单

待实施完成后填充。预计：

- **30 个新源文件**：Orchestration/{Events,Engine,Context,Permissions,Telemetry,Output,Executors,Internal} + Capabilities/{SecurityKit,MCP,Skills}
- **14 个新测试文件 + 3 个 Mock helper 共享文件**：OrchestrationTests + CapabilitiesTests
- **3 个 SliceCore 白名单文件**：`SliceError.swift` Modify + `ContextError.swift` Create + `ToolPermissionError.swift` Create
- **1 个 Package.swift Modify**：移除 placeholder testTarget + 给 Orchestration 加 Capabilities 依赖（R13-P1-NEW-1）+ OrchestrationTests testTarget 同样加
- **2 个 README.md Modify**：Orchestration / Capabilities target 介绍替换 M1 placeholder

## 6. 测试结果

待实施完成后填充。期望：

- `swift test --parallel --enable-code-coverage` 全绿（含 M1 既有 341 SliceCoreTests + 新增 OrchestrationTests / CapabilitiesTests）
- `swiftlint lint --strict` 0 violations
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` BUILD SUCCEEDED
- 覆盖率：SliceCore ≥ 90% / Orchestration ≥ 75% / Capabilities ≥ 60%
- zero-touch 验证：`git diff $(git merge-base HEAD origin/main)..HEAD -- <v1 模块>` 期望 0 行 + SliceCore 实际改动文件仅 3 个白名单 + M1 既有 341 测试全绿

## 7. 修改逻辑总结

待实施完成后填充。
