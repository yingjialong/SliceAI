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
| 最后更新 | 2026-05-27 |
| 当前 Phase | **Phase 3 Prompt IDE + 本地模型（kickoff）** |
| 当前 Milestone | **用户已选择跳过 Phase 2 release；下一步进入 Phase 3 spec 收敛** |
| 下一个动作 | 在 `origin/codex/phase3-tool-editor-playground` 上 review / 修订 Phase 3 ToolEditor v2 + Prompt Playground MVP spec |
| 阻塞 | 无已知产品代码阻塞；`v0.3.0` draft release 已生成并校验通过，但用户已决定暂缓人工发布 |

**Milestone 状态**

> 不在此处给"整体完成百分比"——spec §4.8 明确仅 Phase 0–1 有时间承诺，Phase 2–5 是 directional 无人天估算，谈总进度没基准。

| Phase | Milestone | 状态 |
|---|---|---|
| 0 | M1 | ✅ 已 merge 入 main（merge commit `5cdf0f7`，2026-04-25） |
| 0 | M2 | ✅ 已完成：Orchestration + Capabilities 骨架落地 |
| 0 | M3 | ✅ 已完成并发布：PR #3 merged，`v0.2.0` tag + GitHub Release |
| 1 | M1 | ✅ 已完成：MCP 数据契约、store/importer、stdio client、Settings MCP Servers 页面 |
| 1 | M2 | ✅ 已完成：Task 6 PermissionGraph case-aware coverage、Task 7 Core ContextProviders、Task 8 Permission Consent Grants、Task 9 AppContainer wiring |
| 1 | M3 | ✅ 已完成：tool calling contract、AgentExecutor ReAct loop、ResultPanel tool-call lifecycle、`web-search-summarize` |
| 1 | M4 | ✅ Task 57 release prep 已完成；直接 MCP E2E 已通过，DeepSeek/权限/finalization 缺陷、自定义 Agent Tool 编辑器、MCP allowlist、通用 tool-call policy 和 review 发现的 release blocker 均已修复；最终 gate、本地 DMG 预检、CI draft release 和 artifact SHA 校验通过 |
| 2 | Skill Registry MVP | ✅ 已完成并推送 `main` / `origin/main`（commit `1411e88`）；用户已完成 App 手测且未反馈问题 |
| 2 | Skill E2E Validation | ✅ 已完成：3 个本地 Claude / Codex 风格 skill E2E 与 full gate 均通过 |
| 2 | Public Skill Repository Smoke | ✅ 已完成：3 个公开仓库 / 9 个真实 skill 的扫描、解析、启用和 `SKILL.md` 加载 smoke 通过 |
| 2 | Supporting Files Read-Only Loading | ✅ 已完成：`references/` 与文本型 `assets/` 可按需只读加载；`scripts/` 仍不读取、不执行 |
| 2 | Phase 2 Completion | ✅ 已完成：Output lifecycle、SideEffect executor、多 DisplayMode、本地 TTS、English Tutor、automated gate、公开仓库 smoke 和真实 App smoke 均完成 |
| 3–5 | — | 🟦 Directional，进入前需重新 spec |

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
   - 提交文档 commit（在 main 分支），按用户确认后推送

**"实质性推进"指**：启动新 milestone、merge PR、完成一轮评审修复、写完一份 plan、回答一个 Open Question。**单纯的技术讨论不算**。

---

## 2. 全项目 Phase 全景

（摘自 v2 roadmap spec §4.1，状态按 2026-05-24 当前源码与发布记录更新）

| Phase | 主题 | 状态 | 时长（人天） | 对外可见新功能 | 关键产出 |
|---|---|---|---|---|---|
| **0** | 底层重构 | ✅ 已完成并正式发布 `v0.2.0` | 15–21 (M1+M2+M3) | **无**（只重构） | Orchestration + Capabilities 骨架、Tool 三态、ExecutionSeed/ResolvedContext、Permission + Provenance + PermissionGraph + PathSandbox hook、v2 schema + 独立 config 路径 |
| **1** | MCP + Context 主干 | ✅ 已完成；`v0.3.0` tag + GitHub draft release 已生成，人工发布暂缓 | 20–30 | MCP 支持 / 5 个核心 ContextProvider / Per-Tool Hotkey / 基础自定义 Agent Tool | MCPClient（stdio + Streamable HTTP）+ MCPServersPage + AgentExecutor + Agent Tool 编辑器 + `web-search-summarize` 首个真 Agent Tool |
| **2** | Skill + 多 DisplayMode | ✅ 核心 completion 已完成；Phase 2 release 已按用户决定跳过 | — | Skill 接入 / replace / bubble / structured / TTS / English Tutor | Skill Registry MVP、本地 Skill E2E、公开仓库 smoke、supporting files 只读加载、多 DisplayMode、本地 TTS、English Tutor 和真实 App smoke 已完成；Skill diagnostics、scripts 策略和完整 app 成功率矩阵可作为后续 hardening，不阻塞 Phase 3 |
| **3** | Prompt IDE + 本地模型 | 🟨 Kickoff：需重新 spec | — | Playground / A-B / Ollama & Anthropic 原生 / Memory | 下一步先做 brainstorming/spec；不要直接按 Directional outline 写代码 |
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

### 3.2 M2：Orchestration + Capabilities 骨架 ✅ **已完成**

**目标**：执行引擎、上下文采集器、权限 broker、成本记账、审计日志、路径沙箱、Prompt executor 全部成型，可独立单测；M2 阶段不接入 app 启动链路。

**状态**：已完成并作为 M3 的前置基础。实施记录见：

- plan：[docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md](superpowers/plans/2026-04-25-phase-0-m2-orchestration.md)
- Task-detail：[docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md](Task-detail/2026-04-25-phase-0-m2-orchestration.md)

**关键交付物**：

- [x] `Orchestration` target：`ExecutionEngine` / `ExecutionEvent` / `ContextCollector` / `PermissionGraph` / `PermissionBroker` / `PromptExecutor` / `OutputDispatcher`
- [x] `Capabilities` target：`PathSandbox` / `MCPClientProtocol` / `SkillRegistryProtocol` / production-side mock（M2 当时状态；后续 Phase 1 / 2 已填实 MCP client、ContextProviders 和 LocalSkillRegistry）
- [x] `CostAccounting` sqlite append + `JSONLAuditLog` jsonl append + 脱敏
- [x] M2 保持 app 启动链路 zero-touch；M3 才接入 `ExecutionEngine`

**验证状态**：

- [x] `swift build`
- [x] `swift test --parallel --enable-code-coverage`
- [x] `swiftlint lint --strict`
- [x] `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

---

### 3.3 M3：切换 + 删旧 + 端到端回归 ✅ **已完成并发布**

**目标**：把 AppContainer / 触发通路切到 `ExecutionEngine`；删除旧 `ToolExecutor`；配置改读 `config-v2.json`；端到端回归通过。

**分支 / worktree 状态**：原 `feature/phase-0-m3-switch-to-v2` 已合入并清理；当前事实以 `main` 为准。

**权威文档**：

- mini-spec：[docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md](superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md)
- implementation plan：[docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md](superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md)
- implementation record：[docs/Task-detail/2026-04-28-phase-0-m3-implementation.md](Task-detail/2026-04-28-phase-0-m3-implementation.md)

**Entry criteria**：

- [x] M2 已完成
- [x] 新 worktree / feature branch 已创建
- [x] M3 mini-spec 已完成多轮 review 并与 plan 对齐
- [x] implementation plan 已完成 review / 优化，可执行

**当前任务状态**：

| # | 任务 | 状态 | 备注 |
|---|---|---|---|
| M3.1 | AppContainer / AppDelegate 装配 v2 runtime | ✅ 已完成 | async bootstrap、Xcode deps、InvocationGate、ResultPanel adapter 均已提交 |
| M3.0 Step 1 | caller 切到 `ExecutionEngine` | ✅ 已完成 | App caller、SettingsUI、Windowing、OutputDispatcher fallback 已完成 |
| M3.0 Step 2 | 删除 v1 类型族 + `SelectionReader` + `LLMProviderFactory` 升级 | ✅ 已完成 | v1 `ToolExecutor` 已在此步删除 |
| M3.0 Step 3 | `V2*` 正名回 spec canonical | ✅ 已完成 | `Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` |
| M3.0 Step 4 | `PresentationMode` → `DisplayMode` | ✅ 已完成 | raw values / JSON wire shape 保持不变 |
| M3.0 Step 5 | `SelectionOrigin` → `SelectionSource` | ✅ 已完成 | `SelectionReader` / `AXSelectionSource` / `ClipboardSelectionSource` 保持不变 |
| M3.2 | 触发链端到端验收 | ✅ 已完成 | CLI targeted tests + 用户实机手工回归均通过 |
| M3.3 | 4 个启动场景验证 | ✅ 已完成 | `ConfigurationStoreTests` + 用户实机启动/config 场景回归通过 |
| M3.4 | grep validation 收尾 | ✅ CLI 已完成 | v1 / V2* / `PresentationMode` / `SelectionOrigin` 源码测试范围 0 命中 |
| M3.5 | 13 项手工回归 | ✅ 已完成 | 用户 2026-05-04 反馈剩余项均已测试通过 |
| M3.6 | 文档归档 + `v0.2.0` DMG / release | ✅ 已完成 | Release DMG SHA256：`2d7749a1405e1ec4051b90b8b3ee5e029f5819e18a2cf69eda074f2de5b98aea` |

**Exit criteria（DoD）**：

- [x] `swift build` / `swift test --parallel` / `swiftlint lint --strict` / `xcodebuild` 最后一次全绿
- [x] §4.2.5 回归清单**手工**跑完全过
- [x] 原 4 个内置工具（翻译 / 润色 / 总结 / 解释）在实机行为与 v0.1 等价
- [x] `config-v2.json` 实际生成；旧 `config.json` 未被修改
- [x] 旧分支 app（切回 v0.1 worktree）仍能打开旧 `config.json` 正常工作
- [x] **V2 命名已回归 spec 原名**：没有任何 `V2Tool` / `V2Provider` / `PresentationMode` / `SelectionOrigin` 残留

#### M3.5 手工回归执行结果

> 完整细节以 implementation plan Task 15 为准：`docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`。本节是执行入口，避免每次翻 4800 行 plan。

**执行前准备**：

1. 在当前 worktree 构建 Debug app，并固定产物路径：
   ```bash
   cd /Users/majiajun/workspace/SliceAI/.worktrees/phase-0-m3
   xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug -derivedDataPath build build
   open build/Build/Products/Debug/SliceAI.app
   ```
2. 备份真实 app support 目录，后续涉及删除 / chmod / 手改 config 的测试都从这个备份恢复：
   ```bash
   APP_SUPPORT="$HOME/Library/Application Support/SliceAI"
   BACKUP_ROOT="$(mktemp -d /tmp/sliceai-m3-regression.XXXXXX)"
   echo "BACKUP_ROOT=$BACKUP_ROOT"
   if [ -d "$APP_SUPPORT" ]; then
     cp -a "$APP_SUPPORT" "$BACKUP_ROOT/SliceAI"
   fi
   ```
3. 准备一个可用 Provider：至少一个 OpenAI 兼容 baseURL + API Key；无 key 场景在 Step 5 单独验证，验证后恢复。
4. 打开 Console.app 过滤 `SliceAI`，用于观察 capture source、fallback、Regenerate / single-flight 相关日志。

**13 项回归清单**：

- [x] 1. Safari 划词 → 浮条 → Translate → ResultPanel 正常流式输出。
- [x] 2. `⌥Space` → 命令面板 → 选择工具 → ResultPanel 正常流式输出。（2026-05-04 TextEdit + deepSeek 通过）
- [x] 3. ResultPanel 操作：Regenerate / Copy / Pin / Close / Retry / Open Settings 均与 v0.1 行为等价；Regenerate 时旧 invocation 不应污染新输出。
- [x] 4. Accessibility 降级：关闭 AX 后划词不弹虚假浮条、`⌥Space` 不走 startupError；恢复 AX 后在 AX 文本不可读 app 中验证 Cmd+C fallback 命中。
- [x] 5. 清空 API Key 后触发工具，应出现可理解的配置错误提示；验证后恢复 API Key。
- [x] 6. 修改 Tool / Provider 后立即写入 `config-v2.json` 且执行生效；不得写坏旧 `config.json`。
- [x] 7. 删除 `config-v2.json` 后重启，app 能从旧 `config.json` 重新 migrate；旧 `config.json` 内容不变。
- [x] 8. 切回旧分支 / 旧 build，旧 app 仍能读取原 `config.json` 正常工作。
- [x] 9. 编辑自定义变量并在 prompt 中使用 `{{key}}`，验证 `config-v2.json` 写盘且执行时占位符被替换。
- [x] 10. 全新安装场景：临时移走整个 app support 目录后启动，自动生成 `config-v2.json` / `cost.sqlite` / `audit.jsonl`，且不生成 `config.json`。
- [x] 11. v1 `displayMode = "bubble"` / `"replace"` 经 migrator 后仍 fallback 到 ResultPanel 流式，不报 `.notImplemented`。
- [x] 12. app support 目录不可写时启动，应弹 “SliceAI 启动失败” NSAlert 并退出；验证后恢复目录权限。
- [x] 13. ToolEditorView 切换 Provider 时清空旧 `modelId`；`config-v2.json` 中对应 prompt provider 的 `modelId` 为 `null` 或缺省。

**恢复配置**：

```bash
APP_SUPPORT="$HOME/Library/Application Support/SliceAI"
if [ -n "$BACKUP_ROOT" ] && [ -d "$BACKUP_ROOT/SliceAI" ]; then
  rm -rf "$APP_SUPPORT"
  cp -a "$BACKUP_ROOT/SliceAI" "$APP_SUPPORT"
