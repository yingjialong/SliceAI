# 2026-05-24 · Phase 2 Public Skill Repository Compatibility

## 任务背景

用户确认继续 Phase 2，按“自动化 smoke + 文档证据 + 必要代码修复”的方式执行公开 Anthropic / Codex skill 仓库兼容性验证。

上一任务已完成 3 个本地 Claude / Codex 风格 skill 的真实文件系统 E2E；本任务进一步验证公开仓库真实目录结构。关键边界保持不变：SliceAI 当前 MVP 只扫描和解析 `SKILL.md`，只按需加载 `SKILL.md` body，不读取 `references/` / `assets/`，不执行 `scripts/`，不把 skill manifest 的 `allowed-tools` 映射为 SliceAI 权限。

## 官方/公开行为基线

- Anthropic 官方公开仓库 `anthropics/skills` 声明 skill 是自包含文件夹，每个文件夹包含 `SKILL.md` 指令与元数据。
- Claude Code docs 说明 skills 可位于 `.claude/skills/`，支持 `disable-model-invocation`、`user-invocable`、`allowed-tools` 等 frontmatter 字段。
- OpenAI Codex docs 说明 Codex skills 使用渐进式披露：初始只给 name / description / file path，使用时再读取完整 `SKILL.md`；skill 目录可包含 `scripts/`、`references/`、`assets/`、`agents/openai.yaml`。

## 计划验证样本

| 来源 | 仓库 | 固定 commit | 样本路径 |
|---|---|---|---|
| Anthropic official | `https://github.com/anthropics/skills.git` | `690f15cac7f7b4c055c5ab109c79ed9259934081` | `skills/docx`、`skills/frontend-design`、`skills/mcp-builder` |
| OpenAI official | `https://github.com/openai/skills.git` | `b0401f07213a66414d84a65cb50c1d226f99485a` | `skills/.curated/openai-docs`、`skills/.curated/pdf`、`skills/.curated/security-threat-model` |
| Codex community | `https://github.com/jMerta/codex-skills.git` | `1be063de2a730d61133e957dfc01a670cce7abd4` | `agents-md`、`bug-triage`、`plan-work` |

## ToDoList

- [x] 创建 task detail、spec 和 implementation plan。
- [x] TDD 新增 scanner nested collection 兼容测试，并确认当前实现红灯。
- [x] 修复 `SkillDirectoryScanner`，支持公开仓库常见的 `skills/.curated/<skill>/SKILL.md` / `skills/.system/<skill>/SKILL.md` collection 布局。
- [x] 新增 opt-in `PublicSkillRepositorySmokeTests`，默认无 env 时 skip，脚本提供 manifest 时验证真实公开仓库快照。
- [x] 新增 `scripts/phase2-public-skill-smoke.sh`，拉取固定 commit + sparse checkout + 运行 smoke test。
- [x] 运行 focused tests、公开仓库 smoke、full gate。
- [x] 更新 README / master todolist / Task_history / 本任务文档。

## 预期通过标准

- 常规 `swift test --package-path SliceAIKit` 不依赖网络，公开仓库 smoke 默认 skip。
- `scripts/phase2-public-skill-smoke.sh` 能拉取 3 个固定公开仓库快照并运行 opt-in smoke。
- 9 个公开 skill 样本可被 `LocalSkillRegistry` 扫描、解析并启用。
- 每个样本可通过 `loadSkillInstructions` 加载真实 `SKILL.md` body。
- 不执行公开仓库中的任何 script，不读取 supporting files 到模型 payload。
- full gate 通过：`swift test --package-path SliceAIKit`、`swiftlint lint --strict`、`git diff --check`。

## 变动文件清单

- `SliceAIKit/Sources/Capabilities/Skills/SkillDirectoryScanner.swift`
- `SliceAIKit/Tests/CapabilitiesTests/SkillDirectoryScannerTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/PublicSkillRepositorySmokeTests.swift`
- `scripts/phase2-public-skill-smoke.sh`
- `docs/Task-detail/2026-05-24-phase-2-public-skill-repository-compatibility.md`
- `docs/superpowers/specs/2026-05-24-phase-2-public-skill-repository-compatibility.md`
- `docs/superpowers/plans/2026-05-24-phase-2-public-skill-repository-compatibility.md`
- `docs/Task_history.md`
- `docs/v2-refactor-master-todolist.md`
- `README.md`
- `AGENTS.md`
- `CLAUDE.md`

## 测试与验证结果

- `swift test --package-path SliceAIKit --filter CapabilitiesTests.SkillDirectoryScannerTests/test_scannerFindsKnownCollectionLayoutsUnderSkillsDirectory`：先红灯，旧实现返回空集合；修复后通过。
- `swift test --package-path SliceAIKit --filter CapabilitiesTests.SkillDirectoryScannerTests`：通过，5 tests，0 failures。
- `swift test --package-path SliceAIKit --filter CapabilitiesTests.LocalSkillRegistryTests`：通过，8 tests，0 failures。
- `swift test --package-path SliceAIKit --filter CapabilitiesTests.PublicSkillRepositorySmokeTests`：无 env 时通过并 skip，保证默认测试不联网。
- `bash scripts/phase2-public-skill-smoke.sh`：通过，3 repositories，9 public skills。
- `swift test --package-path SliceAIKit`：通过，798 tests，1 skipped，0 failures。
- `swiftlint lint --strict`：通过，0 violations，0 serious。
- `git diff --check`：通过，无输出。

公开 smoke 覆盖：

- `anthropics/skills@690f15cac7f7b4c055c5ab109c79ed9259934081`：`docx`、`frontend-design`、`mcp-builder`
- `openai/skills@b0401f07213a66414d84a65cb50c1d226f99485a`：`openai-docs`、`pdf`、`security-threat-model`
- `jMerta/codex-skills@1be063de2a730d61133e957dfc01a670cce7abd4`：`agents-md`、`bug-triage`、`plan-work`

## 问题与处理

- 发现真实兼容缺口：OpenAI 官方 `openai/skills` 仓库使用 `skills/.curated/<skill>/SKILL.md` 布局，旧 scanner 只扫描 `skills/<skill>/SKILL.md`，无法发现这些 skill。
- 修复方式：`SkillDirectoryScanner` 新增有界 collection parent 支持，仅额外扫描 `skills/.curated` 和 `skills/.system` 的直接子目录，不做任意递归。
- 安全边界不变：symlink 越界仍由现有 root containment 检查拒绝；公开仓库 scripts 不执行，supporting files 不进入模型 payload。

## 任务结果

完成。公开 Anthropic / OpenAI / Codex skill 仓库自动化 smoke 已通过；本任务验证的是 MVP 的扫描、解析、启用和 `SKILL.md` 按需加载兼容性，不代表 supporting files、scripts、marketplace 或真实 LLM 运行链路已经完成。
