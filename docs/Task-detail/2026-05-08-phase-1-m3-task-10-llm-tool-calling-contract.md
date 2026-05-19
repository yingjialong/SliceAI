# Phase 1 M3 Task 10 · LLM Tool Calling Contract

## 任务背景

Phase 1 M1 已完成 MCP 配置、stdio client 和 Settings MCP Servers 页面，M2 已完成 ContextProvider、PermissionBroker consent boundary 与 AppContainer 生产 wiring。当前 `.agent` / `.pipeline` 仍保持 stub，这是正确的 M2 完成状态。

M3 的目标是跑通真实 Agent Tool。Task 10 是 M3 的第一步：先把 SliceCore / LLMProviders 的 OpenAI-compatible tool calling 数据契约和流式解析补齐，为后续 `AgentExecutor` 提供稳定输入输出边界。如果跳过此任务直接写 AgentExecutor，会导致 agent loop 私自拼 OpenAI wire shape，破坏现有 provider 抽象。

## 实施方案

1. 以 `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md` 的 M3 Task 10 为执行依据；本任务只做 LLM tool calling contract，不实现 AgentExecutor、不改 ResultPanel 工具调用 UI、不新增 `web-search-summarize`。
2. 实施前先复核 OpenAI 官方 tool calling / streaming 文档，确认当前 Chat Completions tool call delta wire shape；SliceAI 仍保持 OpenAI-compatible 抽象，不绑定某一家扩展字段。
3. 按 TDD 先补 `ChatTypesTests`、`OpenAIDTOsTests`、`OpenAICompatibleProviderTests` 和 SSE fixture，确认红灯。
4. 在 `SliceCore` 增加 `ChatTool`、`ChatToolChoice`、`ChatToolRequest`、`ChatStreamEvent`、`ChatToolCall`、`ChatToolCallDelta`，并扩展 `ChatMessage` 支持 assistant tool calls 与 tool result message。
5. 在 `LLMProvider` 增加 `streamToolChat(request:)`，保持现有 prompt-only `stream(request:)` 行为不变，避免回归四个内置 prompt tool。
6. 在 `LLMProviders` 的 OpenAI-compatible DTO 层编码 `tools` / `tool_choice`，解码 streaming tool call deltas，并把模型输出的 arguments raw string 保留到 SliceCore 类型。
7. 运行 focused tests 和必要回归，更新本任务文档测试结果后提交。

## ToDoList

- [x] 同步 Phase 1 implementation plan 到当前 feature worktree。
- [x] 创建 Task 10 任务文档并登记 Task_history。
- [x] 复核 OpenAI 官方 tool calling / streaming 文档，并把关键 wire shape 约束落实到测试。
- [x] 编写 Task 10 红灯测试与 SSE fixture。
- [x] 运行指定测试确认 red。
- [x] 实现 SliceCore tool calling 类型与 `LLMProvider.streamToolChat(request:)` 协议。
- [x] 实现 OpenAI-compatible DTO 编码 / 解码与 provider streaming 转换。
- [x] 运行 focused tests 与 LLMProviders / PromptExecutor / ExecutionEngine 回归。
- [x] 更新任务文档的变动文件、代码修改逻辑、测试结果。
- [x] 运行 `git diff --check`、touched Swift files targeted lint、App Debug build。
- [x] 提交 commit。
- [x] 走 `claude-review-loop` 评审；Round 1 approve，无阻断项。

## 变动文件

- `SliceAIKit/Sources/SliceCore/ChatTypes.swift`
- `SliceAIKit/Sources/SliceCore/LLMProvider.swift`
- `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift`
- `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift`
- `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`
- `SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift`
- `SliceAIKit/Tests/LLMProvidersTests/OpenAIDTOsTests.swift`
- `SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift`
- `SliceAIKit/Tests/LLMProvidersTests/Fixtures/openai_chat_tool_call.sse`
- `docs/Task-detail/2026-05-08-phase-1-m3-task-10-llm-tool-calling-contract.md`
- `docs/Task_history.md`

## 代码修改逻辑

