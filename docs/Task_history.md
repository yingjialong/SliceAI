# Task History

SliceAI 项目任务历史记录索引。每条记录对应 `docs/Task-detail/` 目录下的详细文件。

---

## Task 71 · Phase 3 Task 5 ToolEditor Draft State

- **时间**：2026-05-28
- **描述**：执行 Phase 3 ToolEditor v2 + Prompt Playground MVP implementation plan 的 Task 5，新增 ToolEditor 本地草稿会话和保存前校验，确保编辑已有 Tool 不会在 Save 前污染正式配置，并校验重复 id、disabled/unknown skills、无效或冲突热键。
- **详情**：[docs/Task-detail/2026-05-28-phase-3-task-5-tool-editor-draft-state.md](Task-detail/2026-05-28-phase-3-task-5-tool-editor-draft-state.md)
- **结果**：完成。已新增 `ToolEditorDraft`、`ToolEditorDraftSession` 和 `ToolDraftValidator`；保存前校验覆盖重复 Tool id、`Tool.validate()` 不变量、Agent disabled/unknown skills、无效工具热键、命令面板冲突和其它工具热键冲突。focused SettingsUI tests 通过。

## Task 70 · Phase 3 Task 4 Tool Playground Runner

- **时间**：2026-05-28
- **描述**：执行 Phase 3 ToolEditor v2 + Prompt Playground MVP implementation plan 的 Task 4，新增 Tool Playground Runner，并在 AppContainer 中创建 Playground 专用 ExecutionEngine，支持未保存 Tool 草稿 dry-run 试跑。
- **详情**：[docs/Task-detail/2026-05-28-phase-3-task-4-tool-playground-runner.md](Task-detail/2026-05-28-phase-3-task-4-tool-playground-runner.md)
- **结果**：完成。已新增 `ToolPlaygroundRunner`，非法草稿会在进入 engine 前失败；AppContainer 创建 Playground 专用 engine，共享生产上下文 / 权限 / Provider / MCP / Skill / Cost / Audit 依赖，仅替换 preview output 并禁用 side effect executor。为修正 plan 前置依赖，已提前给 `SettingsViewModel` 增加最小 `playgroundRunner` 注入点，未展开 UI 集成。focused tests 与 App Debug build 通过。

## Task 69 · Phase 3 Task 3 Agent MCP Run Policy

- **时间**：2026-05-28
- **描述**：执行 Phase 3 ToolEditor v2 + Prompt Playground MVP implementation plan 的 Task 3，把 `ExecutionRunPolicy` 传入 AgentExecutor，并按 Playground MCP 开关控制 Agent MCP tool call。
- **详情**：[docs/Task-detail/2026-05-28-phase-3-task-3-agent-mcp-run-policy.md](Task-detail/2026-05-28-phase-3-task-3-agent-mcp-run-policy.md)
- **结果**：完成。Playground 禁用 MCP 时，AgentExecutor 在 allowlist / 参数校验后、预算记录前拒绝 MCP tool call，不触发 Agent 内部 PermissionBroker 或 MCP client；Playground 显式允许 MCP 时继续以非 dry-run one-time gate 调用 PermissionBroker。focused AgentExecutor / ExecutionEngine tests 通过。

---

## Task 68 · Phase 3 Task 2 Playground Output Dispatcher

- **时间**：2026-05-28
- **描述**：执行 Phase 3 ToolEditor v2 + Prompt Playground MVP implementation plan 的 Task 2，新增 Settings Playground 专用 OutputDispatcher，收集 preview 输出快照并确保试跑不触发生产 UI、文件写入、选区替换、剪贴板或气泡副作用。
- **详情**：[docs/Task-detail/2026-05-28-phase-3-task-2-playground-output-dispatcher.md](Task-detail/2026-05-28-phase-3-task-2-playground-output-dispatcher.md)
- **结果**：完成。已新增 `PlaygroundOutputDispatcher` 与 `PlaygroundOutputSnapshot`，Playground preview 只记录 begin / chunk / finish / fail 状态，不持有生产输出 sink；focused output tests 通过。

---

## Task 67 · Phase 3 Task 1 Run Policy And Telemetry Foundation

- **时间**：2026-05-28
- **描述**：执行 Phase 3 ToolEditor v2 + Prompt Playground MVP implementation plan 的 Task 1，为 Playground 试跑新增 run policy、telemetry source 标记、CostAccounting 轻量迁移，并把策略传递到 ExecutionEngine report / cost / dry-run outcome。
- **详情**：[docs/Task-detail/2026-05-28-phase-3-task-1-run-policy-telemetry-foundation.md](Task-detail/2026-05-28-phase-3-task-1-run-policy-telemetry-foundation.md)
- **结果**：完成。已新增 `ExecutionRunPolicy`、`TriggerSource.playground`、`ExecutionSeed.runPolicy` / `effectiveRunPolicy`，InvocationReport / CostRecord 可标记 Playground source，CostAccounting 会幂等迁移旧 sqlite source 列；ExecutionEngine 现在用 run policy 决定权限 dry-run、副作用 dry-run、report flags、cost source 和 dry-run outcome。验证通过 Task 1 focused tests 与 `git diff --check`。

---

## Task 66 · Phase 3 ToolEditor v2 + Prompt Playground MVP Plan

- **时间**：2026-05-28
- **描述**：使用 `superpowers:writing-plans` 将已 review 的 Phase 3 ToolEditor v2 + Prompt Playground MVP spec 转换为可执行 implementation plan。
- **详情**：[docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md](Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-plan.md)
- **结果**：完成。已创建 plan `docs/superpowers/plans/2026-05-28-phase-3-tool-editor-playground-mvp.md`，按 TDD 拆分 run policy / telemetry、Playground output dispatcher、Agent MCP policy、ToolEditor draft state、Playground reducer / UI、AppContainer wiring、文档与 final gate；Claude review loop Round 3 已 approve（`findings: []`）；等待用户选择执行方式。

---

## Task 65 · Phase 3 ToolEditor v2 + Prompt Playground MVP Spec

- **时间**：2026-05-28
- **描述**：启动 Phase 3 首个可实施切片的规格收敛，冻结 ToolEditor v2 + Prompt Playground MVP，明确未保存草稿试跑、Prompt / Agent Tool 覆盖、真实 LLM、权限闭环下真实 MCP、side effects dry-run、右侧预览和后续技术债务。
- **详情**：[docs/Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-spec.md](Task-detail/2026-05-28-phase-3-tool-editor-playground-mvp-spec.md)
- **结果**：Codex review 后条件通过。已创建并修订 spec `docs/superpowers/specs/2026-05-28-phase-3-tool-editor-playground-mvp.md`：补齐 Phase 3 分支口径、Playground telemetry 兼容、MCP 显式确认安全边界、ToolEditor draft 校验 / reload 策略和相关测试要求；本任务不包含代码实现和 release。

---

## Task 64 · Phase 3 Handoff And Remote Sync

- **时间**：2026-05-27
- **描述**：用户选择跳过 Phase 2 release，后续在另一台机器的 Codex 继续 Phase 3；本任务负责推送最新分支并生成可复制的新会话接续提示词。
- **详情**：[docs/Task-detail/2026-05-27-phase-3-handoff-remote-sync.md](Task-detail/2026-05-27-phase-3-handoff-remote-sync.md)
- **结果**：完成。已新增跨机器 handoff 文档 `docs/handoffs/2026-05-27-phase-3-prompt-ide-local-models.md`，并将 README、AGENTS、CLAUDE 和 master todolist 更新到“跳过 Phase 2 release，进入 Phase 3 kickoff”口径；初始 handoff 曾推送到 `origin/codex/phase2-completion`，2026-05-28 已将 Phase 2 completion 合回 `main`，并把 Phase 3 workstream 迁移到 `origin/codex/phase3-tool-editor-playground`。

