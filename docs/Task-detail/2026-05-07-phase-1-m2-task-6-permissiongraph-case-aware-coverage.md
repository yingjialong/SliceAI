# Phase 1 M2 Task 6 · PermissionGraph Case-Aware Coverage

## 任务背景

Phase 0 的 `EffectivePermissions.undeclared` 使用字面量 `Set.subtracting` 判断 `effectivePermissions ⊆ tool.permissions`。进入 Phase 1 后，权限声明需要表达更宽的覆盖关系：例如声明 `~/Documents/**/*.md` 应覆盖具体读取 `~/Documents/a.md`，MCP server 声明 `tools=nil` 应覆盖同 server 的具体 tool。

本任务目标是把静态权限闭环升级为 case-aware coverage：对每个 effective permission，必须至少有一个 declared permission 能覆盖它，否则仍进入 `undeclared` 并阻止执行。

## 实施方案

1. 先在 `PermissionGraphTests` 增加覆盖规则测试，确认当前 raw Set 语义下红灯。
2. 在 Orchestration 内新增 `Permission.covers(_:fileNormalizer:)`，按权限 case 实现最小覆盖语义。
3. 在 `PathSandbox` 增加最小 hard-deny helper，供文件权限覆盖在 exact / prefix / glob 前统一拒绝敏感路径。
4. 将 `EffectivePermissions.undeclared` 从字面集合差升级为“effective 无 declared cover”的过滤结果。
5. 运行指定测试、`git diff --check`，完成 self-review 后提交。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 编写 PermissionGraph coverage 红灯测试。
- [x] 运行 `swift test --filter OrchestrationTests.PermissionGraphTests` 确认红灯。
- [x] 实现 case-aware coverage 与 PathSandbox hard-deny helper。
- [x] 运行指定回归测试与 `git diff --check`。
- [x] 更新本文档、master todolist，完成 self-review 并提交。

## 变动文件

