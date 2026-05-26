# 2026-05-26 · Phase 2 Completion

## 背景

Task 58-62 已完成 Phase 2 前半段：Skill Registry MVP、真实本地 skill E2E、公开 skill 仓库 smoke，以及 supporting files 只读加载。本任务启动时，Phase 2 还不能标记完成，因为多 DisplayMode、真实 side effects、TTS 和 English Tutor 仍未落地。

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
- [x] 按 TDD 实施 `.replace`。
- [x] 按 TDD 实施 `.bubble` 与 `.structured`。
- [x] 按 TDD 实施 TTS capability。
- [x] 按 TDD 实施 `english-tutor` 默认工具。
- [x] 完成 App wiring。
- [ ] 完成真实手工 smoke。
- [x] 跑最终 automated gate 并更新文档结果。

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
- Replace DisplayMode：
  - 红灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.ReplaceDisplayModeTests` 首次因 `TextReplacementClient` / `TextReplacementResult` 与 `OutputDispatcher(replacementClient:)` 缺失编译失败。
  - 红灯：`.replace` 生产实现后，旧 fallback 测试仍断言 replace 写 window sink，触发越界崩溃；已修正为 replace 不落窗。
  - 绿灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.ReplaceDisplayModeTests`，4 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'OrchestrationTests.ReplaceDisplayModeTests|OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.OutputDispatcherTests|OrchestrationTests.OutputLifecycleTests'`，25 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'OrchestrationTests.ReplaceDisplayModeTests|OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.OutputDispatcherTests|OrchestrationTests.OutputLifecycleTests|OrchestrationTests.ExecutionEngineTests'`，44 tests，0 failures。
  - 绿灯：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`，BUILD SUCCEEDED。
  - 绿灯：touched Swift files `swiftlint lint --strict ...`，0 violations。
- Bubble / Structured DisplayMode：
  - 红灯：`swift test --package-path SliceAIKit --filter WindowingTests.StructuredResultViewStateTests` 首次因 `StructuredResultParser`、`StructuredField`、`StructuredResultParseError` 与 `BubblePresentationState` 缺失编译失败。
  - 红灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.BubbleStructuredDisplayModeTests` 首次因 `BubbleOutputSink` / `StructuredOutputSink` 与 `OutputDispatcher` 注入点缺失编译失败；修正测试并发 snapshot 后红灯来源收敛到待实现协议。
  - 绿灯：`swift test --package-path SliceAIKit --filter WindowingTests.StructuredResultViewStateTests`，3 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.BubbleStructuredDisplayModeTests`，3 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'WindowingTests|OrchestrationTests.OutputLifecycleTests|OrchestrationTests.BubbleStructuredDisplayModeTests|OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.OutputDispatcherTests'`，36 tests，0 failures。
  - 绿灯：`swiftlint lint --strict`，190 files，0 violations。
  - 绿灯：`git diff --check`，passed。
  - 绿灯：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`，BUILD SUCCEEDED。
- TTS capability：
  - 红灯：`swift test --package-path SliceAIKit --filter 'CapabilitiesTests.TTSCapabilityTests|OrchestrationTests.SideEffectExecutorTests'` 首次因 `SpeechSynthesizing`、`TTSRequest`、`AVSpeechTTSCapability` 缺失编译失败。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'CapabilitiesTests.TTSCapabilityTests|OrchestrationTests.SideEffectExecutorTests'`，12 tests，0 failures。
  - 红灯：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 首次因 App target 默认 `MainActor` 隔离导致文件级 logger 被非隔离 side-effect adapter 访问而失败。
  - 绿灯：局部 logger 修复后，`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`，BUILD SUCCEEDED。
  - 绿灯：`swiftlint lint --strict`，192 files，0 violations。
  - 绿灯：`git diff --check`，passed。
