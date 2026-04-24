# SliceAI 产品规划 v2.0 · 从划词工具到 AI Agent 配置框架

- **日期**：2026-04-23
- **版本**：2.0（产品定位重塑 + 底层架构重构规划）
- **状态**：Phase 0–1 = Design Freeze（可进入实施）；Phase 2–5 = Directional Outline（进入前需独立 spec）。详见 §4.1
- **与 v1.0 的关系**：不作废 v1.0 ([docs/superpowers/specs/2026-04-20-sliceai-design.md](2026-04-20-sliceai-design.md))，而是在 v1.0 已完成的 MVP v0.1（8 个 module + 双通路触发 + OpenAI 兼容 + 4 内置工具）之上**扩展定位、重构核心抽象、新增模块**
- **作者**：与产品负责人对齐后由 Claude 结构化产出
- **读者**：项目作者 / 未来的 Claude 会话 / 潜在开源贡献者
- **评审与修订**：2026-04-23 经 Codex 评审（`REWORK_REQUIRED`，见 [docs/Task-detail/sliceai-v2-roadmap-review-2026-04-23.md](../../Task-detail/sliceai-v2-roadmap-review-2026-04-23.md)）；本版为采纳评审后的修订版，主要变更：
  - ExecutionContext 拆成 `ExecutionSeed` + `ResolvedExecutionContext` 两阶段，修正"不可变 vs 回填"自相矛盾（§3.3.2）
  - 移除 ContextCollector DAG 承诺，Phase 0–1 明确用平铺并发（§3.3.3）
  - 新增 §3.9 Security Model（来源分级 / 能力分级 / 路径规范化 / 日志脱敏 / Pack 校验 / 默认拒绝）
  - Phase 0 从 22 任务一包改为 M1/M2/M3 三 milestone，每个独立 PR 可 merge（§4.2）
  - v2 期间使用独立 `config-v2.json` 路径，v1 原文件不动（§3.7 + §4.2）
  - **冻结范围收敛**：只有 Phase 0–1 是 Design Freeze，Phase 2–5 降为 Directional Outline，细节进入 phase 前再独立 plan（§4.1）
- **评审与修订（第二轮）**：2026-04-23 Codex 二次评审再次给出 `REWORK_REQUIRED`（3 条 P1 安全硬伤 + 1 条一致性）；本文件在原地继续修订。主要变更：
  - §3.9.1 / §3.9.2 重写：**能力分级为最低下限，来源分级只能在下限之上放宽 UX，不能突破下限**；`exec` / `network-write` 无论来源都要每次确认（D-22）
  - §3.9 扩展 MCP 威胁建模：**启动 unknown stdio MCP server ≡ 授权用户身份下的本地代码执行**，不可靠运行时 gate 兜底；Phase 1 只推荐 first-party / 自管 server（D-23）
  - §3.9 / §3.4 新增硬约束：执行前把 `ContextRequest` / `OutputBinding.sideEffects` 解析为 `effectivePermissions`，必须 ⊆ `tool.permissions`，否则直接失败（D-24）
  - 全文一致性清理：§2.3、§3.1、§3.2、§3.4 Agent 伪代码、附录 A、附录 C 里残留的 `ExecutionContext` / 旧任务编号 / 旧迁移描述统一改为新命名
- **评审与修订（第三轮）**：2026-04-23 Codex 三次评审给出 `REWORK_REQUIRED`（2 条 P1，已收敛到 `CONDITIONAL_APPROVE` 边界）。本文件继续原地修订：
  - **Canonical schema 闭合（D-24 补全）**：`Tool` / `Skill` / `MCPDescriptor` 正式定义加 `provenance: Provenance`（§3.3.1 / §3.3.8 + 附录 B）；`ContextProvider` protocol 加 `static inferredPermissions(for args:)`（§3.3.3）；`SideEffect` 加 computed `inferredPermissions`（§3.3.6）；`Provenance` enum **唯一 canonical 定义**提升到 §3.3.5（SliceCore 权限体系），§3.9.1 与 §3.9.4.2 的重复定义删除
  - **firstParty 授权规则收敛（D-25 新）**：§3.9.1 的"已声明即授权"描述删除；§3.9.2 下限列改为"所有来源均适用"；三处规则（§3.9.1 / §3.9.2 / §3.9.6）统一为 **"默认未授权 → 按下限触发确认 → 按 provenance 只调整确认 UX 文案"**；`firstParty` 对 `readonly-network` / `local-write` **不再跳过首次确认**
- **评审与修订（第四轮：M1 实施期命名更新）**：2026-04-24 落地 Phase 0 M1 时发现两个 v2 新类型名与 v1 既有声明冲突，为保证"v1 zero-touch"不变量，M1 阶段引入临时改名；本 spec 源代码块保留原始设计名以便阅读连贯，但落地代码采用新名。M3 rename pass 会在删除 v1 冲突声明后，把新名重命名回 spec 原意。
  - `DisplayMode` → **`PresentationMode`**（v2 六态）：v1 `Tool.swift:85` 已存在 `public enum DisplayMode`（3-case），名字直接复用会造成 API 歧义；新名 rawValue 完全超集 v1（`window`/`bubble`/`replace` 保留原字符串），migrator 零损失
  - `SelectionSource` → **`SelectionOrigin`**（v2 三值枚举 `.accessibility` / `.clipboardFallback` / `.inputBox`）：v1 `SelectionCapture/SelectionSource.swift` 已有 `public protocol SelectionSource`，跨 target 命名冲突；`SelectionSnapshot.source` 字段类型相应改名
  - 详细评审修正索引见 M1 plan [2026-04-24-phase-0-m1-core-types.md](../plans/2026-04-24-phase-0-m1-core-types.md) "评审修正索引" 段
- **评审与修订（第五轮：M1 merge 前 Codex 质量评审）**：2026-04-24 Codex 针对 36 commit 的 M1 实施做最终评审，三条 findings（1 P1 + 2 P2）全部接受并落地为独立 fix commit，**不影响 M1 功能范围**，只收紧类型不变量：
  - **P1**（`e64c3d3`）：`V2ConfigurationStore.current()` 的 `try?` 吞掉所有错误，M3 接入后会导致用户 config 损坏时默认值覆盖真实文件（数据丢失）；改为 `async throws`，"两份文件都不存在"继续是 first-launch 默认
  - **P2a**（`2b7095c`）：`V2Provider.init(from:)` 加校验——`ProviderKind.openAICompatible` / `.ollama` 必须非 nil baseURL（注释里的 "Anthropic/Gemini 可 nil" intent 类型层未 enforce）
  - **P2b**（`d141c05`）：`V2Tool` 手写 Codable，解码时拒绝 `outputBinding.primary != displayMode` 的 JSON（单一事实源原则；`displayMode` 为 primary truth）
  - M3 承接：AppContainer 接入 `V2ConfigurationStore.current()` 时必须处理 `throws`，建议 alert 告警 + 中止启动，不要静默回退
- **评审与修订（第六轮：收紧写入边界 + migrator schema 校验）**：2026-04-24 Codex 第八轮 review 指出第五轮的不变量只覆盖"读入边界"（decoder），未锁定"写入边界"（代码构造非法对象再保存）与 migrator 输入的 schema 合法性；三条 P2 全部接受并落地，M3 UI/AppContainer 接入前补齐最后一层守护：
  - **P2-1/P2-2**（`03fa632`）：`V2Provider` / `V2Tool` 各加 `public func validate() throws`（镜像 decoder 校验），`V2ConfigurationStore.save()` 在 `writeV2` 前逐个 validate；非法对象 save 失败时磁盘文件不被写入 / 覆盖。`init(id:...)` 非 throws 保持（保护 `DefaultV2Configuration` `static let`）
  - **P2-3**（`2f4f8d9`）：`ConfigMigratorV1ToV2.migrate(_ v1:)` 改 throwing，首行 `guard v1.schemaVersion == 1`；手改 `config.json` 为 `schemaVersion: 2/99` 时不再被盲目迁移
  - 配套（`14a5500`）：`SliceError.ConfigurationError.validationFailed(String)` 新 case，developerContext 按脱敏规则输出 `<redacted>`
  - M3 承接：UI 层写入新 Provider/Tool 前应当先 call `.validate()` 给用户即时反馈；save() 是最后防线不应是首次反馈

---

## 目录

