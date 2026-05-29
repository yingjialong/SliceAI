# 2026-05-28 · Phase 3 Task 1 Run Policy And Telemetry Foundation

## 背景

用户要求作为 Phase 3 ToolEditor v2 + Prompt Playground MVP 的实现 worker，执行 Task 1：为 Playground 试跑建立 `ExecutionRunPolicy`、telemetry source 标记和 ExecutionEngine 内部传递基础。

本任务只做 plan 中 Task 1 明确范围，不实现 Playground UI、专用 output dispatcher、Agent MCP disabled 策略或 Settings wiring。

## 任务目标

- 新增 SliceCore 运行策略类型，区分生产触发与 Settings Playground 试跑。
- 保持 `ExecutionSeed.isDryRun` 的向后兼容语义，并用可选 `runPolicy` 扩展 Playground 运行语义。
- 给 InvocationReport / CostRecord 增加 Playground source 标记，并保证旧 sqlite 成本库可迁移读取。
- 让 ExecutionEngine 使用 `context.runPolicy` 判断副作用 dry-run、审计 flags、成本 source 和 outcome。

## ToDoList

- [x] Step 1：写 SliceCore run policy 失败测试。
- [x] Step 2：运行 SliceCore focused tests 确认红灯。
- [x] Step 3：实现 SliceCore run policy 类型与 ExecutionSeed / TriggerSource 扩展。
- [x] Step 4：运行 SliceCore focused tests 确认通过。
- [x] Step 5：写 telemetry 兼容失败测试。
- [x] Step 6：运行 telemetry focused tests 确认红灯。
- [x] Step 7：实现 InvocationFlag / CostRecord / CostAccounting source 字段与迁移。
- [x] Step 8：在 ExecutionEngine flow 中传递 run policy 并写入 report / cost。
- [x] Step 9：运行 Task 1 focused tests。
- [x] Step 10：提交 `feat: add playground run policy telemetry`。

## 设计边界

- KISS：只增加运行策略的最小类型和字段，不在本任务中实现 UI 或新的执行入口。
- 向后兼容：`ExecutionSeed.runPolicy == nil` 时继续按 `isDryRun` 推导生产策略；旧成本 sqlite 记录的 `source` 为 nil。
- 安全边界：Playground source 只用于标记与后续路由，不在本任务中放宽权限或 MCP 行为。
- 日志边界：不新增自由日志输出，避免误写 selection、provider payload 或 MCP result。

## 实施记录

1. 新增 `ExecutionRunPolicy` 及四个小枚举，把执行来源、副作用模式、MCP tool call 模式和输出路由拆开，避免继续用 `isDryRun` 同时表达 Playground 的所有行为。
2. `ExecutionSeed` 新增可选 `runPolicy`，旧调用默认 nil；`effectiveRunPolicy` 在 nil 时回退为 `.production(isDryRun:)`，保持旧 JSON / 旧调用兼容。
3. `TriggerSource` 新增 `.playground`，用于 Settings Prompt Playground 试跑的触发来源标记。
4. `InvocationFlag` 新增 `.playground`，`CostRecord` 新增 nullable `source`，并让 `CostAccounting` 新库直接建 source 列、旧库通过 `ALTER TABLE ... ADD COLUMN source TEXT` 幂等迁移。
5. `FlowContext` 持有 `runPolicy`；ExecutionEngine 的整体 permission gate、side effects、finish report outcome、audit flags 和 cost source 均从 `context.runPolicy` 派生。
6. 新增 ExecutionEngine 回归测试覆盖 `seed.isDryRun == false` 但 Playground policy 强制 side effects dry-run，并在 report / audit / cost 中标记 Playground source。

## 变动文件清单

- `SliceAIKit/Sources/SliceCore/ExecutionRunPolicy.swift`
- `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift`
- `SliceAIKit/Sources/SliceCore/TriggerSource.swift`
- `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`
- `SliceAIKit/Sources/Orchestration/Telemetry/CostRecord.swift`
- `SliceAIKit/Sources/Orchestration/Telemetry/CostAccounting.swift`
- `SliceAIKit/Sources/Orchestration/Engine/FlowContext.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+PromptPipeline.swift`
- `SliceAIKit/Tests/SliceCoreTests/ExecutionRunPolicyTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ExecutionSeedTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/TriggerSourceTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/InvocationReportTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/CostAccountingTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-28-phase-3-task-1-run-policy-telemetry-foundation.md`

## 测试记录

- Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'SliceCoreTests.ExecutionRunPolicyTests|SliceCoreTests.ExecutionSeedTests'` 失败，符合预期；缺少 `ExecutionRunPolicy`、`TriggerSource.playground`、`ExecutionSeed.runPolicy` 和 `ExecutionSeed.effectiveRunPolicy`。
- Green：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'SliceCoreTests.ExecutionRunPolicyTests|SliceCoreTests.ExecutionSeedTests|SliceCoreTests.TriggerSourceTests'` 通过，15 tests，0 failures。
- Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'OrchestrationTests.InvocationReportTests|OrchestrationTests.CostAccountingTests'` 失败，符合预期；缺少 `InvocationFlag.playground` 与 `CostRecord.source`。
- Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'OrchestrationTests.ExecutionEngineTests/test_execute_playgroundRunPolicyMarksReportAndCostSource'` 失败，符合预期；新增 ExecutionEngine 回归测试同样暴露缺少 `InvocationFlag.playground` 与 `CostRecord.source`。
- Green：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'OrchestrationTests.InvocationReportTests|OrchestrationTests.CostAccountingTests'` 通过，19 tests，0 failures。
- Green：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'OrchestrationTests.ExecutionEngineTests/test_execute_playgroundRunPolicyMarksReportAndCostSource'` 通过，1 test，0 failures。
- Final focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'SliceCoreTests.ExecutionRunPolicyTests|SliceCoreTests.ExecutionSeedTests|OrchestrationTests.InvocationReportTests|OrchestrationTests.CostAccountingTests|OrchestrationTests.ExecutionEngineTests'` 通过，51 tests，0 failures。
- Whitespace：`git diff --check` 通过，无输出。
