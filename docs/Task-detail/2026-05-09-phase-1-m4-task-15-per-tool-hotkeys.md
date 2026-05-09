# Phase 1 M4 Task 15 · Per-Tool Hotkeys

## 任务背景

Task 14 已补齐 MCP Streamable HTTP transport，Phase 1 进入 M4 收口阶段。当前 App 只注册 `hotkeys.toggleCommandPalette`，工具级热键虽然在 `Tool.hotkey` 字段中已有占位，但没有配置聚合、冲突校验、Settings UI 保存路径，也没有运行时按工具 id 直接执行的路由。

本任务要让用户能为单个工具绑定全局热键，并在触发时直接捕获当前选区、执行对应工具，同时保留命令面板热键的既有行为。

## 当前计划差异

Phase plan 的 Task 15 方向适合继续：在 `HotkeyBindings` 增加 `tools` 映射，Settings UI 录制每个工具热键，运行时注册命令面板和工具热键。需要明确两点边界：

1. 本任务不引入新的触发系统，也不重写 `HotkeyRegistrar` 的 Carbon 注册模型；只扩展现有注册器的多注册能力。
2. `Tool.hotkey` 已存在，但本任务以 `Configuration.hotkeys.tools[tool.id]` 作为集中配置入口，保存时同步 `Tool.hotkey` 以保持模型字段不悬空。

## 实施方案

1. 按 TDD 先补红灯测试：
   - `Configuration` 可编码 / 解码 per-tool hotkeys，旧 JSON 缺 `tools` 时默认 `[:]`。
   - hotkey 冲突检测能发现命令面板与工具冲突、工具与工具冲突。
   - App 层纯 helper 能按 tool id 选择直接执行的工具，并覆盖旧 `Tool.hotkey` fallback 的冲突过滤，不实例化 `NSApp`。
2. 实现配置支持：
   - `HotkeyBindings` 增加 `tools: [String: String]`。
   - 自定义解码兼容旧配置。
   - `ConfigMigratorV1ToV2` 和 `DefaultConfiguration` 使用空工具热键映射。
3. 实现冲突检测：
   - 新增纯 Swift helper，基于 `Hotkey.parse(...).description` 归一化。
   - 运行时注册前把集中 `hotkeys.tools` 与旧 `Tool.hotkey` fallback 合并成有效映射，避免兼容路径绕过冲突检测。
   - 忽略空字符串；无效热键作为 validation issue 暴露给 Settings UI。
4. 实现 Settings UI：
   - 工具编辑页显示当前工具热键录制器。
   - 保存时更新 `configuration.hotkeys.tools[tool.id]`，空值删除映射，并同步 `tool.hotkey`。
   - 显示冲突 / 无效热键提示，避免运行时静默失败。
5. 实现运行时注册：
   - `AppDelegate.reloadHotkey()` 注册命令面板热键和每个有效工具热键。
   - 工具热键回调捕获当前选区并调用已有 `execute(tool:payload:triggerSource:)`，triggerSource 使用 `.hotkey`。
   - parse/register 失败继续遵循“无自由日志”规范，只保留必要诊断日志。
6. 跑 focused tests、相关回归、targeted lint、`git diff --check`、App Debug build。
7. 更新 README、Task 详情和 Task_history，提交实现。
8. 按用户要求运行 `claude-review-loop`，处理 finding 后复验并记录结果。

## ToDoList

- [x] 创建 Task 15 任务文档并登记 Task_history。
- [x] 编写配置与冲突检测红灯测试。
- [x] 编写 AppDelegate 纯 helper 红灯测试，并覆盖旧 `Tool.hotkey` fallback 冲突。
- [x] 运行 focused tests 确认 red。
- [x] 实现 `HotkeyBindings.tools` 与旧配置兼容解码。
- [x] 实现 hotkey validation / conflict helper。
- [x] 更新 Settings UI 工具热键录制与保存路径。
- [x] 更新 `AppDelegate.reloadHotkey()` 多热键注册和工具直达执行。
- [x] 运行 focused tests、回归测试、targeted lint、App Debug build。
- [x] 更新 README、Task 详情和 Task_history。
- [x] 提交 commit。
- [x] 运行 `claude-review-loop` 并记录结果。

## 变动文件（计划）

- `README.md`：记录 Task 15 变更和验证结果。
- `docs/Task_history.md`：登记 Task 15。
- `SliceAIKit/Sources/SliceCore/ConfigurationComponents.swift`：扩展 `HotkeyBindings`。
- `SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift`：迁移时初始化工具热键映射。
- `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`：默认配置初始化工具热键映射。
- `SliceAIKit/Sources/HotkeyManager/HotkeyBindingValidator.swift`：新增热键冲突检测和工具热键注册 helper。
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`：新增工具热键编辑区。
- `SliceAIKit/Sources/SettingsUI/HotkeyEditorView.swift`：复用录制器展示工具热键校验错误。
- `SliceAIApp/AppDelegate.swift`：注册并路由工具热键。
- `SliceAIApp/AppDelegate+Hotkeys.swift`：拆分命令面板和工具热键注册逻辑。
- `SliceAI.xcodeproj/project.pbxproj`：把 `AppDelegate+Hotkeys.swift` 加入 App target。
- `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`：新增配置兼容测试。
- `SliceAIKit/Tests/HotkeyManagerTests/HotkeyTests.swift`：新增冲突检测测试。
- `SliceAIKit/Tests/HotkeyManagerTests/HotkeyTests.swift`：用纯 helper 覆盖 AppDelegate tool id 路由输入、有效热键映射合并和旧 `Tool.hotkey` fallback 冲突过滤。

## 测试计划

- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationTests`
- `cd SliceAIKit && swift test --filter HotkeyManagerTests`
- `cd SliceAIKit && swift test --filter SettingsUITests`
- `cd SliceAIKit && swift test`
- `git diff --check`
- `swiftlint lint --strict <Task 15 touched Swift files>`
- `swiftlint lint --strict`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

