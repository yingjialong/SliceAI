# MCPClient 模块

## 模块职责

MCPClient 模块位于 `SliceAIKit/Sources/Capabilities/MCP/`，负责把 SliceCore 的 MCP 数据契约落到真实传输层。它不决定 Agent loop，也不决定权限 UI；它只做三件事：

- 读取并校验本地 `mcp.json`。
- 通过 stdio 或 Streamable HTTP 完成 MCP JSON-RPC `initialize`、`tools/list`、`tools/call`。
- 向 `AgentExecutor` 暴露统一的 `MCPClientProtocol`，让上层不直接关心传输类型。

生产路径由 `SliceAIApp/AppContainer.swift` 创建：

- `MCPServerStore(appSupport/mcp.json)` 作为 descriptor 来源。
- `StdioMCPClient` 处理本地子进程 server。
- `StreamableHTTPMCPClient` 处理远程 Streamable HTTP server。
- `RoutingMCPClient` 作为唯一 facade 注入 `ExecutionEngine` 和 `AgentExecutor`。

## 配置与存储

默认配置路径：

```text
~/Library/Application Support/SliceAI/mcp.json
```

文件结构由 `MCPServerConfiguration` 定义：

- `schemaVersion`：当前为 `1`。
- `servers`：`MCPDescriptor` 列表。
- `runnerConfirmations`：用户对 `npx` / `uvx` / `node` / `python` / `python3` 等 runner 的 typed confirmation。

`MCPServerStore` 的读写都执行 fail-closed 校验；`snapshot()` 返回按 `id` 排序后的 descriptor 列表，供运行时稳定解析。

主要校验规则：

- 拒绝不支持的 `schemaVersion`。
- 拒绝重复 server id。
- 拒绝 `.unknown` provenance。
- stdio server 必须有非空 command，且不能带 `url`。
- 裸 runner 命令需要用户 typed confirmation。
- 绝对 command path 不能包含父目录跳转，也不能把真实 runner 藏在 `env` / shell wrapper 下。
- Streamable HTTP 只允许 HTTPS，或本机 `localhost` / `127.0.0.1` / `::1` 的明文 HTTP。
- `.sse` 和 `.websocket` 仅保留解码兼容，不允许新建、保存或路由连接。

## Claude Desktop 导入

`ClaudeDesktopMCPImporter` 读取 Claude Desktop 的 `mcpServers` JSON，并转换为 SliceCore canonical `MCPDescriptor`。

当前导入边界：

- 接受 stdio `command` / `args` / `env`。
- 导入结果按 id 排序。
- 调用方必须提供明确 provenance；`.unknown` 被拒绝。
- 看到 `url` 会拒绝导入，避免把未知远程配置静默当成本地 stdio。

导入后的配置仍会在 `MCPServerStore.save` 时再次校验。

## 协议契约

`MCPClientProtocol` 只暴露两个方法：

- `tools(for:) -> [MCPToolDescriptor]`
- `call(ref:args:) -> MCPCallResult`

所有 MCP 领域类型都来自 SliceCore：

- `MCPDescriptor`
- `MCPToolDescriptor`
- `MCPToolRef`
- `MCPJSONValue.Object`
- `MCPCallResult`

这保证了 Settings、AgentExecutor、PermissionGraph、ResultPanel 使用同一套 canonical 类型，不需要传输层私有 DTO 适配。

## stdio 生命周期

`StdioMCPClient` 是 actor，每个 server id 维护一个独立 `Process` session。

生命周期：

1. 首次 `tools(for:)` 或 `call(ref:args:)` 时 lazy 启动子进程。
2. 将系统环境变量与 descriptor `env` 合并后传给 `Process.environment`。
3. 通过 stdin/stdout 发送 newline-delimited JSON-RPC。
4. 依次发送 `initialize`、`notifications/initialized`、`tools/list`。
5. `tools/list` 结果缓存到 session，后续 tool call 复用。
6. `tools/call` 使用结构化 `MCPJSONValue.Object` 传参。
7. 请求超时或协议错误会 teardown 当前 session，下一次调用重新启动。
8. 默认 5 分钟 idle timeout 后自动停止子进程。