- [0. 前言](#0-前言)
- [1. 产品愿景与定位](#1-产品愿景与定位)
- [2. 设计哲学与不变量](#2-设计哲学与不变量)
- [3. 底层架构重构](#3-底层架构重构)
- [4. 分阶段路线图](#4-分阶段路线图)
- [5. 风险与关键决策](#5-风险与关键决策)
- [6. 成功指标](#6-成功指标)
- [7. 附录](#7-附录)

---

## 0. 前言

### 0.1 为什么要重规划

v1.0 把 SliceAI 定位为"开源版 PopClip + LLM"，在 MVP v0.1 收尾阶段暴露了两个问题：

1. **定位过窄**：落入 AI Writing 工具赛道，会被 Apple Intelligence（系统级）、ChatGPT Desktop（免费 tier）、Raycast AI（键盘党生态）三面夹击——"划词触发翻译/润色/摘要"的叙事今天已无独特性。
2. **抽象过弱**：当前 `Tool` 结构本质是"一次 LLM 调用的参数包"（`systemPrompt + userPrompt + provider + model + temperature`），无法承载用户真正想要的"把选中内容作为任意 AI 工作流的输入"这一定位。`MCP / Skill / Pipeline / Context Providers / Agent loop` 在 v1.0 Roadmap 中被推到 v0.2+，等于**把核心能力当可选项**。

v2.0 的任务是：**重新定位产品为"划词触发型 AI Agent 配置框架"，并在 MVP v0.1 UI 打磨收尾后，用一轮架构重构（Phase 0）把底层抽象提到能承载 MCP / Skill / Pipeline 的层次，再分阶段把这些能力逐一交付**。

### 0.2 本文档与 v1.0 spec 的关系

| 项目 | v1.0 立场 | v2.0 立场 |
|---|---|---|
| 产品定位 | 开源划词 LLM 工具（PopClip 风格） | 划词触发型 AI Agent 配置框架 |
| 竞品锚点 | PopClip / Bob / ChatGPT Desktop | Raycast AI Commands / Claude Desktop / Cherry Studio |
| 核心差异化 | 任意 Prompt + OpenAI 兼容 + 开源 | 本地 + 开源 + **划词触发 MCP / Skill / Agent** |
| MCP / Skill | v0.2+ 扩展方向 | **v2.0 的定位必需，Phase 1 必须落地** |
| Tool 抽象 | 单次 LLM 调用 | 三态（prompt / agent / pipeline），可承载 Agent |
| 输出模式 | 仅 `window`，其余延后 | `window / replace / bubble / file / silent / structured` 都作为基础能力建模 |
| 模块数 | 8 个 library target | 10 个（新增 `Orchestration` + `Capabilities`） |
| Roadmap 锚点 | v0.1 MVP → v0.2 MCP | v0.1 MVP（已完成）→ Phase 0 重构 → Phase 1–5 逐步释放 |

v1.0 的以下决策在 v2.0 **保留且被强化**：

- SliceCore 零 UI 依赖（v2.0 进一步要求 SliceCore 零网络、零文件系统、零子进程——任何副作用都通过 Capability abstraction 注入）
- DesignSystem 只被 UI 层依赖的反向约束
- `Provider` / `LLMProvider` 的 protocol 化
- Accessibility + Cmd+C fallback 的透明降级
- Configuration 与 Keychain 的严格分离
- Composition Root 在 `SliceAIApp/AppContainer.swift`

v1.0 的以下决策在 v2.0 **被修订**（见 §5.2 决策记录）：

- "MCP / Skill 在 v0.2+" → 提到 Phase 1 必须落地
- "只做 OpenAI 兼容" → 保留 OpenAI 兼容 provider，但同时支持 Anthropic / Gemini / Ollama 原生 provider，允许 Tool 声明能力需求（caching / thinking / tool-use / vision）
- "DisplayMode 只实现 .window" → `replace / bubble / file / silent / structured` 都作为 DisplayMode 的正式成员进入数据模型，实现节奏按 phase 逐步释放
- "不自研 DSL" → 保留；但 PromptTemplate 要从"字符串替换"升级到"可调用 ContextProvider 与 Helper 函数的 Mustache 超集"

### 0.3 读这份文档的方式

- 第一次读：先读 §1 + §2 + §3.1 + §4.1（定位 + 架构分层 + Freeze 范围），约 20 分钟。
- 准备实施 Phase 0：精读 §3 全部（含 §3.9 Security Model）+ §4.2 M1/M2/M3 拆分，约 75 分钟。
- 准备实施 Phase 1：精读 §3.5 MCP + §3.3.3 Context + §3.9 + §4.3，约 45 分钟。
- 进入 Phase 2–5 之前：**不要**直接按本文档细化——先用 `superpowers:brainstorming` 对该 phase 重新对齐，再写独立 plan.md，最后回填到本文档对应小节前加"状态：已交付 @ commit XXXX"。

---

## 1. 产品愿景与定位

### 1.1 一句话定位

> **SliceAI 是一个 macOS 原生、开源的"划词触发型 AI Agent 配置框架"——用户在任何应用中选中文字、图像、文件片段，即可触发一个由 prompt + skill + MCP + 自定义上下文装配的 AI Agent，让 LLM 在本地身份下做任意事情。**

### 1.2 三个锚点

1. **划词 = 意图触发器**：选中的内容是 agent 的第一输入，但**不是唯一输入**；contexts（剪贴板、文件、窗口、屏幕、MCP 拉取）共同组成执行上下文。
2. **Prompt / Skill / MCP = 能力扩展面**：用户的"想象力边界"等价于他能组合多少 prompt、skill、MCP。产品的职责是把组合成本降到**近乎零**。
3. **本地 + 开源 = 信任锚点**：配置、密钥、执行历史、Prompt 迭代全部本地化；LLM 调用走用户自己的 API Key 或本地模型（Ollama / MLX）；整个产品可审计。

### 1.3 重新校准的竞品地图

| 维度 | SliceAI | Raycast AI | Claude Desktop | Cherry Studio | PopClip | ChatGPT Desktop | Apple Intelligence |
|---|---|---|---|---|---|---|---|
| 划词触发 | ✅ | ❌（键盘优先） | ❌ | ❌ | ✅ | ❌（需快捷键） | ✅（系统级） |
| 自定义 Prompt | ✅ | ✅ | ❌ | ✅ | 需装 extension | Custom GPT | ❌ |
| MCP 支持 | ✅（Phase 1） | ❌ | ✅ | ✅ | ❌ | ❌ | ❌ |
| Skill 支持 | ✅（Phase 2） | ❌ | 部分 | ❌ | ❌ | ❌ | ❌ |
| 本地模型 | ✅（Phase 3） | ❌ | ❌ | ✅ | ❌ | ❌ | ✅（端内） |
| 开源 | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Mac 原生 | ✅ | ✅ | ✅ | ❌（Electron） | ✅ | ✅（SwiftUI） | ✅ |
| 划词 + MCP | **✅（独家）** | — | — | — | — | — | — |

**SliceAI 的独占格**：**"划词 × MCP"的交叉点**，是目前市场上没有任何产品填补的空位。这是 v2.0 的战略卡位。

### 1.4 目标用户与场景

#### 1.4.1 用户画像

- **Primary（想象力派）**：熟悉 LLM、用过 Claude Desktop / Cursor，手里有一堆自己的 prompt 和 MCP server，希望"用划词把它们装配起来触发"。
- **Secondary（场景垂直派）**：英语学习者、研究生、全栈工程师、Indie Hacker——有明确领域需求，会按官方发布的 Tool Pack 开箱使用，并根据自己场景微调 prompt。
- **Tertiary（开源贡献者）**：通过贡献 Tool Pack、Skill、MCP adapter 获得社区认可。

#### 1.4.2 场景矩阵（示例）

| 场景 | 选中内容 | Tool 配置 | 用到的能力 | 产出 |
|---|---|---|---|---|
| 学英语 | 自己写的英语段落 | `english-tutor` | skill: grammar + MCP: Anki | 语法分析 + 地道改写 + 自动入 Anki |
| 读论文 | PDF 中的段落 | `paper-reader` | MCP: arxiv-fetch + web-search | 术语解释 + 上下文引用 + 相关论文 |
| 代码分析 | 一段函数 | `code-reviewer` | MCP: git + shell（跑 test） | Review + 修复 patch + 验证测试 |
| 写 commit | 选中 git diff | `commit-writer` | MCP: git + project conventions | 符合项目规范的 commit message |
| 时区转换 | `2026-04-23 15:00 PST` | `tz-convert` | local helper | 多时区并列显示 |
| SQL 查询 | 自然语言"昨日订单" | `nl2sql` | MCP: postgres + schema cache | 生成 SQL + 执行 + 展示结果 |
| 任务入库 | 会议纪要段落 | `task-extractor` | MCP: Things3 / OmniFocus | 拆成 task 列表 + 一键入库 |
| 翻译 + 发推 | 一段中文想法 | `tweet-it` | MCP: Twitter API | 英语改写 + 推文长度调整 + 一键发 |

**这八个场景没有一个能被 Apple Intelligence / ChatGPT Desktop / Bob 覆盖**——它们都需要"用户自定义的 prompt + 用户选定的外部工具 + 用户自己的账号"的组合。这就是 SliceAI 的护城河。

### 1.5 不做什么（Non-goals 更新）

保留 v1.0 的 Non-goals，并新增：

- ❌ **不做 AI Writing 特效**（纠错/改写/友好语气这些系统级做不好的事由 Apple Intelligence 覆盖）
- ❌ **不做内置推理引擎**（Ollama / MLX / vLLM 生态足够好，SliceAI 做 adapter 即可）
- ❌ **不做内置 ChatBot**（ChatGPT Desktop / Claude Desktop 已覆盖；SliceAI 的 ResultPanel 支持基础追问即可，不做长聊天）
- ❌ **不做团队协作 / 云同步**（Git + iCloud / Dropbox 同步 config.json 是用户级方案）
- ❌ **不做商业订阅**（至少 Phase 5 前不做；保持纯开源吸引贡献者）
- ❌ **不做移动端 / Windows / Linux**（Mac 专注到底）

---

## 2. 设计哲学与不变量

### 2.1 哲学宣言

1. **"选中即输入，Agent 即输出"**：产品的核心动线不是"用户点按钮"而是"用户的意图被捕获并被一个配置好的 agent 执行"。所有 UI 都围绕这个动线服务。
2. **"想象力必须可以在午休期间实现"**：用户配一个新 Tool、装一个 MCP、写一段 prompt，应该能在 30 分钟内从想法跑到可用。复杂度不由用户承担，由框架承担。
3. **"本地优先，信任第一"**：密钥、执行日志、MCP 调用记录全部本地可审计。上云是用户的选择，不是产品默认。
4. **"抽象必须可以被不看过源码的贡献者理解"**：Tool / Provider / Skill / MCP / Context Provider 五个核心概念是对外语义的全部，任何新功能都应能映射到这五个概念之一，不能时就暂停功能设计、先改抽象。
5. **"每一层都可以跑在别的地方"**：SliceCore 零副作用 → 能装进 CLI / MCP server；Capabilities 层可重用 → 能装进 iOS app / 浏览器扩展；Windowing 可替换 → 能改成 AppKit / SwiftUI / Electron 壳。

### 2.2 架构不变量（Architectural Invariants）

| 编号 | 不变量 | 违反时后果 | 检测方式 |
|---|---|---|---|
| INV-1 | `SliceCore` 零 UI / 零网络 / 零 FS / 零进程副作用 | 未来复用能力被毁 | `Package.swift` 禁止依赖 AppKit/Foundation-FS API；CI 检查 import |
| INV-2 | `DesignSystem` 只被 UI 层 target 依赖 | 领域层被拖进 AppKit | `Package.swift` 反向依赖断言 |
| INV-3 | 模块间只通过 `SliceCore` 的 protocol 通信 | 替换某一层会级联影响 | PR review + module import fence |
| INV-4 | 配置（明文）与密钥（Keychain）严格分离 | 密钥泄露风险 | Configuration codable 无 apiKey / token 字段 |
| INV-5 | Composition Root 只在 `SliceAIApp/AppContainer.swift` | 依赖装配分散难排查 | PR review |
| INV-6 | `ExecutionSeed` 与 `ResolvedExecutionContext` 一旦构建后**只读**不可变（两阶段均 immutable） | Tool 执行中途上下文变异导致不可复现 | struct + `let`；ContextCollector 产出新对象而非 mutate seed |
| INV-7 | 所有外部副作用经过 `PermissionBroker` 检查 | Tool 越权执行危险操作 | 执行引擎中硬编码 check point |
| INV-8 | 任何 Tool 的调用都可以被"干跑"（dry-run）预览 | 调试与信任不可建立 | 执行引擎支持 `DryRun` mode |
| INV-9 | 任何 Tool 的调用都必须有 `invocationId` 贯穿日志 | 事后追溯不可能 | `Logger` 强制注入 |
| INV-10 | `SliceError` 对携带字符串 payload 的 case 一律脱敏 | 密钥/用户数据进日志 | 单测 + `developerContext` 审计 |

### 2.3 哲学与设计的对应表

| 哲学 | 对应的架构决策 |
|---|---|
| 选中即输入 | `ExecutionSeed`（触发层产物）→ `ResolvedExecutionContext`（ContextCollector 产物）两阶段模型，selection 与 contexts 平级，contexts 平铺并发预取 |
| Agent 即输出 | `Tool` 有三态（prompt/agent/pipeline），默认执行引擎是 agentic loop |
| 本地优先 | `Capabilities` 层把 LLM / MCP / 文件 / shell 都 abstract 成 Capability，Ollama/MLX 与 OpenAI 平等 |
| 想象力可实现 | `Tool Pack` 格式 + Prompt Playground + Tool from Conversation |
| 信任第一 | `PermissionBroker` + `CostAccounting` + `AuditLog` 为一等公民 |

---

## 3. 底层架构重构

> 这是本规划的核心。Phase 0 的唯一目标就是把下面的模型落地，**不加任何新功能**。新功能在 Phase 1 以后叠加。

### 3.1 新架构分层

```
┌─── SliceAI.app (Xcode App target) ──────────────────────────────┐
│   @main · MenuBarController · Onboarding · AppContainer          │
└───────────────────────────┬──────────────────────────────────────┘
                            │ depends on
                            ▼
┌─── Presentation（UI 层，可替换）─────────────────────────────────┐
│  Windowing  │  SettingsUI  │  Permissions  │  MarketplaceUI*     │
│  (NSPanel)  │  (SwiftUI)   │  (Onboarding) │  (Phase 4 新增)     │
└──────┬──────┴──────┬───────┴──────┬────────┴──────────────────────┘
       │             │              │
       ▼             ▼              ▼
┌─── Interaction（触发层）──────────────────────────────────────────┐
│  HotkeyManager  │  SelectionCapture  │  TriggerRouter*           │
│  (Carbon API)   │  (AX + Cmd+C)      │  (Phase 0 新增)           │
└────────┬────────┴──────────┬─────────┴──────────────────────────┘
         │                   │
         ▼                   ▼
┌─── Orchestration（编排层，Phase 0 新增）──────────────────────────┐
│  ExecutionEngine    │  ContextCollector  │  PermissionBroker      │
│  (Agent loop 核心)  │  (多 Provider)     │  (权限 gate)           │
│  CostAccounting     │  AuditLog          │  ToolRouter            │
└────────┬─────────────┴──────────┬─────────┴──────────┬────────────┘
         │                        │                    │
         ▼                        ▼                    ▼
┌─── Capabilities（能力层，Phase 0 新增 target，Phase 1+ 填充）────┐
│  LLMProviders   │  MCPClient*    │  SkillRegistry*   │  Memory*  │
│  (多 Provider)  │  (stdio/http)  │  (Anthropic 规范) │  (jsonl)  │
│  FilesystemCap* │  ShellCap*     │  VisionCap*       │  TTSCap*  │
└────────┬────────┴──────┬─────────┴─────────┬─────────┴──────┬────┘
         │               │                   │                │
         ▼               ▼                   ▼                ▼
┌─── SliceCore（领域层，零副作用）──────────────────────────────────┐
│  Tool{PromptTool, AgentTool, PipelineTool}                        │
│  ExecutionSeed · ResolvedExecutionContext · ContextKey · ContextRequest │
│  Provider · ProviderCapability                                     │
│  Skill · MCPDescriptor · Permission                                │
│  OutputBinding · DisplayMode · InvocationReport                    │
│  Configuration(v2) · SliceError                                    │
└───────────────────────────────────────────────────────────────────┘
```

**标 `*` 的是 Phase 0 新引入的类型 / 模块**。其他复用现有实现。

### 3.2 模块职责一览

| 模块 | 状态 | 职责 | 新增 / 变更 |
|---|---|---|---|
| `SliceCore` | 扩充 | 领域模型 + 协议 | +`ExecutionSeed` `ResolvedExecutionContext` `Capability` `Permission` `Provenance` `Skill` `MCPDescriptor` `OutputBinding` 等 |
| `LLMProviders` | 保留 + 扩展 | OpenAI 兼容实现 + 未来多 Provider | Phase 3 起加 Anthropic / Gemini / Ollama 原生 |
| `SelectionCapture` | 保留 | AX + Cmd+C fallback | 无大改 |
| `HotkeyManager` | 保留 + 扩展 | 全局热键 | Phase 1 起支持 per-tool hotkey |
| `DesignSystem` | 保留 | UI token + 组件 | 小补充（structured output 的渲染组件） |
| `Windowing` | 保留 + 扩展 | 浮条 / 面板 / 结果窗 | 新增 BubblePanel / InlineReplaceOverlay / StructuredResultView |
| `Permissions` | 保留 | Accessibility / Input Monitoring 等 | 新增：Tool Permission 展示 |
| `SettingsUI` | 保留 + 扩展 | 设置界面 | 新增：MCP Servers / Skills / Memory / Budget / Audit 页面 |
| **`Orchestration`** | **新增（Phase 0）** | 执行引擎、上下文采集、权限 gate、成本计量、审计 | — |
| **`Capabilities`** | **新增（Phase 0）** | MCP client、Skill registry、Filesystem / Shell / Vision / TTS / Memory 等外部能力 adapter | — |

### 3.3 核心领域模型升级（SliceCore 的变化）

#### 3.3.1 `Tool` 从单态升级到三态

```swift
// 新 Tool 定义（SliceCore/Tool.swift）
public struct Tool: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var icon: String
    public var description: String?
    public var kind: ToolKind                // 新增
    public var visibleWhen: ToolMatcher?     // 新增，智能匹配（§3.3.7）
    public var displayMode: DisplayMode
    public var outputBinding: OutputBinding? // 新增（§3.3.6）
    public var permissions: [Permission]     // 新增（§3.3.5）；必须覆盖所有 effective permission（D-24）
    public var provenance: Provenance        // 新增（§3.9.1，D-23）；安装流程写入，运行时只读
    public var budget: ToolBudget?           // 新增，per-tool 成本上限
    public var hotkey: String?               // 新增，per-tool 快捷键
    public var labelStyle: ToolLabelStyle
    public var tags: [String]                // 新增，用于搜索与 Marketplace
}

public enum ToolKind: Codable, Sendable, Equatable {
    case prompt(PromptTool)
    case agent(AgentTool)
    case pipeline(PipelineTool)
}

public struct PromptTool: Codable, Sendable, Equatable {
    public var systemPrompt: String?
    public var userPrompt: String
    public var contexts: [ContextRequest]   // 需要采集的上下文（§3.3.3）
    public var provider: ProviderSelection  // 不再是 providerId:String，见 §3.3.4
    public var temperature: Double?
    public var maxTokens: Int?
    public var variables: [String: String]  // 静态变量
}

public struct AgentTool: Codable, Sendable, Equatable {
    public var systemPrompt: String?
    public var initialUserPrompt: String
    public var contexts: [ContextRequest]
    public var provider: ProviderSelection
    public var skill: SkillReference?       // 可选引用 Skill
    public var mcpAllowlist: [MCPToolRef]   // 允许调用的 MCP tools
    public var builtinCapabilities: [CapabilityRef] // 内置能力（filesystem/shell/vision/tts/memory）
    public var maxSteps: Int                // agent loop 最大步数
    public var stopCondition: StopCondition
}

public struct PipelineTool: Codable, Sendable, Equatable {
    public var steps: [PipelineStep]
    public var onStepFail: StepFailurePolicy
}

public enum PipelineStep: Codable, Sendable, Equatable {
    case tool(toolRef: String, input: TemplateString)
    case prompt(inline: PromptTool, input: TemplateString)
    case mcp(ref: MCPToolRef, args: [String: TemplateString])
    case transform(TransformOp)   // jq / json-path / regex 等纯函数
    case branch(condition: ConditionExpr, onTrue: String, onFalse: String)
}
```

**设计要点**：

- `ToolKind` 的三态是**封闭集合**，新的执行模式（如 multi-agent）走"Pipeline 中嵌 Agent"的组合路线，而不是加第四态。
- `variables: [String: String]` 保留用于静态变量（兼容旧 config），动态变量走 `contexts` + 模板 helper。
- 旧 MVP 的 Tool（只含 systemPrompt/userPrompt）全部映射到 `.prompt(PromptTool)` kind，通过 migration 自动转换（§3.8）。

#### 3.3.2 两阶段执行上下文：`ExecutionSeed` → `ResolvedExecutionContext`

> **评审修正（2026-04-23 Codex）**：初版把 `ExecutionContext` 定义成"不可变 + 由 ContextCollector 回填 contexts"，两条约束自相矛盾。本版拆成两阶段只读模型——触发层产出 `ExecutionSeed`，`ContextCollector` 消费 seed 后产出 `ResolvedExecutionContext`，两者均 immutable，INV-6 仍成立。

```swift
// SliceCore/ExecutionSeed.swift
/// 阶段 1：由触发层（FloatingToolbar / CommandPalette / Hotkey / Shortcuts / Services）构建
/// 含所有"一发即知"的信息；只读且完整，但尚未采集按需上下文
public struct ExecutionSeed: Sendable, Equatable {
    public let invocationId: UUID               // 贯穿日志的追踪 id
    public let selection: SelectionSnapshot
    public let frontApp: AppSnapshot            // bundleId / name / windowTitle / url
    public let screenAnchor: CGPoint
    public let timestamp: Date
    public let triggerSource: TriggerSource     // .floatingToolbar / .commandPalette / .hotkey / .shortcuts
    public let isDryRun: Bool                   // 预览模式（不触发副作用）
}

// SliceCore/ResolvedExecutionContext.swift
/// 阶段 2：由 `ContextCollector.resolve(seed:requests:)` 产出；
/// 是执行引擎真正消费的上下文载体。任何字段不可 mutation；
/// 如需更新（如 Pipeline 中后续 step 的中间结果）必须构造新实例
public struct ResolvedExecutionContext: Sendable, Equatable {
    public let seed: ExecutionSeed
    public let contexts: ContextBag
    public let resolvedAt: Date
    public let failures: [ContextKey: SliceError]  // requiredness=.optional 请求失败的记录

    // 常用字段透传（仅为调用方便，非独立字段）
    public var invocationId: UUID { seed.invocationId }
    public var selection: SelectionSnapshot { seed.selection }
    public var frontApp: AppSnapshot { seed.frontApp }
    public var isDryRun: Bool { seed.isDryRun }
}

public struct SelectionSnapshot: Sendable, Equatable {
    public let text: String
    public let source: SelectionSource          // .accessibility / .clipboardFallback / .inputBox
    public let length: Int
    public let language: String?                // 简单语言识别（Phase 1 起填充）
    public let contentType: SelectionContentType? // .prose / .code / .url / .email / .json / …
}

public struct ContextBag: Sendable, Equatable {
    public let values: [ContextKey: ContextValue]
    public subscript(key: ContextKey) -> ContextValue? { values[key] }
}

public enum ContextValue: Sendable, Equatable {
    case text(String)
    case json(Data)                 // 由 ContextProvider 解析后的结构化数据
    case file(URL, mimeType: String)
    case image(Data, format: String)
    case error(SliceError)          // 采集失败也记录下来，供 prompt 降级使用
}
```

**要点**：

- 两阶段边界清晰：`seed` 是触发层的产物；`ResolvedExecutionContext` 是 `ContextCollector` 的产物；两者都只读。
- `invocationId` 由 seed 生成，resolved context 透传，整条链路 trace 统一。
- `contexts` 是 opaque bag，失败进入 `failures` 字段不污染 bag 本体；执行器按 `requiredness` 决定继续还是中止。
- `isDryRun` 在 seed 阶段就决定，resolved context 透传；下游 `PermissionBroker` / `OutputDispatcher` 读这一位决定是否执行副作用。

#### 3.3.3 `ContextProvider` / `ContextRequest`

```swift
// SliceCore/Context.swift
public struct ContextKey: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ContextRequest: Codable, Sendable, Equatable {
    public let key: ContextKey
    public let provider: String           // ContextProvider 的注册名
    public let args: [String: String]     // 透传参数
    public let cachePolicy: CachePolicy   // .none / .session / .ttl(seconds)
    public let requiredness: Requiredness // .required（失败→Tool 失败）/.optional（失败→记录并继续）
}

public protocol ContextProvider: Sendable {
    /// Provider 注册名，必须唯一（如 "file.read" / "clipboard.current" / "mcp.call"）
    var name: String { get }

    /// 【D-24 硬约束】静态推导：给定一次 request 的 args，本次采集会实际触发哪些 Permission？
    ///
    /// 这个方法必须是纯函数、无副作用、不访问外部资源——只根据 args 推导。
    /// `PermissionGraph.compute(tool:)` 聚合所有 ContextProvider 的此方法返回值，
    /// 与 `tool.permissions` 做 ⊆ 校验。漏报会导致 Tool 执行时"权限未声明"的运行错误；
    /// 多报则会让 manifest 要求超出实际，没有安全风险但影响 UX。
    ///
    /// 例：`file.read` 应返回 `[.fileRead(path: args["path"] ?? "")]`；
    ///    `mcp.call` 应返回 `[.mcp(server: args["server"]!, tools: [args["tool"]!])]`。
    static func inferredPermissions(for args: [String: String]) -> [Permission]

    /// 实际执行采集；调用前 `PermissionBroker.gate` 已通过
    func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue
}
```

**内置 Provider（Phase 0 骨架，Phase 1 逐步填充）**：

| Provider name | 功能 | 权限 | 实现 phase |
|---|---|---|---|
| `selection` | 选中文字（直接从 seed） | — | Phase 0 |
| `app.windowTitle` | 当前窗口标题 | AX | Phase 0 |
| `app.url` | 浏览器 URL（AX） | AX | Phase 0 |
| `clipboard.current` | 当前剪贴板 | Clipboard | Phase 1 |
| `clipboard.recent` | 最近 N 条剪贴板 | Clipboard + 历史记录权限 | Phase 1 |
| `file.read` | 读指定文件 | `fileRead:<path>` | Phase 1 |
| `file.inApp` | 当前编辑器打开的文件（VSCode / Xcode 通过 AX 或扩展） | AX | Phase 2 |
| `shell.run` | 执行 shell 命令取 stdout | `shellExec` | Phase 2 |
| `mcp.call` | 调用 MCP tool 取结果 | `mcp:<server>` | Phase 1 |
| `screen.capture` | 当前窗口截图 | Screen Recording | Phase 3 |
| `memory.recent` | Tool 个人记忆 | `memory:<tool>` | Phase 2 |
| `surrounding.paragraph` | 选中所在段落扩展 | AX | Phase 2 |

**并发与缓存（Phase 0–1 范围）**：
- `ContextCollector` 把 Tool 声明的 requests **平铺并发** 执行：所有 request 同时发起，等待全部完成或各自超时。
- 不支持 request 间依赖（即不提供 `depends` 字段）。若某 request 需要另一个 request 的结果，应该拆成两个 Tool 用 `.pipeline` 串联，或 Phase 5 再扩展 DAG 能力。
- 每个 request 有独立 timeout（默认 1.5s），超时 → `ContextValue.error`；`requiredness=.required` 时中止执行，`.optional` 时记入 `failures` 字段继续。
- 缓存按 `invocationId` 作用域（session 内）或 TTL。
- **DAG 排除理由**（评审采纳）：真实场景里 90% 的 context 采集是独立的（selection / app / file / clipboard / mcp），强依赖型采集（A 的输出决定 B 的参数）天然适合 Pipeline 而非同一 ContextCollector 层。过早做 DAG 会让 Phase 0 爆炸。

#### 3.3.4 `ProviderSelection` 替代 `providerId: String`

```swift
public enum ProviderSelection: Codable, Sendable, Equatable {
    case fixed(providerId: String, modelId: String?)
    case capability(requires: Set<ProviderCapability>, prefer: [String])
    case cascade(rules: [CascadeRule])   // 按条件选 provider
}

public enum ProviderCapability: String, Codable, Sendable {
    case promptCaching
    case toolCalling
    case vision
    case extendedThinking    // Claude Extended Thinking
    case grounding           // Gemini Grounding
    case jsonSchemaOutput
    case longContext         // ≥200k
}

public struct CascadeRule: Codable, Sendable, Equatable {
    public let when: ConditionExpr           // 简单表达式：e.g. `selection.length > 8000`
    public let providerId: String
    public let modelId: String?
}
```

**要点**：
- 兼容模式：`.fixed(providerId, modelId)` 等价于旧 `providerId + modelId`。
- `capability` 模式让 Tool 声明"我需要支持 vision 的模型"，运行时从 Configuration 中选择满足能力且启用的 provider。
- `cascade` 实现"长文用 Claude Haiku，代码用 Claude Sonnet"之类的策略。
- `Provider` 结构增加 `capabilities: Set<ProviderCapability>` 字段，由 Provider 定义本身声明。

#### 3.3.5 `Permission` 体系

```swift
public enum Permission: Codable, Sendable, Hashable {
    case network(host: String)                  // 访问特定域名
    case fileRead(path: String)                 // 读指定路径（允许通配：~/Documents/**/*.md）
    case fileWrite(path: String)
    case clipboard
    case clipboardHistory
    case shellExec(commands: [String])          // 允许的命令白名单
    case mcp(server: String, tools: [String]?)  // 允许的 MCP server / 具体 tool
    case screen
    case systemAudio                            // TTS / 朗读
    case memoryAccess(scope: String)
    case appIntents(bundleId: String)           // 触发其他 App 的 Shortcut
}

public struct PermissionGrant: Codable, Sendable, Equatable {
    public let permission: Permission
    public let grantedAt: Date
    public let grantedBy: GrantSource       // .userConsent / .toolInstall / .developer
    public let scope: GrantScope             // .oneTime / .session / .persistent
}

/// 【canonical 定义，D-23】信任来源分级
///
/// 由安装 / 导入流程写入 `Tool` / `Skill` / `MCPDescriptor` 等顶层资源；运行时只读。
/// PermissionBroker 按"能力分级下限（§3.9.2）∧ Provenance 上限（§3.9.1）"合并决策。
/// 语义细节见 §3.9.1；MCP server 的特殊约束见 §3.9.4.2。
public enum Provenance: Codable, Sendable, Equatable {
    /// 随 App 打包的 Starter Pack / 内置工具
    case firstParty
    /// 从官方 Marketplace 安装且签名校验通过（Phase 4+）
    case communitySigned(publisher: String, signedAt: Date)
    /// 用户本地 clone / 自己写的资源，安装时已显式承认"我已审读来源"
    /// （仅 MCPDescriptor 当前 Phase 1 需要此态；其他资源到 Phase 4 再评估）
    case selfManaged(userAcknowledgedAt: Date)
    /// 手动导入文件 / URL clone / 第三方教程贴 / sideload
    /// MCPDescriptor 不允许此态——Phase 1 安装流程会直接拒绝（§3.9.4.2）
    case unknown(importedFrom: URL?, importedAt: Date)
}
```

**PermissionBroker**（在 Orchestration 层）：
- Tool install 时展示清单供用户确认（类似 iOS 权限）。
- Tool 执行时每个副作用前必过 Broker。
- Broker 基于 `grants` 判定是否放行；未授权时：
  - `.oneTime`：弹 sheet 临时同意。
  - `.persistent`：写入 config，永久授权。

#### 3.3.6 `OutputBinding`：把结果绑到多种落地

```swift
public struct OutputBinding: Codable, Sendable, Equatable {
    public let primary: DisplayMode          // 默认的展示方式
    public let sideEffects: [SideEffect]     // 并行副作用
}

public enum DisplayMode: String, Codable, Sendable {
    case window        // 当前默认
    case bubble        // 小气泡，自动消失
    case replace       // 替换选区（AX setSelectedText / paste fallback）
    case file          // 写文件（OutputBinding.file 配置路径）
    case silent        // 无 UI，只做副作用
    case structured    // JSON-Schema 结果，UI 自动渲染为表单/表格
}

public enum SideEffect: Codable, Sendable, Equatable {
    case appendToFile(path: String, header: String?)
    case copyToClipboard
    case notify(title: String, body: String)
    case runAppIntent(bundleId: String, intent: String, params: [String: String])
    case callMCP(ref: MCPToolRef, params: [String: String])
    case writeMemory(tool: String, entry: TemplateString)
    case tts(voice: String?)
}

public extension SideEffect {
    /// 【D-24 硬约束】纯静态推导本 side effect 触发的 Permission。
    ///
    /// 不可返回运行时依赖信息——所有所需 Permission 必须能从 case 的关联值推出。
    /// `PermissionGraph.compute(tool:)` 聚合所有 sideEffect 的该值做 ⊆ 校验。
    var inferredPermissions: [Permission] {
        switch self {
        case .appendToFile(let path, _):          return [.fileWrite(path: path)]
        case .copyToClipboard:                    return [.clipboard]
        case .notify:                             return []          // 本地通知不视作 permission
        case .runAppIntent(let bundleId, _, _):   return [.appIntents(bundleId: bundleId)]
        case .callMCP(let ref, _):                return [.mcp(server: ref.server, tools: [ref.tool])]
        case .writeMemory(let toolId, _):         return [.memoryAccess(scope: toolId)]
        case .tts:                                return [.systemAudio]
        }
    }
}

// DisplayMode.replace 的 permission 由 ExecutionEngine 在合并 effectivePermissions 时单独注入
// （`primary == .replace` → 追加 .fileWrite 等价语义，但实际走 AX setSelectedText）
```

**要点**：
- `primary` 决定主 UI；`sideEffects` 是"顺便做这些事"（如翻译完自动复制到剪贴板）。
- `structured` 模式要求 Tool 给出 `jsonSchema`，LLM 走 JSON-mode 输出，UI 层用 schema 渲染表单。
- `replace` 需要 AX 写入，失败时降级为 `copyToClipboard` + 通知"请手动粘贴"。
- `SideEffect.inferredPermissions` 必须保持纯静态——若未来扩展的 case 需要运行时信息才能确定 permission（如动态 URL），必须在编译期拆成更细的 case，不可在此方法中做 I/O 或条件分支依赖外部状态。

#### 3.3.7 `ToolMatcher`：智能显示条件

```swift
public struct ToolMatcher: Codable, Sendable, Equatable {
    public let appAllowlist: [String]?          // 只在这些 bundleId 显示
    public let appDenylist: [String]?
    public let contentTypes: [SelectionContentType]?  // .code / .prose / .url ...
    public let languageAllowlist: [String]?     // 只对英语显示等
    public let minLength: Int?
    public let maxLength: Int?
    public let regex: String?                   // 可选正则匹配
}
```

UI 层在渲染浮条 / 面板工具列表前先过 `ToolMatcher.matches(context:)` 过滤。

#### 3.3.8 `Skill` / `MCPDescriptor`

```swift
public struct Skill: Identifiable, Codable, Sendable, Equatable {
    public let id: String                   // 如 "english-tutor@1.2.0"
    public let path: URL                    // 本地 skill 目录
    public var manifest: SkillManifest      // 从 SKILL.md 解析
    public var resources: [SkillResource]
    public var provenance: Provenance       // 新增（§3.9.1，D-23）；安装流程写入
}

public struct SkillManifest: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let version: String
    public let triggers: [String]           // 何时激活
    public let requiredCapabilities: [CapabilityRef]
}

public struct SkillReference: Codable, Sendable, Equatable {
    public let id: String                   // 指向 SkillRegistry
    public let pinVersion: String?          // 可选锁定版本
}

public struct MCPDescriptor: Identifiable, Codable, Sendable, Equatable {
    public let id: String                   // 本地注册名
    public let transport: MCPTransport      // .stdio / .sse / .websocket
    public let command: String?             // stdio 时的命令
    public let args: [String]?
    public let url: URL?                    // sse / ws 时的端点
    public let env: [String: String]?
    public let capabilities: [MCPCapability] // 声明能提供的工具集、资源集
    public var provenance: Provenance       // 新增（§3.9.4.2，D-23）；.unknown 来源在安装时即拒绝，运行时只会看到 .firstParty / .selfManaged / .communitySigned
}

public struct MCPToolRef: Codable, Sendable, Hashable {
    public let server: String
    public let tool: String     // MCP server 暴露的 tool 名称
}
```

### 3.4 执行引擎设计（Orchestration）

```swift
// Orchestration/ExecutionEngine.swift
public actor ExecutionEngine {
    public init(
        contextCollector: ContextCollector,
        permissionBroker: PermissionBroker,
        providerResolver: ProviderResolver,
        mcpClient: any MCPClientProtocol,
        skillRegistry: any SkillRegistryProtocol,
        costAccounting: CostAccounting,
        auditLog: any AuditLogProtocol,
        output: any OutputDispatcher
    )

    /// 入参是 `ExecutionSeed`（触发层产物），内部经过 ContextCollector 解析为
    /// `ResolvedExecutionContext` 后才交给底层 executor。调用方不持有 resolved context——
    /// 这样保证"一次 execute 调用对应一个 invocationId 的完整生命周期"，便于审计与复现。
    public func execute(
        tool: Tool,
        seed: ExecutionSeed
    ) -> AsyncThrowingStream<ExecutionEvent, Error>
}

public enum ExecutionEvent: Sendable {
    case started(invocationId: UUID)
    case contextResolved(key: ContextKey, value: ContextValue)
    case promptRendered(preview: String)          // 用于 Playground / DryRun
    case llmChunk(delta: String)
    case toolCallProposed(MCPToolRef, args: [String: Any])
    case toolCallApproved(id: UUID)               // 用户同意或自动批准
    case toolCallResult(id: UUID, result: Any)
    case stepCompleted(step: Int, total: Int)
    case sideEffectTriggered(SideEffect)
    case finished(report: InvocationReport)
    case failed(SliceError)
}
```

**流程**：

```
1. ExecutionEngine.execute(tool, seed)          // 入参是不可变 seed
      ↓
2. 计算 effective = PermissionGraph.compute(tool)  // 见 §3.9.6.5
      ├─ effective ⊄ tool.permissions → .failed(.permission(.undeclared(...)))
      └─ ok → 继续                                // 本步是纯静态校验，不弹 UI
      ↓
2.5 PermissionBroker.gate(effective, provenance: tool.provenance, isDryRun: seed.isDryRun)
      ├─ 按 §3.9.2 下限 + §3.9.1 provenance 合并决策
      ├─ 需确认 → 弹 UI → 授予 / 拒绝
      └─ 拒绝 → .failed(.permission(.denied(...)))
      ↓
3. let resolved: ResolvedExecutionContext =
     try await ContextCollector.resolve(seed: seed, requests: tool.contexts)
      ↓                                           // 产出新对象，seed 仍不可变
4. ProviderResolver.resolve(tool.kind.provider, resolved) → Provider
      ↓
5. switch tool.kind {
     case .prompt:   PromptExecutor.run(resolved, provider) → LLM stream
     case .agent:    AgentExecutor.run(resolved, provider) → ReAct loop（带 MCP / skill）
     case .pipeline: PipelineExecutor.run(resolved, provider) → 按 step 编排
   }
      ↓                                           // Pipeline 中每一步产生新的 resolved
6. 每次 LLM chunk 通过 OutputDispatcher 转发到 ResultPanel（或其他 DisplayMode）
      ↓
7. 副作用由 OutputDispatcher 按 OutputBinding.sideEffects 触发
   （每次副作用前仍会经过 PermissionBroker.gate，因为 network-write / exec 下限要求"每次确认"）
   （seed.isDryRun = true 时全部副作用被跳过，只流式呈现预览）
      ↓
8. CostAccounting.record(invocationId, tokens, usd)
      ↓
9. AuditLog.append(InvocationReport{ declaredPermissions, effectivePermissions, flags, ... })
      ↓
10. yield .finished(report)
```

**关键约束**：
- **Step 2 是纯静态闭环校验**（不涉及 UI），确保"实际会触发的 permission 是否都在 Tool manifest 里声明过"——这是 D-24 的架构级保证。
- **Step 2.5 是运行时 gate**，按 §3.9.1 / §3.9.2 的合并规则判断具体弹不弹确认。
- **Step 7 副作用阶段仍要 gate**：因为 `network-write` / `exec` 的"每次确认"下限不能被 Step 2.5 的"session 级授权"覆盖——副作用触发时机点才是用户真正需要看到参数的时机。

**Agent loop（简化伪代码）**：

```swift
func runAgent(tool: AgentTool, resolved: ResolvedExecutionContext) async throws {
    var messages = buildInitialMessages(tool, resolved)
    let mcpTools = try await mcpClient.tools(for: tool.mcpAllowlist)
    let builtinTools = resolveBuiltins(tool.builtinCapabilities)
    let allTools = mcpTools + builtinTools

    for step in 0..<tool.maxSteps {
        let response = try await provider.chat(
            messages: messages,
            tools: allTools,
            stream: true
        )
        // 流式转发 delta 给 UI
        for try await chunk in response {
            yield .llmChunk(delta: chunk.delta)
            if let toolCall = chunk.toolCall {
                yield .toolCallProposed(ref: toolCall.ref, args: toolCall.args)
                try await permissionBroker.check(mcpCall: toolCall)
                let result = try await dispatch(toolCall)
                yield .toolCallResult(id: toolCall.id, result: result)
                messages.append(.toolResult(toolCall.id, result))
                break   // 继续下一轮
            }
        }
        if response.finishReason == .stop { break }
    }
}
```

### 3.5 MCP 集成策略

#### 3.5.1 兼容 Claude Desktop 的配置格式

用户已经在 Claude Desktop 里配的 MCP server 可以 **零改动** 复制到 SliceAI：

```json
// ~/Library/Application Support/SliceAI/mcp.json（独立文件，不和 config.json 混放）
{
  "mcpServers": {
    "postgres": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-postgres", "postgresql://..."]
    },
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Documents"]
    }
  }
}
```

#### 3.5.2 进程模型

- stdio 子进程由 `MCPClient` 管理，懒启动（Tool 第一次用到时启动）、idle 超时后自动停（默认 5min）。
- 每个 server 独立进程，崩溃隔离。
- macOS sandbox 下启动子进程需在 entitlements 声明 `com.apple.security.inherit`；因 SliceAI v1.0 已是 unsigned 非 sandbox 运行，Phase 1 可直接做；如未来进 sandbox 需重新评估。

#### 3.5.3 Tool 与 MCP 的交互模式

- Tool 声明 `mcpAllowlist: [MCPToolRef]`，只有这些 tool 会被暴露给 LLM。
- LLM function-calling 产出 tool call → PermissionBroker 检查 → MCPClient 执行 → 结果回灌 LLM。
- ResultPanel 在流式过程中展示 tool call（折叠/展开 + 参数 + 结果），让用户看见 agent 在"想什么"。

### 3.6 Skill 集成策略

- Skill 存放：`~/Library/Application Support/SliceAI/skills/<skill-id>/`。
- 结构兼容 Anthropic Skills（`SKILL.md` + 可选资源文件）。
- `SkillRegistry` 启动时扫描目录，解析 manifest。
- Tool 声明 `skill: SkillReference`，执行前把 SKILL.md 内容拼接进 system prompt（按 `systemPrompt + "\n\n<skill>\n...\n</skill>"` 格式，便于 LLM 识别）。
- 资源文件（如 `references/*.md`）按需 lazy 读取——通过 `ContextRequest(provider: "skill.resource", args: [...])` 显式声明。

### 3.7 配置系统升级到 schemaVersion 2

```json
{
  "schemaVersion": 2,
  "providers": [
    {
      "id": "openai-official",
      "kind": "openai-compatible",
      "name": "OpenAI",
      "baseURL": "https://api.openai.com/v1",
      "apiKeyRef": "keychain:openai-official",
      "defaultModel": "gpt-5",
      "capabilities": ["promptCaching", "toolCalling", "vision", "jsonSchemaOutput"]
    },
    {
      "id": "claude",
      "kind": "anthropic",
      "apiKeyRef": "keychain:claude",
      "defaultModel": "claude-sonnet-4-6",
      "capabilities": ["promptCaching", "toolCalling", "extendedThinking", "vision", "longContext"]
    },
    {
      "id": "ollama-local",
      "kind": "ollama",
      "baseURL": "http://127.0.0.1:11434",
      "defaultModel": "llama3.3",
      "capabilities": []
    }
  ],
  "tools": [
    {
      "id": "grammar-tutor",
      "name": "Grammar Tutor",
      "icon": "📝",
      "kind": {
        "agent": {
          "systemPrompt": "You are a patient English tutor.",
          "initialUserPrompt": "Analyze and improve: {{selection}}\n\nContext vocab:\n{{vocab}}",
          "contexts": [
            {"key": "vocab", "provider": "file.read", "args": {"path": "~/Notes/vocab.md"}}
          ],
          "provider": {"capability": {"requires": ["toolCalling"], "prefer": ["claude"]}},
          "skill": {"id": "english-tutor@1.0.0"},
          "mcpAllowlist": [{"server": "anki", "tool": "createNote"}],
          "builtinCapabilities": ["tts"],
          "maxSteps": 6,
          "stopCondition": "finalAnswerProvided"
        }
      },
      "visibleWhen": {"contentTypes": ["prose"], "languageAllowlist": ["en"]},
      "displayMode": "window",
      "outputBinding": {
        "primary": "window",
        "sideEffects": [{"writeMemory": {"tool": "grammar-tutor", "entry": "{{response.summary}}"}}]
      },
      "permissions": [
        {"fileRead": {"path": "~/Notes/vocab.md"}},
        {"mcp": {"server": "anki", "tools": ["createNote"]}}
      ],
      "budget": {"dailyUSD": 0.5},
      "hotkey": "option+shift+g",
      "labelStyle": "iconAndName",
      "tags": ["english", "learning"]
    }
  ],
  "hotkeys": {"toggleCommandPalette": "option+space"},
  "triggers": { /* 同 v1 */ },
  "telemetry": {"enabled": false},
  "appBlocklist": [ /* 同 v1 */ ],
  "appearance": "auto",
  "budget": {"globalDailyUSD": 5.0},
  "mcpServersPath": "~/Library/Application Support/SliceAI/mcp.json",
  "skillsPath": "~/Library/Application Support/SliceAI/skills/"
}
```

**schema 升级策略（评审修正版）**：
- **独立路径**：v2 期间的配置文件使用 **独立文件名** `config-v2.json`，**不覆盖旧 `config.json`**。
  - 理由（采纳 Codex 评审 P1-2）：即使当前无外部用户，作者本人在不同 worktree / branch 之间切换时仍会用到旧版 app，共享同一 `config.json` 会造成"v2 升级后旧分支打不开"。独立路径是最小代价的隔离方案。
  - v2 app 启动时：若 `config-v2.json` 存在 → 直接读；不存在但 `config.json` 存在 → 运行 migrator 生成 `config-v2.json`（**不修改** `config.json`）；都不存在 → 写默认配置到 `config-v2.json`。
  - Keychain 槽位（`service: com.sliceai.app.providers`）v1/v2 共享，不做隔离（密钥本就对齐 provider.id）。
- **迁移器实现**：
  - 旧 `Tool{systemPrompt, userPrompt, providerId, modelId, temperature, variables}` → 新 `Tool{kind: .prompt(PromptTool{...})}`
  - 旧 `Provider{id, baseURL, apiKeyRef, defaultModel}` → 新 `Provider{id, kind: .openAICompatible, ..., capabilities: [默认按 baseURL 推断]}`
  - `DisplayMode` 旧 enum 值原样映射；新值（`file` / `silent` / `structured`）v1 不存在所以无需映射。
  - 其他字段平移。
- **不做降级**：v2 app 只写 v2 格式；若未来需要长期回退，再引入双写机制（当前阶段不实现，因为没有用户基数）。
- **v1 文件只读**：v2 app 启动后永远不写 `config.json`，保留给旧分支 / 旧 tag 的 app 正常打开。

### 3.8 向后兼容与旧代码迁移清单

| 现有代码 | 新位置 / 重构 |
|---|---|
| `SliceCore/SelectionPayload.swift` | 重命名为 `SelectionSnapshot.swift`，公共 API 增加 `language` `contentType` 字段 |
| `SliceCore/Tool.swift` | 扩展为 `Tool` + `ToolKind`；旧字段通过 migration 进入 `.prompt` |
| `SliceCore/ToolExecutor.swift` | **删除**；逻辑拆分到 `Orchestration/ExecutionEngine` + `Orchestration/PromptExecutor` |
| `SliceCore/LLMProvider.swift` | 保留 + 扩展 `capabilities` 字段 |
| `LLMProviders/OpenAICompatibleProvider` | 保留，作为 `.openAICompatible` kind |
| `SliceAIApp/AppContainer.swift` | 装配列表扩展：加入 Orchestration + Capabilities 组件 |
| `Windowing/ResultPanel` | 保留；新增 `displayMode: structured` 分支时走 `StructuredResultView` |
| `SettingsUI/Pages/*` | 新增 `MCPServersPage` `SkillsPage` `MemoryPage` `BudgetPage` `AuditLogPage` |

**Phase 0 结束时必须满足**：
- 所有旧 config.json 能被 migrator 读入并写出新的 `config-v2.json`，MVP v0.1 的 4 个内置工具行为不变。
- `swift build` / `swift test` / `swiftlint --strict` 全绿。
- 用户视觉上**无感**：Phase 0 不加任何可见新功能。

---

### 3.9 安全模型（Phase 0–1 必须先定义，评审新增）

> 评审采纳 P1-3：文档允许 shell / filesystem / mcp / AppIntents / Marketplace 等高权限能力，控制手段仅靠权限弹窗+调用确认是不够的。本节提前把信任边界写死，Phase 0 在 `Permission` 枚举层、`PermissionBroker` 接口层、`AuditLog` schema 层就按这个模型留 hook；Phase 1+ 填具体实现。

#### 3.9.1 信任来源分级（Provenance）

`Provenance` 的 canonical 定义在 §3.3.5（作为 SliceCore 权限体系的一部分）；此处只定义 **运行时 gate 的 UX 差异**。每个 `Tool` / `Skill` / `MCPDescriptor` 都带 `provenance: Provenance` 字段，由安装流程写入、运行时只读。

> **核心原则（D-22 + 第三轮评审收敛 D-25）**：**能力分级决定最低安全下限（§3.9.2），Provenance 只能在下限之上微调 UX 文案，不能减少确认次数**。`firstParty` 不等于"全权限静默放行"，只能在 `readonly-local` 档免于确认；`readonly-network` / `local-write` / `network-write` / `exec` 的**首次 / 每次确认** **永远不可因来源而跳过**。

**下限 × Provenance = 实际 gate 策略**（PermissionBroker 查表）：

| 能力档 | `firstParty` | `communitySigned` | `selfManaged` | `unknown` |
|---|---|---|---|---|
| `readonly-local` | 静默 | 静默 | 静默 | 首次确认 |
| `readonly-network` | **首次确认**（不可跳过） | 首次确认 | 首次确认 | 每次确认 |
| `local-write` | **首次确认**（不可跳过） | 首次确认 | 首次确认 | 每次确认 |
| `network-write` | **每次确认**（不可跳过） | 每次确认 | 每次确认 | 每次确认 |
| `exec` | **每次确认**（不可跳过） | 每次确认 | 每次确认 | 每次确认 |

**Provenance 唯一允许调节的 UX**：
- 确认弹窗的**文案强度**（如 firstParty 用中性"授权以下操作？"；unknown 用警告"此来源未经过校验，继续？"）
- 确认选项的**附加选项**（如 firstParty / signed 的首次确认 dialog 可勾"本次会话记住"；unknown 不显示此选项）
- 确认弹窗的**信息披露深度**（如 unknown 必须展示完整 Permission diff；firstParty 可折叠）

**不允许的**：
- ❌ 因为 `firstParty` 就把 `readonly-network` / `local-write` 的首次确认跳过——这会让"安装即授权"悄悄生效，违反"默认安全"。
- ❌ 因为 `firstParty` 就把 `network-write` / `exec` 的每次确认降级为"session 记住"——不可逆副作用必须逐次可审。

**与 §3.9.6 的关系**：§3.9.6"默认拒绝"定义 grant 初始状态（未授权），本表定义"何时 / 如何从未授权进入授权"。三者现在互相一致：**默认未授权 → 按下限触发确认 → 按 provenance 调整确认 UX**。

#### 3.9.2 能力分级（最低安全下限）

下表的"**下限**"列是 `PermissionBroker` 的硬约束——**任何 provenance（包括 firstParty）都不可放宽**。

| 级别 | 对应 Permission | 示例 | **下限（所有来源均适用）** |
|---|---|---|---|
| **readonly-local** | `clipboard`（读）、`fileRead`（白名单内）、`memoryAccess`（读） | selection / app.url / file.read | 路径必须在 PathSandbox 白名单内 |
| **readonly-network** | `network(host:)` GET | HTTPS GET 白名单域名 / MCP 只读 tool | **首次确认**；域名必须显式声明 |
| **local-write** | `fileWrite`（白名单内）、`clipboard`（写）、`replace` | appendToFile / copyToClipboard / setSelectedText | **首次确认**；路径必须在 PathSandbox 白名单内 |
| **network-write** | `network(host:)` POST/PUT/DELETE | 发推 / Notion API / MCP 写操作 | **每次确认**（任何来源都不能放宽为"记住"） |
| **exec** | `shellExec`、`appIntents`、启动子进程 | `shell.run` / runAppIntent / MCP stdio server 首次启动 | **每次确认 + 完整命令/意图参数可见** |

具体到 provenance 的 UX 差异（弹窗文案、信息披露深度、是否可"本次会话记住"）见 §3.9.1 的"下限 × Provenance"表。

`PermissionBroker.gate(...)` 的决策伪代码：

```
let tier = inferTier(permission)                  // readonly-local / readonly-network / ...
let lowerBound = minimumGatePolicy(tier)          // 见本节表
let uxHint = provenanceAdjustment(tier, provenance)  // 见 §3.9.1 表
return LowerBound(policy: lowerBound, uxHint: uxHint)
```

**关键性质**：`lowerBound` 只依赖 `tier`，与 `provenance` **完全无关**；`provenance` 只产出 UX hint，不进入 policy 计算。这保证测试矩阵唯一（每个 tier 一个下限行，与 provenance 笛卡尔积只影响 UX 文案）。

**为什么这样定**：
- 发推 API / 发邮件 MCP / 运行 `rm -rf` 的副作用不可逆，一旦放行为"记住"，用户事后发现时数据已经发生变化；
- 即使工具来自 firstParty，用户也可能因为选区文本不符预期而不想 actually 执行；
- 这是"默认安全"而非"默认便利"的选择，UX 代价可接受。

#### 3.9.3 路径规范化与白名单

所有文件路径在 `ContextCollector` / `OutputDispatcher` / `SkillRegistry` 入口统一做：
1. `URL(fileURLWithPath:).standardizedFileURL` 消除 `..` / symlink。
2. 与白名单前缀做 `hasPrefix` 匹配。

默认白名单：
- **允许读**：`~/Documents` `~/Desktop` `~/Downloads` `~/Library/Application Support/SliceAI/**` 以及用户显式添加的目录
- **允许写**：`~/Library/Application Support/SliceAI/**` + 用户显式添加
- **硬禁止**（无论用户怎么配都拒绝）：`~/Library/Keychains/**` `~/.ssh/**` `~/Library/Cookies/**` `/etc/**` `/var/db/**` `/Library/Keychains/**`

超出白名单的路径需用户在 Settings → Permissions → File Access 里显式添加（UX 类似 macOS "Files & Folders" 权限）。

#### 3.9.4 Pack / Skill / MCP 安装校验

##### 3.9.4.1 Pack / Skill（静态资源）

Phase 4 Marketplace 上线时：
- 官方 Pack 带 `manifest.sig`（Ed25519 签名，公钥随 App 内置）。
- 安装流程：**下载 → 解压到临时目录 → 校验签名 → 展示 manifest 的 permissions 清单 → 用户确认 → 移动到 `~/Library/Application Support/SliceAI/packs/<id>/`**。
- 签名失败或未签名：允许安装但 `provenance = .unknown`，执行时按 §3.9.2 的 unknown 策略 gate。
- Pack 安装不会执行任何代码（只解压 + 校验 + 挪位置），所以 `unknown` 来源风险在"运行时 gate"层可以兜住。

##### 3.9.4.2 MCP Server（**威胁模型升级，D-23，Codex 第二轮评审**）

> **关键认知**：stdio MCP server **不是** SliceAI 可以"沙箱化"的对象。它是用户身份下启动的独立进程，**等同于用户手动在终端里 `npx some-mcp-server`**——一旦启动，该进程的所有文件系统 / 网络 / 子进程 / Keychain 读取能力都是完整的用户权限，`PermissionBroker` 和 `PathSandbox` 只能约束 **SliceAI 与 server 的协议面**（tool call 参数、返回值），无法约束 server 进程自身的系统访问。

因此 `PermissionBroker` 的运行时 gate **不能当作 MCP server 的安全兜底**。必须在**安装时**就把信任决定清楚：

| 来源 | Phase 1 策略 | 安装 UX | 运行时 gate |
|---|---|---|---|
| `firstParty`（随 App 内置 MCP） | ✅ 允许 | 无额外确认 | 仍按 §3.9.2 对 tool call 参数做 gate |
| `自管`（用户在本地 clone / 自己写、手动填 command） | ✅ 允许 | 弹出警告："启动此 MCP server 等同于授权它在你的账号下运行任意本地代码。请仅在你信任来源时继续" | 同上 |
| `communitySigned`（Phase 4+ 带签名） | ⚠️ 允许 | 展示签名信息 + 警告 + `requiredCapabilities` 清单 | 同上 |
| `unknown`（URL copy-paste / 第三方教程贴的 config） | ❌ **Phase 1 不支持** | 拒绝安装；在 Settings 明确给出"要装未知 MCP，请先手动 clone 到本地并审读源码，然后用'自管'方式添加" | — |

**Phase 1 硬约束**：
- `MCPDescriptor.provenance` 必须是 `.firstParty` 或用户在 Settings 里手动确认"我已审读来源"后的 `.selfManaged` 状态。`.unknown` 来源的 MCP config 在**安装流程入口**直接拒绝（不进数据模型）。
- MCP server 的 stdio `command` **禁止**使用相对路径；`npx` / `uvx` / `node` / `python` 等 runner 在首次启动时要求用户输入"确认启动"串（防 copy-paste 攻击）。
- 安装任何 MCP server 的 UX 文案**必须明确提示**："启动 MCP server = 授权用户身份下本地代码执行"；不可用"我们会沙箱它"之类的虚假安全感措辞。

> `Provenance` 的 canonical 定义见 §3.3.5（含 `.selfManaged` case）。Phase 1 的 MCP 安装流程只允许产出 `.firstParty` / `.selfManaged` / `.communitySigned`；`.unknown` 是安装被拒绝的对象，不会落到磁盘。

**不接受的安全幻觉**：
- ❌ "stdio 子进程有进程隔离" —— 进程隔离不等于权限隔离，同 UID 进程可互相访问文件、剪贴板、Keychain。
- ❌ "运行时 gate 可以兜住 unknown server" —— gate 只拦 SliceAI → server 方向的 tool call，server 进程可以自主发起任意系统调用，不经过 SliceAI。
- ❌ "把 server 放进 App Sandbox" —— 需要全程 sandbox 重新签名 + server 自身也支持 sandbox，工程代价巨大且破坏"用本地能力"的卖点。Phase 1 不走这条路。

#### 3.9.5 日志脱敏

承接并扩展 v1.0 的 `SliceError.developerContext` 脱敏约定：
- `ExecutionEvent.promptRendered.preview`：截断到首 200 字符，超长部分用 `… <truncated N chars>` 标记；不入明文 AuditLog。
- MCP `toolCall.args` 中若 key 名匹配 `/(password|token|apiKey|secret|key|authorization|cookie)/i` → 值替换为 `<redacted>`。
- `AuditLog` **默认不写 selection 原文**，只写 `sha256` + 长度 + 语言；用户可在 Settings → Privacy 显式 opt-in "记录选区原文"（仅建议调试期开启）。
- 任何进入 `SliceError.developerContext` 的字符串 payload（已有约定）继续走 `<redacted>`。

#### 3.9.6 默认拒绝（Default Deny）

- 新装 Tool：所有非 `readonly-local` 能力 **默认未授权**，首次触发时由 `PermissionBroker` gate。
- 新装 MCP server：所有 tool **默认未 allowlist**，Tool 必须显式声明 `mcpAllowlist` 才可用。
- 新装 Skill：`manifest.requiredCapabilities` 全部需用户勾选后生效。
- 新增网络域名 / 文件路径：除白名单外一律走用户确认。

#### 3.9.6.5 权限声明闭环（D-24，Codex 第二轮评审）

> **问题**：Tool 有 `permissions: [Permission]` 静态声明，但 `ContextProvider` / `OutputBinding.sideEffects` 运行时还会**额外**触发文件读写、网络、MCP 调用等。如果 Tool 作者只声明了 `permissions: [.fileRead("~/Docs/**")]`，却在 `contexts` 里塞了 `file.read` 指向 `~/Desktop`，而 `~/Desktop` 又恰好在 PathSandbox 白名单里——就会出现"授权清单外的实际访问"，用户事先无法从 Tool manifest 审计出它会碰 `~/Desktop`。

**硬约束**（`ExecutionEngine` 执行前必须过一道静态校验）：

1. **计算 effectivePermissions**：
   - 从 `tool.contexts: [ContextRequest]` 聚合：每个 request 根据 provider + args 计算出它会触发哪些 Permission（由 `ContextProvider.inferredPermissions(for args: [String:String]) -> [Permission]` 静态方法提供，每个内置 provider 必须实现）。
   - 从 `tool.outputBinding.sideEffects: [SideEffect]` 聚合：同样有 `SideEffect.inferredPermissions` 静态映射。
   - 从 `tool.kind.agent.mcpAllowlist` / `.builtinCapabilities` 聚合对应的 `Permission.mcp(...)` / `Permission.shellExec(...)` 等。
   - 取并集得到 `effectivePermissions: Set<Permission>`。

2. **校验 ⊆ 关系**：
   - 若 `effectivePermissions ⊄ Set(tool.permissions)` → `ExecutionEngine.execute` 立即 `yield .failed(.permission(.undeclared(missing: effective - declared)))`。
   - 校验发生在流程 Step 2 之后、Step 3（ContextCollector.resolve）之前——**访问永远不会早于校验**。

3. **Tool 编辑器 / 安装流程也静态跑一次**：
   - Tool 编辑器保存时 lint 显示"以下 context / sideEffect 产生的 permission 未在 `permissions` 中声明"。
   - Marketplace 安装时展示"完整 effectivePermissions 清单"供用户确认——用户看到的是**实际会发生的**访问，而非作者声明的。

4. **审计**：
   - `AuditLog` 记录 `declaredPermissions` 与 `effectivePermissions` 的 diff；有差额时 `InvocationReport.flags` 里打 `.permissionUndeclared`。
   - 即便校验通过（declared 覆盖 effective），记录 diff 有助于事后溯源"实际用了哪些 permission 子集"。

```swift
// Orchestration/PermissionGraph.swift 骨架（Phase 0 M2 实现）
public struct EffectivePermissions: Sendable, Equatable {
    public let declared: Set<Permission>
    public let fromContexts: Set<Permission>
    public let fromSideEffects: Set<Permission>
    public let fromMCP: Set<Permission>
    public let fromBuiltins: Set<Permission>

    public var union: Set<Permission> {
        fromContexts.union(fromSideEffects).union(fromMCP).union(fromBuiltins)
    }
    public var undeclared: Set<Permission> { union.subtracting(declared) }
}

public enum PermissionError: Error, Sendable {
    case undeclared(missing: Set<Permission>)
    case denied(Permission)
    case sandboxViolation(path: String)
    // ... 其他
}
```

**为什么放在 Phase 0**：这是**架构级硬约束**而非运行时策略，必须在 `ContextProvider` / `SideEffect` 的 protocol 设计阶段就加上 `inferredPermissions` 要求，后补成本 10 倍。Phase 0 M1 的 `ContextProvider` protocol 必须带此方法；M2 的 `ExecutionEngine` 必须在主流程里做 ⊆ 校验。

#### 3.9.7 审计不可绕过

- 任何 `ExecutionEngine.execute(...)` 调用都至少产生一条 `InvocationReport`（成功 / 失败 / 被拒 都记录）。
- `AuditLog` **append-only**：Settings 里可清空但清空动作本身也记录（新文件第一条为 `logCleared` 事件）。
- Phase 1 起 `MCPClient` 所有 tool call 的 request/response 都过 AuditLog（脱敏后）。

#### 3.9.8 安全相关的架构 Hook（Phase 0 必须留）

| Hook | 位置 | 状态 |
|---|---|---|
| `Provenance` 字段（含 `.selfManaged` case） | `Tool` / `Skill` / `MCPDescriptor` / `Pack` manifest | Phase 0 M1 加 |
| `ContextProvider.inferredPermissions(for:)` 协议方法 | `SliceCore/Context.swift` | Phase 0 M1 加；内置 provider 全部实现 |
| `SideEffect.inferredPermissions` 静态映射 | `SliceCore/OutputBinding.swift` | Phase 0 M1 加 |
| `PermissionGraph.compute(tool:) -> EffectivePermissions` | `Orchestration/PermissionGraph.swift` | Phase 0 M2 加；ExecutionEngine Step 2 调用 |
| `PermissionBroker.gate(effective:provenance:scope:isDryRun:)` 接口 | Orchestration | Phase 0 M2 加骨架（按 §3.9.2 下限表跑单测），Phase 1 填实 UI gate |
| 路径规范化工具 `PathSandbox.normalize(_:against:)` + 硬禁止路径单测 | Capabilities/SecurityKit 新文件 | Phase 0 M2 加 |
| `AuditLog.append(InvocationReport{declaredPermissions, effectivePermissions, flags})` | Orchestration | Phase 0 M2 加骨架 + 脱敏测试 |
| `SliceError.developerContext` 脱敏单测 | SliceCore | 已有；扩展覆盖新增 payload（含 `PermissionError.undeclared.missing` 集合） |

---

## 4. 分阶段路线图

### 4.1 全景与冻结范围

> **评审修正（采纳 P2-1）**：初版把 6 个 phase 都写进"冻结规划"，范围过宽、稀释核心。本版收敛为：
>
> - **Phase 0–1 = Design Freeze**（底层 + MCP 主干）：细节已锁定，可直接出 plan.md 进入实施。
> - **Phase 2–5 = Directional Outline**（方向性大纲）：只保留"做什么"的意图和粗粒度交付项，**具体抽象 / API / 数据模型 / 拆分 在进入该 phase 前独立用 brainstorming 重新走一遍**再冻结。
> - 任何新想法（Marketplace / Memory / TTS / Pipeline 编辑器 / Smart Actions / SliceAI as MCP server）默认进入 Phase 2–5 的"候选池"，不是承诺。真正进入冻结需要独立 spec 评审。

| Phase | 主题 | 状态 | 时长（人天） | 对外可见新功能 | 关键产出 |
|---|---|---|---|---|---|
| **0** | 底层重构 | **Freeze** | 15–21（M1+M2+M3） | **无**（只重构） | Orchestration + Capabilities 骨架、Tool 三态、ExecutionSeed/ResolvedContext、Permission + Provenance + PermissionGraph + PathSandbox hook、v2 schema + 独立 config 路径 |
| **1** | MCP + Context 主干 | **Freeze** | 20–30 | MCP 支持 / 5 个核心 ContextProvider / Per-Tool Hotkey | MCPClient（stdio + SSE）+ MCPServersPage + AgentExecutor + `web-search-summarize` 首个真 Agent Tool |
| **2** | Skill + 多 DisplayMode | Directional | — | Skill 接入 / replace / bubble / structured / TTS | 进入前重新 spec |
| **3** | Prompt IDE + 本地模型 | Directional | — | Playground / A-B / Ollama & Anthropic 原生 / Memory | 进入前重新 spec |
| **4** | 生态与分享 | Directional | — | Tool Pack / Marketplace / SliceAI as MCP server / Shortcuts / Services | 进入前重新 spec；Pack 签名体系在 §3.9.4 已埋 hook |
| **5** | 高级编排 | Directional | — | Pipeline / 智能路由 / Smart Actions | 进入前重新 spec |

每个 Freeze phase 结束都发一个 minor version（Phase 0 → v0.2，Phase 1 → v0.3），前置条件是上一 phase 全绿。Directional phase 的版本号分配到进入时再定。

### 4.2 Phase 0：底层重构（**最关键**）

#### 4.2.1 目标

- 把 §3 描述的架构落地为可运行代码。
- 现有功能 100% 保留，用户视觉无感知。
- 引入新 target 但不填实现（留接口，让 Phase 1 实施者一眼能看到要做什么）。

#### 4.2.2 范围（Out-of-Scope 要明确）

- ❌ 不写任何 MCP 实际调用
- ❌ 不加 Skill 实际加载
- ❌ 不新增任何 UI 功能（Settings 页面保持现状）
- ❌ 不换 Provider（仍只 OpenAI 兼容）
- ✅ 仅做数据模型升级 + 配置迁移 + 执行引擎骨架

#### 4.2.3 任务拆分：M1 → M2 → M3 三个 Milestone

> **评审修正（采纳 P1-1）**：初版把 22 个任务打成一包，单次 PR 难 review、难回滚。改为三个 **独立可 merge** 的 Milestone，每个 Milestone 产出一个独立 PR，上一个未 merge 前下一个不启动。拆分依据不是"兼容 vs 破坏"（worktree 隔离已解决兼容性），而是**依赖最小化**——M1 只碰 SliceCore，M2 只碰新增 target，M3 才动 AppContainer 与触发链路。

##### Milestone M1 · 纯数据模型 + 配置迁移（6–8 人天）

目标：SliceCore 所有新类型就位，Configuration v2 的读写 + v1→v2 迁移测试齐全；**Orchestration 尚未接入** —— 此时 app 仍跑旧 `ToolExecutor`，行为零变化。

| # | 任务 | 人天 | 交付物 |
|---|---|---|---|
| M1.1 | 新增 `Orchestration` + `Capabilities` 空 library target | 0.5 | `Package.swift` 更新 + 两个空 `README.md` |
| M1.2 | `SliceCore/ExecutionSeed.swift` + `ResolvedExecutionContext.swift` + `SelectionSnapshot.swift` 重命名 | 1.5 | 新类型 + 单测（构造、等价、透传） |
| M1.3 | `SliceCore/Context.swift`：`ContextKey` / `ContextRequest` / `ContextProvider` protocol（**含 `inferredPermissions(for args:)` 协议方法，D-24**） | 1 | protocol + 注册点 + `Requiredness` enum |
| M1.4 | `SliceCore/Permission.swift` + `Provenance.swift`（**含 `.selfManaged` case，D-23**）+ `SideEffect.inferredPermissions` 映射 | 1 | enum + `PermissionGrant` + `Provenance` 结构 + 单测 |
| M1.5 | `SliceCore/Tool.swift` 改造为三态 `ToolKind`（prompt/agent/pipeline） | 2 | 新 Tool + 反序列化兼容 v1 扁平结构的测试 |
| M1.6 | `SliceCore/Provider.swift` 加 `capabilities: Set<ProviderCapability>` + `ProviderSelection` enum | 1 | 新 Provider + 单测 |
| M1.7 | `SliceCore/OutputBinding.swift` + `SideEffect` | 0.5 | 新类型 |
| M1.8 | `SliceCore/Skill.swift` + `MCPDescriptor.swift`（数据结构骨架） | 0.5 | 类型 + 占位文档 |
| M1.9 | `Configuration` v2 + `ConfigMigratorV1ToV2` + **独立路径** `config-v2.json` | 2 | migrator + 10+ fixture（v1 各形态 → v2）+ 单测 |

**M1 Definition of Done**：
- [ ] `swift test SliceCoreTests` 全绿；覆盖率 ≥ 90%。
- [ ] App 仍启动到 v0.1 行为（因为 AppContainer 未改）。
- [ ] 作者本人的 `config.json` 被 migrator 生成 `config-v2.json`，diff 对比无字段丢失。
- [ ] PR 独立可 merge；不影响任何现有模块。

---

##### Milestone M2 · Orchestration + Capabilities 骨架（6–8 人天）

目标：执行引擎、上下文采集器、权限 broker、成本记账、审计日志、路径沙箱、Prompt executor 全部成型，**可独立单测**但尚未在 app 启动链路中接入。

| # | 任务 | 人天 | 交付物 |
|---|---|---|---|
| M2.1 | `Orchestration/ExecutionEngine.swift` 骨架 + `ExecutionEvent` | 1.5 | actor + 事件流 + dry-run 分支 + 单测（Mock Provider） |
| M2.2 | `Orchestration/ContextCollector.swift`（**平铺并发，非 DAG**） | 1.5 | `resolve(seed:requests:) -> ResolvedExecutionContext` + timeout + failures 记录 + 单测 |
| M2.3 | `Orchestration/PermissionBroker.swift`（接口 + 默认全放行实现，但 **§3.9.2 下限约束在此层硬编码**） | 1 | `gate(effective:provenance:scope:isDryRun:)` + grant store + 单测覆盖 §3.9.2 表（firstParty 不能放行 exec / network-write） |
| **M2.3a** | **`Orchestration/PermissionGraph.swift`（D-24 新增）**：`compute(tool:) -> EffectivePermissions` + `ExecutionEngine` Step 2 静态校验 ⊆ | 1 | 单测覆盖：未声明的 context permission 导致 `.failed(.permission(.undeclared))`；多种 tool.kind 均命中 |
| M2.4 | `Orchestration/CostAccounting.swift` | 1 | sqlite schema + 写入 API + 单测 |
| M2.5 | `Orchestration/AuditLog.swift` | 1 | jsonl append + 脱敏（§3.9.5）+ 单测（含 `logCleared` 事件） |
| M2.6 | `Orchestration/OutputDispatcher.swift`（**仅 window 分支**，其余 mode 返回 `.notImplemented` 事件） | 0.5 | 路由 + 单测 |
| M2.7 | `Orchestration/PromptExecutor.swift`（从旧 `ToolExecutor` **复制** 逻辑到新文件，**不替换**旧文件） | 1 | 新 executor + 单测；旧 ToolExecutor 保留 |
| M2.8 | `Capabilities/SecurityKit/PathSandbox.swift`（路径规范化 + 白名单） | 0.5 | 工具 + 单测覆盖所有硬禁止路径 |
| M2.9 | `Capabilities` 预留 `MCPClientProtocol` `SkillRegistryProtocol` | 0.5 | 接口 + Mock 实现 |

**M2 Definition of Done**：
- [ ] `swift test OrchestrationTests CapabilitiesTests` 全绿；`Orchestration` 覆盖率 ≥ 75%。
- [ ] ExecutionEngine 单测覆盖 `.prompt` kind 的 happy / context-fail / permission-deny / dry-run 四条路径。
- [ ] 旧 `ToolExecutor` **保留不动**，app 行为仍为 v0.1；AppContainer 未改动。
- [ ] PR 独立可 merge。

---

##### Milestone M3 · 切换 + 删旧 + 端到端回归（3–5 人天）

目标：把 AppContainer / 触发通路切到 `ExecutionEngine`，删除旧 `ToolExecutor`，配置改读 `config-v2.json`，端到端回归通过。

| # | 任务 | 人天 | 交付物 |
|---|---|---|---|
| M3.1 | `SliceAIApp/AppContainer.swift` 装配 `ExecutionEngine` + 各依赖 | 1 | 装配链路 + 启动冒烟 |
| M3.2 | 触发通路（FloatingToolbar / CommandPalette）从 `ToolExecutor.execute` 切到 `ExecutionEngine.execute(tool:seed:)` | 1 | 对齐 `ExecutionSeed` 构造方式 |
| M3.3 | `ConfigurationStore` 启动时按 §3.7 规则选择 v1/v2 路径，运行 migrator | 0.5 | 启动逻辑 + 单测 |
| M3.4 | 删除 `SliceCore/ToolExecutor.swift` | 0.5 | PR |
| M3.5 | 端到端手动回归（见 §4.2.5） | 1.5 | checklist 全过 |
| M3.6 | 更新 `README.md` 项目修改变动记录、Module 文档、Task-detail | 1 | 文档 |

**M3 Definition of Done**：
- [ ] `swift build` / `swift test --parallel` / `swiftlint lint --strict` / `xcodebuild` 全绿。
- [ ] §4.2.5 回归清单手工跑完全过。
- [ ] 原 4 个内置工具在实机行为与 v0.1 等价。
- [ ] `config-v2.json` 实际生成；旧 `config.json` 未被修改。
- [ ] 旧分支 app（切回 v0.1 worktree）仍能打开旧 `config.json` 正常工作。

---

**Phase 0 合计人天**：15–21（M1: 6–8 + M2: 6–8 + M3: 3–5；比初版 22–27 更紧凑，因为移除了 "ExecutionContext 重复建模" 等冗余并把 DAG 延后；M2 加了 PermissionGraph 补 1 人天）。加 buffer 20% → **19–26 人天**。

#### 4.2.4 整体 Definition of Done（M1 + M2 + M3 全部合入）

- [ ] `swift build` 成功（全 10 个 target）。
- [ ] `swift test --parallel --enable-code-coverage` 全绿；`SliceCore` 覆盖率 ≥ 90%，`Orchestration` ≥ 75%，`Capabilities` ≥ 60%。
- [ ] `swiftlint lint --strict` 0 violations。
- [ ] 原 4 个内置工具在实机上与 v0.1 行为等价（翻译 / 润色 / 总结 / 解释）。
- [ ] 老 `config.json` 经 migrator 产出 `config-v2.json`；**旧 `config.json` 未被修改**；切回旧分支 app 仍正常。
- [ ] Settings 界面无功能变化（不要误加 UI）。
- [ ] PR 不引入任何 TODO / FIXME 注释（要做的留成 Issue）。
- [ ] `docs/Task-detail/phase-0-*.md` 归档 M1/M2/M3 各自的实施过程。

#### 4.2.5 回归测试清单（M3 手工跑）

- Safari 划词翻译 → 弹浮条 → 点"Translate"→ ResultPanel 流式。
- ⌥Space → 面板 → 搜索 → 选工具 → 同上。
- Regenerate / Copy / Pin / Close / Retry / Open Settings。
- Accessibility 权限 revoke 后的降级提示。
- 无 API Key 时的错误提示。
- 修改 Tool / Provider 后配置立即生效并**写入 `config-v2.json`**（不写 `config.json`）。
- 将 `config-v2.json` 删除后重启：app 能从 `config.json` 重新 migrate。
- 同一机器切回旧分支 / 旧 build：旧 app 读取原 `config.json` 仍正常（验证独立路径保护有效）。

### 4.3 Phase 1：MCP + Context 落地

#### 4.3.1 目标

- 把 Phase 0 的 `ContextProvider` / `MCPClient` / `AgentExecutor` 填实。
- 用户可以在 Settings 里加 MCP server，并在 Tool 里勾选哪些 MCP tool 可用。
- Per-Tool Hotkey 生效。

#### 4.3.2 关键交付

| # | 项目 | 说明 |
|---|---|---|
| 1.1 | `Capabilities/MCPClient`（stdio） | 子进程管理、JSON-RPC framing、懒启动、idle 超时 |
| 1.2 | `Capabilities/MCPClient`（SSE） | 远程 MCP server |
| 1.3 | `SettingsUI/Pages/MCPServersPage` | 增删改、测试连接、查看暴露的 tool 列表 |
| 1.4 | 兼容 Claude Desktop 的 `mcp.json` 格式 | 用户导入一次搞定 |
| 1.5 | `Orchestration/AgentExecutor` | ReAct loop + tool call 审批 UI |
| 1.6 | 5 个核心 ContextProvider 实现 | `selection` `app.windowTitle` `app.url` `clipboard.current` `file.read` |
| 1.7 | `HotkeyManager` 支持多组 hotkey | Per-Tool Hotkey |
| 1.8 | `Windowing/ResultPanel` 增加 tool call 展示 | 折叠/展开 + 参数 + 结果 |
| 1.9 | `PermissionBroker` 真实接入 | Tool install 时批量授权、执行时 gate |
| 1.10 | **首个真实 Agent Tool**：`web-search-summarize` | MCP: brave-search + agent loop + Markdown 总结 |

#### 4.3.3 Definition of Done

- [ ] 可从 Claude Desktop 直接复制 `mcp.json` 并工作。
- [ ] 至少 5 个 MCP server 验证通过（filesystem / postgres / brave-search / git / sqlite）。
- [ ] Tool Permission 的一键同意 / 撤销 UX 有测试。
- [ ] `web-search-summarize` Tool 在 Safari / Notes / Slack 三个场景 E2E 通过。
- [ ] 新增文档 `docs/Module/MCPClient.md` `docs/Module/ContextProviders.md`。

### 4.4 Phase 2：Skill + 多 DisplayMode

#### 4.4.1 目标

- 把 Anthropic Skills 规范的 skill 包引入 SliceAI。
- `replace / bubble / structured / silent` 四种 DisplayMode 真正可用。

#### 4.4.2 关键交付

| # | 项目 | 说明 |
|---|---|---|
| 2.1 | `Capabilities/SkillRegistry` | 扫描目录、解析 SKILL.md、加载资源 |
| 2.2 | `SettingsUI/Pages/SkillsPage` | 管理 skills、查看 manifest、一键打开 skill 目录 |
| 2.3 | `Windowing/BubblePanel` | 小气泡，2.5s 自动消失 |
| 2.4 | `Windowing/InlineReplaceOverlay` | AX setSelectedText + 确认撤销浮条 |
| 2.5 | `Windowing/StructuredResultView` | JSONSchema → SwiftUI 表单 + 每条副作用按钮 |
| 2.6 | `Capabilities/TTSCapability` | AVSpeech + OpenAI TTS 切换 |
| 2.7 | `Orchestration/OutputDispatcher` 填充所有 DisplayMode | 完整 |
| 2.8 | Anthropic Skills 兼容性测试 | 覆盖 `obra/superpowers` 等公开仓库的 skill |
| 2.9 | 新内置 Tool Pack：`english-tutor`（用到 skill + structured + TTS） | Phase 2 的 demo tool |

#### 4.4.3 Definition of Done

- [ ] 至少 3 个公开 Anthropic Skill 能在 SliceAI 中直接工作。
- [ ] `english-tutor` Tool 能触发"语法分析 + 改写 + 朗读"全流程。
- [ ] `replace` 模式在 Notes / VSCode 上通过；Figma / Slack 降级为复制 + 通知。
- [ ] `structured` 模式支持动态表单渲染（至少 5 种字段类型）。

### 4.5 Phase 3：Prompt IDE + 本地模型

#### 4.5.1 目标

- Tool 编辑器升级为 Prompt Playground。
- 原生支持 Anthropic / Gemini / Ollama 三家（不再经 OpenAI 兼容协议）。
- Per-Tool Memory 可用。

#### 4.5.2 关键交付

| # | 项目 |
|---|---|
| 3.1 | `SettingsUI/ToolEditor v2`（左侧配置 + 右侧 Playground） |
| 3.2 | 测试用例管理（保存样本 selection + expected output） |
| 3.3 | A/B 双栏对比（两个 prompt 版本并排跑） |
| 3.4 | Version history（Tool 每次保存产生 snapshot） |
| 3.5 | `LLMProviders/AnthropicProvider`（Prompt Caching + Extended Thinking） |
| 3.6 | `LLMProviders/GeminiProvider`（Grounding + JSON Schema） |
| 3.7 | `LLMProviders/OllamaProvider`（本地直连） |
| 3.8 | `Capabilities/Memory`（jsonl + FTS index） |
| 3.9 | `SettingsUI/Pages/MemoryPage` |
| 3.10 | "Cost Panel" 显示 token / usd 汇总 |
| 3.11 | Tool 可声明 `privacy: local-only` 强制本地 provider |

#### 4.5.3 Definition of Done

- [ ] 同一 Tool 可以通过 Playground 并排跑 Claude Sonnet 4.6 / GPT-5 / Llama3.3 三家。
- [ ] Per-Tool Memory 能注入 prompt 并通过 E2E 测试。
- [ ] `privacy: local-only` 的 Tool 在无 Ollama 运行时正确报错。
- [ ] Cost Panel 数据与真实 Provider 账单偏差 < 5%。

### 4.6 Phase 4：生态与分享

#### 4.6.1 目标

- 让 Tool 可以被打包、分享、安装。
- 让 SliceAI 本身成为 MCP server，被其他 AI 客户端消费。
- 开放 Shortcuts / Services / URL Scheme 三条外部入口。

#### 4.6.2 关键交付

| # | 项目 |
|---|---|
| 4.1 | `.slicepack` 格式定义 + 打包脚本 |
| 4.2 | `SettingsUI/Pages/MarketplacePage`（从静态站下载安装） |
| 4.3 | `tools.sliceai.app` 静态站（GitHub Pages） |
| 4.4 | Tool Pack 元数据规范（author / license / screenshots / rating） |
| 4.5 | SliceAI 启动 MCP server（stdio），暴露用户的 Tool |
| 4.6 | AppIntents：每个 Tool 自动映射为 Shortcuts Action |
| 4.7 | Services 菜单注册（macOS Services） |
| 4.8 | URL Scheme（`sliceai://run/<tool-id>?text=...`） |
| 4.9 | 官方 Starter Packs（English Learning / Code / Research / Writing / Productivity / Dev DX） |
| 4.10 | Signing + Notarization（决定是否迈出这步，见 §5.1） |

#### 4.6.3 Definition of Done

- [ ] 从 Marketplace 一键安装 5 个 Starter Pack 全部成功。
- [ ] Claude Desktop 中添加 SliceAI 为 MCP server，能调用到 SliceAI 的 Tool。
- [ ] macOS Shortcuts 中出现 SliceAI Action。
- [ ] Safari 右键 → Services → SliceAI Tool 可用。

### 4.7 Phase 5：高级编排

#### 4.7.1 目标

- `.pipeline` Tool Kind 真正可用。
- 按选区内容类型动态推荐工具（Smart Actions）。
- `cascade` 智能路由落地。

#### 4.7.2 关键交付

| # | 项目 |
|---|---|
| 5.1 | `Orchestration/PipelineExecutor` |
| 5.2 | Pipeline 可视化编辑器（节点图） |
| 5.3 | `ContentClassifier`（规则 + 可选本地小模型） |
| 5.4 | 浮条的动态工具排序（按内容类型 + 使用频率） |
| 5.5 | `cascade` 规则执行 + provider fallback |
| 5.6 | Agent 的 `stepCompleted` 回调接入 Pipeline 进度条 |

#### 4.7.3 Definition of Done

- [ ] 至少 3 个内置 Pipeline 工具（Translate→Anki、Commit→Push、Paper→Notion）。
- [ ] 选中代码时浮条首位自动变成"Explain Code"，选中 URL 时自动变成"Summarize Webpage"。
- [ ] Cascade 规则在"长文本 > 8k token 走 Claude Haiku"场景下工作正确。

### 4.8 版本时间线（参考）

| 版本 | 阶段 | 状态 | 估计日期 |
|---|---|---|---|
| v0.1.x | MVP UI 收尾 | 已完成 | 2026-04 |
| v0.2 | Phase 0（M1/M2/M3） | **Freeze，可进入实施** | 2026-05 ~ 2026-06 |
| v0.3 | Phase 1（MCP + Context 主干） | **Freeze，等 Phase 0 完成后出独立 plan** | 2026-07 |
| — | Phase 2（Skill + 多 DisplayMode） | Directional，进入前重新 spec | 待定（≥ 2026-08） |
| — | Phase 3（Prompt IDE + 本地模型） | Directional | 待定 |
| — | Phase 4（生态与分享） | Directional | 待定 |
| — | Phase 5（高级编排） | Directional | 待定 |
| v1.0 | 全功能稳定版 + 签名公证 | 待 Phase 4 后评估 | 2026 年底前不承诺 |

（单人节奏估算，仅 Phase 0–1 有时间承诺，其余 phase 进入前重新评估。）

---

## 5. 风险与关键决策

### 5.1 关键技术风险

| 风险 | 概率 | 影响 | 缓解 |
|---|---|---|---|
| **MCP stdio 子进程在 macOS sandbox 下启动受限** | 中 | 高 | v0.1 已是 unsigned 非 sandbox；Phase 4 之前不进 sandbox；若 Phase 4 要 notarize，允许 `com.apple.security.inherit` 但评估是否改为 "带 helper tool" 方案 |
| **AX setSelectedText 在 Electron app 不工作** | 高 | 中 | Phase 2 设计时就默认会失败，有 clipboard + paste 降级路径 |
| **Extended Thinking / Prompt Caching 在 OpenAI 兼容协议不可用** | 高 | 中 | Phase 3 引入原生 Anthropic provider 解决 |
| **本地 Ollama 的 function-calling 支持不稳定** | 高 | 中 | 本地 Agent Tool 明确标记"实验性"；优先保证 Prompt Tool 本地可用 |
| **Skill 目录结构 Anthropic 未来变动** | 中 | 中 | SkillRegistry 做 version 字段；变动时出迁移脚本 |
| **Tool Pack 格式社区难统一** | 中 | 高 | Phase 4 前先锁 schema；变动走 schemaVersion + deprecation window |
| **Prompt 注入攻击（MCP 返回值诱导 LLM 调恶意 tool）** | 中 | 高 | Phase 1 起所有 tool call 默认需要用户确认；引入"只读 / 可写 / 危险"三级标签 |
| **成本失控（agent loop 死循环）** | 中 | 高 | `maxSteps` 硬限 + per-tool budget + 全局 budget + 超限硬停 |
| **CPU / 内存在 MCP server 数量增多时膨胀** | 中 | 中 | idle 超时回收 + 每 server RSS watchdog |

### 5.2 关键决策记录（v2.0）

| # | 决策 | 备选方案 | 选择理由 |
|---|---|---|---|
| D-1 | Tool 三态（prompt/agent/pipeline）而非单态 | 单态 + 字段组合 | 三态封闭集合清晰、执行器可独立优化；单态字段组合会让非法组合爆炸 |
| D-2 | MCP 与 Skill 提前到 Phase 1–2 | 按 v1.0 放 v0.2+ | 产品定位需要；推迟等于产品不成立 |
| D-3 | ExecutionContext 不可变（INV-6） | 可变 + mutation 通知 | 可重放、可 dry-run、便于审计 |
| D-4 | Provider 抽象加 `capabilities` | 每家 provider 各自 ad-hoc | 让 Tool 声明能力需求而非绑定 provider，未来新加 provider 零改动 |
| D-5 | Orchestration 作为独立 target | 塞进 SliceCore | SliceCore 零副作用（INV-1）不能放执行逻辑 |
| D-6 | SliceAI 作为 MCP server | 仅作为 MCP client | 让 SliceAI 融入 AI 生态而不只是工具壳，Claude Desktop / Cursor 可反向调用 |
| D-7 | `.slicepack` 文件夹格式而非单 JSON | 单 JSON | 需要带 SKILL.md / 资源 / 截图，文件夹天然承载 |
| D-8 | 兼容 Claude Desktop 的 `mcp.json` | 自创格式 | 降低用户迁移成本到零 |
| D-9 | schemaVersion 硬升级到 2 | 在 v1 schema 中加字段 | 模型变化太大，硬升级 + 自动迁移更干净 |
| D-10 | Agent loop 每次 tool call 默认需用户确认 | 自动执行 | 安全 > 效率；Tool 可声明"自动批准白名单" |
| D-11 | AuditLog 写 jsonl + Cost 写 sqlite | 都写 sqlite | jsonl 追加安全、易手动查；sqlite 便于汇总查询 |
| D-12 | 不自研 Prompt DSL，用 Mustache + helpers | 自研 | 不浪费资源造轮子 |
| D-13 | 保留 OpenAI 兼容作为一种 Provider kind | 直接替换为各家原生 | 国内中转 + OpenRouter 仍需要；OpenAI 兼容是 adapter 不是主协议 |
| D-14 | MCP server 独立进程（stdio） | in-process 插件 | 崩溃隔离、安全、兼容社区生态 |
| D-15 | `outputBinding.sideEffects` 作为数据字段而非 UI 按钮组 | UI-only | 副作用声明式可被 dry-run / Playground 复用 |
| **D-16** | **两阶段执行上下文**：`ExecutionSeed`（触发层产出）→ `ResolvedExecutionContext`（ContextCollector 产出） | 单 `ExecutionContext` + mutation | 采纳 Codex 评审 P1-4：初版"不可变 + 回填"自相矛盾；两阶段模型让 INV-6 真正可守 |
| **D-17** | **Phase 0–1 放弃 Context DAG**，ContextCollector 只做平铺并发 | Phase 0 起就做 DAG | 采纳 Codex 评审 P1-4：真实场景 90% 上下文独立，强依赖型适合 Pipeline 而非 Collector；DAG 留到有真实诉求再加 |
| **D-18** | **v2 期间使用独立 `config-v2.json` 路径**，不覆盖 v1 `config.json` | 直接升级覆盖 | 采纳 Codex 评审 P1-2（轻量版）：即便无外部用户，作者跨 worktree / 旧分支 app 仍会冲突；独立路径是最小代价的隔离 |
| **D-19** | **Freeze 范围收敛到 Phase 0–1**，Phase 2–5 降为 Directional Outline | 全 phase 一次性冻结 | 采纳 Codex 评审 P2-1：提前冻结 Phase 2+ 会强加过早抽象；每个 phase 进入前独立 spec 评审更健康 |
| **D-20** | **Phase 0 拆 M1/M2/M3 三个独立 PR**，而非一次大重构 | 单一 Phase 0 PR | 采纳 Codex 评审 P1-1（重新定性）：不因风险（worktree 已隔离），而因可 review 性；三段依赖最小化，M1 只碰 SliceCore，M2 只碰新 target，M3 才切 AppContainer |
| **D-21** | **§3.9 独立 Security Model**（来源分级 + 能力分级 + 路径沙箱 + 日志脱敏 + 默认拒绝） | 仅 Permission 枚举 + 弹窗 | 采纳 Codex 评审 P1-3：MCP / shell / Marketplace 的信任边界必须在 Phase 0 就有 hook，而不是 Phase 4 赶工 |
| **D-22** | **能力分级是最低下限，Provenance 只能在下限之上放宽 UX，不能突破下限**；`exec` / `network-write` 无论来源都要每次确认 | firstParty 全能力默认静默 | 采纳 Codex 第二轮评审 P1-1：不可逆副作用不应因来源而下放；"默认安全"优先于"默认便利" |
| **D-23** | **stdio MCP server ≡ 用户身份下本地代码执行**，Phase 1 只支持 `firstParty` / `selfManaged`（用户审读后接受），**`unknown` 来源的 MCP config 直接拒绝导入** | 运行时 gate 兜底所有来源 | 采纳 Codex 第二轮评审 P1-2：PermissionBroker 只能约束协议面，无法约束 server 进程自主系统访问；必须在安装时决定信任 |
| **D-24** | **权限声明闭环**：执行前静态计算 `effectivePermissions`（来自 contexts + sideEffects + mcpAllowlist + builtins），必须 ⊆ `tool.permissions`，否则直接失败 | 只 check `tool.permissions`，运行时由 PathSandbox 兜底 | 采纳 Codex 第二轮评审 P1-3：避免"授权清单里没有、但实际访问发生"；要求 `ContextProvider.inferredPermissions` 协议级实现，Phase 0 M1/M2 就位 |
| **D-25** | **Provenance 只调节 UX 文案，不减少确认次数**；`Provenance` canonical 定义唯一化到 `SliceCore/Permission.swift`（§3.3.5） | 第二轮写的"firstParty 对 readonly-network / local-write 已声明即授权" | 采纳 Codex 第三轮评审 P1-2：多处规则（§3.9.1 / §3.9.2 / §3.9.6）必须同时成立；"已声明即授权"会让 PermissionBroker 测试矩阵不唯一、且违反"默认安全"。统一为"下限由 capability 决定，provenance 只改 UX"。副产品：三处 Provenance 定义收敛到一处，canonical schema 闭合（配合 D-24） |

### 5.3 待验证假设（Open Questions）

记录我尚未能 100% 把握的假设，实施时需要先验证：

1. Anthropic Skills 规范在 2026-04 时的稳定度？（若仍在快速变动，我们的 SkillRegistry 可能需频繁更新。）—— **Phase 2 进入前需答**
2. macOS Sonoma / Sequoia / Tahoe 上 AX `setSelectedText` 在 Safari / Notes / Xcode / VSCode / Slack / Figma / Discord 的成功率矩阵？—— **Phase 2 进入前需答**；Phase 0 期间可并行做实机调研
3. Ollama 的 function-calling 在 2026 年的主流模型（Llama 3.3、Qwen 3、DeepSeek V3）上稳定度？—— **Phase 3 进入前需答**
4. macOS Services 菜单在 unsigned app 上是否受限？—— **Phase 4 进入前需答**
5. 用户对"Tool Permission 弹窗确认"的容忍度——多少次确认后就烦了？需要早期用户测试。—— **Phase 1 早期验收** `web-search-summarize` Tool 时观察
6. `.slicepack` / MCP server 的 import 安全 —— **已由 §3.9 部分回答，但需区分两类**：
   - **Pack / Skill（纯静态资源）**：签名校验 + `provenance=.unknown` 默认全权限拒绝 + 运行时能力分级 gate 足够。安装过程不执行代码，所以不需要 sandboxing。
   - **MCP server（独立进程）**：**进程隔离 ≠ 权限隔离**。stdio MCP server 启动后等同于用户身份下本地代码执行，SliceAI 的 PermissionBroker 只能约束协议面。因此 Phase 1 硬约束：`unknown` 来源的 MCP config **直接拒绝导入**（见 §3.9.4.2 + D-23）；未来是否引入真正的 server 侧 sandbox（sandbox-exec / seatbelt / Docker）在 Phase 4 Marketplace 进入前再独立评估。
   - **遗留疑问**：`selfManaged` 的"用户审读后接受"UX 如何设计？仅一次文本警告是否足够？需要 Phase 1 早期在实机 UX 迭代中验证。
7. （新增）`PermissionGrant` 的持久化粒度："本次会话"（进程级）vs "今日"（24h）vs "永久"三种 scope 哪种是默认？需在 Phase 1 的 `web-search-summarize` Tool 上做 A/B。

这些问题在对应 phase 的 plan.md 中必须先给出答案。

---

## 6. 成功指标

### 6.1 产品指标（到 v1.0）

- **活跃用户**：DAU ≥ 5000（开源工具口径：启动过 App 一次即算）。
- **用户留存**：7 日留存 ≥ 40%。
- **Tool 创建**：活跃用户平均自建 ≥ 3 个 Tool（表示真的"把想象力变成配置"）。
- **MCP 装机**：活跃用户中 ≥ 25% 安装至少一个 MCP server（表示定位被接受）。
- **Marketplace**：至少 30 个社区贡献的 Tool Pack。

### 6.2 技术指标

- **启动到可用**：冷启动 ≤ 1.5s。
- **划词响应**：mouseUp → 浮条 ≤ 200ms（延续 v0.1 目标）。
- **Agent 首字节**：触发 → 首 token ≤ 1.2s（含 context 采集 + MCP 启动）。
- **测试覆盖**：SliceCore ≥ 90%、Orchestration ≥ 75%、LLMProviders ≥ 80%、Capabilities ≥ 60%。
- **CI 时长**：PR 全流程 ≤ 6 分钟。

### 6.3 社区指标

- **GitHub Stars**：v1.0 前达到 5k+。
- **贡献者数**：至少 30 个 merged PR 的非维护者贡献者。
- **HN / Product Hunt**：Phase 4 发布 Marketplace 时上 HN 首页、Product Hunt 当日 Top 5。

---

## 7. 附录

### 附录 A：新旧 spec 字段变更对比

| 字段 / 概念 | v1.0 | v2.0 | 迁移方式 |
|---|---|---|---|
| `Tool` 结构 | 单态，扁平 prompt/provider 字段 | 三态（prompt/agent/pipeline） | 自动映射到 `.prompt` |
| `Tool.variables` | `[String:String]` 静态 | 保留静态 + 新增 `contexts: [ContextRequest]` | 直接兼容 |
| `Provider.providerId` | Tool 绑死一个 | `ProviderSelection` 可按 capability | 旧值映射到 `.fixed` |
| `SelectionPayload` | 一个 struct | `ExecutionSeed.selection: SelectionSnapshot`（`ExecutionSeed` + `ResolvedExecutionContext` 两阶段只读） | 重命名 + 合入更大结构；执行链改用 seed 入参 |
| `DisplayMode` | `window/bubble/replace`（后两者未实现） | 六种全部作为正式模式 | 旧值不变，新模式在 Phase 2+ 启用 |
| Permissions | 无 | 显式 `Permission` 列表 | 老工具迁移时推导默认权限 |
| Budget | 无 | per-tool + global | 默认无限制 |
| Hotkey | 仅全局 toggleCommandPalette | 全局 + per-tool | 旧 config 无 per-tool |
| MCP | Roadmap 未实现 | Phase 1 落地 | 新增 |
| Skill | Roadmap 未实现 | Phase 2 落地 | 新增 |
| Memory | 无 | Phase 3 落地 | 新增 |
| Marketplace | 无 | Phase 4 落地 | 新增 |
| `schemaVersion` | 1 | 2（Phase 0 升级） | `config-v2.json` 独立路径；v1 原文件不动（见 §3.7） |
| Provenance | 无 | 显式 `Provenance` 字段（firstParty / communitySigned / selfManaged / unknown） | 迁移器给所有 v1 Tool 赋 `.firstParty`；`Skill` / `MCPDescriptor` 由安装流程写入 |
| 安全模型 | 无 | §3.9 Security Model（下限不可放宽 + MCP 威胁建模 + 权限声明闭环 + PathSandbox + 脱敏） | Phase 0 M1/M2 埋 hook；Phase 1 填实 |

### 附录 B：核心数据模型伪代码汇总

```swift
// ========== SliceCore/Tool.swift ==========
public struct Tool: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var name: String
    public var icon: String
    public var description: String?
    public var kind: ToolKind
    public var visibleWhen: ToolMatcher?
    public var displayMode: DisplayMode
    public var outputBinding: OutputBinding?
    public var permissions: [Permission]    // D-24: 必须覆盖所有 effective permission
    public var provenance: Provenance       // D-23: 安装流程写入
    public var budget: ToolBudget?
    public var hotkey: String?
    public var labelStyle: ToolLabelStyle
    public var tags: [String]
}

public enum ToolKind: Codable, Sendable, Equatable {
    case prompt(PromptTool)
    case agent(AgentTool)
    case pipeline(PipelineTool)
}

// ========== SliceCore/Permission.swift ==========
// canonical Provenance 定义见 §3.3.5（含 .firstParty / .communitySigned / .selfManaged / .unknown）
// 本附录仅为查阅索引，不重复定义；任何代码引用以 §3.3.5 为准

// ========== SliceCore/Skill.swift / MCPDescriptor.swift ==========
// Skill / MCPDescriptor 均带 `provenance: Provenance`（见 §3.3.8）

// ========== SliceCore/ExecutionSeed.swift ==========
public struct ExecutionSeed: Sendable, Equatable {
    public let invocationId: UUID
    public let selection: SelectionSnapshot
    public let frontApp: AppSnapshot
    public let screenAnchor: CGPoint
    public let timestamp: Date
    public let triggerSource: TriggerSource
    public let isDryRun: Bool
}

// ========== SliceCore/ResolvedExecutionContext.swift ==========
public struct ResolvedExecutionContext: Sendable, Equatable {
    public let seed: ExecutionSeed
    public let contexts: ContextBag
    public let resolvedAt: Date
    public let failures: [ContextKey: SliceError]
}

// ========== SliceCore/Provider.swift ==========
public struct Provider: Identifiable, Codable, Sendable, Equatable {
    public let id: String
    public var kind: ProviderKind           // .openAICompatible / .anthropic / .gemini / .ollama
    public var name: String
    public var baseURL: URL?
    public var apiKeyRef: String?
    public var defaultModel: String
    public var capabilities: Set<ProviderCapability>
}

// ========== Orchestration/ExecutionEngine.swift ==========
public actor ExecutionEngine { /* 见 §3.4 */ }

// ========== SliceCore/Context.swift ==========
public protocol ContextProvider: Sendable {
    var name: String { get }
    static func inferredPermissions(for args: [String: String]) -> [Permission]  // D-24
    func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue
}

// ========== SliceCore/OutputBinding.swift ==========
public enum SideEffect: Codable, Sendable, Equatable { /* 见 §3.3.6 */ }
public extension SideEffect {
    var inferredPermissions: [Permission] { /* 见 §3.3.6 */ }   // D-24
}

// ========== Orchestration/PermissionGraph.swift ==========
public struct EffectivePermissions: Sendable, Equatable {
    public let declared: Set<Permission>
    public let fromContexts: Set<Permission>
    public let fromSideEffects: Set<Permission>
    public let fromMCP: Set<Permission>
    public let fromBuiltins: Set<Permission>
    public var union: Set<Permission> { /* 并集 */ }
    public var undeclared: Set<Permission> { union.subtracting(declared) }
}
```

### 附录 C：实施时的参考顺序（对应 §4.2.3 M1/M2/M3 拆分）

**M1 · 纯数据模型 + 配置迁移**（一个 PR）
1. M1.1 先建 `Orchestration` / `Capabilities` 空 target → 让 `Package.swift` 和 CI 先挂起来。
2. M1.2–M1.4 做"与执行无关的基础类型"：`ExecutionSeed` / `ResolvedExecutionContext` / `SelectionSnapshot` / `ContextKey` / `ContextRequest` / `ContextProvider` protocol / `Permission` / `Provenance`。
3. M1.5–M1.8 做"上层业务类型"：三态 `Tool` / `Provider` 扩展 / `OutputBinding` / `Skill` / `MCPDescriptor`。
4. M1.9 做 `Configuration` v2 + `ConfigMigratorV1ToV2` + `config-v2.json` 独立路径（v1→v2 映射给所有 Tool 补 `provenance = .firstParty`；`Skill` / `MCPDescriptor` 的 provenance 由安装流程负责写入）。
5. 合并前：`swift test SliceCoreTests` 全绿；app 行为仍为 v0.1。

**M2 · Orchestration + Capabilities 骨架**（一个 PR）
6. M2.1 `ExecutionEngine` 骨架（入参 `ExecutionSeed`，流程按 §3.4 Step 1→10）。
7. M2.2 `ContextCollector`（平铺并发，非 DAG）。
8. M2.3 `PermissionBroker` 接口 + 默认全放行实现 + **按 §3.9.2 下限表跑单测**（验证 exec / network-write 不会因 firstParty 被放行）。
9. M2.4–M2.5 `CostAccounting` + `AuditLog`（含 §3.9.5 脱敏）。
10. M2.6 `OutputDispatcher`（仅 window 分支）。
11. M2.7 `PromptExecutor`（从旧 `ToolExecutor` 复制逻辑，不替换）。
12. M2.8 `PathSandbox`（§3.9.3 白名单校验 + 硬禁止路径单测）。
13. **M2 关键新增**：`PermissionGraph.compute(tool)`（§3.9.6.5，Step 2 静态校验 effectivePermissions ⊆ declared）。
14. M2.9 `MCPClientProtocol` / `SkillRegistryProtocol` 预留。
15. 合并前：`swift test OrchestrationTests CapabilitiesTests` 全绿；覆盖率 ≥ 75%。

**M3 · 切换 AppContainer + 删旧**（一个 PR）
16. M3.1 AppContainer 装配 ExecutionEngine 链路。
17. M3.2 触发通路切到 `ExecutionEngine.execute(tool:seed:)`。
18. M3.3 `ConfigurationStore` 按 §3.7 规则选择 v1/v2 路径 + 跑 migrator。
19. M3.4 删除 `SliceCore/ToolExecutor.swift`。
20. M3.5 端到端手动回归（§4.2.5 清单）。
21. M3.6 更新 README 项目修改变动记录 + Module 文档 + Task-detail。

**不变量**：
- M1 merge 前 app 必须仍跑旧 `ToolExecutor`；M2 merge 前仍跑旧 `ToolExecutor`；M3 才切换。
- 任何一个 milestone 的 PR 如果需要修改另一个 milestone 范围的文件（例如 M2 的 PR 动了 AppContainer），说明拆分有误，要重新 review。

### 附录 D：对外叙事（Launch Narrative）

Phase 4 发布时的叙事（v2.0 规划的信任抵押）：

> **SliceAI 让你在任意 Mac 应用里选中文字，触发一个由 prompt + MCP + Skill 装配的 AI Agent——数据不离开你的电脑，能力由你的想象力决定。**
>
> - 兼容 Claude Desktop 的 MCP 配置，零迁移成本
> - 支持 Anthropic Skills，复用社区几百个 skill
> - 本地模型（Ollama / MLX）与云端模型（OpenAI / Claude / Gemini）平等对待
> - 反向成为 MCP server，让 Claude Desktop 也能调用你的 Tool
> - 全开源、无订阅、无云端账号

### 附录 E：废弃与不再做的设计（明确说明）

| 项 | 原因 |
|---|---|
| v1.0 中的 `DisplayMode.bubble/replace` 实现细节 | v2.0 用更完整的 `OutputBinding` 设计覆盖 |
| v1.0 预设的"只做 OpenAI 兼容" | 定位升级要求原生 provider |
| v1.0 的 `ToolExecutor` actor | 拆分进 Orchestration |
| v1.0 的"不做历史"Non-goal | 弱化——通过 AuditLog + Memory 替代完整对话历史（仍不做 ChatGPT 风格线性历史列表） |

---

## 8. 维护说明

- 本 spec 的 **Phase 0–1 部分** 冻结于 2026-04-23（评审修订版），进入实施前不再扩大范围；新想法记录到 `docs/superpowers/ideas/` 下独立文件，等对应 phase 进入时再合入。
- 本 spec 的 **Phase 2–5 部分** 为 Directional Outline，**不是冻结**：进入前必须独立走 brainstorming + 写独立 spec/plan，避免在未验证假设上层层堆叠。
- 每个 phase 启动前，用独立 `docs/superpowers/plans/YYYY-MM-DD-phase-N-*.md` 展开任务级计划（Phase 0 至少三份：M1 / M2 / M3）。
- 完成每个 phase 后，在本 spec 的对应 §4.x 小节前加 **"状态：已交付 @ commit XXXX"** 字样；不要改原内容。
- 若 §5.3 的待验证假设在实施中被证伪，必须在本 spec 的 §5.2 增加一条新决策记录（不要修改历史决策）。
- 重要评审或设计修订（类似本次 Codex 评审）以同样的方式：在 §0 追加"评审与修订"条目、在 §5.2 追加新决策、在对应正文小节前加修正说明；**不覆盖原文**。

---

_本规划文档由 Claude 与产品负责人在 2026-04-23 的三轮对话中产出：第一轮定位被纠正（AI Writing ≠ SliceAI 定位），第二轮围绕"自定义 prompt + skill + MCP"重新给出建议清单，第三轮正式结构化为本 v2.0 规划。_

_下一步：在 MVP v0.1 UI 打磨收尾（Task 22）完成后，新建 `docs/superpowers/plans/2026-04-24-phase-0-refactor.md` 展开 Phase 0 的任务级实施计划。_
