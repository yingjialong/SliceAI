# 2026-05-24 · Phase 2 Skill E2E Validation

## 任务背景

用户确认继续 Phase 2，并要求执行真实 Skill E2E 兼容性验证，直到验证通过为止。

当前 Phase 2 Skill Registry MVP 已完成，但已有证据主要来自 parser / scanner / registry / AgentExecutor 的单元测试与 App 手测。下一步需要补齐一条可重复的本地端到端证据：真实 Claude / Codex 风格 skill 目录写入文件系统后，SliceAI 能从 `SkillSource` 扫描到 `LocalSkillRegistry`，再由 Agent Tool 绑定并通过 `sliceai_load_skill` 渐进式加载完整 `SKILL.md`。

## 已核对的官方行为基线

- OpenAI Codex Skills：skill 是包含 `SKILL.md` 的目录，可带 `scripts/`、`references/`、`assets/`、`agents/openai.yaml`；初始只给模型 name / description / file path，按需加载完整 `SKILL.md`。
- Claude Code Skills：常见位置包括 `.claude/skills/`；frontmatter 支持 `allowed-tools`、`disable-model-invocation`、`user-invocable`。`allowed-tools` 属于 Claude Code 权限语义，在 SliceAI 中只展示，不映射为 PermissionGraph 授权。

## 实施方案

1. 新增 Phase 2 Skill E2E validation plan，明确 3 个本地 skill 场景、通过标准和验证命令。
2. 新增自动化 E2E 测试，使用真实临时目录和 `LocalSkillRegistry`，不使用 `MockSkillRegistry` 替代 registry 关键路径。
3. 覆盖 3 个本地 skill 形态：
   - Codex 风格：`skills/<name>/SKILL.md`，包含 `agents/openai.yaml`、`references/`、`assets/`、`scripts/`。
   - Claude 风格：`.claude/skills/<name>/SKILL.md`，包含 `disable-model-invocation: true`，通过 SliceAI override `.on` 开启。
   - Codex / Agents 用户风格：`.agents/skills/<name>/SKILL.md` 或 `.codex/skills/<name>/SKILL.md`，包含 `user-invocable` 与 `allowed-tools` 兼容字段。
4. 如果测试暴露真实兼容问题，先修复源码，再复跑 focused tests 和全量 gate。
5. 更新 README / master todolist / Task_history，记录验证结果和剩余 Phase 2 后续任务。

## ToDoList

- [x] 写入 Phase 2 Skill E2E validation implementation plan。
- [x] 新增真实文件系统 E2E 测试，覆盖 3 个 Claude / Codex 风格 skill。
- [x] 运行 focused E2E 测试，确认验证链路通过或暴露问题。
- [x] 修复验证暴露的问题。（focused E2E 首次通过，未发现需要修改产品逻辑的问题；full gate 暴露既有取消测试竞态，已收紧测试夹具。）
- [x] 运行完整 gate：`swift test --package-path SliceAIKit`、`swiftlint lint --strict`、`git diff --check`。
- [x] 更新 README / master todolist / Task_history / 本任务文档。

## 预期通过标准

- 真实 `LocalSkillRegistry` 能扫描并启用 3 个本地 skill。
- `disable-model-invocation: true` 的 Claude 风格 skill 在 override `.on` 后能被 Agent Tool 绑定并加载。
- Agent 初始 prompt 包含 3 个 skill 的 metadata，且 provider-visible tool catalog 包含 `sliceai_load_skill`。
- Agent 运行时调用 `sliceai_load_skill` 能返回真实 `SKILL.md` body。
- Supporting files 只作为目录存在，不被 `loadSkillInstructions` 读取到模型 payload。
- `allowed-tools` 能被解析为 manifest 展示字段，但不产生 MCP / shell 权限授权。

## 变动文件清单

- `SliceAIKit/Tests/OrchestrationTests/AgentExecutorSkillE2ETests.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- `docs/Task-detail/2026-05-24-phase-2-skill-e2e-validation.md`
- `docs/superpowers/plans/2026-05-24-phase-2-skill-e2e-validation.md`
- `docs/Task_history.md`
- `docs/v2-refactor-master-todolist.md`
- `README.md`
- `AGENTS.md`
- `CLAUDE.md`

## 测试与验证结果

- `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorSkillE2ETests`：通过，1 test，0 failures。
- `swift test --package-path SliceAIKit --filter OrchestrationTests.ExecutionEngineTests/test_execute_cancellationDuringPromptStream_skipsLaterChunkDispatch`：通过，1 test，0 failures。
- `swift test --package-path SliceAIKit`：通过，796 tests，0 failures。
- `swiftlint lint --strict`：通过，0 violations，0 serious。
- `git diff --check`：通过，无输出。

本测试使用真实临时目录创建 3 个 skill：

- `skills/prose-polisher/SKILL.md`：Codex 风格，包含 `allowed-tools` 列表、`references/`、`assets/`、`scripts/`、`agents/openai.yaml`。
- `.claude/skills/claude-research/SKILL.md`：Claude 风格，包含 `disable-model-invocation: true`，通过 SliceAI override `.on` 后启用。
- `.agents/skills/codex-review/SKILL.md`：Codex / Agents 风格，包含 `user-invocable: true` 与 `allowed-tools`。

已验证：

- `LocalSkillRegistry` 能扫描到 3 个 enabled skills。
- `allowed-tools`、`disable-model-invocation`、`user-invocable` 均按当前 MVP 语义解析。
- Agent 初始请求暴露 `sliceai_load_skill`，prompt 中包含 3 个 skill metadata。
- Agent 调用 `sliceai_load_skill` 后，后续模型消息包含真实 `SKILL.md` body。
- `references/` 和 `scripts/` 中的 sentinel 文本没有进入模型可见 payload。
- `sliceai_load_skill` 未触发 MCP client 调用。

## 问题与处理

- 本地 Skill E2E 首次通过，没有发现 scanner / parser / registry / AgentExecutor 的产品兼容性缺陷。
- full gate 首次暴露既有 `test_execute_cancellationDuringPromptStream_skipsLaterChunkDispatch` 的 Swift async 调度竞态：普通 `MockOutputDispatcher` 返回过快时，完整套件负载下 producer 可能在 consumer break 取消真正传导前多处理一个 chunk。
- 已将该测试改为使用 `CancellationAwareFirstChunkOutputDispatcher`：首个 `handle` 内执行可取消等待，让 consumer break 明确传导到 `ExecutionEngine` 的 post-handle cancellation check。此处只改测试夹具，不改生产逻辑。

## 任务结果

完成。真实本地 Claude / Codex 风格 Skill E2E 兼容性验证已通过；完整 gate 已通过。Phase 2 的下一步仍不是“整个 Phase 2 完成”，而是继续做公开 skill 仓库兼容性、supporting files 只读加载设计或 DisplayMode 相关切片。
