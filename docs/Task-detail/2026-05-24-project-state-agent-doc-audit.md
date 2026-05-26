# 2026-05-24 · Project State And Agent Doc Audit

## 任务背景

用户要求基于整个 SliceAI 项目完整了解当前实际情况，并完成三件事：

1. 更新项目级 `AGENTS.md`，使其反映当前 Swift/macOS 项目事实。
2. 梳理项目已经完成的功能、当前做到哪一步、后续还需要做什么。
3. 核对实际代码实现与设计 spec / 项目文档之间的不一致。

本任务不修改产品代码，只做项目事实盘点、Agent 指引文档更新和状态审计输出。

## 已读取的关键信息源

- `README.md`
- `CLAUDE.md`
- `docs/Task_history.md`
- `docs/v2-refactor-master-todolist.md`
- `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`
- `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`
- `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`
- `docs/Module/SliceCore.md`
- `docs/Module/Capabilities.md`
- `docs/Module/Orchestration.md`
- `docs/Module/SkillRegistry.md`
- `SliceAIKit/Package.swift`
- `SliceAIApp/AppContainer.swift`
- `SliceAIKit/Sources/SliceCore/*`
- `SliceAIKit/Sources/Capabilities/Skills/*`
- `SliceAIKit/Sources/Orchestration/Executors/*`
- `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift`
- `SliceAIKit/Sources/SettingsUI/*`
- `config.schema.json`

## 实施方案

1. 以最新源码为事实源，文档只作为历史和设计意图参考。
2. 新增项目级 `AGENTS.md`，覆盖当前平台、模块、执行入口、配置路径、常用命令、开发约束、测试门槛和已知未完成能力。
3. 不在本任务中修复源码与 spec 的行为差异，只把差异分级列出；避免把审计任务扩大成产品开发任务。
4. 对文档修改运行轻量验证；如时间允许，运行 SwiftPM 测试或至少相关文档/工作区状态检查。

## ToDoList

### 第一轮：项目状态审计与 AGENTS.md

- [x] 阅读 README、任务历史、master todolist 和当前 Phase 2 spec / plan。
- [x] 阅读核心源码，确认实际实现状态。
- [x] 创建本任务详情文档。
- [x] 更新 `docs/Task_history.md` 索引。
- [x] 新增 / 更新项目级 `AGENTS.md`。
- [x] 整理“已完成功能 / 当前阶段 / 待办任务”清单。
- [x] 整理“代码实现 vs spec / 文档偏差”清单。
- [x] 运行验证命令。
- [x] 补充本任务总结、文件清单和验证结果。

### 第二轮：剩余任务总表与不一致修复

- [x] 在 `docs/v2-refactor-master-todolist.md` 中补齐从当前到 v1.0 的剩余任务总表。
- [x] 修复 `docs/v2-refactor-master-todolist.md` 中 Phase 0 / Phase 1 的旧状态口径。
- [x] 修复 `config.schema.json` 与当前 schemaVersion 3 / v2 Tool 模型 / SkillSettings 的不一致。
- [x] 修复 `CLAUDE.md` 当前状态、命令、架构描述落后于 Phase 2 的问题。
- [x] 修复 `docs/Module/SliceCore.md` 中 `.agent` 仍写 not implemented 的错误。
- [x] 修复 `docs/Module/Orchestration.md` 中 `.agent` 执行链与 AgentExecutor 状态的错误。
- [x] 运行验证命令并更新本任务结果。

## 审计判断

- 项目是 macOS 原生 Swift 6.0 / SwiftPM + Xcode App 项目，不是 Python 项目；PEP 8、Alembic、uv 等规则对当前仓库无实际适用面。
- 根目录原本没有 `AGENTS.md`，只有 `CLAUDE.md`；本任务已新增 `AGENTS.md` 并刷新 `CLAUDE.md` 的 Phase 2 状态口径。
- 代码层面已完成 Phase 2 Skill Registry MVP：`Configuration.currentSchemaVersion = 3`、`SkillSettings`、`LocalSkillRegistry`、Settings Skills 页面、Agent Tool skills 绑定、AgentExecutor `sliceai_load_skill` pseudo-tool 均已存在。
- `config.schema.json` 原本仍是旧 schemaVersion 1 和旧扁平工具模型；本任务已更新到 schemaVersion 3、v2 ToolKind、ProviderSelection、permissions、SkillSettings 和 Agent Tool skills 模型。

