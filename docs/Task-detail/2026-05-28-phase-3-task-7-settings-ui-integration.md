# 2026-05-28 · Phase 3 Task 7 Settings UI Integration

## 背景

用户要求作为 Phase 3 ToolEditor v2 + Prompt Playground MVP 的实现 worker，执行 Task 7：把前序 Task 1-6 已完成的 Playground runner、ToolEditor 草稿状态和 Playground reducer 接入 Settings Tools 页面。

本任务承接 Task 4 的 `SettingsViewModel.playgroundRunner`、Task 5 的 `ToolDraftValidator.commandPaletteEnabled` 参数，以及 Task 6 的 `ToolPlaygroundState.markCancelling()`。

## 任务目标

- 新增右侧 `ToolPlaygroundView`，支持 selection 输入、MCP 开关、Run / Cancel / Clear、prompt preview、权限提示、tool-call lifecycle、side effect dry-run、report 和错误展示。
- 新增 `ToolEditorV2View`，组合左侧 `ToolEditorView` 草稿编辑器和右侧 Playground。
- 将 Tools 设置页从直接绑定 `configuration.tools[index]` 改为 `ToolEditorDraftSession`，只有 Save 写回正式配置。
- Add Prompt / Add Agent 只创建 `.creating` 草稿，不立即 mutate `configuration.tools`。
- Save / Revert 共用草稿校验；Playground Run 与 Save 共用 `validateDraftForRun`，并显式传入 `configuration.triggers.commandPaletteEnabled`。
- Settings 窗口从 `720×520` 调整到 `980×620`，容纳双栏编辑器。

## ToDoList

- [x] Step 1：读取现有 SettingsUI / Orchestration 接口，确认 Task 4-6 前置修正已存在。
- [x] Step 2：在 `ToolEditorDraftStateTests` 补充 Task 7 相关草稿校验测试并运行红灯。
- [x] Step 3：新增 `ToolPlaygroundView.swift` 和 `ToolEditorV2View.swift`。
- [x] Step 4：改造 `ToolsSettingsPage` 为 draft session + v2 editor + Playground。
- [x] Step 5：在 `ToolsSettingsPage+Actions.swift` 实现创建、保存、放弃和删除 / 拖拽收口。
- [x] Step 6：调整 `SettingsScene` 默认窗口尺寸。
- [x] Step 7：运行 SettingsUI tests 和 App Debug build，按失败做最小修复。
- [x] Step 8：更新任务文档并准备提交 `feat: add tool editor playground ui`。

## 设计边界

- KISS：保持现有 Tools 列表、行点击展开、拖拽排序和删除确认行为，不重构整页导航。
- 草稿隔离：打开编辑器后修改只进入 `ToolEditorDraftSession`，不触发 `configuration.tools` 的 onChange debounced save。
- 安全：Playground 默认不允许 MCP tool call；side effects 仍由运行策略 dry-run，不触发真实文件、剪贴板、选区替换、通知或 TTS。
- 校验一致性：Save 与 Run 使用同一个 `ToolDraftValidator`，避免 Playground 绕过保存规则。

## 实施记录

1. 已确认 Task 4 前置注入存在：`SettingsViewModel` 已 import `Orchestration`，并有 `playgroundRunner` init 参数和 published 属性；`AppContainer` 已注入专用 `ToolPlaygroundRunner`，本任务未重复扩大范围。
2. 新增 focused UI composition 测试，先运行红灯，确认缺少 `ToolEditorV2View` 导致 SettingsUI 测试编译失败。
3. 新增 `ToolPlaygroundView`：渲染 selection 输入、MCP 显式开关、Run / Cancel / Clear、prompt preview、权限提示、错误、streaming 输出、tool-call rows、side effect dry-run rows 和 report summary。Run 前调用外层传入的草稿校验；Cancel 调用 `ToolPlaygroundState.markCancelling()`。
4. 新增 `ToolEditorV2View`：顶部显示 Unsaved draft + Save / Revert，主体为左侧 `ToolEditorView` 草稿编辑器和右侧 `ToolPlaygroundView`。
5. 改造 `ToolsSettingsPage`：用 `editingSession` / `validationErrors` 替代 `expandedId`；打开已有 Tool 时复制正式配置为草稿；创建新 Tool 时在操作行下方展示创建草稿；SwiftUI 关闭 session 的瞬时重绘使用 fallback Tool，避免数组越界。
6. 新增 `validateDraftForRun(_:)`，Save 和 Playground Run 共用同一校验，并显式传入 `viewModel.configuration.triggers.commandPaletteEnabled`。
7. 改造 `ToolsSettingsPage+Actions`：Add Prompt / Add Agent 不再 append 到 `configuration.tools`；`saveEditingSession()` 通过校验后才写回 tools/hotkeys；热键变化时调用 `viewModel.saveHotkeys()` 触发重新注册；`revertEditingSession()` 放弃草稿。
8. 删除和拖拽保持原行为：删除仍直接移除工具并走确认 alert；拖拽开始会关闭当前编辑器，避免排序过程中草稿绑定到错误行。
9. `SettingsScene` 默认 frame 从 `720×520` 调整为 `980×620`，给双栏编辑器和 Playground 预留空间。

