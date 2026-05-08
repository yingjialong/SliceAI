# Phase 1 M3 Task 11 · AgentExecutor ReAct Loop

## 任务背景

M3 Task 10 已完成 `ChatToolRequest`、`ChatStreamEvent` 与 OpenAI-compatible `streamToolChat(request:)`，但 `.agent` ToolKind 仍在 `ExecutionEngine` 中走 M2 stub。Task 11 的目标是在 Orchestration 层实现真实 Agent ReAct loop：模型发起 tool call，执行链校验 MCP allowlist、走 `PermissionBroker`、调用 `MCPClient`，再把 tool result 作为 `role: .tool` 消息回填给模型，直到模型输出最终答案或达到停止条件。

这个任务必须保持 UI 边界干净：`AgentExecutor` 只产出 `ExecutionEvent`，不直接操作 ResultPanel；`ExecutionEngine` 仍负责把 LLM chunk 交给 `OutputDispatcher`。

## 当前计划差异

Phase 1 plan 中给出的 `AgentExecutor` 构造参数只有 `ProviderResolverProtocol`、`MCPClientProtocol`、`PermissionBrokerProtocol` 和 `mcpDescriptors`。但当前代码中 `ProviderResolverProtocol` 只负责把 `ProviderSelection` 解析为 `Provider` 配置，真正创建可调用的 `LLMProvider` 需要 `KeychainAccessing` 与 `LLMProviderFactory`，这两个依赖目前只由 `PromptExecutor` 持有。

因此本任务采用最小架构调整：`AgentExecutor` 显式注入 `KeychainAccessing` 与 `LLMProviderFactory`，复用 `PromptExecutor` 的 provider preflight、keychain 读取和模型选择语义。否则无法合法调用 Task 10 新增的 `LLMProvider.streamToolChat(request:)`。

## 实施方案

1. 按 TDD 先新增 `AgentExecutorTests` 与 `MockToolCallingLLMProvider`，覆盖 allowlist、broker、MCP 成功/错误、invalid arguments、schema 透传、消息顺序和文本 delta。
2. 扩展 `ExecutionEvent` 的 tool-call lifecycle：`toolCallProposed` 增加 UI `UUID`，新增 denied/error 事件。
3. 新增 `AgentPromptBuilder`，集中渲染 agent system/user messages 和上下文摘要，避免 loop 主流程拼模板膨胀。
4. 新增 `AgentExecutor` actor，按单轮 LLM stream → assemble tool calls → sequential tool execution → append tool messages → 下一轮 LLM stream 的顺序执行。
5. 在 `ExecutionEngine` 中把 `.agent` 路由接到 `AgentExecutor`，保留 `.pipeline` 为 not implemented。
6. 更新 AppContainer wiring，让生产路径使用同一 `mcpDescriptors`、`keychain` 与 `llmProviderFactory`。
7. 运行 focused tests、ExecutionEngine 回归、全量必要验证，并在 Task 完成后运行 `claude-review-loop`。

## ToDoList

- [x] 创建 Task 11 任务文档并登记 Task_history。
- [x] 编写 AgentExecutor 红灯测试和 MockToolCallingLLMProvider。
- [x] 运行 AgentExecutor 测试确认 red。
- [x] 实现 ExecutionEvent tool-call lifecycle 扩展。
- [x] 实现 AgentPromptBuilder。
- [x] 实现 AgentExecutor ReAct loop。
- [x] 将 `.agent` 接入 ExecutionEngine 与 AppContainer。
- [x] 运行 focused tests 与回归测试。
- [x] 更新任务文档的变动文件、代码修改逻辑、测试结果。
- [x] 运行 `git diff --check`、targeted lint、App Debug build。
- [x] 提交 commit。
- [x] 运行 `claude-review-loop` 并记录结果。

## 变动文件