---

## Task 63 · Phase 2 Completion

- **时间**：2026-05-26
- **描述**：按“严格 Roadmap”范围完成 Phase 2 剩余内容：Output lifecycle、多 DisplayMode、side effects 实执行、TTS 和首方 English Tutor。
- **详情**：[docs/Task-detail/2026-05-26-phase-2-completion.md](Task-detail/2026-05-26-phase-2-completion.md)
- **结果**：完成。已完成 Output lifecycle foundation、SideEffect executor、`.silent` / `.file` / `.replace` / `.bubble` / `.structured` DisplayMode、本地 TTS capability 和 English Tutor 默认工具：prompt / agent 路径会传递 output lifecycle 和 final text；`copyToClipboard`、`appendToFile`、`notify`、`callMCP`、`tts` 已有执行边界并接入生产 `ExecutionEngine`；`.silent` 不再落窗，`.file` 在 finish 阶段写入 appendToFile 目标且避免重复执行同一文件写入；`.replace` 在 finish 阶段通过 AX 替换选区，失败时复制到剪贴板并通知；`.bubble` 在 finish 后展示自动消失气泡；`.structured` 把顶层 JSON object 渲染为结构化字段视图；TTS 使用 macOS AVFoundation 朗读 final text，dry-run 不发声，并在 structured JSON 包含 `ttsText` 时优先朗读该字段；默认配置 schema v4 新增 `english-tutor`，并由内置首方 skill 支撑绑定。真实 App smoke 覆盖六种输出路径；final gate 中修复了一个取消测试夹具调度竞态（生产逻辑未改）。最终 automated gate、公开仓库 smoke 和真实 App smoke 均已通过。

---

## Task 62 · Phase 2 Skill Supporting Files Read-Only Loading

- **时间**：2026-05-26
- **描述**：继续 Phase 2，设计并实现 skill supporting files 只读加载。目标是在已绑定 skill 的渐进式加载链路中，安全读取 `references/` 与文本型 `assets/`，同时继续禁止执行 `scripts/`。
- **详情**：[docs/Task-detail/2026-05-26-phase-2-skill-supporting-files-readonly.md](Task-detail/2026-05-26-phase-2-skill-supporting-files-readonly.md)
- **结果**：完成。已新增 `SkillResourcePayload` 与 `SkillRegistryProtocol.loadSkillResource(id:relativePath:)`，`LocalSkillRegistry` 现在索引并只读加载 enabled skill 内的 `references/` 与文本型 `assets/`；AgentExecutor 新增 provider-visible `sliceai_load_skill_resource` pseudo-tool，要求先加载同名 bound skill 后才能读取资源。安全边界继续拒绝 `scripts/`、未索引路径、绝对路径、`..`、symlink 越界、非 UTF-8 和超过 64 KiB 的单文件。验证通过 focused tests、公开仓库 smoke（3 repositories / 9 public skills）、全量 SwiftPM 803 tests（1 skipped）、SwiftLint strict、`git diff --check` 和 App Debug build。

---

## Task 61 · Phase 2 Public Skill Repository Compatibility

- **时间**：2026-05-24
- **描述**：继续 Phase 2，按“自动化 smoke + 文档证据 + 必要代码修复”的方式验证公开 Anthropic / Codex skill 仓库兼容性。固定 3 个公开仓库 commit，拉取真实 `SKILL.md` 样本，使用生产 `LocalSkillRegistry` 验证扫描、解析、启用和按需加载。
- **详情**：[docs/Task-detail/2026-05-24-phase-2-public-skill-repository-compatibility.md](Task-detail/2026-05-24-phase-2-public-skill-repository-compatibility.md)
- **结果**：完成。已新增有界 collection 布局兼容：`SkillDirectoryScanner` 现在支持公开 OpenAI 仓库常见的 `skills/.curated/<skill>/SKILL.md` 和 `skills/.system/<skill>/SKILL.md`，同时继续避免任意递归。已新增 opt-in `PublicSkillRepositorySmokeTests` 和 `scripts/phase2-public-skill-smoke.sh`，默认测试不联网，脚本固定拉取 `anthropics/skills@690f15c`、`openai/skills@b0401f0`、`jMerta/codex-skills@1be063d` 并验证 9 个公开 skill 可扫描、启用和加载 `SKILL.md`。验证通过 scanner 红绿测试、public smoke、全量 SwiftPM 798 tests（1 skipped）、SwiftLint strict 和 `git diff --check`。

---

## Task 60 · Phase 2 Skill E2E Validation

- **时间**：2026-05-24
- **描述**：继续 Phase 2，执行真实 Skill E2E 兼容性验证：用 3 个本地 Claude / Codex 风格 skill 验证文件系统扫描、`SKILL.md` 解析、Settings override、Agent Tool 绑定和 `sliceai_load_skill` 渐进式加载链路。
- **详情**：[docs/Task-detail/2026-05-24-phase-2-skill-e2e-validation.md](Task-detail/2026-05-24-phase-2-skill-e2e-validation.md)
- **结果**：完成。已新增真实文件系统 E2E 自动化测试，覆盖 3 个 Claude / Codex 风格 skill 从 `LocalSkillRegistry` 到 AgentExecutor `sliceai_load_skill` 的贯通链路；验证 `allowed-tools`、`disable-model-invocation`、`user-invocable` 兼容字段、metadata 暴露、按需加载真实 `SKILL.md`、supporting files 不进入模型 payload，以及 pseudo-tool 不触发 MCP。full gate 首次暴露既有取消测试调度竞态，已通过专用可取消 dispatcher 测试夹具收紧。验证通过 focused E2E、focused cancellation regression、全量 SwiftPM 796 tests、SwiftLint strict 和 `git diff --check`。

---

## Task 59 · Project State And Agent Doc Audit

- **时间**：2026-05-24
- **描述**：基于当前源码、README、master todolist、Phase 2 Skill Registry spec / plan 和模块文档，盘点 SliceAI 实际项目状态，新增项目级 `AGENTS.md`，并整理已完成功能、当前阶段、后续任务以及代码实现与 spec / 文档之间的偏差。
- **详情**：[docs/Task-detail/2026-05-24-project-state-agent-doc-audit.md](Task-detail/2026-05-24-project-state-agent-doc-audit.md)
- **结果**：完成。已新增项目级 `AGENTS.md`，明确当前 Swift/macOS 项目事实、必读顺序、模块边界、常用命令、配置路径、开发约束、已落地功能和未完成能力。审计确认 Phase 2 Skill Registry MVP 已在代码层落地；已在 master todolist 补齐从当前到 v1.0 的 60 项剩余主任务，并修复 Phase 0 / Phase 1 / Phase 2 状态口径。已修复主要偏差：`config.schema.json` 从旧 schemaVersion 1 更新到当前 schemaVersion 3 / v2 Tool / SkillSettings 模型；`CLAUDE.md` 更新到 Phase 2 Skill Registry MVP 状态；`README.md`、`docs/Module/SliceCore.md`、`docs/Module/Orchestration.md` 已同步 AgentExecutor、Skills 页面和未完成 DisplayMode / Pipeline 边界。验证：`jq empty config.schema.json`、`git diff --check`、`swift test --package-path SliceAIKit`（795 tests）和 `swiftlint lint --strict` 均通过。

---

## Task 58 · Phase 2 Skill Registry MVP Spec Kickoff

