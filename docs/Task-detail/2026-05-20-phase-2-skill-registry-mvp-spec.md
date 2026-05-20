# Phase 2 Skill Registry MVP Spec Kickoff

## 任务背景

`v0.3.0` draft release 已由 GitHub Actions 生成并校验通过，但用户决定暂缓人工发布，继续后续开发。Phase 2 在总 spec 中仍是 Directional Outline，不能直接进入实现；如果现在直接做 English Tutor、DisplayMode 或完整 Skill runtime，容易把 Skill 抽象、权限边界和 UI 入口写死。

本任务的目标是启动 Phase 2 的第一个可控设计切片：Skill Registry MVP。它先回答“SliceAI 如何发现、解析、展示和引用本地 skill 包”，为后续 DisplayMode、English Tutor、skill 安装与运行时能力建立边界。

## 实施方案

1. 更新项目进度文档，明确 `v0.3.0` draft release 已暂缓人工发布，避免下一会话继续沿“发布”方向误操作。
2. 使用 `session-handoff` 保存当前工作流，要求下一会话先复述上下文，再开始任何编辑。
3. 下一会话先使用 `superpowers:brainstorming` 与用户对齐 Skill Registry MVP 的用户价值、scope 和 out-of-scope。
4. 在确认设计后产出 `docs/superpowers/specs/YYYY-MM-DD-phase-2-skill-registry-mvp.md`，再进入 plan / 实现。

## ToDoList

- [x] 创建本任务文档。
- [x] 登记 `docs/Task_history.md`。
- [x] 更新 README、master TodoList 和 v0.3 release prep 任务文档，记录暂缓发布和 Phase 2 下一步。
- [x] 创建 `docs/handoffs/2026-05-20-phase-2-skill-registry-mvp.md`。
- [ ] 使用 `superpowers:brainstorming` 明确 Skill Registry MVP 范围。
- [ ] 产出 `docs/superpowers/specs/YYYY-MM-DD-phase-2-skill-registry-mvp.md`。
- [ ] 对 spec 做自检 / review，并在用户确认后进入 implementation plan。

## 当前状态

- 当前分支：`main`。
- 当前工作不改业务代码，只修正文档和交接状态。
- `v0.3.0` draft release 保持草稿；除非用户重新明确要求，不发布、不删 draft、不重打 tag。
- Phase 2 推荐首个切片为 Skill Registry MVP；DisplayMode、English Tutor、远端 skill 安装、marketplace 和复杂运行时能力先不进入第一轮 spec。

## 推荐 MVP 边界

- 本地 skill 目录扫描与 enable / disable 状态模型。
- `SKILL.md` frontmatter / description / instructions 的最小解析规则。
- Settings UI 可查看 skill 列表、来源、状态和解析错误。
- Tool 配置能引用已启用 skill，并在执行前把 skill 指令注入到 agent / prompt 上下文。
- 至少 2 个本地 fixture skill 覆盖解析成功、解析失败和禁用场景。

## 暂不进入本轮的内容

- Marketplace、远端安装、GitHub 拉取或自动更新。
- Skill 内脚本执行、依赖安装、沙箱运行和长期后台任务。
- English Tutor 全流程。
- `replace / bubble / structured / silent` DisplayMode 的完整 UI 实现。
- TTS、复杂 structured form schema、跨 App `setSelectedText` 兼容矩阵。

## 验证策略

本任务当前阶段是文档和设计启动，不需要运行 Swift 测试。下一步进入 spec / plan 后，应在实现前按 TDD 补齐以下验证方向：

- Skill manifest / `SKILL.md` 解析单测。
- Skill registry 扫描、错误收集和 enable / disable 状态单测。
- Tool 引用 skill 后的 prompt / agent context 组装单测。
- Settings UI 的 skill 列表和错误态 ViewModel 测试。

## 变动文件清单

- `README.md`：更新项目状态和 Phase 2 启动记录。
- `docs/Task_history.md`：新增 Task 58。
- `docs/v2-refactor-master-todolist.md`：更新 Dashboard、Phase 2 启动切片和最新 snapshot。
- `docs/Task-detail/2026-05-19-v0.3-release-prep.md`：记录人工发布暂缓。
- `docs/Task-detail/2026-05-20-phase-2-skill-registry-mvp-spec.md`：新增本任务文档。
- `docs/handoffs/2026-05-20-phase-2-skill-registry-mvp.md`：新增下一会话交接。

## 代码修改逻辑

本任务目前没有业务代码修改。文档修改逻辑是把“v0.3 发布动作”与“Phase 2 开发启动”拆开：`v0.3.0` draft release 技术上已准备好，但人工发布是显式暂缓的产品决策；后续开发不应围绕发布 checklist 继续，而应先对 Directional 的 Phase 2 重新做 spec。

## 测试结果

- 已通过：`git diff --check`，确认文档 patch 无 whitespace 问题。
- 未执行 Swift 测试：本任务未修改业务代码。
