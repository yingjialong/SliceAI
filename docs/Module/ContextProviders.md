# ContextProviders 模块

## 模块职责

ContextProviders 模块把 `Tool.contexts` 中声明的上下文请求解析成 `ContextBag`，供 Prompt 和 Agent 执行链使用。实现分布在两层：

- `SliceAIKit/Sources/Capabilities/ContextProviders/`：五个核心 provider。
- `SliceAIKit/Sources/Orchestration/Context/ContextCollector.swift`：provider registry、并发解析、required / optional 失败语义和超时。

生产路径由 `AppContainer.makeContextProviderRegistry()` 注册同一套 provider，并让 `ContextCollector` 与 `PermissionGraph` 共用 registry，避免权限推导和实际解析使用不同 provider 集合。

## Provider 一览

| Provider | args schema | 返回值 | 推导权限 | 运行逻辑 |
|---|---|---|---|---|
| `selection` | 无 | `.text(seed.selection.text)` | 无 | 读取 `ExecutionSeed` 中的选区文本，不触发 IO |
| `app.windowTitle` | 无 | `.text(app.windowTitle ?? "")` | 无 | 读取前台 app 快照中的窗口标题，缺失时降级为空字符串 |
| `app.url` | 无 | `.text(app.url?.absoluteString ?? "")` | 无 | 读取前台 app 快照中的 URL，非浏览器或缺失时降级为空字符串 |
| `clipboard.current` | 无 | `.text(clipboardText ?? "")` | `.clipboard` | 生产通过 App 层注入的 `NSPasteboard` 读取闭包获取剪贴板文本 |
| `file.read` | `path` | `.text(fileText)` | `.fileRead(path:)` | 先经 `PathSandbox` 校验，再按 chunk 读取 UTF-8 文本 |

## ContextCollector 语义

`ContextCollector.resolve(seed:requests:)` 使用平铺并发模型：

- 每个 `ContextRequest` 独立执行，不支持 provider 之间的 DAG 或依赖关系。
- required 请求失败会抛出 `SliceError.context(.requiredFailed)`，并通过结构化并发取消兄弟任务。
- optional 请求失败会记录到 `ResolvedExecutionContext.failures`，主流程继续。
- 找不到 provider 时，required 抛错，optional 记录失败。
- 单 request 默认 timeout 为 5 秒。
- 非 `SliceError` 的底层错误会包装为安全的 `SliceError`，避免泄露 provider 内部细节。

这套语义保证 required context 失败能 fail closed，optional context 失败不会阻断用户完成一次执行。

## 取消要求

Provider 需要在 IO 边界前后配合取消：

- `ContextCollector` 的 timeout 和外层取消都依赖 Swift structured concurrency 的协作式取消。
- `clipboard.current` 在读取剪贴板前后调用 `Task.checkCancellation()`。
- `file.read` 在打开文件、每个 chunk 读取前后、读取完成前调用 `Task.checkCancellation()`。
- 如果用户关闭 ResultPanel 或执行被取消，取消应穿透为 `CancellationError`，不能被包装成业务失败或写入失败 audit。

## file.read 与 PathSandbox

`file.read` 是唯一直接触达文件系统的核心 provider，因此安全边界集中在这里：

- `args["path"]` 缺失时，权限推导返回空数组；执行时会把空路径交给 `PathSandbox.normalize`，由 sandbox 决定失败。
- 执行前调用 `PathSandbox.normalize(rawPath, role: .read)`。
- `PathSandbox` 负责路径规范化、用户目录 allowlist、硬禁止路径和符号链接展开后的兜底拦截。
- 文件按 chunk 读取，默认单次 chunk 为 64 KiB。
- 默认最大读取 1 MiB，超限抛出非敏感错误 `file.read.maxBytesExceeded`。
- 只接受 UTF-8 文本；非 UTF-8 抛出 `file.read.invalidUTF8`。

`file.read` 不猜测 MIME，不做二进制解析，也不在 provider 内自行绕过权限模型。

## App 生产接线

`AppContainer.makeContextProviderRegistry()` 注册：

- `SelectionContextProvider()`
- `AppWindowTitleContextProvider()`
- `AppURLContextProvider()`
- `ClipboardCurrentContextProvider(readString: AppContextAdapters.readClipboardString)`
- `FileReadContextProvider(sandbox: PathSandbox())`

剪贴板读取通过 `AppContextAdapters` 隔离在 App target 内，避免 Capabilities 直接散落 AppKit 读取细节。选区和前台 app 快照来自 `ExecutionSeed`，由 AppDelegate 触发链在执行前构造。

## 自动化覆盖

核心测试入口：

- `CapabilitiesTests.ContextProviderTests`
- `OrchestrationTests.ContextCollectorTests`
- `OrchestrationTests.PermissionGraphTests`

Task 16 release gate 已通过：

- `cd SliceAIKit && swift test --parallel --enable-code-coverage`：735 tests，0 failures。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过。
- `swiftlint lint --strict`：170 files，0 violations。
