# Phase 1 M1 Task 1 · SliceCore MCP JSON Contract

## 任务背景

Phase 1 MCP 上下文能力需要先在 SliceCore 建立稳定的 JSON/value contract。当前 `SideEffect.callMCP` 与 `PipelineStep.mcp` 只能表达 `[String: String]`，无法承载 MCP tool 参数常见的嵌套 object / array / number / bool / null，也缺少 MCP content/result、tool descriptor、streamable HTTP transport 等公共契约。

## 现有问题

- MCP 参数类型过窄，无法表达任意 JSON。
- Swift synthesized enum Codable 容易产出 wrapper JSON，不适合作为公开配置契约。
- MCP content/result 尚未沉入 SliceCore，后续 Capabilities / Orchestration 会缺少共享值类型。
- `websocket` 需要能解码历史/外部配置，但 Phase 1 设置页不应允许新建。
- Review 指出 `embeddedResource` 必须使用 MCP 2025-06-18 的嵌套 `resource` wire shape，`resource_link.name` 在 wire 层必须 required。
- 第二轮 Review 指出 nested `resource` 必须符合 `TextResourceContents | BlobResourceContents` union，`text` / `blob` 必须恰好存在一个。
- 代码质量 Review 指出 audit 落盘的 MCP params 必须按 object key 递归识别 secret-like 字段，否则 plain secret 会泄漏到 jsonl。
- Claude Review Round 1 指出 `MCPCallResult.meta` 必须映射到 MCP Result wire key `_meta`，不能使用 Swift synthesized `meta` key。

## 实施方案

1. 先新增/更新失败测试，覆盖 `MCPJSONValue` transparent raw JSON、string leaf 渲染、脱敏摘要、MCP content/result、transport、`callMCP` 和 `PipelineStep.mcp` 嵌套 JSON 参数。
2. 确认指定测试命令红灯，且失败原因来自缺失类型或旧参数类型。
3. 实现 `MCPJSONValue`，手写 transparent Codable，复用 `PromptTemplate.render` 渲染字符串叶子，提供确定性脱敏摘要。
4. 实现 `MCPContentItem` / `MCPCallResult` / `MCPToolDescriptor`，保持 MCP 风格 discriminator JSON。
5. 将 `SideEffect.callMCP` 与 `PipelineStep.mcp` 参数升级为 `MCPJSONValue.Object`，并更新 `MCPTransport`。
6. 如 SwiftPM 编译因公开类型变化失败，只做等价的最小适配，不提前实现 Task 2 的 MCPClientProtocol 语义。
7. 运行指定测试和 `SliceCoreTests` 编译验证，更新文档并提交 commit。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 编写失败测试。
- [x] 运行红灯测试并记录失败原因。
- [x] 实现 SliceCore MCP JSON/value contract。
- [x] 做公开类型变更的最小编译适配。
- [x] 运行指定测试与 SliceCoreTests。
- [x] 更新 README / 模块文档 / 本任务文档。
- [x] 提交 commit。

## 变动文件清单

- `SliceAIKit/Sources/SliceCore/MCPJSONValue.swift`
- `SliceAIKit/Sources/SliceCore/MCPContentItem.swift`
- `SliceAIKit/Sources/SliceCore/MCPToolDescriptor.swift`
- `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
- `SliceAIKit/Sources/SliceCore/OutputBinding.swift`
- `SliceAIKit/Sources/SliceCore/ToolKind.swift`
- `SliceAIKit/Tests/SliceCoreTests/MCPJSONValueTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/MCPContentItemTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/MCPDescriptorTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/OutputBindingTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- `SliceAIKit/Sources/Orchestration/Telemetry/JSONLAuditLog.swift`
- `SliceAIKit/Tests/CapabilitiesTests/MCPClientProtocolTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/JSONLAuditLogTests.swift`
- `README.md`
- `docs/Module/Capabilities.md`
- `docs/Module/SliceCore.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-06-phase-1-m1-task-1-mcp-json-contract.md`

## 代码修改逻辑

