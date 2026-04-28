# SliceAI v2.0 重构 Master TodoList

> **这是跨 Phase 的长期协调文档**，是整个 v2 重构的入口与进度追踪单。打开它你就能知道：
>
> 1. **现在在哪**：状态 Dashboard + 当前 Phase / Milestone
> 2. **接下来做什么**：下一个 milestone 的 entry criteria / 子任务 / DoD
> 3. **怎么做**：对照 §8 工作流程 SOP（brainstorm → spec → plan → implement → review → merge）
> 4. **以前做了什么**：每完成一个 milestone，在 §9 历史 snapshot 追加一条
>
> 单次会话可能只推进一小步。这个文档的存在目的是：**任意时刻会话断掉，下一次打开它就能无缝接续，直到整个重构高质量完成**。

---

## 0. 状态 Dashboard

| 字段 | 值 |
|---|---|
| 最后更新 | 2026-04-25 |
| 当前 Phase | **Phase 0**（底层重构） |
| 当前 Milestone | **M1 已 merge 入 main**（merge commit `5cdf0f7`）；M2 准备启动 |
| 下一个动作 | 启动 **Phase 0 M2**（Orchestration + Capabilities 骨架）的 brainstorming + writing-plans |
| 阻塞 | 无 |

**Milestone 状态**

> 不在此处给"整体完成百分比"——spec §4.8 明确仅 Phase 0–1 有时间承诺，Phase 2–5 是 directional 无人天估算，谈总进度没基准。

| Phase | Milestone | 状态 |
|---|---|---|
| 0 | M1 | ✅ 已 merge 入 main（merge commit `5cdf0f7`，2026-04-25） |
| 0 | M2 | ⏳ 准备启动（Entry criteria 中"PR #1 merge + pull main" 已满足） |
| 0 | M3 | ⏳ 未启动（等 M2 merge） |
| 1 | — | ⏳ 设计已 Freeze，plan 未写 |
| 2–5 | — | 🟦 Directional，进入前需重新 spec |

---

## 1. 使用方式（会话恢复指南）

**每次打开新会话的开场白固定流程：**

1. **读本文件**的 §0 状态 Dashboard + §9 最新 snapshot → 确认上下文
2. **读 [2026-04-23-sliceai-v2-roadmap.md](superpowers/specs/2026-04-23-sliceai-v2-roadmap.md)** 对应 phase 的 §4.X（作为设计冻结文档）
3. **读对应 milestone 的 plan**（`docs/superpowers/plans/YYYY-MM-DD-<name>.md`，如果已存在）
4. **确认当前分支 + worktree 位置**：
   ```bash
   git worktree list            # 有哪些 worktree 在哪个分支
   git branch --show-current    # 当前分支
   git status -sb               # 与远程的差距
   gh pr list                   # 未 merge 的 PR
   ```
5. **按 §8 工作流程 SOP** 走下一步
6. **完成任何实质性推进后**：
   - 更新 §0 Dashboard 的"最后更新 / 当前 Milestone / 下一个动作"字段
   - 在 §9 追加一条历史 snapshot
   - 提交文档 commit（在 main 分支）

**"实质性推进"指**：启动新 milestone、merge PR、完成一轮评审修复、写完一份 plan、回答一个 Open Question。**单纯的技术讨论不算**。

---

## 2. 全项目 Phase 全景

（摘自 v2 roadmap spec §4.1，状态按 2026-04-25 本文件编写时实际为准）

| Phase | 主题 | 状态 | 时长（人天） | 对外可见新功能 | 关键产出 |
|---|---|---|---|---|---|
| **0** | 底层重构 | **Freeze，实施中**（M1 完成等 merge） | 15–21 (M1+M2+M3) | **无**（只重构） | Orchestration + Capabilities 骨架、Tool 三态、ExecutionSeed/ResolvedContext、Permission + Provenance + PermissionGraph + PathSandbox hook、v2 schema + 独立 config 路径 |
| **1** | MCP + Context 主干 | **Freeze，未启动** | 20–30 | MCP 支持 / 5 个核心 ContextProvider / Per-Tool Hotkey | MCPClient（stdio + SSE）+ MCPServersPage + AgentExecutor + `web-search-summarize` 首个真 Agent Tool |
| **2** | Skill + 多 DisplayMode | Directional | — | Skill 接入 / replace / bubble / structured / TTS | 进入前重新 spec |
| **3** | Prompt IDE + 本地模型 | Directional | — | Playground / A-B / Ollama & Anthropic 原生 / Memory | 进入前重新 spec |
| **4** | 生态与分享 | Directional | — | Tool Pack / Marketplace / SliceAI as MCP server / Shortcuts / Services | 进入前重新 spec；Pack 签名体系在 §3.9.4 已埋 hook |
| **5** | 高级编排 | Directional | — | Pipeline / 智能路由 / Smart Actions | 进入前重新 spec |

**冻结等级定义**：
- **Freeze**（Phase 0–1）：设计锁定可直接出 plan 进入实施；scope 不增不减。
- **Directional**（Phase 2–5）：方向性大纲；进入该 phase 前必须用 brainstorming skill 重新走一遍 spec，才能开工。

---

## 3. Phase 0：底层重构

**目标**：把 v2 roadmap spec §3 描述的架构落地为可运行代码；现有功能 100% 保留（用户视觉无感知）；引入新 target 但不填实（让 Phase 1 实施者一眼能看到要做什么）。

