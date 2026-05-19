# Phase 1 M1 Task 4 · Stdio MCP JSON-RPC Client

## 任务背景

M1 Task 1-3 已经建立 SliceCore MCP JSON/value contract、Capabilities MCP client canonical contract，以及本地 `mcp.json` store / Claude Desktop stdio import / fail-closed validation。Task 4 需要把 `MCPClientProtocol` 的真实 stdio 实现补齐，让后续 Settings 测试连接、AgentExecutor tool calling 和 M1 filesystem / brave-search 验收有可运行的传输主干。

## 现有问题

- Capabilities 目前只有 `MockMCPClient`，没有真实 stdio JSON-RPC client。
- 缺少 MCP JSON-RPC request / response / error framing，无法区分 transport protocol error 与 tool execution error。
- 缺少 idle timeout、stderr diagnostic redaction 和 process lifecycle 测试。
- 后续 AgentExecutor 不应直接 switch `MCPTransport`，需要先有 `RoutingMCPClient` 作为唯一 facade。

## 实施方案

1. 使用 `superpowers:subagent-driven-development`，派发 GPT-5.5 worker 实现 Task 4，并要求 TDD 红绿闭环。
2. 先写 `MCPJSONRPCTests`、`StdioMCPClientTests`、`RoutingMCPClientTests` 和 deterministic Node fixture，确认缺失类型 / 行为红灯。
3. 新增 `MCPJSONRPC` framing、`MCPDiagnosticLog`、`StdioMCPClient` actor 和 `RoutingMCPClient` actor。
4. 保持 KISS：M1 stdio client 只支持 newline-delimited JSON-RPC、initialize、notifications/initialized、tools/list、tools/call、idle timeout 和 stderr redaction；不实现 Streamable HTTP / SSE 真实远程 client。
5. 进行 spec compliance review，再进行 code quality review；review 发现的问题必须修复并复审。
6. 运行目标测试、`CapabilitiesTests`、全量 `swift test`、`git diff --check` 后提交。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 派发 implementer worker。
- [x] 编写失败测试并确认红灯。
- [x] 实现 MCP JSON-RPC framing。
- [x] 实现 stdio MCP client。
- [x] 实现 RoutingMCPClient。
- [x] 运行目标测试、CapabilitiesTests、全量测试和 diff 检查。
- [x] 修复 spec compliance review 发现的 call-first 启动顺序缺口。
- [x] 修复 spec re-review 发现的 tools/list title 保真缺口。
- [x] 修复 code quality review 发现的 stdio 阻塞读取、坏 session 复用与 stderr 分块泄漏问题。
- [x] code quality review 复审通过。
- [x] 追加 Claude review loop，并修复 idle timeout generation、并发首次启动 single-flight、pipe chunk FIFO 顺序问题。
- [x] 更新文档完成态并提交。

## 计划约束

- Task 4 范围只覆盖 M1 stdio 主干，不实现 M4 的 Streamable HTTP / legacy SSE 真实 transport。
- `RoutingMCPClient` 在 M1 对 `.streamableHTTP` / `.sse` / `.websocket` 返回 unsupported transport，不做远程 fallback。
- stderr diagnostic 必须脱敏 bearer、`sk-`、Authorization、Cookie 等 secret-like 内容。
- 所有新增 Swift 函数必须有函数级中文注释；复杂分支保留必要中文注释。

## 变动文件清单

