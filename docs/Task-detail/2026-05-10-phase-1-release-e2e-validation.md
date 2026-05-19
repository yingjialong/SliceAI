# Phase 1 Release E2E Validation

## 任务背景

Task 16 已完成 Phase 1 M4 release readiness 收口：代码主干、自动化 gate、SwiftLint strict、模块文档和 E2E checklist 脚本均已通过 review。当前剩余缺口不是继续加功能，而是在真实 release 环境中验证五类 MCP server 和关键 App 场景，确认 Phase 1 能达到 `v0.3` 发布标准。

本任务必须把“前置条件检查”“真实 tools/list / tool call 证据”“App 实机场景回归”严格区分。`scripts/phase1-mcp-e2e.sh` 只能证明环境是否齐备并输出 checklist，不能替代真实 E2E 结果。

## 现有问题

- 根工作区 `docs/handoffs/2026-05-08-phase-1-mcp-context.md` 不存在；上轮实际 handoff 位于 `.worktrees/phase-1-mcp-context/docs/handoffs/2026-05-08-phase-1-mcp-context.md`。
- 当前应在 worktree `/Users/majiajun/workspace/SliceAI/.worktrees/phase-1-mcp-context` 的 `feature/phase-1-mcp-context` 分支继续，不应修改根工作区 `main` 上已有的未提交文档改动。
- Task 16 已记录本机缺少真实 E2E 前置条件：SliceAI `mcp.json`、Brave API key、Postgres 只读连接串、SQLite 测试 DB、filesystem 安全测试目录。
- 2026-05-19 已补齐本地无 secret 的 filesystem / git / sqlite E2E fixture 和 SliceAI `mcp.json` 三项本地 server 配置；随后使用 Docker 起本地 Postgres E2E 容器并加入 `postgres` MCP server。用户已提供 Brave Search API key，已写入本机 `mcp.json` 的 `brave-search` server env；key 原值不写入文档。
- `@modelcontextprotocol/server-brave-search` npm 包可解析但已标记 deprecated；release 前需要确认继续使用是否可接受，或把替代方案作为发布风险记录。
- `@modelcontextprotocol/server-git` npm registry 返回 404；当前可用入口是 `uvx --from mcp-server-git mcp-server-git`。

## 实施方案

1. 创建本任务文档并登记 `docs/Task_history.md`。
2. 只读核对当前 worktree 状态，确认除 handoff scratch 外没有未提交代码。
3. 运行 `bash scripts/phase1-mcp-e2e.sh`，记录命令、配置摘要和缺失项；脚本输出不得包含 secret 原值。
4. 准备或确认五类 MCP server 前置条件：filesystem、postgres、brave-search、git、sqlite。
5. 对每个 server 记录 Settings 测试连接 `tools/list` 结果，以及一次安全只读 `tools/call` 结果。
6. 执行 App 回归：Safari / Notes / Slack 的 `web-search-summarize`、permission approval / denial、ResultPanel tool-call lifecycle、per-tool hotkey、command palette hotkey。
7. 如果发现代码 bug，只做最小修复，并运行相关 focused tests、full release gate 和 `claude-review-loop`；如果只是环境缺失，记录 blocker，不伪造通过。
8. 完成后更新 README、master todolist、Phase 1 plan 和本任务文档；只有真实 E2E 通过后才进入 `v0.3` release prep。

## ToDoList

