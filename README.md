# SliceAI

> macOS 开源划词触发 LLM 工具栏

SliceAI 让你在任何 Mac 应用里选中文字后，通过快捷工具栏或 `⌥Space` 命令面板调用 OpenAI 兼容的大模型，流式查看结果。

## Status

v0.2.0 Phase 0 底层重构已正式发布：v2 数据模型、Orchestration 执行引擎、Capabilities 能力边界已接入真实 App 触发链。Release: <https://github.com/yingjialong/SliceAI/releases/tag/v0.2.0>。参见 [docs/v2-refactor-master-todolist.md](docs/v2-refactor-master-todolist.md) 跟踪后续 Phase。

## Features (MVP v0.2)

- 划词后自动弹出浮条工具栏（PopClip 风格）
- `⌥Space` 快捷键唤起中央命令面板
- 独立浮窗 Markdown 流式渲染
- 支持 OpenAI 兼容协议（OpenAI、DeepSeek、Moonshot、OpenRouter、自建中转…）
- 4 个内置 Prompt 工具：Translate / Polish / Summarize / Explain
- 1 个内置 Agent 工具：Web Search Summarize（需要配置 Brave Search MCP）
- 自定义 prompt、供应商、模型
- API Key 存 macOS Keychain

## Build from source

```bash
git clone https://github.com/<you>/SliceAI.git
cd SliceAI
open SliceAI.xcodeproj
# Product → Run
```

## Requirements

- macOS 14 Sonoma 或更新
- Xcode 26 或更新
- Swift 6.0

## Architecture Modules

| 模块 | 职责 |
|---|---|
| `SliceAIApp` | macOS App 薄壳：菜单栏、Onboarding、全局触发监听、Composition Root、ResultPanel 生命周期。 |
| `SliceCore` | 领域模型与配置：`Tool` / `Provider` / `Configuration` / `ExecutionSeed` / `ResolvedExecutionContext` / 权限 / 输出绑定。 |
| `Orchestration` | v2 执行引擎：`ExecutionEngine`、上下文采集、权限闭环、PromptExecutor、OutputDispatcher、成本记账、审计日志。 |
| `Capabilities` | Phase 1+ 能力边界：`PathSandbox`、MCP server store/importer、MCP client 协议、stdio / Streamable HTTP client、Skill registry 协议和生产侧 mock。 |
| `LLMProviders` | OpenAI 兼容协议实现与 provider factory，负责 Chat Completions / SSE 流式解析。 |
| `SelectionCapture` | 选区捕获：AX 主路径 + Cmd+C fallback，统一产出 `SelectionPayload`。 |
| `HotkeyManager` | Carbon `RegisterEventHotKey` 全局快捷键注册与解析。 |
| `Windowing` | FloatingToolbar、CommandPalette、ResultPanel 与屏幕定位算法。 |
| `SettingsUI` | SwiftUI 设置界面、KeychainStore、Provider / Tool / MCP Servers 编辑器、配置即时保存。 |
| `DesignSystem` / `Permissions` | 设计 token、主题管理、共享控件与 Accessibility onboarding / monitor。 |

## 项目修改变动记录

### 2026-05-09 · Phase 1 M4 Task 15 · Per-Tool Hotkeys

**范围**：worktree `.worktrees/phase-1-mcp-context`，M4 Task 15

