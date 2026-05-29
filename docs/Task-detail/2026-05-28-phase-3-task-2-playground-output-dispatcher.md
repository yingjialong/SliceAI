# 2026-05-28 · Phase 3 Task 2 Playground Output Dispatcher

## 背景

用户要求作为 Phase 3 ToolEditor v2 + Prompt Playground MVP 的实现 worker，执行 Task 2：新增 Settings Playground 专用输出派发器，用于收集 preview 输出状态，避免试跑打开生产 ResultPanel / BubblePanel 或触发文件、替换、剪贴板等系统副作用。

本任务承接 Task 1 的 `ExecutionRunPolicy` 与 telemetry 基础，只实现 plan 中 Task 2 明确范围，不接入 SettingsUI、不实现 Playground runner，也不调整 Agent MCP 策略。

## 任务目标

- 新增 `PlaygroundOutputDispatcher`，遵守 `OutputDispatcherProtocol`。
- 对 `.window` 以及 `.file` / `.replace` / `.bubble` / `.structured` / `.silent` 统一记录 preview snapshot。
- 只保存 begin / chunk / finish / fail 状态，不写生产 UI、文件、前台 App 选区或剪贴板。
- 失败状态仅保存 `SliceError.userMessage`，避免把 provider payload 或敏感上下文写入 preview 快照。

## ToDoList

- [x] Step 1：写 Playground output dispatcher 失败测试。
- [x] Step 2：运行 focused test 确认红灯。
- [x] Step 3：实现 PlaygroundOutputDispatcher。
- [x] Step 4：运行 focused output tests。
- [x] Step 5：提交 `feat: add playground output dispatcher`。

## 设计边界

- KISS：使用单个 actor 内存字典按 `invocationId` 保存快照，不引入额外 sink 抽象。
- 安全：Playground dispatcher 不持有生产 sink，也不调用 `OutputDispatcher`，从类型层面避免真实 UI / 文件 / replace 副作用。
- 兼容：实现三参数 `handle(chunk:mode:invocationId:)` 以满足协议 required 方法，同时提供 lifecycle context API 供后续 Playground runner 使用。
- 日志：本任务不新增自由日志；snapshot 只记录 chunk / final text / 用户可读错误。

## 实施记录

1. 新增 `PlaygroundOutputSnapshot`，按 `invocationId` 保存输出模式、streaming chunks、final text 和用户可读失败信息。
2. 新增 `PlaygroundOutputDispatcher` actor，实现 `OutputDispatcherProtocol` 的 begin / chunk / finish / fail 生命周期。
3. `begin` 会重置当前 invocation 的 preview 快照；`handle` 只追加 chunk；`finish` 只记录 final text；`fail` 只记录 `SliceError.userMessage`。
4. `ensureSnapshot` 允许调用方跳过 begin 后仍能记录 chunk / finish / fail，避免失败收口时因生命周期顺序不完整而丢失 preview 状态。

## 实现结果

已完成 Task 2 范围。Playground 输出派发器现在能在内存中收集 streaming chunks、final text 和失败错误文案；`.file` / `.replace` / `.bubble` / `.structured` / `.silent` 在 finish 阶段不会调用生产输出依赖，因此不会触发文件写入、前台选区替换、真实气泡、剪贴板或系统副作用。

## 变动文件清单

- `SliceAIKit/Sources/Orchestration/Output/PlaygroundOutputDispatcher.swift`
- `SliceAIKit/Tests/OrchestrationTests/PlaygroundOutputDispatcherTests.swift`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-28-phase-3-task-2-playground-output-dispatcher.md`

## 测试记录

- Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter OrchestrationTests.PlaygroundOutputDispatcherTests` 失败，符合预期；缺少 `PlaygroundOutputDispatcher`。
- Green：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'OrchestrationTests.PlaygroundOutputDispatcherTests|OrchestrationTests.OutputLifecycleTests|OrchestrationTests.OutputDispatcherFallbackTests'` 通过，14 tests，0 failures。
- Whitespace：`git diff --check` 通过，无输出。
