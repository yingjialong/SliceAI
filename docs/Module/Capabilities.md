# Capabilities 模块说明

## 模块定位

`Capabilities` 是 v2 能力边界模块，承载 Phase 1+ 会接入的 MCP、Skill、ContextProvider、本地安全能力和跨启动能力状态。Phase 0 提供协议、mock 和纯函数安全基础设施；Phase 1 M1 已接入本地 MCP server store、Claude Desktop stdio importer、真实 stdio MCP JSON-RPC client，并暴露给 SettingsUI 的 MCP Servers 设置页使用。Phase 1 M2 Task 7 已补齐五个核心 ContextProvider；Task 8 新增 persistent permission grant store；Task 9 已由 AppContainer 把真实 provider registry、persistent grant store 和 routing MCP client 接入生产启动路径。Phase 2 Skill Registry MVP 已新增本地 `SKILL.md` parser、directory scanner 和 `LocalSkillRegistry` actor。当前仍不实现 WebSocket 远程 transport；旧 HTTP+SSE 明确弃用，不再支持。

## 功能范围

- SecurityKit：`PathSandbox`、`PathSandboxError`。
- ContextProviders：`SelectionContextProvider`、`AppWindowTitleContextProvider`、`AppURLContextProvider`、`ClipboardCurrentContextProvider`、`FileReadContextProvider`。
- Permissions：`PersistentPermissionGrantStore`。
- MCP：`MCPClientProtocol`、`MockMCPClient`、`StdioMCPClient`、`RoutingMCPClient`、`MCPDiagnosticLog`、`MCPClientError`、`MCPServerStore`、`MCPServerValidation`、`ClaudeDesktopMCPImporter`；server descriptor、tool descriptor、工具引用、结构化参数与调用结果均复用 SliceCore 的 canonical 类型。
- Skills：`SkillRegistryProtocol`、`MockSkillRegistry`、`SkillMarkdownParser`、`SkillDirectoryScanner`、`LocalSkillRegistry`；canonical `Skill` 类型位于 `SliceCore`。

## 技术实现

`PathSandbox` 是纯值类型，执行路径规范化和 allowlist / denylist 校验：

1. 展开 `~`。
2. `resolvingSymlinksInPath()` 展开 symlink。
3. `standardizedFileURL` 消除 `..` 等路径段。
4. 硬禁止前缀优先拦截，如 Keychains、`.ssh`、Cookies、`/private/etc`。
5. 按 `.read` / `.write` 角色匹配默认白名单和用户白名单。

MCP 当前以 protocol + routing client 的形式存在；Skill 以 `SkillRegistryProtocol` 抽象，生产实现为 `LocalSkillRegistry`。M1 Task 2 已将 `MCPClientProtocol` 收敛到 SliceCore canonical contract：`tools(for:)` 返回 `MCPToolDescriptor`，`call(ref:args:)` 接收 `MCPJSONValue.Object`。

M1 Task 3 新增本地 MCP server 配置入口：`MCPServerStore` 默认读写 `~/Library/Application Support/SliceAI/mcp.json`，`save/load/snapshot` 都通过 `MCPServerValidation` 做 fail-closed 校验。当前只允许本地 stdio：不支持的 schemaVersion、重复 server id、`.unknown` provenance、空 command、相对 command、未知 bare command、未确认 allowlisted runner、`env` / shell wrapper command、远程 transport 和 websocket 新建写入都会被拒绝；allowlisted runner 即使以绝对路径出现，也会按大小写无关的 basename 归一到 runner 家族后要求 typed confirmation，覆盖 `python3.11`、`node22` 这类版本化解释器路径。`ClaudeDesktopMCPImporter` 只解析 Claude Desktop `mcpServers` stdio 配置并应用调用方传入 provenance；M4 前远程 URL 配置不导入。

M1 Task 4 新增真实 stdio MCP client：`StdioMCPClient` 是 actor，按首次 `tools(for:)` / `call(ref:args:)` lazy 启动子进程，通过 newline-delimited JSON-RPC 发送 `initialize`、`notifications/initialized`、`tools/list` 和 `tools/call`。`tools/list` 的 `inputSchema` 以 `MCPJSONValue.Object` 透明保留，`tools/call` 的 `isError == true` 作为工具执行结果返回，不抛 JSON-RPC protocol error。stderr 诊断通过 `MCPDiagnosticLog` 统一脱敏，idle timeout 默认 5 分钟并可在测试中注入短时间。`RoutingMCPClient` 是当前 MCP client facade：`.stdio` 委托给 stdio client，`.streamableHTTP` / `.sse` / `.websocket` 在 M4 前返回 unsupported transport；其中 `.sse` 是旧 HTTP+SSE deprecated 值，后续也不实现。M1 Task 5 新增的 `SettingsUI.MCPServersViewModel` 通过 `MCPServerStore` 和 `ClaudeDesktopMCPImporter` 管理配置，并通过注入的 `MCPClientProtocol.tools(for:)` 做 Settings 页工具预览。当前仍不包含 AgentExecutor tool calling。

M2 Task 7 新增五个核心 ContextProvider：

1. `selection` 直接返回 `ExecutionSeed.selection.text`。
2. `app.windowTitle` 返回 `ExecutionSeed.frontApp.windowTitle`，缺失时返回空字符串。
3. `app.url` 返回 `ExecutionSeed.frontApp.url?.absoluteString`，缺失时返回空字符串。
4. `clipboard.current` 读取当前剪贴板文本，静态权限推导为 `.clipboard`，IO 前后检查取消。
5. `file.read` 使用 `args["path"]` 推导 `.fileRead(path:)`，执行时先经 `PathSandbox.normalize(_:role: .read)` 规范化和校验，再按 chunk 读取 UTF-8 文本；默认最大 1 MiB，超限抛固定非敏感 `SliceError.execution(.unknown("file.read.maxBytesExceeded"))`，IO 边界前后和每个 chunk 后检查取消。

