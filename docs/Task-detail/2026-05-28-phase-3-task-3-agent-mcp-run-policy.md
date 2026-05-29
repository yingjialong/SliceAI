# 2026-05-28 · Phase 3 Task 3 Agent MCP Run Policy

## 背景

用户要求作为 Phase 3 ToolEditor v2 + Prompt Playground MVP 的实现 worker，执行 Task 3：把 Task 1 的 `ExecutionRunPolicy` 继续传入 AgentExecutor，并按 Playground MCP 开关控制 Agent MCP tool call。

本任务承接 Task 1 的 run policy / telemetry 基础和 Task 2 的 Playground 输出派发器；只处理 Agent MCP policy，不实现 SettingsUI、Playground runner 或 ToolEditor draft state。

## 任务目标

- `AgentExecutor.run(...)` 支持接收 `ExecutionRunPolicy`，默认保持生产行为。
- Playground 禁用 MCP 时，allowlist 和参数校验通过后的 MCP call 被拒绝，并返回 tool message 给模型继续推理。
- Playground 禁用 MCP 时，不调用 `PermissionBroker`，不调用真实 MCP client，也不消耗 Agent MCP 调用预算。
- Playground 显式允许 MCP 时，仍走现有 allowlist 和 `PermissionBroker`，并以非 dry-run 方式 gate。
- `ExecutionEngine` 的 Agent pipeline 把 `FlowContext.runPolicy` 传给 `AgentExecutor`。

## ToDoList

- [x] Step 1：写 Agent MCP policy 失败测试。
- [x] Step 2：运行 focused test 确认红灯。
- [x] Step 3：实现 `AgentExecutor.run(...)` run policy 参数并贯穿 turn context。
- [x] Step 4：在 MCP tool-call 链路中执行 disabled / real policy gate。
- [x] Step 5：从 `ExecutionEngine+AgentPipeline` 传递 run policy。
- [x] Step 6：运行 Task 3 focused tests。
- [x] Step 7：提交 `feat: gate playground mcp tool calls`。

## 设计边界

- KISS：不新增额外执行器或策略抽象，只把已有 `ExecutionRunPolicy` 传入现有 Agent tool-call 链路。
- 安全：禁用 MCP 的判断放在 allowlist / 参数校验之后、调用预算记录之前，避免未授权工具被误报为 Playground 禁用，也避免禁用调用污染预算统计。
- 兼容：`AgentExecutor.run(...)` 的 `runPolicy` 参数带默认值，旧调用保持生产语义。
- 防御：`callAllowedTool` 内保留第二道 guard，防止后续调用路径绕过 `processOneToolCall` 的禁用判断。

## 实施记录

1. `AgentExecutor.run(...)` 新增默认参数 `runPolicy: ExecutionRunPolicy = .production(isDryRun: false)`，保持旧调用的生产语义。
2. `AgentToolTurnProcessingContext` 新增 `runPolicy`，并在每一轮 assistant tool-call processing 时传入。
3. `processToolCalls` / `processOneToolCall` / `callAllowedTool` 贯穿 `ExecutionRunPolicy`。
4. `processOneToolCall` 在 allowlist 与参数校验通过后、预算 `skipReason` 与 `recordExecution` 之前判断 `.disabled`，产出 `.toolCallDenied` 并回填 tool message 给模型继续推理。
5. `callAllowedTool` 增加防御 guard；正常路径下 disabled MCP 已在上游返回，若未来调用路径绕过上游 guard，也不会进入 broker 或 MCP client。
6. `gateMCP` 从 run policy 推导 `isDryRun`：生产和 Playground 显式允许 MCP 时均为 `false`；disabled 模式理论上不会进入 broker。
7. `ExecutionEngine+AgentPipeline` 把 `FlowContext.runPolicy` 传给 `AgentExecutor`。

## 实现结果

已完成 Task 3 范围。Playground 默认禁用 MCP 时，Agent MCP tool call 会在本地受控拒绝，不触发 `PermissionBroker`、不调用 MCP client、不消耗 total / per-turn / per-tool / duplicate 预算；模型仍收到 `role: .tool` 消息，可以继续输出最终答案。Playground 显式允许 MCP 时，继续复用现有 allowlist 与 PermissionBroker one-time gate，并以真实非 dry-run 方式进入 broker。

## 变动文件清单

- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+AgentPipeline.swift`
- `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-28-phase-3-task-3-agent-mcp-run-policy.md`

## 测试记录

- Red cache cleanup：首次运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests` 被旧 `.build` 缓存阻塞，错误为 Swift 6.2.3 编译产物不能被 Swift 6.3.2 导入；随后执行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift package --package-path SliceAIKit clean` 清理缓存。
- Red：重新运行 `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests` 失败，符合预期；缺少 `AgentExecutor.run(..., runPolicy:)`。
- Green：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests` 通过，38 tests，0 failures。
- Final focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter 'OrchestrationTests.AgentExecutorTests|OrchestrationTests.ExecutionEngineTests'` 通过，59 tests，0 failures。
