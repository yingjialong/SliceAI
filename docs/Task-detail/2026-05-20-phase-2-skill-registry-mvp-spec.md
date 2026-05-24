# Phase 2 Skill Registry MVP Spec Kickoff

## 任务背景

`v0.3.0` draft release 已由 GitHub Actions 生成并校验通过，但用户决定暂缓人工发布，继续后续开发。Phase 2 在总 spec 中仍是 Directional Outline，不能直接进入实现；如果现在直接做 English Tutor、DisplayMode 或完整 Skill runtime，容易把 Skill 抽象、权限边界和 UI 入口写死。

本任务的目标是启动 Phase 2 的第一个可控设计切片：Skill Registry MVP。它先回答“SliceAI 如何发现、解析、展示和引用本地 skill 包”，为后续 DisplayMode、English Tutor、skill 安装与运行时能力建立边界。

## 实施方案

1. 更新项目进度文档，明确 `v0.3.0` draft release 已暂缓人工发布，避免下一会话继续沿“发布”方向误操作。
2. 使用 `session-handoff` 保存当前工作流，要求下一会话先复述上下文，再开始任何编辑。
3. 下一会话先使用 `superpowers:brainstorming` 与用户对齐 Skill Registry MVP 的用户价值、scope 和 out-of-scope。
4. 在确认设计后产出 `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`，再进入 plan / 实现。
5. 用户确认 spec 后，使用 `superpowers:writing-plans` 产出 `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`，进入执行方式选择。

## ToDoList

- [x] 创建本任务文档。
- [x] 登记 `docs/Task_history.md`。
- [x] 更新 README、master TodoList 和 v0.3 release prep 任务文档，记录暂缓发布和 Phase 2 下一步。
- [x] 创建 `docs/handoffs/2026-05-20-phase-2-skill-registry-mvp.md`。
- [x] 使用 `superpowers:brainstorming` 明确 Skill Registry MVP 范围。
- [x] 产出 `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`。
- [x] 用户 review spec 并确认进入 implementation plan。
- [x] 使用 `superpowers:writing-plans` 产出 `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`。
- [x] 用户选择执行方式：Subagent-Driven。
- [x] 完成 SliceCore skill schema 与配置迁移。
- [x] 完成 Capabilities `SKILL.md` parser / scanner / `LocalSkillRegistry`。
- [x] 完成 AgentExecutor `sliceai.load_skill` pseudo-tool 和 metadata 注入。
- [x] 完成 Settings Skills 页面与 Agent Tool skill 绑定 UI。
- [x] 按用户反馈将 Agent Tool skill 绑定 UI 从全量列表改为逐条添加：加号新增一行，每行用下拉菜单选择 skill，减号删除该行。
- [x] 完成 AppContainer 真实 `LocalSkillRegistry` 注入。
- [x] 完成 full gate。
- [x] 用户完成 App 手测且未反馈问题。
- [x] 提交 `1411e88 feat: add skill registry mvp` 并推送到 `origin/main`。

## 当前状态

- 当前分支：`main`。
- 当前 HEAD / `origin/main`：`1411e88 feat: add skill registry mvp`。
- 当前工作已完成 Skill Registry MVP 实现、final gate、用户 App 手测和远端推送；Agent Tool skill 绑定 UI 已改为逐条添加 / 下拉选择 / 减号删除，不再一次性列出全部 skills。
- `v0.3.0` draft release 保持草稿；除非用户重新明确要求，不发布、不删 draft、不重打 tag。
- Phase 2 推荐首个切片为 Skill Registry MVP；DisplayMode、English Tutor、远端 skill 安装、marketplace 和复杂运行时能力先不进入第一轮 spec。
- 已完成 Skill Registry MVP 范围对齐、正式 spec、implementation plan、Claude review loop approve、Subagent-Driven 实施、最终验证、用户手测和 `origin/main` 推送。下一步建议先做真实 Skill E2E 兼容性验证，再决定 supporting files、DisplayMode 或 marketplace 的优先级。

## 推荐 MVP 边界

