# Phase 1 MCP + Context 主干设计

- **日期**：2026-05-06
- **状态**：Design spec 已起草，等待用户 review；review 通过后进入 implementation plan。
- **适用范围**：Phase 1 / v0.3 MCP + Context 主干。
- **上游依据**：[2026-04-23-sliceai-v2-roadmap.md](2026-04-23-sliceai-v2-roadmap.md)、[docs/v2-refactor-master-todolist.md](../../v2-refactor-master-todolist.md)
- **协议依据**：MCP 官方最新规范 2025-11-25；标准传输是 `stdio` 与 `Streamable HTTP`，旧 `HTTP+SSE` 在 Phase 1 中弃用且不实现。

## 1. 目标

Phase 1 的目标是把 Phase 0 留下的 v2 主干占位补成可运行闭环：

```text
Tool.agent
  -> ContextCollector
  -> ContextProvider
  -> AgentExecutor
  -> LLM tool call
  -> PermissionBroker
  -> MCPClient
  -> ExecutionEvent
  -> ResultPanel
  -> OutputBinding
```

交付完成后，用户应能在 Settings 中配置 MCP server，在 Tool 中选择允许的 MCP tools，用划词或 Per-Tool Hotkey 触发首个真实 Agent Tool `web-search-summarize`，并在 ResultPanel 看到工具调用审批、执行和结果。

## 2. 非目标

- 不引入 Skill runtime。Skill 属于 Phase 2。
- 不实现 Pipeline 编排。Pipeline 属于 Phase 5 方向。
- 不做云同步、团队协作或远程配置分发。
- 不把 MCP server 当成安全沙箱运行；stdio MCP server 等同于用户身份下本地代码执行，只做明确授权、拦截和审计。
- 不让 provenance 降低权限确认级别。来源只影响 UI 文案和风险提示。

## 3. 架构边界

| 层 | 责任 |
|---|---|
| `SliceCore` | 稳定模型和协议：`MCPDescriptor`、`MCPToolRef`、`Permission`、`ContextRequest`、`AgentTool`、结构化 MCP JSON 类型 |
| `Capabilities` | MCP transport、MCP server store、ContextProvider、PermissionGrantStore、PathSandbox 适配 |
| `Orchestration` | `AgentExecutor`、Context 收集编排、权限 gate 调用、ExecutionEvent 产出 |
| `SliceAIApp` | Settings 页面、权限弹窗、ResultPanel 状态、Hotkey 注册、AppKit / Accessibility 适配 |

设计边界必须保持：`Orchestration` 不直接依赖 UI；`SliceCore` 不引入网络、文件系统、子进程或 AppKit 副作用；Composition Root 仍集中在 `SliceAIApp/AppContainer.swift`。

## 4. 主干口径修正

### 4.1 MCPDescriptor 唯一来源

当前代码中 `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift` 已有 canonical descriptor，但 `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift` 里仍有重复的简化 `MCPDescriptor`。Phase 1 必须以 `SliceCore.MCPDescriptor` 为唯一来源，删除或替换重复定义，避免 Settings、AgentExecutor、MCPClient 使用不同 schema。

### 4.2 MCP JSON 类型

当前 `MCPClientProtocol.call` 使用 `[String: String]` 参数，`MCPCallResult` 使用 `[String]` content，无法覆盖真实 MCP `tools/call` 的 JSON 参数、content item、structuredContent 和 tool execution error。Phase 1 需要引入结构化 JSON value 与 MCP content item 类型。

最低要求：

- tool arguments 支持任意 JSON object。
- tool result 支持 text、image、resource link、embedded resource、structuredContent。
- JSON-RPC protocol error 与 tool execution error 分开建模。
- 传给 LLM 的摘要必须经过长度限制与脱敏。

### 4.3 远程传输命名

旧 roadmap 写的是 MCPClient SSE。当前 MCP 官方最新规范把标准远程传输定义为 `Streamable HTTP`。Phase 1 执行口径改为：

- M1 优先实现 `stdio`，因为 Claude Desktop 兼容和本地 MCP server 是核心场景。
- M4 实现 `Streamable HTTP` 作为远程 MCP transport。
- 旧 `HTTP+SSE` 弃用且不实现；`.sse` 只作为 deprecated wire value 被识别并拒绝。

