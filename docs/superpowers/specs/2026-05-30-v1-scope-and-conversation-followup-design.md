---
topic: v1-scope-and-conversation-followup
title: v1.0 范围与「续聊 + 历史」设计
status: draft（待用户 review）
kind: scope + design-intent（不含内部架构）
created: 2026-05-30
last_updated: 2026-05-30
source: 2026-05-30 brainstorming 一轮（6 个结构化提问 + 2 个 review 补充）
---

# v1.0 范围与「续聊 + 历史」设计

## 0. 文档定位

- 这是 **v1.0 的范围 + 顺序文档**，同时冻结「续聊 + 历史」这一头号新功能的**边界与设计意图**。
- **不展开**续聊 / 历史的内部架构（数据结构细节、executor 改动、持久化格式、UI 布局）——那些留给 M1 的 feature spec（在 `writing-plans` 之前会再单独 brainstorm 一轮并冻结）。
- 本文件的作用：锁定"v1.0 做什么 / 不做什么 / 按什么顺序做"，并把续聊/历史的**关键边界和不变量**钉死，避免 M1 spec 走偏或把已推后的能力混进来。
- 决策来源：2026-05-30 与用户的 brainstorming 一轮，共 8 个决策（6 个结构化提问 + 2 个 review 补充），完整记录见 §8。

## 1. v1.0 范围

### 1.1 IN（v1.0 必须有）

- **现有核心读取链**：划词浮条 / `⌥Space` 命令面板 → `.prompt` / `.agent` → OpenAI 兼容 SSE 流式结果；window / bubble / replace / tts 各 DisplayMode 维持现状。
- **续聊（conversation follow-up）**：任一 window 结果出来后可多轮追问，带上下文管理（见 §3）。
- **历史（History）**：Settings 里查看过往 LLM 交互（见 §4）。

### 1.2 OUT（全部推到 1.0 之后）

- 原生 Anthropic / Gemini / Ollama provider 与 provider 能力 / 级联（master todolist #20–23）。
- Playground 测试样本 + expected output（#17）、A/B 双栏对比（#18）、Tool 版本历史 / 回滚（#19）。
- Tool Memory 存储 / 检索（#24）、MemoryPage（#25）、Cost Panel（#26）、privacy local-only（#27）。
- InlineReplaceOverlay 的确认 / 撤销浮条。
- `.pipeline` ToolKind、skill `scripts/` 执行、二进制 assets、`agents/openai.yaml` 解析。
- Phase 4（marketplace / 生态）、Phase 5（pipeline / smart actions）全部。

### 1.3 闭环底线（"最小可闭环、不影响使用"）

- 读取链全程不撞墙：划词 → 工具 → `.prompt` / `.agent` 流式结果 → 续聊 → 历史，没有 "not implemented" 墙。
- 写入 / 副作用工具（`.replace` / `.file` / `.bubble` / `.tts`）**保持现状**：能用即可，`.replace` 仍是 AX 替换 + 失败复制剪贴板 + 通知，v1.0 不补确认 / 撤销浮条。

### 1.4 分发

- 维持**未签名 DMG** + 文档说明 Gatekeeper 绕过（右键打开 / 移除 quarantine）。
- 签名 + 公证（Developer ID / notarization）留到 release 时单独决定，不进 v1.0 范围。

## 2. 里程碑顺序

- **M0（本轮产出）**：本 v1.0 scope + ordering 文档。
- **M1**：「续聊 + 历史」单 feature spec → plan → 实现。内部实现顺序固定为：
  1. 会话模型 / 持久化基座（含脱敏边界）
  2. 续聊 UX（ResultPanel 多轮）
  3. History 页
- **M2**：v1.0 收口 gate（见 §6）。

> 决策：续聊与历史合为**单切片 / 单 spec**（brainstorming 方案 A）。History 本质是"把会话持久化后展示"，与续聊共享同一会话数据模型 + 持久化 + 脱敏，拆开会返工或割裂。把"先定数据地基"的好处作为单 spec 的**内部实现顺序**吸收进来。

## 3. 续聊（conversation follow-up）

### 3.1 承载面

