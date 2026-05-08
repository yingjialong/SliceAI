# Phase 1 M2 Task 8 · Permission Consent Grants

## 任务背景

M2 Task 6 已建立 `PermissionGraph` 与 `PermissionBroker` 的权限下限模型，Task 7 已接入核心 ContextProvider。Task 8 的目标是把运行时权限确认从“返回待 UI 处理状态”推进到 UI-free consent boundary：生产 `PermissionBroker` 只依赖 `PermissionConsentPresenting` 协议，并把可缓存授权写入 session store 或 Settings-only persistent store。

## 实施方案

1. 先补充 `PermissionBroker`、`PermissionGrantStore`、`PersistentPermissionGrantStore` 的红灯测试。
2. 新增 `PermissionConsentRequest` / `PermissionConsentDecision` / `PermissionConsentPresenting` 协议边界。
3. 将 `PermissionBroker` 改为持有 presenter；dry-run 不调用 presenter，非 dry-run 由 presenter 决策并返回 `.approved` / `.denied`。
4. 让 session store 和 persistent store 在存储层拒绝不可缓存权限，避免只依赖 broker 检查。
5. 补齐持久化 JSON round-trip，默认路径为 `~/Library/Application Support/SliceAI/permission-grants.json`。
6. 运行指定测试，更新 README、模块文档和 master todolist，最后提交。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 编写 Task 8 红灯测试。
- [x] 运行指定测试确认 red。
- [x] 实现 consent 协议与 broker 集成。
- [x] 实现 session / persistent grant 存储规则。
- [x] 运行指定测试并修复回归。
- [x] 更新 README、模块文档和 master todolist。
- [x] 提交 commit。

## 变动文件

- `SliceAIApp/AppContainer.swift`
- `SliceAIKit/Sources/Capabilities/Permissions/PersistentPermissionGrantStore.swift`
- `SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift`
- `SliceAIKit/Sources/Orchestration/Permissions/PermissionBrokerProtocol.swift`
- `SliceAIKit/Sources/Orchestration/Permissions/PermissionGrantStore.swift`
- `SliceAIKit/Tests/CapabilitiesTests/PersistentPermissionGrantStoreTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/PermissionBrokerTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/PermissionGrantStoreTests.swift`
- `README.md`
- `docs/Module/Capabilities.md`
- `docs/Module/Orchestration.md`
- `docs/Task_history.md`
- `docs/v2-refactor-master-todolist.md`

## 代码修改逻辑

- `PermissionBrokerProtocol` 新增 `PermissionConsentRequest`、`PermissionConsentDecision` 与 `PermissionConsentPresenting`。Orchestration 只依赖该 UI-free 协议，不直接接触 AppKit。
- `PermissionBroker` 构造函数改为必须注入 presenter，可选注入 `PersistentPermissionGrantStore`。cacheable tier 先查 session store，再查 persistent store；命中即 `.approved`。
- 非 dry-run 下，broker 内部调用 presenter 并把结果解析为 `.approved` 或 `.denied`，不再把 `.requiresUserConsent` 泄漏给生产调用方。`.oneTime` 不写缓存，`.session` 只写 cacheable permission，`.persistent` 在 runtime 被拒绝，因为持久授权只能由 Settings 管理。
- dry-run 不调用 presenter；遇到需要确认的权限返回 `.wouldRequireConsent`，用于预览“真实执行会需要确认”。
- `PermissionGrantStore` 保持 session-only，并在存储层拒绝 `.mcp`、`.network`、`.shellExec`、`.appIntents`，防止调用方绕过 broker 缓存每次确认权限。
- `PersistentPermissionGrantStore` 位于 Capabilities，默认写入 `~/Library/Application Support/SliceAI/permission-grants.json`；只接受 `.persistent` scope 并同样拒绝不可缓存权限。
- `AppContainer` 为新的 broker 构造函数注入 `RuntimePermissionConsentPresenter`。Task 8 阶段该 presenter fail-closed，真实 AppKit 弹窗留给 M2 Task 9。

## 测试用例

- `test_persistentGrant_roundTripsToDisk()`
- `test_sessionGrant_doesNotPersistAcrossStoreInstances()`
- `test_mcpPermission_isNeverCached()`
- `test_networkWrite_isNeverCached()`
- `test_dryRun_networkWriteReturnsWouldRequireConsent()`
- `test_readonlyLocal_unknownRequiresConsent()`
- `test_permissionBroker_callsConsentHandlerForFirstTimeLocalWrite()`
- `test_permissionBroker_approvalRecordsSessionGrantForCacheableTier()`
- `test_persistentStore_rejectsMCPPermission()`
- 额外覆盖：MCP presenter session approval 仍不缓存、persistent store 忽略 session scope、store 层拒绝 exec / network 写入。

## 测试结果

- `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionBrokerTests`：通过（37 tests）。
- `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionGrantStoreTests`：通过（14 tests）。
- `cd SliceAIKit && swift test --filter CapabilitiesTests.PersistentPermissionGrantStoreTests`：通过（3 tests）。
- `cd SliceAIKit && swift test`：通过（670 tests）。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过。

## Self-review

- Task 8 的生产 broker 行为已从“返回待 UI 处理状态”推进到“内部 presenter 决策”，`GateOutcome.requiresUserConsent` 仅保留给测试 doubles 和兼容路径。
- 不可缓存权限在 broker、session store、persistent store 三层均 fail-closed；MCP / network / shell / AppIntents 不会被 session 或 persistent grant 缓存。
- 当前 App runtime presenter 仍为 fail-closed 临时实现，这是 Task 9 接真实 UI 前的安全过渡，不应被视为用户可用体验完成。