- **时间**：2026-05-20
- **描述**：在 `v0.3.0` draft release 已生成但用户决定暂缓人工发布后，启动并实现 Phase 2 的第一个设计切片：Skill Registry MVP。
- **详情**：[docs/Task-detail/2026-05-20-phase-2-skill-registry-mvp-spec.md](Task-detail/2026-05-20-phase-2-skill-registry-mvp-spec.md)
- **结果**：完成。已完成 `superpowers:brainstorming` 范围收敛、正式 spec、implementation plan、Claude review loop approve 和 Subagent-Driven 实施。MVP 采用自研最小 loader：用户配置多个 skill roots，Agent Tool 通过加号逐条绑定最多 5 个 enabled skills，每行以下拉菜单选择并可用减号删除；执行时先暴露元数据，模型通过内置 pseudo-tool `sliceai.load_skill` 渐进式加载完整 `SKILL.md`。Prompt Tool、supporting files 读取、脚本执行、marketplace、DisplayMode 和 English Tutor 不进入本 MVP。验证通过全量 SwiftPM 795 tests、SwiftLint strict、App Debug build 和 `git diff --check`；用户已完成 App 手测且未反馈问题。已提交 `1411e88 feat: add skill registry mvp` 并推送到 `origin/main`。

---

## Task 57 · v0.3 Release Prep

- **时间**：2026-05-19
- **描述**：Phase 1 MCP + Context 主干合并到 `main` 后，执行 `v0.3` 发布前最终 gate、Claude review loop、release notes 与 tag checklist 准备。
- **详情**：[docs/Task-detail/2026-05-19-v0.3-release-prep.md](Task-detail/2026-05-19-v0.3-release-prep.md)
- **结果**：完成。Phase 1 相关 feature/docs worktree 已合并或清理，保留 `archive/pre-phase1-local-appcontainer-snapshot` 作为不参与发布的旧 AppContainer 本机快照。Claude review loop Round 1 找到并修复 2 个发布阻塞：长 MCP tool result 不再以 `<truncated:N>` 回填给 LLM，stdio MCP server 在 command / args / env 变化后会重启旧 session；Round 2 approve，`findings: []`。验证通过 focused tests、全量 SwiftPM 758 tests、SwiftLint strict、whitespace check、App Debug build、本地 unsigned DMG 构建和 DMG 挂载结构校验。2026-05-20 首次 GitHub Actions Release run `26167656542` 在 Xcode 16.4 Release archive 阶段暴露 Swift 6 `Sendable` 约束缺口；已补齐 `StreamableHTTPMCPClient.retryingExpiredSession<Result: Sendable>` 并通过相关 focused tests、SwiftLint strict 和本地 `scripts/build-dmg.sh 0.3.0`。第二次 Release run `26168050987` 已成功生成 `v0.3.0` draft release，CI DMG SHA256 为 `cf63e4e50b8eeda63e38f04c85ff485d11cdfa939038d7555b72ae61ad96f0e0`，下载后本地校验一致。用户已决定暂缓人工发布，后续开发转入 Phase 2 Skill Registry MVP 规格设计。

---

## Task 56 · Phase 1 Agent Tool Config And MCP Policy

- **时间**：2026-05-19
- **描述**：修正 Phase 1 文档口径，并补齐 v0.3 产品闭环中缺失的基础自定义 Agent Tool 配置、MCP allowlist 编辑和通用 MCP tool-call policy。
- **详情**：[docs/Task-detail/2026-05-19-phase-1-agent-tool-config-policy.md](Task-detail/2026-05-19-phase-1-agent-tool-config-policy.md)
- **结果**：完成。已确认 Skill 属于 Phase 2，不作为当前 v0.3 blocker；新增基础 Agent Tool 编辑入口、`server.tool` 文本 MCP allowlist、policy UI、`AgentToolCallPolicy` 和执行器通用 MCP 调用策略。`maxSteps` 现在只表示 LLM ReAct 轮数；MCP 调用总量、单轮量、单工具量、重复参数和 rate limit 停止由 policy 控制。验证通过 focused tests、全量 SwiftPM 756 tests、SwiftLint strict、`git diff --check` 和 App Debug build；Debug App 已重启，进程 `13394`。

---

## Task 55 · Phase 1 Task 17 · Release E2E Validation

- **时间**：2026-05-10
- **描述**：启动 Phase 1 真实 release E2E 验证任务，补齐 filesystem / postgres / brave-search / git / sqlite 五类 MCP server 的 `tools/list` 与安全只读 tool call 证据，并回归 Safari / Notes / Slack 的 `web-search-summarize`、权限确认、ResultPanel lifecycle 和热键路径。
- **详情**：[docs/Task-detail/2026-05-10-phase-1-release-e2e-validation.md](Task-detail/2026-05-10-phase-1-release-e2e-validation.md)
- **结果**：主体验证完成。已创建任务文档并明确环境前置条件、测试计划、证据记录模板和 secret 脱敏边界；已完成只读 worktree 核对和 `bash scripts/phase1-mcp-e2e.sh` 检查；README、master todolist 和 Phase 1 plan 已同步到 Task 17 当前状态。2026-05-19 已搭建 filesystem / postgres / brave-search / git / sqlite 五项本地 MCP 环境，写入 SliceAI `mcp.json`，并通过直接 MCP JSON-RPC 完成五项 `tools/list` 与安全只读 / 低风险 `tools/call`。已补丁本机 `config-v2.json` 使 `web-search-summarize` 可见，并修复 DeepSeek V4 thinking mode tool-call follow-up 丢失 `reasoning_content`、Brave 搜索 MCP 授权按钮不可用、Agent 连续工具调用后无最终回答、最终回合 DSML 工具调用标记误作为正文输出，以及单次运行中过量顺序 Brave 搜索触发限流等 App 实测缺陷；验证通过 focused tests、全量 SwiftPM 749 tests、全量 SwiftLint strict、`git diff --check` 和 App Debug build。用户已基本复测 Safari / Notes / Slack `web-search-summarize`、权限、ResultPanel 和热键 App 回归且未反馈阻塞问题；进入 `v0.3` 发布前仍需最终 release gate / review loop。

---

## Task 54 · Phase 1 M4 Task 16 · Five MCP Server E2E And Release Documentation

- **时间**：2026-05-09
- **描述**：启动 Phase 1 收口任务，运行 M4 release readiness gate，记录 5 个 MCP server E2E 和 App 场景回归证据，补齐 MCPClient / ContextProviders 模块文档，并更新项目状态文档。
- **详情**：[docs/Task-detail/2026-05-09-phase-1-m4-task-16-five-server-e2e-release-readiness.md](Task-detail/2026-05-09-phase-1-m4-task-16-five-server-e2e-release-readiness.md)
- **结果**：完成。已完成 release lint blocker 修复、自动化 gate、E2E checklist 脚本和模块文档；真实 5-server MCP E2E / Safari-Notes-Slack 回归缺本机配置和测试数据源，已记录为 release 环境 blocker。Claude review loop Round 1 接受并修复脚本配置摘要泄漏 `args/url` 原值风险；Round 2 approve，`findings: []`。验证通过：`swift build`、735 tests with coverage、App Debug build、full strict lint、E2E checklist 脚本和敏感 fixture redaction check。

---

## Task 53 · Phase 1 M4 Task 15 · Per-Tool Hotkeys

