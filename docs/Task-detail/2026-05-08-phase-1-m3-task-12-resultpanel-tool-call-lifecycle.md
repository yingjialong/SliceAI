# Phase 1 M3 Task 12 · ResultPanel Tool Call Lifecycle

## 任务背景

M3 Task 11 已让 `.agent` 走真实 `AgentExecutor`，并产出稳定的 tool-call lifecycle events：`toolCallProposed`、`toolCallApproved`、`toolCallResult`、`toolCallDenied`、`toolCallError`。但当前 `ExecutionEventConsumer` 只把这些事件写入日志，ResultPanel 仍只显示最终 Markdown 文本或终态错误，用户无法看到 Agent 正在调用哪个 MCP tool、是否被批准、是否失败。

Task 12 的目标是把 tool-call lifecycle 以轻量状态行展示在 ResultPanel 中，同时保持现有单一文本写入契约：`.llmChunk` 仍只能通过 `OutputDispatcher -> WindowSink -> ResultPanel.append` 写正文，`ExecutionEventConsumer` 只更新工具调用状态，不直接 append LLM 文本。

## 当前计划差异

Phase 1 plan 指定修改 `ResultContentView.swift`、`ResultPanel.swift` 与 `ExecutionEventConsumer.swift`，并提示“Add a pure state model in Windowing if none exists”。当前 `ResultPanel.swift` 已有 389 行，继续塞入状态模型和转换逻辑会增加文件膨胀风险。因此本任务采用更小边界：新增 `SliceAIKit/Sources/Windowing/ResultToolCallState.swift` 放纯状态模型，`ResultPanel.swift` 只暴露薄 API 并委托 view model。

## 实施方案

1. 先新增 `WindowingTests.ResultPanelToolCallStateTests` 红灯测试，覆盖 proposed → approved → result、denied、error、重复 proposed 更新，以及 reset 清空。
2. 新增 `ResultToolCallState` 与 `ResultToolCallStateStore`，集中处理状态 upsert/transition，避免 SwiftUI View 里散落数组更新逻辑。
3. `ResultViewModel` 持有 `@Published toolCalls`，`reset` 清空状态；`ResultPanel` 暴露 `showToolCallProposed/Approved/Result/Denied/Error` 等 MainActor API。
4. `ResultContentView` 在正文上方渲染 compact lifecycle rows；不遮挡 Markdown 正文，不改变 `.llmChunk` 输出路径。
5. `ExecutionEventConsumer` 把 Task 11 events 映射到 ResultPanel API；保留日志，但不再只是日志。
6. 按 TDD 逐步跑红灯、实现、focused tests、回归测试、targeted lint、App Debug build。
7. 完成后提交，并按用户要求运行 `claude-review-loop`。

## ToDoList

- [x] 创建 Task 12 任务文档并登记 Task_history。
- [x] 编写 ResultPanel tool-call state 红灯测试。
- [x] 运行测试确认 red。
- [x] 实现 ResultToolCallState / store。
- [x] 接入 ResultViewModel 与 ResultPanel API。
- [x] 更新 ResultContentView 渲染 lifecycle rows。
- [x] 更新 ExecutionEventConsumer 映射 tool-call events。
- [x] 运行 focused tests、回归测试、targeted lint、App Debug build。
- [x] 更新任务文档的变动文件、代码修改逻辑、测试结果。
- [x] 提交 commit。
- [x] 运行 `claude-review-loop` 并记录结果。

## 变动文件

- `SliceAIKit/Sources/Windowing/ResultToolCallState.swift`：新增 ResultPanel 工具调用生命周期纯状态模型。
- `SliceAIKit/Tests/WindowingTests/ResultPanelToolCallStateTests.swift`：新增状态模型红绿测试。
- `SliceAIKit/Sources/Windowing/ResultPanel.swift`：新增 ResultPanel tool-call lifecycle API，并让 `ResultViewModel` 发布 `toolCalls`。
- `SliceAIKit/Sources/Windowing/ResultContentView.swift`：新增 compact lifecycle rows 渲染。
- `SliceAIApp/ExecutionEventConsumer.swift`：将 tool-call events 映射到 ResultPanel API，同时保留日志。
- `docs/Task_history.md`：登记 Task 12。
- `docs/Task-detail/2026-05-08-phase-1-m3-task-12-resultpanel-tool-call-lifecycle.md`：记录任务过程与验证结果。
- `docs/Task-detail/claude-loop-phase-1-m3-task-12-resultpanel-tool-call-lifecycle.md`：记录 Claude review loop goal contract、Round 1 approve 和收敛结论。

