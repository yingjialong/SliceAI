# Phase 2 Public Skill Repository Compatibility Spec

## 背景

SliceAI 已完成 Skill Registry MVP 和真实本地 Skill E2E。下一步需要验证公开 Anthropic / Codex skill 仓库中的真实目录形态，而不是继续依赖手写 fixture。验证必须可重复、可审计，并且不能让常规单元测试依赖 GitHub 网络状态。

## 目标

用自动化 smoke 验证 SliceAI 当前 Skill Registry MVP 能处理 3 个公开仓库快照中的真实 `SKILL.md`：

- `anthropics/skills`
- `openai/skills`
- `jMerta/codex-skills`

每个仓库固定 commit，并只 sparse checkout 少量样本目录。Smoke 运行时使用生产 `LocalSkillRegistry`、`SkillDirectoryScanner` 和 `SkillMarkdownParser`，不使用 mock registry。

## 非目标

- 不执行公开仓库中的 `scripts/` 或任意可执行文件。
- 不读取 `references/`、`assets/`、`agents/openai.yaml` 到模型 payload。
- 不把 `allowed-tools`、OpenAI `agents/openai.yaml` dependencies 或 Claude hooks 映射为 SliceAI Permission。
- 不实现 marketplace、远端安装、自动更新或完整 plugin 体系。
- 不把 smoke 放进默认联网测试；默认 `swift test` 必须离线可跑。

## 公开来源与固定样本

| 来源 | 仓库 | commit | 预期 skill names |
|---|---|---|---|
| Anthropic official | `https://github.com/anthropics/skills.git` | `690f15cac7f7b4c055c5ab109c79ed9259934081` | `docx`、`frontend-design`、`mcp-builder` |
| OpenAI official | `https://github.com/openai/skills.git` | `b0401f07213a66414d84a65cb50c1d226f99485a` | `openai-docs`、`pdf`、`security-threat-model` |
| Codex community | `https://github.com/jMerta/codex-skills.git` | `1be063de2a730d61133e957dfc01a670cce7abd4` | `agents-md`、`bug-triage`、`plan-work` |

## 兼容性要求

1. Scanner 必须继续支持已落地布局：root `SKILL.md`、`root/<skill>/SKILL.md`、`skills/<skill>/SKILL.md`、`.claude/skills/<skill>/SKILL.md`、`.agents/skills/<skill>/SKILL.md`、`.codex/skills/<skill>/SKILL.md`。
2. Scanner 需要新增对公开仓库 collection 布局的支持：`skills/.curated/<skill>/SKILL.md` 和 `skills/.system/<skill>/SKILL.md`。
3. Scanner 仍不做无限递归；只在已知 skill parent 下额外扫描一层 collection parent，避免不可控 IO。
4. Symlink 越界检查继续 fail-closed。
5. Parser 对未知 frontmatter 字段保持忽略；已支持的 `allowed-tools`、`disable-model-invocation`、`user-invocable` 继续解析。
6. Opt-in smoke 测试从 manifest JSON 读取本地 repo root 和 expected names；缺少 env 时 skip。

## 验证设计

新增脚本 `scripts/phase2-public-skill-smoke.sh`：

1. 创建临时目录。
2. 对 3 个公开仓库执行 shallow fetch 固定 commit。
3. 使用 sparse checkout 只拉取样本 skill 目录。
4. 写入 manifest JSON，包含 repo id、url、commit、rootPath、expectedNames。
5. 设置 `SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST` 并运行 `swift test --package-path SliceAIKit --filter CapabilitiesTests.PublicSkillRepositorySmokeTests`。
6. 输出固定 commit、样本数量和测试结果，不输出任何 secret。

新增 opt-in XCTest：

1. 无 env 时 `throw XCTSkip(...)`，保证默认 test suite 离线稳定。
2. 读取 manifest JSON，构造 `SkillSettings.sources`。
3. 用 `LocalSkillRegistry` 生成 snapshot。
4. 断言 9 个 expected skill 均为 `.enabled`。
5. 对每个 expected skill 调用 `loadSkillInstructions`，断言 body 非空、`skillFile` 位于对应 repo root 内。

## 风险与处理

- GitHub 网络不稳定：smoke 脚本作为 opt-in 验证；默认 full gate 不联网。
- 公开仓库 HEAD 变动：脚本固定 commit，后续更新样本需要显式修改文档和脚本。
- 公开 skill 过大或 schema 变化：smoke 失败时先记录具体仓库、路径和错误，再决定是否修 SliceAI 兼容层。
- 第三方 skill 不可信：脚本只读取 `SKILL.md`，不执行任何仓库代码。

## 完成标准

- TDD scanner test 先红后绿。
- Opt-in public smoke 在本机通过。
- 默认 `swift test --package-path SliceAIKit` 通过且不联网。
- `swiftlint lint --strict` 和 `git diff --check` 通过。
- README、Task_history、master todolist 和 task detail 记录固定 commit、结果与剩余边界。
