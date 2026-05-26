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
- [ ] 按 TDD 实施 SideEffect executor。
- [ ] 按 TDD 实施 `.silent` 与 `.file`。
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

## 下一步

提交 Output lifecycle foundation 后进入 plan Task 2：SideEffect executor。
