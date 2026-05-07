# Phase 1 M1 Task 5 · MCP Servers Settings Page

## 任务背景

Phase 1 M1 Task 1-4 已完成 SliceCore MCP contract、Capabilities MCP server store / Claude Desktop importer，以及 stdio MCP JSON-RPC client。Task 5 需要把这些能力接入 SettingsUI，让用户能在设置窗口管理本地 MCP servers，并在保存前后通过 tools/list 做最小连接测试。

## 现有问题

- SettingsUI 当前没有 MCP Servers 页面，用户无法查看或维护本地 `mcp.json`。
- SettingsUI target 尚未依赖 Capabilities，无法直接复用 `MCPServerStore`、`ClaudeDesktopMCPImporter` 和 `MCPClientProtocol`。
- 缺少针对 SettingsUI 层 MCP server 管理行为的单元测试。

## 实施方案

1. 按 TDD 先新增 `SettingsUITests.MCPServersViewModelTests`，覆盖 Claude Desktop JSON 导入持久化、`.unknown` provenance 校验提示、tools/list 测试连接，以及删除持久化。
2. 修改 `SliceAIKit/Package.swift`，让 `SettingsUI` 依赖 `Capabilities`，并新增 `SettingsUITests` test target。
3. 新增 `MCPServersViewModel`，通过注入的 `MCPServerStore`、`ClaudeDesktopMCPImporter` 和 `MCPClientProtocol` 完成加载、导入、保存、删除、测试连接。
4. 新增 `MCPServersPage`，沿用 `SettingsPageShell`、`SectionCard`、`PillButton` 和 DesignSystem token；用粘贴 JSON sheet 导入 Claude Desktop 配置，避免 SwiftPM target 直接依赖 `NSOpenPanel`。
5. 修改 `SettingsScene` sidebar，加入 MCP Servers 页面入口。
6. 更新 README、Capabilities 模块文档和任务文档，运行指定验证命令后提交。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 写 SettingsUITests 失败测试并确认红灯。
- [x] 实现 MCPServersViewModel 行为。
- [x] 实现 MCP Servers 设置页面与侧栏入口。
- [x] 更新 README 与模块文档。
- [x] 运行验证命令、diff 检查并提交。
- [x] 根据 code quality review 修复状态一致性问题并追加回归测试。

## 计划约束

- 必须使用 TDD：先写失败测试并运行确认红灯，再写生产实现。
- 不实现 Legacy SSE，不新增 `LegacySSEMCPClient`；`.sse` 只保留解码兼容，不作为新建选项。
- ViewModel 使用 `MCPServerStore` 读写本地 `mcp.json`；测试使用临时文件 store。
- `save(_:)` 遇到 `.unknown` provenance 或 store validation 错误时设置 `validationMessage`，不崩溃。
- 每个 catch 路径打印简短、可读的中文调试日志。
- 所有新增 Swift 函数添加函数级中文注释，复杂逻辑内添加必要中文注释。

## 变动文件清单

- `SliceAIKit/Package.swift`
- `SliceAIKit/Sources/SettingsUI/MCPServersViewModel.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/MCPServersPage.swift`
- `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`
- `SliceAIKit/Tests/SettingsUITests/MCPServersViewModelTests.swift`
- `README.md`
- `docs/Module/Capabilities.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-07-phase-1-m1-task-5-mcp-servers-settings-page.md`

## 代码修改逻辑

