# AGENTS.md

本文件是 SliceAI 项目的 agent 工作指引。请优先使用中文沟通，并以当前源码为事实源；历史文档只作为设计意图和任务记录参考。

## 当前项目事实

- 项目定位：macOS 原生、开源的划词触发型 LLM / Agent 工具栏。
- 平台基线：macOS 14+、Xcode 26+、Swift 6.0、SwiftPM local package。
- 当前分支：`codex/phase2-completion`。
- 当前阶段：Task 63 Phase 2 completion 进行中；Skill Registry MVP、真实本地 Skill E2E、公开 Anthropic / OpenAI / Codex skill 仓库 smoke、supporting files 只读加载、Output lifecycle、SideEffect executor、`.silent` 与 `.file` DisplayMode 均已完成，下一步实施 `.replace` DisplayMode。
- 已发布状态：`v0.2.0` 已正式发布；`v0.3.0` tag 和 GitHub draft release 已生成并校验通过，但用户明确暂缓人工发布。
- 根工程是 Swift/macOS 项目，不是 Python 项目；PEP 8、Alembic、uv 规则通常不适用于当前仓库。

## 启动前必读顺序

每次重新打开项目或开始实质修改前，按顺序读取：

1. `README.md`：项目最新状态、模块总览和近期变更记录。
2. `docs/v2-refactor-master-todolist.md`：跨 Phase 状态 Dashboard、后续动作和 DoD。
3. `docs/Task_history.md`：最近任务索引。
4. 当前任务对应的 `docs/Task-detail/*.md`：如果是同一任务的多轮对话，继续更新同一个文件。
5. 当前 Phase / Milestone 对应的 `docs/superpowers/specs/*.md` 和 `docs/superpowers/plans/*.md`。

注意：`CLAUDE.md` 可能滞后于当前 Task 63 进度；`AGENTS.md` 仍是 Codex 工作指引的优先入口；遇到状态冲突时以源码、README 和 master todolist 为准。

## 文档规范

- 根目录只放 `README.md` 和项目级 agent 指引；其它任务、模块、handoff、spec、plan 文档放到 `docs/`。
- 每个任务开始前必须创建或复用 `docs/Task-detail/<task-name>.md`，并更新 `docs/Task_history.md`。
- 任务执行过程中要更新 ToDoList；完成后补充变动文件清单、修改逻辑、验证命令和结果。
- 项目模块有实质变化时，同步更新 `docs/Module/*.md` 或 README 的模块说明。

## 架构总览

项目结构是 “Xcode App target + 单一本地 SwiftPM Package”：

- `SliceAIApp/`：AppKit / SwiftUI app 薄壳、菜单栏、全局监听、Composition Root、ResultPanel 生命周期。
- `SliceAIKit/Package.swift`：本地 SwiftPM package，包含 10 个 library target。
- `SliceCore`：领域模型、配置、权限、MCP/Skill canonical 类型和跨模块协议，原则上零 UI、零网络、零文件系统副作用。
- `Capabilities`：PathSandbox、ContextProviders、MCP store/import/client、persistent permission grants、Skill registry parser/scanner/local actor。
- `Orchestration`：ExecutionEngine、ContextCollector、PermissionGraph/Broker、PromptExecutor、AgentExecutor、OutputDispatcher、SideEffectExecutor、审计和成本记录。
- `LLMProviders`：OpenAI-compatible Chat Completions / SSE / tool calling provider。
- `SelectionCapture`：Accessibility 选区读取 + Cmd+C fallback。
- `HotkeyManager`：Carbon 全局快捷键注册与解析。
- `Windowing`：FloatingToolbar、CommandPalette、ResultPanel 和屏幕定位。
- `SettingsUI`：SwiftUI 设置界面、Provider / Tool / MCP Servers / Skills 页面。
- `DesignSystem` / `Permissions`：UI tokens、共享控件、主题、Accessibility onboarding / monitor。

## 当前已落地功能

- 划词浮条工具栏、`⌥Space` 命令面板、ResultPanel Markdown 流式输出。
- OpenAI 兼容 provider、Keychain API Key、Provider / Tool 设置页。
- v2 `config-v2.json`、旧 `config.json` 迁移、ExecutionEngine 生产触发链。
- 4 个内置 Prompt Tool：Translate、Polish、Summarize、Explain。
- 1 个内置 Agent Tool：`web-search-summarize`，通过 Brave Search MCP 搜索并总结。
- MCP stdio 与 Streamable HTTP client、Claude Desktop `mcp.json` 导入、MCP Servers 设置页。
- 五个核心 ContextProvider：`selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read`。
- PermissionGraph / PermissionBroker、AppKit 权限确认、session/persistent grant 读取边界。
- AgentExecutor ReAct loop、OpenAI-compatible tool calling、MCP allowlist、tool-call lifecycle UI。
- 基础自定义 Agent Tool 编辑器、MCP allowlist 文本配置、AgentToolCallPolicy。
- Per-tool hotkeys。
- Phase 2 Skill Registry MVP：本地 skill roots、`SKILL.md` parser/scanner、Skills 设置页、Agent Tool 最多 5 个 skills 绑定、`sliceai_load_skill` pseudo-tool 渐进式加载，以及 `sliceai_load_skill_resource` 对 `references/` 和文本型 `assets/` 的只读加载；真实本地 Skill E2E 已覆盖 3 个 Claude / Codex 风格 skill，公开仓库 smoke 已覆盖 3 个仓库 / 9 个真实 skill。
- Phase 2 output lifecycle：prompt / agent 执行路径都会 begin / chunk / finish，并把 final text 交给 output sink 与 side effect executor。
- Phase 2 `.silent` 与 `.file` DisplayMode：`.silent` 不落窗；`.file` 在 finish 阶段写入 `appendToFile` 目标，并跳过重复的 appendToFile side effect。
- Phase 2 SideEffect executor：`copyToClipboard`、`appendToFile`、`notify`、`callMCP`、`tts` 已有执行边界；`writeMemory` 仍明确 unsupported。