**Out-of-Scope（明确不做）**：
- ❌ 任何 MCP 实际调用
- ❌ Skill 实际加载
- ❌ 任何 UI 功能新增（Settings 保持现状）
- ❌ 换 Provider（仍只 OpenAI 兼容）
- ✅ 仅做：数据模型升级 + 配置迁移 + 执行引擎骨架

### 3.1 M1：纯数据模型 + 配置迁移 ✅ **已完成并合入 main**

**分支**：`feature/phase-0-m1-core-types`（已删除；worktree 已清理）
**PR**：[#1](https://github.com/yingjialong/SliceAI/pull/1) MERGED 2026-04-25 06:27 UTC（merge commit `5cdf0f7`，50 commits 普通 merge 保留实施历史）
**plan**：[docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md](superpowers/plans/2026-04-24-phase-0-m1-core-types.md)
**Task-detail**：[docs/Task-detail/2026-04-24-phase-0-m1-core-types.md](Task-detail/2026-04-24-phase-0-m1-core-types.md)

**Entry criteria**：无（从 v0.1.x 直接开始）

**子任务完成情况**（原 spec §4.2.3 M1.1–M1.9）：

- [x] M1.1 — 新增 `Orchestration` + `Capabilities` 空 library target
- [x] M1.2 — `SliceCore/ExecutionSeed.swift` + `ResolvedExecutionContext.swift` + `SelectionSnapshot.swift`
- [x] M1.3 — `SliceCore/Context.swift`：`ContextKey` / `ContextRequest` / `ContextProvider` protocol（含 `inferredPermissions(for:)` — D-24）
- [x] M1.4 — `SliceCore/Permission.swift` + `Provenance.swift`（含 `.selfManaged` — D-23）+ `SideEffect.inferredPermissions`
- [x] M1.5 — `SliceCore/V2Tool.swift` 三态 `ToolKind`（prompt/agent/pipeline）【注：作为 **V2Tool 独立类型**落地，v1 `Tool` 零改动；M3 rename pass 切换】
- [x] M1.6 — `SliceCore/V2Provider.swift` + `capabilities` + `ProviderSelection`
- [x] M1.7 — `SliceCore/OutputBinding.swift` + `SideEffect`
- [x] M1.8 — `SliceCore/Skill.swift` + `MCPDescriptor.swift`（数据结构骨架）
- [x] M1.9 — `V2Configuration` + `ConfigMigratorV1ToV2` + 独立路径 `config-v2.json` + 2 份 v1 fixture + 完整迁移单测

**Exit criteria（DoD）完成情况**：

- [x] `swift test SliceCoreTests` 全绿（341 tests）；SliceCore 覆盖率实测 ≥ 90%
- [x] App 仍启动到 v0.1 行为（AppContainer 未改）
- [x] Migrator 覆盖 `config.json` → `config-v2.json` 全字段迁移（fixture 测试）
- [x] PR 独立可 merge；不影响任何现有模块
- [x] **额外**：经 **8 轮 Codex 评审**全部 APPROVED（见 plan 顶部"评审修正索引"R1–R8）
- [x] **额外**：`swiftlint lint --strict` 0 violations / 106 files
- [x] **额外**：v1 zero-touch 严格验证（`git diff origin/main..HEAD -- <v1 files>` = 0 行）

**关键交付物**：

| 类型 | 路径 / 值 |
|---|---|
| V2* 独立类型 | `SliceAIKit/Sources/SliceCore/V2Tool.swift` / `V2Provider.swift` / `V2Configuration.swift` / `V2ConfigurationStore.swift` / `DefaultV2Configuration.swift` |
| 领域新类型 | `ContextKey` / `Permission` / `Provenance` / `SelectionSnapshot` / `AppSnapshot` / `ExecutionSeed` / `ResolvedExecutionContext` / `ContextBag` / `ContextRequest` / `OutputBinding` / `PresentationMode` / `SideEffect` / `ProviderSelection` / `ProviderCapability` / `Skill` / `MCPDescriptor` / `ToolKind`（prompt/agent/pipeline）/ `ToolBudget` / `ToolMatcher` 等 |
| Migrator | `SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift` + `LegacyConfigV1.swift`（内部 Decodable） |
| 空 target | `SliceAIKit/Sources/Orchestration/` + `SliceAIKit/Sources/Capabilities/` |
| 测试 | 新增 20+ 测试文件，总量 341 tests |
| Fixture | `Tests/SliceCoreTests/Fixtures/config-v1-minimal.json`, `config-v1-full.json` |

**实施期命名偏离**（M3 rename pass 处理）：

| 设计名（spec） | M1 实际落地名 | 原因 |
|---|---|---|
| `DisplayMode` | `PresentationMode` | v1 `Tool.swift:85` 已有同名 enum（3-case），M1 不得动 v1 |
| `SelectionSource` | `SelectionOrigin` | v1 `SelectionCapture/SelectionSource.swift` 已有同名 protocol |

**M1 收尾**（全部完成 2026-04-25）：

- [x] PR #1 CI 通过（GitHub Actions `.github/workflows/ci.yml`，Build & Test 1m30s pass）
- [x] PR #1 merge：`gh pr merge 1 --merge --delete-branch`，merge commit `5cdf0f7`，2026-04-25 06:27 UTC
- [x] 清理：`git worktree remove .worktrees/phase-0-m1` + `git branch -d feature/phase-0-m1-core-types` + `git push origin --delete feature/phase-0-m1-core-types` + `git pull origin main`
- [x] merge 后 main 上 verification 重测：`swift test --parallel` 341/341 ✅、`swiftlint --strict` 0 violations / 106 files ✅

---

### 3.2 M2：Orchestration + Capabilities 骨架 ⏳ **未启动**

**目标**：执行引擎、上下文采集器、权限 broker、成本记账、审计日志、路径沙箱、Prompt executor 全部成型、**可独立单测**但**尚未在 app 启动链路中接入**。

**Entry criteria（必须全部满足才能启动）**：

- [x] PR #1 已 merge 到 `origin/main`（2026-04-25，merge commit `5cdf0f7`）
- [x] 本地 `main` 已 pull 最新（`origin/main` HEAD = `5cdf0f7`）
- [ ] 新建 worktree：`git worktree add .worktrees/phase-0-m2 -b feature/phase-0-m2-orchestration`（参考 superpowers:using-git-worktrees skill）
- [ ] 确认 M2 **子任务在 spec §4.2.3 M2.1–M2.9 冻结不变（含 M2.3a PermissionGraph，共 10 项）**（如需调整，先在 plan 里记"评审修正"）
- [ ] 用 superpowers:brainstorming skill 预走一遍 M2（可选——spec 已 freeze，如果没有新问题可直接跳到 writing-plans）

**任务拆解**（抄自 spec §4.2.3 M2）：

| # | 任务 | 人天 | 交付物 |
|---|---|---|---|
| M2.1 | `Orchestration/ExecutionEngine.swift` 骨架 + `ExecutionEvent` | 1.5 | actor + 事件流 + dry-run 分支 + 单测（Mock Provider） |
| M2.2 | `Orchestration/ContextCollector.swift`（**平铺并发，非 DAG**——D-17） | 1.5 | `resolve(seed:requests:) -> ResolvedExecutionContext` + timeout + failures 记录 + 单测 |
| M2.3 | `Orchestration/PermissionBroker.swift`（接口 + 默认全放行实现，但 §3.9.2 下限约束在此层硬编码） | 1 | `gate(effective:provenance:scope:isDryRun:)` + grant store + 单测覆盖 §3.9.2 表（firstParty **不能**放行 exec / network-write — D-22） |
| M2.3a | `Orchestration/PermissionGraph.swift`（D-24 新增）：`compute(tool:) -> EffectivePermissions` + `ExecutionEngine` Step 2 静态校验 ⊆ | 1 | 单测覆盖：未声明的 context permission → `.failed(.permission(.undeclared))`；多种 tool.kind 均命中 |
| M2.4 | `Orchestration/CostAccounting.swift` | 1 | sqlite schema + 写入 API + 单测 |
| M2.5 | `Orchestration/AuditLog.swift` | 1 | jsonl append + 脱敏（§3.9.5）+ 单测（含 `logCleared` 事件） |
| M2.6 | `Orchestration/OutputDispatcher.swift`（**仅 window 分支**；其余 mode 返回 `.notImplemented`） | 0.5 | 路由 + 单测 |
| M2.7 | `Orchestration/PromptExecutor.swift`（从旧 `ToolExecutor` **复制**逻辑到新文件，**不替换**旧文件） | 1 | 新 executor + 单测；旧 `ToolExecutor` 保留 |
| M2.8 | `Capabilities/SecurityKit/PathSandbox.swift`（路径规范化 + 白名单） | 0.5 | 工具 + 单测覆盖所有硬禁止路径 |
| M2.9 | `Capabilities` 预留 `MCPClientProtocol` `SkillRegistryProtocol` | 0.5 | 接口 + Mock 实现 |

**Exit criteria（DoD）**：

- [ ] `swift test OrchestrationTests CapabilitiesTests` 全绿；Orchestration 覆盖率 ≥ 75%
- [ ] ExecutionEngine 单测覆盖 `.prompt` kind 的 **4 条路径**：happy / context-fail / permission-deny / dry-run
- [ ] 旧 `ToolExecutor` **保留不动**；app 行为仍为 v0.1；AppContainer 未改动
- [ ] `swiftlint lint --strict` 0 violations
- [ ] v1 + M1 的 V2* 类型都 zero-touch（除了**新建** Orchestration/Capabilities 文件）
- [ ] PR 独立可 merge（独立 review，不与 M1 / M3 绑定）
- [ ] `docs/Task-detail/2026-XX-XX-phase-0-m2-orchestration.md` 归档实施过程

**M2 产出路径**（预计）：

- `docs/superpowers/plans/2026-XX-XX-phase-0-m2-orchestration.md`
- `docs/Task-detail/2026-XX-XX-phase-0-m2-orchestration.md`
- feature branch `feature/phase-0-m2-orchestration` → PR #2

**M2 工作流程**：见 §8 工作流程 SOP。

---

### 3.3 M3：切换 + 删旧 + 端到端回归 ⏳ **未启动**

**目标**：把 AppContainer / 触发通路切到 `ExecutionEngine`；删除旧 `ToolExecutor`；配置改读 `config-v2.json`；端到端回归通过。

**Entry criteria**：

- [ ] M2 PR 已 merge
- [ ] 本地 main 已 pull
- [ ] 新 worktree `feature/phase-0-m3-switch-to-v2`
- [ ] 回答的 open question：M1 里的 V2* 独立类型 rename 策略最终确认（M1 plan 顶部评审修正索引 A 已列；M3 进入前需 sanity check）
- [ ] **先写并评审 M3 mini-spec**：M1 plan 明确要求 "spec §4.2 M3 的任务清单需要在 M3 启动前独立 spec 一次"（见 M1 plan:24）。因为 M3 要做的是 **rename + 切换真实启动路径 + 删旧**，风险比 M1/M2 高一个数量级，不能只靠 spec §4.2.3 的 6 项清单启动；先写 `docs/superpowers/specs/YYYY-MM-DD-phase-0-m3-mini-spec.md` 过一轮 Codex review 再走 writing-plans

**任务拆解**（抄自 spec §4.2.3 M3，**rename pass 升为一等主任务，与 M3.1–M3.6 同级；见下方 M3.0 + 原表**）：

**M3.0（一等主任务）— v1→v2 rename pass**（M1 plan 明文要求：plan:15-24 "**必须把以下任务列为一等主任务**，而非附带清理"；预计 3–5 人天，是 M3 最大工作量）：

- [ ] 删除旧 `Tool.swift` / `Provider.swift` / `Configuration.swift` / `DefaultConfiguration.swift` / `SelectionPayload.swift` / `ConfigurationStore.swift`
- [ ] 把 `V2Tool.swift` → `Tool.swift`（同理 V2Provider / V2Configuration / V2ConfigurationStore / DefaultV2Configuration），类型 + 文件名双重 rename
- [ ] 把 `PresentationMode` → `DisplayMode`；把 `SelectionOrigin` → `SelectionSource`（两处改名恢复 spec 原始意图；**必须**先删除 v1 `DisplayMode` enum 和 v1 `SelectionSource` protocol）
- [ ] 同步改 `ToolExecutor`（删） / `AppContainer` / `ToolEditorView` / `SettingsViewModel` / `OpenAICompatibleProvider` / `SelectionCapture` / `Windowing` 全部引用
- [ ] 把 config 文件路径从 `config.json` 切到 `config-v2.json`（AppContainer 换用 `V2ConfigurationStore`）
- [ ] 首次启动时对既有用户的 `~/Library/Application Support/SliceAI/config.json` 做 migration
- [ ] 升级 `ToolEditorView` UI（v1 扁平字段 → v2 按 `ToolKind` 分派到 prompt/agent/pipeline 编辑器）
- [ ] 更新所有涉及 `Tool` / `Provider` / `Configuration` 的测试引用

**M3.1–M3.6（抄自 spec §4.2.3，与 M3.0 并行）**：

| # | 任务 | 人天 | 交付物 |
|---|---|---|---|
| M3.1 | `SliceAIApp/AppContainer.swift` 装配 `ExecutionEngine` + 各依赖 | 1 | 装配链路 + 启动冒烟 |
| M3.2 | 触发通路（FloatingToolbar / CommandPalette）从 `ToolExecutor.execute` 切到 `ExecutionEngine.execute(tool:seed:)` | 1 | 对齐 `ExecutionSeed` 构造方式 |
| M3.3 | `ConfigurationStore` 启动时按 §3.7 规则选择 v1/v2 路径，运行 migrator | 0.5 | 启动逻辑 + 单测 |
| M3.4 | 删除 `SliceCore/ToolExecutor.swift` | 0.5 | PR |
| M3.5 | 端到端手动回归（见 §4.2.5 清单） | 1.5 | checklist 全过 |
| M3.6 | 更新 `README.md` 项目修改变动记录、Module 文档、Task-detail | 1 | 文档 |

**Exit criteria（DoD）**：

- [ ] `swift build` / `swift test --parallel` / `swiftlint lint --strict` / `xcodebuild` 全绿
- [ ] §4.2.5 回归清单**手工**跑完全过
- [ ] 原 4 个内置工具（翻译 / 润色 / 总结 / 解释）在实机行为与 v0.1 等价
- [ ] `config-v2.json` 实际生成；旧 `config.json` 未被修改
- [ ] 旧分支 app（切回 v0.1 worktree）仍能打开旧 `config.json` 正常工作
- [ ] **V2 命名已回归 spec 原名**：没有任何 `V2Tool` / `V2Provider` / `PresentationMode` / `SelectionOrigin` 残留

**M3 手工回归清单**（抄自 spec §4.2.5）：

- [ ] Safari 划词翻译 → 弹浮条 → 点 "Translate" → ResultPanel 流式
- [ ] ⌥Space → 面板 → 搜索 → 选工具 → 同上
- [ ] Regenerate / Copy / Pin / Close / Retry / Open Settings
- [ ] Accessibility 权限 revoke 后的降级提示
- [ ] 无 API Key 时的错误提示
- [ ] 修改 Tool / Provider 后配置立即生效并**写入 `config-v2.json`**（不写 `config.json`）
- [ ] 将 `config-v2.json` 删除后重启：app 能从 `config.json` 重新 migrate
- [ ] 同一机器切回旧分支 / 旧 build：旧 app 读取原 `config.json` 仍正常

---

### 3.4 Phase 0 整体 DoD（M1 + M2 + M3 全部合入后）

- [ ] `swift build` 成功（全 10 个 target）
- [ ] `swift test --parallel --enable-code-coverage` 全绿；覆盖率：SliceCore ≥ 90% / Orchestration ≥ 75% / Capabilities ≥ 60%
- [ ] `swiftlint lint --strict` 0 violations
- [ ] 原 4 个内置工具在实机上与 v0.1 行为等价
- [ ] 老 `config.json` 经 migrator 产出 `config-v2.json`；旧 `config.json` 未被修改；切回旧分支 app 仍正常
- [ ] Settings 界面无功能变化（不要误加 UI）
- [ ] PR 不引入任何 TODO / FIXME 注释（要做的留成 Issue）
- [ ] `docs/Task-detail/phase-0-*.md` 归档 M1/M2/M3 各自的实施过程
- [ ] 发布 **v0.2** tag（Release Notes 按 `scripts/build-dmg.sh` 打包 unsigned DMG）

**Phase 0 合计人天**：M1: 6–8 + M2: 6–8 + M3: 3–5 = **15–21 人天**；加 20% buffer → 19–26 人天。

---

## 4. Phase 1：MCP + Context 主干

**目标**：把 Phase 0 的 `ContextProvider` / `MCPClient` / `AgentExecutor` 填实；用户可以在 Settings 加 MCP server，并在 Tool 勾选哪些 MCP tool 可用；Per-Tool Hotkey 生效。

**状态**：**设计已 Freeze**，**plan 未写**。

**Entry criteria**（启动 plan 起草的前置条件）：

- [ ] Phase 0 全部 milestone merge（v0.2 已发布）
- [ ] 用 superpowers:brainstorming skill 走一遍 Phase 1 设计（spec 已 freeze 但细节需要再走一遍）
- [ ] 产出 `docs/superpowers/plans/YYYY-MM-DD-phase-1-mcp-context.md`
- [ ] plan 过一轮 Codex review，直到 APPROVED / COMMENT

**Early validation（Phase 1 早期验收，不是启动门槛）**——按 spec §5.3 定位，在首个真实 Agent Tool `web-search-summarize` 开发阶段实测：

- [ ] Q5：用户对"Tool Permission 弹窗确认"的容忍度（实测或 A/B）
- [ ] Q6：`selfManaged` MCP 的"用户审读后接受"UX（一次文本警告是否足够，实机迭代）
- [ ] Q7：`PermissionGrant` 持久化粒度默认（本次会话 / 今日 / 永久，A/B）

**关键交付**（抄自 spec §4.3.2）：

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

**Exit criteria（DoD）**：

- [ ] 可从 Claude Desktop 直接复制 `mcp.json` 并工作
- [ ] 至少 5 个 MCP server 验证通过（filesystem / postgres / brave-search / git / sqlite）
- [ ] Tool Permission 的一键同意 / 撤销 UX 有测试
- [ ] `web-search-summarize` Tool 在 Safari / Notes / Slack 三个场景 E2E 通过
- [ ] 新增文档 `docs/Module/MCPClient.md` `docs/Module/ContextProviders.md`
- [ ] 发布 **v0.3** tag

**Phase 1 预计人天**：20–30；加 20% buffer → 24–36 人天。

---

## 5. Phase 2–5：Directional（进入前需重新 spec）

> 以下 4 个 phase 处于 Directional Outline 状态：只保留"做什么"的意图和粗粒度交付项，**具体抽象 / API / 数据模型 / 拆分 在进入该 phase 前独立用 brainstorming skill 重新走一遍再冻结**。
>
> 进入某个 phase 前必走流程：
> 1. 用 superpowers:brainstorming 预走一遍设计
> 2. 产出新的 `docs/superpowers/specs/YYYY-MM-DD-phase-N-<topic>.md`（设计冻结）
> 3. 走 Codex 评审（至少一轮，直到 APPROVED）
> 4. 产出 `docs/superpowers/plans/YYYY-MM-DD-phase-N-<topic>.md`（实施 plan）
> 5. plan 完成后再过一轮 Codex 评审，直到 APPROVED / COMMENT（与 §8 阶段 2 对齐）
> 6. 本文件的 §0 Dashboard 更新 + 在对应 phase 章节展开子任务

### 5.1 Phase 2：Skill + 多 DisplayMode

**目标**：把 Anthropic Skills 规范的 skill 包引入；`replace / bubble / structured / silent` 四种 DisplayMode 真正可用。

**关键交付**（粗粒度，进入前重新 spec）：

- [ ] `Capabilities/SkillRegistry`（扫目录、解析 SKILL.md、加载资源）
- [ ] `SettingsUI/Pages/SkillsPage`
- [ ] `Windowing/BubblePanel`（小气泡、2.5s 自动消失）
- [ ] `Windowing/InlineReplaceOverlay`（AX `setSelectedText` + 确认撤销浮条）
- [ ] `Windowing/StructuredResultView`（JSONSchema → SwiftUI 表单）
- [ ] `Capabilities/TTSCapability`（AVSpeech + OpenAI TTS 切换）
- [ ] `Orchestration/OutputDispatcher` 填充所有 DisplayMode
- [ ] Anthropic Skills 兼容性测试（`obra/superpowers` 等公开仓库）
- [ ] 新内置 Tool Pack：`english-tutor`

**Definition of Done**（抄自 spec §4.4.3，进入前可重写）：

- [ ] 至少 3 个公开 Anthropic Skill 能在 SliceAI 中直接工作
- [ ] `english-tutor` Tool 能触发"语法分析 + 改写 + 朗读"全流程
- [ ] `replace` 模式在 Notes / VSCode 上通过；Figma / Slack 降级为复制 + 通知
- [ ] `structured` 模式支持动态表单渲染（至少 5 种字段类型）

**Open questions 必答**（spec §5.3 Q1 / Q2）：

- [ ] Anthropic Skills 规范稳定度
- [ ] macOS 各应用 `setSelectedText` 成功率矩阵

### 5.2 Phase 3：Prompt IDE + 本地模型

**目标**：Tool 编辑器升级为 Prompt Playground；原生支持 Anthropic / Gemini / Ollama 三家；Per-Tool Memory 可用。

**关键交付**（粗粒度）：

- [ ] `SettingsUI/ToolEditor v2`（左配置 + 右 Playground）
- [ ] 测试用例管理（保存样本 selection + expected output）
- [ ] A/B 双栏对比
- [ ] Version history（Tool 每次保存 snapshot）
- [ ] `LLMProviders/AnthropicProvider`（Prompt Caching + Extended Thinking）
- [ ] `LLMProviders/GeminiProvider`（Grounding + JSON Schema）
- [ ] `LLMProviders/OllamaProvider`（本地直连）
- [ ] `Capabilities/Memory`（jsonl + FTS index）
- [ ] `SettingsUI/Pages/MemoryPage`
- [ ] Cost Panel
- [ ] Tool 声明 `privacy: local-only`

**Definition of Done**（抄自 spec §4.5.3，进入前可重写）：

- [ ] 同一 Tool 可以通过 Playground 并排跑 Claude Sonnet 4.6 / GPT-5 / Llama3.3 三家
- [ ] Per-Tool Memory 能注入 prompt 并通过 E2E 测试
- [ ] `privacy: local-only` 的 Tool 在无 Ollama 运行时正确报错
- [ ] Cost Panel 数据与真实 Provider 账单偏差 < 5%

**Open question 必答**（spec §5.3 Q3）：Ollama function-calling 主流模型稳定度

### 5.3 Phase 4：生态与分享

**目标**：Tool 可打包 / 分享 / 安装；SliceAI 本身成为 MCP server；开放 Shortcuts / Services / URL Scheme 三条外部入口。

**关键交付**（粗粒度）：

- [ ] `.slicepack` 格式定义 + 打包脚本
- [ ] `SettingsUI/Pages/MarketplacePage`
- [ ] `tools.sliceai.app` 静态站（GitHub Pages）
- [ ] Tool Pack 元数据规范
- [ ] SliceAI 启动 MCP server（stdio）
- [ ] AppIntents（Shortcuts Action）
- [ ] Services 菜单注册
- [ ] URL Scheme
- [ ] 6 个官方 Starter Packs
- [ ] **Signing + Notarization**（决定是否迈出这步 — 见 spec §5.1）

**Definition of Done**（抄自 spec §4.6.3，进入前可重写）：

- [ ] 从 Marketplace 一键安装 5 个 Starter Pack 全部成功
- [ ] Claude Desktop 中添加 SliceAI 为 MCP server，能调用到 SliceAI 的 Tool
- [ ] macOS Shortcuts 中出现 SliceAI Action
- [ ] Safari 右键 → Services → SliceAI Tool 可用

**Open question 必答**（spec §5.3 Q4）：macOS Services 菜单在 unsigned app 上是否受限

### 5.4 Phase 5：高级编排

**目标**：`.pipeline` Tool Kind 真正可用；按选区内容类型动态推荐工具（Smart Actions）；`cascade` 智能路由落地。

**关键交付**（粗粒度）：

- [ ] `Orchestration/PipelineExecutor`
- [ ] Pipeline 可视化编辑器（节点图）
- [ ] `ContentClassifier`（规则 + 可选本地小模型）
- [ ] 浮条动态工具排序
- [ ] `cascade` 规则 + provider fallback
- [ ] Agent `stepCompleted` 回调接入 Pipeline 进度条

**Definition of Done**（抄自 spec §4.7.3，进入前可重写）：

- [ ] 至少 3 个内置 Pipeline 工具（Translate→Anki、Commit→Push、Paper→Notion）
- [ ] 选中代码时浮条首位自动变成"Explain Code"，选中 URL 时自动变成"Summarize Webpage"
- [ ] Cascade 规则在"长文本 > 8k token 走 Claude Haiku"场景下工作正确

### 5.5 v1.0 Gate

- [ ] Phase 0–5 全部 DoD 达成
- [ ] 决策是否 Signing + Notarization（Phase 4 遗留决策）
- [ ] 实机打包 + Marketplace 5 个 Starter Pack 全部安装成功
- [ ] Release Notes / 官网 / Homepage
- [ ] tag `v1.0.0`

---

## 6. 跨 Phase Open Questions（按 phase 需答的时点）

| # | 问题 | 需答时点 | 答法 |
|---|---|---|---|
| Q1 | Anthropic Skills 规范稳定度 | Phase 2 启动前 | 实机跑 3+ 公开 skill 仓库，记录 manifest 变动频率 |
| Q2 | `setSelectedText` 在 Safari / Notes / Xcode / VSCode / Slack / Figma / Discord 的成功率矩阵 | Phase 2 启动前（Phase 0 期间可并行做） | 实机测试表 |
| Q3 | Ollama function-calling 在 Llama 3.3 / Qwen 3 / DeepSeek V3 的稳定度 | Phase 3 启动前 | 实机跑 Agent tool 3 个场景 |
| Q4 | macOS Services 菜单在 unsigned app 上是否受限 | Phase 4 启动前 | 实机验证 + 查官方文档 |
| Q5 | 用户对"Tool Permission 弹窗确认"的容忍度 | Phase 1 早期（`web-search-summarize` 验收） | A/B 测试 或 实机使用观察 |
| Q6 | `selfManaged` MCP 的"用户审读后接受"UX（一次文本警告够不够） | Phase 1 早期 | 实机迭代 |
| Q7 | `PermissionGrant` 持久化粒度默认（本次会话 / 今日 / 永久） | Phase 1 早期 | A/B 在 `web-search-summarize` 上 |

---

## 7. 关键决策索引（D-1 ~ D-25）

**完整决策记录见 [v2-roadmap spec §5.2](superpowers/specs/2026-04-23-sliceai-v2-roadmap.md#52-关键决策记录v20)**。以下仅作索引：

| # | 决策主题 | 对应 Phase |
|---|---|---|
| D-1 | Tool 三态 prompt/agent/pipeline | Phase 0 M1 |
| D-2 | MCP/Skill 提前到 Phase 1–2 | 全局 |
| D-3 | ExecutionContext 不可变 | Phase 0 M1 |
| D-4 | Provider 加 `capabilities` | Phase 0 M1 |
| D-5 | Orchestration 独立 target | Phase 0 M1 |
| D-6 | SliceAI 作为 MCP server | Phase 4 |
| D-7 | `.slicepack` 文件夹格式 | Phase 4 |
| D-8 | 兼容 Claude Desktop `mcp.json` | Phase 1 |
| D-9 | schemaVersion 硬升级到 2 | Phase 0 M1 |
| D-10 | Agent loop tool call 默认需用户确认 | Phase 1 |
| D-11 | AuditLog 写 jsonl + Cost 写 sqlite | Phase 0 M2 |
| D-12 | 不自研 Prompt DSL，用 Mustache + helpers | Phase 3 |
| D-13 | 保留 OpenAI 兼容作为 Provider kind | Phase 3 |
| D-14 | MCP server 独立进程（stdio） | Phase 1 |
| D-15 | `outputBinding.sideEffects` 作为数据字段 | Phase 0 M1 |
| D-16 | 两阶段执行上下文（Seed + Resolved） | Phase 0 M1 |
| D-17 | Phase 0–1 放弃 Context DAG | Phase 0 M2 |
| D-18 | v2 期间独立 `config-v2.json` 路径 | Phase 0 M1/M3 |
| D-19 | Freeze 范围收敛到 Phase 0–1 | 全局 |
| D-20 | Phase 0 拆 M1/M2/M3 三独立 PR | Phase 0 |
| D-21 | §3.9 独立 Security Model | Phase 0 |
| D-22 | Provenance 不能突破能力下限 | Phase 0 M2 / Phase 1 |
| D-23 | stdio MCP server ≡ 本地代码执行 | Phase 1 |
| D-24 | 权限声明闭环（effectivePermissions ⊆ tool.permissions） | Phase 0 M1/M2 |
| D-25 | Provenance 只调 UX 文案不减确认次数 | Phase 0 M2 / Phase 1 |

**注**：M1 实施期还新增两条实施期命名偏离（non-decision，只是技术债），见 §3.1 "实施期命名偏离"表。

---

## 8. 工作流程 SOP（每个 milestone 统一执行）

```
 ┌──────────────────────────────────────────────────────────────┐
 │ 阶段 0：启动                                                   │
 │ - 读本文件 §0 Dashboard + §9 最新 snapshot                     │
 │ - 确认 milestone entry criteria 全部满足                       │
 │ - 创建 worktree：                                              │
 │   git worktree add .worktrees/<name> -b feature/<name>         │
 │   （遵循 superpowers:using-git-worktrees skill）               │
 └──────────────────────────────────┬───────────────────────────┘
                                    │
 ┌──────────────────────────────────▼───────────────────────────┐
 │ 阶段 1：设计（仅当 phase 是 Directional 或 spec 需更新时）      │
 │ - 用 superpowers:brainstorming skill 走一遍设计                │
 │ - 产出 docs/superpowers/specs/YYYY-MM-DD-<topic>.md            │
 │ - 跑至少一轮 Codex 评审（subagent-type=general-purpose + model=opus）│
 │ - 根据评审迭代直到 APPROVED                                     │
 └──────────────────────────────────┬───────────────────────────┘
                                    │
 ┌──────────────────────────────────▼───────────────────────────┐
 │ 阶段 2：出 plan                                                 │
 │ - 用 superpowers:writing-plans skill                            │
 │ - 产出 docs/superpowers/plans/YYYY-MM-DD-<topic>.md             │
 │ - 每个 task 必须包含：files / TDD 步骤 / 测试代码 / commit 指令 │
 │ - 跑一轮 Codex 评审                                             │
 └──────────────────────────────────┬───────────────────────────┘
                                    │
 ┌──────────────────────────────────▼───────────────────────────┐
 │ 阶段 3：实施（subagent-driven-development）                     │
 │ - 按 superpowers:subagent-driven-development skill              │
 │ - 每个 task：implementer subagent（opus）→ spec-reviewer →      │
 │   code-quality-reviewer → 必要时修复再 review                   │
 │ - 每个 task 独立 commit；commit message 遵循仓库风格            │
 │ - 每个 task 完成后跑 swift build + swift test + swiftlint lint --strict│
 └──────────────────────────────────┬───────────────────────────┘
                                    │
 ┌──────────────────────────────────▼───────────────────────────┐
 │ 阶段 4：milestone 整体评审（Codex 第 N 轮）                     │
 │ - 所有 task 完成后跑一次 Codex 全局 review                      │
 │ - 根据发现的 P0/P1/P2 迭代修复（每轮一个 fix commit 组）        │
 │ - 直到 Codex 返回 COMMENT 级无阻断项                            │
 └──────────────────────────────────┬───────────────────────────┘
                                    │
 ┌──────────────────────────────────▼───────────────────────────┐
 │ 阶段 5：归档 + PR + merge                                       │
 │ - 填 docs/Task-detail/YYYY-MM-DD-<topic>.md（实施总结）         │
 │ - 更新 docs/Task_history.md 索引                                │
 │ - git push -u origin feature/<name>                             │
 │ - gh pr create --base main --head feature/<name>               │
 │ - 等 CI 全绿（或本地先跑全量 CI gate）                          │
 │ - 由用户决定何时 merge                                           │
 │ - merge 后清理：git worktree remove + 分支删除（可选）          │
 └──────────────────────────────────┬───────────────────────────┘
                                    │
 ┌──────────────────────────────────▼───────────────────────────┐
 │ 阶段 6：更新本文件                                               │
 │ - §0 Dashboard 的"最后更新 / 当前 Milestone / 下一个动作"        │
 │ - §3.X / §4 / §5 对应 milestone 打勾                             │
 │ - §9 追加一条历史 snapshot                                       │
 │ - commit 本文件到 main（不 push，由用户决定）                    │
 └──────────────────────────────────────────────────────────────┘
```

**关键原则**（从 M1 实施总结出的血泪教训）：

1. **质量优先，不为效率牺牲**：每个 task 都走完整两阶段评审。快不等于好。
2. **v1 zero-touch 严格验证**（**仅适用 M1 / M2**）：`git diff origin/main..HEAD -- <v1 files>` 必须为 0 行。**M3 阶段此原则不适用**——M3.0 rename pass 会大面积删除 / 重命名 v1 类型；M3 的等价验收是 §3.3 的回归清单 + 迁移单测 + 切回旧分支仍能打开旧 config.json 的兼容性测试。
3. **SliceError 脱敏规则**：所有带 String payload 的 case → `developerContext` 输出 `<redacted>`。
4. **手写 Codable 模板**：enum with associated values 必须用 `allKeys.count == 1` 单键 guard + `DecodingError.dataCorrupted(.init(codingPath:, debugDescription:))`。
5. **decoder 与 validator 双守**：decoder 挡外部 JSON 输入、`.validate()` 挡代码构造；不变量在两处都要 enforce，写入边界（store.save）统一调 validate。
6. **commit 粒度**：每个 task 独立 commit（feat/fix + module + 一句 why + Co-Authored-By）；review fix 独立 commit（便于 bisect）。
7. **swiftlint strict 必须从 worktree / 主仓库根目录跑**（子目录跑会 fallback 到默认规则错报）。
8. **文档 commit 要在正确的 worktree**（不要在主仓库改 worktree 的文档再迁移；先 cd 对路径再 Edit）。
9. **实施期改名 / scope 调整**必须在 plan 顶部"评审修正索引"段显式记录（同步 spec 对应章节加 Round 记录）。
10. **plan 的代码块是实施当日快照**，后续 fix 不回填 plan 代码块；以 worktree 源码为最终真相。

---

## 9. 历史 snapshot（每次重大 milestone 完成时追加一条）

### 2026-04-25 — 初始化本文件 + Phase 0 M1 完成并开 PR

- 完成 Phase 0 M1 纯数据模型 + 配置迁移全部 9 个子任务（M1.1–M1.9）
- 45 个 M1 commit + 5 个 base commit = PR #1 共 50 commits
- 经 8 轮 Codex 评审全部 APPROVED（R1–R3 设计阶段 / R4 plan / R5 merge 前代码 / R6 code-quality minor notes / R7 代码块快照规约 / R8 写入边界 + migrator 不变量）
- CI 三项全绿：swift build / 341 tests / swiftlint strict 0 violations
- v1 zero-touch 严格验证通过
- PR #1 OPEN，等 merge
- 本文件建立作为 v2 重构的 master 入口

**关键文件**：

- spec：`docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`
- plan：`docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（顶部评审修正索引记录 R1–R8 全部决策）
- PR：https://github.com/yingjialong/SliceAI/pull/1

**下一步**：等 PR #1 merge → 启动 Phase 0 M2 的 brainstorming + writing-plans。

---

### 2026-04-25（晚） — Phase 0 M1 已 merge 入 main + main 重测全绿

- 在 push 本地 main（领先 `origin/main` 7 个 commit）的过程中把 v2 spec / M1 plan / master todolist / Codex review 文档一并推到远程，让 PR #1 评审上下文公开可见
- PR #1 通过 `gh pr merge 1 --merge --delete-branch` 合入 main（merge commit `5cdf0f7`，2026-04-25 06:27 UTC，普通 merge 保留 50 commits 实施历史以便 bisect）
- gh 在 merge 后试图删除本地分支但因 worktree 占用失败；随后手动 `git worktree remove .worktrees/phase-0-m1` + `git branch -d feature/phase-0-m1-core-types` + `git push origin --delete feature/phase-0-m1-core-types` 清理
- main pull 完成后立即跑 verification 验证 merge 未引入回归：
  - `swift test --parallel --enable-code-coverage`：**341/341 全过**（含 V2Tool/V2Provider/V2Configuration/Migrator/Permission/ToolKind 等 M1 全部 V2* 类型测试）
  - `swiftlint lint --strict`：**0 violations / 0 serious / 106 files**
- M1 实际产出：73 个文件 / +5790 行 / -31 行（M1 plan 顶部 R1–R8 评审修正索引完整保留 commit 链）

**下一步**：启动 **Phase 0 M2**（Orchestration + Capabilities 骨架）—— 按 §8 工作流程 SOP：
1. 阶段 0：`git worktree add .worktrees/phase-0-m2 -b feature/phase-0-m2-orchestration`
2. 阶段 1：（可选）用 `superpowers:brainstorming` 过一遍 M2 设计（spec §4.2.3 M2 已 freeze，无新问题可跳过）
3. 阶段 2：用 `superpowers:writing-plans` 产出 `docs/superpowers/plans/2026-04-XX-phase-0-m2-orchestration.md`，过一轮 Codex 评审到 APPROVED
4. 阶段 3：subagent-driven-development 实施 M2.1–M2.9 + M2.3a 共 10 个子任务
