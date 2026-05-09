# Phase 1 M3 Task 14 · Streamable HTTP Transport

## 任务背景

Task 13 已提供首方 `web-search-summarize` Agent tool，并通过 Brave Search MCP allowlist 暴露默认 Agent 入口。当前生产 MCP client 仍只真正支持 stdio，`.streamableHTTP` 在 `RoutingMCPClient` 中 fail-fast。本任务要补齐 MCP Streamable HTTP transport，使远程 MCP server 能通过同一个 `MCPClientProtocol` 被 AgentExecutor 使用，同时继续拒绝 deprecated `.sse`。

## 官方规范核对

本任务实现对齐 MCP **2025-06-18** transport 规范：每个 JSON-RPC message 通过 HTTP POST 发送；POST 请求需要 `Accept: application/json, text/event-stream`；请求响应可以是 `application/json` 单个 JSON-RPC response，也可以是 `text/event-stream` 的 SSE 流；初始化响应可返回 `Mcp-Session-Id`，后续请求必须携带；后续 HTTP 请求还应携带 `MCP-Protocol-Version: 2025-06-18`。

2026-05-09 查询到 MCP draft 已增加 `Mcp-Method` / `Mcp-Name` 标准请求头，但当前代码中的 stdio initialize 仍使用 `protocolVersion: "2025-06-18"`，Phase 1 计划也只要求 2025-06-18 header set。本任务不纳入 draft header standardization，避免协议版本和实现范围错位。

## 当前计划差异

Phase plan 的方向适合继续：新增 `StreamableHTTPMCPClient`，更新 `RoutingMCPClient` 和 `AppContainer`，用 URLProtocol stub 先写红灯测试。需要补充两点实现边界：

1. 安全校验放在 client descriptor 使用入口和 `MCPServerValidation` 配置入口：`.streamableHTTP` 必须有 URL 和 host；`http` scheme 只允许 localhost / 127.0.0.1 / ::1；远程必须使用显式 HTTPS URL。
2. 不实现 deprecated SSE fallback probe，也不新增 `LegacySSEMCPClient`。`.sse` 继续明确返回 unsupported transport。

## 实施方案

1. 按 TDD 新增 `StreamableHTTPMCPClientTests`，先覆盖 initialize header、session id 后续携带、JSON response、SSE response、descriptor URL 安全校验。
2. 更新 `RoutingMCPClientTests`，把 `.streamableHTTP` 从 unsupported 改为路由到注入的 HTTP client，同时保留 `.sse` unsupported 断言。
3. 运行 focused tests 确认红灯，预期失败原因为 `StreamableHTTPMCPClient` 缺失和 routing 仍拒绝 `.streamableHTTP`。
4. 实现 `StreamableHTTPMCPClient`：
   - lazy initialize per server；
   - `tools(for:)` 走 initialize 后 `tools/list`，并缓存 tool descriptors；
   - `call(ref:args:)` 走 initialize、确保 tool list 后发送 `tools/call`；
   - 支持 `application/json` 和 `text/event-stream` 两种响应；
   - 将 HTTP 状态错误、URL 缺失、JSON-RPC error、decode 失败映射到既有 `MCPClientError`。
5. 更新 `RoutingMCPClient`，`.streamableHTTP` 仅在注入 transport client 后转发；`.sse` 继续 unsupported。
6. 更新 `AppContainer.makeMCPRuntime`，生产环境构造并注入 `StreamableHTTPMCPClient`。
7. 跑 focused tests、Capabilities 回归、全量 SwiftPM、targeted lint、`git diff --check`、App Debug build。
8. 提交实现后按用户要求运行 `claude-review-loop`。

## ToDoList

- [x] 创建 Task 14 任务文档并登记 Task_history。
- [x] 编写 Streamable HTTP transport 红灯测试。
- [x] 编写 RoutingMCPClient 红灯测试。
- [x] 运行 focused tests 确认 red。
- [x] 实现 `StreamableHTTPMCPClient`。
- [x] 更新 `RoutingMCPClient` 和 `AppContainer` wiring。
- [x] 补充 `MCPServerValidation` 配置入口测试与实现。
- [x] 运行 focused tests、回归测试、targeted lint、App Debug build。
- [x] 更新 README、Task 详情和 Task_history。
- [ ] 提交 commit。
- [ ] 运行 `claude-review-loop` 并记录结果。

## 变动文件（计划）