## 明确未完成 / 不应误报已完成

- `DisplayMode` 仍未全部完成：`.window`、`.silent`、`.file` 已有真实行为；`.bubble`、`.replace`、`.structured` 目前仍 fallback 到 window。
- SideEffect executor 尚未完成 AppContainer 生产 adapter 全量 wiring；当前主要在 Orchestration 层和测试注入路径可用。
- `.pipeline` ToolKind 仍未实现真实 PipelineExecutor。
- Skill supporting files 已支持只读读取 `references/` 与文本型 `assets/`；`scripts/` 不读取、不执行，二进制 assets、`agents/openai.yaml` 解析、script 授权策略仍未实现。
- Marketplace、远端安装、skill 自动更新、Tool Pack、`.slicepack` 尚未实现。
- English Tutor、TTS、StructuredResultView、InlineReplaceOverlay、BubblePanel 尚未实现。
- 原生 Anthropic / Gemini / Ollama provider、Prompt Playground、Memory、Cost Panel 尚未实现。
- `config.schema.json` 已更新到 `Configuration.currentSchemaVersion = 3` 和 v2/Phase 2 配置模型；后续修改配置模型时必须同步更新 schema。

## 常用命令

SwiftPM 命令可从仓库根目录用 `--package-path` 执行：

```bash
swift build --package-path SliceAIKit
swift test --package-path SliceAIKit
swift test --package-path SliceAIKit --parallel --enable-code-coverage
swift test --package-path SliceAIKit --filter SliceCoreTests
```

App / lint / release 相关命令从仓库根目录执行：

```bash
swiftlint lint --strict
git diff --check
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
scripts/build-dmg.sh 0.3.0
```

Phase 1 MCP 环境检查：

```bash
bash scripts/phase1-mcp-e2e.sh
```

## 配置与本地状态

- 主配置：`~/Library/Application Support/SliceAI/config-v2.json`
- 旧配置迁移输入：`~/Library/Application Support/SliceAI/config.json`
- MCP server 配置：`~/Library/Application Support/SliceAI/mcp.json`
- 权限持久化读取：`~/Library/Application Support/SliceAI/permission-grants.json`
- 成本记录：`~/Library/Application Support/SliceAI/cost.sqlite`
- 审计日志：`~/Library/Application Support/SliceAI/audit.jsonl`
- API Key：macOS Keychain，service 为 `com.sliceai.app.providers`，配置只保存 `keychain:<account>` 引用。

不要把密钥、完整用户选区、原始 MCP 返回大段内容或未脱敏错误写入文档、日志或测试 fixture。

## 开发约束

- 优先遵循现有 Swift / SwiftUI / actor / protocol 注入风格，保持 KISS，不做无关抽象。
- 所有 public API 必须写 `///` 文档注释；复杂私有函数也要有简短中文注释说明意图。
- 函数内只在有助于审查或调试的地方写中文注释，不写机械复述代码的注释。
- 必要日志可以用 `Logger` 或项目既有 `print` 路径，但必须避免输出密钥和用户原文；错误 payload 遵守 `SliceError.developerContext` 脱敏规则。
- 不随意改动用户本地 App Support 配置；需要真实 E2E 时先说明会读写哪些本地文件。
- 如果将来新增 `.env`，必须同步维护 `.env.example`；当前项目没有常规 `.env` 流程。
- 不要引入新第三方依赖，除非已确认 Swift 6.0 / macOS 14+ 基线兼容且有明确收益。

## 关键不变量

- `SliceCore` 不依赖 AppKit / SwiftUI，不直接访问网络、文件系统或子进程。
- `DesignSystem` 只被 UI target 依赖，不反向进入领域层。
- `AppContainer` 是生产依赖装配中心；业务层不要分散创建跨模块依赖。
- `ExecutionEngine` 是生产工具执行唯一入口；App 层只消费 `ExecutionEvent`。
- 权限必须先声明再执行：`effectivePermissions` 必须被 `Tool.permissions` 覆盖，否则 fail-closed。
- `MCP`、`network`、`shellExec`、`appIntents` 等高风险能力默认不持久缓存运行期授权。
- `DisplayMode` 目前以 `Tool.displayMode` 为单一事实源；`outputBinding.primary` 若存在必须一致。
- Agent Tool skill 绑定最多 5 个，只能绑定 registry 中 `.enabled` skill。

## 测试与完成标准

代码变更至少运行与改动相关的 focused tests，并在最终说明中写明命令和结果。跨模块、配置、执行链、权限或 UI wiring 变更，应优先运行：

```bash
swift test --package-path SliceAIKit
swiftlint lint --strict
git diff --check
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

如果因为本机环境、Xcode、权限或外部服务无法验证，必须明确说明未验证项、原因和风险。不要在未运行验证时声称“已通过”。
