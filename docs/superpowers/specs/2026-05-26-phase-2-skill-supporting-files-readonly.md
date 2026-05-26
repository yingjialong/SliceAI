# Phase 2 Skill Supporting Files Read-Only Loading Spec

## 目标

为 SliceAI Skill Registry 增加 supporting files 的安全只读加载能力，让已绑定 Agent Tool 的模型在加载 `SKILL.md` 后，可以按需读取 skill 包内的参考资料和文本模板。该能力补齐真实 Codex / Anthropic 风格 skill 的渐进式披露链路，但不扩大到脚本执行或 marketplace。

## 依据

OpenAI Codex Skills 文档定义 skill 为包含 `SKILL.md` 的目录，并允许可选 `scripts/`、`references/`、`assets/`、`agents/openai.yaml`。Codex 的核心原则是渐进式披露：先暴露 name / description / path，使用时再读取完整指令。本 spec 延续该原则：supporting files 只在模型明确调用时读取。

## 范围

本切片包含：

- Registry 扫描并索引可读 supporting files。
- Registry 提供只读加载 API。
- AgentExecutor 新增 provider-visible pseudo-tool。
- Agent prompt metadata 暴露可读资源路径。
- 测试覆盖路径安全、资源过滤、Agent pseudo-tool 成功和拒绝路径。
- 文档同步当前状态。

本切片不包含：

- 执行 `scripts/`。
- 解析 `agents/openai.yaml` 的 UI metadata / dependencies / policy。
- 读取二进制 asset 进入模型。
- 远端安装、marketplace、自动更新或 plugin 打包。
- DisplayMode、TTS、English Tutor。

## 资源模型

`Skill.resources` 继续使用现有 `SkillResource(relativePath:mimeType:)`。本切片不修改持久化 schema，因为 resources 是 registry snapshot 的运行期派生数据，不写入 `config-v2.json`。

可索引资源：

- `references/**` 下的 UTF-8 文本文件。
- `assets/**` 下常见文本文件。

不可索引资源：

- `scripts/**`。
- `agents/**`。
- `SKILL.md`。
- 隐藏系统文件，例如 `.DS_Store`。
- 符号链接越出 skill 根目录的文件。
- 明显二进制或未知扩展文件。

## 读取 API

在 `SkillRegistryProtocol` 增加：

```swift
func loadSkillResource(id: String, relativePath: String) async throws -> SkillResourcePayload
```

`SkillResourcePayload` 包含 skill id、canonical name、relativePath、absoluteURL、mimeType 和 UTF-8 content。

读取规则：

- `id` 必须指向 enabled 且未 shadowed 的 skill。
- `relativePath` 必须是相对路径，不能为空，不能包含 `..`。
- 目标路径必须在 `Skill.resources` 中。
- 解析符号链接后的目标必须仍在 skill 根目录内。
- 单文件最大 64 KiB。
- 文件必须可解码为 UTF-8。

## Agent Tool 行为

当 Agent Tool 绑定的 skill 至少有一个可读 resource 时，Provider 可见工具列表新增：

```text
sliceai_load_skill_resource
```

输入 schema：

```json
{
  "type": "object",
  "properties": {
    "name": { "type": "string" },
    "path": { "type": "string" }
  },
  "required": ["name", "path"],
  "additionalProperties": false
}
```

运行约束：

- 只能读取当前 Agent Tool 已绑定 skill 的资源。
- 必须先通过 `sliceai_load_skill` 加载同名 skill；否则返回错误，提醒先加载 skill。
- 不进入 MCP allowlist、PermissionBroker 或 MCP client。
- UI lifecycle 使用 synthetic ref：`sliceai.load_skill_resource`。
- 回填给模型的内容走现有 `sanitizeToolMessageContent`，继续脱敏并按 16 KiB 模型 tool message 上限裁剪。

## Prompt Metadata

初始 prompt 的 skill metadata block 增加 resources：

```text
- name: writing
  description: ...
  path: /.../SKILL.md
  resources:
    - references/style.md
    - assets/template.md
```

Footer 增加约束：

- 先 `sliceai_load_skill`，再按需 `sliceai_load_skill_resource`。
- 只能请求 metadata 中列出的路径。
- 不要请求或假设 scripts 已执行。

Metadata block 仍受 8,000 字符预算约束；name/path 优先保留，description 和 resources 可截断。

## 安全与 KISS 决策

- 不新增用户级文件权限弹窗：skill root 是用户显式配置来源，且读取严格限制在 enabled skill 内部。
- 不读取 scripts：脚本执行和脚本内容暴露都可能引入更高风险，留给后续独立 spec。
- 不做二进制 asset 编码：图片、PDF、音频等会迅速膨胀模型上下文，后续若需要应走专门 resource/attachment 设计。
- 不递归扫描整个 skill 根：只扫描 `references/` 和文本型 `assets/`，降低误读私有文件风险。

## 验收标准

- Registry focused tests 证明 resources 索引、读取、路径拒绝、脚本拒绝和 symlink 越界拒绝。
- Agent focused tests 证明 pseudo-tool 可见、必须先加载 skill、成功读取资源、不触发 MCP。
- 既有 Skill E2E 和 public smoke 不回退。
- 全量 SwiftPM tests、SwiftLint strict、`git diff --check` 通过。

