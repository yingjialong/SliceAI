# Phase 1 M2 Task 9 · AppContainer Context And Permission UI Wiring

## 任务背景

M2 Task 7 已实现五个核心 `ContextProvider`，M2 Task 8 已建立 UI-free permission consent boundary，但 `AppContainer` 当前仍使用空 `ContextProviderRegistry`，并注入 fail-closed 的临时 `RuntimePermissionConsentPresenter`。Task 9 的目标是把真实 App wiring 接上：生产启动路径注册真实 context providers，接入 AppKit 权限确认 presenter，并把 MCP runtime client 从 mock 替换为本地 `mcp.json` 驱动的 routing client。

## 实施方案

1. 先保留基线验证结果，确认 `ExecutionEngineTests` 当前全绿。
2. 复核测试缺口：计划中三类 Orchestration 行为已由现有 `ExecutionEngineTests` / `PermissionBrokerTests` / `ContextProviderTests` 覆盖；本任务不新增重复低价值测试，改用 focused tests + `xcodebuild` 验证 App target wiring。
3. 新增 `SliceAIApp/AppPermissionConsentPresenter.swift`，实现 `@MainActor` AppKit `NSAlert` presenter，按钮仅包含“本次允许 / 本次会话允许 / 拒绝”，不提供 persistent approval。
4. 新增 `SliceAIApp/AppContextAdapters.swift`，集中封装 AppKit/NSPasteboard/AX 读取辅助能力，避免把 AppKit 细节扩散到 Orchestration。
5. 修改 `AppContainer`：注册 Task 7 五个 provider；`PersistentPermissionGrantStore` 显式使用 `appSupport/permission-grants.json`；`MCPServerStore`、`StdioMCPClient`、`RoutingMCPClient` 接入 `mcp.json`。
6. 按当前代码状态校正 plan 口径：不在 Task 9 强行实现 `AgentExecutor` routing，因为该类型属于后续 M3 尚未存在；ContextProvider 构造参数也以当前 Task 7 API 为准。
7. 运行 focused tests、全量相关测试、App Debug build，更新 README / 模块文档 / master todolist 并提交。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 运行 `ExecutionEngineTests` 基线。
- [x] 评估 Task 9 测试缺口：不新增重复 Orchestration 行为测试。
- [x] 实现 AppKit permission presenter。
- [x] 实现 App context adapters。
- [x] 修改 AppContainer wiring。
- [x] 运行 focused tests 与 App build。
- [x] 更新 README、模块文档和 master todolist。
- [ ] 提交 commit。

## 变动文件

- `SliceAIApp/AppContainer.swift`
- `SliceAIApp/AppContextAdapters.swift`
- `SliceAIApp/AppPermissionConsentPresenter.swift`
- `SliceAI.xcodeproj/project.pbxproj`
- `README.md`
- `docs/Module/Capabilities.md`
- `docs/Module/Orchestration.md`
- `docs/Task-detail/2026-05-08-phase-1-m2-task-9-appcontainer-context-permission-ui.md`
- `docs/Task_history.md`
- `docs/v2-refactor-master-todolist.md`

## 代码修改逻辑

- `AppContainer.makeContextProviderRegistry()` 集中创建五个核心 provider，替换原空 `ContextProviderRegistry(providers: [:])`。`clipboard.current` 通过 `AppContextAdapters.readClipboardString` 读取系统剪贴板；`file.read` 使用当前 Task 7 API `FileReadContextProvider(sandbox: PathSandbox())`。
- `PermissionBroker` 继续使用内存 `PermissionGrantStore` 保存 session grant，同时显式读取 `appSupport/permission-grants.json` 的 `PersistentPermissionGrantStore`。运行期 consent presenter 从 fail-closed placeholder 换成 `AppPermissionConsentPresenter()`。
- `AppPermissionConsentPresenter` 是 `@MainActor` AppKit presenter，协议方法用 `nonisolated` async bridge 回主线程展示 `NSAlert`，避免从 Orchestration actor 直接触碰 AppKit。弹窗展示权限 case、provenance summary、operation risk copy 和 `uxHint`；按钮为本次允许、本次会话允许、拒绝，且不返回 `.persistent`。
- `AppContextAdapters` 只封装当前确实需要的剪贴板读取，没有提前扩展 AX / URL 快照 helper，保持 KISS。
- MCP runtime 改为从 `appSupport/mcp.json` 创建 `MCPServerStore`，通过 `snapshot()` 提供 descriptors，再创建 `StdioMCPClient` 和 `RoutingMCPClient` 注入 `ExecutionEngine`。`.agent` / `.pipeline` stub 未改动，避免把后续 M3 的 AgentExecutor 强塞进 Task 9。
- 新增 App target Swift 文件已同步写入 `SliceAI.xcodeproj/project.pbxproj` 的 file reference、group 和 sources build phase。

## 测试用例

- 基线：`cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`：通过（18 tests）。
- 未新增红灯测试原因：计划列出的 `test_executionFailsBeforeFileReadWhenPermissionUndeclared()`、`test_permissionDeniedYieldsFailedEventWithoutCrash()`、`test_permissionApprovedContinuesToPromptExecution()` 已有近等价覆盖。Task 9 的新增行为是 App composition root wiring，当前没有 App SPM test seam；强行新增 Orchestration 测试只会重复既有行为，不能证明 App target wiring。
- 最终验证命令：
  - `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`
  - `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`
  - `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionBrokerTests`
  - `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
  - `git diff --check`

## 测试结果

- 基线 `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`：通过（18 tests）。
- `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`：通过（9 tests）。
- `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionBrokerTests`：通过（37 tests）。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过（BUILD SUCCEEDED）。
- `git diff --check`：通过（无输出）。

## Self-review

- `AppPermissionConsentPresenter` 没有提供 persistent approval，符合 Settings-only persistent grant 要求。
- 非 cacheable 权限的 session 按钮保留但禁用，避免 presenter 返回 misleading 的 session grant；broker 侧仍对不可缓存权限 fail-safe 为 one invocation。
- `AppContextAdapters` 未过度设计，只放当前生产 wiring 需要的剪贴板读取。
- MCP routing client 已注入 `ExecutionEngine`，但 AgentExecutor 未实现，因此不会改变 `.agent` stub 行为。