- [x] 创建 Task 17 任务文档。
- [x] 登记 `docs/Task_history.md`。
- [x] 只读核对 worktree 状态。
- [x] 运行 `bash scripts/phase1-mcp-e2e.sh` 并记录脱敏输出摘要。
- [x] 准备 / 确认 filesystem MCP server 前置条件。
- [x] 准备 / 确认 postgres MCP server 前置条件。
- [x] 准备 / 确认 brave-search MCP server 前置条件。
- [x] 准备 / 确认 git MCP server 前置条件。
- [x] 准备 / 确认 sqlite MCP server 前置条件。
- [x] 验证 filesystem server：`tools/list` + 一次安全只读 tool call。
- [x] 验证 postgres server：`tools/list` + 一次只读 schema/query tool call。
- [x] 验证 brave-search server：`tools/list` + 一次 search tool call。
- [x] 验证 git server：`tools/list` + 一次只读 status/log tool call。
- [x] 验证 sqlite server：`tools/list` + 一次只读 query tool call。
- [x] 回归 Safari `web-search-summarize`（用户基本复测通过；未沉淀逐项截图 / 日志证据）。
- [x] 回归 Notes `web-search-summarize`（用户基本复测通过；未沉淀逐项截图 / 日志证据）。
- [x] 回归 Slack `web-search-summarize`（用户基本复测通过；未沉淀逐项截图 / 日志证据）。
- [x] 回归 permission approval / denial（用户基本复测通过；未沉淀逐项截图 / 日志证据）。
- [x] 回归 ResultPanel proposed / approved / result / denied / error rows（用户基本复测通过；未沉淀逐项截图 / 日志证据）。
- [x] 回归 per-tool hotkey 与 command palette hotkey（用户基本复测通过；未沉淀逐项截图 / 日志证据）。
- [x] 修复 DeepSeek thinking-mode tool-call follow-up 丢失 `reasoning_content`。
- [x] 修复 Brave 搜索 MCP 权限弹窗会话按钮不可用，并增加“以后一直允许”路径。
- [x] 修复 Agent 连续 MCP tool call 达到 `maxSteps` 后没有最终回答。
- [x] 修复 Agent 最终回合把 DSML 工具调用标记当普通文本输出的问题。
- [x] 修复 Web Search Summarize 单次运行中过量顺序 Brave 搜索触发限流的问题。
- [x] 如有代码修复，运行 focused tests、full release gate。
- [x] release prep 前运行最终 `claude-review-loop` / code review。
- [x] 更新 README、master todolist、Phase 1 plan 和任务文档总结。

## 环境前置条件

### 文件路径

- SliceAI MCP 配置：`~/Library/Application Support/SliceAI/mcp.json`
- filesystem 安全目录：通过 `SLICEAI_E2E_FILESYSTEM_DIR` 指向一个只含测试文件的目录。
- git 测试仓库：通过 `SLICEAI_E2E_GIT_REPO` 指向一个可安全读取的仓库。
- sqlite 测试 DB：通过 `SLICEAI_E2E_SQLITE_DB` 指向一个测试数据库文件。

### Secret 与敏感配置

- Brave Search API key：只通过环境变量或 SliceAI MCP server env 配置注入，不写入文档。
- Postgres 只读连接串：只通过环境变量或 SliceAI MCP server args/env 配置注入，不写入文档。
- 任何 `mcp.json` 的 `args`、`url`、`env` 值不得复制到任务文档、README、handoff 或 review log。

### 推荐 server 入口

- filesystem：`npx -y @modelcontextprotocol/server-filesystem "$SLICEAI_E2E_FILESYSTEM_DIR"`
- postgres：`npx -y @modelcontextprotocol/server-postgres "$SLICEAI_E2E_POSTGRES_URL"`
- brave-search：`BRAVE_API_KEY="<set outside docs>" npx -y @modelcontextprotocol/server-brave-search`
- git：`uvx --from mcp-server-git mcp-server-git --repository "$SLICEAI_E2E_GIT_REPO"`
- sqlite：`uvx --from mcp-server-sqlite mcp-server-sqlite --db-path "$SLICEAI_E2E_SQLITE_DB"`

## 测试计划

- `git status -sb`：确认 worktree 只包含预期文档改动和 handoff scratch。
- `bash scripts/phase1-mcp-e2e.sh`：检查本机命令、环境变量和配置摘要，确认输出不泄露 secret 原值。
- Settings UI MCP Servers 页面：逐个 server 执行测试连接，记录 `tools/list` 结果摘要。
- MCP tool call：逐个 server 执行一次安全只读调用，记录 tool 名称、输入类型摘要、输出摘要和是否通过。
- App 实机回归：Safari / Notes / Slack 中执行 `web-search-summarize`，记录权限弹窗、tool-call row、ResultPanel 终态和异常。
- 代码修复时追加：focused tests、`cd SliceAIKit && swift build`、`cd SliceAIKit && swift test --parallel --enable-code-coverage`、`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`、`swiftlint lint --strict`。

## 当前检查结果

### Worktree 状态

- `git status -sb`：当前 worktree 为 `feature/phase-1-mcp-context`，未提交内容只有本任务文档、`docs/Task_history.md` 和未跟踪 handoff scratch。
- `git diff --check`：通过，无 whitespace error。
- 根工作区 `main` 仍有既有未提交文档改动；本任务不在根工作区继续编辑。

### E2E checklist 脚本

命令：

```bash
bash scripts/phase1-mcp-e2e.sh
```

结果摘要：