- English Tutor 默认工具：
  - 红灯：`swift test --package-path SliceAIKit --filter 'SliceCoreTests.ConfigurationTests|SliceCoreTests.ConfigurationStoreTests|SliceCoreTests.ConfigMigratorV1ToV2Tests|CapabilitiesTests.LocalSkillRegistryTests'` 首次因 schema 仍为 3、默认工具缺失、v3 迁移未补入 English Tutor、registry 未暴露内置 skill 而失败。
  - 红灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.SideEffectExecutorTests/test_execute_tts_prefersStructuredTTSText` 首次因 TTS 朗读整段 structured JSON 而失败。
  - 绿灯：`swift test --package-path SliceAIKit --filter 'SliceCoreTests.ConfigurationTests|SliceCoreTests.ConfigurationStoreTests|SliceCoreTests.ConfigMigratorV1ToV2Tests|CapabilitiesTests.LocalSkillRegistryTests'`，55 tests，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.SideEffectExecutorTests/test_execute_tts_prefersStructuredTTSText`，1 test，0 failures。
  - 绿灯：`swift test --package-path SliceAIKit --filter SettingsUITests`，24 tests，0 failures。
  - 绿灯：`jq empty config.schema.json`，passed。
- Final automated gate：
  - 红灯：首次 `swift test --package-path SliceAIKit` 因 `AgentExecutorSkillE2ETests` 把内置 `english-tutor` skill 一并暴露给 fixture E2E 而失败；已把该测试收敛到 `project-skills` source。
  - 绿灯：`swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorSkillE2ETests`，0 failures。
  - 红灯：一次全量 SwiftPM 回归因既有取消测试 `ExecutionEngineTests/test_execute_cancellationDuringPermissionGate_skipsAuditAndLLM` 调度竞态失败；focused rerun 通过，未修改生产逻辑。
  - 绿灯：`swift test --package-path SliceAIKit`，837 tests，1 skipped，0 failures。
  - 绿灯：`swiftlint lint --strict`，194 files，0 violations。
  - 绿灯：`git diff --check`，passed。
  - 绿灯：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`，BUILD SUCCEEDED。
  - 绿灯：`bash scripts/phase2-public-skill-smoke.sh`，3 repositories / 9 public skills。
- 真实 App 手工 smoke：
  - 未执行。该项会启动真实 App，并可能临时备份 / 修改 `~/Library/Application Support/SliceAI/config-v2.json`、触发系统剪贴板、选区替换、通知和本地 TTS；执行前需要用户确认具体读写边界。

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

### `.replace`

- 新增 `TextReplacementClient` 与 `TextReplacementResult`，让 Orchestration 只依赖协议，不直接 import AppKit。
- `OutputDispatcher` 对 `.replace` 的 streaming chunk 不写 window；finish 阶段用完整 final text 调用 replacement client。
- `AppTextReplacementClient` 在 App 层先尝试 AX `kAXSelectedTextAttribute` 直接替换；失败时把 final text 写入剪贴板并发本地通知，日志只记录长度和结果，不记录用户文本。
- AppContainer 已注入 `AppTextReplacementClient`；AppDelegate 对 `.replace`、`.file`、`.silent` 不再提前打开空 ResultPanel，失败时才打开面板展示错误。

### `.bubble` / `.structured`

- 新增 `BubbleOutputSink` / `StructuredOutputSink`，Orchestration 只依赖 final-only 协议，不 import Windowing。
- `OutputDispatcher` 对 `.bubble` 与 `.structured` 的 chunk 阶段不写 window；finish 阶段使用完整 final text 调用对应 sink，缺少 sink 时返回配置错误。
- Windowing 新增 `BubblePresentationState`、`BubblePanel`、`StructuredResultParser` 和 `StructuredResultView`。`StructuredResultParser` 要求顶层 JSON object，支持 string / number / bool / array / object / null，并按 key 排序保证稳定渲染。
- `ResultPanel` 新增 structured 字段展示状态；`.structured` 执行开始时仍打开 ResultPanel 展示等待态和 tool-call lifecycle，finish 后切换到结构化视图。
- `AppBubbleOutputSink` / `AppStructuredOutputSink` 已在 AppContainer 注入；`.bubble` 不再提前打开空 ResultPanel，finish 后展示自动消失气泡。
- Settings Tool Editor 已开放 `.structured` 展示模式；`.file` / `.silent` 仍不在基础编辑器暴露，因为它们依赖高级 outputBinding / side effect 配置。

### TTS capability

- 新增 `TTSCapability`、`TTSRequest`、`TTSCapabilityError` 和 `AVSpeechTTSCapability`。
- `AVSpeechTTSCapability` 通过注入的 `SpeechSynthesizing` 便于单测，生产默认使用 `AVFoundationSpeechSynthesizer`。
- `AVFoundationSpeechSynthesizer` 在主线程提交 `AVSpeechUtterance`，支持按 voice identifier 或 voice name 解析系统 voice；找不到 voice 时降级到系统默认 voice。
- `SideEffectExecutor` 已从临时 `TextSpeaking` 协议收敛到 `Capabilities.TTSCapability`，避免 Orchestration 重复定义 TTS 抽象。
- 新增 `MockTTSCapability`，用于测试和预览记录请求，不触发真实发声。
- App 层新增 `AppClipboardWriter` 与 `AppUserNotifier`，并在 `AppContainer` 中把真实 `SideEffectExecutor` 注入 `ExecutionEngine`。
- dry-run 下 TTS side effect 会 yield `.sideEffectSkippedDryRun`，不会调用真实 executor 或发声。

### English Tutor 默认工具

- 新增 `EnglishTutorToolFactory`，集中构造首方 `english-tutor` Agent Tool，避免默认配置文件直接堆叠 Agent 细节。
- `english-tutor` 使用 `.structured` 主输出、`.tts(voice: nil)` side effect、`.systemAudio` 权限和 `.capability(requires: [.toolCalling])` provider 选择。
- `Configuration.currentSchemaVersion` 提升到 4；`ConfigurationStore` 在加载 v3 配置时只补入一次 English Tutor，v4 用户删除后不再重加。
- `config.schema.json` 已同步到 schemaVersion 4。
- 新增 `BundledSkillCatalog`，`LocalSkillRegistry.snapshot()` 默认加入首方内置 `english-tutor` skill，`loadSkillInstructions(id:)` 对内置 skill 直接返回内存中的 `SKILL.md` payload，不依赖用户本地 skill root。
- `SideEffectExecutor` 在 final text 是顶层 JSON object 且包含非空 `ttsText` 时，优先朗读该字段；普通文本仍按原 final text 朗读。

## 变动文件清单

- `SliceAIKit/Sources/Orchestration/Output/OutputDispatcherProtocol.swift`
- `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift`
- `SliceAIKit/Sources/Orchestration/Output/FinalTextFileAppender.swift`
- `SliceAIKit/Sources/Orchestration/Output/SideEffectExecutor.swift`
- `SliceAIKit/Sources/Orchestration/Output/TextReplacementClient.swift`
- `SliceAIKit/Sources/Orchestration/Output/FinalDisplaySinks.swift`
- `SliceAIKit/Sources/Capabilities/TTS/TTSCapability.swift`
- `SliceAIKit/Sources/Capabilities/TTS/MockTTSCapability.swift`
- `SliceAIKit/Sources/Capabilities/Skills/BundledSkillCatalog.swift`
- `SliceAIKit/Sources/Capabilities/Skills/LocalSkillRegistry.swift`
- `SliceAIKit/Sources/SliceCore/EnglishTutorToolFactory.swift`
- `SliceAIKit/Sources/SliceCore/Configuration.swift`
- `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift`
- `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+OutputLifecycle.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`
- `SliceAIKit/Sources/Orchestration/Flow/FlowContext.swift`
- `SliceAIKit/Sources/Windowing/BubblePanel.swift`
- `SliceAIKit/Sources/Windowing/StructuredResultState.swift`
- `SliceAIKit/Sources/Windowing/StructuredResultView.swift`
- `SliceAIKit/Sources/Windowing/ResultPanel.swift`
- `SliceAIKit/Sources/Windowing/ResultContentView.swift`
- `SliceAIKit/Tests/OrchestrationTests/Helpers/MockOutputDispatcher.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/OutputLifecycleTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/SideEffectExecutorTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/OutputDispatcherFallbackTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/ReplaceDisplayModeTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/Output/BubbleStructuredDisplayModeTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/TTSCapabilityTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/LocalSkillRegistryTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ConfigMigratorV1ToV2Tests.swift`
- `SliceAIKit/Tests/OrchestrationTests/OutputDispatcherTests.swift`
- `SliceAIKit/Tests/WindowingTests/StructuredResultViewStateTests.swift`
- `SliceAIApp/AppContextAdapters.swift`
- `SliceAIApp/AppContainer.swift`
- `SliceAIApp/AppDelegate+Execution.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Support.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`
- `config.schema.json`

## 下一步

完成真实 App 手工 smoke，或由用户确认以 automated gate 作为本阶段收口边界后再关闭 goal。