- `README.md`：记录 Task 14 变更和验证结果。
- `SliceAIKit/Sources/Capabilities/MCP/StreamableHTTPMCPClient.swift`：新增 Streamable HTTP MCP client。
- `SliceAIKit/Sources/Capabilities/MCP/RoutingMCPClient.swift`：让 `.streamableHTTP` 路由到注入 client，继续拒绝 `.sse`。
- `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift`：允许 HTTPS / 本机 HTTP 的 `.streamableHTTP` 配置入口，拒绝缺 URL、缺 host 和非本机明文 HTTP。
- `SliceAIApp/AppContainer.swift`：生产 wiring 注入 Streamable HTTP client。
- `SliceAIKit/Tests/CapabilitiesTests/StreamableHTTPMCPClientTests.swift`：新增 transport 行为测试。
- `SliceAIKit/Tests/CapabilitiesTests/RoutingMCPClientTests.swift`：更新 routing 行为测试。
- `SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift`：新增 Streamable HTTP 配置校验测试。
- `docs/Task_history.md`：登记 Task 14。
- `docs/Task-detail/2026-05-09-phase-1-m3-task-14-streamable-http-transport.md`：记录任务过程与验证结果。

## 测试计划

- `cd SliceAIKit && swift test --filter CapabilitiesTests.StreamableHTTPMCPClientTests`
- `cd SliceAIKit && swift test --filter CapabilitiesTests.RoutingMCPClientTests`
- `cd SliceAIKit && swift test --filter CapabilitiesTests`
- `cd SliceAIKit && swift test`
- `git diff --check`
- `swiftlint lint --strict <Task 14 touched Swift files>`
- `swiftlint lint --strict`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

## 测试结果

- `cd SliceAIKit && swift test --filter CapabilitiesTests.StreamableHTTPMCPClientTests`：通过，6 tests。
- `cd SliceAIKit && swift test --filter CapabilitiesTests.RoutingMCPClientTests`：通过，4 tests。
- `cd SliceAIKit && swift test --filter CapabilitiesTests.MCPServerStoreTests`：通过，16 tests。
- `cd SliceAIKit && swift test --filter CapabilitiesTests`：通过，90 tests。
- `cd SliceAIKit && swift test`：通过，726 tests。
- `git diff --check`：通过。
- touched Swift files targeted `swiftlint lint --strict`：通过，0 violations。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过。
- `swiftlint lint --strict`：失败，13 个既有历史违规，阻塞文件包括 `MCPServersPage.swift`、`StdioMCPClient.swift`、`MCPDiagnosticLog.swift`、`ClaudeDesktopMCPImporter.swift`、`MCPServerStore.swift`、`PersistentPermissionGrantStore.swift`、`PermissionBroker.swift`、`AppPermissionConsentPresenter.swift`。这些文件的违规并非 Task 14 新增，本任务只记录不扩大重构范围。

## 代码修改逻辑

`StreamableHTTPMCPClient` 采用 actor 管理 per-server session state：首次 `tools(for:)` 或 `call(ref:args:)` 时校验 URL，single-flight 执行 initialize，保存 `Mcp-Session-Id` 和 negotiated `protocolVersion`，再发送 `notifications/initialized`。后续请求统一走 HTTP POST，并在 header 中携带 `MCP-Protocol-Version` 和可选 `Mcp-Session-Id`。

`tools/list` 只在每个 session 内执行一次并缓存 canonical `MCPToolDescriptor`，避免重复拉取；`tools/call` 先确保工具已出现在缓存列表中，再发送 `name` 与结构化 `arguments`。HTTP response 按 `Content-Type` 分支：`application/json` 直接解 `MCPJSONRPCResponse`，`text/event-stream` 则从 SSE `data:` payload 中找到匹配 request id 的 JSON-RPC response。

`RoutingMCPClient` 只负责 transport 分发：`.stdio` 仍委托 stdio client，`.streamableHTTP` 委托新 HTTP client，`.sse` / `.websocket` 继续 fail-fast。`AppContainer` 只在 composition root 新增 HTTP client 实例并注入 routing client，不改变 AgentExecutor 或 ExecutionEngine 的调用契约。

`MCPServerValidation` 从“远程 transport 全拒绝”收敛为更精确的 URL 策略：`.streamableHTTP` 允许 HTTPS 和本机明文 HTTP，拒绝缺 URL、缺 host、非本机明文 HTTP；deprecated `.sse` 仍不作为兼容入口，避免把旧 SSE 当作 Streamable HTTP fallback。

## Self-review

- 实现范围保持在 Task 14：没有引入 Legacy SSE client，也没有实现 draft `Mcp-Method` / `Mcp-Name` header，避免协议版本错位。
- 新 client 的日志只记录 server id 且使用 private privacy，不写入 URL、payload 或 response body。
- URLSession 默认 redirect 策略暂未额外收紧；当前安全边界覆盖 descriptor/store 入口，后续若要禁止 HTTPS -> HTTP redirect downgrade，应独立建任务增加 delegate / redirect policy。
- 全仓 SwiftLint 仍有历史债务；Task 14 touched source 已通过 targeted lint。
