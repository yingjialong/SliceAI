# 2026-05-28 · Phase 3 Task 6 Playground State Reducer

## 背景

用户要求作为 Phase 3 ToolEditor v2 + Prompt Playground MVP 的实现 worker，执行 Task 6：新增 SettingsUI Playground 状态 reducer，把 Orchestration 的 `ExecutionEvent` 转换为右侧 Playground UI 可展示的状态。

本任务承接 Task 1-5 的运行策略、Playground runner 和 ToolEditor 草稿状态；只处理 UI-facing state reducer 与 focused tests，不接入完整 Playground 视图。

## 任务目标

- 新增 `ToolPlaygroundState`，统一记录输入上下文、运行状态、streaming 输出、prompt preview、tool-call rows、permission rows、dry-run side effects、DisplayMode 预览、report 和错误文案。
- 支持 `.window`、`.bubble`、`.replace`、`.file`、`.silent`、`.structured` 的 dry-run 预览摘要。
- 解析 `.structured` final text 的顶层 JSON object key，非法 JSON 返回受控 parse error。
- 补齐 `SettingsUITests` 对 `Orchestration` 的 test dependency。
- 用 focused reducer tests 覆盖事件累积、结构化预览、文件预览、权限/prompt 记录、report/error summary。

## ToDoList

- [x] Step 1：创建 `ToolPlaygroundStateTests`，写 reducer 行为测试。
- [x] Step 2：运行指定 focused test，确认 `ToolPlaygroundState` 缺失导致红灯。
- [x] Step 3：检查并补 `SettingsUITests` 的 `Orchestration` 依赖。
- [x] Step 4：新增 `ToolPlaygroundState.swift` 实现 reducer 和 preview helpers。
- [x] Step 5：运行 focused reducer tests。
- [x] Step 6：更新任务文档并提交 `feat: add tool playground state reducer`。

## 设计边界

- KISS：状态 reducer 只消费现有 `ExecutionEvent`，不启动执行、不读写配置、不持有 UI 对象。
- 安全：日志/摘要不记录密钥；permission、report、side effect 只展示短文本和路径。
- 结构化预览：MVP 只验证顶层 JSON object 并列出 key，不在 reducer 内构造完整字段树，避免和后续 UI 渲染重复。
- DisplayMode：以 `Tool.displayMode` 为事实源；`.file` 只从 `outputBinding.sideEffects.appendToFile` 提取 dry-run 目标路径。

## 实施记录

1. 新增 `ToolPlaygroundStateTests`，覆盖 streaming chunk 累积、structured JSON 顶层 object key 解析、`.file` append dry-run 摘要、prompt preview / permission dry-run 记录、InvocationReport tokens / cost / flags 摘要和 SliceError 用户文案。
2. 首次按用户指定命令运行 RED 时被本地 `.build` Swift 6.2/6.3 产物混用截断；改用唯一 `--scratch-path` 后得到预期编译失败，缺少 `ToolPlaygroundState`。
3. `SettingsUI` target 已在 Task 4 提前依赖 `Orchestration`；本任务补齐 `SettingsUITests` 的 `Orchestration` test dependency，保证 reducer tests 可直接导入 `ExecutionEvent` 与 `InvocationReport`。
4. 新增 `ToolPlaygroundRunStatus`、`ToolPlaygroundPreviewKind`、`ToolPlaygroundDisplayPreview` 和 `ToolPlaygroundState`。
5. `reduce(_:,tool:)` 处理 `.started`、`.promptRendered`、`.permissionWouldBeRequested`、`.llmChunk`、MCP tool-call lifecycle、`.sideEffectSkippedDryRun`、`.finished` 和 `.failed`。`.started` 会重置上次运行输出、权限、tool-call、side effect、report 和错误；`.finished` 生成 report summary 与 DisplayMode preview；`.failed` 清理上一轮 run-scoped 状态后展示用户可读错误文案。
6. DisplayMode 预览按 `Tool.displayMode` 生成：`.window` 显示 final text，`.bubble` / `.replace` / `.silent` 使用 dry-run 摘要，`.file` 从 `outputBinding.sideEffects.appendToFile` 提取目标路径，`.structured` 只解析顶层 JSON object key。
7. reducer 增加低敏日志：started 记录 invocation id，finished 记录 tool id，failed 记录 `SliceError.developerContext`，不记录 selection、prompt 原文或 streaming 输出。

### Review follow-up

1. `.failed` 分支现在复用 `clearRunScopedFields(for:)`，与 `.started` 一样清理 `streamedText`、prompt preview、tool-call rows、permission rows、skipped side effects、last report、report summary、error message 和 DisplayMode preview，避免 invalid draft 这类只产出 `.failed` 的路径显示上一轮输出。
2. `.structured` preview 对空字符串和纯空白返回空摘要，不再把 `.started` 初始态误显示为 `structured parse error`；非空非法 JSON 和 array/non-object JSON 仍返回受控 parse error。
3. 新增 `markCancelling()` 作为 UI 进入 `.cancelling` 状态的集中入口，不新增 `ExecutionEvent`。

## 实现结果

已完成 Task 6 范围和 review follow-up。SettingsUI 现在具备 Prompt Playground 右侧面板可复用的纯状态 reducer，后续 Task 7 可直接把 `ToolPlaygroundRunner` 的 `ExecutionEvent` 流 reduce 到该状态并渲染 UI，取消按钮可调用 `state.markCancelling()`。

## 变动文件清单

- `SliceAIKit/Package.swift`
- `SliceAIKit/Sources/SettingsUI/ToolPlaygroundState.swift`
- `SliceAIKit/Tests/SettingsUITests/ToolPlaygroundStateTests.swift`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-28-phase-3-task-6-playground-state-reducer.md`

## 测试记录

- Cache issue：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter SettingsUITests.ToolPlaygroundStateTests` 被旧 `.build` Swift 6.2.3 产物阻塞，Swift 6.3.2 无法导入旧 `SliceCore.swiftmodule`。
- Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task6-red-20260528-01 --filter SettingsUITests.ToolPlaygroundStateTests` 编译失败，符合预期；缺少 `ToolPlaygroundState`。
- Focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task6-focused-20260528-02 --filter SettingsUITests.ToolPlaygroundStateTests` 通过，5 tests，0 failures。构建阶段仍出现既有 `CapabilitiesTests/MCPServerStoreTests.swift` unused-result warning，非本任务文件。
- Whitespace：`git diff --check` 通过。
- Lint note：尝试运行 `swiftlint lint --strict --path SliceAIKit/Sources/SettingsUI/ToolPlaygroundState.swift --path SliceAIKit/Tests/SettingsUITests/ToolPlaygroundStateTests.swift`，本机 `swiftlint` 不在 PATH，未能执行；本任务未扩大安装工具范围。
- Review follow-up Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task6-fix-red-20260528-01 --filter SettingsUITests.ToolPlaygroundStateTests` 编译失败，符合预期；新增测试调用的 `markCancelling()` 尚不存在。
- Review follow-up Focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task6-fix-focused --filter SettingsUITests.ToolPlaygroundStateTests` 通过，9 tests，0 failures。构建阶段仍出现既有 `CapabilitiesTests/MCPServerStoreTests.swift` unused-result warning，非本任务文件。
- Review follow-up Whitespace：`git diff --check` 通过。