### Review follow-up

1. `ToolPlaygroundView` 增加 `activeRunID` token：重复 Run、Cancel、Clear 和 view disappear 都会让旧 Task 停止回写状态；旧 Task 结束时只有 token 仍匹配才会清理 `runTask`。
2. `ToolPlaygroundView` 增加 `.onDisappear` 取消 active run，关闭编辑器或 Settings 后不继续让后台 Playground run 写 UI 状态。
3. `ToolPlaygroundView` 输出区在 streaming raw text 之外额外展示非空且不同的 `displayPreview.summary`，让 `.file` / `.replace` / `.bubble` / `.silent` dry-run 摘要可见。
4. `saveEditingSession()` 不再用草稿里的全局 `HotkeyBindings` 覆盖当前配置；新增 `mergedHotkeysForSavingDraft(...)`，只合并当前草稿工具的 hotkey，避免复活编辑期间已删除工具的 orphan hotkey。
5. 新增 dirty guard：creating session 默认 dirty；existing session 比较当前正式 Tool 与草稿 Tool，并只比较当前工具相关 hotkey。切换行、新增 Prompt / Agent、开始拖拽时如有未保存改动会保留当前草稿并展示“请先保存或撤销当前草稿后再继续。”

## 变动文件清单

- `SliceAIKit/Sources/SettingsUI/ToolPlaygroundView.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorV2View.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Actions.swift`
- `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`
- `SliceAIKit/Tests/SettingsUITests/ToolEditorDraftStateTests.swift`
- `docs/Module/SettingsUI.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-28-phase-3-task-7-settings-ui-integration.md`

## 测试记录

- Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task7-red-20260528-01 --filter SettingsUITests.ToolEditorDraftStateTests/test_toolEditorV2ViewCanBeConstructedWithDraftSession` 编译失败，符合预期；缺少 `ToolEditorV2View`。
- Focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task7-focused-20260528-02 --filter SettingsUITests.ToolEditorDraftStateTests` 通过，12 tests，0 failures。构建阶段仍出现既有 `CapabilitiesTests/MCPServerStoreTests.swift` unused-result warning，非本任务文件。
- SettingsUI：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task7-settingsui --filter SettingsUITests` 通过，45 tests，0 failures。构建阶段仍出现既有 `CapabilitiesTests/MCPServerStoreTests.swift` unused-result warning，非本任务文件。
- App build：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过，`BUILD SUCCEEDED`。Xcode 仍输出多 destination 选择 warning 和 AppIntents metadata skipped warning，非本任务新增。
- Whitespace：`git diff --check` 通过，无输出。
- Review follow-up Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task7-fix-red-20260528-01 --filter SettingsUITests.ToolEditorDraftStateTests` 编译失败，符合预期；新增测试调用的 `mergedHotkeysForSavingDraft(...)` 和 `hasUnsavedEditingChanges(...)` 尚不存在。
- Review follow-up Focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task7-fix-focused-20260528-02 --filter SettingsUITests.ToolEditorDraftStateTests` 通过，16 tests，0 failures。构建阶段仍出现既有 `CapabilitiesTests/MCPServerStoreTests.swift` unused-result warning，非本任务文件。
- Review follow-up SettingsUI：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task7-fix-settingsui --filter SettingsUITests` 通过，49 tests，0 failures。构建阶段仍出现既有 `CapabilitiesTests/MCPServerStoreTests.swift` unused-result warning，非本任务文件。
- Review follow-up App build：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过，`BUILD SUCCEEDED`。Xcode 仍输出多 destination 选择 warning 和 AppIntents metadata skipped warning，非本任务新增。
- Review follow-up Whitespace：`git diff --check` 通过，无输出。