fi
```

任一项不通过：不要进入 M3.6；记录失败项、现象、Console 日志关键行，回 implementation 修复后重跑相关项。

#### M3.6 文档归档 + `v0.2.0` release（M3.5 全过后执行）

**M3.6 不在 M3.5 之前执行。**它包含：

- [x] 更新 `README.md`：项目状态、模块说明、Phase 0 M3 变更记录。
- [x] 更新 `CLAUDE.md`：架构总览从 v1 `ToolExecutor` 改为 v2 `ExecutionEngine`。
- [x] 创建 / 更新 `docs/Module/SliceCore.md`、`docs/Module/Orchestration.md`、`docs/Module/Capabilities.md`。
- [x] 更新 `docs/Task_history.md`，补 M3 implementation 索引。
- [x] 更新本文件：Phase 0 / M3 / 历史 snapshot 标为 M3.6 本地 release preflight 已完成。
- [x] 最后一次跑 4 关 gate：`swift build`、`swift test --parallel --enable-code-coverage`、`xcodebuild`、`swiftlint lint --strict`。
- [x] `scripts/build-dmg.sh 0.2.0`，计算并记录 `build/SliceAI-0.2.0.dmg.sha256`。
- [x] 验证 DMG 可挂载且包结构包含 `SliceAI.app` 与 `Applications` 链接。
- [x] 从 DMG 临时安装 / 启动新 app，并只结束临时启动的新进程。
- [x] merge PR 后打 `v0.2.0` tag，并创建 GitHub Release / 上传 unsigned DMG。

---

### 3.4 Phase 0 整体 DoD（M1 + M2 + M3 全部合入后）

- [x] `swift build` 成功（全 10 个 target）
- [x] `swift test --parallel --enable-code-coverage` 全绿；覆盖率：SliceCore ≥ 90% / Orchestration ≥ 75% / Capabilities ≥ 60%
- [x] `swiftlint lint --strict` 0 violations
- [x] 原 4 个内置工具在实机上与 v0.1 行为等价
- [x] 老 `config.json` 经 migrator 产出 `config-v2.json`；旧 `config.json` 未被修改；切回旧分支 app 仍正常
- [x] Settings 界面无功能变化（不要误加 UI）
- [x] PR 不引入任何 TODO / FIXME 注释（要做的留成 Issue）
- [x] `docs/Task-detail/phase-0-*.md` 归档 M1/M2/M3 各自的实施过程
- [x] 发布 **v0.2.0** tag（Release Notes 按 `scripts/build-dmg.sh 0.2.0` 打包 unsigned DMG）

**Phase 0 合计人天**：M1: 6–8 + M2: 6–8 + M3: 3–5 = **15–21 人天**；加 20% buffer → 19–26 人天。

---

## 4. Phase 1：MCP + Context 主干

**目标**：把 Phase 0 的 `ContextProvider` / `MCPClient` / `AgentExecutor` 填实；用户可以在 Settings 加 MCP server，并在 Tool 勾选哪些 MCP tool 可用；Per-Tool Hotkey 生效。

**状态**：**M1-M4 主干已完成**。原 `feature/phase-1-mcp-context` worktree 已清理；Task 57 release prep 已完成，`v0.3.0` tag 与 GitHub draft release 已生成并校验通过，但用户已明确暂缓人工发布。自动化 gate、真实 5-server 直接 MCP E2E、本地 DMG 预检和 CI artifact SHA 校验均已通过。App 实测发现的 DeepSeek thinking-mode finalize、Brave 搜索 MCP 授权范围、Agent maxSteps 无最终回答、最终回合 DSML 标记误作为正文输出缺陷已修复；基础自定义 Agent Tool 编辑器、MCP allowlist 文本配置和通用 MCP tool-call policy 已完成代码实现；用户已基本复测 App 场景且未反馈阻塞问题。

**Entry criteria**（Phase 1 实施启动前置条件）：

- [x] Phase 0 全部 milestone merge（v0.2 已发布）
- [x] 用 superpowers:brainstorming skill 走一遍 Phase 1 设计（spec 已 freeze 但细节需要再走一遍）
- [x] 用户 review `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- [x] 产出 `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- [x] plan 经 `claude-review-loop` review 到 APPROVED / COMMENT 边界后进入实施

**Early validation（Phase 1 早期验收，不是启动门槛）**——按 spec §5.3 定位，在首个真实 Agent Tool `web-search-summarize` 开发阶段实测：

- [ ] Q5：用户对"Tool Permission 弹窗确认"的容忍度（实测或 A/B）
- [ ] Q6：`selfManaged` MCP 的"用户审读后接受"UX（一次文本警告是否足够，实机迭代）
- [ ] Q7：`PermissionGrant` 持久化粒度默认（本次会话 / 今日 / 永久，A/B）

**关键交付**（抄自 spec §4.3.2）：

| # | 项目 | 说明 |
|---|---|---|
| 1.1 | `Capabilities/MCPClient`（stdio） | 子进程管理、JSON-RPC framing、懒启动、idle 超时 |
| 1.2 | `Capabilities/MCPClient`（Streamable HTTP） | 远程 MCP server；旧 HTTP+SSE 已弃用且不实现 |
| 1.3 | `SettingsUI/Pages/MCPServersPage` | 增删改、测试连接、查看暴露的 tool 列表 |
| 1.4 | 兼容 Claude Desktop 的 `mcp.json` 格式 | 用户导入一次搞定 |
| 1.5 | `Orchestration/AgentExecutor` | ReAct loop + tool call 审批 UI |
| 1.6 | 5 个核心 ContextProvider 实现 | `selection` `app.windowTitle` `app.url` `clipboard.current` `file.read` |
| 1.7 | `HotkeyManager` 支持多组 hotkey | Per-Tool Hotkey |
| 1.8 | `Windowing/ResultPanel` 增加 tool call 展示 | 折叠/展开 + 参数 + 结果 |
| 1.9 | `PermissionBroker` 真实接入 | Tool install 时批量授权、执行时 gate |
| 1.10 | **首个真实 Agent Tool**：`web-search-summarize` | MCP: brave-search + agent loop + Markdown 总结 |
| 1.11 | **基础 Agent Tool 编辑器** | Tools 设置页可新增 Agent，编辑 prompt / provider / LLM 轮数 / MCP allowlist / 调用策略 |
| 1.12 | **Agent tool-call policy** | `maxSteps` 只表示 LLM 轮数；MCP 调用由独立 policy 控制 |

**Exit criteria（DoD）**：

- [x] 可从 Claude Desktop 直接复制 `mcp.json` 并导入 SliceAI（真实工作仍取决于 server runner confirmation 和本机可用命令）
- [x] 至少 5 个 MCP server 验证通过（filesystem / postgres / brave-search / git / sqlite）——Task 17 已完成直接 MCP JSON-RPC `tools/list` 与低风险 `tools/call`；用户已基本复测 App 场景且未反馈阻塞问题
- [x] Tool Permission 的批准 / 拒绝 / grant 下限有自动化测试；真实 UX 仍建议在 release 环境回归
- [x] `web-search-summarize` Tool 在 Safari / Notes / Slack 等 App 场景完成用户基本复测（未沉淀逐项截图 / 日志证据）
- [x] 用户可从 Settings 创建基础 Agent Tool，并用 `server.tool` 文本配置 MCP allowlist 和调用策略
- [x] AgentExecutor 使用独立 `AgentToolCallPolicy` 控制总调用数、单轮调用数、重复参数和 rate limit 停止
- [x] 新增文档 `docs/Module/MCPClient.md` `docs/Module/ContextProviders.md`
- [x] 发布 **v0.3.0** tag；GitHub draft release 已由 CI 生成并校验通过，人工发布暂缓

**Phase 1 预计人天**：20–30；加 20% buffer → 24–36 人天。

### 4.1 M1：MCP 配置与 stdio

**状态**：Task 1-5 已完成；Task 5 已按 code-quality review 修复两轮，二次复审 `APPROVED`。

**计划文档**：[docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md](superpowers/plans/2026-05-06-phase-1-mcp-context.md)

| Task | 内容 | 状态 | 备注 |
|---|---|---|---|
| M1 Task 1 | SliceCore MCP JSON Contract | ✅ 已完成 | `MCPJSONValue` / MCP content / tool / transport contract；`.sse` 仅解码兼容不可新建 |
| M1 Task 2 | MCP Client Protocol Uses Canonical Descriptor | ✅ 已完成 | Capabilities 使用 SliceCore canonical `MCPDescriptor` / `MCPToolDescriptor` |
| M1 Task 3 | MCP Server Store And Claude Desktop Import | ✅ 已完成 | `mcp.json` store、fail-closed validation、Claude Desktop stdio import |
| M1 Task 4 | Stdio MCP JSON-RPC Client | ✅ 已完成 | stdio JSON-RPC initialize / tools/list / tools/call；remote transport M4 前 fail-fast |
| M1 Task 5 | MCP Servers Settings Page | ✅ 已完成 | Settings 页面、导入 / 新增 / 编辑 / 删除 / 测试连接；已修复原子 update、metadata 保留、sheet 失败保留输入、stale preview |

**M1 Gate 候选验证**：

- [x] `swift test --filter SliceCoreTests.MCPDescriptorTests`
- [x] `swift test --filter CapabilitiesTests.MCPServerStoreTests`
- [x] `swift test --filter CapabilitiesTests.RoutingMCPClientTests`
- [x] `swift test --filter SettingsUITests.MCPServersViewModelTests`（15 tests）
- [x] `swift test`（639 tests）
- [x] Task 5 二次 code-quality 复审 APPROVED

**下一步**：M1 已完成；继续查看 M2-M4 状态。

---

### 4.2 M2：Context 与 Permission

**状态**：Task 6-9 已完成。

| Task | 内容 | 状态 | 备注 |
|---|---|---|---|
| M2 Task 6 | PermissionGraph Case-Aware Coverage | ✅ 已完成 | `EffectivePermissions.undeclared` 改为 declared covers effective；支持文件 exact / 目录前缀 / glob、PathSandbox hard-deny、MCP nil/superset、shellExec exact |
| M2 Task 7 | Five ContextProviders | ✅ 已完成 | 新增 `selection` / `app.windowTitle` / `app.url` / `clipboard.current` / `file.read`；剪贴板和文件 IO 支持取消检查，文件读取先经 `PathSandbox`，并按 chunk 读取且默认 1 MiB 上限 |
| M2 Task 8 | Permission Grant Persistence And UI-Gate Protocol | ✅ 已完成 | 新增 UI-free consent boundary、session grant cache、persistent permission-grants store；默认 MCP / network / shell / AppIntents 不缓存；Task 17 仅对白名单内置 `brave-search.brave_web_search` 开启 session / persistent grant |
| M2 Task 9 | AppContainer Wires Real Context And Permission UI | ✅ 已完成 | `AppContainer` 注册真实 provider registry，接入 AppKit presenter、`permission-grants.json` persistent store、`mcp.json` + stdio/routing MCP client；当时 `.agent` 仍为 stub，后续 M3 已接入真实 AgentExecutor |

**Task 6 验证**：

- [x] `swift test --filter OrchestrationTests.PermissionGraphTests`
- [x] `swift test --filter OrchestrationTests.ExecutionEngineTests`
- [x] `swift test --filter CapabilitiesTests.PathSandboxTests`
- [x] `git diff --check`

**Task 7 验证**：

- [x] `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`
- [x] `cd SliceAIKit && swift test --filter OrchestrationTests.ContextCollectorTests`
- [x] `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionGraphTests`
- [x] `git diff --check`

**Task 8 验证**：

- [x] `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionBrokerTests`
- [x] `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionGrantStoreTests`
- [x] `cd SliceAIKit && swift test --filter CapabilitiesTests.PersistentPermissionGrantStoreTests`（7 tests）
- [x] `cd SliceAIKit && swift test`
- [x] `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