**主要变更**：
- `HotkeyBindings` 新增 `tools: [String: String]`，旧 config-v2 缺字段时默认 `[:]`，v1 migrator 也保持工具热键为空。
- 新增 `HotkeyBindingValidator` 和 `ToolHotkeyRegistration`，集中处理热键标准化、命令面板冲突、工具间冲突、无效热键和按 tool id 生成注册项；运行时注册和 Settings UI 会共用同一套有效热键映射，把旧 `Tool.hotkey` fallback 一并纳入冲突过滤。
- Tools 设置页在每个工具基础信息中新增热键录制器，保存时同步 `configuration.hotkeys.tools[tool.id]` 与 `Tool.hotkey` 兼容字段，并触发运行时重新注册热键。
- Hotkey 设置页显示命令面板与工具热键的冲突提示；删除带热键的工具时同步清理对应工具热键映射，并立即重新注册 Carbon 热键，避免旧全局热键继续占用。
- `AppDelegate.reloadHotkey()` 现在同时注册命令面板热键和有效工具热键；工具热键触发后重新读取当前配置、按 tool id 定位工具、捕获选区并以 `.hotkey` trigger source 直接执行。
- 新增 `AppDelegate+Hotkeys.swift` 拆出热键注册逻辑，避免 `AppDelegate.swift` 文件长度继续膨胀。

**验证状态**：
- 已按 TDD 先写失败测试并确认红灯：`HotkeyBindings.tools`、`HotkeyBindingValidator`、`ToolHotkeyRegistration` 缺失。
- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationTests`（11 tests）
- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigMigratorV1ToV2Tests`（10 tests）
- `cd SliceAIKit && swift test --filter HotkeyManagerTests`（10 tests）
- `cd SliceAIKit && swift test --filter SettingsUITests`（15 tests）
- `cd SliceAIKit && swift test`（735 tests）
- `git diff --check`
- touched Swift files targeted `swiftlint lint --strict`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
- 全仓 `swiftlint lint --strict` 仍被 13 个既有历史违规阻塞，Task 15 touched source 已通过 targeted lint。
- Claude review loop Round 1 接受并修复 2 条 finding：删除工具后热键未立即重载、UI/runtime 旧 `Tool.hotkey` fallback 校验不一致；Round 2 approve，`findings: []`。

### 2026-05-09 · Phase 1 M4 Task 14 · Streamable HTTP Transport

**范围**：worktree `.worktrees/phase-1-mcp-context`，M4 Task 14

**主要变更**：
- 新增 `StreamableHTTPMCPClient` actor，按 MCP 2025-06-18 通过 HTTP POST 发送 JSON-RPC，统一声明 `Accept: application/json, text/event-stream` 与 `Content-Type: application/json`。
- initialize 后记录 `Mcp-Session-Id`，后续 `notifications/initialized`、`tools/list`、`tools/call` 会携带 `Mcp-Session-Id` 与 `MCP-Protocol-Version`。
- `tools/list` 结果转换为 canonical `MCPToolDescriptor` 并缓存；`tools/call` 发送结构化 `MCPJSONValue.Object` arguments，支持 `application/json` 和 `text/event-stream` response。
- 生产默认 HTTP session 禁止自动跟随 redirect，避免 `Mcp-Session-Id` 与 JSON-RPC payload 被转发到新地址；带旧 session 的 404 会触发 session reset，后续请求重新 initialize。
- `RoutingMCPClient` 现在把 `.streamableHTTP` 委托给注入的 HTTP client；deprecated `.sse` 与 `.websocket` 继续 fail-fast，不做 legacy fallback probe。
- `AppContainer.makeMCPRuntime` 在生产路径构造并注入 `StreamableHTTPMCPClient`。
- `MCPServerValidation` 已允许 HTTPS Streamable HTTP URL 和 localhost / 127.0.0.1 / ::1 明文 HTTP；缺 URL、缺 host、非本机明文 HTTP 继续 fail-closed。

