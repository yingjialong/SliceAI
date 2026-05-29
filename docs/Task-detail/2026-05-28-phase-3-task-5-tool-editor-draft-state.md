# 2026-05-28 · Phase 3 Task 5 ToolEditor Draft State

## 背景

用户要求作为 Phase 3 ToolEditor v2 + Prompt Playground MVP 的实现 worker，执行 Task 5：新增 ToolEditor 本地草稿状态，并提供保存前校验能力。

本任务承接 Task 1-4 的 Playground 执行基础；只处理 SettingsUI 中 ToolEditor 的草稿模型和校验，不接入 Save/Revert UI，不创建 `ToolPlaygroundState`、`ToolPlaygroundView` 或 `ToolEditorV2View`。

## 任务目标

- 新增 `ToolEditorDraft` 和 `ToolEditorDraftSession`，让编辑已有 Tool 时先复制到本地草稿，Save 前不修改原始 Tool。
- 新增 `ToolDraftValidator`，复用生产 `Tool.validate()` 和 `HotkeyBindingValidator` 做保存前校验。
- 覆盖重复 Tool id、Agent disabled/unknown skills、无效工具热键、命令面板冲突和其它工具热键冲突。
- 更新 `ToolEditorView` 顶部注释，移除“binding 一定直接指向生产配置”的旧口径。

## ToDoList

- [x] Step 1：创建 `ToolEditorDraftStateTests`，写草稿隔离和保存校验测试。
- [x] Step 2：运行指定 focused test，确认草稿类型缺失导致红灯。
- [x] Step 3：新增 `ToolEditorDraftState.swift` 实现草稿会话和校验器。
- [x] Step 4：更新 `ToolEditorView` 顶部注释和 init 文档。
- [x] Step 5：运行 focused SettingsUI tests。
- [x] Step 6：更新任务文档并提交 `feat: add tool editor draft state`。

## 设计边界

- KISS：本任务只新增草稿状态和校验器，不把 UI 保存流提前接入。
- 草稿隔离：`Tool` 是值类型，`ToolEditorDraftSession.existing` 只保存原始 Tool 快照和可变草稿。
- 校验复用：结构性 Tool 不变量继续走 `Tool.validate()`；热键解析和冲突检测继续走 `HotkeyBindingValidator`，避免 SettingsUI 自建规则。
- Skill 安全：Agent Tool 绑定的 skill 必须存在于 available skills 且处于 `.enabled`；unknown skill 与 disabled skill 都按不可保存处理。

## 实施记录

### 初始实现

1. 新增 `ToolEditorDraftStateTests`，覆盖已有 Tool 编辑草稿隔离、创建时重复 id、编辑时保留原 id、disabled/unknown skill、工具热键与命令面板冲突、工具热键与旧 `Tool.hotkey` fallback 冲突、无效工具热键。
2. 首次按用户指定命令运行 RED 时被本地 `.build` 的 Swift 6.2/6.3 产物混用阻塞；改用唯一 `--scratch-path` 后得到预期编译失败，缺少 `ToolEditorDraftSession`、`ToolEditorDraft` 和 `ToolDraftValidator`。
3. 新增 `ToolEditorDraft`，保存未提交的 `Tool` 和 `HotkeyBindings` 草稿。
4. 新增 `ToolEditorDraftSession`，区分编辑已有工具和创建新工具；`existing(original:hotkeys:)` 会复制原始 Tool 到草稿，`originalToolId` 用于保存校验时允许已有工具保留原 id。
5. 新增 `ToolDraftValidationError` 和 `ToolDraftValidator`。校验顺序为重复 id、`Tool.validate()`、Agent skill enabled 检查、热键解析与冲突检查。
6. 热键校验复用 `HotkeyBindingValidator.effectiveToolHotkeys` 与 `HotkeyBindingValidator.issues`，并把当前草稿 Tool 加入比较集合，确保集中式 `hotkeys.tools` 和旧 `Tool.hotkey` fallback 使用同一规则。
7. `ToolDraftValidator` 增加脱敏 debug 日志，只输出 tool id、original id 和错误数量，不记录 prompt、selection 或用户文本。
8. 更新 `ToolEditorView` 顶部注释和 `tool` 参数文档，明确 v2 binding 可指向本地草稿，只有外层 Save 才写回 `Configuration.tools`。

### Review follow-up

1. `ToolDraftValidator.validate(...)` 新增向后兼容参数 `commandPaletteEnabled: Bool = true`，并传入热键校验路径。命令面板关闭时，校验器会向 `HotkeyBindingValidator.issues(...)` 传空字符串，与生产 `ToolHotkeyRegistration.validRegistrations(in:)` 的行为一致。
2. `Tool.validate()` 抛出 `SliceError` 时，草稿校验现在使用 `SliceError.userMessage` 生成 `.invalidTool`，其它错误才回落到 `localizedDescription`。
3. 测试拆分 disabled skill 与 unknown skill 场景，并新增命令面板关闭时不检测 `toggleCommandPalette` 冲突、invalid Tool 使用用户可读文案的回归测试。

## 实现结果

已完成 Task 5 范围和 review follow-up。SettingsUI 现在具备 ToolEditor v2 所需的本地草稿状态和保存前校验基础；后续 Task 7 可以在 Tools 页面接入 Save/Revert UI 时复用该草稿层，避免未保存编辑污染正式配置。

## 变动文件清单

- `SliceAIKit/Sources/SettingsUI/ToolEditorDraftState.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`
- `SliceAIKit/Tests/SettingsUITests/ToolEditorDraftStateTests.swift`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-28-phase-3-task-5-tool-editor-draft-state.md`

## 测试记录

- Red cache issue：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --filter SettingsUITests.ToolEditorDraftStateTests` 被旧 `.build` Swift 6.2.3 产物阻塞，Swift 6.3.2 无法导入旧 `LLMProviders.swiftmodule`。
- Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task5-red-20260528-01 --filter SettingsUITests.ToolEditorDraftStateTests` 编译失败，符合预期；缺少 `ToolEditorDraftSession`、`ToolEditorDraft` 和 `ToolDraftValidator`。
- Focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task5-focused-20260528-05 --filter 'SettingsUITests.ToolEditorDraftStateTests|SettingsUITests.ToolEditorSkillsBindingTests|SettingsUITests.ToolEditorAgentAllowlistCodecTests'` 通过，14 tests，0 failures。
- Whitespace：`git diff --check` 通过。
- Review follow-up Red：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task5-fix-red-20260528-01 --filter SettingsUITests.ToolEditorDraftStateTests` 编译失败，符合预期；新增测试调用的 `commandPaletteEnabled` 参数尚不存在。
- Review follow-up Focused：`DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --package-path SliceAIKit --scratch-path /tmp/sliceai-task5-fix-focused --filter 'SettingsUITests.ToolEditorDraftStateTests|SettingsUITests.ToolEditorSkillsBindingTests|SettingsUITests.ToolEditorAgentAllowlistCodecTests'` 通过，17 tests，0 failures。
- Review follow-up Whitespace：`git diff --check` 通过。