- `SliceAIKit/Sources/Orchestration/Events/ExecutionEvent.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCatalog.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+TurnAssembly.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+PromptPipeline.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+AgentPipeline.swift`
- `SliceAIApp/AppContainer.swift`
- `SliceAIApp/ExecutionEventConsumer.swift`
- `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Helpers/MockToolCallingLLMProvider.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEventTests.swift`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-08-phase-1-m3-task-11-agentexecutor-react-loop.md`

## 代码修改逻辑

1. `ExecutionEvent` 增加 agent 工具调用生命周期事件：`toolCallProposed` 携带 UI `UUID` 与参数摘要，新增 `toolCallDenied` / `toolCallError`，让 engine 和 App consumer 能区分批准、拒绝、执行成功与错误。
2. `AgentPromptBuilder` 负责把 `ResolvedExecutionContext` 与 `ContextBag` 渲染成 agent 初始 `system` / `user` 消息；上下文摘要统一经过 `Redaction.scrub`，非文本上下文只暴露短摘要，避免把渲染逻辑塞进执行循环。
3. `AgentExecutor` 实现 ReAct loop：先复用 `ProviderResolver` + `KeychainAccessing` + `LLMProviderFactory` 创建真实 provider，再把 MCP allowlist 解析为 `ChatTool` catalog，随后按 `LLM stream -> assemble tool calls -> permission broker -> MCP call -> append tool messages -> next turn` 执行。
4. 工具执行保持 fail-closed：allowlist、descriptor 缺失、重复函数名、非法参数都在调用 broker/MCP 前失败；broker 拒绝、MCP 抛错、MCP `isError=true` 都转换为 tool result 消息回填模型，同时发出对应生命周期事件。
5. `ExecutionEngine` 仅在存在 `AgentExecutor` 时把 `.agent` 接入真实执行链；没有注入 executor 时保留旧 stub 行为，降低测试与迁移风险。`.pipeline` 仍保持 not implemented，避免扩大本任务范围。
6. `ExecutionEngine+AgentPipeline` 复用现有 `OutputDispatcher` 单写路径处理 `.llmChunk`，把 agent 最终内容纳入 cost accounting 的输出估算；当前 input token 仍为 `0`，后续如果 provider 暴露 usage 再补精确统计。
7. `AppContainer` 在生产路径注入 `AgentExecutor`，复用现有 MCP descriptor provider、routing MCP client、permission broker、keychain 和 provider factory；`ExecutionEventConsumer` 先记录 tool lifecycle 日志，ResultPanel 可视化留给 Task 12。
8. Claude review Round 1 后修正 catalog 与 stop condition 边界：LLM function namespace 只注册 allowlist 内工具，available refs 单独用于存在性校验；重复 MCP server id 改为可恢复配置错误；当前不支持的 `.maxStepsReached` fail-closed，避免配置静默生效失败。

## 测试计划

- `cd SliceAIKit && swift test --filter OrchestrationTests.AgentExecutorTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests`
- `cd SliceAIKit && swift test`
- `git diff --check`
- `swiftlint lint --strict <Task 11 touched Swift files>`
- `swiftlint lint --strict`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

## 测试结果

- 红灯确认：`cd SliceAIKit && swift test --filter OrchestrationTests.AgentExecutorTests` 编译失败，核心错误为缺少 `AgentExecutor` 类型；测试自身的 Swift 6 `await` autoclosure 写法已修正。
- `cd SliceAIKit && swift test --filter OrchestrationTests.AgentExecutorTests`：通过（16 tests；Claude review 修复后为 19 tests）。
- `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`：通过（19 tests）。
- `cd SliceAIKit && swift test --filter OrchestrationTests`：通过（228 tests；Claude review 修复后为 231 tests）。
- `cd SliceAIKit && swift test`：通过（698 tests；Claude review 修复后为 701 tests）。
- `git diff --check`：通过。
- `swiftlint lint --strict <Task 11 touched Swift files>`：通过（0 violations, 0 serious in 12 files；测试文件未被当前 SwiftLint 配置纳入计数）。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：首次失败，原因是 `ExecutionEventConsumer` 中 `Logger.debug` 的 `OSLogMessage` 被 `+` 拼接；已改为先生成 private `String` detail 后重新构建，复跑通过。
- `swiftlint lint --strict`：失败（13 serious），阻塞点均为既有历史文件：`MCPServersPage.swift`、`StdioMCPClient.swift`、`MCPDiagnosticLog.swift`、`MCPServerStore.swift`、`ClaudeDesktopMCPImporter.swift`、`PersistentPermissionGrantStore.swift`、`PermissionBroker.swift`、`AppPermissionConsentPresenter.swift`。Task 11 新增/修改文件在 targeted lint 中已通过，本任务不扩大修复历史 lint 债务。
- `claude-review-loop`：Round 1 `needs_attention`（1 high、3 medium、1 low）；接受并修复 allowlist catalog 非授权同名冲突、重复 descriptor id trap；部分接受 stopCondition 问题并对 `.maxStepsReached` fail-closed；defer agent MCP audit log 与非协作 MCP cancellation。Round 2 `approve`，`findings: []`。详见 `docs/Task-detail/claude-loop-phase-1-m3-task-11-agentexecutor-react-loop.md`。

## Self-review

已自查的风险与边界：

- **重复 allowlisted tool function name**：当前 `ChatTool` function name 仍直接使用 MCP tool name；如果两个 allowlist 内工具来自不同 server 但同名，`AgentExecutor` 会 fail-closed。非 allowlist 同名工具不再阻断合法多 server agent。
- **usage 统计**：agent pipeline 暂只估算输出 token，input token 为 `0`。这不会影响执行正确性，但 cost accounting 精度低于 prompt pipeline。
- **UI 展示**：App consumer 只记录 tool lifecycle 日志，不改 ResultPanel 状态。原因是 Task 12 明确负责 lifecycle UI，本任务只交付执行链。
- **deferred review follow-ups**：agent MCP tool-call audit log 需要 Task 12+ 结合 audit schema 设计；非协作 MCP cancellation 需要 MCPClient/StdioMCPClient 层统一处理，不能只在 AgentExecutor 做局部 workaround。