**Task 9 验证**：

- [x] `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionEngineTests`
- [x] `cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`
- [x] `cd SliceAIKit && swift test --filter OrchestrationTests.PermissionBrokerTests`
- [x] `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
- [x] `git diff --check`

**下一步**：M2 已完成；继续查看 M3-M4 状态。

---

### 4.3 M3：AgentExecutor 与工具调用 UI

**状态**：Task 10-13 已完成。

| Task | 内容 | 状态 | 备注 |
|---|---|---|---|
| M3 Task 10 | LLM Tool Calling Contract | ✅ 已完成 | OpenAI-compatible tool schema、流式 tool-call delta、`ChatToolCall.arguments` 解析 |
| M3 Task 11 | AgentExecutor ReAct Loop | ✅ 已完成 | MCP allowlist catalog、permission gate、MCP result 回填、max step / denial / error 处理 |
| M3 Task 12 | ResultPanel Tool Call Lifecycle | ✅ 已完成 | proposed / approved / result / denied / error rows 映射到 ResultPanel |
| M3 Task 13 | Built-In web-search-summarize Agent Tool | ✅ 已完成 | 默认配置新增首方 Agent tool，声明 selection context、tool-calling provider capability 和 Brave MCP 权限 |

**M3 验证摘要**：

- [x] LLMProviders / Orchestration / Windowing focused tests
- [x] AgentExecutor / ExecutionEngine 回归
- [x] App Debug build
- [x] 每个 Task 均完成 `claude-review-loop`

**下一步**：M3 已完成；继续查看 M4 状态。

---

### 4.4 M4：Remote Transport、Per-Tool Hotkeys、E2E、Release Docs

**状态**：Task 14-16 已实施；Task 16 review 已 approve。

| Task | 内容 | 状态 | 备注 |
|---|---|---|---|
| M4 Task 14 | Streamable HTTP Transport | ✅ 已完成 | MCP 2025-06-18 HTTP POST、session id、JSON / SSE response、redirect 阻断、404 session retry |
| M4 Task 15 | Per-Tool Hotkeys | ✅ 已完成 | `HotkeyBindings.tools`、冲突检测、Settings UI、AppDelegate 多热键注册和 tool id 路由 |
| M4 Task 16 | Five MCP Server E2E And Release Documentation | ✅ 已完成 | 自动化 gate 和模块文档完成；真实 5-server/App E2E 缺本机配置，已记录 blocker；Claude Round 2 approve |
| Task 17 | Release E2E Validation | ✅ 主体验证完成 | filesystem / postgres / brave-search / git / sqlite 直接 MCP E2E 已通过；已修复 DeepSeek / Brave permission / maxSteps / DSML finalization 缺陷；用户已基本复测 App 场景 |
| Task 56 | Agent Tool Config And MCP Policy | ✅ 已完成 | 基础 Agent Tool 编辑器、MCP allowlist 文本配置、policy UI、独立 `AgentToolCallPolicy` 已实现；完整 gate 通过 |
| Task 57 | v0.3 Release Prep | ✅ 已完成 | Claude Round 2 approve；修复长 MCP result 回填 LLM 截断、stdio descriptor 变更不重启、CI Release archive Sendable 约束三项发布阻塞；最终 gate、本地 DMG 构建、draft release 生成和 CI artifact SHA 校验通过 |

**Task 16 gate 结果**：

- [x] `cd SliceAIKit && swift build`
- [x] `cd SliceAIKit && swift test --parallel --enable-code-coverage`（735 tests）
- [x] `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
- [x] `swiftlint lint --strict`（170 files，0 violations）
- [x] `bash scripts/phase1-mcp-e2e.sh` 完成只读前置条件检查

**Release 前环境 blocker**：

- [x] SliceAI `~/Library/Application Support/SliceAI/mcp.json`
- [x] Brave Search API key（仅写入本机配置，不记录原值）
- [x] Postgres 只读连接串（仅写入本机配置，不记录原值）
- [x] SQLite 测试 DB 路径
- [x] filesystem 安全测试目录
- [x] Safari / Notes / Slack 等真实 App 场景基本复测（用户反馈无阻塞；未沉淀逐项截图 / 日志证据）

**当前后续**：Phase 0 已以 `v0.2.0` 正式发布。Phase 1 已完成 `v0.3.0` release prep，用户已决定暂缓人工发布 GitHub Release draft；Phase 2 Skill Registry MVP 已在后续任务中完成。

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

### 5.0 从当前到 v1.0 的剩余任务总表

> 这张表按当前 spec / 源码事实把剩余工作拆成 **60 个主任务**。Phase 3–5 仍是 Directional，所以这些条目是 v1.0 路线图级任务，不是已经冻结的实施 plan；真正开工前仍必须重新 spec、review、拆成更细的开发任务。