- **时间**：2026-05-09
- **描述**：启动 M4 第二项任务，为单个工具增加全局热键配置、冲突校验、Settings UI 保存路径和 AppDelegate 直接执行路由。
- **详情**：[docs/Task-detail/2026-05-09-phase-1-m4-task-15-per-tool-hotkeys.md](Task-detail/2026-05-09-phase-1-m4-task-15-per-tool-hotkeys.md)
- **结果**：完成。已按 TDD 新增 per-tool hotkey 配置兼容、冲突检测、旧 `Tool.hotkey` fallback 冲突过滤和 tool id 注册 helper 测试；实现 `HotkeyBindings.tools`、`HotkeyBindingValidator`、`ToolHotkeyRegistration`、工具编辑器热键录制、命令面板/工具冲突提示、删除带热键工具后立即重载注册，以及 `AppDelegate` 多热键注册和工具热键直达执行。Claude review loop Round 1 接受并修复删除工具热键未重载、UI/runtime fallback 校验不一致两条 finding；Round 2 approve，`findings: []`。验证通过：focused tests、SettingsUITests、全量 SwiftPM 735、targeted lint、`git diff --check`、App Debug build。全仓 strict lint 仍被 13 个既有历史违规阻塞。

---

## Task 52 · Phase 1 M4 Task 14 · Streamable HTTP Transport

- **时间**：2026-05-09
- **描述**：启动 M4 第一项任务，为 MCP client 补齐 Streamable HTTP transport，使 `.streamableHTTP` descriptor 可通过 `RoutingMCPClient` 路由到真实 HTTP transport，同时继续拒绝 deprecated `.sse`。
- **详情**：[docs/Task-detail/2026-05-09-phase-1-m3-task-14-streamable-http-transport.md](Task-detail/2026-05-09-phase-1-m3-task-14-streamable-http-transport.md)
- **结果**：完成。已按 TDD 新增 `StreamableHTTPMCPClient`，支持 initialize、session id、2025-06-18 protocol header、JSON 与 SSE response；`RoutingMCPClient` 和 `AppContainer` 已接入 `.streamableHTTP`，`.sse` / `.websocket` 继续 fail-fast；`MCPServerValidation` 已允许 HTTPS 远程和 localhost 明文 HTTP，拒绝缺 URL、缺 host 与非本机明文 HTTP。Claude review Round 1 接受并修复 redirect 泄露风险和 404 session 过期后未重建；Round 2 approve，`findings: []`。验证通过：focused tests、CapabilitiesTests 92、全量 SwiftPM 728、targeted lint、`git diff --check`、App Debug build。全仓 strict lint 仍被 13 个既有历史违规阻塞。

---

## Task 51 · Phase 1 M3 Task 13 · Built-In web-search-summarize Agent Tool

- **时间**：2026-05-08
- **描述**：启动 M3 第四项任务，在默认配置中新增首方 `web-search-summarize` Agent 工具，使用 Brave Search MCP 搜索并总结选中内容，同时声明 tool-calling provider 能力需求和 MCP 权限。
- **详情**：[docs/Task-detail/2026-05-08-phase-1-m3-task-13-web-search-summarize-agent-tool.md](Task-detail/2026-05-08-phase-1-m3-task-13-web-search-summarize-agent-tool.md)
- **结果**：完成。已新增 `web-search-summarize` 首方 Agent tool，声明 selection context、tool-calling provider capability、Brave Search MCP allowlist 和 MCP 权限；`DefaultProviderResolver` 已实现 `.capability` 路由；旧 4 个 prompt tools 保持不变。验证通过：ConfigurationTests、ConfigurationStoreTests、ToolTests、ProviderResolverTests、ExecutionEngineTests、全量 SwiftPM 712、targeted lint、`git diff --check`、App Debug build。全仓 strict lint 仍被 13 个既有历史违规阻塞。Claude review loop Round 1 approve，`findings: []`。

---

## Task 50 · Phase 1 M3 Task 12 · ResultPanel Tool Call Lifecycle

- **时间**：2026-05-08
- **描述**：启动 M3 第三项任务，把 Task 11 的 AgentExecutor tool-call lifecycle events 显示到 ResultPanel，让用户看到 MCP tool call 的 proposed、approved、result、denied 和 error 状态。
- **详情**：[docs/Task-detail/2026-05-08-phase-1-m3-task-12-resultpanel-tool-call-lifecycle.md](Task-detail/2026-05-08-phase-1-m3-task-12-resultpanel-tool-call-lifecycle.md)
- **结果**：完成。已新增 Windowing 纯状态模型和 ResultPanel lifecycle rows，`ExecutionEventConsumer` 已把 tool-call events 映射到 UI，同时保持 `.llmChunk` 仍由 OutputDispatcher 单一路径写入正文。验证通过：focused tests、WindowingTests、全量 SwiftPM 706、targeted lint、`git diff --check`、App Debug build。全仓 strict lint 仍被既有历史文件阻塞。Claude review loop Round 1 approve，`findings: []`，无需额外修复。

---

## Task 49 · Phase 1 M3 Task 11 · AgentExecutor ReAct Loop

- **时间**：2026-05-08
- **描述**：启动 M3 第二项任务，在 Task 10 的 LLM tool calling contract 基础上实现 AgentExecutor ReAct loop，把 `.agent` ToolKind 从 stub 路由到真实 MCP tool calling 执行链。
- **详情**：[docs/Task-detail/2026-05-08-phase-1-m3-task-11-agentexecutor-react-loop.md](Task-detail/2026-05-08-phase-1-m3-task-11-agentexecutor-react-loop.md)
- **结果**：完成。已实现 `AgentExecutor` ReAct loop、MCP allowlist catalog、PermissionBroker gate、MCP result 回填、ExecutionEngine `.agent` 路由和 AppContainer 生产接线。验证通过：AgentExecutorTests 19、OrchestrationTests 231、全量 SwiftPM 701、targeted lint、`git diff --check`、App Debug build。全仓库 strict lint 仍被既有历史文件阻塞。Claude review loop 两轮收敛：Round 1 修复 catalog 非 allowlist 同名冲突、重复 descriptor id trap、unsupported `.maxStepsReached` 静默生效；Round 2 approve，`findings: []`。

---

## Task 48 · Phase 1 M3 Task 10 · LLM Tool Calling Contract

- **时间**：2026-05-08
- **描述**：启动 M3 第一项任务，为 OpenAI-compatible tool calling 建立 SliceCore / LLMProviders 数据契约、流式解析和 provider API，给后续 AgentExecutor 提供稳定边界。
- **详情**：[docs/Task-detail/2026-05-08-phase-1-m3-task-10-llm-tool-calling-contract.md](Task-detail/2026-05-08-phase-1-m3-task-10-llm-tool-calling-contract.md)
- **结果**：完成。已同步 Phase 1 implementation plan 到当前 worktree；已按 TDD 完成 SliceCore tool calling contract、OpenAI-compatible DTO 解码、`streamToolChat(request:)` 和 SSE tool-call fixture；focused tests、LLMProviders 回归、PromptExecutor / ExecutionEngine 回归、全量 `swift test`、`git diff --check`、touched Swift files targeted lint 和 App Debug build 已通过。全仓库 `swiftlint lint --strict` 当前被 M1/M2 历史违规阻塞，Task 10 暂不扩大修复范围。Claude review Round 1 approve，`findings: []`。

---

## Task 47 · Phase 1 M2 Task 9 · AppContainer Context And Permission UI Wiring

- **时间**：2026-05-08
- **描述**：把 M2 Task 7/8 的真实 ContextProvider、MCP runtime client 和 UI-free permission consent boundary 接入 AppContainer，替换空 registry 与 fail-closed 临时 presenter。
- **详情**：[docs/Task-detail/2026-05-08-phase-1-m2-task-9-appcontainer-context-permission-ui.md](Task-detail/2026-05-08-phase-1-m2-task-9-appcontainer-context-permission-ui.md)
- **结果**：完成。未新增重复 Orchestration 行为测试，原因是现有 `ExecutionEngineTests` / `PermissionBrokerTests` / `ContextProviderTests` 已覆盖未声明权限、权限拒绝、批准继续执行和 provider 权限推导；本任务改用 focused tests 与 App Debug build 验证组合根 wiring。`AppContainer` 已注册真实 context providers，接入 AppKit permission presenter、persistent grant store 显式路径和 `mcp.json` 驱动的 routing MCP client。

