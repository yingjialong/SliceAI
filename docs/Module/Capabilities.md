# Capabilities 模块说明

## 模块定位

`Capabilities` 是 v2 能力边界模块，承载 Phase 1+ 会接入的 MCP、Skill 和本地安全能力。Phase 0 只提供协议、mock 和纯函数安全基础设施，不做真实 MCP stdio / SSE 调用，也不做真实 skill 文件扫描。

## 功能范围

- SecurityKit：`PathSandbox`、`PathSandboxError`。
- MCP：`MCPClientProtocol`、`MockMCPClient`、`MCPClientError`、`MCPServerStore`、`MCPServerValidation`、`ClaudeDesktopMCPImporter`；server descriptor、tool descriptor、工具引用、结构化参数与调用结果均复用 SliceCore 的 canonical 类型。
- Skills：`SkillRegistryProtocol`、`MockSkillRegistry`、`Skill`。

## 技术实现

`PathSandbox` 是纯值类型，执行路径规范化和 allowlist / denylist 校验：

1. 展开 `~`。
2. `resolvingSymlinksInPath()` 展开 symlink。
3. `standardizedFileURL` 消除 `..` 等路径段。
4. 硬禁止前缀优先拦截，如 Keychains、`.ssh`、Cookies、`/private/etc`。
5. 按 `.read` / `.write` 角色匹配默认白名单和用户白名单。

MCP 与 Skill 当前以 protocol + mock 的形式存在，目的是让 `Orchestration.ExecutionEngine` 在 Phase 0 就能稳定装配 10 个依赖，并为 Phase 1 / Phase 2 保留清晰替换点。M1 Task 2 已将 `MCPClientProtocol` 收敛到 SliceCore canonical contract：`tools(for:)` 返回 `MCPToolDescriptor`，`call(ref:args:)` 接收 `MCPJSONValue.Object`。

M1 Task 3 新增本地 MCP server 配置入口：`MCPServerStore` 默认读写 `~/Library/Application Support/SliceAI/mcp.json`，`save/load/snapshot` 都通过 `MCPServerValidation` 做 fail-closed 校验。当前只允许本地 stdio：不支持的 schemaVersion、重复 server id、`.unknown` provenance、空 command、相对 command、未知 bare command、未确认 allowlisted runner、`env` / shell wrapper command、远程 transport 和 websocket 新建写入都会被拒绝；allowlisted runner 即使以绝对路径出现，也会按大小写无关的 basename 归一到 runner 家族后要求 typed confirmation，覆盖 `python3.11`、`node22` 这类版本化解释器路径。`ClaudeDesktopMCPImporter` 只解析 Claude Desktop `mcpServers` stdio 配置并应用调用方传入 provenance；M4 前远程 URL 配置不导入。当前仍不包含真实 MCP transport/client，也不包含 AgentExecutor tool calling。

## 关键接口

| 接口 | 说明 |
|---|---|
| `PathSandbox.normalize(_:role:)` | 规范化并校验路径，返回安全 URL 或抛出 `PathSandboxError`。 |
| `MCPClientProtocol.tools(for:)` | 使用 SliceCore `MCPDescriptor` 查询 MCP server 暴露的 `MCPToolDescriptor` 列表。 |
| `MCPClientProtocol.call(ref:args:)` | 使用 `MCPJSONValue.Object` 调用 MCP tool；Phase 0/1 mock 可用于主流程测试。 |
| `MCPServerStore.save(_:)` | 校验并写入本地 `mcp.json`。 |
| `MCPServerStore.snapshot()` | 读取、校验并按 `id` 排序返回 runtime wiring 使用的 descriptors。 |
| `MCPServerValidation.validate(_:)` | 对 MCP server 配置执行 fail-closed 校验。 |
| `ClaudeDesktopMCPImporter.importDescriptors(from:provenance:)` | 导入 Claude Desktop stdio `mcpServers` 配置。 |
| `SkillRegistryProtocol.findSkill(id:)` | 按 id 查询 skill。 |
| `SkillRegistryProtocol.allSkills()` | 列出全部已注册 skill。 |

## 运行逻辑

Phase 0 的生产 App 装配 `MockMCPClient` 和 `MockSkillRegistry`。`.agent` / `.pipeline` 工具在执行引擎中仍返回 not implemented，不会触发真实 MCP 或 Skill 调用。

后续 Phase 1 接入真实 MCP stdio client 时，runtime 可通过 `MCPServerStore.snapshot()` 获取已校验 descriptors，再注入新的 `MCPClientProtocol` 实现。Phase 2 接入 Skill 文件扫描时，同样替换 `SkillRegistryProtocol` 实现。`PathSandbox` 会作为文件读取、文件写入和 MCP/Skill 本地路径访问的统一安全入口。

## 代码实现说明

核心源码位于 `SliceAIKit/Sources/Capabilities/`。测试位于 `SliceAIKit/Tests/CapabilitiesTests/`，重点覆盖路径 symlink 展开、硬禁止前缀、读写白名单、mock MCP 和 mock skill registry 行为。