- `SliceAIKit/Sources/Capabilities/MCP/MCPJSONRPC.swift`
- `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift`
- `SliceAIKit/Sources/Capabilities/MCP/RoutingMCPClient.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPDiagnosticLog.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- `SliceAIKit/Tests/CapabilitiesTests/MCPJSONRPCTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/StdioMCPClientTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/RoutingMCPClientTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/Fixtures/stdio-mcp-fixture.js`
- `SliceAIKit/Package.swift`
- `README.md`
- `docs/Module/Capabilities.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-07-phase-1-m1-task-4-stdio-mcp-json-rpc-client.md`

## 代码修改逻辑

1. `MCPJSONRPC.swift` 定义 JSON-RPC request / response / error DTO，并新增 `MCPToolsListResult` / `MCPToolListItem` / `MCPInitializeResult`。`MCPToolListItem` 解码 MCP tool 的 optional `title`，转换为 `MCPToolDescriptor` 时优先使用 `title`，缺失时回退到 `name`。`MCPJSONRPCResponse.resultOrThrow()` 只把 JSON-RPC error object 转为 `.protocolError`；`MCPCallResult.isError == true` 保持为正常 result。
2. `MCPClientError` 新增 `.protocolError(code:message:)` 和 `.unsupportedTransport(_:)`，并保持 developerContext 对用户/服务端 payload 脱敏。
3. `MCPDiagnosticLog` 提供默认禁用 sink 和异步日志回调，入口统一脱敏 bearer、`sk-`、Authorization、Cookie，避免 stderr 泄露 secret。
4. `StdioMCPClient` 使用 actor 隔离进程状态：首次调用 lazy 启动 `Process`，连接 stdin/stdout/stderr pipe；启动后发送 `initialize`，再发 `notifications/initialized`。`tools(for:)` 和 `call(ref:args:)` 都会通过 `listToolsIfNeeded(session:)` 确保当前 session 已发送 `tools/list`；如果首次公开入口是 `call(ref:args:)`，实际顺序仍是 `initialize` → `notifications/initialized` → `tools/list` → `tools/call`。`tools/list` 结果按 session 缓存，避免同一进程内重复列工具。
5. stdout 使用 newline-delimited JSON-RPC；`tools/list` 的 `inputSchema` 保留为 `MCPJSONValue.Object`；`tools/call` 按 ref.server 从 descriptors provider 解析 descriptor。
6. stdout 从旧的 actor 内同步逐字节 `readData` 改为 `FileHandle.readabilityHandler` + FIFO `AsyncStream<Data>` consumer + `StdioMCPResponseRouter`：handler 只 yield bytes，单一 reader task 按顺序把 NDJSON chunk 送入 router，router 按换行和 JSON-RPC id 唤醒 pending request；`requestTimeoutNanoseconds` 默认 30 秒，测试可注入短 timeout。request timeout、协议错误、transport/decoding 失败会 teardown 当前 session，避免继续复用状态未知的连接；`MCPCallResult.isError == true` 仍作为正常 result 返回。
7. 同一 server 的首次并发请求通过 `sessionStartTasks` 做 single-flight，避免 actor reentrancy 在 initialize 完成前重复拉起 stdio 子进程；initialize 失败时 session 不登记到 `sessions`，失败路径会关闭 handler/pipe、terminate 子进程，并写入脱敏诊断日志。后续 `tools/list` / `tools/call` 的协议、传输或解码错误也会丢弃当前 session，下一次调用重新 lazy start。
8. stderr diagnostic 从 chunk 级拆分改为 FIFO `AsyncStream<Data>` consumer + `StdioMCPStderrLineBuffer` 行缓冲：完整行后再调用 `MCPDiagnosticLog.record`，EOF/teardown flush 剩余片段，并设置 16KB 最大缓冲兜底；诊断 message 中 server 标识固定为 `<redacted>`，不拼接用户自定义 descriptor id。
9. idle timeout 采用可取消 `Task` + actor 内 generation token，每次请求成功后重新安排；到期前会校验 generation 仍是当前调度，避免旧 timeout task 在取消后误停 in-flight session。
10. `RoutingMCPClient` 作为唯一 facade：stdio 委托到注入的 stdio client；`.streamableHTTP` / `.sse` / `.websocket` 在 M4 前直接抛 `.unsupportedTransport`，不实现远程 fallback。
11. `CapabilitiesTests` 增加 deterministic Node fixture，并在 `Package.swift` 中把 `Fixtures` 作为 test resources 复制。fixture 后续扩展了“未先 tools/list 时 tools/call 返回 JSON-RPC error”、首次 initialize 失败、延迟 tools/list、stderr 分块输出等状态门，用于锁定 review 修复。

## 测试用例与结果

- 红灯确认：
  - `swift test --filter CapabilitiesTests.MCPJSONRPCTests`：首次运行因缺少 `MCPJSONRPCRequest` / `MCPJSONRPCResponse` / `MCPToolsListResult` / `.protocolError` 等类型失败。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests`：首次运行因缺少 `StdioMCPClient` / `MCPDiagnosticLog` / `RoutingMCPClient` 等类型失败。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests/test_stdioClient_callFirstPerformsToolsListBeforeToolCall`：review 修复前失败，fixture 返回 `protocolError(code: -32000, message: "tools/list required before tools/call")`，证明 `call(ref:args:)` 首次入口漏发 `tools/list`。
  - `swift test --filter CapabilitiesTests.MCPJSONRPCTests/test_jsonRPCResponse_decodesToolList`：re-review 修复前失败，`MCPToolDescriptor.title` 实际为 `"echo"` 而不是 tools/list 提供的 `"Echo Query"`，证明 title 未保真。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests/test_stdioClient_initializeFailureDiscardsSessionBeforeRetry`：code quality review 修复前失败，第二次调用复用首次 initialize 失败后的坏 session，fixture 返回 `protocolError(code: -32002, message: "initialize required before tools/list")`。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests/test_stdioClient_buffersStderrLinesBeforeRedactionAndRedactsServerID`：code quality review 修复前失败，日志包含跨 chunk 的 `secret` 片段和原始 server id。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests/test_stdioClient_requestTimeoutTearsDownSessionAndAllowsActorToContinue`：code quality review 修复前先因 `requestTimeoutNanoseconds` 注入参数缺失编译失败；补齐 timeout 机制后锁定为 60ms 内抛 `request_timeout` 并写入 teardown 诊断。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests/test_stdioClient_cancelledIdleTimeoutCannotStopInFlightRequest`：Claude review 修复前失败，多次出现 `stdio response router closed` / `stdio session stopped`，证明旧 idle timeout task 会误停 in-flight request。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests/test_stdioClient_concurrentFirstUseSharesSingleSessionStart`：用于锁定同 server 并发首次请求只执行一次 initialize，避免重复拉起 stdio 子进程。