### 4.4 Permission 默认策略

`PermissionBroker` 现在遇到 `requiresUserConsent` 会在非 dry-run 下失败。Phase 1 要接入真实 UI gate：

- 默认 scope 为 `oneTime`。
- 弹窗允许选择 `session`。
- `persistent` 只能在 Settings 中管理和撤销，避免误点长期授权。
- MCP tool call 默认每次确认；已有 grant 只影响同一 permission / provenance / tool 范围内的重复确认。
- `unknown` provenance、相对 command path、未确认 runner、allowlist 外工具调用全部 fail closed。

## 5. 里程碑拆分

### M1：MCP 配置与 stdio 主干

目标：SliceAI 能加载、校验、导入、启动本地 MCP server。

范围：

- 新增 `MCPServerStore`，落盘到 `~/Library/Application Support/SliceAI/mcp.json`。
- 支持 Claude Desktop `mcpServers` 导入。
- 校验 provenance：允许 `firstParty`、`selfManaged`、`communitySigned`；拒绝 `unknown`。
- 对 `npx`、`uvx`、`node`、`python` runner 做首次 typed confirmation。
- 实现 stdio JSON-RPC client：lazy start、独立进程、initialize、tools/list、tools/call、idle timeout 5 分钟、stderr redacted diagnostic log。
- 新增 `SettingsUI/Pages/MCPServersPage`：增删改查、测试连接、查看 tools。

验收：

- filesystem 与 brave-search 两个 stdio MCP server 可配置、可列出 tools、可执行一次安全 tool call。
- 重启 app 后 MCP 配置仍存在。
- unknown provenance config 被拒绝并显示明确错误。

### M2：Context 与 Permission 主干

目标：Agent 执行前拿到真实上下文，敏感能力有真实用户门禁。

范围：

- 实现 `selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read` 五个 ContextProvider。
- `AppContainer` 注册真实 provider，不再使用空 registry。
- `PermissionBroker` 接入 AppKit UI gate。
- `PermissionGrantStore` 支持持久化、session 生命周期、撤销。
- `file.read` 走 PathSandbox 和 permission gate。
- 产出 permission lifecycle execution events。

验收：

- 五个 provider 都有自动化验证或稳定集成验证。
- 用户拒绝权限时，Agent 执行受控失败，不崩溃。
- 重启 app 后 persistent grant 保留，session grant 不保留。

### M3：AgentExecutor 与工具调用 UI

目标：跑通真正的 agent tool execution。

范围：

- 实现 ReAct loop：上下文注入、LLM 调用、工具调用解析、审批、MCP call、结果回填、停止条件。
- 默认每次 MCP tool call 都需要用户确认。
- `ExecutionEventConsumer` 将 tool call 生命周期转换为 ResultPanel 状态。
- ResultPanel 展示 proposed、approved、result、denied、error。
- 新增首个 Agent tool：`web-search-summarize`，默认使用 brave-search MCP。
- 设置 `maxSteps` 与单次 tool timeout，防止循环失控。

验收：

- `web-search-summarize` 完整走通：selection/context -> LLM -> brave-search -> 用户确认 -> Markdown 总结。
- 用户拒绝某个 tool call 时，Agent 给出可理解终止结果。
- ResultPanel 能看到每个 tool call 的生命周期。

### M4：HTTP Transport、Per-Tool Hotkey、5 Server E2E 与发布准备

目标：补齐 v0.3 发布口径。

范围：

- 实现 MCP `Streamable HTTP` transport；旧 `HTTP+SSE` server 不兼容。
- HotkeyManager 支持多个 hotkey 注册。
- Tool 设置页支持 Per-Tool Hotkey、冲突检测和移除。
- Tool hotkey 触发对应 Tool，而不是只打开 Command Palette。
- 验证 filesystem、postgres、brave-search、git、sqlite 五个 MCP server。
- 在 Safari、Notes、Slack 中手工回归 `web-search-summarize`。
- 新增 `docs/Module/MCPClient.md` 与 `docs/Module/ContextProviders.md`。
- 更新 master todolist，准备 v0.3 tag / release notes。

验收：