---

## Task 46 · Phase 1 M2 Task 8 · Permission Consent Grants

- **时间**：2026-05-08
- **描述**：实现 UI-free 权限确认协议、PermissionBroker presenter 集成、session grant 缓存规则和 persistent permission grant 磁盘存储。
- **详情**：[docs/Task-detail/2026-05-08-phase-1-m2-task-8-permission-consent-grants.md](Task-detail/2026-05-08-phase-1-m2-task-8-permission-consent-grants.md)
- **结果**：完成。已按 TDD 补齐 broker / session store / persistent store 测试；`PermissionBroker` 通过 UI-free presenter 在生产路径内部解析确认决策；不可缓存权限在 session 与 persistent 存储层均 fail-closed；指定测试、全量 `swift test` 与 App Debug build 已通过。

---

## Task 45 · Phase 1 M2 Task 7 · Core Context Providers

- **时间**：2026-05-08
- **描述**：新增五个核心 ContextProvider：`selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read`，并接入 ContextCollector 与 PermissionGraph 的真实 provider 测试。
- **详情**：[docs/Task-detail/2026-05-08-phase-1-m2-task-7-core-context-providers.md](Task-detail/2026-05-08-phase-1-m2-task-7-core-context-providers.md)
- **结果**：完成。已按 TDD 先写失败测试并确认 provider 类型缺失红灯；实现剪贴板/文件 IO 取消检查和 `PathSandbox` 规范化读取；code review follow-up 已将 `file.read` 改为默认 1 MiB 上限的分块读取并补超限/取消回归；指定 ContextProvider、ContextCollector、PermissionGraph 测试与 `git diff --check` 已通过。

---

## Task 44 · Phase 1 M2 Task 6 · PermissionGraph Case-Aware Coverage

- **时间**：2026-05-07
- **描述**：将 `EffectivePermissions.undeclared` 从字面 `Set.subtracting` 升级为 case-aware coverage，支持文件路径 exact / directory prefix / glob 覆盖、PathSandbox hard-deny 拦截、MCP tools nil/superset 覆盖，以及 shellExec 精确命令列表。
- **详情**：[docs/Task-detail/2026-05-07-phase-1-m2-task-6-permissiongraph-case-aware-coverage.md](Task-detail/2026-05-07-phase-1-m2-task-6-permissiongraph-case-aware-coverage.md)
- **结果**：完成。已按 TDD 先写失败测试并确认红灯；实现 case-aware coverage 与 `PathSandbox.isHardDenied(_:)`；目标测试、ExecutionEngine 回归、PathSandbox 回归和 `git diff --check` 已通过。

---

## Task 43 · Phase 1 M1 Task 5 · MCP Servers Settings Page

- **时间**：2026-05-07
- **描述**：为 SettingsUI 增加 MCP Servers 设置页，提供本地 `mcp.json` 的 server 列表、Claude Desktop JSON 导入、stdio server 新增/编辑/删除，以及调用 MCP client 的 tools/list 测试连接预览。
- **详情**：[docs/Task-detail/2026-05-07-phase-1-m1-task-5-mcp-servers-settings-page.md](Task-detail/2026-05-07-phase-1-m1-task-5-mcp-servers-settings-page.md)
- **结果**：完成。已按 TDD 先写失败测试并确认红灯；两轮 code quality review 的状态一致性 / stale preview 问题均已修复并获 `APPROVED`；`claude-review-loop` 发现的新增重复 id 静默覆盖问题已修复；目标测试、相关 SliceCore / Capabilities 回归、`swift build`、全量 `swift test`（639 tests）与 `git diff --check` 均通过。

---

## Task 42 · Phase 1 M1 Task 4 · Stdio MCP JSON-RPC Client

- **时间**：2026-05-07
- **描述**：实现 M1 stdio MCP JSON-RPC client：JSON-RPC framing、lazy start、initialize、tools/list、tools/call、idle timeout、stderr diagnostic redaction，以及 RoutingMCPClient 的 stdio/远程 transport 路由边界。
- **详情**：[docs/Task-detail/2026-05-07-phase-1-m1-task-4-stdio-mcp-json-rpc-client.md](Task-detail/2026-05-07-phase-1-m1-task-4-stdio-mcp-json-rpc-client.md)
- **结果**：完成。Spec compliance review 与 code quality review 均已通过；目标测试、`CapabilitiesTests`、全量 `swift test` 与 `git diff --check` 已通过，已提交 commit。

---

## Task 41 · Phase 1 M1 Task 3 · MCP Server Store And Claude Desktop Import

- **时间**：2026-05-07
- **描述**：新增 MCP server 本地配置 store、fail-closed 校验和 Claude Desktop stdio 配置导入能力；M1 仅允许本地 stdio，远程 transport 留到 M4。
- **详情**：[docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md](Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md)
- **结果**：完成。目标测试、`CapabilitiesTests`、全量 `swift test` 与 `git diff --check` 已通过，已提交 commit。

---

## Task 40 · Phase 1 M1 Task 2 · MCP Client Protocol Uses Canonical Descriptor

- **时间**：2026-05-07
- **描述**：将 Capabilities 的 `MCPClientProtocol` 收敛到 SliceCore canonical `MCPDescriptor` / `MCPToolDescriptor` / `MCPJSONValue.Object`，删除重复 descriptor，并增强 `MockMCPClient` 的结构化参数记录与错误脱敏测试。
- **详情**：[docs/Task-detail/2026-05-07-phase-1-m1-task-2-mcp-client-protocol-canonical-descriptor.md](Task-detail/2026-05-07-phase-1-m1-task-2-mcp-client-protocol-canonical-descriptor.md)
- **结果**：完成。目标测试、全量 `swift test` 与 `git diff --check` 已通过，已提交 commit。

---

## Task 39 · Phase 1 M1 Task 1 · SliceCore MCP JSON Contract

- **时间**：2026-05-06
- **描述**：为 Phase 1 MCP 上下文能力建立 SliceCore 的 JSON/value contract：任意 JSON 参数、MCP content/result、tool descriptor、transport enum，并把 `callMCP` / `PipelineStep.mcp` 参数从字符串字典升级为结构化 JSON 对象。
- **详情**：[docs/Task-detail/2026-05-06-phase-1-m1-task-1-mcp-json-contract.md](Task-detail/2026-05-06-phase-1-m1-task-1-mcp-json-contract.md)
- **结果**：完成。SliceCore MCP JSON/value contract 已落地，指定测试和 `SliceCoreTests` 均通过，已提交 commit。

---

## Task 38 · Phase 1 MCP + Context 主干设计与计划准备

- **时间**：2026-05-06
- **描述**：按 `superpowers:brainstorming` 流程复核 Phase 1 MCP + Context 主干设计，明确采用"主干先行 + M1-M4 里程碑验收"方案，并在写 implementation plan 前产出独立 design spec。
- **详情**：[docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md](Task-detail/2026-05-06-phase-1-mcp-context-planning.md)
- **结果**：进行中。Phase 1 总范围已确认覆盖完整 v0.3 DoD；design spec 已通过 Claude review loop（3 rounds，最终 `approve`）；implementation plan 已完成 Claude review loop（8 rounds，19 条 finding 全部接受并修复，最终 `approve`）。下一步可按 plan 选择 subagent-driven 或 inline execution 进入实现。

---

## Task 37 · Phase 1 前收尾

