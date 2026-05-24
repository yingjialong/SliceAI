# SkillRegistry 模块

## 模块职责

SkillRegistry 负责扫描用户配置的本地 skill roots，解析 Claude / Codex 风格 `SKILL.md`，生成可供 Settings 和 AgentExecutor 使用的 registry snapshot。

## MVP 边界

- 只读取 `SKILL.md`。
- 不执行 `scripts/`。
- 不读取 `references/` / `assets/` supporting files。
- 只支持 Agent Tool 绑定，Prompt Tool 暂不支持 skill。
- 每个 Agent Tool 最多绑定 5 个 enabled skills。
- 通过概念工具 `sliceai.load_skill` 渐进式加载完整指令；发送给 OpenAI-compatible provider 的函数名是 `sliceai_load_skill`。

## 目录扫描规则

`LocalSkillRegistry` 通过 `SkillDirectoryScanner` 对每个 enabled source root 执行一层扫描：

1. `root/SKILL.md`
2. `root/*/SKILL.md`
3. `root/skills/*/SKILL.md`
4. `root/.claude/skills/*/SKILL.md`
5. `root/.agents/skills/*/SKILL.md`
6. `root/.codex/skills/*/SKILL.md`

scanner 会解析 symlink，并要求候选目录和 `SKILL.md` 的真实路径仍位于 source root 内。越界候选不会进入 registry，会生成 `.symlinkEscape` 诊断。source root 不存在或不可读会生成 `.sourceUnreadable` 诊断。

## 运行时流程

1. Settings 通过 `SkillsPage` 管理 skill roots、查看 skill 状态与诊断，并写入 `Configuration.skillSettings`。
2. `LocalSkillRegistry.snapshot()` 按 source order 解析候选 skill，合并 frontmatter、用户 override、大小限制和 duplicate name 规则。
3. Agent Tool 编辑器只展示已绑定行；用户用加号新增一条绑定，行内下拉菜单从 `.enabled` skills 中选择，减号删除该行，并把结果写入 `AgentTool.skills`。
4. AgentExecutor 创建 tool catalog 时解析当前 Agent Tool 绑定的 enabled skills，向模型暴露 metadata block。
5. 模型需要完整指令时调用 `sliceai_load_skill`。执行器在本地处理该 pseudo-tool，不走 MCP allowlist、permission gate 或 MCP client。
6. ResultPanel 继续使用现有 `toolCallProposed` / `toolCallApproved` / `toolCallResult` / `toolCallError` 生命周期展示加载过程。

## 状态模型

- `.enabled`：可展示、可绑定、可加载。
- `.disabled`：用户 override off。
- `.defaultDisabled`：frontmatter 缺 `description` 或 `disable-model-invocation: true`，除非用户 override on。
- `.parseError`：`SKILL.md` frontmatter 或字段解析失败，不可加载。
- `.tooLarge`：`SKILL.md` 超过 128 KiB，不可加载。
- `.shadowed`：同名 enabled skill 中较低优先级版本被隐藏，不可加载。
- `.sourceError`：预留给 source 级错误。

## 技术债务

- supporting files 只索引、不读取；后续需要按权限模型补 `references/` / `assets/` 读取。
- frontmatter parser 是最小 YAML 子集；后续可在 Swift 6.0 / macOS 14 基线允许时复评估 YAML 库。
- `allowed-tools` 目前只展示，不授予本地工具权限。
- duplicate name 语义当前按 source order 处理；后续兼容更多 Codex / Claude skill 约定时需要复评估。
- 暂未支持 `agents/openai.yaml`、marketplace、远端安装、脚本执行和自动更新。