- 五个 MCP server 至少覆盖 list tools 与一次成功 tool call。
- Per-Tool Hotkey 可配置、可冲突检测、可触发。
- v0.3 release checklist 全部完成。

## 6. 关键数据流

### 6.1 MCP 配置流

`MCPServersPage` 写入 `MCPServerStore`，store 负责 schema 校验、安全校验、runner typed confirmation 状态和落盘。Claude Desktop 导入只接受兼容字段，并补齐 SliceAI 所需的 provenance、displayName、enabled 等元数据。

### 6.2 Context 收集流

`Tool.agent.contexts` 声明所需上下文，`AgentExecutor` 调用 `ContextCollector`。`ContextCollector` 只依赖 `ContextProvider` 协议。涉及 AppKit、Accessibility、剪贴板、文件系统的 provider 通过 Capabilities 或 App 层 adapter 注入。

### 6.3 Agent 执行流

`AgentExecutor` 构造 system prompt、user prompt 和 context bag，调用 provider LLM。模型请求 tool call 时，先发出 `ExecutionEvent.toolCallProposed`，再进入 `PermissionBroker`。用户批准后调用 `MCPClient.call`，结果回填给模型继续推理，直到 stop condition、maxSteps 或错误终止。

### 6.4 UI 展示流

`ExecutionEventConsumer` 订阅执行事件，将 tool call 生命周期转成 ResultPanel 状态。ResultPanel 不直接调用 MCP，也不决定权限；权限决策只来自 `PermissionBroker` UI gate。

## 7. 错误处理

| 错误类型 | 处理策略 |
|---|---|
| MCP 配置错误 | 阻断保存或导入，指出 server、字段和原因 |
| MCP 进程错误 | 区分启动失败、initialize 失败、JSON-RPC 解码失败、工具不存在、调用超时 |
| stderr 输出 | 只进入 redacted diagnostic log，不能直接拼入用户可见结果 |
| 权限拒绝 | 作为结构化 tool denial 传给 Agent，不作为崩溃或系统错误 |
| Context 缺失 | required 失败终止；optional 失败记录 warning 后继续 |
| Agent 失控 | `maxSteps` 与 tool timeout 双保险 |
| 安全策略冲突 | unknown provenance、相对 command path、allowlist 外 tool、未确认 runner 全部 fail closed |

## 8. 测试策略

| 层级 | 覆盖内容 |
|---|---|
| 单元测试 | MCP descriptor 编解码、mcp.json import/export、provenance 校验、runner detection、JSON-RPC framing、grant scope、provider inferred permissions |
| 集成测试 | stdio process lifecycle、tools/list、tools/call、idle timeout、ContextCollector required/optional、AgentExecutor maxSteps / denial / allowlist violation |
| App/UI 回归 | MCPServersPage 增删改查、测试连接、权限弹窗、ResultPanel tool call 展示、Per-Tool Hotkey |
| 手工 E2E | filesystem、postgres、brave-search、git、sqlite；Safari、Notes、Slack；`web-search-summarize` 完整链路 |

Phase 1 不能只靠手工验证。MCP JSON-RPC、权限 gate 和 Agent loop 是高风险主干，implementation plan 必须为这些部分写入自动化验证。

## 9. Plan 编写要求

implementation plan 路径固定为：

```text
docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md
```

plan 必须包含：

- M1-M4 的任务级拆分。
- 每个任务的文件清单、测试命令、验收标准。
- 对 `MCPDescriptor` 重复定义的修复步骤。
- MCP JSON value / content item 的模型设计。
- Permission UI gate 的主线程桥接方案。
- `Streamable HTTP` 与 deprecated `.sse` 拒绝策略的执行口径。
- 5 server E2E 与 Safari / Notes / Slack 手工回归清单。

## 10. 自审结果

- Placeholder scan：未保留占位语或空章节。
- Internal consistency：MCP 远程传输统一为 `Streamable HTTP` 主线，旧 `HTTP+SSE` 弃用且不实现；与用户确认后的 Phase 1 口径一致。
- Scope check：保持一个 Phase 1 总 plan，但内部拆 M1-M4，适合后续 subagent-driven execution。
- Ambiguity check：默认 permission scope、provenance 策略、MCP descriptor 来源、ContextProvider 五件套均已明确。
