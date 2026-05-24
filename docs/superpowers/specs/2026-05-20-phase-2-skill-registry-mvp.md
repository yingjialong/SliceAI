# Phase 2 Skill Registry MVP Spec

## 1. 背景

Phase 1 MCP + Context 主干已完成 `v0.3.0` release prep，GitHub Actions 已生成 draft release，但用户明确暂缓人工发布，继续后续开发。Phase 2 在总 roadmap 中仍是 Directional Outline，不能直接实现 English Tutor、DisplayMode 或完整 Skill runtime。

本 spec 将 Phase 2 第一个切片冻结为 **Skill Registry MVP**：让 SliceAI 能扫描用户指定目录中的 Claude / Codex 风格 skill 包，在 Settings 中展示和启停，并允许 **Agent Tool** 绑定最多 5 个 skills。运行时模型先看到绑定 skills 的 `name / description / path` 元数据，只有决定使用时才通过内置 pseudo-tool `sliceai.load_skill` 渐进式加载完整 `SKILL.md` 指令。

本 spec 覆盖设计、数据模型、错误模型、UI、执行流和测试策略；不进入业务代码实现计划。后续实现前仍需产出 implementation plan。

## 2. 调研结论

### 2.1 官方行为基线

OpenAI Codex Skills 官方文档说明：skill 是包含 `SKILL.md` 的目录，可带 `scripts/`、`references/`、`assets/` 和 `agents/openai.yaml`；Codex 使用 progressive disclosure，初始只给模型 `name / description / file path`，选中 skill 后才加载完整 `SKILL.md`。Codex 初始 skill 列表有上下文预算，未知窗口时按约 8,000 字符处理。参考：[Codex Agent Skills](https://developers.openai.com/codex/skills)。

Claude Code Skills 文档说明：skill 目录包含 `SKILL.md`，可带 supporting files；`allowed-tools` 等 frontmatter 属于 Claude Code 的权限体系，不应直接搬进 SliceAI 的 PermissionGraph。参考：[Claude Code Skills](https://code.claude.com/docs/en/skills)。

### 2.2 开源项目复用判断

- [1amageek/swift-skills](https://github.com/1amageek/swift-skills)：方向匹配，覆盖 Swift 侧 skill bundle / parser / validator / supporting files，但当前要求 Swift 6.2 与 macOS 15+，高于 SliceAI 的 Swift 6.0 / macOS 14+ 基线。直接引入会改平台约束，fork 降级会形成长期维护成本。
- [vercel-labs/skills](https://github.com/vercel-labs/skills)：对 Claude / Codex 目录规则和 package 管理有参考价值，但实现是 TypeScript CLI，不适合作为 macOS Swift runtime 依赖。

结论：本 MVP 不直接引入外部 runtime 库，采用最小自研 loader。外部项目作为兼容性参考；supporting files 的渐进式读取作为明确技术债务保留。

## 3. 目标

本 MVP 要完成以下闭环：

1. 用户可在 Settings 中添加多个本地 skill root。
2. Registry 可扫描 Claude / Codex 常见 skill 目录结构并解析 `SKILL.md`。
3. Settings 可展示 skill 列表、来源、解析状态、启停状态和错误信息。
4. Agent Tool 编辑器可从 enabled skills 中绑定最多 5 个 skills。
5. AgentExecutor 初始 prompt 只暴露绑定 skills 的元数据清单。
6. 模型可通过内置 pseudo-tool `sliceai.load_skill` 按需加载绑定 skill 的完整 `SKILL.md` 指令。
7. `load_skill` 调用在 ResultPanel tool-call lifecycle 中可见，同一 invocation 对同一 skill 去重。
8. 现有 MCP 权限、ContextProviders、PromptTool 和 DisplayMode 语义不被改变。

## 4. 非目标

本 MVP 明确不做：

- Marketplace、远端安装、GitHub 拉取、自动更新和插件分发。
- skill 内脚本执行、依赖安装、后台任务和 sandboxed process runtime。
- `references/`、`assets/`、`scripts/` 等 supporting files 的模型按需读取。
- Prompt Tool 绑定 skill；MVP 只支持 Agent Tool。
- 按全局 description 自动匹配所有 enabled skills；模型只能在当前 Agent Tool 绑定的 skills 中选择。
- English Tutor 全流程。
- `replace / bubble / structured / silent` DisplayMode 的完整 UI 或输出分发实现。
- TTS、structured form schema、AX `setSelectedText` 成功率矩阵。

## 5. 核心决策

### 5.1 Skill 来源

用户可配置多个本地 root。root 既可以是一个单独 skill 目录，也可以是一个 skills collection 目录，也可以是项目根目录。Registry 只做本地扫描，不联网、不安装、不执行。

默认不自动扫描任意用户目录。若用户希望使用 `~/.agents/skills`、`~/.claude/skills`、`~/.codex/skills` 或某个仓库的 `.agents/skills`，需要在 SliceAI Settings 中显式添加对应 root 或其项目根。

### 5.2 身份和冲突

Skill 的用户可见身份为 `canonicalName`：

1. 优先读取 `SKILL.md` frontmatter 的 `name`。
2. 缺少 `name` 时使用 skill 目录名。
3. `canonicalName` 需要在 active registry 中唯一。

多个 root 出现相同 `canonicalName` 时，按 root 排序选择最高优先级的 skill 作为 active skill；其余重复项标记为 `shadowed`，在 Settings 中显示但不能绑定到 Agent Tool。这样牺牲了 Codex “同名 skill 可同时出现在 selector” 的完整语义，但避免 Tool 引用时出现二义性，符合 SliceAI 当前 `Tool` 配置需要稳定引用的要求。

### 5.3 启停语义

配置中保存 optional override：

- 无 override：使用 `SKILL.md` 默认语义。
- `.on`：用户显式允许此 skill 供 Agent Tool 绑定，即使 frontmatter 声明 `disable-model-invocation: true`。
- `.off`：用户显式禁用此 skill，不能绑定，运行时也不可加载。

`disable-model-invocation: true` 在 SliceAI 中解释为默认不暴露给模型选择，但用户可在 Skills 设置页显式开启。`allowed-tools`、`user-invocable` 等字段先展示和保留，不授予任何权限。

### 5.4 渐进式加载

每个 Agent Tool 保存一组绑定 skills。执行该 Tool 时：

1. 初始 prompt 只包含绑定 skills 的 `name / description / source path` 清单。
2. Agent 可调用 pseudo-tool `sliceai.load_skill`，参数为 `name`。
3. `sliceai.load_skill` 只允许加载当前 Tool 绑定且当前 enabled 的 skill。
4. 返回完整 `SKILL.md` 指令正文和 frontmatter 摘要。
5. 同一 invocation 中同一 skill 只返回一次完整内容；重复调用返回 “already loaded” 提示。

此机制保留 skill 的核心优势：模型不必一开始吞下所有指令，只有需要时才加载。

## 6. 数据模型

### 6.1 Canonical Skill 类型

`SliceCore/Skill.swift` 是 canonical 类型归属。`Capabilities/Skills/SkillRegistryProtocol.swift` 中重复定义的小型 `Skill` 必须删除或迁移为使用 `SliceCore.Skill`，避免双模型长期存在。

建议模型：

```swift
public struct Skill: Identifiable, Sendable, Codable, Equatable {
    public let id: String              // 稳定 id，MVP 中等于 canonicalName
    public let canonicalName: String
    public let path: URL               // skill 目录
    public let skillFile: URL          // SKILL.md 绝对路径
    public var manifest: SkillManifest
    public var resources: [SkillResource]
    public var provenance: Provenance
    public var source: SkillSourceRef
    public var state: SkillRegistryState
}
```

`id` 与 `canonicalName` 在 MVP 中保持一致，后续如果引入 package identity 或签名 id，可在不破坏 UI 引用的前提下扩展。

`SkillSourceRef` 和 `SkillRegistryState` 是运行时 registry snapshot 的一部分：

```swift
public struct SkillSourceRef: Sendable, Codable, Equatable {
    public let sourceId: String
    public let rootPath: String
}

public enum SkillRegistryState: String, Sendable, Codable {
    case enabled
    case disabled
    case defaultDisabled
    case parseError
    case shadowed
    case sourceError
    case tooLarge
}
```

这些状态不直接表达用户偏好；用户偏好只由 `SkillSettings.overrides` 表示。`SkillRegistryState` 是 registry 将 source、frontmatter、override、冲突和解析结果合并后的可展示状态。

### 6.2 SkillManifest

`SkillManifest` 保存已解析 frontmatter 和 body 摘要：

```swift
public struct SkillManifest: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let disableModelInvocation: Bool
    public let allowedTools: [String]
    public let userInvocable: Bool?
    public let rawFrontmatter: String
    public let instructionsCharacterCount: Int
}
```

说明：

- `name` 可由目录名 fallback。
- `description` 是模型选择 skill 的关键字段；缺失时 skill 标记为 parse warning，默认不可绑定。
- `allowedTools` 只展示，不映射为 SliceAI `Permission`。
- `rawFrontmatter` 用于调试和未来兼容，不在日志中原样打印。

### 6.3 SkillSettings

新增 `Configuration.skillSettings`：

```swift
public struct SkillSettings: Sendable, Codable, Equatable {
    public var sources: [SkillSource]
    public var overrides: [String: SkillEnablementOverride]
}

public struct SkillSource: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var displayName: String
    public var rootPath: String
    public var isEnabled: Bool
    public var order: Int
}

public enum SkillEnablementOverride: String, Sendable, Codable {
    case on
    case off
}
```

`Configuration.currentSchemaVersion` 需要升级。旧配置缺少 `skillSettings` 时默认 `sources = []`、`overrides = [:]`，不触发迁移失败。

### 6.4 Agent Tool 绑定

现有 `AgentTool.skill: SkillReference?` 只能表达一个 skill。MVP 需要升级为多绑定：

```swift
public struct AgentTool: Sendable, Codable, Equatable {
    public var skills: [SkillReference]
    // 其它既有字段保持不变
}

public struct SkillReference: Sendable, Codable, Equatable {
    public let id: String              // canonicalName
    public let pinVersion: String?     // MVP 保留但不实现版本选择
}
```

兼容规则：

- decoder 读取旧字段 `skill` 时转换为 `skills = [skill]`。
- encoder 只写新字段 `skills`。
- 每个 Agent Tool 最多保存 5 个 `SkillReference`。
- Prompt Tool 不新增 skill 字段。

## 7. Registry 扫描与解析

### 7.1 扫描入口

真实实现位于 `Capabilities/Skills/`，由 actor `LocalSkillRegistry` 提供：

```swift
public protocol SkillRegistryProtocol: Sendable {
    func snapshot() async throws -> SkillRegistrySnapshot
    func findSkill(id: String) async throws -> Skill?
    func loadSkillInstructions(id: String) async throws -> SkillInstructionPayload
}
```

`snapshot()` 给 Settings 和 AgentExecutor 获取稳定视图。`loadSkillInstructions` 只返回 `SKILL.md` body，不读取 supporting files。

Snapshot 和 load payload 建议定义为：

```swift
public struct SkillRegistrySnapshot: Sendable, Codable, Equatable {
    public let sources: [SkillSource]
    public let skills: [Skill]
    public let diagnostics: [SkillRegistryDiagnostic]
    public let generatedAt: Date
}

public struct SkillInstructionPayload: Sendable, Codable, Equatable {
    public let id: String
    public let canonicalName: String
    public let skillFile: URL
    public let frontmatterSummary: SkillManifest
    public let instructions: String
}

public struct SkillRegistryDiagnostic: Sendable, Codable, Equatable {
    public let code: SkillRegistryDiagnosticCode
    public let sourceId: String?
    public let path: String?
    public let message: String
}
```

`message` 面向 UI 展示，必须是短文案；详细底层错误仅进入脱敏日志。

### 7.2 扫描规则

对每个 enabled source root，解析绝对路径并执行以下候选发现：

1. `root/SKILL.md`：root 本身是一个 skill。
2. `root/*/SKILL.md`：root 是 skills collection 目录，例如 `~/.agents/skills`。
3. `root/skills/*/SKILL.md`。
4. `root/.claude/skills/*/SKILL.md`。
5. `root/.agents/skills/*/SKILL.md`。
6. `root/.codex/skills/*/SKILL.md`。

不做无限递归，不扫描深层 `node_modules`、构建产物或任意隐藏目录。每个 root 默认最多处理 200 个候选，超过部分记录 diagnostic，避免误把大目录配置成 root 后卡住 App。

### 7.3 Symlink 策略

MVP 支持 symlinked skill folder，但解析后的真实路径必须仍位于当前 source root 下。若 symlink target 越界，candidate 标记为安全错误并不加载。用户如果确实要使用外部 target，应把 target 本身作为新的 source root 添加。

这个策略比 Codex 的 symlink 行为更保守，但符合 SliceAI 本地 App 的安全边界。

### 7.4 `SKILL.md` 解析

MVP 实现一个小型 frontmatter parser：

- `SKILL.md` 可以以 YAML frontmatter 开头：第一行 `---`，后续直到单独一行 `---`。
- 支持顶层 scalar：`name`、`description`、`disable-model-invocation`、`user-invocable`。
- 支持 `allowed-tools` 的 string 或简单 list。
- 未识别字段保留在 `rawFrontmatter`，不影响解析。
- 缺少 closing marker、布尔值非法、frontmatter 超过大小限制时标记 parse error。

不引入完整 YAML 依赖。若后续发现真实 Claude/Codex skills 大量使用复杂 YAML，再重新评估引入轻量 YAML parser 或移植 SwiftSkill。

### 7.5 大小限制

- 单个 `SKILL.md` 最大 128 KiB。超过则标记为 `tooLarge`，不进入可绑定列表。
- 初始 skills 元数据清单总预算 8,000 字符。
- `load_skill` 返回完整 `SKILL.md` 指令正文；不会静默截断。若文件超过 128 KiB，registry 在扫描阶段已拒绝。

不静默截断完整指令是刻意设计：截断后的 skill 可能丢失安全约束，比直接报错更危险。

## 8. AgentExecutor 运行时设计

### 8.1 Tool catalog 扩展

现有 AgentExecutor 从 MCP allowlist 构造 `ChatTool` catalog。MVP 在 catalog 中追加一个内置 pseudo-tool。用户可见概念名是 `sliceai.load_skill`；发送给 OpenAI-compatible provider 的 function name 使用 `sliceai_load_skill`，因为 function name 只能包含字母、数字、下划线和短横线：

```text
name: sliceai_load_skill
description: Load the full instructions for one of the skills bound to this Agent Tool.
input_schema:
  type: object
  properties:
    name:
      type: string
      description: The exact skill name from the available skills list.
  required: ["name"]
```

只有 `agent.skills` 非空且所有绑定 skill 都解析成功时，才暴露该 pseudo-tool。

### 8.2 Pseudo-tool 不走 MCP

`sliceai.load_skill` 不属于 MCP：

- 不进入 `AgentTool.mcpAllowlist`。
- 不需要 MCP server 配置。
- 不触发 `.mcp` Permission。
- 不调用 `MCPClientProtocol.call`。

它仍走 ResultPanel tool-call lifecycle，让用户能看到模型加载了哪个 skill。

### 8.3 Agent Tool prompt 初始化

AgentPromptBuilder 在 user prompt 或 system prompt 后追加一个受控区块：

```text
Available SliceAI skills for this tool:
- name: ...
  description: ...
  path: ...

Use sliceai_load_skill with the exact skill name when a skill is relevant.
Do not assume instructions from a skill until you load it.
```

清单按 Agent Tool 中绑定顺序输出，最多 5 个。若 description 导致清单超过 8,000 字符，按顺序保留所有 name/path，逐条截断 description，并在日志与事件摘要中记录 metadata truncation。

### 8.4 加载状态

每次 Agent invocation 维护 `loadedSkillNames: Set<String>`：

- 首次 `sliceai.load_skill(name)`：返回完整 instructions。
- 重复加载同名 skill：返回 `Skill already loaded in this invocation.`。
- 请求未绑定 skill：返回 tool error `Skill not bound to this Agent Tool`。
- 请求 disabled / shadowed / parse error skill：运行前配置校验应已阻断；若运行期状态变化导致命中，返回 tool error 并结束本次 tool call。

### 8.5 预算策略

MCP tool-call policy 不控制 `sliceai.load_skill`。原因是加载 skill 是本地 prompt capability，不是外部服务调用；但需要独立限制：

- 每个 invocation 最多成功加载 5 个 skills。
- 同一 skill 重复加载不计入成功加载次数。
- `sliceai.load_skill` 无网络和进程副作用。

若未来增加 `read_skill_resource` 或 script execution，必须引入新的 policy 和权限 gate。

## 9. Settings UI 设计

### 9.1 Skills 设置页

新增 Settings sidebar 页面 `Skills`：

- Source roots 列表：添加、删除、启用/停用、上移/下移。
- Skill 列表：显示 name、description、source、path、状态。
- 状态包括：enabled、disabled、default-disabled、parse-error、shadowed、source-error、too-large。
- 每个 skill 提供 “Open in Finder”。
- 解析错误以短文案展示，详细错误只写脱敏日志。

Settings 页面不执行 skill 脚本，不读取 references 内容。

### 9.2 Agent Tool 编辑器

`ToolEditorView` 的 Agent 分支新增 “Skills” 分组：

- 不一次性列出全部 enabled active skills；用户点击加号新增一条 skill 绑定行。
- 每条绑定行使用下拉菜单选择 skill，并提供减号删除该绑定。
- 最多选择 5 个。
- 下拉菜单排除其它行已选择的 skill，避免重复绑定。
- 显示 description 和来源路径摘要。
- 选中 shadowed / disabled / parse-error skill 不允许保存。
- Prompt Tool 不显示该分组。

### 9.3 保存语义

所有配置写入现有 `config-v2.json`：

- `Configuration.skillSettings.sources`
- `Configuration.skillSettings.overrides`
- `AgentTool.skills`

不新增 registry cache。扫描结果每次从文件系统动态生成。Settings 页面需要异步刷新 registry snapshot，并在 source 修改后重新扫描。

## 10. 错误模型与日志

新增或复用 `SliceError.configuration` / `SliceError.execution` 表达以下错误：

- source root 不存在或不可读。
- `SKILL.md` frontmatter 无效。
- `SKILL.md` 超过大小限制。
- canonical name 冲突导致 shadowed。
- Agent Tool 绑定的 skill 缺失、禁用或解析失败。
- `sliceai.load_skill` 请求未绑定 skill。

日志要求：

- 日志只打印固定字段和脱敏路径摘要，不打印完整 `SKILL.md` body。
- `load_skill` 成功日志记录 tool id、skill name、character count。
- parse error 记录 source id、skill path 摘要、错误 code。
- Settings UI 可显示面向用户的错误文案，但不泄露 `SKILL.md` 具体内容。

实现时所有新增函数遵守项目要求：函数级中文注释，复杂逻辑处添加必要中文注释，关键路径添加必要日志。

## 11. 权限与安全边界

MVP 的安全原则是 “读取本地文本指令，不执行任何代码”：

- `allowed-tools` 不授予 SliceAI 权限。
- skill scripts 不运行。
- references/assets 不读取。
- symlink target 越界阻断。
- `load_skill` 只能读取当前 Agent Tool 绑定 skills。
- Prompt injection 风险通过 Tool 绑定收窄；模型看不到全局所有 skills。

如果后续实现 supporting file 读取，需要新增 `sliceai.list_skill_resources` 与 `sliceai.read_skill_resource`，并把路径规范化、大小限制、MIME 限制和用户可见 lifecycle 单独纳入 spec。

## 12. 与现有代码的关系

### 12.1 需要改动的主要区域

- `SliceCore/Skill.swift`：收敛 canonical Skill 模型。
- `SliceCore/Configuration.swift`：新增 `skillSettings`，升级 schema。
- `SliceCore/ToolKind.swift`：`AgentTool.skill` 升级为 `AgentTool.skills`，提供 decode 兼容。
- `Capabilities/Skills/*`：实现 `LocalSkillRegistry`、parser、scanner、snapshot、diagnostics。
- `Orchestration/Executors/AgentExecutor*`：扩展 tool catalog，处理 `sliceai.load_skill`。
- `Orchestration/Executors/AgentPromptBuilder.swift`：注入绑定 skills metadata 清单。
- `SettingsUI`：新增 `SkillsPage`、ViewModel，Agent Tool 编辑器新增 Skills 分组。
- `SliceAIApp/AppContainer.swift`：构造真实 `LocalSkillRegistry` 并注入 AgentExecutor / ExecutionEngine。

### 12.2 不应改动的区域

- `MCPClient` 传输和 store 语义。
- `ContextProviders` provider 语义。
- `PromptExecutor` 单次 prompt 路径。
- `OutputDispatcher` DisplayMode 行为。
- Release draft / tag / artifact。

## 13. 技术债务

本 MVP 故意留下以下债务，必须在任务文档中记录：

1. **supporting files 渐进式读取**：MVP 不实现 `references/`、`assets/`、`scripts/` 的按需读取。后续需要 `list_skill_resources/read_skill_resource`，并定义路径沙箱、MIME、大小、UI lifecycle 和权限策略。
2. **Skill 脚本执行 runtime**：MVP 不执行 `scripts/`、不安装依赖、不启动后台任务。后续若要支持，需要先设计 sandbox、进程生命周期、日志、权限确认、超时和依赖缓存策略。
3. **Marketplace / 远端安装分发**：MVP 只扫描用户显式添加的本地目录。后续若要支持 marketplace、GitHub 拉取、自动更新或社区分发，需要先补 trust model、签名/校验、版本 pinning、回滚和 UI 审核流程。
4. **完整 YAML frontmatter**：MVP 使用小型 parser。若真实 skills 依赖复杂 YAML，需要引入或移植 parser。
5. **SwiftSkill 复用评估**：当 SliceAI 基线升级到 Swift 6.2 / macOS 15+，或 SwiftSkill 支持 Swift 6.0 / macOS 14 时，重新评估替换自研 parser。
6. **Codex duplicate name 完整语义**：MVP 对同名 skill 使用 root precedence + shadowing；Codex 允许同名 skill 同时出现 selector。后续如果需要完全兼容，应改为 path-scoped binding。
7. **Codex `agents/openai.yaml`**：MVP 不解析 UI metadata、dependencies 和 `allow_implicit_invocation`。后续可用于更好的 Settings 展示和 MCP dependency 提示。
8. **Skill provenance / signing**：MVP 将用户添加 root 视为 self-managed，本轮不做签名校验和 community trust。

## 14. 测试策略

### 14.1 SliceCoreTests

- `SkillSettings` Codable round-trip。
- 旧 `AgentTool.skill` decode 为新 `AgentTool.skills`。
- `AgentTool.skills` 超过 5 个时配置校验失败。
- `Configuration` 缺 `skillSettings` 时默认值正确。

### 14.2 CapabilitiesTests

- 解析合法 `SKILL.md`：name、description、body。
- name 缺失时 fallback 目录名。
- description 缺失时状态为 default-disabled / warning。
- `disable-model-invocation` 默认禁用模型可见性。
- `allowed-tools` string 和 list 均能保留。
- root 扫描覆盖：root skill、collection root、`.claude/skills`、`.agents/skills`、`.codex/skills`、`skills`。
- 不做深层递归。
- symlink target 越界报安全错误。
- 重名 skill 按 source order shadow。
- 大文件拒绝。

### 14.3 OrchestrationTests

- Agent Tool 绑定 skills 时，初始 messages 包含 metadata 清单。
- 未绑定 skills 时不暴露 `sliceai.load_skill`。
- `sliceai.load_skill` 成功返回完整 instructions。
- 未绑定 skill 请求被拒绝。
- 同一 invocation 重复加载同一 skill 返回 already loaded。
- pseudo-tool 不调用 MCPClient、不触发 MCP PermissionBroker gate。
- metadata 清单超过 8,000 字符时 description 截断但 name/path 保留。

### 14.4 SettingsUITests

- Skills ViewModel 添加 / 删除 / 排序 source roots。
- 解析错误在列表中可见。
- Agent Tool skills 通过加号逐条新增，最多 5 个。
- 绑定行下拉菜单排除其它行已选择的 skill，减号删除后写回 `AgentTool.skills`。
- Prompt Tool 不显示 Skills 分组。
- 保存 Agent Tool 时写入 `AgentTool.skills`。

### 14.5 Gate

实现完成后需要至少通过：

```bash
swift test --package-path SliceAIKit --filter 'SliceCoreTests|CapabilitiesTests|OrchestrationTests|SettingsUITests'
swift test --package-path SliceAIKit
swiftlint lint --strict
git diff --check
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

## 15. 验收标准

MVP 完成时必须满足：

1. 用户可添加至少两个 skill root，并在 Settings 中看到合并后的 active skills 与 shadowed / parse-error 项。
2. Claude / Codex 常见 `SKILL.md` 最小字段可解析。
3. Agent Tool 可绑定最多 5 个 enabled skills。
4. 运行 Agent Tool 时，模型初始只看到绑定 skills 的 metadata。
5. 模型调用 `sliceai.load_skill` 后能读取完整 `SKILL.md` 指令。
6. ResultPanel 可看到 `sliceai.load_skill` 生命周期行。
7. 未绑定、禁用、解析失败或 shadowed skill 不能被运行时加载。
8. Prompt Tool、MCP allowlist、MCP PermissionBroker 和 DisplayMode 行为保持不变。

## 16. 实施顺序建议

后续 plan 应按以下顺序拆分：

1. SliceCore schema 和 Codable 兼容。
2. `SKILL.md` parser 与扫描器 TDD。
3. `LocalSkillRegistry` actor 与 diagnostics。
4. AgentExecutor pseudo-tool 与 prompt metadata 注入。
5. Skills Settings page。
6. Agent Tool editor skills binding。
7. AppContainer wiring。
8. 文档、fixtures、全量 gate。

该顺序先稳定数据契约和 registry，再接执行链，最后接 UI，避免 UI 先行导致模型边界反复改动。