**验证状态**：
- 已按 TDD 先写失败测试并确认红灯：`StreamableHTTPMCPClient` 缺失、store 仍拒绝 `.streamableHTTP`。
- `cd SliceAIKit && swift test --filter CapabilitiesTests.StreamableHTTPMCPClientTests`
- `cd SliceAIKit && swift test --filter CapabilitiesTests.RoutingMCPClientTests`
- `cd SliceAIKit && swift test --filter CapabilitiesTests.MCPServerStoreTests`
- `cd SliceAIKit && swift test --filter CapabilitiesTests`
- `cd SliceAIKit && swift test`（728 tests；review fix 后复跑通过）
- `git diff --check`
- touched Swift files targeted `swiftlint lint --strict`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
- 全仓 `swiftlint lint --strict` 仍被 13 个既有历史违规阻塞，Task 14 未扩大到无关 lint 重构。
- Claude review loop Round 1 接受并修复 2 条 finding：redirect 泄露风险和 404 session 过期后未重建；Round 2 approve，`findings: []`。

### 2026-05-08 · Phase 1 M3 Task 13 · Built-In web-search-summarize Agent Tool

**范围**：worktree `.worktrees/phase-1-mcp-context`，M3 Task 13

**主要变更**：
- 默认配置从 4 个 prompt tool 扩展为 5 个首方工具，新增 `web-search-summarize` Agent tool。
- 新工具使用 `selection` context，要求 provider 支持 `.toolCalling`，allowlist 仅开放 `brave-search.brave_web_search`。
- 新工具显式声明 `.mcp(server: "brave-search", tools: ["brave_web_search"])` 权限，确保 PermissionGraph / PermissionBroker 保持 fail-closed。
- `DefaultProviderResolver` 已实现 `.capability` 路由：优先选中 `prefer` 中满足能力的 provider，否则回退到第一个满足能力的 provider。
- 保留旧 4 个 prompt tool 的 `.prompt` 类型与首方 provenance，不改变既有 prompt 工具行为。

**验证状态**：
- 已按 TDD 先更新默认配置测试并确认红灯。
- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationTests`
- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationStoreTests`
- `cd SliceAIKit && swift test --filter SliceCoreTests.ToolTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.ProviderResolverTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`
- `cd SliceAIKit && swift test`
- `git diff --check`
- touched Swift files targeted `swiftlint lint --strict`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
- Claude review loop Round 1 approve，`findings: []`

### 2026-05-08 · Phase 1 M2 Task 9 · AppContainer Context And Permission UI Wiring

**范围**：worktree `.worktrees/phase-1-mcp-context`，M2 Task 9

**主要变更**：
- `AppContainer` 注册真实核心 ContextProvider：`selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read`，并让 `ContextCollector` 与 `PermissionGraph` 共享同一 registry。
- 新增 `AppContextAdapters`，把生产剪贴板读取封装在 App 层后注入 `ClipboardCurrentContextProvider(readString:)`。
- 新增 `AppPermissionConsentPresenter`，通过 `NSAlert` 展示权限 case、来源摘要、操作风险和 UX hint；运行期只提供本次允许 / 本次会话允许 / 拒绝，不提供 persistent approval。
- `PermissionBroker` 改为读取 `appSupport/permission-grants.json` 的 persistent grant store，并接入真实 AppKit presenter。
- App runtime MCP client 从 `MockMCPClient()` 改为 `MCPServerStore(appSupport/mcp.json)` + `StdioMCPClient` + `RoutingMCPClient`；`.agent` stub 行为保持不变，真实 AgentExecutor 留给后续 M3。

**验证状态**：
- 未新增重复 Orchestration 行为测试：`ExecutionEngineTests` 已覆盖未声明权限阻断、权限拒绝失败事件、requires-user-consent fallback；Task 9 新增行为主要是 App target wiring，由 `xcodebuild` 编译验证。
- `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`
- `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionBrokerTests`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

### 2026-05-08 · Phase 1 M2 Task 8 · Permission Consent Grants

**范围**：worktree `.worktrees/phase-1-mcp-context`，M2 Task 8