## 变动文件清单

- `docs/Task-detail/2026-05-24-project-state-agent-doc-audit.md`
- `docs/Task_history.md`
- `AGENTS.md`
- `README.md`
- `CLAUDE.md`
- `config.schema.json`
- `docs/v2-refactor-master-todolist.md`
- `docs/Module/SliceCore.md`
- `docs/Module/Orchestration.md`

## 测试与验证结果

- `git diff --check`：通过，无输出。
- `swift test --package-path SliceAIKit`：第一次全量运行失败 1 个未复现用例：
  - `OrchestrationTests.ExecutionEngineTests.test_execute_cancellationDuringPromptStream_skipsLaterChunkDispatch`
  - 失败现象：`handleCallCount=2`，断言要求 cancelled-during-prompt-stream 最多 dispatch 1 个 chunk。
  - 本轮仅修改文档，未修改 Swift 源码；该 focused test 随后单独复跑通过。
- `swift test --package-path SliceAIKit --filter OrchestrationTests.ExecutionEngineTests/test_execute_cancellationDuringPromptStream_skipsLaterChunkDispatch`：通过，1 test，0 failures。
- `swift test --package-path SliceAIKit`：第二次全量复跑通过，795 tests，0 failures。
- `swiftlint lint --strict`：通过，180 files，0 violations，0 serious。
- `jq empty config.schema.json`：第二轮通过，schema 文件为合法 JSON。
- `git diff --check`：第二轮通过，无输出。
- `swift test --package-path SliceAIKit`：第二轮通过，795 tests，0 failures。
- `swiftlint lint --strict`：第二轮通过，180 files，0 violations，0 serious；仍有既有 `.swiftlint.yml` 关于 `unused_import` 应放到 `analyzer_rules` 的提示，不影响退出码。

## 任务结果

已完成。

- 新增根目录 `AGENTS.md`，记录当前 Swift/macOS 项目事实、必读顺序、模块边界、当前已落地功能、明确未完成能力、常用命令、配置路径、开发约束、关键不变量和测试完成标准。
- 已梳理项目当前阶段：Phase 0 已发布 `v0.2.0`；Phase 1 `v0.3.0` tag / draft release 已生成但人工发布暂缓；Phase 2 Skill Registry MVP 已合入，下一步应先做真实 Claude / Codex 风格 skill E2E。
- 已在 `docs/v2-refactor-master-todolist.md` 补齐从当前到 v1.0 的 **60 项剩余主任务**。
- 已修复主要偏差：
  - `config.schema.json` 已从 schemaVersion 1 / 旧扁平工具模型更新为 schemaVersion 3 / v2 ToolKind / SkillSettings 模型。
  - `CLAUDE.md` 已更新到 Phase 2 Skill Registry MVP 状态、10 个 SwiftPM target、AgentExecutor / LocalSkillRegistry 和当前未完成边界。
  - `README.md` 已修正 Current Features 标题，并补充 Orchestration / SettingsUI 的 AgentExecutor、Skills 页面事实。
  - `docs/Module/SliceCore.md` / `docs/Module/Orchestration.md` 已修正 `.agent` 执行状态，明确 `.agent` 已走真实 AgentExecutor，`.pipeline` 才仍是 not implemented。
  - `docs/v2-refactor-master-todolist.md` 已修正 Phase 0 / Phase 1 / Phase 2 状态口径，并保留 `v0.3.0` 人工发布暂缓事实。
- 仍然是产品事实的未完成功能：`DisplayMode` 非 `.window`、PipelineExecutor、Skill supporting files、Marketplace、English Tutor、TTS、原生 Anthropic/Gemini/Ollama、Memory 等尚未实现，不应对外宣称完成。