- **时间**：2026-05-05
- **描述**：进入 Phase 1 前收敛本地状态：归档旧 `AppContainer.swift` 本地中间态、归档 M3 review loop / handoff 历史草稿、同步根工作区到最新 `origin/main`，并更新 master todolist 的下一步为 Phase 1 planning。
- **详情**：[docs/Task-detail/2026-05-05-pre-phase1-closeout.md](Task-detail/2026-05-05-pre-phase1-closeout.md)
- **结果**：完成。本地未提交内容已保存到归档分支；根工作区 `main` 已同步到 PR #4 后的最新远端；下一步是 Phase 1 brainstorming + plan 起草。

---

## Task 36 · Phase 0 M3 · Switch to V2 implementation

- **时间**：2026-04-28 – 2026-05-04
- **描述**：按 `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md` 执行 M3 implementation：V2 类型族接入真实启动路径、删除 v1 冲突类型族、完成 rename pass、13 项手工回归与 v0.2.0 unsigned DMG release。
- **详情**：[mini-spec 归档](Task-detail/2026-04-28-phase-0-m3-mini-spec.md) + [implementation 归档](Task-detail/2026-04-28-phase-0-m3-implementation.md)
- **结果**：完成。M3.0–M3.5 已通过自动化 / 手工回归；M3.6 本地 release preflight 已完成；PR #3 已 merge；`v0.2.0` tag 与 GitHub Release 已正式发布（2026-05-04 21:19 CST）。Release DMG SHA256：`2d7749a1405e1ec4051b90b8b3ee5e029f5819e18a2cf69eda074f2de5b98aea`。

---

## Task 35 · Phase 0 M3 · plan/spec 口径对齐修复

- **时间**：2026-04-29
- **描述**：根据 M3 mini-spec 与 implementation plan 的 fresh review 差异，修复两份文档的口径不一致：M3.5 手工回归统一为 13 项；release tag 统一为 SemVer `v0.2.0`；M3.1 C+D 明确为原子实现 / 提交单元；plan 中早期 commit 前补齐 4 关 CI gate；手工回归命令改为不依赖固定 `/tmp/SliceAI-backup` 且保留恢复路径；2026-04-30 追加同步 Accessibility 回归语义、清理 ToolEditorView 展示模式步骤的历史矛盾指令，并统一 D-28 / SelectionReader 真实代码口径。
- **详情**：[docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md](Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md)
- **结果**：完成

---

## Task 34 · Phase 0 M2 · Orchestration + Capabilities 骨架

- **时间**：2026-04-25
- **描述**：把 v2.0 spec §3.4 / §3.9 描述的执行引擎 + 权限闭环 + 安全模型骨架落地为 `Orchestration` + `Capabilities` 两个 target 的可独立单测代码；**不接入 app 启动链路**（M3 才切）。10 个 spec 子任务（M2.1 ExecutionEngine / M2.2 ContextCollector / M2.3 PermissionBroker / M2.3a PermissionGraph / M2.4 CostAccounting / M2.5 AuditLog / M2.6 OutputDispatcher / M2.7 PromptExecutor / M2.8 PathSandbox / M2.9 MCP/Skill 接口）拆为 14 个 implementation Task；plan 经 13 轮 Codex review-fix loop 完成（plan HEAD `5cfac70`）
- **详情**：[docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md](Task-detail/2026-04-25-phase-0-m2-orchestration.md)
- **结果**：实施中

---

## Task 33 · Phase 0 M1 · 核心类型与配置迁移

- **时间**：2026-04-24
- **描述**：落地 v2.0 spec §3.3 / §3.7 / §3.9 定义的领域模型——**以独立 V2* 类型** 新建（V2Tool / V2Provider / V2Configuration / V2ConfigurationStore），不改动现有 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `DefaultConfiguration`；新建 Orchestration / Capabilities 空 target；ConfigMigratorV1ToV2 纯函数 migrator 产出 V2Configuration
- **详情**：[docs/Task-detail/2026-04-24-phase-0-m1-core-types.md](Task-detail/2026-04-24-phase-0-m1-core-types.md)
- **结果**：20 个 sub-task 全部完成（35 commit，26 个新源文件 + 22 个新测试文件 + 2 个 fixture JSON）；`swift build` / `swift test --parallel --enable-code-coverage`（320/320 pass）/ `xcodebuild ... SliceAI`（BUILD SUCCEEDED）/ `swiftlint lint --strict`（0/0 in 106 files）全绿；v1 `Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` / `SelectionPayload` / `ToolExecutor.swift` / `AppContainer.swift` 字节不变（`git diff main..HEAD` 为空）；V2 canonical JSON schema 由 golden 测试锁定（10 个手写 Codable enum + 单键闸门 + `_0` 禁入）；两处 plan 内部冲突就地修订（`DisplayMode → PresentationMode` 避开 Tool.swift 冲突；Task 17/18 顺序互换解决依赖倒置）。分支 `feature/phase-0-m1-core-types`，HEAD `<本次 commit>`；未 push，等待用户审阅后决定 PR

---

## Task 32 · 基于 Codex 第七轮评审（CONDITIONAL_APPROVE）收尾 M1 Plan

- **时间**：2026-04-23
- **描述**：针对 Codex 第七轮 `CONDITIONAL_APPROVE`（79/100）的 1 条 P1 + 2 条 P2 全部接受并落地。(P1) golden JSON 测试从顶部模板引用落实为 **Task 3/8/10/11/13/14 测试代码块里的具体断言**：PermissionTests 加 `test_permission_goldenJSON_fileRead_usesSingleKeyWithStringValue` 等 5 个 + ProvenanceTests 2 个；ContextRequestTests 加 CachePolicy 2 个；OutputBindingTests 加 SideEffect 4 个；ProviderSelectionTests 加 ProviderSelection / ConditionExpr 4 个（含 `"requires":["promptCaching","toolCalling","vision"]` 按 rawValue 字母序断言）；MCPDescriptorTests 加 MCPCapability 2 个；ToolKindTests 加 ToolKind / PipelineStep / TransformOp 6 个——**所有 golden 都断言 `.hasPrefix` single-key discriminator + `XCTAssertFalse(json.contains("_0"))`**。(P2-1) V2Provider 手写 `init(from:)`：即使用户手改 `config-v2.json` 带重复 / 乱序 capabilities，decoder 也做 `Array(Set(raw)).sorted { $0.rawValue < $1.rawValue }` 归一化；`encode(to:)` 仍走自动合成（因 self 已规范化）。(P2-2) 三处残留文案清理：Architecture 顶部的 `ContextValue` 从 golden 锁定清单移除 + 明确标注"不 Codable"；Task 4 文件清单"Modify SelectionPayloadTests.swift"改为"Keep（零改动）"；Task 20 归档列表里的 "ContextValue" 从 golden 清单替换为正确的 10 个 enum
- **详情**：直接修订 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（Architecture 顶部 / Task 3 / Task 4 文件清单 / Task 8 / Task 10 / Task 11 / Task 12 V2Provider / Task 13 / Task 14 / Task 20 归档清单）
- **结果**：plan 第七轮修订完成；Codex `CONDITIONAL_APPROVE` 三条收尾全部落地；下一步可正式进入实施

---

## Task 31 · 基于 Codex 第六轮评审修订 M1 Plan（手写 Codable 实际落地 + internal 访问控制修复）