**主要变更**：
- `Orchestration` 新增 UI-free 权限确认协议：`PermissionConsentRequest`、`PermissionConsentDecision`、`PermissionConsentPresenting`。
- `PermissionBroker` 改为持有 presenter，生产非 dry-run 路径内部解析为 `.approved` / `.denied`；`GateOutcome.requiresUserConsent` 仅保留给测试 doubles 与兼容路径。
- `PermissionGrantStore` 只保存 session grant，并在存储层拒绝 `.mcp`、`.network`、`.shellExec`、`.appIntents`。
- `Capabilities` 新增 `PersistentPermissionGrantStore`，默认路径 `~/Library/Application Support/SliceAI/permission-grants.json`，仅持久化 `.persistent` 且同样拒绝不可缓存权限；读侧校验 schema、scope、permission 一致性和 provenanceTag，损坏文件 fail-closed。
- `AppContainer` 在 Task 9 已替换 fail-closed runtime presenter；真实 AppKit 权限弹窗已接入生产 wiring。

**验证状态**：
- 已按 TDD 先写失败测试并确认 persistent store / consent presenter 缺失红灯。
- `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionBrokerTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionGrantStoreTests`
- `cd SliceAIKit && swift test --filter CapabilitiesTests.PersistentPermissionGrantStoreTests`
- `cd SliceAIKit && swift test`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

### 2026-05-08 · Phase 1 M2 Task 7 · Core Context Providers

**范围**：worktree `.worktrees/phase-1-mcp-context`，M2 Task 7

**主要变更**：
- `Capabilities` 新增五个核心 `ContextProvider`：`selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read`。
- `clipboard.current` 默认读取系统剪贴板文本并支持测试注入；`file.read` 先经 `PathSandbox.normalize(_:role: .read)` 规范化和 allowlist / hard-deny 校验，再按 chunk 分块读取 UTF-8 文本，默认 1 MiB 上限。
- `ContextCollectorTests` 增加真实 provider registry 集成测试；`PermissionGraphTests` 增加真实 provider 静态权限推导测试。

**验证状态**：
- 已按 TDD 先写失败测试并确认 provider 类型缺失红灯。
- `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.ContextCollectorTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionGraphTests`
- `git diff --check`

### 2026-05-07 · Phase 1 M2 Task 6 · PermissionGraph Case-Aware Coverage

**范围**：worktree `.worktrees/phase-1-mcp-context`，M2 Task 6

**主要变更**：
- `EffectivePermissions.undeclared` 从字面 `Set.subtracting` 升级为 declared covers effective 的 case-aware coverage。
- 文件权限支持规范化后的 exact、显式目录前缀、`*` / `**` glob 覆盖，并在覆盖前通过 `PathSandbox.isHardDenied(_:)` 拒绝硬禁止路径。
- MCP 权限支持同 server `tools=nil` 覆盖全部具体 tool，以及 declared tool 集合覆盖 effective tool 子集；`shellExec` 保持命令数组精确匹配。

**验证状态**：
- 已按 TDD 先写失败测试并确认红灯。
- `swift test --filter OrchestrationTests.PermissionGraphTests`
- `swift test --filter OrchestrationTests.ExecutionEngineTests`
- `swift test --filter CapabilitiesTests.PathSandboxTests`
- `git diff --check`

### 2026-05-07 · Phase 1 M1 Task 5 · MCP Servers Settings Page

**范围**：worktree `.worktrees/phase-1-mcp-context`，M1 Task 5

**主要变更**：
- `SettingsUI` target 新增 `Capabilities` 依赖，并新增 `SettingsUITests` test target。
- 新增 `MCPServersViewModel`，通过 `MCPServerStore` 读写本地 `mcp.json`，支持 Claude Desktop JSON 导入、server 保存/删除，以及注入 `MCPClientProtocol.tools(for:)` 的测试连接工具预览。
- 新增 `MCPServersPage`，在设置窗口中提供 MCP server 列表、stdio server 新增/编辑 sheet、Claude Desktop JSON 粘贴导入 sheet、测试连接按钮和 tools/list 预览。
- `SettingsScene` sidebar 新增 MCP Servers 页面入口；不提供 legacy SSE 新建选项，也未新增 `LegacySSEMCPClient`。
- `MCPServersViewModel` 的 save/import/delete 使用 actor 内原子 update，编辑改 ID 保留 metadata，并通过 preview generation 丢弃配置变更后的飞行中旧 `tools/list` 结果。

