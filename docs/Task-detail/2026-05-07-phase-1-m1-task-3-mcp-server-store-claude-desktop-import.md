# Phase 1 M1 Task 3 · MCP Server Store And Claude Desktop Import

## 任务背景

M1 Task 1/2 已经建立 SliceCore canonical MCP JSON/value contract，并让 Capabilities 的 MCP client protocol 直接消费 canonical `MCPDescriptor`。Task 3 需要补齐 MCP server 配置的本地持久化、导入 Claude Desktop stdio 配置，以及写入前的 fail-closed 校验，为后续真实 MCP stdio client 和 AgentExecutor wiring 提供稳定配置入口。

## 现有问题

- Capabilities 目前只有 `MCPClientProtocol` 和 `MockMCPClient`，没有读取 `mcp.json` 的 store。
- 缺少对 `.unknown` provenance、相对 command、未确认 runner、远程 transport 的统一拒绝逻辑。
- Claude Desktop `mcpServers` 格式尚未导入到 SliceCore canonical `MCPDescriptor`。
- `MCPDescriptor` 的 `Equatable` 是 id-only，store round-trip 测试不能依赖整体 `XCTAssertEqual` 判断字段完整性。

## 实施方案

1. 新增 `MCPServerStoreTests` 与 `ClaudeDesktopMCPImporterTests`，先覆盖 store round-trip、未知 provenance、相对 command、Claude Desktop stdio 导入、M4 前远程 URL 拒绝、runner 首次确认拒绝。
2. 运行目标测试确认红灯，预期为 `MCPServerStore`、`MCPServerConfiguration`、`RunnerConfirmation`、`MCPServerValidation`、`ClaudeDesktopMCPImporter` 等类型缺失。
3. 新增 `MCPServerConfiguration`、`RunnerConfirmation` 与 `MCPServerStore` actor，默认路径为 `~/Library/Application Support/SliceAI/mcp.json`，`snapshot()` 返回校验后的 descriptors 并按 `id` 排序。
4. 新增 `MCPServerValidation` 与 `MCPServerValidationError`，集中处理 fail-closed 规则：未知来源、stdio 空命令、相对命令、未确认 allowlisted runner、未知 bare command、M1 远程 transport、websocket 全部拒绝。
5. 新增 `ClaudeDesktopMCPImporter`，仅解析 Claude Desktop 兼容 stdio 配置，应用调用方传入 provenance；M4 前遇到 `url` 或非 stdio 远程配置直接拒绝。
6. 运行指定目标测试、CapabilitiesTests、全量 `swift test` 与 `git diff --check`。
7. 更新 README / Capabilities 模块文档 / 本任务文档完成态并提交。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 编写失败测试。
- [x] 运行红灯测试并记录失败原因。
- [x] 实现 MCP server store 模型与 actor。
- [x] 实现 MCP server fail-closed 校验。
- [x] 实现 Claude Desktop stdio importer。
- [x] 运行目标测试、CapabilitiesTests、全量测试和 diff 检查。
- [x] 更新文档完成态并提交 commit。
- [x] Review fix：拒绝不支持的 schemaVersion。
- [x] Review fix：拒绝重复 server id。
- [x] Review fix：错误类型不回显原始 command path。
- [x] Review fix：删除未使用的 `invalidClaudeDesktopConfig` public case。
- [x] Claude review fix：绝对路径形式的 allowlisted runner 也必须 typed confirmation。
- [x] Claude review fix：版本化或大小写不同的绝对 runner path 也必须 typed confirmation。
- [x] Claude review fix：拒绝会隐藏真实 runner 的 `env` / shell wrapper command。

## 变动文件清单

- `SliceAIKit/Sources/Capabilities/MCP/MCPServerStore.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift`
- `SliceAIKit/Sources/Capabilities/MCP/ClaudeDesktopMCPImporter.swift`
- `SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/ClaudeDesktopMCPImporterTests.swift`
- `README.md`
- `docs/Module/Capabilities.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md`

## 代码修改逻辑