## 测试结果

- 红灯测试：`cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationTests && swift test --filter SliceCoreTests.ConfigMigratorV1ToV2Tests && swift test --filter HotkeyManagerTests` 失败，原因为 `HotkeyBindings.tools`、`HotkeyBindingValidator`、`ToolHotkeyRegistration` 缺失，符合预期。
- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigurationTests`：通过，11 tests。
- `cd SliceAIKit && swift test --filter SliceCoreTests.ConfigMigratorV1ToV2Tests`：通过，10 tests。
- `cd SliceAIKit && swift test --filter HotkeyManagerTests`：通过，10 tests。
- `cd SliceAIKit && swift test --filter SettingsUITests`：通过，15 tests。
- `cd SliceAIKit && swift test`：通过，735 tests。
- `git diff --check`：通过。
- touched Swift files targeted `swiftlint lint --strict`：通过，0 violations。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过。
- `swiftlint lint --strict`：失败，13 个既有历史违规，阻塞文件包括 `MCPServersPage.swift`、`MCPServerStore.swift`、`MCPDiagnosticLog.swift`、`StdioMCPClient.swift`、`PersistentPermissionGrantStore.swift`、`ClaudeDesktopMCPImporter.swift`、`PermissionBroker.swift`、`AppPermissionConsentPresenter.swift`。这些文件并非 Task 15 新增，本任务不扩大到无关重构。
- `claude-review-loop`：Round 1 `needs_attention`，接受并修复 2 条 finding（删除工具后热键未立即重载；Settings UI 与 runtime 对旧 `Tool.hotkey` fallback 的冲突输入不一致）；Round 2 `approve`，`findings: []`。

## 代码修改逻辑

`HotkeyBindings` 增加 `tools` 字典作为集中工具热键配置，key 为 `Tool.id`。自定义 decoder 用 `decodeIfPresent` 让旧 config-v2 自动回落到空字典；v1 migrator 和默认配置继续显式生成空工具热键映射，避免迁移时产生隐式绑定。

`HotkeyBindingValidator` 是纯逻辑层：先用 `Hotkey.parse(...).description` 标准化热键，再稳定排序生成无效热键、命令面板冲突和工具间冲突。共享的 `effectiveToolHotkeys(bindings:tools:)` 会生成有效工具热键映射：集中 `configuration.hotkeys.tools` 优先，旧 `Tool.hotkey` 仅作 fallback；runtime 注册、工具编辑器校验和 Hotkey 设置页校验均使用此映射，避免 UI 与运行时行为不一致。`ToolHotkeyRegistration.validRegistrations(in:)` 按 `configuration.tools` 顺序生成可注册项，跳过缺失工具、无效热键和冲突热键。命令面板被禁用时不会阻塞同组合的工具热键。

Settings UI 复用现有 `HotkeyEditorView`。`ToolEditorView` 接收 `configuration.hotkeys` binding 和当前工具列表，在录制或清除工具热键时同步更新 `hotkeys.tools[tool.id]` 与 `Tool.hotkey` 兼容字段；录制完成后调用 `saveHotkeys()`，使 App 层立刻重新注册 Carbon 热键。工具删除时同步移除对应热键映射；若被删工具存在有效热键，则立即调用 `saveHotkeys()` 触发 Carbon 重新注册，避免旧全局热键继续占用。

`AppDelegate.reloadHotkey()` 拆到 `AppDelegate+Hotkeys.swift`，先清空所有 Carbon 注册，再注册命令面板和所有有效工具热键。工具热键回调只捕获 tool id，触发时重新读取当前配置并定位工具，再复用选区捕获、黑名单和最短长度过滤逻辑，最后以 `.hotkey` trigger source 调用既有 `execute(tool:payload:)` 执行链。

## Self-review

- 本任务未重写 Carbon `HotkeyRegistrar`，只使用既有多次 `register` + `unregisterAll` 能力，符合 KISS。
- 冲突检测是纯 helper，SwiftPM 测试不实例化 `NSApp`，避免把 AppKit 生命周期拖进单测。
- 工具热键保存使用集中 `configuration.hotkeys.tools`，同时同步 `Tool.hotkey` 以避免已有字段长期悬空；运行时 fallback 也纳入同一套冲突过滤，避免旧字段绕过校验。
- Claude review 指出的删除后热键占用和 UI/runtime fallback 不一致已接受并修复，修复后 Round 2 approve。
- AppDelegate 主文件因新增逻辑接近 file length 限制，已拆分 `AppDelegate+Hotkeys.swift` 并加入 Xcode project。