**验证状态**：
- 已按 TDD 先写失败测试并确认红灯。
- `swift test --filter SettingsUITests.MCPServersViewModelTests`（15 tests）
- `swift build`
- `swift test --filter SliceCoreTests.MCPDescriptorTests`
- `swift test --filter CapabilitiesTests.RoutingMCPClientTests`
- `swift test --filter SettingsUITests`
- `swift test`（639 tests）
- `git diff --check`

### 2026-05-07 · Phase 1 M1 Task 4 · Stdio MCP JSON-RPC Client

**范围**：worktree `.worktrees/phase-1-mcp-context`，M1 Task 4

**主要变更**：
- 新增 `MCPJSONRPCRequest` / `MCPJSONRPCResponse` / `MCPJSONRPCError` / `MCPToolsListResult`，锁定 MCP newline-delimited JSON-RPC request、response、error 和 tools/list wire shape。
- 新增 `StdioMCPClient` actor，按首次 `tools(for:)` / `call(ref:args:)` lazy 启动 stdio 子进程，依次发送 `initialize`、`notifications/initialized`、`tools/list`，并通过 `tools/call` 传递结构化 `MCPJSONValue.Object` arguments。
- 新增 `MCPDiagnosticLog`，对 stderr 诊断统一脱敏 bearer、`sk-`、Authorization、Cookie 等敏感片段；stdio client 支持默认 5 分钟 idle timeout，测试可注入短 timeout。
- 新增 `RoutingMCPClient` actor 作为 MCP client facade：`.stdio` 委托给 stdio client；M4 前 `.streamableHTTP` fail-fast 为 unsupported transport，旧 `.sse` 与 `.websocket` 只保留解码兼容且不允许新建或连接。
- `MCPClientError` 新增 `.protocolError(code:message:)` 与 `.unsupportedTransport(_:)`，明确区分 JSON-RPC protocol error 与 `MCPCallResult.isError == true` 的工具执行错误。

**验证状态**：
- 已按 TDD 先写失败测试并确认红灯。
- `swift test --filter CapabilitiesTests.MCPJSONRPCTests`
- `swift test --filter CapabilitiesTests.StdioMCPClientTests`
- `swift test --filter CapabilitiesTests.RoutingMCPClientTests`
- `swift test --filter CapabilitiesTests.MCPClientProtocolTests`
- `swift test --filter CapabilitiesTests`
- `swift test`
- `git diff --check`

### 2026-05-07 · Phase 1 M1 Task 3 · MCP Server Store And Claude Desktop Import

**范围**：worktree `.worktrees/phase-1-mcp-context`，M1 Task 3

**主要变更**：
- 新增 `MCPServerConfiguration` / `RunnerConfirmation` / `MCPServerStore`，默认读写 `~/Library/Application Support/SliceAI/mcp.json`。
- `MCPServerStore.save/load/snapshot` 在写入、读取和 runtime snapshot 前统一执行 fail-closed 校验；`snapshot()` 按 `id` 排序，保证后续 AgentExecutor wiring 测试稳定。
- 新增 `MCPServerValidation`，拒绝不支持的 schemaVersion、重复 server id、`.unknown` provenance、空 stdio command、相对 command、未确认 allowlisted runner、M1 远程 transport 和 websocket 新建写入。
- 新增 `ClaudeDesktopMCPImporter`，仅导入 Claude Desktop `mcpServers` stdio 配置；M4 前遇到 `url` 远程配置直接拒绝。
- 对 `npx`、`uvx`、`node`、`python`、`python3` 做首次 typed confirmation 要求；绝对 command path 会按大小写无关的 basename 归一到 runner 家族，`python3.11`、`node22` 这类版本化解释器路径同样必须确认。
- M1 直接拒绝 `env` / shell wrapper command，避免真实 runner 被藏在 args 或 `-c` payload 中绕过 typed confirmation。

