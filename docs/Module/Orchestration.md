# Orchestration 模块说明

## 模块定位

`Orchestration` 是 v2 执行引擎模块，负责把一次用户触发从 `Tool + ExecutionSeed` 串成完整执行流。它不直接管理 AppKit UI，而是通过协议把输出投递给 output sink，由 `SliceAIApp` 的 adapter 接到 `ResultPanel`、BubblePanel 或其它 DisplayMode sink。

## 功能范围

- 执行入口：`ExecutionEngine.execute(tool:seed:)`。
- 上下文采集：`ContextCollector`、`ContextProviderRegistry`。Phase 1 M2 Task 7 后，Capabilities 已提供 `selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read` 五个核心 provider，可通过 registry 注入 collector。
- 权限闭环：`PermissionGraph`、`PermissionBroker`、`PermissionConsentPresenting`、`PermissionGrantStore`、`EffectivePermissions`。Phase 1 M2 Task 6 后，`EffectivePermissions.undeclared` 使用 case-aware coverage；Task 8 后，生产 `PermissionBroker` 通过 UI-free presenter 在 broker 内部解析 consent，不再把运行期确认需求直接交给 `ExecutionEngine`；Task 9 后，App target 提供 `AppPermissionConsentPresenter` 作为真实 AppKit presenter。
- Provider 解析：`ProviderResolver`、`DefaultProviderResolver`。
- Prompt / Agent 执行：`PromptExecutor` 负责 prompt 渲染、Keychain 取 key、调用 `LLMProviderFactory` 和流式 provider；`AgentExecutor` 负责 OpenAI-compatible tool calling、MCP allowlist、ReAct loop、tool-call lifecycle 和 skill 渐进式加载。
- 输出派发：`OutputDispatcher`、`WindowSinkProtocol`、`FinalTextFileAppending`、`TextReplacementClient`、`BubbleOutputSink`、`StructuredOutputSink`、`SideEffectExecutor`、`InvocationGate`。
- 遥测：`CostAccounting`、`JSONLAuditLog`、`InvocationReport`、`ExecutionEvent`。

## 技术实现

`ExecutionEngine` 是 actor，公开 API 返回 `AsyncThrowingStream<ExecutionEvent, Error>`。调用方无需 await 即可拿到 stream；内部通过 actor-isolated 主流程串行推进。

主流程按固定顺序执行：

1. 发送 `.started`。
2. `PermissionGraph.compute` 计算 effective permissions，并通过 `Permission.covers` 校验每个 effective permission 是否被 declared permission 覆盖。
3. `PermissionBroker.gate` 对权限集合做授权决策；cacheable grant 命中时直接放行，否则通过 App 层注入的 `PermissionConsentPresenting` 获取 approve / deny。
4. `ContextCollector.resolve` 并发解析 `ContextRequest`；内置 provider 可采集 seed/app 快照、剪贴板和 `PathSandbox` 允许的文件内容。
5. `ProviderResolver.resolve` 解析 `ProviderSelection`。
6. `.prompt` 工具进入 `PromptExecutor`；`.agent` 工具进入 `AgentExecutor`；`.pipeline` 仍返回 not implemented。
7. LLM chunk 通过 `OutputDispatcher` lifecycle 投递；prompt / agent 路径都会累积 final text 并在 finish 阶段收口。
8. `OutputBinding.sideEffects` 逐条 gate；`.file` 主输出已经消费的 `appendToFile` 会跳过重复实执行。
9. `CostAccounting` 写 token / USD 估算。
10. `JSONLAuditLog` 写终态报告并发送 `.finished` / `.failed`。

取消语义由 stream termination 触发内部 task cancel。每个重要 await 边界都有取消短路，用户关闭结果面板后不再写失败审计，也不继续发网络或成本记录。

## 关键接口

| 接口 | 说明 |
|---|---|
| `ExecutionEngine.execute(tool:seed:)` | v2 唯一执行入口，返回事件流。 |
| `ExecutionEvent` | UI / Playground / 测试消费的事件枚举。 |
| `ContextCollector.resolve(seed:requests:)` | 通过 `ContextProviderRegistry` 并发解析 Tool 声明的 `ContextRequest`。 |
| `ContextProviderRegistry` | provider name 到实例的只读注册表；PermissionGraph 与 ContextCollector 应共享同一 registry。 |
| `PermissionBroker.gate(effective:provenance:scope:isDryRun:)` | 权限 gate 入口；生产实现内部解析 presenter 决策并返回 `.approved` / `.denied` / dry-run `.wouldRequireConsent`。 |
| `PermissionConsentPresenting.requestConsent(_:)` | UI-free runtime consent 边界；App 层实现 presenter，Orchestration 不 import AppKit。 |
| `PermissionGrantStore` | actor 隔离的 session grant store；只缓存 cacheable permissions，拒绝 MCP / network / shell / AppIntents。 |
| `PromptExecutor.run(...)` | prompt 渲染 + LLM provider stream。 |
| `AgentExecutor.run(...)` | Agent ReAct loop；按 MCP allowlist 暴露 tool catalog，执行 MCP tool call，并支持 `sliceai.load_skill` / `sliceai.load_skill_resource` pseudo-tool 按需加载绑定 skill 指令和只读 supporting files。 |
| `OutputDispatcher.handle(chunk:context:)` / `finish(finalText:context:)` | 按 `DisplayMode` 生命周期派发输出；`.silent` 不展示，`.file` 在 finish 写文件，`.replace` 在 finish 替换选区，`.bubble` 在 finish 展示气泡，`.structured` 在 finish 展示结构化结果。 |
| `SideEffectExecutor.execute(_:finalText:invocationId:)` | 在 permission gate 通过后执行副作用；支持 clipboard、file append、notification、MCP call 和 TTS，memory 明确 unsupported；structured JSON 含 `ttsText` 时 TTS 优先朗读该字段。 |
| `InvocationGate` | single-flight 状态唯一来源，阻止旧 invocation 污染新结果。 |
| `AuditLogProtocol.append(_:)` | 审计日志抽象，生产实现为 JSONL append。 |

