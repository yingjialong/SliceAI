# Phase 1 M3 Task 13 · Built-In web-search-summarize Agent Tool

## 任务背景

Task 11 已实现 AgentExecutor ReAct loop，Task 12 已让 ResultPanel 显示 MCP tool-call lifecycle。当前默认配置仍只有 4 个 prompt tool，用户首次启动后没有可直接试用的内置 Agent 工具。本任务要新增一个首方 `web-search-summarize` Agent tool，使用 Brave Search MCP 搜索并总结选中内容，同时声明 tool-calling provider 能力需求和 MCP 权限，形成 Phase 1 Agent 功能的默认入口。

## 当前计划差异

Phase 1 plan 中的 `DefaultConfigurationTests.swift` 在当前代码库不存在，默认配置测试实际位于 `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`。本任务会在该文件中新增/更新默认配置测试。计划还列出 `ToolEditorView+Sections.swift`，但当前设置页已有 `unsupportedKindCard` 对 Agent/Pipeline 做只读提示；在没有明确 UI 行为缺口前，本任务不为该文件制造额外 diff。

实现过程中发现仅把默认工具声明为 `.capability(requires: [.toolCalling])` 不够：`DefaultProviderResolver` 仍把 `.capability` 视为未实现，会导致内置 Agent tool 在执行链路上无法选中 provider。因此本任务同步补齐 `.capability` provider routing；这不是偏离方向，而是让计划中的 provider capability requirement 真正可执行的必要闭环。

## 实施方案

1. 按 TDD 先更新默认配置测试：默认工具数量变为 5，新增 `web-search-summarize`，并验证它是 `.agent`、声明 Brave Search MCP 权限、provider selection 要求 `.toolCalling`。
2. 运行 `swift test --filter SliceCoreTests.ConfigurationTests` 确认红灯，预期失败原因为默认配置缺少新工具。
3. 在 `DefaultConfiguration.initial()` 中加入 `webSearchSummarize`，用实际 `ContextRequest` / `ProviderSelection` 初始化签名实现计划中的 tool shape。
4. 补齐 `DefaultProviderResolver` 的 `.capability` 路由：先按 `requires` 过滤，再按 `prefer` 选优，否则回退到第一个满足能力的 provider；无匹配时返回显式错误。
5. 跑 focused tests、ToolTests 回归、全量 SwiftPM、targeted lint、App Debug build。
6. 更新任务文档和 Task_history，提交实现后按用户要求运行 `claude-review-loop`。

## ToDoList

- [x] 创建 Task 13 任务文档并登记 Task_history。
- [x] 编写默认配置红灯测试。
- [x] 运行测试确认 red。
- [x] 实现 `web-search-summarize` 默认 Agent tool。
- [x] 实现 provider `.capability` 路由闭环。
- [x] 运行 focused tests、回归测试、targeted lint、App Debug build。
- [x] 更新任务文档的变动文件、代码修改逻辑、测试结果。
- [ ] 提交 commit。
- [ ] 运行 `claude-review-loop` 并记录结果。

## 变动文件