- `MCPServerConfiguration` 是 `mcp.json` 的顶层 schema，包含 `schemaVersion`、`servers` 和 `runnerConfirmations`；`RunnerConfirmation` 用 `command + confirmedAt + confirmationText` 表达用户对 runner 的首次 typed confirmation。
- `MCPServerStore` 是 actor，默认路径为 `~/Library/Application Support/SliceAI/mcp.json`；`save(_:)` 先校验后原子写入，`load()` 文件不存在时返回 schemaVersion=1 的空配置，文件存在时解码并校验，`snapshot()` 复用 `load()` 并按 `id` 排序返回 runtime descriptors。
- `MCPServerValidation.validate(_:)` 先做配置级校验：`schemaVersion` 必须等于 `MCPServerStore.currentSchemaVersion`，且 `servers` 里的 `descriptor.id` 不能重复；随后逐个 descriptor 校验。`.unknown` provenance 直接拒绝；`.stdio` 要求非空 command 且 `url == nil`；`.streamableHTTP`、`.sse`、`.websocket` 在 M1 全部拒绝写入。
- stdio command 校验分两类：`npx`、`uvx`、`node`、`python`、`python3` 必须存在同 command 且 `confirmationText` 非空的 `RunnerConfirmation`；绝对路径形式的 command 会先通过路径校验，再拒绝 `env` / shell wrapper command，避免真实 runner 藏在 args 或 `-c` payload 中绕过确认；随后按大小写无关的 basename 归一到 runner 家族，`python3.11`、`node22` 这类版本化解释器路径也必须存在对应家族 runner 的 typed confirmation。其他 command 必须是绝对路径，且原始路径和标准化路径都不能包含 `..` 组件。未知 bare command 与相对 path 同样 fail closed。
- `MCPServerValidationError` 将原 `relativeCommandPath(id:command:)` 收敛为 `invalidCommandPath(id:)`，避免 public error payload 携带用户本地路径；`unconfirmedRunner(id:command:)` 只回显 allowlisted runner 字面量。
- 删除未使用的 `invalidClaudeDesktopConfig(reason:)`，避免 public API 暴露未定义语义的错误入口。
- `ClaudeDesktopMCPImporter` 只解析 Claude Desktop `mcpServers` 的 `command`、`args`、`env`、`url` 字段。存在 `url` 时抛 `.invalidRemoteURL`，缺少 command 时抛 `.missingCommand`，`.unknown` provenance 抛 `.unknownProvenance`。它不会检查 runner confirmation，避免把导入和用户确认 UI 流程耦合；最终写入仍由 store validation 把关。
- 新增测试按字段断言 descriptor round-trip，避免 `MCPDescriptor` id-only `Equatable` 掩盖字段损坏。

## 测试用例与结果

- 红灯命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests`：失败，原因符合预期。`MCPServerStore`、`MCPServerConfiguration`、`RunnerConfirmation`、`MCPServerValidation`、`MCPServerValidationError`、`ClaudeDesktopMCPImporter` 等类型尚不存在。
  - `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`：失败，原因符合预期。`ClaudeDesktopMCPImporter` 与 `MCPServerValidationError` 尚不存在。
- 绿色命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests`：通过，4 tests。
  - `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`：通过，2 tests。
  - `swift test --filter CapabilitiesTests`：通过，39 tests。
  - `swift test`：通过，602 tests。
  - `git diff --check`：通过，无 whitespace error。
- Review fix 红灯命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests`：失败，原因符合预期。`MCPServerValidationError` 尚无 `.invalidCommandPath`、`.unsupportedSchemaVersion`、`.duplicateServerID`。
- Review fix 绿色命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests`：通过，6 tests。
  - `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`：通过，2 tests。
  - `swift test --filter CapabilitiesTests`：通过，41 tests。
  - `swift test`：通过，604 tests。
  - `git diff --check`：通过，无 whitespace error。
- Claude review fix 红灯命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_runnerConfirmationRequiredForAbsoluteRunnerPaths`：失败，原因符合预期。绝对路径 `/usr/local/bin/npx` 未抛出 `.unconfirmedRunner`。
- Claude review fix 绿色命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_runnerConfirmationRequiredForAbsoluteRunnerPaths`：通过，1 test。
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests`：通过，7 tests。
  - `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`：通过，2 tests。
  - `swift test --filter CapabilitiesTests`：通过，42 tests。
  - `swift test`：通过，605 tests。
  - `git diff --check`：通过，无 whitespace error。
- Claude review round 2 fix 红灯命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_runnerConfirmationRequiredForVersionedRunnerPaths`：失败，原因符合预期。版本化绝对 runner path 未抛出 `.unconfirmedRunner`。
- Claude review round 2 fix 绿色命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_runnerConfirmationRequiredForVersionedRunnerPaths`：通过，1 test。
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests`：通过，8 tests。
  - `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`：通过，2 tests。
  - `swift test --filter CapabilitiesTests`：通过，43 tests。
  - `swift test`：通过，606 tests。
  - `git diff --check`：通过，无 whitespace error。
- Claude review round 3 fix 红灯命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_storeRejectsWrapperCommandsThatCanHideRunners`：失败，原因符合预期。`/usr/bin/env` 与 `/bin/sh` wrapper command 未被拒绝。
- Claude review round 3 fix 绿色命令：
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_storeRejectsWrapperCommandsThatCanHideRunners`：通过，1 test。
  - `swift test --filter CapabilitiesTests.MCPServerStoreTests`：通过，9 tests。
  - `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`：通过，2 tests。
  - `swift test --filter CapabilitiesTests`：通过，44 tests。
  - `swift test`：通过，607 tests。
  - `git diff --check`：通过，无 whitespace error。