- 已具备命令：`node`、`npm`、`npx`、`uvx`、`git`、`sqlite3`、`jq`。
- 缺失命令：`psql`。
- 当前命令环境可从本机 `mcp.json` 注入并通过脚本检查的环境变量：`BRAVE_API_KEY`、`SLICEAI_E2E_FILESYSTEM_DIR`、`SLICEAI_E2E_POSTGRES_URL`、`SLICEAI_E2E_GIT_REPO`、`SLICEAI_E2E_SQLITE_DB`。
- SliceAI MCP 配置已存在：`~/Library/Application Support/SliceAI/mcp.json`，脚本脱敏摘要显示 `filesystem`、`postgres`、`brave-search`、`git`、`sqlite` 五项 server。
- 脚本只输出 env key 名称、命令存在性和配置路径状态；本次输出未包含 secret 原值。

当前结论：5-server 直接 MCP E2E 的环境前置条件已齐备；本机仍缺 `psql`，但 Postgres MCP 已用 server 自身完成直接验证。完整 release E2E 仍需 Settings UI 与 App 场景证据，不能只用 checklist 代替。

### 2026-05-19 本地 MCP 环境搭建

- 创建 filesystem 安全目录：`~/Library/Application Support/SliceAI/E2E/filesystem`，包含只读样例文件 `sample.txt`。
- 创建 SQLite 测试 DB：`~/Library/Application Support/SliceAI/E2E/sliceai-e2e.sqlite`，包含 `notes` 表和两条测试记录。
- 使用当前 worktree `/Users/majiajun/workspace/SliceAI/.worktrees/phase-1-mcp-context` 作为 git 测试仓库。
- 写入 SliceAI MCP 配置：`~/Library/Application Support/SliceAI/mcp.json`，当前包含 `filesystem`、`git`、`sqlite` 三个 stdio server；runner confirmations 包含 `npx` 与 `uvx`。
- 重新运行 checklist 后，`SLICEAI_E2E_FILESYSTEM_DIR`、`SLICEAI_E2E_GIT_REPO`、`SLICEAI_E2E_SQLITE_DB` 对应前置条件已具备；`BRAVE_API_KEY`、`SLICEAI_E2E_POSTGRES_URL` 和 `psql` 仍缺失。
- 使用 Docker 启动本地 Postgres E2E 容器 `sliceai-e2e-postgres`，创建只读查询测试表和只读用户，并将 `postgres` stdio server 加入 `mcp.json`。连接串只写入本机 `mcp.json`，未写入文档或 shell 输出。
- 再次运行 checklist 后，`SLICEAI_E2E_POSTGRES_URL` 已可在当前命令环境中提供；脚本仍提示本机缺 `psql`，但 Postgres MCP 直接 E2E 已用 server 自身完成验证。
- 用户提供 Brave Search API key 后，已将 `brave-search` stdio server 加入本机 `mcp.json`；配置摘要为 server id `brave-search`、command `npx`、args 数量 2、env key `BRAVE_API_KEY`，未记录 key 原值。
- 当前 Debug App 已从本 worktree 构建产物启动：`build/e2e/Build/Products/Debug/SliceAI.app`。本项只证明 App 进程启动成功，不等同于 Settings UI 或 App 场景 E2E 已通过。
- 由于当前用户 `config-v2.json` 来自旧配置 / 自定义配置，缺少内置 `web-search-summarize` Agent 工具，且 Provider 未声明 `toolCalling` capability；已备份本机配置并补入 `web-search-summarize`，同时仅给 `deepSeek` Provider 标记 `toolCalling`，Agent provider selection 优先使用该 Provider。
- App 实测 `Web Search Summarize` 时，Brave MCP tool call 已完成，但后续 LLM finalize 阶段返回 `provider.invalidResponse(<redacted>)`。根因：DeepSeek V4 thinking mode 的 tool-call turn 要求后续请求回传 `reasoning_content`；现有 `OpenAICompatibleProvider` 只解析 `content` / `tool_calls`，`AgentExecutor` 回填 assistant tool-call message 时丢失 `reasoning_content`。
- 修复 `reasoning_content` 后继续 App 实测，发现权限弹窗中的“本次会话允许”不可点击，且没有“以后一直允许”；根因是所有 MCP 权限都被保守视为 network-write，每次只允许 one-time。当前修复只对白名单内置只读 `brave-search.brave_web_search` 开启 session / persistent grant，filesystem / git / postgres / sqlite 等 MCP 仍默认逐次确认。
- 同轮 App 实测还发现多次 Brave MCP 调用完成后没有最终回答；根因是 `AgentExecutor` 达到 `maxSteps` 后直接结束。第一轮修复是在达到工具调用轮数上限后再请求一次最终回答，避免静默无结果。
- 用户复测后发现最终回答仍不正确：ResultPanel 显示 `<|DSML|tool_calls>` / `<|DSML|invoke ...>` 一类内部工具调用标记。根因是最终回合虽然设置了 `tool_choice: none`，但仍向 provider 暴露 tools schema；该 OpenAI-compatible provider 会把“继续调用工具”的 DSML 标记作为普通文本流式返回，执行器又在校验前直接写入 UI。当前修复改为最终回合追加“只生成最终答案”的 user 指令、不再编码 `tools/tool_choice`，并先缓冲校验最终文本；若 provider 仍返回 DSML/tool-call markup，则产出受控 `provider.invalidResponse(<redacted>)`，不会再把协议标记写入 ResultPanel。
- 用户再次复测后最终正文已经出现，但中途有一条 `brave-search.brave_web_search` 返回 `Rate limit exceeded`。排查结果：`AgentExecutor+ToolCalls.processToolCalls` 是 `for call in calls` 顺序执行，不存在多 MCP call 并发 fan-out；`callMCPWithTimeout` 的 task group 只用于单次调用和超时竞争。限流根因是 `maxSteps` 只限制 LLM 轮数，不限制整次运行的总 tool call 数；模型可以在单轮返回多个 tool calls，也可以多轮连续搜索，旧默认 `maxSteps = 6` 且提示词没有搜索次数上限，导致一次 Web Search Summarize 打出 8 次 Brave 搜索。第一轮曾用 `maxSteps` 临时限制总 tool-call 预算；Task 56 已修正为独立 `AgentToolCallPolicy`：`maxSteps` 只表示 LLM ReAct 轮数，MCP 调用由总量、单轮、单工具、重复参数和 rate limit 停止策略控制。默认和本机 `web-search-summarize` 显式限制最多 2 次 Brave 搜索；超策略调用会生成对应 `role=.tool` 跳过消息以满足 provider 协议，但不会再调用 MCP / Brave API。

