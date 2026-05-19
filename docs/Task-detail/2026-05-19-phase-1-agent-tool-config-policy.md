# Phase 1 Agent Tool Config And MCP Policy

## 任务背景

用户复测 `Web Search Summarize` 时暴露出两个更大的问题：

1. MCP 限流不是 Brave 独有，所有 MCP tool 都可能遇到调用次数、重复参数、慢查询、成本或副作用风险。
2. 任务启动时 Phase 1 只实现了内置 `web-search-summarize` Agent Tool，Settings UI 仍只能编辑 `.prompt` 工具，用户无法自定义一个类似的 MCP Agent。

重新核对总 spec 后，Phase 1 的冻结目标应包括 MCP 主干和基础自定义 Agent Tool；Skill 则属于 Phase 2，不应作为 v0.3 blocker。

## 实施方案

1. 修正 spec / plan / TodoList 的 Phase 1 口径：MCP 是 Phase 1，Skill 是 Phase 2；Phase 1 仍缺基础 Agent Tool 编辑器、MCP allowlist 和独立 tool-call policy。
2. 在 SliceCore 增加 `AgentToolCallPolicy`，把 MCP 调用预算从 `maxSteps` 拆出来；`maxSteps` 只表示 LLM ReAct 轮数。
3. 在 AgentExecutor 中按 policy 控制总调用数、单轮调用数、每 tool 调用数、重复参数和限流后停止。
4. 在 Settings UI 中补最小可用 Agent 编辑能力：新增 Agent Tool、编辑 system / initial prompt、选择 provider、编辑 maxSteps、用文本格式配置 MCP allowlist，并配置总 MCP 上限、单轮上限、重复参数和限流停止策略。
5. 保持 Skill、完整 MCP tool picker、多 DisplayMode、Prompt IDE 不进入本任务。

## ToDoList

- [x] 修正总 spec 的 Phase 1 / Phase 2 口径。
- [x] 修正 master TodoList 当前状态。
- [x] 修正 Phase 1 plan，记录 Task 18 scope。
- [x] 新建本任务文档并登记 Task_history。
- [x] 增加 `AgentToolCallPolicy` 数据模型测试。
- [x] 实现 `AgentToolCallPolicy` 数据模型。
- [x] 增加 AgentExecutor tool-call policy 行为测试。
- [x] 实现 AgentExecutor 通用 MCP 调用策略。
- [x] 增加 Settings UI MCP allowlist 文本解析测试。
- [x] 实现最小 Agent Tool 编辑 UI。
- [x] 更新默认 `web-search-summarize` 配置和本机配置。
- [x] 运行 focused tests。
- [x] 运行全量 SwiftPM、SwiftLint、Xcode build。
- [x] 更新 README、Task 17/56 文档和 handoff。

## 设计约束

- KISS：先用 `server.tool` 文本格式编辑 MCP allowlist，不在本任务做完整图形化 MCP picker。
- 安全：修改 allowlist 时同步 `tool.permissions` 中的 MCP 权限，避免 PermissionGraph 声明闭环失效。
- 兼容：旧 config 中缺少 `toolCallPolicy` 的 Agent 仍能 decode；默认通用策略不应强制套用 Brave 的 2 次限制。
- 可观测：跳过重复、预算耗尽、限流停止都通过现有 `toolCallError` row 展示，并通过脱敏日志记录。

## 变动文件清单

- `SliceAIKit/Sources/SliceCore/AgentToolCallPolicy.swift`：新增 Agent MCP 调用策略模型。
- `SliceAIKit/Sources/SliceCore/ToolKind.swift`：`AgentTool` 增加可选 `toolCallPolicy`，旧配置缺字段仍可 decode。
- `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`：`web-search-summarize` 增加显式 policy，`maxSteps` 回到 LLM 轮数语义。
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`：移除 `maxSteps` 作为总 MCP 调用预算的逻辑。
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`：新增运行期 policy state，控制总量、单轮量、单工具量、重复参数和限流停止。
- `SliceAIKit/Sources/SettingsUI/ToolEditorView*.swift`：Settings UI 支持基础 Agent 编辑、MCP allowlist 文本配置和 MCP 调用策略配置。
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`、`SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Actions.swift`：新增“添加 Prompt / 添加 Agent”入口，并把工具增删改动作拆出，避免设置页主体继续膨胀。
- `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`：覆盖 maxSteps 语义、policy 总量、重复参数和限流停止。
- `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`、`SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`：覆盖 schema 兼容和默认配置。
- `SliceAIKit/Tests/SettingsUITests/ToolEditorAgentAllowlistCodecTests.swift`：覆盖 allowlist 文本编解码。

## 代码修改逻辑

1. `AgentTool.maxSteps` 只控制 LLM ReAct 轮数，不再控制 MCP 调用总数。
2. `AgentToolCallPolicy` 独立表达 MCP 调用策略：`maxTotalCalls`、`maxCallsPerTurn`、`perToolLimits`、`duplicateArgumentStrategy` 和 `stopOnRateLimit`。
3. 未配置 policy 的 Agent 使用通用兜底：每轮最多每个 allowlist tool 调用一次，总量为 `maxSteps * allowlist.count`；这不是 Brave 特例，不会把所有 MCP 都强制限制为 2 次。
4. `web-search-summarize` 作为内置示例显式配置最多 2 次 Brave 搜索、跳过重复参数、命中 rate limit 后停止继续调用 MCP。
5. Settings UI 先用 KISS 的 `server.tool` 文本格式编辑 Agent MCP allowlist，写入时同步 `tool.permissions` 的 MCP 权限声明，避免 allowlist 与权限图脱节。
6. Settings UI 暴露最小 policy 控件：总 MCP 上限、单轮 MCP 上限、跳过重复参数、限流后停止；per-tool limits 暂不做 UI，内置工具仍可通过配置显式声明。

## 测试结果

- 已通过：`swift test --package-path SliceAIKit --filter 'AgentExecutorTests|ToolKindTests|ConfigurationTests|ToolEditorAgentAllowlistCodecTests'`（72 tests）。
- 已通过：`swift test --package-path SliceAIKit`（756 tests；第一次全量跑出现 1 个未复现瞬时失败，随后复跑通过）。
- 已通过：`swiftlint lint --strict`（172 files，0 violations）。
- 已通过：`git diff --check`。
- 已通过：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`。
- 已通过：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug -derivedDataPath build/e2e build`。
- 已重启 Debug App：`build/e2e/Build/Products/Debug/SliceAI.app`，进程 `13394`。

## 当前状态

代码侧的基础 Agent Tool 配置与通用 MCP tool-call policy 已实现并通过完整本地 gate；用户已基本复测 Task 17 App 场景且未反馈阻塞问题。后续 Task 57 已在 `main` 上完成最终 release gate / Claude review loop / 本地 DMG 预检；下一步只剩用户确认后的远端 push、`v0.3.0` tag 和 GitHub Release 发布流程。