**验证状态**：
- 已按 TDD 先写失败测试并确认红灯。
- `swift test --filter CapabilitiesTests.MCPServerStoreTests`
- `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`
- `swift test --filter CapabilitiesTests`
- `swift test`
- `git diff --check`

### 2026-05-07 · Phase 1 M1 Task 2 · MCP Client Protocol Uses Canonical Descriptor

**范围**：worktree `.worktrees/phase-1-mcp-context`，M1 Task 2

**主要变更**：
- `MCPClientProtocol` 删除 Capabilities 内重复 `MCPDescriptor`，改为直接使用 SliceCore canonical `MCPDescriptor`。
- `tools(for:)` 返回 `MCPToolDescriptor`，`call(ref:args:)` 接收 `MCPJSONValue.Object`，协议可承载 MCP tools/list schema 和结构化 JSON 参数。
- `MockMCPClient` 改为 `[MCPDescriptor: [MCPToolDescriptor]]` / `[MCPToolRef: MCPCallResult]` 注入，并记录 `callCount`、`lastArguments`、`lastToolsDescriptor`。
- `MCPDescriptor` 的 `Equatable` / `Hashable` 均按稳定 `id` 身份判断，避免同一 server 配置更新后无法命中 mock registry。
- `MCPClientError.developerContext` 增加针对 tool ref 的脱敏回归测试，避免泄露原始 server/tool 名称。

**验证状态**：
- 已按 TDD 先写失败测试并确认红灯。
- `swift test --filter SliceCoreTests.MCPDescriptorTests`
- `swift test --filter CapabilitiesTests.MCPClientProtocolTests`
- `swift test`
- `git diff --check`

### 2026-05-06 · Phase 1 M1 Task 1 · SliceCore MCP JSON Contract

**范围**：worktree `.worktrees/phase-1-mcp-context`，M1 Task 1

**主要变更**：
- 新增 `MCPJSONValue` transparent raw JSON 值类型，支持 null / bool / number / string / array / object、字符串叶子变量渲染和 secret-like key 摘要脱敏。
- 新增 `MCPContentItem`、`MCPCallResult`、`MCPToolDescriptor`，将 MCP content/result/tool schema contract 放入 SliceCore；`resource` 与 `resource_link` wire shape 按 MCP 2025-06-18 schema 约束。
- `SideEffect.callMCP` 与 `PipelineStep.mcp` 参数升级为 `MCPJSONValue.Object`，可表达嵌套 JSON。
- `MCPTransport` 新增 `streamable-http`，并通过 `isCreatableInPhase1Settings` 保留旧 `.sse` / `.websocket` 可解码但不可在 Phase 1 设置中新建的约束。

**验证状态**：
- 已按 TDD 先写失败测试并确认红灯。
- `swift test --filter SliceCoreTests.MCPJSONValueTests`
- `swift test --filter SliceCoreTests.MCPContentItemTests`
- `swift test --filter SliceCoreTests.MCPDescriptorTests`
- `swift test --filter SliceCoreTests.OutputBindingTests`
- `swift test --filter SliceCoreTests.ToolKindTests`
- `swift test --filter SliceCoreTests`

### 2026-05-04 · Phase 0 M3 · Switch to V2

**范围**：plan `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`，分支 `feature/phase-0-m3-switch-to-v2`