- **时间**：2026-04-23
- **描述**：针对 Codex 第六轮 `REWORK_REQUIRED`（2 条 P1 + 4 条 P2）全部接受并落地。(P1-1) 手写 Codable 真正落地：plan 顶部新增 **"Canonical JSON Schema：手写 Codable 模板"独立章节**，定义模板 A（single-key discriminator + empty marker）、模板 B（多 associated value 用 nested Repr struct）、模板 C（单值简化）、模板 D（golden JSON 测试）；对 10 个关键 enum（`Permission` / `Provenance` / `CachePolicy` / `SideEffect` / `ProviderSelection` / `ConditionExpr` / `MCPCapability` / `ToolKind` / `PipelineStep` / `TransformOp`）全部补齐 `init(from:) / encode(to:)` + CodingKeys + private Repr struct，产出形如 `{"prompt":{...}}` / `{"clipboard":{}}` / `{"mcp":{"server":"x","tools":[...]}}` 的可读 JSON，保证 golden test 里 `XCTAssertFalse(json.contains("_0"))` 能真实通过；`ContextValue` 明确不 Codable（与 Task 7 一致），从 golden 清单排除。(P1-2) `LegacyConfigV1` 访问控制修复：把 `ConfigMigratorV1ToV2` 和 `migrate(_:)` 从 `public` 改为 `internal`，避免 "public API uses internal type" 编译错误；V2ConfigurationStore 的 private method 调 internal Migrator 合法。(P2-1) Task 4 标题 / 文件清单里残留的 "重命名 + typealias" 措辞彻底清理。(P2-2) Self-Review 里 ContextValue golden 矛盾消除。(P2-3) `V2Provider.capabilities` 从 `Set<ProviderCapability>` 改为 `[ProviderCapability]`，`init` 接受 `some Sequence<ProviderCapability>` 并自动去重 + 按 rawValue 排序，保证 JSON 数组顺序稳定；`ProviderSelection.capability` 手写 Codable 的 encoder 对 `Set<ProviderCapability>` 同样先排序再编码。(P2-4) 在 plan 顶部明确列出 M3 rename pass 的 7 项主任务（删除 V1 全族 / 重命名 V2* / 同步改引用 / 切 config 路径 / 触发首次迁移 / UI kind-aware / 更新测试），要求 spec §4.2 M3 启动前独立 spec 一次
- **详情**：直接修订 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（新增 Canonical JSON Schema 章节 + 10 个 enum 补手写 Codable + LegacyConfigV1/Migrator 改 internal + Task 4 清理 + V2Provider.capabilities 改 Array + Self-Review 更新 + M3 技术债强化段落）
- **结果**：plan 第六轮修订完成；v2 canonical JSON 由手写 Codable 与 golden test 真正锁定（不再是空口声明）；`LegacyConfigV1` 可编译通过；`Set` 相关顺序问题统一修正

---

## Task 30 · 基于 Codex 第五轮评审修订 M1 Plan（V2* 独立类型化 + golden JSON + 文档前置）

- **时间**：2026-04-23
- **描述**：针对 Codex 第五轮 `REWORK_REQUIRED`（3 条 P1 + 4 条 P2）全部接受并落地。(P1-1) 真实 app 可能写坏 v1 config 的核心风险修复：**取消原地改造 Tool / Provider / Configuration / ConfigurationStore 的方案**，改为新建独立 `V2Tool` / `V2Provider` / `V2Configuration` / `DefaultV2Configuration` / `V2ConfigurationStore`；现有 v1 类型全部保持不变；migrator 产出 `V2Configuration` 而非 v1 `Configuration`；V2ConfigurationStore 是独立 actor，不替换现有 FileConfigurationStore；真实 app 启动路径继续读写 v1 `config.json` + schemaVersion=1。(P1-2) Provider.baseURL: URL? 破坏 LLMProviders 编译的问题天然解决：V2Provider 独立，baseURL 可为 URL?；现有 Provider.baseURL 保持 URL 非 optional。(P1-3) v2 canonical JSON schema 锁定：对 ToolKind / PipelineStep / SideEffect / MCPCapability / TransformOp / ProviderSelection / ContextValue 等 associated-value enum 要求增加 golden JSON shape 测试，禁止 Swift 合成 `_0` 泄漏（V2ToolTests 中 `test_v2tool_goldenJSON_promptKind_usesKindDiscriminator` 是典型示例）。(P2-1) SelectionSnapshot 残留文案清理（文件清单 / 依赖图 / 测试注释统一为"新增干净类型，保留 SelectionPayload"）。(P2-2) Package.swift 给 Orchestration / Capabilities 两个新 target 加 `exclude: ["README.md"]`。(P2-3) ContextBag / ContextValue 明确**不实现 Codable**，删除 Codable 分支指令。(P2-4) 新增 Task 0：文档初始化前置（创建 Task-detail 骨架 + Task_history 索引，编号按 grep 取下一个可用值不硬编码）；Task 20 只做"填充完成态字段"
- **详情**：直接修订 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（Architecture / 文件清单 / 依赖图 / Task 0（新）/ Task 1 / Task 7 / Task 12 / Task 15 / Task 17 / Task 18 / Task 19 / Task 20 / Self-Review）
- **结果**：plan 第五轮修订完成；v1 config.json 在真实运行路径上**从架构上不可能**被写入 v2 形状（V2 / v1 类型完全独立，无共享 Codable）；LLMProviders / SettingsUI / AppContainer / DefaultConfiguration 零改动；下一步可进入实施

---

## Task 29 · 基于 Codex 第四轮评审修订 M1 Plan

- **时间**：2026-04-23
- **描述**：针对 Task 28 的 `REWORK_REQUIRED` 三条 P1/P2 全部接受并落地。(P1-1) `SelectionSnapshot` 收缩为干净 v2 类型：删除"重命名 + v1 兼容 init + _legacyXxx stored + v1 Codable key + v1 accessor + typealias SelectionPayload = SelectionSnapshot"整套反模式；`SelectionPayload.swift` 原封保留，`SelectionSnapshot` 只含 `text/source/length/language/contentType` 五字段，两类型独立共存，M3 才做触发层映射。(P1-2) Tool 的 v1 bridge 对**非 .prompt 形态**一律 `assertionFailure` + 生产 no-op：`v1CompatRead` / `v1CompatWrite` 两个 helper 收敛所有 accessor；`providerId` / `modelId` setter 对非 .fixed ProviderSelection 直接拒绝（不再把 .capability / .cascade 强转 .fixed 静默篡改）。(P1-3, Codex P2-1) M1 DoD 口径收紧：不再承诺"真实 app 启动路径已完成迁移"；Task 19 改为"v2 路径 API + migration 能力就绪"，`standardFileURL()` 保持返回 v1；Task 20 Step 5 改为"migrator fixture 单测全绿 + 可选作者 config 干跑"，显式不做"删除/移动作者 config.json / 创建 config-v2.json 在 home"；Self-Review 新增 DoD 口径条目
- **详情**：直接修订 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（Architecture / 文件清单 / Task 4 / Task 15 / Task 19 / Task 20 / Self-Review）
- **结果**：plan 收敛完成，canonical v2 模型不再被兼容层反向污染，DoD 与真实运行路径一致；下一步可进入实施

---

## Task 28 · Phase 0 M1 实施计划评审