- `ChatMessage.content` 从 `String` 放宽为 `String?`，新增 `toolCallID` 与 `toolCalls` 字段，并保留旧的 `init(role:content:)`，避免破坏 PromptExecutor 和既有测试调用点。
- `ChatTool` 在领域层用 `name` / `description` / `inputSchema` 表达，但 Codable wire shape 编码为 OpenAI-compatible `{"type":"function","function":{...}}`。这样 `AgentExecutor` 后续只传 MCP tool schema，不需要拼 provider JSON。
- `ChatToolRequest` 新增 `tools` 与 `toolChoice`，编码为 `tools` / `tool_choice`；`temperature` 和 `max_tokens` 继续沿用现有可选省略规则。
- `ChatToolCall` 保留 `argumentsRaw`，并尽量解析为 `MCPJSONValue.Object`；解析失败时 `arguments` 为 nil，留给 Task 11 的 AgentExecutor 做 invalid-arguments 分支处理。
- `LLMProvider` 新增 `streamToolChat(request:)`。协议扩展提供默认 fail-fast 实现，避免未实现 tool calling 的未来 provider 静默走 prompt-only 路径；生产 `OpenAICompatibleProvider` 覆盖该方法。
- `OpenAIDTOs` 增加 `delta.tool_calls` 解码结构，按 OpenAI streaming 语义支持同一 `index` 的多片 arguments delta。
- `OpenAICompatibleProvider` 复用原 chat completions endpoint、Authorization、SSE decoder 和 429 一次重试策略；tool calling 路径只替换请求类型与解码输出，文本 delta 映射为 `.textDelta`，工具调用 delta 映射为 `.toolCallDelta`，finish_reason 映射为 `.finished`。
- `PromptExecutor` 的 input token 估算改为按 `message.content?.count ?? 0` 累加，兼容 tool calling 消息把 content 设为 nil 的新模型。

## 测试计划

- `cd SliceAIKit && swift test --filter SliceCoreTests.ChatTypesTests`
- `cd SliceAIKit && swift test --filter LLMProvidersTests.OpenAIDTOsTests`
- `cd SliceAIKit && swift test --filter LLMProvidersTests.OpenAICompatibleProviderTests`
- `cd SliceAIKit && swift test --filter LLMProvidersTests`
- `git diff --check`

## 测试结果

- 红灯确认：`cd SliceAIKit && swift test --filter SliceCoreTests.ChatTypesTests` 初次失败，核心错误为缺少 `ChatToolRequest`、`ChatTool`、`ChatStreamEvent`、`ChatToolCallDelta`、`streamToolChat(request:)` 和 `OpenAIStreamDelta.toolCalls`。
- `cd SliceAIKit && swift test --filter SliceCoreTests.ChatTypesTests`：通过（8 tests）。
- `cd SliceAIKit && swift test --filter LLMProvidersTests.OpenAIDTOsTests`：通过（3 tests）。
- `cd SliceAIKit && swift test --filter LLMProvidersTests.OpenAICompatibleProviderTests`：通过（10 tests）。
- `cd SliceAIKit && swift test --filter LLMProvidersTests`：通过（21 tests）。
- `cd SliceAIKit && swift test --filter OrchestrationTests.PromptExecutorTests`：通过（21 tests）。
- `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`：通过（18 tests）。
- `cd SliceAIKit && swift test`：通过（681 tests）。注：一次全量重跑曾出现 1 个未稳定复现的失败；随后用输出过滤定位时 681 tests 全部通过，未发现可复现失败。
- `git diff --check`：通过（无输出）。
- `swiftlint lint --strict <本次触及 Swift 文件>`：通过（0 violations / 0 serious）。
- `swiftlint lint --strict`（全仓库）：未通过，当前报 16 个 serious violation，集中在 M1/M2 历史文件（如 `MCPServersPage.swift`、`StdioMCPClient.swift`、`AppContainer.swift`、`AppPermissionConsentPresenter.swift` 等）的 file length / function body / trailing comma / line length；本次新增的 `OpenAICompatibleProvider` type body 超限已通过拆同文件 extension 修复。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过（BUILD SUCCEEDED）。
- `claude-review-loop` Round 1：approve，`findings: []`，mutation check `mutation_detected: false`。

## Self-review

- Task 10 边界只覆盖 LLM tool calling contract，不提前实现 AgentExecutor 或 UI。
- 保持 KISS：新增一个 provider-agnostic tool calling stream API，而不是让 Orchestration 拼接 provider-specific JSON。
- 保持现有 prompt stream API，降低对四个内置 prompt tool 的回归风险。
- 后续 Task 11 需要复用本任务产出的 `ChatTool.inputSchema`、`ChatToolCall.argumentsRaw` 和 `role: .tool` 消息，不应另建并行数据模型。
