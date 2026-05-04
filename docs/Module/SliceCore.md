# SliceCore 模块说明

## 模块定位

`SliceCore` 是 SliceAI 的领域层，要求只依赖 Foundation / CoreGraphics 等基础库，不依赖 AppKit、SwiftUI 或具体 UI 实现。它承载 v2 canonical 数据模型、配置 schema、执行输入输出结构、权限模型、错误模型和跨模块协议。

## 功能范围

- 工具模型：`Tool`、`ToolKind`、`PromptTool`、`AgentTool`、`PipelineStep`、`ToolMatcher`、`ToolBudget`。
- Provider 模型：`Provider`、`ProviderKind`、`ProviderCapability`、`ProviderSelection`。
- 配置模型：`Configuration`、`ConfigurationStore`、`DefaultConfiguration`、`ConfigMigratorV1ToV2`、`LegacyConfigV1`。
- 执行上下文：`ExecutionSeed`、`ResolvedExecutionContext`、`SelectionSnapshot`、`AppSnapshot`、`ContextRequest`、`ContextBag`。
- 权限与安全：`Permission`、`Provenance`、`OutputBinding`、`DisplayMode`、`SideEffect`。
- 错误与协议：`SliceError`、`LLMProvider`、`KeychainAccessing`。

## 技术实现

`Tool` 是 v2 后唯一的 canonical 工具类型，采用三态 `ToolKind`：

- `.prompt`：当前 v0.2.0 真实执行路径，包含 system/user prompt、provider selection、temperature、变量表。
- `.agent`：Phase 1 MCP / Agent loop 的数据骨架，当前执行引擎返回 not implemented。
- `.pipeline`：Phase 5 pipeline 的数据骨架，当前执行引擎返回 not implemented。

`ConfigurationStore` 只读写 `config-v2.json`。首次启动时：

1. 如果 `config-v2.json` 存在，直接读取并校验。
2. 如果只有旧 `config.json`，通过 `ConfigMigratorV1ToV2` 迁移生成 v2 配置。
3. 如果两者都不存在，写入 `DefaultConfiguration.initial()`。

旧 `config.json` 是迁移输入，不被 v2 store 覆写；API Key 始终保存在 Keychain，配置文件只保存 `apiKeyRef = "keychain:<provider.id>"`。

## 关键接口

| 接口 | 说明 |
|---|---|
| `ConfigurationStore.current()` | 异步读取当前 v2 配置；内部负责首次迁移 / 默认写盘。 |
| `ConfigurationStore.save(_:)` | 校验并保存 v2 配置。 |
| `SelectionPayload.toExecutionSeed(triggerSource:)` | App 触发层到 v2 执行入口的边界转换。 |
| `LLMProvider.stream(_:)` | LLM 流式输出协议，生产实现由 `LLMProviders` 提供。 |
| `KeychainAccessing` | Keychain 读写协议，供 `PromptExecutor` 读取 API Key。 |
| `SideEffect.inferredPermissions` | D-24 静态权限闭环的基础：副作用可推导出所需权限。 |

## 运行逻辑

App 触发层捕获 `SelectionPayload` 后，调用 `toExecutionSeed` 生成不可变执行种子。后续 `Orchestration.ExecutionEngine` 使用 `Tool` + `ExecutionSeed` 完成权限、上下文、Provider、prompt、输出、审计与成本闭环。

`SliceCore` 本身不发网络、不访问文件系统、不渲染 UI。它只定义稳定的数据结构和协议边界，保证后续 CLI、MCP server 或其他宿主复用同一套领域模型。

## 代码实现说明

核心源码位于 `SliceAIKit/Sources/SliceCore/`。测试位于 `SliceAIKit/Tests/SliceCoreTests/`，覆盖配置迁移、canonical JSON、权限编码、SelectionPayload 到 ExecutionSeed 映射、错误脱敏和默认配置生成。