## 权限覆盖语义

`EffectivePermissions.undeclared` 的判断方向是 declared 覆盖 effective：只要某个 effective permission 找不到任何 declared cover，就视为漏报并在执行前失败。

真实 ContextProvider 的权限推导通过 registry 路由到 provider 类型的 `inferredPermissions(for:)`：

- `selection`、`app.windowTitle`、`app.url` 不产生额外权限。
- `clipboard.current` 推导 `.clipboard`。
- `file.read` 根据 `args["path"]` 推导 `.fileRead(path:)`。

- 标量权限保持 exact match。
- `.fileRead` / `.fileWrite` 先做 PathSandbox hard-deny 检查，再比较规范化后的 exact、显式目录前缀和 `*` / `**` glob。
- `.mcp` 要求 server 相同；declared tools 为 `nil` 覆盖同 server 全部工具，否则 declared tools 必须是 effective tools 的超集。
- `.shellExec` 只接受命令数组完全相等，空数组不表示全部命令。

`PermissionBroker` 根据 tier × provenance 生成 UX hint，但 provenance 只能调节文案强度，不能降低权限下限。`.mcp`、`.network`、`.shellExec`、`.appIntents` 属于每次确认权限；即使 presenter 返回 `.approve(scope: .session)`，broker 也只允许本次 invocation 通过，不写 session grant。

`.persistent` grant 是 Settings-only：runtime presenter 返回 `.approve(scope: .persistent)` 会被 broker 拒绝。生产路径如果需要跨启动保留授权，必须由 Settings 写入 Capabilities 的 persistent store，再由 broker 只读查询。

## 运行逻辑

`SliceAIApp.AppDelegate` 在用户选择工具后创建 `ExecutionSeed`，先设置 `InvocationGate` active id，再打开 `ResultPanel`，最后启动 stream consumer。`ExecutionEventConsumer` 把 `.llmChunk`、`.finished`、`.failed`、`.notImplemented` 等事件翻译为面板操作。

`SliceAIApp.AppContainer` 在启动期创建真实 `ContextProviderRegistry`，注册 `selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read` 五个 provider，并让 `ContextCollector` 与 `PermissionGraph` 共享该 registry。运行期权限确认由 AppKit `NSAlert` presenter 完成；presenter 只返回 `.oneTime` 或 `.session`，persistent grant 仍是 Settings-only。

Agent 执行链会把 allowlist 中的 MCP tool 暴露给支持 tool calling 的 OpenAI-compatible provider，并在每次真实 MCP 调用前走权限 gate。Phase 2 Skill Registry MVP 后，Agent Tool 初始只注入绑定 skills 的 metadata；模型需要完整指令时调用内置 `sliceai.load_skill` pseudo-tool，执行器从 `LocalSkillRegistry` 读取对应 `SKILL.md`。Task 62 后，metadata 还会列出可读 supporting files；模型必须先加载 skill，再用 `sliceai.load_skill_resource` 读取 `references/` 或文本型 `assets/`。`scripts/` 仍不读取、不执行。

`OutputDispatcher` 当前已具备 `.window`、`.silent`、`.file`、`.replace`、`.bubble` 和 `.structured` 的真实行为。`.silent` 消费输出但不写 window；`.file` 在 finish 阶段从 `outputBinding.sideEffects` 读取首个 `appendToFile` 目标并写入 final text，缺少目标时返回配置错误；`.replace` 在 finish 阶段通过 `TextReplacementClient` 替换前台 App 选区，AX 失败时由 App 层复制到剪贴板并通知用户；`.bubble` 与 `.structured` 在 chunk 阶段均不写 window，finish 阶段分别调用 `BubbleOutputSink` 和 `StructuredOutputSink`。缺少对应 sink 时会返回配置错误，避免静默丢输出或退回旧 window fallback。

`SideEffectExecutor` 当前已接入生产 `ExecutionEngine`。App 层注入剪贴板写入、用户通知、routing MCP client、`PathSandbox` 和 `AVSpeechTTSCapability`；`.tts` 在 permission gate 通过后朗读 final text，dry-run 只发 `.sideEffectSkippedDryRun`，不会调用真实 TTS。English Tutor 这类 structured 输出如果包含顶层 `ttsText` 字段，会朗读该字段而不是整段 JSON。

## 代码实现说明

核心源码位于 `SliceAIKit/Sources/Orchestration/`。测试位于 `SliceAIKit/Tests/OrchestrationTests/`，重点覆盖 `InvocationGate`、事件顺序、single-writer 输出契约、OutputDispatcher lifecycle / final-only sink、SideEffectExecutor、PromptExecutor 错误分类、AgentExecutor MCP / skill tool-call 行为、InvocationReport 和权限闭环。
