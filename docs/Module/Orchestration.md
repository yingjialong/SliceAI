# Orchestration 模块说明

## 模块定位

`Orchestration` 是 v2 执行引擎模块，负责把一次用户触发从 `Tool + ExecutionSeed` 串成完整执行流。它不直接管理 AppKit UI，而是通过协议把输出投递给 Window sink，由 `SliceAIApp` 的 adapter 接到既有 `ResultPanel`。

## 功能范围

- 执行入口：`ExecutionEngine.execute(tool:seed:)`。
- 上下文采集：`ContextCollector`、`ContextProviderRegistry`。
- 权限闭环：`PermissionGraph`、`PermissionBroker`、`PermissionGrantStore`、`EffectivePermissions`。
- Provider 解析：`ProviderResolver`、`DefaultProviderResolver`。
- Prompt 执行：`PromptExecutor`，负责 prompt 渲染、Keychain 取 key、调用 `LLMProviderFactory` 和流式 provider。
- 输出派发：`OutputDispatcher`、`WindowSinkProtocol`、`InvocationGate`。
- 遥测：`CostAccounting`、`JSONLAuditLog`、`InvocationReport`、`ExecutionEvent`。

## 技术实现

`ExecutionEngine` 是 actor，公开 API 返回 `AsyncThrowingStream<ExecutionEvent, Error>`。调用方无需 await 即可拿到 stream；内部通过 actor-isolated 主流程串行推进。

主流程按固定顺序执行：

1. 发送 `.started`。
2. `PermissionGraph.compute` 计算 effective permissions，并校验 `effective ⊆ tool.permissions`。
3. `PermissionBroker.gate` 对权限集合做授权决策。
4. `ContextCollector.resolve` 并发解析 `ContextRequest`。
5. `ProviderResolver.resolve` 解析 `ProviderSelection`。
6. `.prompt` 工具进入 `PromptExecutor`；`.agent` / `.pipeline` 在 v0.2.0 返回 not implemented。
7. LLM chunk 通过 `OutputDispatcher` 投递到 window sink。
8. `OutputBinding.sideEffects` 逐条 gate。
9. `CostAccounting` 写 token / USD 估算。
10. `JSONLAuditLog` 写终态报告并发送 `.finished` / `.failed`。

取消语义由 stream termination 触发内部 task cancel。每个重要 await 边界都有取消短路，用户关闭结果面板后不再写失败审计，也不继续发网络或成本记录。

## 关键接口

| 接口 | 说明 |
|---|---|
| `ExecutionEngine.execute(tool:seed:)` | v2 唯一执行入口，返回事件流。 |
| `ExecutionEvent` | UI / Playground / 测试消费的事件枚举。 |
| `PromptExecutor.run(...)` | prompt 渲染 + LLM provider stream。 |
| `OutputDispatcher.handle(chunk:mode:invocationId:)` | 按 `DisplayMode` 派发输出；v0.2.0 non-window mode fallback 到 window。 |
| `InvocationGate` | single-flight 状态唯一来源，阻止旧 invocation 污染新结果。 |
| `AuditLogProtocol.append(_:)` | 审计日志抽象，生产实现为 JSONL append。 |

## 运行逻辑

`SliceAIApp.AppDelegate` 在用户选择工具后创建 `ExecutionSeed`，先设置 `InvocationGate` active id，再打开 `ResultPanel`，最后启动 stream consumer。`ExecutionEventConsumer` 把 `.llmChunk`、`.finished`、`.failed`、`.notImplemented` 等事件翻译为面板操作。

`OutputDispatcher` 在 v0.2.0 中只有 `.window` 真实 sink。`.bubble`、`.replace`、`.file`、`.silent`、`.structured` 会 fallback 到 window sink 并记录一次去重日志，保证旧配置迁移后用户仍能看到结果，不会因为 Phase 2 UI 未实现而丢输出。

## 代码实现说明

核心源码位于 `SliceAIKit/Sources/Orchestration/`。测试位于 `SliceAIKit/Tests/OrchestrationTests/`，重点覆盖 `InvocationGate`、事件顺序、single-writer 输出契约、OutputDispatcher fallback、PromptExecutor 错误分类、InvocationReport 和权限闭环。