| # | Phase | 任务 | 交付结果 | 状态 |
|---|---|---|---|---|
| 1 | 2 | 真实本地 Skill E2E 兼容性验证 | 用 3 个本地 Claude / Codex 风格 skill 验证扫描、启停、Agent 绑定和 `sliceai.load_skill` 链路 | 完成：focused E2E、full SwiftPM 796 tests、SwiftLint strict 和 `git diff --check` 均通过 |
| 2 | 2 | 公开 Anthropic / Codex Skill 仓库兼容性验证 | 至少 3 个公开 skill 仓库在 SliceAI 中能扫描、解析、启用并加载核心 `SKILL.md` 指令 | 完成：3 个公开仓库 / 9 个真实 skill 的 opt-in smoke 通过；不含 scripts / supporting files / 真实模型执行 |
| 3 | 2 | Skill 诊断与 `allowed-tools` UX 硬化 | 解析错误、shadowed、禁用、too large、allowed-tools 不授权等状态在 Settings 中可解释 | 待做 |
| 4 | 2 | Skill supporting files 只读加载 | `references/`、文本型 `assets/` 资源支持按需读取，继续遵守 root sandbox | 完成：`sliceai_load_skill_resource` 支持已加载 bound skill 的只读资源读取；`scripts/` 仍不读取、不执行 |
| 5 | 2 | Skill scripts 策略冻结 | 明确 scripts 是否执行、如何授权、如何审计；未冻结前保持不执行 | 待做 |
| 6 | 2 | DisplayMode 设计冻结与 app 成功率矩阵 | 完成 `setSelectedText` 在 Safari / Notes / Xcode / VSCode / Slack / Figma / Discord 的实测表 | 待做 |
| 7 | 2 | `Windowing/BubblePanel` | 小气泡展示、自动消失、定位、降级行为和测试 | 完成：`.bubble` finish 后展示自动消失气泡，已覆盖 Windowing / Orchestration focused tests |
| 8 | 2 | `Windowing/InlineReplaceOverlay` | AX `setSelectedText`、paste fallback、确认 / 撤销浮条 | 部分完成：AX 替换与复制通知 fallback 已完成；确认 / 撤销浮条待做 |
| 9 | 2 | `Windowing/StructuredResultView` | 顶层 JSON object 的结构化字段渲染；后续 English Tutor 会验证真实输出契约 | 完成 |
| 10 | 2 | `OutputDispatcher` 多 sink 落地 | `.silent`、`.file`、`.replace`、`.bubble`、`.structured` 已不再 fallback；TTS side effect 已通过 SideEffectExecutor 执行 | 完成 |
| 11 | 2 | `Capabilities/TTSCapability` | 本地 AVSpeech、权限和 dry-run 防误发声已完成；远端 TTS provider 切换留到后续重新 spec | 完成 |
| 12 | 2 | `english-tutor` 官方 Tool Pack | 语法分析、改写、朗读、结构化结果和 skill 绑定 | 完成：默认 `english-tutor` Agent Tool、内置 skill、schema v4 迁移和 structured TTS `ttsText` 已实现 |
| 13 | 2 | Phase 2 E2E / 文档 / 回归 | Skill、DisplayMode、TTS、English Tutor 的自动化与实机回归 | 完成：automated gate、公开仓库 smoke、真实 App smoke 和最终文档 gate 均通过 |
| 14 | 2 | Phase 2 release | 建议 `v0.4.0` tag / DMG / release notes，版本号需发布前确认 | 跳过：用户 2026-05-27 明确选择不发布，直接进入 Phase 3 |
| 15 | 3 | `ToolEditor v2` 信息架构 | 左侧配置、右侧 Playground、kind-aware 编辑器和保存规则 | 待做 |
| 16 | 3 | Prompt Playground 运行器 | 在 Settings 内运行 selection sample、展示 streaming / tool call / structured output | 待做 |
| 17 | 3 | 测试样本与 expected output 管理 | 保存 selection、上下文、期望输出和回归结果 | 待做 |
| 18 | 3 | A/B 双栏对比 | 同一 Tool 并排跑不同 provider / model / prompt version | 待做 |
| 19 | 3 | Tool version history | 每次保存生成 snapshot，支持查看、回滚和 diff | 待做 |
| 20 | 3 | 原生 `AnthropicProvider` | Messages API、Prompt Caching、Extended Thinking、错误映射 | 待做 |
| 21 | 3 | 原生 `GeminiProvider` | Gemini API、Grounding、JSON Schema output、错误映射 | 待做 |
| 22 | 3 | `OllamaProvider` | 本地模型、可用性检测、function calling 能力验证 | 待做 |
| 23 | 3 | Provider capability / cascade 产品化 | `ProviderSelection.capability` / `.cascade` 从数据模型变成可靠运行时策略 | 待做 |
| 24 | 3 | Tool Memory 存储与检索 | jsonl + FTS index、permission、注入 prompt 和清理策略 | 待做 |
| 25 | 3 | `SettingsUI/Pages/MemoryPage` | 查看、搜索、删除、按 Tool 管理 memory | 待做 |
| 26 | 3 | Cost Panel | 成本聚合、provider 账单偏差校验、sqlite 迁移策略 | 待做 |
| 27 | 3 | `privacy: local-only` 执行闭环 | local-only Tool 禁止远端 provider，无 Ollama 时明确报错 | 待做 |
| 28 | 4 | `.slicepack` 格式冻结 | 包结构、manifest、schema、兼容版本和校验规则 | 待做 |
| 29 | 4 | Tool / Skill Pack import-export | 打包、导入、冲突处理、权限预览和回滚 | 待做 |
| 30 | 4 | Signing / Notarization 决策 | 是否签名、公证、证书策略和 release 影响 | 待做 |
| 31 | 4 | Pack 安装权限审阅 | 安装时集中展示 MCP / file / network / shell / memory 等风险 | 待做 |
| 32 | 4 | `SettingsUI/Pages/MarketplacePage` | 浏览、安装、更新、禁用和来源展示 | 待做 |
| 33 | 4 | `tools.sliceai.app` 静态站 | Marketplace metadata、索引构建、GitHub Pages 发布 | 待做 |
| 34 | 4 | 6 个官方 Starter Packs | 翻译、写作、代码、研究、英语学习、工作流等初始包 | 待做 |
| 35 | 4 | 远端安装与自动更新 | 版本检查、更新提示、签名校验和失败回滚 | 待做 |
| 36 | 4 | SliceAI as MCP server | 通过 stdio 暴露 SliceAI Tool 给 Claude Desktop 等外部宿主 | 待做 |
| 37 | 4 | Shortcuts AppIntents | macOS Shortcuts 中出现 SliceAI Action | 待做 |
| 38 | 4 | macOS Services 菜单 | 右键 Services 调用 SliceAI Tool，并验证 unsigned 限制 | 待做 |
| 39 | 4 | URL Scheme | 外部 URL 调用 Tool / pack install / settings deep link | 待做 |
| 40 | 4 | Phase 4 安全评审与文档 | 对 sideload、签名、远端更新、MCP server 做安全复核 | 待做 |
| 41 | 4 | Phase 4 release | 建议 `v0.6.0` / `v0.7.0` 分段发布，版本号需发布前确认 | 待做 |
| 42 | 5 | `Orchestration/PipelineExecutor` | `.pipeline` ToolKind 真正执行，不再返回 not implemented | 待做 |
| 43 | 5 | Pipeline schema validation / runtime graph | step 引用、分支、失败策略、循环防护和权限聚合 | 待做 |
| 44 | 5 | Pipeline 可视化编辑器 | 节点图编辑、连接校验、预览和版本化 | 待做 |
| 45 | 5 | `ContentClassifier` | 规则 + 可选本地小模型，识别代码、URL、论文、普通文本等 | 待做 |
| 46 | 5 | Smart Actions 动态排序 | 浮条根据内容类型、App、历史使用动态推荐工具 | 待做 |
| 47 | 5 | Provider cascade runtime 完整化 | 长文本、代码、隐私等条件路由与 fallback 可观测 | 待做 |
| 48 | 5 | Agent step callback 接入 Pipeline 进度 | tool-call / stepCompleted / progress 映射到 UI | 待做 |
| 49 | 5 | 内置 Pipeline 工具 | Translate→Anki、Commit→Push、Paper→Notion 等至少 3 个 | 待做 |
| 50 | 5 | Phase 5 E2E / release | Pipeline、Smart Actions、cascade 的自动化和实机回归，建议 `v0.8.0` / `v0.9.0` | 待做 |
| 51 | v1.0 | 全 Phase DoD 审计 | Phase 0–5 DoD 全部逐项复核并关闭遗留项 | 待做 |
| 52 | v1.0 | 文档 / spec / schema 同步 | README、AGENTS、CLAUDE、模块文档、schema、task history 全部与源码一致 | 待做 |
| 53 | v1.0 | 全量回归矩阵 | Apps、providers、MCP servers、skills、DisplayModes、permissions、migration 全覆盖 | 待做 |
| 54 | v1.0 | Accessibility / privacy / security review | AX、剪贴板、文件、MCP、远端更新、日志脱敏最终审计 | 待做 |
| 55 | v1.0 | CI / release hardening | release workflow、artifact 校验、崩溃日志策略和失败回滚 | 待做 |
| 56 | v1.0 | 安装包与签名收尾 | DMG、签名、公证、首次启动体验和权限引导 | 待做 |
| 57 | v1.0 | 官网 / Homepage / Release Notes | 对外说明、安装指引、功能列表、限制说明 | 待做 |
| 58 | v1.0 | 迁移与向后兼容 smoke | v0.1 / v0.2 / v0.3 配置迁移和旧配置读取复核 | 待做 |
| 59 | v1.0 | Bug bash / 性能 / 可用性打磨 | 真实使用场景压力测试、启动速度、内存、长输出、取消行为 | 待做 |
| 60 | v1.0 | `v1.0.0` 发布 | tag、DMG、release、公告和发布后 smoke | 待做 |

### 5.1 Phase 2：Skill + 多 DisplayMode

**目标**：把 Anthropic Skills 规范的 skill 包引入；`replace / bubble / structured / silent` 四种 DisplayMode 真正可用。

**当前进度**：Skill Registry MVP、真实本地 Skill E2E、公开 skill 仓库 smoke、supporting files 只读加载、Output lifecycle、SideEffect executor、`.silent`、`.file`、`.replace`、`.bubble`、`.structured` DisplayMode、本地 TTS capability 与 English Tutor 默认工具已完成。Task 63 automated gate、公开仓库 smoke 和真实 App smoke 均已通过。Skill scripts 执行明确不进入 Phase 2 completion。

**已实现的 MVP 边界**：

- [x] 用户可配置多个本地 skill roots，registry 扫描 root skill、collection root、`skills/`、`.claude/skills/`、`.agents/skills/`、`.codex/skills/`。
- [x] `SKILL.md` frontmatter / description / instructions 的最小解析规则；兼容 Claude / Codex 常见字段，`allowed-tools` 仅展示不授权。
- [x] Settings UI 可查看 skill 列表、来源、状态、解析错误和 enable / disable overrides。
- [x] Agent Tool 可通过加号逐条绑定最多 5 个 enabled skills，每行下拉选择并可删除；Prompt Tool 暂不支持 skill 绑定。
- [x] AgentExecutor 初始只注入绑定 skills 的 metadata，模型通过内置 pseudo-tool `sliceai.load_skill` 按需加载完整 `SKILL.md`。
- [x] 单元测试覆盖解析成功、解析失败、禁用、too large、missing description、missing source、shadowed 和 pseudo-tool 加载场景。
- [x] 完整 gate 已通过：SwiftPM 795 tests、SwiftLint strict、App Debug build 和 `git diff --check`。
- [x] 已合入并推送 `main` / `origin/main`（commit `1411e88`）；用户已完成 App 手测且未反馈问题。
- [x] 暂不实现 marketplace、远端安装、skill 内脚本执行；supporting files 已先落地只读读取，不包含 scripts。