- 目标测试：
  - `swift test --filter CapabilitiesTests.MCPJSONRPCTests`：通过，3 tests。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests`：通过，10 tests。
  - `swift test --filter CapabilitiesTests.RoutingMCPClientTests`：通过，2 tests。
  - `swift test --filter CapabilitiesTests.MCPClientProtocolTests`：通过，12 tests。
- 范围测试：
  - `swift test --filter CapabilitiesTests`：通过，59 tests。
  - `swift test`：通过，622 tests。
  - `git diff --check`：通过。

## Review 结果

- Spec compliance review：发现真实缺口：当首次公开入口是 `call(ref:args:)` 时，旧实现只执行 `initialize` / `notifications/initialized`，随后直接 `tools/call`，没有满足 Task 4 要求的 `tools/list` 前置顺序。已通过红灯测试 `test_stdioClient_callFirstPerformsToolsListBeforeToolCall` 复现，并修复为 call-first 也强制先 `tools/list`。
- Spec re-review：发现真实缺口：`MCPToolListItem` 未解码 MCP 2025-06-18 tool optional `title`，导致 canonical `MCPToolDescriptor.title` 总是使用 `name`。已通过红灯测试复现，并修复为 `title ?? name`；fixture 也返回 `title: "Echo Query"`，覆盖 stdio 端到端路径。
- Code quality review：返回 `CHANGES_REQUESTED`，发现三类真实问题并已按 TDD 修复：1) actor 内同步阻塞读取 stdout，现改为 readability handler + response router + request timeout；2) initialize / 后续请求失败后会复用坏 session，现失败路径统一 teardown 并删除 session；3) stderr chunk 级脱敏存在跨 chunk 泄漏窗口且日志暴露原始 server id，现改为行缓冲、EOF flush 和 `server=<redacted>`。
- Code quality re-review：`APPROVED`。复审确认 stdout 不再阻塞 actor、request timeout 会清理 pending waiter 并触发 session teardown、initialize / request 失败不会复用坏 session、`MCPCallResult.isError == true` 仍作为正常结果、stderr 行缓冲与 server id 脱敏符合当前 Task 4 质量要求。
- Claude review loop：共 3 轮，最终 `verdict: "approve"` / `findings: []`。Round 1 接受并修复 idle timeout 旧 task 误停 in-flight session 的 generation 缺口；Round 2 接受并修复同 server 并发首次请求重复启动 stdio 进程、stdout/stderr per-chunk unstructured Task 可能乱序的问题；Round 3 无新增 material finding。
