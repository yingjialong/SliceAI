# Phase 1 M4 Task 16 · Five MCP Server E2E And Release Documentation

## 任务背景

Task 14 已补齐 Streamable HTTP，Task 15 已补齐 per-tool hotkeys。Phase 1 剩余工作不再是新增核心功能，而是 release readiness 收口：确认 5 个 MCP server 的端到端证据、App 关键场景回归、全量自动化 gate、模块文档和项目状态文档。

本任务的目标是把 Phase 1 的 MCP + Context 主干从“功能已实现”推进到“可交付、可复查、可恢复”的状态。证据必须写入文档；无法在当前机器真实执行的手工项必须记录前置条件和 blocker，不能伪造通过。

## 当前计划差异

Phase plan 的 Task 16 要求 M4 gate 中 `swiftlint lint --strict` 全仓通过。当前 Task 14/15 均记录全仓 strict lint 被 13 个既有历史违规阻塞。本任务是 release readiness 收口，继续把这些违规只写成 blocker 会让 M4 gate 永远无法闭合；因此本任务将先把这些 lint blocker 作为最小质量修复处理，再运行完整 gate。

E2E 手工验证依赖本机安装并配置 filesystem、postgres、brave-search、git、sqlite 五类 MCP server，以及可用 API key / 测试数据源。若本机缺少任一条件，本任务会提供脚本化 checklist 和可执行命令，并在任务文档中记录“未执行原因 / 需要用户提供的环境条件”。

## 实施方案

1. 创建任务文档并登记 Task_history。
2. 核对 M4 gate 和历史 lint blocker，修复 release readiness 必需的全仓 strict lint 违规。
3. 检查本机 5 个 MCP server 条件，记录已具备项和缺失项。
4. 运行自动化 gate：`swift build`、`swift test --parallel --enable-code-coverage`、App Debug build、`swiftlint lint --strict`。
5. 执行或生成 5-server E2E checklist，并记录 filesystem / postgres / brave-search / git / sqlite 的证据或 blocker。
6. 执行或记录 App 场景回归：Safari、Notes、Slack、权限批准/拒绝、ResultPanel lifecycle、per-tool hotkey、命令面板热键。
7. 编写 `docs/Module/MCPClient.md` 和 `docs/Module/ContextProviders.md`，更新 README、Task_history、Phase 1 planning doc 和 master todolist，提交实现与文档后运行 `claude-review-loop`。

## ToDoList

- [x] 创建 Task 16 任务文档。
- [x] 登记 Task_history。
- [x] 核对 M4 gate 与历史 lint blocker。
- [x] 修复 release readiness 必需的全仓 strict lint 违规。
- [x] 检查 5 个 MCP server 本机条件。
- [x] 创建 E2E checklist 脚本。
- [x] 运行自动化 gate。
- [x] 执行 / 记录 5-server E2E 证据。
- [x] 执行 / 记录 App 场景回归证据。
- [x] 编写 `docs/Module/MCPClient.md`。
- [x] 编写 `docs/Module/ContextProviders.md`。
- [x] 更新 README、Task_history、planning doc、master todolist。
- [ ] 提交 commit。
- [ ] 运行 `claude-review-loop` 并记录结果。

## 变动文件（计划）

- `README.md`：更新 Phase 1 / v0.3 readiness 状态、验证结果和历史记录。
- `docs/Task_history.md`：登记 Task 16。
- `docs/Task-detail/2026-05-09-phase-1-m4-task-16-five-server-e2e-release-readiness.md`：记录实施、证据、测试和 review loop。
- `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`：更新 Phase 1 planning 的完成状态。
- `docs/v2-refactor-master-todolist.md`：更新 Dashboard、Phase 1 状态和历史 snapshot。
- `docs/Module/MCPClient.md`：新增 MCP client 模块文档。
- `docs/Module/ContextProviders.md`：新增 ContextProviders 模块文档。
- `scripts/phase1-mcp-e2e.sh`：新增手工 E2E checklist 脚本。
- Swift lint blocker 文件：仅做 SwiftLint 必需的格式 / 拆分 / 行长修复，不改变业务行为。

## 测试计划

- `swiftlint lint --strict`
- `cd SliceAIKit && swift build`
- `cd SliceAIKit && swift test --parallel --enable-code-coverage`
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
- `bash scripts/phase1-mcp-e2e.sh`
- 5-server MCP E2E 手工检查
- App 场景手工回归

## 测试结果