**主要变更**：
- **触发链切到 v2**：`AppDelegate` 的浮条与 `⌥Space` 命令面板执行入口改为构造 `ExecutionSeed`，通过 `ExecutionEngine.execute(tool:seed:)` 消费 `ExecutionEvent` stream，再由 `ExecutionEventConsumer` 翻译到既有 `ResultPanel`。
- **配置切到 `config-v2.json`**：`AppContainer.bootstrap()` 启动期 eager load `ConfigurationStore.current()`；首次启动写入默认 v2 配置，已有 `config.json` 时通过 migrator 迁移，旧 `config.json` 保持兼容不被覆写。
- **删除 v1 冲突类型族**：移除旧 `ToolExecutor`、`Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` v1 文件；`V2*` 类型回归 spec canonical 名称。
- **命名回归 spec**：`PresentationMode` → `DisplayMode`，`SelectionOrigin` → `SelectionSource`；保留 `SelectionReader` 作为读取器接口，避免与来源枚举混淆。
- **ResultPanel single-flight**：新增 `InvocationGate` 与 `ResultPanelWindowSinkAdapter`，旧 invocation 的 chunk / terminal event 不会污染新 invocation。
- **Provider factory 升级**：`LLMProviderFactory` 直接接收 canonical `Provider`，并在读取 Keychain 前先做 provider kind / baseURL preflight，避免配置错误被误报为 API Key 缺失。

**验证状态**：
- CLI gate：`swift build`、`swift test --parallel --enable-code-coverage`、`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`、`swiftlint lint --strict` 已通过。
- M3.4 grep validation：v1 / `V2*` / `PresentationMode` / `SelectionOrigin` 源码测试范围 0 命中。
- M3.5 13 项手工回归：用户反馈剩余项均已测试通过；2026-05-04 已记录安全子集实机证据。
- M3.6：本地文档归档、最后 4 关 gate、`SliceAI-0.2.0.dmg` 打包、SHA256、DMG 挂载结构校验与临时安装 / 启动校验已完成；PR #3 已 merge，`v0.2.0` tag 已发布，GitHub Release 已正式发布。Release DMG SHA256 为 `2d7749a1405e1ec4051b90b8b3ee5e029f5819e18a2cf69eda074f2de5b98aea`。

### 2026-04-27 · Phase 0 M2 · Orchestration + Capabilities 骨架

**范围**：Task 0–14（plan `docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`，39 commits 自 M1 PR #1 merge `5cdf0f7`）

**主要变更**：
- **Orchestration 模块完整落地**：`ExecutionEngine` actor 主流程串起 spec §3.4 Step 1-10（PermissionGraph 静态闭环 → PermissionBroker.gate → ContextCollector 平铺并发 → ProviderResolver → PromptExecutor → OutputDispatcher → CostAccounting → JSONLAuditLog → finishSuccess）；事件流 `ExecutionEvent` + 终态报告 `InvocationReport`（含 declared/effective 权限差异 + flags + outcome）
- **Capabilities 模块 + SecurityKit**：`PathSandbox`（路径规范化 + 默认白名单 + 硬禁止表，含 macOS `/private/etc` symlink 展开后的兜底）+ `MCPClientProtocol` / `SkillRegistryProtocol` 完整接口 + production-side `MockMCPClient` / `MockSkillRegistry`（Phase 1 才实现真实 stdio / Streamable HTTP；旧 SSE 弃用）
- **权限闭环（spec §3.9.6.5）**：`EffectivePermissions` 5 字段（context/sideEffect/mcp/builtin/declared）+ `PermissionGraph.compute` D-24 静态闭环 + `PermissionBroker` 4 态决策（approved / denied / requiresUserConsent / wouldRequireConsent）+ `ConsentUXHint` 5×4 矩阵（spec §3.9.2 下限 × provenance）
- **遥测 + 安全下限**：`CostAccounting` actor + sqlite append（毫秒精度 `recorded_at` + `usd: TEXT` Decimal 精度）；`JSONLAuditLog` actor + `Redaction.scrub` 4 模式脱敏（Bearer / sk- / Authorization / Cookie）+ `AuditEntry` enum 3 case（含 `.logCleared`）；`SliceCore.SliceError` 加 `.context` / `.toolPermission` 顶层 case，全部 String payload 严格 `<redacted>`
- **PromptExecutor 复制非替换**（§C-7）：从 `SliceCore/ToolExecutor.swift` 复制 prompt 渲染逻辑到 `Orchestration/Executors/PromptExecutor.swift`（升级到 V2 类型 + `PromptStreamElement` enum + `UsageStats` token 估算），**v1 ToolExecutor.swift 0 行 diff**——M3 才删旧文件
- **§C-1 Zero-touch v1**：v1 8 模块（LLMProviders / SelectionCapture / HotkeyManager / DesignSystem / Windowing / Permissions / SettingsUI）+ SliceAIApp 自 baseline 起严格 0 行 diff；SliceCore 仅白名单 3 文件（SliceError + ContextError + ToolPermissionError）