- `README.md`：更新功能列表和 Phase 1 M3 Task 13 变更记录。
- `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`：新增 `webSearchSummarize` 默认 Agent tool，并加入 `DefaultConfiguration.initial().tools`。
- `SliceAIKit/Sources/Orchestration/Engine/ProviderResolver.swift`：实现 `.capability` provider routing。
- `SliceAIKit/Sources/Orchestration/Engine/ProviderResolutionError.swift`：新增无 provider 满足能力要求的显式错误。
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`：把 capability routing 失败映射为配置校验失败事件。
- `SliceAIKit/Sources/Orchestration/Engine/FlowContext.swift`：将共享流程上下文从 step 文件抽出，消除本次新增分支触发的 file length lint。
- `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`：新增默认配置红绿测试，覆盖内置 Agent tool、MCP 权限和 provider capability。
- `SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift`：同步首次启动默认工具数量断言，从 4 改为 5。
- `SliceAIKit/Tests/OrchestrationTests/ProviderResolverTests.swift`：新增 `.capability` 路由测试，覆盖 prefer、fallback 和无匹配错误。
- `docs/Task_history.md`：登记 Task 13。
- `docs/Task-detail/2026-05-08-phase-1-m3-task-13-web-search-summarize-agent-tool.md`：记录任务过程与验证结果。

## 代码修改逻辑

1. `DefaultConfiguration.initial()` 仍保留旧 4 个 prompt tools 的顺序和类型，只在末尾追加 `webSearchSummarize`，降低既有浮条/命令面板排序漂移风险。
2. `webSearchSummarize` 使用 `.agent(AgentTool(...))`，`initialUserPrompt` 读取 `{{selection}}`，并通过 `ContextRequest(provider: "selection", requiredness: .required)` 显式要求选区上下文。
3. Provider 选择改用 `.capability(requires: [.toolCalling], prefer: [])`，避免普通 prompt-only provider 执行 Agent tool。
4. MCP allowlist 和 tool permissions 使用同一个 Brave Search ref：`brave-search.brave_web_search`；allowlist 控制 AgentExecutor 可调用工具，permissions 控制 PermissionGraph / PermissionBroker fail-closed。
5. 默认 OpenAI compatible provider 标记为 `[.toolCalling]`，使默认配置中唯一的内置 Agent tool 能被 capability routing 命中；旧 prompt tools 不依赖该能力。
6. `DefaultProviderResolver` 对 `.capability` 的处理保持 KISS：只做集合包含判断、`prefer` 顺序选择和首个可用 fallback，不引入评分或模型探测。
7. 无 provider 满足能力要求时抛出 `noProviderMatchingCapabilities`，`ExecutionEngine` 捕获后转成 `.configuration(.validationFailed(...))`，避免被泛化为未知错误。
8. `FlowContext` 抽到独立文件是 lint 修复，不改变引用语义和 actor-isolated 使用方式；这是因为本任务新增 catch 分支让原文件超过 500 行阈值。
9. `ToolEditorView+Sections.swift` 未修改：当前 `unsupportedKindCard` 已能对 Agent/Pipeline 做只读提示，本任务不扩展 Agent 编辑器，避免无需求的 UI scope creep。
10. README 同步从“4 个内置工具”改为“4 个 prompt tools + 1 个 Agent tool”，避免项目说明和默认配置不一致。

## 测试计划

- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationTests`
- `cd SliceAIKit && swift test --filter SliceCoreTests.ToolTests`
- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationStoreTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.ProviderResolverTests`
- `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`
- `cd SliceAIKit && swift test`
- `git diff --check`
- `swiftlint lint --strict <Task 13 touched Swift files>`
- `swiftlint lint --strict`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

## 测试结果

- Red：`cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationTests` 初次失败，4 failures，原因是默认配置仍只有 4 个工具且找不到 `web-search-summarize`，符合 TDD 预期。
- Red：补充 provider routing 测试后，`ProviderResolverTests` 编译失败，原因是 `ProviderResolutionError.noProviderMatchingCapabilities` 尚不存在，符合“capability routing 未实现”的红灯预期。
- Green：`cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationTests` 通过，9 tests。
- Green：`cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationStoreTests` 通过，15 tests。
- Green：`cd SliceAIKit && swift test --filter SliceCoreTests.ToolTests` 通过，14 tests。
- Green：`cd SliceAIKit && swift test --filter OrchestrationTests.ProviderResolverTests` 通过，7 tests。
- Green：`cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests` 通过，19 tests。
- Green：`cd SliceAIKit && swift test` 最终通过，712 tests。期间一次全量测试触发既有取消时序测试 `test_execute_cancellationDuringPromptStream_skipsLaterChunkDispatch` 的瞬时失败；单测复跑通过，随后全量复跑通过，未改业务代码。
- Green：`git diff --check` 通过。
- Green：`swiftlint lint --strict SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift SliceAIKit/Sources/Orchestration/Engine/ProviderResolver.swift SliceAIKit/Sources/Orchestration/Engine/ProviderResolutionError.swift SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift SliceAIKit/Sources/Orchestration/Engine/FlowContext.swift SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift SliceAIKit/Tests/OrchestrationTests/ProviderResolverTests.swift` 通过，0 violations。测试文件被当前 SwiftLint 配置排除，实际 lint 了 5 个源文件。
- Known historical blocker：`swiftlint lint --strict` 全仓仍失败，13 个既有违规均不在本任务新增/修改文件中，主要位于 `MCPServersPage.swift`、`StdioMCPClient.swift`、`MCPDiagnosticLog.swift`、`PersistentPermissionGrantStore.swift`、`MCPServerStore.swift`、`ClaudeDesktopMCPImporter.swift`、`PermissionBroker.swift`、`AppPermissionConsentPresenter.swift`。
- Green：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过。

## Self-review

已检查新默认工具不会改变旧 4 个 prompt tools 的类型与顺序；Agent tool 的 MCP allowlist 与 declared permission 保持一致；provider selection 明确要求 `.toolCalling`，且 provider resolver 已能实际执行该选择策略。设置页当前对 Agent tool 只读展示，不在本任务扩展编辑能力，符合 KISS。