- 续聊放在现有 **ResultPanel**：结果流式结束后，面板底部出现输入框，用户输入追问 → 同一会话继续多轮。ResultPanel 从"单结果展示"演进为"轻量对话视图"，保留 pin / drag / resize。
- **边界**：续聊只作用于 **window DisplayMode（ResultPanel）** 的结果。`.bubble` / `.tts` 是 fire-and-forget，v1.0 不支持续聊。

### 3.2 会话模型（在发起工具的能力上下文里继续）

续聊**不是**"与工具无关的纯 chat"，而是"在发起工具的能力上下文里继续"：

- **agent 发起** → 续聊走回 `AgentExecutor`，**继承该 agent tool 的 skill 绑定 + MCP 配置 + system 配置 + ReAct 能力**，携带前面所有轮次。追问时仍能 `sliceai_load_skill` / `sliceai_load_skill_resource` 和调 MCP tool。
- **prompt 发起** → 续聊走多轮 `PromptExecutor` 纯对话（prompt 工具本就没绑 skill / MCP，无可继承）。
- 仍然成立：续聊**不重新跑工具的 prompt 模板、不重启一个全新 agent**——继承的是能力与上下文，新的一轮是用户输入本身（发起工具的"输入 → 输出"作为第 1 轮）。
- 注：skill / MCP 目前只挂在 `.agent` 工具上。"prompt 工具也能挂 MCP / skill" 是更大改动，超出 v1.0。

> 具体由哪个 executor 承载多轮、消息数组如何组织，留给 M1 feature spec；本文件只钉死边界：续聊全程走 **ExecutionEngine 唯一入口**，不旁路。

### 3.3 上下文管理（质量优先）

- **不做激进裁剪、不摘要压缩**——优先保证对话质量。
- 默认 **10 轮**滑动窗口（1 轮 = 一次 user → assistant 交换）全量载入上下文。
- 超过 10 轮：从**最老的整轮**开始裁剪（whole-turn FIFO，不在单轮内切碎）。
- 触发裁剪时给用户**友好的非阻塞提示**：会话轮数已过长、较早内容已不在上下文、可能影响对话质量。
- agent 续聊的 ReAct 中间上下文**保留哪些**按业内最佳实践：保留窗口内相关的 `tool_call` / `tool_result` 消息以维持连续性，超大 tool 输出可有界。具体策略留 M1 feature spec。

### 3.4 MCP / 安全边界

- 续聊里的 MCP 调用走该 agent tool **既有的 allowlist + PermissionBroker（生产路径）**，不因为"是续聊"就放宽。
- Playground 的"MCP 默认禁用、需本次运行显式打开"是 **Playground 专属**规则，不波及生产续聊。

## 4. 历史（History）

### 4.1 History 页范围（最小）

- Settings 一个 History 页：**只读列表 + 点开看某次会话完整多轮**。每条显示：时间、来源工具、首条输入摘要、provider / model。
- 支持**删除**（单条 + 清空）——存了用户文本，必须给用户删除权。
- **取舍**：v1.0 **不做**"从历史重开会话继续追问"（re-open to continue），推后。

### 4.2 持久化

- 会话落盘到 App Support 下**独立存储**（如 `~/Library/Application Support/SliceAI/conversations/`），格式（JSON 文件 vs sqlite）留 M1 feature spec。
- 存储**独立于** `config-v2.json` 与 Keychain。

### 4.3 脱敏 vs 明文（最重要的边界）

这块的核心张力：`audit.jsonl` / `cost.sqlite` 是**脱敏**的，但 History 页要给用户看"我问了什么、模型答了什么"，天然需要存**完整明文**（选中文本 + 模型输出）。因此 **History 存储 ≠ audit 日志**：

- History = 用户自己的数据，**明文存本地**，给用户自己看；`audit.jsonl` / `cost.sqlite` 仍旧脱敏。
- 硬规则：History 明文**只存本地、永不进日志 / 仓库 / 外发、可删除**。
- History **只存用户可见轮次**（user 输入 + assistant 最终输出）；agent 内部 ReAct 的 skill 加载 / MCP 结果**不进 History 明文**（避免 MCP 结果的敏感数据落入明文存储），它们仍只在脱敏 audit 里。

## 5. 不变量与约束（M1 实现必须守住）