并发边界：

- `sessionStartTasks` 对同一 server 做 single-flight，避免并发首次调用重复启动进程。
- `StdioMCPResponseRouter` 按 JSON-RPC id 路由 stdout response。
- `StdioMCPStderrLineBuffer` 对 stderr 做行缓冲，完整行进入诊断日志前统一脱敏。

## Streamable HTTP 生命周期

`StreamableHTTPMCPClient` 也是 actor，每个 server id 维护一个 HTTP session 状态。

生命周期：

1. 校验 descriptor URL：HTTPS 直接允许，本机 HTTP 允许，其他明文 HTTP 拒绝。
2. 通过 HTTP POST 发送 JSON-RPC。
3. `initialize` 使用 MCP protocol version `2025-06-18`。
4. 请求头包含 `Accept: application/json, text/event-stream` 和 `Content-Type: application/json`。
5. server 返回 `Mcp-Session-Id` 后，后续 request / notification 携带该 session id 和 `MCP-Protocol-Version`。
6. 支持 `application/json` 和 `text/event-stream` response。
7. 默认 URLSession 禁止 redirect，避免 session header 或 JSON-RPC payload 泄露到新地址。
8. 已有 session 的 404 会触发一次 reset + retry；再次 404 才转换为 transport failure。

旧 `.sse` 不做 fallback probe，也不新增 legacy client。

## 权限与 provenance

MCPClient 不直接做权限决策。权限链路在 Orchestration 中完成：

- Tool 的 `agent.mcpAllowlist` 决定 LLM 可见和可调用的 MCP tool。
- `PermissionGraph` 将 MCP ref 推导为 `.mcp(server:tools:)`。
- `PermissionBroker` 对 MCP 调用执行运行期 gate。
- `.mcp` 权限不可缓存，session / persistent store 都会拒绝记录；即使 presenter 返回 session approval，也只对本次 invocation 生效。

Provenance 只影响 UX 文案与来源展示，不降低 MCP 调用确认下限。

## 诊断与脱敏

`MCPDiagnosticLog` 是可注入的异步日志 sink，默认禁用。入口统一脱敏：

- Bearer token
- OpenAI `sk-` 风格密钥
- `Authorization` header
- `Cookie` header

`MCPClientError.developerContext` 对 server id、tool name、transport reason、protocol error message 等用户或服务端 payload 统一输出 `<redacted>`。

## E2E 矩阵

Task 16 当前本机环境缺少 SliceAI `mcp.json`、Brave API key、Postgres 只读连接串、SQLite 测试 DB 路径和安全 filesystem 目录，因此真实 5-server E2E 未执行，已记录为 release 前置条件。

| Server | 推荐入口 | Task 16 状态 |
|---|---|---|
| filesystem | `npx -y @modelcontextprotocol/server-filesystem "$SLICEAI_E2E_FILESYSTEM_DIR"` | 包可解析；缺 SliceAI 配置和目录 |
| postgres | `npx -y @modelcontextprotocol/server-postgres "$SLICEAI_E2E_POSTGRES_URL"` | 包可解析；缺连接串，本机无 `psql` |
| brave-search | `BRAVE_API_KEY=... npx -y @modelcontextprotocol/server-brave-search` | 包可解析但 deprecated；缺 API key |
| git | `uvx --from mcp-server-git mcp-server-git --repository "$SLICEAI_E2E_GIT_REPO"` | uvx 入口可启动；缺 SliceAI 配置和 repo env |
| sqlite | `uvx --from mcp-server-sqlite mcp-server-sqlite --db-path "$SLICEAI_E2E_SQLITE_DB"` | uvx 入口可启动；缺 SliceAI 配置和 DB 路径 |

只读 checklist 脚本：

```bash
bash scripts/phase1-mcp-e2e.sh
```