**关键交付**（粗粒度，进入前重新 spec）：

- [x] `Capabilities/SkillRegistry`（扫目录、解析 SKILL.md、生成 snapshot 和按需加载 body）
- [x] `SettingsUI/Pages/SkillsPage`
- [x] 真实 Skill E2E 兼容性验证（3 个本地 Claude / Codex 风格 skill）— focused E2E 与 full gate 均通过
- [x] 公开 Skill 仓库兼容性 smoke（`anthropics/skills`、`openai/skills`、`jMerta/codex-skills` 3 个仓库 / 9 个真实 skill）
- [x] Skill supporting files 只读加载（`references/` 与文本型 `assets/`，通过 `sliceai_load_skill_resource` 渐进式读取）
- [x] Phase 2 completion spec / implementation plan（严格 Roadmap 范围，不包含 scripts 执行和 marketplace）
- [x] `Windowing/BubblePanel`（小气泡、2.5s 自动消失）
- [ ] `Windowing/InlineReplaceOverlay`（AX `setSelectedText` + 确认撤销浮条）
- [x] `Windowing/StructuredResultView`（顶层 JSON object → SwiftUI 字段视图）
- [x] `Capabilities/TTSCapability`（本地 AVSpeech；OpenAI TTS 切换留到后续重新 spec）
- [x] `Orchestration/OutputDispatcher` 填充所有 Phase 2 DisplayMode（`.silent`、`.file`、`.replace`、`.bubble`、`.structured` 已完成）
- [x] Anthropic / OpenAI / Codex Skills 仓库 smoke（扫描、解析、启用和 `SKILL.md` 加载）
- [x] 新内置 Tool Pack：`english-tutor`

**Definition of Done**（抄自 spec §4.4.3，进入前可重写）：

- [ ] 至少 3 个公开 Anthropic Skill 能在 SliceAI 中直接工作
- [ ] `english-tutor` Tool 能触发"语法分析 + 改写 + 朗读"全流程
- [ ] `replace` 模式在 Notes / VSCode 上通过；Figma / Slack 降级为复制 + 通知
- [x] `structured` 模式支持顶层 JSON object 渲染（string / number / bool / array / object / null）

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

---

### 2026-05-02 — Phase 0 M3 代码切换 + CLI 验收完成，进入 M3.5 手工回归

- M2 已完成；M3 已基于 `feature/phase-0-m3-switch-to-v2` 实施。
- M3.1 完成：SliceAI app target 链接 Orchestration / Capabilities；AppContainer async bootstrap；InvocationGate + ResultPanelWindowSinkAdapter 接入。
- M3.0 Step 1–5 完成：caller 切到 `ExecutionEngine`；删除 v1 类型族；`V2*` / `PresentationMode` / `SelectionOrigin` 回归 spec canonical 命名。
- M3.2/M3.3/M3.4 CLI 自动化验收完成：
  - `swift build`
  - `swift test --parallel --enable-code-coverage`（569/569）
  - `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
  - `swiftlint lint --strict`
  - M3.4 grep validation：v1 / V2* / `PresentationMode` / `SelectionOrigin` 源码测试范围 0 命中
- 仍未完成：M3.5 13 项手工回归、M3.6 文档归档 + `v0.2.0` DMG / release。

**关键文件**：

- mini-spec：`docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`
- plan：`docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`
- implementation record：`docs/Task-detail/2026-04-28-phase-0-m3-implementation.md`

**下一步**：执行 §3.3 的 M3.5 13 项手工回归；全部通过后再进入 M3.6。不要提前打 `v0.2.0`。

### 2026-05-04 — Phase 0 M3.5 安全子集实机回归部分通过

- 用户在真实 `SliceAI.app` 中新增并保存 DeepSeek OpenAI-compatible Provider，Provider 连接测试成功。
- 已通过 Settings UI 把 `中译英` Tool 的 Provider 从 `oneApi` 切到 `deepSeek`；`config-v2.json` 写入 `provider-1777873129`，`modelId = null`，旧 `config.json` 未出现 deepSeek 相关字样。
- 已在 TextEdit 中验证：
  - `⌥Space` 命令面板能读取选中文本并执行 `中译英`。
  - 鼠标划词后浮条出现，点击 `中译英` 后 ResultPanel 正常显示。
  - ResultPanel 成功态 Copy / Pin / Unpin / Regenerate / Close 子集可用。
- 三次真实调用均写入 `audit.jsonl` 与 `cost.sqlite`，均为 `tool_id = translate`、`provider_id = provider-1777873129`、`model = deepseek-v4-flash`。
- 仍未完成：Safari 专项、Retry / Open Settings、AX 降级、清空 API Key、删除 / 迁移 / 全新安装 / 不可写 app support、旧 build 兼容、编辑自定义变量、先设置旧 modelId 再切 provider。

**下一步**：继续 M3.5 剩余项；涉及清空 Keychain API Key、删除/移动 app support、chmod、关闭 Accessibility 的步骤必须在执行前获得用户确认。全 13 项通过前不要进入 M3.6。

### 2026-05-04 — Phase 0 M3.6 本地 release preflight 已完成

- 用户反馈 M3.5 剩余项均已测试通过，13 项手工回归按用户实机验收标记为全部通过。
- M3.0–M3.5 当前状态：代码切换、CLI gate、grep validation、真实 GUI / Provider / config / Accessibility / legacy compatibility 回归均已完成。
- M3.6 已完成 README / CLAUDE.md / Module docs / Task-detail / Task_history / master todolist 文档归档，并通过最后 4 关 gate。
- 已执行 `scripts/build-dmg.sh 0.2.0`，生成 `build/SliceAI-0.2.0.dmg` 与 `build/SliceAI-0.2.0.dmg.sha256`；SHA256 为 `2855758e11d02abb7137999577a74bdcb497d41812efe645b1d335ee04d60f84`。
- DMG 挂载结构校验通过：卷内包含 `SliceAI.app` 与 `Applications -> /Applications` 链接。
- DMG 临时安装 / 启动校验通过：复制到 `/tmp/sliceai-dmg-install.*` 后 `open -n` 启动出新 `SliceAI` 进程，随后只结束该临时进程；未覆盖 `/Applications`。
- 当时待执行的远端动作（已在下一节完成）：`git push origin feature/phase-0-m3-switch-to-v2`、PR 创建/merge、`v0.2.0` tag push、GitHub Release publish。

**下一步（历史快照）**：执行远端 push 并创建 PR；PR merge 后再执行 `v0.2.0` tag 与 GitHub Release。该动作已在下一个快照完成。

### 2026-05-04 — Phase 0 / v0.2.0 已正式发布

- PR #3 已 merge：`https://github.com/yingjialong/SliceAI/pull/3`。
- Merge commit：`0e06eeeac3ada99f3fa8aad559f41f0591a6e62a`。
- Tag：`v0.2.0` 已推送并指向 PR #3 merge commit。
- GitHub Release：`https://github.com/yingjialong/SliceAI/releases/tag/v0.2.0`，已正式发布，非 draft。
- Release workflow run `25314316460` 成功，上传 `SliceAI-0.2.0.dmg`。
- Release DMG SHA256：`2d7749a1405e1ec4051b90b8b3ee5e029f5819e18a2cf69eda074f2de5b98aea`。

**下一步**：启动 Phase 1，不要直接写代码。先用 `superpowers:brainstorming` 复核 MCP + Context 主干设计，再起草 Phase 1 plan 并做 plan review。

### 2026-05-05 — Phase 1 前本地收尾完成

- 根工作区 `main` 已 fast-forward 到最新 `origin/main`，包含 PR #3（M3 implementation）与 PR #4（v0.2.0 发布进展文档）。
- 旧根工作区里的 `SliceAIApp/AppContainer.swift` 本地中间态已保存到归档分支 `archive/pre-phase1-local-appcontainer-snapshot`，commit `51f27fd`；该代码不合入 `main`，避免倒退已发布的 v2 runtime。
- M3 worktree 中未跟踪的 review loop / handoff 历史草稿已保存到归档分支 `archive/phase-0-m3-review-loop-artifacts`，commit `03ac677`；正式发布文档主线保持干净。
- 当前进入 Phase 1 前的唯一产品动作是 planning：先 brainstorming，再写 Phase 1 MCP + Context plan，再做 plan review。

**下一步**：启动 Phase 1 planning，首个动作是 `superpowers:brainstorming`。

### 2026-05-06 — Phase 1 MCP + Context design spec 起草

- 按 `superpowers:brainstorming` 完成 Phase 1 设计复核，范围确认采用完整 v0.3 DoD，总 plan 内部拆 M1-M4。
- 推荐并确认执行方案为"主干先行 + 里程碑验收"：M1 MCP 配置与 stdio、M2 Context 与 Permission、M3 AgentExecutor 与工具调用 UI、M4 HTTP transport / Per-Tool Hotkey / 5 server E2E / 发布准备。
- 新增 design spec：`docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`。
- MCP 远程传输口径修正：当前 MCP 官方最新规范以 `Streamable HTTP` 为标准远程传输，旧 `HTTP+SSE` 只作为兼容路径；Phase 1 不再把旧 SSE 当作新设计主线。

**下一步**：用户 review design spec；确认后用 `superpowers:writing-plans` 起草 `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md` 并做 plan review。

### 2026-05-07 — Phase 1 M1 完成