- `SliceAIKit/Sources/Capabilities/SecurityKit/PathSandbox.swift`
- `SliceAIKit/Sources/Orchestration/Permissions/EffectivePermissions.swift`
- `SliceAIKit/Sources/Orchestration/Permissions/PermissionGraph.swift`
- `SliceAIKit/Tests/OrchestrationTests/PermissionGraphTests.swift`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-07-phase-1-m2-task-6-permissiongraph-case-aware-coverage.md`
- `docs/v2-refactor-master-todolist.md`
- `docs/Module/Orchestration.md`
- `docs/Module/Capabilities.md`
- `README.md`

## 代码修改逻辑

1. `EffectivePermissions.undeclared` 不再做字面 `union.subtracting(declared)`，而是逐个 effective permission 查找是否存在 declared permission 能覆盖它；没有任何 declared cover 时才进入 undeclared。
2. `PermissionGraph.swift` 内新增 `Permission.covers(_:fileNormalizer:)` 和默认文件路径 normalizer：
   - 标量权限保持同 case exact match；
   - `.fileRead` / `.fileWrite` 在 hard-deny 检查后做 exact、目录前缀、glob 匹配；
   - glob 支持 `*` 与 `**`，并保留内置 `.filesystem` 使用的相对 glob `"**"`；
   - `.mcp` 要求 server 相同，declared tools 为 `nil` 表示覆盖同 server 全部工具，否则 declared tools 必须是 effective tools 的超集；
   - `.shellExec` 只允许命令数组完全相等，空数组不再表示覆盖全部命令。
3. `PathSandbox` 新增 `isHardDenied(_:)`，只复用现有 hard-deny 前缀逻辑，不引入读写 allowlist。这样 PermissionGraph 能在静态 coverage 阶段拒绝敏感路径声明，避免 `/etc/passwd` 这类路径因“声明字符串相同”绕过执行前阻断。
4. 未实现 Streamable HTTP，也未支持旧 HTTP+SSE；本任务没有触碰 MCP transport。
5. Code quality review follow-up：`EffectivePermissions.undeclared(effective:declared:)` 抽成共享 helper，`InvocationReport.undeclaredPermissions` 复用同一路径，避免 report / audit 层用 raw Set 差集误报 declared glob、目录前缀或 MCP superset 已覆盖的 effective permission。
6. Code quality review follow-up：`.shell` builtin 仍映射为 `.shellExec(commands: [])`，但仅作为通用 shell capability 占位标记；Task 6 后空数组不表示命令通配，后续真实 shell.run 必须推导具体命令权限。

## 测试用例

新增：

- `test_fileRead_declaredGlobCoversConcretePath() async throws`
- `test_fileRead_declaredDirectoryPrefixCoversConcretePath() async throws`
- `test_fileRead_declaredGlobDoesNotCoverSiblingEscape() async throws`
- `test_fileRead_pathSandboxHardDeniedDeclarationDoesNotCoverEffective() async throws`
- `test_mcp_declaredNilToolsCoversConcreteTool() async throws`
- `test_mcp_declaredToolSupersetCoversConcreteTool() async throws`
- `test_mcp_missingToolIsUndeclared() async throws`
- `test_shellExec_requiresExactCommandList() async throws`
- `InvocationReportTests.test_undeclaredPermissions_declaredFileGlobCoversConcretePath()`
- `InvocationReportTests.test_undeclaredPermissions_declaredMCPSupersetCoversConcreteTool()`

## 测试结果

红灯确认：

- `swift test --filter OrchestrationTests.PermissionGraphTests`：新增正向覆盖用例在 raw Set 语义下失败 5 项，符合预期。

最终验证：

- `swift test --filter OrchestrationTests.PermissionGraphTests`：24 tests passed。
- `swift test --filter OrchestrationTests.ExecutionEngineTests`：18 tests passed。中间一次整组运行触发既有 cancellation 调度竞态失败；单用例复跑通过，最终整组复跑通过，未改 ExecutionEngine 或其测试夹具。
- `swift test --filter CapabilitiesTests.PathSandboxTests`：16 tests passed。
- `git diff --check`：通过。

Code quality review follow-up 验证：

- 红灯：`swift test --filter OrchestrationTests.InvocationReportTests` 新增 report glob / MCP superset 用例在 raw Set subtraction 下失败 2 项。
- 绿灯：`swift test --filter OrchestrationTests.InvocationReportTests`：8 tests passed。
- 绿灯：`swift test --filter OrchestrationTests.PermissionGraphTests`：24 tests passed。
- 绿灯：`swift test --filter OrchestrationTests.ExecutionEngineTests`：18 tests passed。
- 绿灯：`swift test --filter CapabilitiesTests.PathSandboxTests`：16 tests passed。
- 绿灯：`git diff --check`。

## Self-review

- 覆盖语义只在 declared → effective 方向生效，声明多于实际权限仍不报错。
- hard-deny 在 exact / prefix / glob 前执行；hard-denied effective 会保留在 undeclared，执行引擎仍会在文件 IO 前失败。
- 目录前缀只接受显式以 `/` 结尾的声明，避免把 `~/Documents/foo` 误解释为目录并覆盖 `~/Documents/foobar`。
- glob sibling escape 已用 `~/Documents/sliceai-notes/**/*.md` 对 `~/Documents/sliceai-notes-evil/task-6.md` 锁定，避免 `sliceai-notes` 同名前缀误覆盖 sibling 目录。
- InvocationReport 与 ExecutionEngine gate 共用 `EffectivePermissions.undeclared(effective:declared:)`，避免审计层与执行层语义分叉。
- MCP `tools=nil` 只覆盖同 server，不跨 server；空数组只是空集合，不代表全部工具。
- shellExec 没有实现“空数组全开”，避免延续 Phase 0 注释中的宽松语义到 Task 6 后的权限覆盖层。