1. `Package.swift` 让 `SettingsUI` 依赖 `Capabilities`，从而 Settings 层可以复用 `MCPServerStore`、`ClaudeDesktopMCPImporter`、`RoutingMCPClient`、`StdioMCPClient` 和 `MCPClientProtocol`；新增 `SettingsUITests` test target，依赖 `SettingsUI`、`SliceCore`、`Capabilities`。
2. `MCPServersViewModel` 是 `@MainActor ObservableObject`，公开计划要求的 `servers`、`validationMessage`、`reload()`、`importClaudeDesktopConfig(_:)`、`save(_:)`、`delete(id:)`、`testConnection(id:)` API，并额外公开只读 `toolsByServerID`、`connectionMessage`、`testingServerID` 支持页面预览。
3. ViewModel 通过构造器注入 `MCPServerStore`、`ClaudeDesktopMCPImporter` 和 `MCPClientProtocol`；生产默认 client 使用 `RoutingMCPClient` + `StdioMCPClient`，descriptor provider 从同一个 store 的 `snapshot()` 读取。测试用临时文件 store 和 `MockMCPClient`，避免触碰用户真实 `~/Library/Application Support/SliceAI/mcp.json`。
4. Claude Desktop JSON 导入使用 `.selfManaged(userAcknowledgedAt: Date())` provenance，并按 server id 合并到已有列表：同 id 替换、不同 id 追加；随后调用 store save 让 `MCPServerValidation` 统一校验。
5. `save(_:)` 和 `delete(id:)` 每次都先 load 当前配置，再原地更新 `servers` 后 save，保留 `runnerConfirmations` 等配置字段；校验失败时设置 `validationMessage`，不更新内存列表，不崩溃。
6. `testConnection(id:)` 从当前 `servers` 找 descriptor，调用注入 client 的 `tools(for:)`，成功后把工具列表写入 `toolsByServerID[id]`，失败则写入 `validationMessage` / `connectionMessage`；所有 catch 路径都有中文可读 `print`。
7. `MCPServersPage` 使用 `SettingsPageShell`、`SectionCard`、`PillButton` 和 DesignSystem token；server 列表展示 id、transport 和 provenance 摘要，操作按钮提供编辑、测试连接、删除；tools/list 成功后在行内展示工具预览。
8. 新增/编辑 sheet 只创建 `.stdio` descriptor，字段包含 id、command、args、env；args/env 采用多行文本解析，env 行必须是 `KEY=VALUE`。页面没有 `.sse` 新建选项，也没有 legacy SSE client。
9. Claude Desktop 导入使用粘贴 JSON sheet，不直接依赖 AppKit `NSOpenPanel`，保持 SwiftPM `SettingsUI` target 简洁。

## Code Quality Review 修复记录

Review commit：`ebe5641`。结论：`CHANGES_REQUESTED`。本轮全部接受并修复：

1. `MCPServerStore` 新增 `update(_:)`，在 actor 内同步完成 `load -> mutate -> validate -> save`，并提取 `loadSync()` / `saveSync(_:)` 供 `load`、`save`、`snapshot`、`update` 复用。`MCPServersViewModel.importClaudeDesktopConfig(_:)`、`save(_:replacing:)`、`delete(id:)` 均改为调用原子 update API，避免多个 UI 操作并发时互相覆盖。
2. `MCPServersViewModel.save(_:)` 扩展为 `save(_:replacing:)` 且保留原调用方式；编辑改 ID 时会原子替换旧 ID，不残留旧 server。若新 ID 已被其他 server 使用，抛 `.duplicateServerID` 并转为 `validationMessage`，不静默覆盖。
3. `MCPServerDraft` 携带 `originalID`、原始 `capabilities`、原始 `provenance`。编辑保存只改 id / command / args / env，不重置 metadata。
4. `MCPServersPage` 在 save/import 后检查 `viewModel.validationMessage`；成功才关闭 sheet / 清空 JSON，失败则保留 sheet 和用户输入，并在 sheet 内展示错误。
5. `toolsByServerID` 增加失效策略：save/import 成功后清理受影响 server 的工具预览；`testConnection(id:)` 失败时清理该 server 旧预览。测试状态从单个 `testingServerID` 改为 `testingServerIDs` 集合，并提供 `isTesting(id:)` helper。

## 测试用例与结果

- 红灯确认：
  - `swift test --filter SettingsUITests.MCPServersViewModelTests`：失败，原因符合预期。测试 target 可编译入口已接入，但生产代码尚未提供 `MCPServersViewModel`，编译报 `cannot find 'MCPServersViewModel' in scope`。
  - Review 修复红灯：`swift test --filter SettingsUITests.MCPServersViewModelTests` 失败，原因符合预期：新增回归测试调用 `save(_:replacing:)`、访问 `MCPServerDraft` metadata API，但生产代码尚未提供这些能力；同次编译也暴露 `MCPServerStore.update` 缺失。
- 目标测试：
  - `swift test --filter SettingsUITests.MCPServersViewModelTests`：通过，12 tests。
- 回归验证：
  - `swift build`：通过。
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests`：通过，10 tests。
  - `swift test --filter SliceCoreTests.MCPDescriptorTests`：通过，15 tests。
  - `swift test --filter CapabilitiesTests.RoutingMCPClientTests`：通过，2 tests。
  - `git diff --check`：通过。
