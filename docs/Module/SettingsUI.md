# SettingsUI Module

## 模块职责

`SettingsUI` 承载 SliceAI 的 SwiftUI 设置界面，包括 Provider、Tools、Skills、MCP Servers、Hotkey、Trigger、Appearance、Permissions 和 About 页面。

该模块负责编辑内存中的 `Configuration`，并通过注入的 `SettingsViewModel` 写回 `ConfigurationStore`。API Key 只通过 `KeychainAccessing` 读写，不进入配置文件。

## ToolEditor v2

Phase 3 Task 7 后，Tools 页面不再把编辑器直接绑定到 `configuration.tools[index]`：

- 点击已有 Tool 时创建 `ToolEditorDraftSession.editingExisting`。
- 点击 Add Prompt / Add Agent 时创建 `ToolEditorDraftSession.creating`，不立即追加到 `configuration.tools`。
- 左侧 `ToolEditorView` 只编辑 `ToolEditorDraft`。
- 点击 Save 后才校验并写回 `configuration.tools` / `configuration.hotkeys`。
- 点击 Revert 或拖拽开始时关闭草稿会话，不污染正式配置。

草稿校验统一使用 `ToolDraftValidator.validate(...)`，覆盖重复 id、`Tool.validate()`、Agent Skill 启用状态和工具热键冲突。Tools 页的 Run / Save 校验必须显式传入 `configuration.triggers.commandPaletteEnabled`，避免命令面板关闭时仍误判热键冲突。

## Prompt Playground UI

`ToolEditorV2View` 采用左侧编辑器 + 右侧 `ToolPlaygroundView` 的双栏布局。右侧 Playground：

- 使用 `ToolPlaygroundRunner` 复用 Orchestration 执行链。
- 默认禁用真实 MCP tool call，用户需打开“允许本次运行调用 MCP tools”。
- 所有 side effects 仍由 run policy dry-run，不写文件、剪贴板、前台选区、通知或 TTS。
- 通过 `ToolPlaygroundState.reduce(_:,tool:)` 展示 streaming 输出、prompt preview、权限提示、tool-call lifecycle、side effect dry-run、DisplayMode preview、report 和错误。

Settings 窗口默认尺寸已调整为 `980×620`，以容纳双栏编辑器和 Playground。