### 2026-05-19 直接 MCP JSON-RPC E2E 结果

| Server | `tools/list` | 安全 tool call | 结果 | 证据摘要 |
|---|---|---|---|---|
| filesystem | 通过，14 个 tools | `read_text_file` | 通过 | 成功读取 `sample.txt`，返回 “SliceAI Phase 1 filesystem MCP E2E sample.” |
| git | 通过，12 个 tools | `git_status` | 通过 | 成功返回 `feature/phase-1-mcp-context` 当前工作区状态。 |
| sqlite | 通过，6 个 tools | `read_query` | 通过 | 成功执行 `SELECT id, title FROM notes ORDER BY id;`，返回 `phase1` 和 `release` 两条记录。 |
| postgres | 通过，1 个 tool | `query` | 通过 | 成功执行 `SELECT id, title FROM e2e_notes ORDER BY id;`，返回 `phase1` 和 `release` 两条记录。 |
| brave-search | 通过，2 个 tools | `brave_web_search` | 通过 | 成功返回搜索结果；server stderr 仅显示 “Brave Search MCP Server running on stdio”。仍需把 deprecated npm 包作为 release 风险确认。 |

## E2E 证据记录模板

| Server | 前置条件 | `tools/list` | 安全 tool call | 结果 | 证据摘要 |
|---|---|---|---|---|---|
| filesystem | 已具备 | 通过 | `read_text_file` 通过 | 通过 | 读取 `sample.txt` 成功 |
| postgres | 已具备 | 通过 | `query` 通过 | 通过 | 返回 Docker Postgres 测试表两条记录 |
| brave-search | 已具备 | 通过 | `brave_web_search` 通过 | 通过 | 返回搜索结果，未记录 API key 原值 |
| git | 已具备 | 通过 | `git_status` 通过 | 通过 | 返回当前 worktree 状态 |
| sqlite | 已具备 | 通过 | `read_query` 通过 | 通过 | 返回测试表两条记录 |