- 已按 `superpowers:subagent-driven-development` + TDD 完成 M1 Task 1-5。
- Task 5 新增 MCP Servers 设置页，支持 stdio server 新增 / 编辑 / 删除、Claude Desktop JSON 导入、`tools/list` 测试连接和工具预览。
- code-quality review 两轮修复均已完成：原子 update、metadata 保留、save/import 失败保留 sheet 输入、stale preview 失效、同一 server 并发测试 loading 计数。
- `claude-review-loop` Round 1 发现新增 server 重复 id 会静默覆盖现有配置；已修复为新增路径拒绝重复 id，导入路径仍保留同 id 覆盖语义。
- 旧 HTTP+SSE 偏差已修正：`.sse` 仅保留解码兼容，不允许 Phase 1 新建或连接；M4 只实现 Streamable HTTP。
- 验证：`swift build`、`swift test --filter SettingsUITests.MCPServersViewModelTests`（15 tests）、`swift test`（639 tests）、`git diff --check` 均通过。
- Task 5 二次 code-quality 复审结论：`APPROVED`。

**下一步**：启动 M2 Task 6：PermissionGraph case-aware coverage。

### 2026-05-07 — Phase 1 M2 Task 6 完成

- Task 6 将 `EffectivePermissions.undeclared` 从 raw Set 差集升级为 case-aware coverage。
- 文件权限 coverage 支持 exact、显式目录前缀、`*` / `**` glob，并在 coverage 前通过 `PathSandbox.isHardDenied(_:)` 拦截硬禁止路径。
- MCP coverage 支持同 server 的 `tools=nil` 全量声明和 declared tools 超集；shellExec 保持命令数组 exact match，空数组不表示全部命令。
- 验证：`swift test --filter OrchestrationTests.PermissionGraphTests`、`swift test --filter OrchestrationTests.ExecutionEngineTests`、`swift test --filter CapabilitiesTests.PathSandboxTests`、`git diff --check` 均通过。

**下一步**：启动 M2 Task 7。

### 2026-05-08 — Phase 1 M2 Task 7 完成

- Task 7 新增五个核心 ContextProvider：`selection`、`app.windowTitle`、`app.url`、`clipboard.current`、`file.read`。
- `clipboard.current` 默认读取系统剪贴板文本并推导 `.clipboard`；`file.read` 根据 `args["path"]` 推导 `.fileRead(path:)`，执行时先通过 `PathSandbox.normalize(_:role: .read)`，再按 chunk 读取且默认 1 MiB 上限。
- 触及 IO 的 provider 均在 IO 边界前后调用 `Task.checkCancellation()`。
- 验证：`cd SliceAIKit && swift test --filter CapabilitiesTests.ContextProviderTests`、`cd SliceAIKit && swift test --filter OrchestrationTests.ContextCollectorTests`、`cd SliceAIKit && swift test --filter OrchestrationTests.PermissionGraphTests`、`git diff --check` 均通过。

**下一步**：启动 M2 Task 8。

### 2026-05-08 — Phase 1 M2 Task 8 完成

