# 2026-05-26 · Phase 2 Completion

## 背景

Task 58-62 已完成 Phase 2 前半段：Skill Registry MVP、真实本地 skill E2E、公开 skill 仓库 smoke，以及 supporting files 只读加载。当前 Phase 2 还不能标记完成，因为多 DisplayMode、真实 side effects、TTS 和 English Tutor 仍未落地。

本任务按用户确认的“严格 Roadmap”范围继续推进 Phase 2，目标是做到完整完成并通过测试。

## 范围

包含：

- Output lifecycle foundation。
- `.bubble / .replace / .file / .silent / .structured` 真实 DisplayMode。
- `appendToFile / copyToClipboard / notify / callMCP / tts` side effects 实执行。
- 本地 TTS capability。
- 首方 `english-tutor` Agent Tool。
- 配置 schema、README、模块文档、任务文档和 final gate。

不包含：

- skill scripts 执行或读取。
- marketplace、远端安装、自动更新、`.slicepack`。
- PipelineExecutor。
- 真实 memory 写入。
- 原生 Anthropic / Gemini / Ollama provider。

## ToDoList

- [x] 创建 Phase 2 completion spec。
- [x] 创建 Phase 2 completion implementation plan。
- [x] 更新 Task_history、README、AGENTS 和 master todolist 的任务口径。
- [x] 按 TDD 实施 Output lifecycle foundation。
- [x] 按 TDD 实施 SideEffect executor。
- [x] 按 TDD 实施 `.silent` 与 `.file`。
- [ ] 按 TDD 实施 `.replace`。
- [ ] 按 TDD 实施 `.bubble` 与 `.structured`。
- [ ] 按 TDD 实施 TTS capability。
- [ ] 按 TDD 实施 `english-tutor` 默认工具。
- [ ] 完成 App wiring 和真实手工 smoke。
- [ ] 跑最终 automated gate 并更新文档结果。

## 当前实施方案

权威 spec：`docs/superpowers/specs/2026-05-26-phase-2-completion.md`

权威 plan：`docs/superpowers/plans/2026-05-26-phase-2-completion.md`

核心设计：

1. `OutputDispatcher` 从 chunk-only API 升级到 begin / chunk / finish / fail 生命周期。
2. `ExecutionEngine` 在 prompt 和 agent 路径都收集 final text，最终传给 output sink 和 side effect executor。
3. `SideEffectExecutor` 作为独立协议注入，避免副作用混入展示层。
4. `.replace / .file / .structured / .tts` 都在 final text 后执行，不对 stream chunk 做破坏性操作。
5. `english-tutor` 作为 Phase 2 demo tool，验证 skill + structured + TTS 的端到端路径。

## 已执行验证

- M0 收口前已通过：
  - `git diff --check`
  - `swift test --package-path SliceAIKit --filter CapabilitiesTests.LocalSkillRegistryTests`
  - `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests`
- Output lifecycle foundation：
  - 红灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.OutputLifecycleTests` 首次因 lifecycle API / `lifecycleCalls` 缺失编译失败。
  - 红灯：Prompt lifecycle 变绿后，Agent lifecycle 测试因 lifecycle calls 为空失败，证明 Agent 路径仍未接入。
  - 绿灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.OutputLifecycleTests`，2 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'OrchestrationTests.OutputLifecycleTests|OrchestrationTests.ExecutionEngineTests|OrchestrationTests.AgentExecutorTests'`，56 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'OrchestrationTests.OutputDispatcherTests|OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.OutputLifecycleTests'`，18 tests，0 failures。
  - 绿灯：touched Swift files `swiftlint lint --strict ...`，0 violations。
  - 绿灯：`git diff --check`，passed。
- SideEffect executor：
  - 红灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.SideEffectExecutorTests` 首次因 `SideEffectExecutor` 与 adapter 协议缺失编译失败。
  - 红灯：直接 executor 实现后，ExecutionEngine wiring 测试因 `sideEffectExecutor` init 参数不存在失败。
  - 绿灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.SideEffectExecutorTests`，7 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'OrchestrationTests.SideEffectExecutorTests|OrchestrationTests.ExecutionEngineTests|OrchestrationTests.OutputLifecycleTests|OrchestrationTests.AgentExecutorTests'`，63 tests，0 failures。
  - 绿灯：touched Swift files `swiftlint lint --strict ...`，0 violations。
  - 绿灯：`git diff --check`，passed。
- Silent / File DisplayMode：
  - 红灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.OutputDispatcherFallbackTests` 首次因 `FinalTextFileAppending`、`OutputDispatcher(fileAppender:)` 和 `OutputInvocationContext.outputBinding` 缺失编译失败。
  - 绿灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.OutputDispatcherFallbackTests`，9 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.OutputDispatcherTests|OrchestrationTests.SideEffectExecutorTests'`，27 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'OrchestrationTests.OutputLifecycleTests|OrchestrationTests.ExecutionEngineTests|OrchestrationTests.AgentExecutorTests'`，56 tests，0 failures。
  - 绿灯：touched Swift files `swiftlint lint --strict ...`，0 violations。
  - 绿灯：`git diff --check`，passed。

## 已完成实现细节

### Output lifecycle foundation

- 新增 `OutputInvocationContext`，由 `ExecutionEngine` 在 prompt / agent 两条路径构造并传给 `OutputDispatcher`。
- `ExecutionEngine` 在 streaming chunk 期间累积 final text，并在 finish 阶段把完整输出交给 output sink 与 side effect executor。
- `MockOutputDispatcher` 增加 lifecycle call 记录，覆盖 prompt 与 agent 路径。

### SideEffect executor

- 新增 `SideEffectExecutorProtocol`、`SideEffectExecutionOutcome` 和 concrete `SideEffectExecutor`。
- `copyToClipboard`、`appendToFile`、`notify`、`callMCP`、`tts` 已有执行边界；`writeMemory` 明确返回 Phase 3 unsupported。
- `ExecutionEngine.runSideEffects` 在 permission gate 通过后调用 executor，只有 `.executed` 才发 `.sideEffectTriggered` 与 audit。

### `.silent` / `.file`

- `.silent` chunk / finish 均不写 window sink。
- `.file` chunk 阶段不写 window sink，finish 阶段从 `outputBinding.sideEffects` 读取首个 `appendToFile` 目标并写入 final text；缺少目标时返回 configuration failure。
- 旧 `OutputDispatcher.handle(chunk:mode:invocationId:)` 已桥接到 lifecycle 路由，避免旧调用方继续把 `.silent/.file` fallback 到 window。
- `.file` 主输出已经消费的 `appendToFile` 会从 `runSideEffects` 实执行列表中过滤，避免文件重复写入；其它 side effect 仍照常执行。

## 变动文件清单

- `SliceAIKit/Sources/Orchestration/Output/OutputDispatcherProtocol.swift`
- `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift`
- `SliceAIKit/Sources/Orchestration/Output/FinalTextFileAppender.swift`
- `SliceAIKit/Sources/Orchestration/Output/SideEffectExecutor.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+OutputLifecycle.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`
- `SliceAIKit/Sources/Orchestration/Flow/FlowContext.swift`
- `SliceAIKit/Tests/OrchestrationTests/Helpers/MockOutputDispatcher.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/OutputLifecycleTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/SideEffectExecutorTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/OutputDispatcherFallbackTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/OutputDispatcherTests.swift`

## 下一步

提交 `.silent` / `.file` 后进入 plan Task 4：`.replace` DisplayMode。