| App 场景 | 结果 | 证据摘要 |
|---|---|---|
| Safari `web-search-summarize` | 基本通过 | 用户反馈基本测试无问题；未沉淀逐项截图 / 日志证据 |
| Notes `web-search-summarize` | 基本通过 | 用户反馈基本测试无问题；未沉淀逐项截图 / 日志证据 |
| Slack `web-search-summarize` | 基本通过 | 用户反馈基本测试无问题；未沉淀逐项截图 / 日志证据 |
| Permission approval | 基本通过 | 用户反馈基本测试无问题；未沉淀逐项截图 / 日志证据 |
| Permission denial | 基本通过 | 用户反馈基本测试无问题；未沉淀逐项截图 / 日志证据 |
| ResultPanel tool-call lifecycle | 基本通过 | 用户反馈基本测试无问题；未沉淀逐项截图 / 日志证据 |
| Per-tool hotkey | 基本通过 | 用户反馈基本测试无问题；未沉淀逐项截图 / 日志证据 |
| Command palette hotkey | 基本通过 | 用户反馈基本测试无问题；未沉淀逐项截图 / 日志证据 |

## 批判性检查

本任务最容易犯的错误是把“脚本能跑”误判为“E2E 通过”。脚本只读检查环境，不会替用户在 App 中调用 MCP tool，也不会证明权限 gate、AgentExecutor、ResultPanel 和真实 provider 的组合链路可用。若当前机器仍缺少 API key、数据库或测试数据源，正确结论是继续记录 blocker，而不是扩大代码改动去绕过真实验收。

另一个风险是为了快速通过 E2E，把真实 secret 写进文档或 shell 输出。这个风险比 E2E 未完成更严重；一旦需要展示配置，只能记录 server id、transport、args 数量、是否有 URL、env key 名称和脱敏结果摘要。

## 当前状态

- 任务主体验证已完成，进入 release prep 前最终 gate 阶段。
- 已完成只读 worktree 核对和 E2E checklist 脚本检查。
- 已同步 `README.md`、`docs/v2-refactor-master-todolist.md`、`docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`、`docs/Task_history.md`，下次恢复可从 Task 17 继续。
- 已完成 filesystem / postgres / brave-search / git / sqlite 五项本地 MCP server 的直接 JSON-RPC `tools/list` 和安全只读 / 低风险 `tools/call`。
- 已修复 DeepSeek V4 thinking mode tool-call follow-up：`reasoning_content` 会从 SSE delta 解码、在 Agent turn 中累积，并随下一轮 assistant tool-call message 回传；assistant tool-call message 的 `content` 保持空字符串，匹配 DeepSeek 示例。
- 已修复 Brave 搜索 MCP 权限 UX：`brave-search.brave_web_search` 精确权限支持“本次会话允许”和“以后一直允许”，grant 仍按 permission + provenance 精确缓存；其它 MCP 权限仍不缓存，避免把文件、数据库、Git 等工具误升级为长期授权。
- 已修复 Agent 达到 `maxSteps` 后无最终回答：执行器在处理完最后一轮 tool result 后会追加最终答案指令，并用不含 `tools/tool_choice` 的请求获取最终答案，避免 ResultPanel 只显示一串已完成工具调用。
- 已修复最终回合 DSML 工具标记泄漏：最终文本先缓冲校验，识别到 `DSML/tool_calls/invoke` 一类内部工具调用标记时转为受控 provider 错误，不再写入 UI。
- 已修复 Web Search Summarize 过量 Brave 搜索触发限流：MCP 调用链是顺序执行，问题不在并发控制；当前默认提示词和本机配置要求最多 2 次 Brave 搜索，且通过独立 `AgentToolCallPolicy` 控制总调用数、单轮调用数、重复参数和 rate limit 停止；`maxSteps` 不再兼任 MCP 总预算。
- 已补齐基础自定义 Agent Tool 配置：Tools 设置页可新增 Agent，编辑 prompt / provider / LLM 轮数 / MCP allowlist / 调用策略；allowlist 使用一行一个 `server.tool` 并同步 MCP 权限声明。
- 验证通过：focused tests（72 tests）、全量 SwiftPM（756 tests）、SwiftLint strict、`git diff --check`、Xcode Debug build、`build/e2e` Debug build。
- 用户已基本复测 Safari / Notes / Slack `web-search-summarize`、permission approval / denial、ResultPanel lifecycle、per-tool hotkey 和 command palette hotkey，未反馈阻塞问题；当前本机 `config-v2.json` 已同步新 `toolCallPolicy`，Debug App 已重启并重新读取配置，进程 `13394`。最终 `v0.3` release prep 已在 `main` 上完成：Claude review loop Round 2 approve，修复了长 MCP tool result 回填 LLM 被 `<truncated:N>` 替换、stdio MCP Settings 修改后旧 session 复用两项发布阻塞；最终 gate 和本地 unsigned DMG 预检均已通过。下一步等待用户确认远端 push / `v0.3.0` tag / GitHub Release。