- `swiftlint lint --strict SliceAIKit/Sources/SettingsUI/Pages/MCPServersPage.swift SliceAIKit/Sources/SettingsUI/Pages/MCPServersPage+Editor.swift SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient+Session.swift SliceAIKit/Sources/Capabilities/MCP/MCPServerStore.swift SliceAIKit/Sources/Capabilities/MCP/MCPDiagnosticLog.swift SliceAIKit/Sources/Capabilities/MCP/ClaudeDesktopMCPImporter.swift SliceAIKit/Sources/Capabilities/Permissions/PersistentPermissionGrantStore.swift SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift SliceAIApp/AppPermissionConsentPresenter.swift`：通过，0 violations。
- `cd SliceAIKit && swift test --filter PermissionBrokerTests`：通过，37 tests，0 failures。
- `cd SliceAIKit && swift build`：通过。
- `cd SliceAIKit && swift test --parallel --enable-code-coverage`：通过，735 tests，0 failures。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过，`** BUILD SUCCEEDED **`。
- `swiftlint lint --strict`：通过，170 files，0 violations。
- `bash scripts/phase1-mcp-e2e.sh`：通过，脚本完成只读环境检查和手工 checklist 输出；检查结果显示真实 E2E 前置条件缺失。

## 代码修改逻辑

- 拆分 `MCPServersPage.swift` 中的 editor/import/status/draft 类型到 `MCPServersPage+Editor.swift`，仅降低原文件长度，不改变设置页 UI 行为。
- 拆分 `StdioMCPClient.swift` 的 session/router/stderr buffer/JSON-RPC ID helper 到 `StdioMCPClient+Session.swift`，并把 actor 主体按职责移入 extension，保持 stdio 初始化、工具列表、工具调用和 teardown 流程不变。
- 将 `PermissionBroker.decide` 的 grant cache 查询和 lower-bound 决策拆为独立 helper，保留原 tier/provenance 决策表与 presenter 解析路径。
- 修复 release gate 必需的行长、尾逗号和 `Logger.debug` 拼接问题；日志仍保留写入字节数和配置数量，便于调试。
- 新增 MCPClient 模块文档，覆盖配置路径、Claude Desktop 导入、stdio / Streamable HTTP 生命周期、权限 / provenance、诊断脱敏和 E2E server 矩阵。
- 新增 ContextProviders 模块文档，覆盖五个 provider、args schema、权限推导、取消语义和 `file.read` 的 PathSandbox 行为。
- 新增 E2E checklist 脚本，统一输出本机前置条件、server 命令模板和 App 回归矩阵，不写配置、不打印密钥。

## E2E 证据

### 本机条件核对

- `~/Library/Application Support/SliceAI/mcp.json`：不存在，当前 App 无可读取的 MCP server 配置。
- 基础命令：`node`、`npm`、`npx`、`uv`、`uvx`、`python3`、`git`、`sqlite3` 存在；`psql` 未找到。
- npm 包探测：`@modelcontextprotocol/server-filesystem` 版本 `2026.1.14` 可解析；`@modelcontextprotocol/server-brave-search` 版本 `0.6.2` 可解析但包已标记 deprecated；`@modelcontextprotocol/server-postgres` 版本 `0.6.2` 可解析；`@modelcontextprotocol/server-git` 在 npm registry 返回 404。
- uvx 包探测：`uvx --from mcp-server-git mcp-server-git --help` 可启动；`uvx --from mcp-server-sqlite mcp-server-sqlite --help` 可启动。
- 真实 E2E blocker：需要用户提供或配置 SliceAI `mcp.json`、Brave API key、Postgres 只读连接串、SQLite 测试 DB 路径和可安全读取的 filesystem 目录。

### 5-server E2E 结果

- filesystem：未执行真实 tools/list / tool call。原因：SliceAI `mcp.json` 不存在，且未提供 `SLICEAI_E2E_FILESYSTEM_DIR`。
- postgres：未执行真实 tools/list / read-only query。原因：未提供 `SLICEAI_E2E_POSTGRES_URL`，本机也未找到 `psql` 用于独立校验连接。
- brave-search：未执行真实 tools/list / search。原因：未提供 `BRAVE_API_KEY`；npm 包可解析但已标记 deprecated，后续 release 前应确认是否继续使用该包或切换到维护中的 server。
- git：未执行真实 tools/list / status/log。原因：SliceAI `mcp.json` 不存在，未提供 `SLICEAI_E2E_GIT_REPO`；`mcp-server-git` 的 uvx 入口可启动。
- sqlite：未执行真实 tools/list / read-only query。原因：SliceAI `mcp.json` 不存在，未提供 `SLICEAI_E2E_SQLITE_DB`；`mcp-server-sqlite` 的 uvx 入口可启动。

### App 场景回归结果

- Safari `web-search-summarize`：未执行。原因：缺 Brave Search MCP 配置、API key、可用 provider keychain 配置和交互式选区前置条件。
- Notes `web-search-summarize`：未执行。原因同上。
- Slack `web-search-summarize`：未执行。原因同上。
- permission approval / denial：未执行真实 App 弹窗回归；自动化覆盖见 `PermissionBrokerTests` 和 App Debug build。
- ResultPanel proposed / approved / result / denied / error rows：未执行真实 App 回归；自动化覆盖见 `WindowingTests.ResultPanelToolCallStateTests` 和 `ExecutionEngineTests`。
- per-tool hotkey / command palette hotkey：未执行真实 App 回归；自动化覆盖见 `HotkeyManagerTests.HotkeyTests` 和 App Debug build。

## Claude Review Loop

- 待记录。