- 本地 skill 目录扫描与 enable / disable 状态模型。
- `SKILL.md` frontmatter / description / instructions 的最小解析规则。
- Settings UI 可查看 skill 列表、来源、状态和解析错误。
- Agent Tool 配置能绑定最多 5 个已启用 skill；执行时先向模型暴露绑定 skill 的元数据，模型通过内置 pseudo-tool `sliceai.load_skill` 按需加载完整 `SKILL.md` 指令。Prompt Tool 暂不支持 skill 绑定。
- 至少 2 个本地 fixture skill 覆盖解析成功、解析失败和禁用场景。

## 暂不进入本轮的内容

- Marketplace、远端安装、GitHub 拉取或自动更新。
- Supporting files（`references/`、`assets/`、`scripts/`）按需读取；本轮只读取 `SKILL.md`，并把资源读取列为技术债务。
- Skill 内脚本执行、依赖安装、沙箱运行和长期后台任务；本轮不做，后续作为 runtime 技术债务单独设计。
- Marketplace、远端安装、GitHub 拉取或自动更新；本轮不做，后续作为分发与 trust model 技术债务单独设计。
- English Tutor 全流程。
- `replace / bubble / structured / silent` DisplayMode 的完整 UI 实现。
- TTS、复杂 structured form schema、跨 App `setSelectedText` 兼容矩阵。

## 验证策略

本任务已从文档和设计启动推进到实现、手测和远端推送。实现阶段按 TDD 补齐并运行以下验证方向：

- Skill manifest / `SKILL.md` 解析单测。
- Skill registry 扫描、错误收集和 enable / disable 状态单测。
- Agent Tool 绑定 skill 后的 metadata 注入与 `sliceai.load_skill` pseudo-tool 单测。
- Settings UI 的 skill 列表、roots 管理、错误态和 Agent Tool skill 绑定 ViewModel 测试。
- Agent Tool skill 绑定 UI 的逐条新增、下拉候选去重、行内替换和删除测试。
- 全量 SwiftPM、SwiftLint strict、`git diff --check` 和 Xcode Debug build gate。

## 变动文件清单

- `README.md`：更新项目状态和 Phase 2 启动记录。
- `docs/Task_history.md`：新增 Task 58。
- `docs/v2-refactor-master-todolist.md`：更新 Dashboard、Phase 2 启动切片和最新 snapshot。
- `docs/Task-detail/2026-05-19-v0.3-release-prep.md`：记录人工发布暂缓。
- `docs/Task-detail/2026-05-20-phase-2-skill-registry-mvp-spec.md`：新增本任务文档。
- `docs/handoffs/2026-05-20-phase-2-skill-registry-mvp.md`：新增下一会话交接。
- `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`：新增 Skill Registry MVP 正式规格，记录 Claude/Codex 兼容、渐进式加载、pseudo-tool、配置、UI、错误模型、测试策略和技术债务。
- `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`：implementation plan，按 TDD 拆分 SliceCore schema、parser/scanner、registry、AgentExecutor pseudo-tool、Settings UI、AppContainer wiring、文档和最终 gate。
- `docs/Module/SkillRegistry.md`：新增 SkillRegistry 模块文档。
- `docs/Module/Capabilities.md`：更新 Capabilities 的 SkillRegistry 口径。
- `SliceAIKit/Sources/SliceCore/*`：新增 canonical skill schema、`SkillSettings`、`AgentTool.skills`、schema version 3 与兼容解码。
- `SliceAIKit/Sources/Capabilities/Skills/*`：新增 parser、scanner、registry、snapshot 和 mock registry。
- `SliceAIKit/Sources/Orchestration/Executors/*`：新增 skill metadata prompt 和 `sliceai_load_skill` pseudo-tool 本地处理。
- `SliceAIKit/Sources/SettingsUI/*`：新增 Skills 页面、SkillsViewModel 和 Agent Tool skill 绑定 UI；`ToolEditorView+AgentSkills.swift` 封装逐条添加、下拉选择、重复排除和删除逻辑。
- `SliceAIApp/AppContainer.swift`、`SliceAIApp/AppDelegate.swift`：注入单例 `LocalSkillRegistry`。

