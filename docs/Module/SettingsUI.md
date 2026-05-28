# SettingsUI

## 模块职责

`SettingsUI` 承载 SliceAI 的 SwiftUI 设置界面，包括 Provider、Tools、Skills、MCP Servers、Hotkey、Trigger、Appearance、Permissions 和 About 页面。

该模块负责编辑内存中的 `Configuration`，并通过注入的 `SettingsViewModel` 写回 `ConfigurationStore`。API Key 只通过 `KeychainAccessing` 读写，不进入配置文件。

## ToolEditor v2

ToolEditor v2 使用 `ToolEditorDraftSession` 保存未提交草稿。左侧编辑器修改 draft，不直接写 `Configuration.tools`；点击 Save 后通过 `ToolDraftValidator` 校验并写回配置。Revert 丢弃草稿。

Phase 3 Task 7 后，Tools 页面不再把编辑器直接绑定到 `configuration.tools[index]`：

- 点击已有 Tool 时创建 `ToolEditorDraftSession.editingExisting`。
- 点击 Add Prompt / Add Agent 时创建 `ToolEditorDraftSession.creating`，不立即追加到 `configuration.tools`。
- 左侧 `ToolEditorView` 只编辑 `ToolEditorDraft`。
- 点击 Save 后才校验并写回 `configuration.tools` / `configuration.hotkeys`。
- 点击 Revert 时关闭草稿会话，不污染正式配置。
- 切换行、新增工具或拖拽开始前会执行 dirty guard；如果当前草稿有未保存改动，会提示用户先保存或撤销。

草稿校验统一使用 `ToolDraftValidator.validate(...)`，覆盖重复 id、`Tool.validate()`、Agent Skill 启用状态和工具热键冲突。Tools 页的 Run / Save 校验必须显式传入 `configuration.triggers.commandPaletteEnabled`，避免命令面板关闭时仍误判热键冲突。

保存草稿时只合并当前工具相关 hotkey：保留当前 `configuration.hotkeys.toggleCommandPalette` 和其它工具最新 hotkey，删除重命名工具的旧 id hotkey，并按当前草稿工具的 hotkey 写入或清除。不要把打开编辑器时的旧全局 hotkeys 快照整包写回。

## Prompt Playground UI

右侧 Prompt Playground 使用 `ToolPlaygroundView` 和 `ToolPlaygroundState` 消费 Orchestration `ExecutionEvent`。Playground run 的 LLM 可真实调用，side effects 只 dry-run，MCP tool call 默认禁用，必须由用户显式打开本次运行开关。

`ToolEditorV2View` 采用左侧编辑器 + 右侧 `ToolPlaygroundView` 的双栏布局。右侧 Playground：

- 使用 `ToolPlaygroundRunner` 复用 Orchestration 执行链。
- 默认禁用真实 MCP tool call，用户需打开“允许本次运行调用 MCP tools”。
- 所有 side effects 仍由 run policy dry-run，不写文件、剪贴板、前台选区、通知或 TTS。
- 通过 `ToolPlaygroundState.reduce(_:,tool:)` 展示 streaming 输出、prompt preview、权限提示、tool-call lifecycle、side effect dry-run、DisplayMode preview、report 和错误。
- 每次运行都有独立 token；重复 Run、Cancel、Clear 或视图消失后，旧 Task 不得继续回写当前 UI state。
- streaming raw text 存在时仍要展示不同的 DisplayMode dry-run summary，避免 `.file` / `.replace` / `.bubble` / `.silent` 试跑结果只剩原文。

Settings 窗口默认尺寸已调整为 `980×620`，以容纳双栏编辑器和 Playground。
