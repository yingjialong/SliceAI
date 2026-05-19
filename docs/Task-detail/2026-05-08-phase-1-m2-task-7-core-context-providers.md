# Phase 1 M2 Task 7 · Core Context Providers

## 任务背景

Phase 1 M1 已完成 MCP contract、server store、stdio client 和 Settings MCP Servers 页面；M2 Task 6 已把 PermissionGraph 升级为 case-aware coverage。Task 7 的目标是补齐五个核心 `ContextProvider`，让 Tool 可以声明并采集当前选区、前台窗口标题、前台 URL、当前剪贴板和白名单文件内容。

## 实施方案

1. 先新增 provider 行为测试，覆盖五个 provider 的注册名、返回值、文件读取白名单和硬禁止路径拒绝。
2. 在 `ContextCollectorTests` 增加真实 provider registry 解析测试，确认 collector 可消费内置 provider。
3. 在 `PermissionGraphTests` 增加真实 provider 静态权限推导测试，确认 `clipboard.current` 和 `file.read` 进入权限闭环。
4. 确认红灯后实现五个 provider，并让触及 IO 的 provider 在 IO 边界前后调用 `Task.checkCancellation()`。
5. 跑指定过滤测试、`git diff --check`，自审后提交。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 编写五个 ContextProvider 红灯测试。
- [x] 运行 `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests` 确认红灯。
- [x] 实现 `selection` / `app.windowTitle` / `app.url` / `clipboard.current` / `file.read`。
- [x] 运行 Task 7 指定测试。
- [x] 更新 README、模块文档和 master todolist。
- [x] 运行最终验证并提交。

## 变动文件

- `SliceAIKit/Sources/Capabilities/ContextProviders/SelectionContextProvider.swift`
- `SliceAIKit/Sources/Capabilities/ContextProviders/AppWindowTitleContextProvider.swift`
- `SliceAIKit/Sources/Capabilities/ContextProviders/AppURLContextProvider.swift`
- `SliceAIKit/Sources/Capabilities/ContextProviders/ClipboardCurrentContextProvider.swift`
- `SliceAIKit/Sources/Capabilities/ContextProviders/FileReadContextProvider.swift`
- `SliceAIKit/Tests/CapabilitiesTests/ContextProviderTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/ContextCollectorTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/PermissionGraphTests.swift`
- `README.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-08-phase-1-m2-task-7-core-context-providers.md`
- `docs/Module/Capabilities.md`
- `docs/Module/Orchestration.md`
- `docs/v2-refactor-master-todolist.md`

## 代码修改逻辑

1. `SelectionContextProvider` 直接返回 `ExecutionSeed.selection.text`，不推导额外权限。
2. `AppWindowTitleContextProvider` 返回 `ExecutionSeed.frontApp.windowTitle`；快照缺失时返回空字符串，避免把可选 app 元数据缺失升级为 required 失败。
3. `AppURLContextProvider` 返回 `ExecutionSeed.frontApp.url?.absoluteString`；非浏览器 app 没有 URL 时返回空字符串。
4. `ClipboardCurrentContextProvider` 默认读取 `NSPasteboard.general.string(forType: .string)`，同时支持测试注入读取闭包；权限推导为 `[.clipboard]`，读取前后各检查一次取消，并只打印文本长度调试日志，避免泄露剪贴板内容。
5. `FileReadContextProvider` 使用 `request.args["path"]`，先通过 `PathSandbox.normalize(_:role: .read)` 规范化并校验，再按 chunk 读取 UTF-8 文本；默认 `maxBytes` 为 1 MiB，超限抛固定非敏感 `SliceError.execution(.unknown("file.read.maxBytesExceeded"))`。读取前、打开文件后、每个 chunk 后和读取完成后都会检查取消。权限推导为 `args["path"]` 对应的 `[.fileRead(path:)]`，调试日志只输出文本长度，不输出路径或文件内容。
6. `ContextCollectorTests` 使用真实 provider registry 验证 collector 能采集 seed/app 快照 provider。
7. `PermissionGraphTests` 使用真实 provider registry 验证 `.clipboard` 和 `.fileRead(path:)` 会进入 `fromContexts`，且声明覆盖后 `undeclared` 为空。

## 测试用例

新增：

- `ContextProviderTests.test_selectionProvider_returnsSeedSelection()`
- `ContextProviderTests.test_windowTitleProvider_returnsFrontAppTitle()`
- `ContextProviderTests.test_appURLProvider_returnsFrontAppURL()`
- `ContextProviderTests.test_clipboardProvider_returnsInjectedPasteboardText()`
- `ContextProviderTests.test_fileReadProvider_readsWhitelistedFile()`
- `ContextProviderTests.test_fileReadProvider_rejectsFileLargerThanMaxBytes()`
- `ContextProviderTests.test_fileReadProvider_observesCancellationDuringChunkedRead()`
- `ContextProviderTests.test_fileReadProvider_rejectsHardDeniedPath()`
- `ContextProviderTests.test_contextProviders_inferPermissions()`
- `ContextCollectorTests.test_resolve_coreContextProviders_collectsSeedAndAppContexts()`
- `PermissionGraphTests.test_compute_coreContextProviders_inferExpectedPermissions()`

## 测试结果

红灯确认：

- `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`：编译失败，错误为 `cannot find 'SelectionContextProvider' in scope`、`cannot find 'AppWindowTitleContextProvider' in scope`、`cannot find 'AppURLContextProvider' in scope`、`cannot find 'ClipboardCurrentContextProvider' in scope`、`cannot find 'FileReadContextProvider' in scope`，符合 provider 类型缺失预期。
- Code review follow-up 红灯：`cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests` 编译失败，错误为 `extra arguments at positions #2, #3 in call`，证明 `FileReadContextProvider` 尚未支持 `maxBytes` / `chunkSize`。

最终验证：

- `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`：9 tests passed。
- `cd SliceAIKit && swift test --filter OrchestrationTests.ContextCollectorTests`：10 tests passed。
- `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionGraphTests`：25 tests passed。
- `git diff --check`：通过。

## Self-review

- 文件读取先走 `PathSandbox.normalize` 再读文件，硬禁止路径即使被用户 allowlist 覆盖也会拒绝。
- 触及 IO 的剪贴板和文件 provider 均在 IO 边界前后检查取消；`file.read` 已从一次性 `String(contentsOf:)` 改为有 `maxBytes` 上限的分块读取，降低大文件和慢挂载路径对内存、取消和 prompt token 的风险。纯 seed/app provider 不需要额外取消点。
- 调试日志刻意不打印剪贴板内容、文件路径或文件内容，避免把上下文采集本身变成隐私泄漏源。
- 当前 `file.read` 只读 UTF-8 文本，不做 MIME 推断或二进制返回，符合 Task 7 的 KISS 范围；后续如需图片/二进制文件，应单独新增 provider 或扩展返回策略并补测试。
- `app.windowTitle` / `app.url` 对 nil 返回空字符串是有意降级；如果产品希望“缺失即失败”，需要先明确 optional/required 语义对用户体验的影响。