## 代码修改逻辑

最初文档修改逻辑是把“v0.3 发布动作”与“Phase 2 开发启动”拆开：`v0.3.0` draft release 技术上已准备好，但人工发布是显式暂缓的产品决策；后续开发不应围绕发布 checklist 继续，而应先对 Directional 的 Phase 2 重新做 spec。

Skill Registry MVP 的 spec 修改逻辑是把原 roadmap 中“执行前直接拼接完整 `SKILL.md`”修正为更接近 Claude/Codex 的 progressive disclosure：Agent Tool 先绑定候选 skills，模型初始只看到 `name / description / path` 元数据，真正需要时通过内置 `sliceai.load_skill` 读取完整 `SKILL.md`。同时明确本轮只支持 Agent Tool，不支持 Prompt Tool；只读取 `SKILL.md`，不执行脚本、不读取 supporting files、不做 marketplace，并把这些后续能力列为技术债务。

Implementation plan 的修改逻辑是把 spec 拆为 8 个可 TDD 执行的任务：先稳定 SliceCore schema，再落 parser / scanner / registry，再接 AgentExecutor 渐进式加载，最后接 Settings UI 和 AppContainer wiring。这样可以避免 UI 先行或执行链先行导致模型边界反复重写。

实现修改逻辑是保持 KISS：canonical skill 数据只放 `SliceCore`，`Capabilities` 只负责文件系统扫描、最小 frontmatter 解析和 registry snapshot；`Orchestration` 不读取目录，只消费当前 Agent Tool 已绑定的 enabled skills；`SettingsUI` 只写 `Configuration.skillSettings` 和 `AgentTool.skills`；`SliceAIApp` 只负责把同一个 `LocalSkillRegistry` 注入 UI 和运行时。这样能避免 registry、UI 和执行链各自扫描或缓存出不同真相。

Agent Tool skill 绑定 UI 的二次修改逻辑是减少配置噪音：原全量列表会把所有 enabled skills 一次性铺开，skill 数量上来后会影响 Agent 编辑器可读性。新实现只展示已绑定行；用户通过加号一次新增一个绑定，行内 Picker 只显示当前行 skill 和其它未绑定 skills，避免重复选择；减号删除当前绑定。添加时默认选中第一个未绑定 skill，保持配置模型只保存有效 `SkillReference`，避免引入 UI-only 空行状态。

final gate 前的 lint 修复只做结构性小拆分：`SkillDirectoryScanner` 改为私有累加器，`LocalSkillRegistry` 把候选读取/解析/构造拆成小 helper，`AgentExecutor` 把请求构造和 tool message 摘要拆到独立扩展文件，`AppContainer` 用输入结构体收口 runtime 参数。拆分不改变业务语义，主要目的是让实现继续符合仓库 SwiftLint 阈值。

## 测试结果

- 已通过：`git diff --check`，确认最终 diff 无 whitespace 问题。
- 已通过：spec 完整性扫描，未发现未完成标记或未替换日期模板。
- 已通过：plan 完整性扫描，未发现未完成标记或未替换日期模板。
- 已通过：`swift test --package-path SliceAIKit --filter ToolEditorSkillsBindingTests`（5 tests），覆盖加号新增、下拉候选去重、行内替换和减号删除。
- 已通过：`swift test --package-path SliceAIKit --filter 'AgentExecutorTests|SettingsUITests|SkillMarkdownParserTests|SkillDirectoryScannerTests|SkillRegistryProtocolTests|LocalSkillRegistryTests'`（76 tests）。
- 已通过：`swift test --package-path SliceAIKit`（795 tests，0 failures）。
- 已通过：`swiftlint lint --strict`（0 violations，0 serious）。
- 已通过：`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`（`BUILD SUCCEEDED`）。
- 已完成：用户 App 手测，未反馈问题。
- 已完成：`git push origin main`，`HEAD == origin/main == 1411e88c47660512ff876d76174da41ec5e5f209`。