- **ExecutionEngine 唯一入口**：续聊（含 agent 续聊的 skill / MCP）全程走 ExecutionEngine，不旁路。
- **SliceCore 零 UI**：会话值类型（Conversation / Turn）落在 SliceCore（Foundation only）；持久化走 protocol（SliceCore 定义、Capabilities 实现），不让领域层碰 AppKit / SwiftUI。
- **脱敏不变**：`audit.jsonl` / `cost.sqlite` 继续脱敏；`SliceError` 带 String payload 的 case 仍输出 `<redacted>`。History 明文是**唯一例外**，但只存本地、不外发、可删除、不进日志 / 仓库。
- **MCP / side-effect 安全不弱化**：续聊 MCP 走该 agent tool 既有 allowlist + PermissionBroker；Playground 默认禁用规则只属 Playground。
- **config / Keychain 分离**：History 存储独立于 `config-v2.json` 与 Keychain。
- **不新增 provider**：复用既有 OpenAI 兼容流式路径。
- **schema 同步**：若新增配置字段（历史开关、保留上限等），必须同步仓库根 `config.schema.json` 并 bump `Configuration.currentSchemaVersion`（当前 4）。

## 6. v1.0 gate（M2 验收标准）

- 全量 SwiftPM tests 绿（新增：prompt 续聊多轮、agent 续聊继承 skill / MCP、历史持久化 / 删除、既有读取链回归）。
- `swiftlint lint --strict` 0 违规。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 绿。
- 真实 App smoke：
  1. prompt 多轮续聊；
  2. agent 续聊能继承 skill + MCP；
  3. 历史查看 + 删除 / 清空；
  4. 既有读取链回归；
  5. 上下文 10 轮窗口裁剪 + 友好提示生效。
- 文档同步：README / AGENTS / `docs/v2-refactor-master-todolist.md` / `docs/Task_history.md` / Module（Orchestration / SettingsUI / SliceCore）。
- 未签名 DMG 可构建（`scripts/build-dmg.sh`）；tag / 正式发布留用户决定。

## 7. 风险与未决（留给 M1 feature spec）

- **上下文成本**：agent 续聊每轮重跑 ReAct + 全历史（10 轮窗口内），token 成本偏高。已定**不做更激进裁剪**，以质量优先；M1 需确认 10 轮窗口在 agent 场景下的成本可接受度，并实现窗口内 ReAct 消息的最佳实践保留。
- **持久化格式**：JSON 文件 vs sqlite；并发写；大会话体积。
- **会话内切 provider / model**：默认锁定发起时的 provider / model，切换推后。
- **History 存储粒度**：已定只存用户可见轮次；agent 内部 MCP / skill 步骤仍只在脱敏 audit。
- **ResultPanel 多轮布局债**：小宽度响应式已是已知技术债（见 master todolist / SettingsUI Module）。

## 8. 决策记录（2026-05-30 brainstorming 结论）

| # | 决策点 | 选择 | 理由 |
|---|--------|------|------|
| 1 | 本轮产出结构 | 范围文档优先；续聊 + 历史作为头号特性单独走 spec | 每份 spec 保持单一 plan 体量 |
| 2 | 原生 provider / 本地模型 | v1.0 只要 OpenAI 兼容，原生 provider 全部推后 | Ollama 已可经 OpenAI 兼容端点接入；保持 v1.0 瘦 |
| 3 | 遗留 Phase 3 条目 | 全部推后，但 v1.0 必须最小可闭环、不影响使用 | 聚焦续聊主线，避免产品残缺 |
| 4 | 闭环完整度 | 核心读取链闭环即可；写入 / 副作用工具保持现状 | `.replace` 已能用；overlay 是 polish，推后 |
| 5 | 分发 / 签名 | 维持未签名 + 文档绕过；签名留 release 决定 | 零额外成本；签名流水线不影响功能开发 |
| 6 | 续聊 + 历史 切片 | 方案 A：单 spec，内部顺序 数据基座 → 续聊 UX → History | 三者本是同一数据模型的不同视图，硬拆返工 / 割裂 |
| 7 | 续聊能力继承（用户补充） | 续聊继承发起工具 / agent 的 skill 与 MCP 配置 | agent 续聊需保留原能力，否则追问无法用原工具的 skill / MCP |
| 8 | 上下文管理（用户补充） | 质量优先、不激进裁剪；默认 10 轮窗口，超出从最老整轮裁剪 + 友好提示 | 短会话质量优先；10 轮足够，超长给用户预期管理 |
