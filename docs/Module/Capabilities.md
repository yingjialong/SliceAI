# Capabilities 模块说明

## 模块定位

`Capabilities` 是 v2 能力边界模块，承载 Phase 1+ 会接入的 MCP、Skill 和本地安全能力。Phase 0 提供协议、mock 和纯函数安全基础设施；Phase 1 M1 已接入真实 stdio MCP JSON-RPC client，但仍不实现 Streamable HTTP / SSE / WebSocket 远程 transport，也不做真实 skill 文件扫描。

## 功能范围

- SecurityKit：`PathSandbox`、`PathSandboxError`。
- MCP：`MCPClientProtocol`、`MockMCPClient`、`StdioMCPClient`、`RoutingMCPClient`、`MCPDiagnosticLog`、`MCPClientError`、`MCPServerStore`、`MCPServerValidation`、`ClaudeDesktopMCPImporter`；server descriptor、tool descriptor、工具引用、结构化参数与调用结果均复用 SliceCore 的 canonical 类型。
- Skills：`SkillRegistryProtocol`、`MockSkillRegistry`、`Skill`。

## 技术实现

`PathSandbox` 是纯值类型，执行路径规范化和 allowlist / denylist 校验：

1. 展开 `~`。
2. `resolvingSymlinksInPath()` 展开 symlink。
3. `standardizedFileURL` 消除 `..` 等路径段。
4. 硬禁止前缀优先拦截，如 Keychains、`.ssh`、Cookies、`/private/etc`。
5. 按 `.read` / `.write` 角色匹配默认白名单和用户白名单。

MCP 与 Skill 当前以 protocol + mock 的形式存在，目的是让 `Orchestration.ExecutionEngine` 在 Phase 0 就能稳定装配 10 个依赖，并为 Phase 1 / Phase 2 保留清晰替换点。M1 Task 2 已将 `MCPClientProtocol` 收敛到 SliceCore canonical contract：`tools(for:)` 返回 `MCPToolDescriptor`，`call(ref:args:)` 接收 `MCPJSONValue.Object`。

M1 Task 3 新增本地 MCP server 配置入口：`MCPServerStore` 默认读写 `~/Library/Application Support/SliceAI/mcp.json`，`save/load/snapshot` 都通过 `MCPServerValidation` 做 fail-closed 校验。当前只允许本地 stdio：不支持的 schemaVersion、重复 server id、`.unknown` provenance、空 command、相对 command、未知 bare command、未确认 allowlisted runner、`env` / shell wrapper command、远程 transport 和 websocket 新建写入都会被拒绝；allowlisted runner 即使以绝对路径出现，也会按大小写无关的 basename 归一到 runner 家族后要求 typed confirmation，覆盖 `python3.11`、`node22` 这类版本化解释器路径。`ClaudeDesktopMCPImporter` 只解析 Claude Desktop `mcpServers` stdio 配置并应用调用方传入 provenance；M4 前远程 URL 配置不导入。

M1 Task 4 新增真实 stdio MCP client：`StdioMCPClient` 是 actor，按首次 `tools(for:)` / `call(ref:args:)` lazy 启动子进程，通过 newline-delimited JSON-RPC 发送 `initialize`、`notifications/initialized`、`tools/list` 和 `tools/call`。`tools/list` 的 `inputSchema` 以 `MCPJSONValue.Object` 透明保留，`tools/call` 的 `isError == true` 作为工具执行结果返回，不抛 JSON-RPC protocol error。stderr 诊断通过 `MCPDiagnosticLog` 统一脱敏，idle timeout 默认 5 分钟并可在测试中注入短时间。`RoutingMCPClient` 是当前 MCP client facade：`.stdio` 委托给 stdio client，`.streamableHTTP` / `.sse` / `.websocket` 在 M4 前返回 unsupported transport；当前仍不包含 AgentExecutor tool calling。

## 关键接口

| 接口 | 说明 |
|---|---|
| `PathSandbox.normalize(_:role:)` | 规范化并校验路径，返回安全 URL 或抛出 `PathSandboxError`。 |
| `MCPClientProtocol.tools(for:)` | 使用 SliceCore `MCPDescriptor` 查询 MCP server 暴露的 `MCPToolDescriptor` 列表。 |
| `MCPClientProtocol.call(ref:args:)` | 使用 `MCPJSONValue.Object` 调用 MCP tool；`MCPCallResult.isError` 表示工具执行错误而非 transport/protocol error。 |
| `StdioMCPClient` | M1 stdio JSON-RPC client，lazy 启动本地进程并执行 initialize / tools/list / tools/call。 |
| `RoutingMCPClient` | MCP client facade，按 transport 委托 stdio 或在 M4 前拒绝远程 transport。 |
| `MCPDiagnosticLog` | stdio stderr / lifecycle 诊断日志 sink，入口统一脱敏敏感片段。 |
| `MCPServerStore.save(_:)` | 校验并写入本地 `mcp.json`。 |
| `MCPServerStore.snapshot()` | 读取、校验并按 `id` 排序返回 runtime wiring 使用的 descriptors。 |
| `MCPServerValidation.validate(_:)` | 对 MCP server 配置执行 fail-closed 校验。 |
| `ClaudeDesktopMCPImporter.importDescriptors(from:provenance:)` | 导入 Claude Desktop stdio `mcpServers` 配置。 |
| `SkillRegistryProtocol.findSkill(id:)` | 按 id 查询 skill。 |
| `SkillRegistryProtocol.allSkills()` | 列出全部已注册 skill。 |

## 运行逻辑

当前生产 App 仍未把真实 MCP 调用接入 `AgentExecutor`；`.agent` / `.pipeline` 工具在执行引擎中仍返回 not implemented，不会触发真实 MCP 或 Skill 调用。M1 的 stdio client 已可作为后续 Settings 测试连接和 AgentExecutor wiring 的底层 transport。

后续 runtime 可通过 `MCPServerStore.snapshot()` 获取已校验 descriptors，再把 `RoutingMCPClient` 作为唯一 MCP facade 注入执行链路。Phase 2 接入 Skill 文件扫描时，同样替换 `SkillRegistryProtocol` 实现。`PathSandbox` 会作为文件读取、文件写入和 MCP/Skill 本地路径访问的统一安全入口。

## 代码实现说明

核心源码位于 `SliceAIKit/Sources/Capabilities/`。测试位于 `SliceAIKit/Tests/CapabilitiesTests/`，重点覆盖路径 symlink 展开、硬禁止前缀、读写白名单、mock MCP 和 mock skill registry 行为。