- `MCPJSONValue` 手写 `Codable`，按 nil、Bool、Double、String、Array、Object 顺序透明解码，编码直接输出 raw JSON，避免 `{"string":"..."}` 或 `_0` wrapper。
- `renderingStringLeaves(variables:)` 只递归渲染 `.string` 叶子，复用 `PromptTemplate.render`，数字、布尔、null、数组和对象形状保持不变。
- `redactedSummary(maxCharacters:)` 先递归脱敏 secret-like object key，再用 sorted JSON 输出确定性摘要并截断。
- `MCPContentItem` 使用 MCP `type` discriminator：`text`、`image`、`resource_link`、`resource`；`MCPCallResult` 放在 SliceCore，承载 content、structuredContent、isError、meta。
- `MCPCallResult.meta` 的 Swift 属性名保持 `meta`，但通过显式 `CodingKeys` 映射到 MCP wire key `_meta`，避免 Task 2 真实 client 额外做隐藏翻译。
- `embeddedResource` 的 wire JSON 使用 `{ "type": "resource", "resource": { ... } }`；`resourceLink` 保留 Swift public optional `name`，但 wire decode 缺 `name` 必须失败，wire encode 遇到 `name == nil` 抛 `EncodingError.invalidValue`。
- `embeddedResource` 保留 Swift public optional `text` / `blob`，但 wire decode/encode 强制 `text` / `blob` 恰好一个存在，避免输出或接受非法 MCP resource union。
- `MCPToolDescriptor.inputSchema` 使用 `MCPJSONValue.Object`，只建立契约，不提前接入 AgentExecutor。
- `SideEffect.callMCP` 与 `PipelineStep.mcp` 的参数类型从 `[String: String]` 升级到 `MCPJSONValue.Object`，保持原有单键手写 Codable 外层形状。
- `MCPTransport` 新增 `streamableHTTP = "streamable-http"`，`websocket` 继续可解码，但 `isCreatableInPhase1Settings` 返回 false。
- Capabilities 里删除旧 `MCPCallResult` 定义，协议仍保持 `call(ref:args: [String: String])`，仅复用 SliceCore 的结果值类型，避免提前做 Task 2 协议迁移。
- `JSONLAuditLog` 对 MCP JSON params 递归脱敏字符串叶子，保持旧字符串参数的非敏感值保留语义。
- `JSONLAuditLog` 对 `SideEffect.callMCP` 的 `MCPJSONValue.Object` params 做 key-aware recursive redaction：secret-like key 的 value 直接替换为 `<redacted>`，非敏感字段继续递归并保留 `Redaction.scrub` 字符串兜底。
- `Capabilities` 文档更新为复用 SliceCore 的 `MCPToolRef` / `MCPCallResult`，不声明 Task 2 已完成。

## 测试用例与结果

- 红灯命令：
  - `swift test --filter SliceCoreTests.MCPJSONValueTests`：失败，原因是 `MCPJSONValue` / `MCPCallResult` / `MCPContentItem` 不存在，`callMCP` 与 `PipelineStep.mcp` 仍为 `[String: String]`，`MCPTransport.streamableHTTP` 和 `isCreatableInPhase1Settings` 不存在。
  - `swift test --filter SliceCoreTests.MCPContentItemTests`：失败，原因同上，核心是 `MCPCallResult` / `MCPContentItem` 缺失。
  - `swift test --filter SliceCoreTests.MCPDescriptorTests`：失败，原因同上，核心是 transport 新 case / 属性缺失。
- 绿色命令：
  - `swift test --filter SliceCoreTests.MCPJSONValueTests`：通过，4 tests。
  - `swift test --filter SliceCoreTests.MCPContentItemTests`：通过，2 tests。
  - `swift test --filter SliceCoreTests.MCPDescriptorTests`：通过，13 tests。
  - `swift test --filter SliceCoreTests.OutputBindingTests`：通过，24 tests。
  - `swift test --filter SliceCoreTests.ToolKindTests`：通过，30 tests。
  - `swift test --filter SliceCoreTests`：通过，311 tests；同时证明包内目标可编译。
- Review 修复红灯命令：
  - `swift test --filter SliceCoreTests.MCPContentItemTests`：失败，原因是 embedded resource 仍扁平编码/解码，resource_link 缺 name 时未抛错。
- Review 修复绿色命令：
  - `swift test --filter SliceCoreTests.MCPContentItemTests`：通过，9 tests。
- 第二轮 Review 修复红灯命令：
  - `swift test --filter SliceCoreTests.MCPContentItemTests`：失败，原因是 embedded resource 缺 text/blob 或同时含 text/blob 时没有抛错。
- 第二轮 Review 修复绿色命令：
  - `swift test --filter SliceCoreTests.MCPContentItemTests`：通过，13 tests。
  - `swift test --filter SliceCoreTests`：通过，322 tests。
  - `swift test`：通过，590 tests。
- 代码质量 Review 修复红灯命令：
  - `swift test --filter OrchestrationTests.JSONLAuditLogTests`：失败，原因是 top-level password、nested apiKey、array 内 token key 的 plain value 未按 key 脱敏。
- 代码质量 Review 修复绿色命令：
  - `swift test --filter OrchestrationTests.JSONLAuditLogTests`：通过，18 tests。
  - `swift test --filter SliceCoreTests`：通过，322 tests。
  - `swift test`：通过，591 tests。
  - `git diff --check HEAD^ HEAD`：通过，无 whitespace error。
- Claude Review Round 1 红灯命令：
  - `swift test --filter SliceCoreTests.MCPContentItemTests`：失败，原因是 `MCPCallResult` encode 输出 `meta`，decode MCP wire `_meta` 后 `meta == nil`。
- Claude Review Round 1 绿色命令：
  - `swift test --filter SliceCoreTests.MCPContentItemTests`：通过，15 tests。