**验证状态**：
- `swift build`：Build complete (0.20s)
- `swift test --parallel --enable-code-coverage`：**545/545 tests pass** (0.48s)
- `swiftlint lint --strict`：**133 files / 0 violations / 0 serious**
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：**BUILD SUCCEEDED**
- 覆盖率（行覆盖）：**Orchestration 89.12%（≥75%）/ Capabilities 97.64%（≥60%）/ SliceCore 92.73%（≥90%）**
- Zero-touch：v1 8 模块 + SliceAIApp + ToolExecutor 共 0 行 diff；SliceCore 仅 3 个白名单文件
- enum-switch `default:` 反向断言：PermissionBroker / ExecutionEngine / ExecutionEngine+Steps / InvocationReport 全部 0 个 default 兜底（C-3 / C-10 不变量持守）

**M2 不做（保留给后续 Phase）**：
- AppContainer 接入 ExecutionEngine 与触发链（M3）
- 删除 `SliceCore/ToolExecutor.swift` + rename pass（M3）
- 真实 MCPClient（stdio / Streamable HTTP，Phase 1；旧 SSE 弃用）+ 真实 SkillRegistry（fs scan，Phase 2）
- OutputDispatcher 的 `.clipboard` / `.replaceSelection` / `.notification` / `.sideOnly` / `.window+notification` 5 种 mode（Phase 2，M2 仅 `.window` 真实分发，其余 `.notImplemented`）

### 2026-04-21 · UI 全面美化 + Task 22 收官

**范围**：Task 18–22（跨越约 4 周的 MVP v0.1 UI 迭代）

**主要变更**：
- 新增 `DesignSystem` SwiftPM target：颜色/字体/间距/圆角/阴影/动画 token + 交互 modifier（GlassBackground、HoverHighlight、PressScale）+ 基础组件（IconButton、PillButton、Chip、KbdKey、SectionCard）
- `ThemeManager` + `AppearanceMode`：全局浅色/深色/跟随系统主题切换，`onModeChange` 回调持久化到 config.json
- 重构所有面板（FloatingToolbarPanel / CommandPalettePanel / ResultPanel）使用 DesignSystem token，删除旧 `PanelStyle.swift`
- 设置界面迁移为 `NavigationSplitView`，新增外观页（Appearance）；填充所有设置子页内容
- `OnboardingFlow` 重设计：560×520 步骤指示器 + Hero 图标风格
- `MenuBarController` 增强：外观子菜单（跟随系统/浅色/深色）+ 未配置 Provider 时图标右上角叠加紫色小红点
- SwiftLint strict 清零：修复 `implicit_return`、`opening_brace`、`sorted_imports`、`line_length`、`force_unwrapping` 共 6 处（4 项真实修复，2 项加 disable 注释说明原因）

**验证状态**：
- `swift build`：Build complete
- `swift test --parallel`：All tests passed
- `swiftlint lint --strict`：0 violations, 0 serious
- `xcodebuild`：BUILD SUCCEEDED

## License

MIT — see [LICENSE](LICENSE)