## 代码修改逻辑

1. `ResultToolCallState` 只表示 UI 需要的轻量字段：`id/title/detail/status`，`Status` 覆盖 proposed、approved、result、denied、error 五个阶段。
2. `ResultToolCallStateStore` 负责同一 id 的 upsert 和状态转换：重复 proposed 更新原行；approved/result/denied/error 更新同一行；乱序终态事件会创建兜底行，避免 UI 静默丢事件。
3. `ResultViewModel` 持有 `ResultToolCallStateStore` 与 `@Published toolCalls`，`reset` 清空旧 invocation 的 rows，避免下一次打开窗口看到旧 Agent 状态。
4. `ResultPanel` 暴露 `showToolCallProposed/Approved/Result/Denied/Error` 薄 API，保持所有 UI 状态写入仍在 `@MainActor`。
5. `ResultContentView` 在进度条和正文之间展示 compact rows，未嵌套 `StreamingMarkdownView` 的内部 ScrollView，不改变 Markdown 正文渲染。
6. `ExecutionEventConsumer` 对 tool-call events 先记录现有 OSLog，再同步 ResultPanel lifecycle rows；`.llmChunk` 仍只记录长度，不直接 append，正文写入继续由 `OutputDispatcher -> WindowSink -> ResultPanel.append` 单一路径负责。

## 测试计划

- `cd SliceAIKit && swift test --filter WindowingTests.ResultPanelToolCallStateTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEventTests`
- `cd SliceAIKit && swift test --filter WindowingTests`
- `cd SliceAIKit && swift test`
- `git diff --check`
- `swiftlint lint --strict <Task 12 touched Swift files>`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

## 测试结果

- Red：`cd SliceAIKit && swift test --filter WindowingTests.ResultPanelToolCallStateTests` 初次失败，原因是 `ResultToolCallStateStore` / `ResultToolCallState` 尚未实现，符合 TDD 预期。
- Green：`cd SliceAIKit && swift test --filter WindowingTests.ResultPanelToolCallStateTests` 通过，5 tests。
- Green：`cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEventTests` 通过，2 tests。
- Green：`cd SliceAIKit && swift test --filter WindowingTests` 通过，9 tests。
- Green：`cd SliceAIKit && swift test` 通过，706 tests。
- Green：`git diff --check` 通过。
- Green：`swiftlint lint --strict SliceAIKit/Sources/Windowing/ResultToolCallState.swift SliceAIKit/Sources/Windowing/ResultContentView.swift SliceAIKit/Sources/Windowing/ResultPanel.swift SliceAIApp/ExecutionEventConsumer.swift SliceAIKit/Tests/WindowingTests/ResultPanelToolCallStateTests.swift` 通过，0 violations。测试文件被当前 SwiftLint 配置排除，实际 lint 了 4 个源文件。
- Known historical blocker：`swiftlint lint --strict` 全仓仍失败，13 个既有违规均不在本任务新增/修改文件中，主要位于 `MCPServersPage.swift`、`StdioMCPClient.swift`、`MCPDiagnosticLog.swift`、`PersistentPermissionGrantStore.swift`、`MCPServerStore.swift`、`ClaudeDesktopMCPImporter.swift`、`PermissionBroker.swift`、`AppPermissionConsentPresenter.swift`。
- Green：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过。
- Claude review loop：Round 1 使用 `branch --base HEAD~1` 范围审查实现 commit，结果 `verdict: "approve"`、`findings: []`；`mutation-check.json` 显示 `mutation_detected: false`。

## Self-review

已检查本任务没有改变 `.llmChunk` 的单一正文写入契约，tool-call lifecycle 只作为 ResultPanel 状态行展示。UI 方案没有嵌套滚动容器，避免和现有 Markdown ScrollView 冲突；状态模型单独成文件，避免继续膨胀 `ResultPanel.swift`。Claude review loop 已 Round 1 approve，无需额外修复。