- Task 8 新增 UI-free permission consent boundary：`PermissionConsentRequest`、`PermissionConsentDecision`、`PermissionConsentPresenting`。
- `PermissionBroker` 构造函数改为注入 presenter；生产非 dry-run 路径内部解析 approve / deny，不再把 `.requiresUserConsent` 泄漏给 `ExecutionEngine`。
- session grant 只进入 `PermissionGrantStore`；persistent grant 只由 `PersistentPermissionGrantStore` 写入 `~/Library/Application Support/SliceAI/permission-grants.json`，运行时 broker 只读。
- `.mcp`、`.network`、`.shellExec`、`.appIntents` 在 session 与 persistent 存储层均拒绝缓存；MCP 即使 presenter 返回 session approval 也只对本次 invocation 生效。
- `AppContainer` 当前注入 fail-closed runtime presenter，真实 AppKit 弹窗留给 Task 9。
- code-quality review follow-up 已补 persistent grant 读侧 schema/scope/permission/provenanceTag 校验，并拆分 session / persistent store 错误类型，避免跨模块 API 歧义。
- 验证：`cd SliceAIKit && swift test --filter OrchestrationTests.PermissionBrokerTests`、`cd SliceAIKit && swift test --filter OrchestrationTests.PermissionGrantStoreTests`、`cd SliceAIKit && swift test --filter CapabilitiesTests.PersistentPermissionGrantStoreTests`（7 tests）、`cd SliceAIKit && swift test`、`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 均通过。

**下一步**：启动 M2 Task 9：AppContainer Wires Real Context And Permission UI。

### 2026-05-09 — Phase 1 M4 Task 16 release readiness 自动化 gate 完成

- M3 Task 10-13 已完成：OpenAI-compatible tool calling contract、AgentExecutor ReAct loop、ResultPanel tool-call lifecycle、`web-search-summarize` Agent tool。
- M4 Task 14-15 已完成：Streamable HTTP transport、per-tool hotkeys。
- Task 16 清理了 release gate 的历史 SwiftLint blocker，全仓 `swiftlint lint --strict` 当前为 170 files / 0 violations。
- Task 16 自动化 gate 已通过：`swift build`、`swift test --parallel --enable-code-coverage`（735 tests）、App Debug build、strict lint。
- 新增 `docs/Module/MCPClient.md`、`docs/Module/ContextProviders.md` 和 `scripts/phase1-mcp-e2e.sh`。
- 真实 5-server MCP E2E 与 Safari / Notes / Slack App 回归未在当前机器执行成功：缺 SliceAI `mcp.json`、Brave API key、Postgres 只读连接串、SQLite 测试 DB 和 filesystem 测试目录。

**下一步**：补齐真实 release 环境做 5-server / App E2E，再决定是否打 `v0.3`。

### 2026-05-10 — Phase 1 Task 17 release E2E validation 启动

- 新增 Task 17 任务文档：`docs/Task-detail/2026-05-10-phase-1-release-e2e-validation.md`。
- `docs/Task_history.md` 已登记 Task 55，作为当前恢复入口。
- 已运行 `bash scripts/phase1-mcp-e2e.sh` 做只读环境检查；输出未包含 secret 原值。
- 当前已具备命令：`node`、`npm`、`npx`、`uvx`、`git`、`sqlite3`、`jq`。
- 当前缺失：`psql`、SliceAI `~/Library/Application Support/SliceAI/mcp.json`、`BRAVE_API_KEY`、`SLICEAI_E2E_FILESYSTEM_DIR`、`SLICEAI_E2E_POSTGRES_URL`、`SLICEAI_E2E_GIT_REPO`、`SLICEAI_E2E_SQLITE_DB`。
- 真实 5-server MCP E2E 与 Safari / Notes / Slack App 回归仍未通过，原因是环境前置条件未齐备。

**下一步**：补齐真实 MCP 配置和测试数据源；先在 Settings 中逐个 server 跑 `tools/list`，再做一次安全只读 tool call，最后回归 App 场景。

### 2026-05-19 — Phase 1 Task 17 本地四项 MCP E2E 通过

- 已创建本地 filesystem 安全目录和 SQLite 测试 DB，并使用当前 Phase 1 worktree 作为 git 测试仓库。
- 已用 Docker 启动本地 Postgres E2E 容器，创建只读用户和测试数据。
- 已写入 SliceAI `~/Library/Application Support/SliceAI/mcp.json`，包含 `filesystem`、`postgres`、`git`、`sqlite` 四个 stdio server，runner confirmations 覆盖 `npx` 与 `uvx`。
- 直接 MCP JSON-RPC `tools/list` 通过：filesystem 14 个 tools、postgres 1 个 tool、git 12 个 tools、sqlite 6 个 tools。
- 安全只读 `tools/call` 通过：filesystem `read_text_file`、postgres `query`、git `git_status`、sqlite `read_query`。
- 仍未完成：brave-search、Settings UI 测试连接、Safari / Notes / Slack `web-search-summarize` App 回归。

**后续**：Brave Search 已在下一节补齐；继续完成 App 场景回归。

### 2026-05-19 — Phase 1 Task 17 五项 MCP 直接 E2E 通过

- 用户提供 Brave Search API key 后，已将 `brave-search` stdio server 写入本机 SliceAI `mcp.json`；配置记录只保留 env key 名称，不记录 key 原值。
- 直接 MCP JSON-RPC `tools/list` 通过：brave-search 2 个 tools（`brave_web_search`、`brave_local_search`）。
- 低风险 `tools/call` 通过：`brave_web_search` 返回搜索结果，`isError=false`。
- 当前 worktree Debug App 已启动，进程路径指向 `build/e2e/Build/Products/Debug/SliceAI.app`。
- 当前用户配置缺少内置 `web-search-summarize` Agent 工具，且 Provider 未声明 `toolCalling`；已备份并补丁本机 `config-v2.json`，新增 `web-search-summarize`，并仅给 `deepSeek` Provider 标记 `toolCalling` 作为 Agent 首选。
- App 实测发现 DeepSeek V4 thinking mode finalize 失败：Brave MCP 调用完成后，后续 LLM 请求因缺少 `reasoning_content` 续传而返回 `provider.invalidResponse(<redacted>)`。
- 已修复 OpenAI-compatible tool-calling streaming 对 `reasoning_content` 的解码与 Agent follow-up 回传；验证通过 focused tests、LLMProvidersTests、AgentExecutorTests、ChatTypesTests、全量 SwiftPM 739 tests 和 App Debug build。
- 后续 App 实测继续发现 Brave MCP 授权按钮不可用、Agent maxSteps 后无最终回答，以及最终回合 DSML 标记误作为正文输出；已在下一节修复并把最终验证更新为 748 tests。
- 后续更新：用户已基本复测 Safari / Notes / Slack `web-search-summarize`、permission approval / denial、ResultPanel lifecycle、per-tool hotkey 和 command palette hotkey，未反馈阻塞问题；未沉淀逐项截图 / 日志证据。

**下一步**：该项已在后续 Task 57 完成；`v0.3.0` draft release 已生成并在 Task 58 中暂缓人工发布，后续转入 Phase 2 Skill Registry MVP spec。

### 2026-05-19 — Phase 1 Task 17 App 实测缺陷修复

- 已修复 DeepSeek V4 thinking mode：OpenAI-compatible SSE 解码 `reasoning_content`，Agent follow-up assistant tool-call message 回传 `reasoning_content`。
- 已修复 Brave Search MCP 权限弹窗：精确 `brave-search.brave_web_search` 权限允许“本次会话允许”和“以后一直允许”；其它 MCP 权限仍默认逐次确认。
- 已修复 Agent 连续 tool call 后无最终回答：达到 `maxSteps` 后追加最终答案指令，并用不含 `tools/tool_choice` 的请求获取最终答案。
- 已修复最终回合 DSML 工具标记泄漏：如果 provider 仍把 `DSML/tool_calls/invoke` 标记作为文本返回，执行器会转为受控 provider 错误，不再写入 ResultPanel。
- 已补齐 Phase 1 基础自定义 Agent Tool 配置：Tools 设置页支持新增 Agent、编辑 prompt / provider / LLM 轮数 / MCP allowlist / 调用策略；allowlist 使用一行一个 `server.tool` 的文本格式并同步 MCP 权限声明。
- 已把 MCP 调用预算从 `maxSteps` 中拆出：`maxSteps` 只表示 LLM ReAct 轮数，`AgentToolCallPolicy` 控制总调用数、单轮调用数、单工具调用数、重复参数和 rate limit 停止；`web-search-summarize` 显式限制最多 2 次 Brave 搜索。
- 验证通过：focused tests（72 tests）、全量 SwiftPM（756 tests）、SwiftLint strict、`git diff --check`、Xcode Debug build、`build/e2e` Debug build。
- Debug App 已重启，进程 `13394`，进程路径仍为 `build/e2e/Build/Products/Debug/SliceAI.app`。
- 用户已基本复测 App 场景且未反馈阻塞问题；该反馈未附逐项截图 / 日志证据，发布前仍建议以最终 gate / review loop 补齐 release 可信度。

**下一步**：该项已在后续 Task 57 完成；`v0.3.0` draft release 已生成并在 Task 58 中暂缓人工发布，后续转入 Phase 2 Skill Registry MVP spec。

### 2026-05-19 — Phase 1 Task 57 v0.3 Release Prep 完成

- Phase 1 MCP + Context 主干和历史归档文档已合并到 `main`；无继续保留的 feature worktree。
- Claude review loop Round 1 找到 2 个发布阻塞，均接受并修复：
  - 长 MCP tool result 不再以 `<truncated:N>` 形式回填给 LLM；UI / 日志短摘要和模型可见 tool payload 已拆成两条路径。
  - stdio MCP server 在 Settings 修改 command / args / env / url / transport 后会 teardown 并重启旧 session。
- Claude review loop Round 2 approve，`findings: []`。
- 验证通过：focused tests（55 tests）、全量 SwiftPM 758 tests、SwiftLint strict、`git diff --check`、App Debug build、本地 `scripts/build-dmg.sh 0.3.0`、DMG SHA256 和只读挂载结构校验。
- 首次 GitHub Actions Release run `26167656542` 已触发，但在 Xcode 16.4 Release archive 阶段因 Swift 6 严格并发失败；已补齐 `StreamableHTTPMCPClient.retryingExpiredSession<Result: Sendable>` 约束，并通过相关 focused tests、SwiftLint 和本地 `scripts/build-dmg.sh 0.3.0`。
- 第二次 GitHub Actions Release run `26168050987` 已成功生成 `v0.3.0` draft release；artifact `SliceAI-0.3.0.dmg` 文件名正确，release body SHA 和下载后本地 `shasum -a 256` 均为 `cf63e4e50b8eeda63e38f04c85ff485d11cdfa939038d7555b72ae61ad96f0e0`。
- 最新本地 unsigned DMG：`build/SliceAI-0.3.0.dmg`，SHA256 `1520d53e6e0edd097c30f6d6552f28d8b0bc0f80799e0b080f0b36a2bd121e34`。该产物只作为本地预检；CI 会重新构建 draft release artifact，SHA 可能不同。

**下一步**：后续 2026-05-20 用户已决定暂缓人工发布 `v0.3.0` GitHub Release draft，转入 Phase 2 Skill Registry MVP spec。

### 2026-05-20 — 暂缓 v0.3.0 人工发布，启动 Phase 2 Skill Registry MVP spec

- `v0.3.0` draft release 已由 GitHub Actions Release run `26168050987` 生成并校验通过；用户已明确选择暂缓人工发布，继续后续开发。
- 不删除 draft release，不删除或重打 `v0.3.0` tag；后续若要发布，需要用户重新明确要求，并注意 `main` 可能已包含 release tag 之后的文档或开发提交。
- Phase 2 仍是 Directional Outline，不能直接实现。推荐的第一个切片是 Skill Registry MVP spec，而不是 English Tutor、DisplayMode 或完整 Skill runtime。
- 当前已登记 Task 58，并将 README / Task History / 本 TodoList 更新到“Phase 2 启动准备”口径。

**下一步（历史记录）**：该动作已在下一节完成，正式 spec 为 `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`。

### 2026-05-20 — Phase 2 Skill Registry MVP spec 已产出

- 已按 `superpowers:brainstorming` 完成 Skill Registry MVP 范围收敛，并写入 `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`。
- 本轮采用自研最小 loader，不直接引入 `swift-skills` 或 TypeScript 生态实现；原因是现有 Swift 方案要求 Swift 6.2 / macOS 15+，不符合 SliceAI 当前 Swift 6.0 / macOS 14+ 基线。
- 确认用户可配置多个 skill roots；registry 扫描 root skill、collection root、`skills/`、`.claude/skills/`、`.agents/skills/`、`.codex/skills/`，不做无限递归。
- 确认 Skill MVP 只接入 Agent Tool：每个 Agent Tool 最多绑定 5 个 enabled skills；Prompt Tool 不支持 skill 绑定。
- 确认执行时使用 progressive disclosure：初始只给模型绑定 skills 的 `name / description / path` 元数据，模型通过内置 pseudo-tool `sliceai.load_skill` 按需加载完整 `SKILL.md`。
- 明确本 MVP 不实现 supporting files 读取、脚本执行、marketplace、远端安装、DisplayMode、TTS 或 English Tutor；supporting files 渐进式读取作为技术债务记录在 spec。

**下一步**：用户 review Skill Registry MVP spec；确认后用 `superpowers:writing-plans` 产出 implementation plan，plan 通过 review 前不改业务代码。

### 2026-05-21 — Phase 2 Skill Registry MVP implementation plan 已产出

- 用户确认进入 implementation plan 后，已按 `superpowers:writing-plans` 写入 `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`。
- Plan 将实现拆成 8 个任务：preflight/worktree、SliceCore schema、`SKILL.md` parser/scanner、`LocalSkillRegistry`、AgentExecutor pseudo-tool、Skills 设置页、Agent Tool skill binding、AppContainer wiring 与最终 gate。
- Plan 明确采用 TDD，每个任务包含 focused tests、预期失败/通过命令和 commit 点；最终 gate 包含 SwiftPM 全量测试、SwiftLint strict、`git diff --check` 和 Xcode Debug build。
- 当前仍未修改业务代码；下一步需要用户选择执行方式。

**下一步**：已选择 Subagent-Driven 并完成实现，见下一条实现完成记录。

### 2026-05-24 — Phase 2 Skill Registry MVP 完成并推送 main

- 已按 Subagent-Driven 执行实现，覆盖 SliceCore schema、Capabilities parser/scanner/registry、AgentExecutor pseudo-tool、Settings Skills 页面、Agent Tool skill 绑定和 AppContainer wiring。
- `sliceai.load_skill` 的 provider function name 固定为 `sliceai_load_skill`，避免 OpenAI-compatible function name 中使用点号。
- AppContainer 已创建单例 `LocalSkillRegistry`，同一实例注入 Settings、AgentExecutor 和 ExecutionEngine。
- Agent Tool skill 绑定 UI 已按用户反馈改为加号逐条新增、行内下拉选择、减号删除，避免在编辑器里一次性铺开全部 skills。
- Full gate 已通过：SwiftPM 795 tests、SwiftLint strict、App Debug build 和 `git diff --check`。
- 用户已完成 App 手测且未反馈问题。
- 已提交 `1411e88 feat: add skill registry mvp`，并推送到 `origin/main`；本地 `HEAD`、`main`、`origin/main` 均指向 `1411e88`。
- 下一步建议启动真实 Skill E2E 兼容性验证，再根据真实缺口决定 supporting files 只读加载、DisplayMode 或 marketplace 的优先级。

### 2026-05-24 — 项目状态审计与剩余任务总表完成

- 新增项目级 `AGENTS.md`，把当前 Swift/macOS 项目事实、必读顺序、模块边界、已落地功能、未完成能力、常用命令、配置路径和测试门槛写成 agent 入口文档。
- 本文件 §5.0 已补齐从当前到 `v1.0.0` 的 60 项剩余主任务；Phase 3–5 仍是 Directional，真正开工前需要重新 spec / review / plan。
- 修复当前文档漂移：Phase 0 / Phase 1 状态、`CLAUDE.md`、`README.md`、`docs/Module/SliceCore.md`、`docs/Module/Orchestration.md` 均已同步 AgentExecutor、Skill Registry MVP 和 DisplayMode / Pipeline 未完成边界。
- `config.schema.json` 已从旧 schemaVersion 1 / v1 扁平 Tool schema 更新到当前 schemaVersion 3 / v2 ToolKind / SkillSettings schema。
- 验证通过：`jq empty config.schema.json`、`git diff --check`、`swift test --package-path SliceAIKit`（795 tests）和 `swiftlint lint --strict`。
- 下一步仍建议先做真实 Skill E2E 兼容性验证（3 个本地 Claude / Codex 风格 skill）。

### 2026-05-24 — Phase 2 真实本地 Skill E2E 兼容性验证完成

- 新增 `AgentExecutorSkillE2ETests`，用真实临时 skill root 和生产 `LocalSkillRegistry` 覆盖 `skills/`、`.claude/skills/`、`.agents/skills/` 三种本地目录形态。
- 已验证 3 个 Claude / Codex 风格 skill 的 `allowed-tools`、`disable-model-invocation`、`user-invocable` 兼容字段解析，Agent Tool 绑定，初始 metadata 暴露，以及 `sliceai_load_skill` 按需加载真实 `SKILL.md`。
- Supporting files 当前仍只保留目录兼容性：`references/`、`assets/`、`scripts/` 和 `agents/openai.yaml` 不进入模型 payload，也不会被执行。
- full gate 首次暴露既有 prompt stream cancellation 测试调度竞态；已通过专用可取消 dispatcher 测试夹具收紧断言，未修改生产逻辑。
- 验证通过：focused Skill E2E、focused cancellation regression、`swift test --package-path SliceAIKit`（796 tests）、`swiftlint lint --strict` 和 `git diff --check`。
- 下一步建议进入公开 Anthropic / Codex skill 兼容性验证；supporting files 只读加载、DisplayMode、TTS 和 English Tutor 仍是后续 Phase 2 任务。

### 2026-05-24 — Phase 2 公开 Skill 仓库兼容性 smoke 完成

- 新增 `scripts/phase2-public-skill-smoke.sh`：固定 commit sparse checkout 公开仓库样本，写入 manifest，并以 opt-in env 运行 `PublicSkillRepositorySmokeTests`。
- 新增 `PublicSkillRepositorySmokeTests`：默认无 `SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST` 时 skip，保证常规 `swift test` 不联网。
- 已验证 3 个公开仓库 / 9 个真实 skill：`anthropics/skills@690f15c`、`openai/skills@b0401f0`、`jMerta/codex-skills@1be063d`。
- 发现并修复真实兼容缺口：OpenAI 官方仓库使用 `skills/.curated/<skill>/SKILL.md` 布局；`SkillDirectoryScanner` 现在有界支持 `skills/.curated` 与 `skills/.system` 直接子 skill，仍不做任意递归。
- 验证通过：scanner 红绿测试、public smoke、`swift test --package-path SliceAIKit`（798 tests，1 skipped）、`swiftlint lint --strict` 和 `git diff --check`。
- 下一步建议做 supporting files 只读加载设计；scripts 执行、marketplace、DisplayMode、TTS 和 English Tutor 仍未完成。

### 2026-05-26 — Phase 2 supporting files 只读加载完成

- 新增 `SkillResourcePayload` 与 `SkillRegistryProtocol.loadSkillResource(id:relativePath:)`；`LocalSkillRegistry` 会索引 enabled skill 内的 `references/` 和文本型 `assets/`。
- 新增 provider-visible `sliceai_load_skill_resource` pseudo-tool；模型必须先调用 `sliceai_load_skill` 加载同名 bound skill，才能读取 metadata 中列出的 supporting file。
- 安全边界：只接受相对路径，拒绝绝对路径、`..`、未索引资源、symlink 越界、非 UTF-8 和超过 64 KiB 的单文件；`scripts/` 不读取、不执行。
- E2E 已覆盖真实临时 skill root：`references/style.md` 可按需进入模型 tool message，`scripts/check.sh` 仍不会进入 payload。
- 验证通过：focused registry / Agent / Skill E2E、公开仓库 smoke（3 repositories / 9 public skills）、`swift test --package-path SliceAIKit`（803 tests，1 skipped）、`swiftlint lint --strict`、`git diff --check` 和 App Debug build。
- 下一步建议进入 DisplayMode 设计切片或 Skill scripts 策略冻结；TTS、English Tutor、marketplace 仍未实现。

### 2026-05-26 — Phase 2 completion spec / plan 冻结

- 用户确认按“严格 Roadmap”继续 Phase 2 completion，不扩大到 marketplace、scripts 执行、PipelineExecutor、Memory 或原生多 provider。
- 新增 spec：`docs/superpowers/specs/2026-05-26-phase-2-completion.md`。
- 新增 implementation plan：`docs/superpowers/plans/2026-05-26-phase-2-completion.md`。
- 新增 Task 63 任务详情：`docs/Task-detail/2026-05-26-phase-2-completion.md`。
- 范围冻结为 Output lifecycle foundation、side effects 实执行、`.silent/.file/.replace/.bubble/.structured`、本地 TTS、首方 `english-tutor` 和最终 gate。

### 2026-05-26 — Phase 2 Output lifecycle / SideEffect / Silent / File 完成

- 已完成 `OutputDispatcherProtocol` lifecycle API，prompt / agent 执行路径都会 begin / chunk / finish，并把 final text 交给 output sink。
- 已完成 `SideEffectExecutor` 执行边界：`copyToClipboard`、`appendToFile`、`notify`、`callMCP`、`tts` 有实执行入口；`writeMemory` 明确 Phase 3 unsupported。
- `.silent` 不再写 window sink；`.file` 在 finish 阶段使用 `appendToFile` 目标写 final text，且跳过重复的 appendToFile side effect。
- 验证通过 OutputDispatcher / SideEffect / OutputLifecycle / ExecutionEngine / AgentExecutor focused tests、touched Swift lint 和 `git diff --check`。

### 2026-05-26 — Phase 2 Replace DisplayMode 完成

- 新增 `TextReplacementClient` / `TextReplacementResult`，`OutputDispatcher` 对 `.replace` 的 chunk 阶段不写 window，finish 阶段使用完整 final text 替换选区。
- App 层 `AppTextReplacementClient` 先尝试 AX `kAXSelectedTextAttribute` 替换；失败时写剪贴板并发送本地通知，日志不记录用户文本。
- AppDelegate 对 `.replace` / `.file` / `.silent` 不再提前打开空 ResultPanel；失败时才打开面板展示错误。
- 验证通过 Replace / OutputDispatcher / OutputLifecycle / ExecutionEngine focused tests、touched Swift lint 和 App Debug build。

### 2026-05-26 — Phase 2 Bubble / Structured DisplayMode 完成

- 新增 `BubbleOutputSink` / `StructuredOutputSink`，`OutputDispatcher` 对 `.bubble` 与 `.structured` 的 chunk 阶段不写 window，finish 阶段使用完整 final text 调用对应 sink。
- 新增 `BubblePanel`、`BubblePresentationState`、`StructuredResultParser` 和 `StructuredResultView`；structured 顶层必须是 JSON object，支持 string / number / bool / array / object / null。
- ResultPanel 可显示 structured 字段视图；`.bubble` 不再提前打开空 ResultPanel，finish 后展示自动消失气泡。
- Settings Tool Editor 已开放 `.structured` 展示模式；`.file` / `.silent` 因依赖高级 outputBinding，暂不在基础编辑器暴露。
- 验证通过 Windowing / OutputDispatcher / OutputLifecycle focused tests 和 App Debug build。

### 2026-05-26 — Phase 2 本地 TTS side effect 完成

- 新增 `TTSCapability`、`TTSRequest` 和 `AVSpeechTTSCapability`，生产实现使用 macOS AVFoundation `AVSpeechSynthesizer` 朗读 final text。
- `SideEffectExecutor` 已依赖 `Capabilities.TTSCapability`；`.tts` 继续由 `SideEffect.inferredPermissions` 推导 `.systemAudio`，空 final text 返回失败。
- AppContainer 已把真实 `SideEffectExecutor` 注入生产 `ExecutionEngine`，并提供 App 层剪贴板写入、用户通知、MCP client、文件沙箱和本地 TTS。
- 新增 dry-run 回归：TTS side effect 在 dry-run 下只发 `.sideEffectSkippedDryRun`，不会调用真实 executor。
- 验证通过 `swift test --package-path SliceAIKit --filter 'CapabilitiesTests.TTSCapabilityTests|OrchestrationTests.SideEffectExecutorTests'` 和 `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`。

### 2026-05-26 — Phase 2 English Tutor 默认工具完成

- `Configuration.currentSchemaVersion` 提升到 4，`config.schema.json` 已同步。
- 新增 `EnglishTutorToolFactory`，默认配置新增 `english-tutor` Agent Tool：`.structured` 主输出、`.tts` side effect、`.systemAudio` 权限、tool-calling provider capability 和内置 skill 绑定。
- `ConfigurationStore` 在加载 v3 配置时只补入一次 English Tutor；v4 用户删除后不会重新添加。
- `LocalSkillRegistry` 默认暴露首方内置 `english-tutor` skill，避免默认工具依赖用户本地 skill root。
- `SideEffectExecutor` 对 structured JSON 优先朗读 `ttsText` 字段，避免 TTS 朗读整段 JSON。
- 验证通过 `SliceCoreTests.ConfigurationTests`、`SliceCoreTests.ConfigurationStoreTests`、`SliceCoreTests.ConfigMigratorV1ToV2Tests`、`CapabilitiesTests.LocalSkillRegistryTests`、`OrchestrationTests.SideEffectExecutorTests/test_execute_tts_prefersStructuredTTSText` 和 `SettingsUITests` focused tests。

### 2026-05-26 — Phase 2 completion gate 通过

- 已通过 automated gate：`swift test --package-path SliceAIKit`（837 tests，1 skipped，0 failures）、`swiftlint lint --strict`（194 files，0 violations）、`git diff --check` 和 `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`。
- 已重跑公开仓库 smoke：`bash scripts/phase2-public-skill-smoke.sh`，3 repositories / 9 public skills 通过。
- 已完成真实 App smoke：Debug app 启动后确认 `AX trusted=true`、六个临时工具热键注册成功；本地 OpenAI-compatible SSE stub 收到 `.silent`、`.file`、`.replace`、`.bubble`、`.structured + TTS` 和 `.window` 请求；剪贴板、文件写入、TextEdit 替换、BubblePanel、ResultPanel、`sliceai_load_skill` 和 TTS 审计均有证据。
- smoke 结束后已恢复用户 `~/Library/Application Support/SliceAI` 配置、删除临时 Keychain account、恢复剪贴板并重启 SliceAI；恢复后用户配置仍为 `schemaVersion = 3` 且无临时 tool hotkeys。
- final gate 中发现并修复一个测试夹具调度竞态：`ExecutionEngineTests/test_execute_cancellationDuringPermissionGate_skipsAuditAndLLM` 不再用 `Task.yield()` 作为取消同步点，改为 `CancellationAwareMockPermissionBroker` 挂起到 stream termination 取消后返回 denied；生产逻辑未修改。
- 文档收口后的最终验证通过：`swift test --package-path SliceAIKit`（837 tests，1 skipped，0 failures）、`swiftlint lint --strict`（194 files，0 violations）、`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`（BUILD SUCCEEDED）、`bash scripts/phase2-public-skill-smoke.sh`（3 repositories / 9 public skills）、`jq empty config.schema.json` 和 `git diff --check`。
- 下一步：做 Phase 2 release 决策（建议 `v0.4.0` tag / DMG / release notes）或启动 Phase 3 规格设计。

### 2026-05-27 — 跳过 Phase 2 release，转入 Phase 3 kickoff

- 用户明确选择跳过 Phase 2 release，不打 `v0.4.0` tag，不构建 / 发布 DMG，直接继续 Phase 3。
- 新增跨机器 handoff：`docs/handoffs/2026-05-27-phase-3-prompt-ide-local-models.md`。
- 新机器最初误将 Phase 3 spec 推到 `origin/codex/phase2-completion`；2026-05-28 已迁移到 `origin/codex/phase3-tool-editor-playground`，Phase 2 completion 应合并回 `main`。
- 推荐首个 Phase 3 切片从 ToolEditor v2 / Prompt Playground MVP 评估开始，避免一次性同时展开原生 providers、Memory 和 Cost Panel。