M2 Task 8 新增 `PersistentPermissionGrantStore`，默认路径为 `~/Library/Application Support/SliceAI/permission-grants.json`。该 store 只写入 `.persistent` grant；`.session` 由 Orchestration 的 `PermissionGrantStore` 保存在内存中，`.oneTime` 不缓存。存储层会拒绝 `.mcp`、`.network`、`.shellExec`、`.appIntents`，并在读侧校验 schemaVersion、grant scope、permission 一致性和 provenanceTag，避免 Settings、未来导入路径或损坏文件把每次确认权限持久化。

## 关键接口

| 接口 | 说明 |
|---|---|
| `PathSandbox.normalize(_:role:)` | 规范化并校验路径，返回安全 URL 或抛出 `PathSandboxError`。 |
| `PathSandbox.isHardDenied(_:)` | 只做 hard-deny 判定，不检查 allowlist；供 PermissionGraph coverage 在静态闭环阶段拒绝敏感路径声明。 |
| `SelectionContextProvider` | 返回触发 seed 中的当前选区文本。 |
| `AppWindowTitleContextProvider` | 返回前台 app 快照中的窗口标题。 |
| `AppURLContextProvider` | 返回前台 app 快照中的 URL 字符串。 |
| `ClipboardCurrentContextProvider` | 读取当前剪贴板文本；推导 `.clipboard` 权限。 |
| `FileReadContextProvider` | 分块读取 `PathSandbox` 允许的 UTF-8 文本文件；默认 1 MiB 上限；推导 `.fileRead(path:)` 权限。 |
| `PersistentPermissionGrantStore` | 读写 `permission-grants.json`；只持久化 `.persistent` cacheable permission，拒绝 MCP / network / shell / AppIntents。 |
| `MCPClientProtocol.tools(for:)` | 使用 SliceCore `MCPDescriptor` 查询 MCP server 暴露的 `MCPToolDescriptor` 列表。 |
| `MCPClientProtocol.call(ref:args:)` | 使用 `MCPJSONValue.Object` 调用 MCP tool；`MCPCallResult.isError` 表示工具执行错误而非 transport/protocol error。 |
| `StdioMCPClient` | M1 stdio JSON-RPC client，lazy 启动本地进程并执行 initialize / tools/list / tools/call。 |
| `RoutingMCPClient` | MCP client facade，按 transport 委托 stdio 或在 M4 前拒绝远程 transport。 |
| `MCPDiagnosticLog` | stdio stderr / lifecycle 诊断日志 sink，入口统一脱敏敏感片段。 |
| `MCPServerStore.save(_:)` | 校验并写入本地 `mcp.json`。 |
| `MCPServerStore.update(_:)` | 在 store actor 内原子完成 load / mutate / validate / save，供 SettingsUI 避免并发写入丢更新。 |
| `MCPServerStore.snapshot()` | 读取、校验并按 `id` 排序返回 runtime wiring 使用的 descriptors。 |
| `MCPServerValidation.validate(_:)` | 对 MCP server 配置执行 fail-closed 校验。 |
| `ClaudeDesktopMCPImporter.importDescriptors(from:provenance:)` | 导入 Claude Desktop stdio `mcpServers` 配置。 |
| `SkillMarkdownParser.parse(_:directoryName:)` | 解析最小 `SKILL.md` frontmatter / body，并返回可恢复 warning。 |
| `SkillDirectoryScanner.scan(in:)` | 按一层扫描规则发现候选 skill，并拒绝 symlink escape。 |
| `SkillRegistryProtocol.snapshot()` | 返回 sources、skills 和 diagnostics 快照。 |
| `SkillRegistryProtocol.findSkill(id:)` | 按 id 查询 enabled skill。 |
| `SkillRegistryProtocol.loadSkillInstructions(id:)` | 按需加载 enabled skill 的完整 `SKILL.md` body。 |

## 运行逻辑

当前生产 App 已创建 `MCPServerStore(fileURL: appSupport/mcp.json)`、`StdioMCPClient`、`RoutingMCPClient` 和 `LocalSkillRegistry`，并把 routing client 与同一个 skill registry 注入 `ExecutionEngine` / `AgentExecutor` / Settings。M1 的 stdio client 已用于 Settings MCP Servers 页面测试连接，也作为 AgentExecutor tool calling 的底层 transport。

runtime 通过 `MCPServerStore.snapshot()` 获取已校验 descriptors，并把 `RoutingMCPClient` 作为唯一 MCP facade 注入执行链路。Skill runtime 通过 `Configuration.skillSettings` 获取用户 roots，扫描和解析 `SKILL.md` 后供 Settings 与 AgentExecutor 消费。`PathSandbox` 已作为 `file.read` 的真实读取入口，后续也会作为文件写入和 MCP/Skill supporting files 访问的统一安全入口。

`PersistentPermissionGrantStore` 是 Settings-only 的持久授权后端。运行时 `PermissionBroker` 读取 `permission-grants.json` 命中的 persistent grant，但不会在执行过程中写入 `.persistent`；Task 9 已接入真实 AppKit 运行期确认 UI，Settings 写入入口仍留给后续任务。

## 代码实现说明

核心源码位于 `SliceAIKit/Sources/Capabilities/`。测试位于 `SliceAIKit/Tests/CapabilitiesTests/`，重点覆盖路径 symlink 展开、硬禁止前缀、读写白名单、核心 ContextProvider、mock MCP、`SKILL.md` parser、directory scanner 和 local skill registry 行为。