- **时间**：2026-04-23
- **描述**：评审 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`，重点审查它是否与已冻结的 v2 roadmap 一致、是否把 M1 范围控制在“核心类型 + 配置迁移”内，以及兼容层设计是否会污染 v2 数据模型或引入静默语义破坏
- **详情**：[docs/Task-detail/phase-0-m1-plan-review-2026-04-24.md](Task-detail/phase-0-m1-plan-review-2026-04-24.md)
- **结果**：完成评审；结论为 `REWORK_REQUIRED`，需先收敛 `SelectionSnapshot` 兼容方案、`Tool` 的 v1 读写桥策略，以及 M1 对 ConfigurationStore/migrator 的验收口径

---

## Task 27 · 基于 Codex 第三轮评审再次修订 v2.0 Roadmap

- **时间**：2026-04-23
- **描述**：针对 Codex 第三轮 `REWORK_REQUIRED`（2 条 P1，已收敛到 CONDITIONAL_APPROVE 边界）全部接受。(D-24 补全) canonical schema 闭合：`Tool` / `Skill` / `MCPDescriptor` 正式结构加 `provenance: Provenance`；`ContextProvider` protocol 加 `static inferredPermissions(for:)`；`SideEffect` 加 computed `inferredPermissions`；`Provenance` enum 唯一 canonical 定义上移到 §3.3.5，§3.9 的两处重复定义删除；附录 B 伪代码同步。(D-25) firstParty 授权规则收敛：删除 §3.9.1 的"已声明即授权"描述；§3.9.2 下限列改为"所有来源均适用"；三处规则（§3.9.1 / §3.9.2 / §3.9.6）统一为"默认未授权 → 按下限触发确认 → provenance 只调整 UX 文案"，`firstParty` 对 `readonly-network` / `local-write` 不再跳过首次确认
- **详情**：直接修订 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（§0 追加第三轮评审条目、§3.3.1 / §3.3.3 / §3.3.5 / §3.3.6 / §3.3.8 数据模型补字段、§3.9.1 / §3.9.2 / §3.9.4.2 重写、§5.2 追加 D-25、附录 B 同步）
- **结果**：spec 第三轮修订完成；Provenance / inferredPermissions / firstParty 规则三处收敛；下一步应出 M1 plan.md 进入实施

---

## Task 26 · 基于 Codex 第二轮评审再次修订 v2.0 Roadmap

- **时间**：2026-04-23
- **描述**：针对 Codex 第二轮 `REWORK_REQUIRED` 的 3 条安全硬伤 + 1 条一致性清理逐条修订 spec。**三条硬伤全部接受**：(D-22) 重写 §3.9.1 / §3.9.2——能力分级为最低下限、Provenance 只放宽 UX 不突破下限，`exec` / `network-write` 无论来源都要每次确认；(D-23) §3.9.4.2 升级 MCP 威胁建模——stdio server ≡ 用户身份下本地代码执行，Phase 1 只允许 `firstParty` / `selfManaged`（新增 Provenance case），`unknown` 来源直接拒绝导入；(D-24) §3.9.6.5 + §3.4 流程 Step 2 加入权限声明闭环——执行前静态计算 effectivePermissions 必须 ⊆ tool.permissions。一致性清理：§0 状态行、§2.3 哲学表、§3.1 分层图、§3.2 模块表、§3.4 Agent 伪代码、附录 A、附录 C 全部统一为新命名与新 milestone 编号。M2 任务表新增 M2.3a（PermissionGraph），Phase 0 合计人天从 14–20 上调到 15–21
- **详情**：直接修订 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（§0 追加第二轮评审条目、§3.9 重写、§3.4 Step 2/2.5 新增、§5.2 追加 D-22/D-23/D-24、§4.2 M2.3a 新增、附录清理）
- **结果**：spec 第二轮修订完成；Phase 0–1 仍处 Design Freeze，下一步出 M1 plan.md

---

## Task 25 · 基于 Codex 评审修订 v2.0 Roadmap

- **时间**：2026-04-23
- **描述**：针对 Task 24 的 `REWORK_REQUIRED` 结论逐条评估并修订 spec。接受的修改：ExecutionContext → `ExecutionSeed` + `ResolvedExecutionContext` 两阶段（修内部矛盾，D-16）；放弃 Context DAG 改平铺并发（D-17）；新增 §3.9 Security Model（D-21）；Phase 0 拆 M1/M2/M3 三个独立 PR（D-20）；Freeze 范围收敛到 Phase 0–1、Phase 2–5 降为 Directional（D-19）；v2 使用独立 `config-v2.json` 路径不覆盖 v1（D-18）。部分不接受：不做双读双写（用户已 worktree 隔离 + 独立路径足够）；不按"兼容 vs 破坏"二分拆 Phase 0（用户明确"破坏性重构问题不大"）
- **详情**：直接修订 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（原文档同位版本升级，变更点见 §0 "评审与修订"与 §5.2 D-16 ~ D-21）
- **结果**：spec 完成修订；Phase 0–1 进入 Design Freeze，下一步可直接建 M1 的 plan.md 进入实施

---

## Task 24 · SliceAI v2.0 Roadmap 规范评审

- **时间**：2026-04-23
- **描述**：对 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md` 做架构与产品规划评审，重点审查定位收敛度、架构重构边界、迁移/回滚策略、安全模型、实施顺序和与当前代码基线的一致性
- **详情**：[docs/Task-detail/sliceai-v2-roadmap-review-2026-04-23.md](Task-detail/sliceai-v2-roadmap-review-2026-04-23.md)
- **结果**：完成评审；结论为 `REWORK_REQUIRED`，建议先修正 Phase 0 范围、补齐迁移/回滚与安全模型，再进入实施计划

---

## Task 23 · 产品 v2.0 规划制定（定位重塑 + 底层架构重构方案）

- **时间**：2026-04-23
- **描述**：基于用户纠正后的产品定位（"划词触发型 AI Agent 配置框架"，非 AI Writing 工具），重新制定产品愿景、五大不变量、底层架构（新增 Orchestration + Capabilities 两个 target）、Tool 三态模型（prompt/agent/pipeline）、ExecutionContext / Permission / OutputBinding 抽象，以及 Phase 0–5 的分阶段路线图（底层重构 → MCP → Skill → Prompt IDE + 本地模型 → 生态 → 高级编排）
- **详情**：[docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md](superpowers/specs/2026-04-23-sliceai-v2-roadmap.md)
- **结果**：规划文档冻结；下一步需新建 `docs/superpowers/plans/2026-04-24-phase-0-refactor.md` 展开 Phase 0 任务级计划

---

## Task 22 · MenuBarController 增强 + PanelStyle 清理 + SwiftLint 总验收

- **时间**：2026-04-21
- **描述**：MVP v0.1 UI 美化阶段收官任务，清理历史技术债、补全菜单栏功能并通过 SwiftLint strict 总验收
- **详情**：[docs/Task-detail/ui-polish-2026-04-21.md](Task-detail/ui-polish-2026-04-21.md)
- **结果**：完成，swift build / swift test / xcodebuild / swiftlint --strict 全绿

---

## Task 21 · OnboardingFlow 重构

- **时间**：2026-04-20
- **描述**：重新设计首次启动引导流程，560×520 三步骤 + 步骤指示器 + Hero 图标风格
- **结果**：完成

---

## Task 18–20 · SettingsScene 重构 + 所有子页填充

- **时间**：2026-04-15 – 2026-04-19
- **描述**：Settings 迁移为 NavigationSplitView；依次填充 Hotkey/Trigger/Permissions/About/Providers/Tools 页面；新增 Appearance 外观切换页
- **结果**：完成

---

## Task 12–17 · 面板 UI 全面重构

- **时间**：2026-04-08 – 2026-04-14
- **描述**：FloatingToolbarPanel / ResultPanel / CommandPalettePanel 使用 DesignSystem token 彻底重构；ResultPanel 拖拽把手 / Header 4 按钮 / StreamingMarkdownView 增强
- **结果**：完成

---

## Task 1–11 · DesignSystem target 搭建

- **时间**：2026-03-28 – 2026-04-07
- **描述**：新建 DesignSystem SwiftPM target；依次完成颜色/字体/间距/圆角/阴影/动画 token、交互 modifier（GlassBackground/HoverHighlight/PressScale）、基础组件（IconButton/PillButton/Chip/KbdKey/SectionCard）、动画组件（DragHandle/ProgressStripe/ThinkingDots）、Onboarding 组件（StepIndicator/HeroIcon/ErrorBlock）；ThemeManager + AppearanceMode；AppContainer 注入 ThemeManager；Configuration.appearance 字段扩展
- **结果**：完成
