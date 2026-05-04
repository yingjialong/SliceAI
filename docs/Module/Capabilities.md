# Capabilities 模块说明

## 模块定位

`Capabilities` 是 v2 能力边界模块，承载 Phase 1+ 会接入的 MCP、Skill 和本地安全能力。Phase 0 只提供协议、mock 和纯函数安全基础设施，不做真实 MCP stdio / SSE 调用，也不做真实 skill 文件扫描。

## 功能范围

- SecurityKit：`PathSandbox`、`PathSandboxError`。
- MCP：`MCPClientProtocol`、`MockMCPClient`、`MCPCallResult`、`MCPClientError`。
- Skills：`SkillRegistryProtocol`、`MockSkillRegistry`、`Skill`。

## 技术实现

`PathSandbox` 是纯值类型，执行路径规范化和 allowlist / denylist 校验：

1. 展开 `~`。
2. `resolvingSymlinksInPath()` 展开 symlink。
3. `standardizedFileURL` 消除 `..` 等路径段。
4. 硬禁止前缀优先拦截，如 Keychains、`.ssh`、Cookies、`/private/etc`。
5. 按 `.read` / `.write` 角色匹配默认白名单和用户白名单。

MCP 与 Skill 当前以 protocol + mock 的形式存在，目的是让 `Orchestration.ExecutionEngine` 在 Phase 0 就能稳定装配 10 个依赖，并为 Phase 1 / Phase 2 保留清晰替换点。

## 关键接口

| 接口 | 说明 |
|---|---|
| `PathSandbox.normalize(_:role:)` | 规范化并校验路径，返回安全 URL 或抛出 `PathSandboxError`。 |
| `MCPClientProtocol.tools(for:)` | 查询 MCP server 暴露的工具列表。 |
| `MCPClientProtocol.call(ref:args:)` | 调用 MCP tool；Phase 0 mock 可用于主流程测试。 |
| `SkillRegistryProtocol.findSkill(id:)` | 按 id 查询 skill。 |
| `SkillRegistryProtocol.allSkills()` | 列出全部已注册 skill。 |

## 运行逻辑

Phase 0 的生产 App 装配 `MockMCPClient` 和 `MockSkillRegistry`。`.agent` / `.pipeline` 工具在执行引擎中仍返回 not implemented，不会触发真实 MCP 或 Skill 调用。

后续 Phase 1 接入真实 MCP 时，只需提供新的 `MCPClientProtocol` 实现并在 `AppContainer` 替换 mock；Phase 2 接入 Skill 文件扫描时，同样替换 `SkillRegistryProtocol` 实现。`PathSandbox` 会作为文件读取、文件写入和 MCP/Skill 本地路径访问的统一安全入口。

## 代码实现说明

核心源码位于 `SliceAIKit/Sources/Capabilities/`。测试位于 `SliceAIKit/Tests/CapabilitiesTests/`，重点覆盖路径 symlink 展开、硬禁止前缀、读写白名单、mock MCP 和 mock skill registry 行为。
