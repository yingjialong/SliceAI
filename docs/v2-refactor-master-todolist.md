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
| 最后更新 | 2026-05-02 |
| 当前 Phase | **Phase 0**（底层重构） |
| 当前 Milestone | **M3 实施中**：M3.0–M3.4 CLI 自动化验收已完成；M3.5 手工回归待执行 |
| 下一个动作 | 执行 **M3.5 13 项手工回归**；全部通过后进入 M3.6 文档归档 + `v0.2.0` DMG / release |
| 阻塞 | M3.5 需要用户在真实 macOS 桌面环境执行 GUI / Accessibility / Provider / config 场景 |

**Milestone 状态**

> 不在此处给"整体完成百分比"——spec §4.8 明确仅 Phase 0–1 有时间承诺，Phase 2–5 是 directional 无人天估算，谈总进度没基准。

| Phase | Milestone | 状态 |
|---|---|---|
| 0 | M1 | ✅ 已 merge 入 main（merge commit `5cdf0f7`，2026-04-25） |
| 0 | M2 | ✅ 已完成：Orchestration + Capabilities 骨架落地 |
| 0 | M3 | ⏳ 实施中：代码切换 + CLI 验收完成；等待 M3.5 手工回归 |
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

### 3.2 M2：Orchestration + Capabilities 骨架 ✅ **已完成**

**目标**：执行引擎、上下文采集器、权限 broker、成本记账、审计日志、路径沙箱、Prompt executor 全部成型，可独立单测；M2 阶段不接入 app 启动链路。

**状态**：已完成并作为 M3 的前置基础。实施记录见：

- plan：[docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md](superpowers/plans/2026-04-25-phase-0-m2-orchestration.md)
- Task-detail：[docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md](Task-detail/2026-04-25-phase-0-m2-orchestration.md)

**关键交付物**：

- [x] `Orchestration` target：`ExecutionEngine` / `ExecutionEvent` / `ContextCollector` / `PermissionGraph` / `PermissionBroker` / `PromptExecutor` / `OutputDispatcher`
- [x] `Capabilities` target：`PathSandbox` / `MCPClientProtocol` / `SkillRegistryProtocol` / production-side mock
- [x] `CostAccounting` sqlite append + `JSONLAuditLog` jsonl append + 脱敏
- [x] M2 保持 app 启动链路 zero-touch；M3 才接入 `ExecutionEngine`

**验证状态**：

- [x] `swift build`
- [x] `swift test --parallel --enable-code-coverage`
- [x] `swiftlint lint --strict`
- [x] `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

---

### 3.3 M3：切换 + 删旧 + 端到端回归 ⏳ **实施中**

**目标**：把 AppContainer / 触发通路切到 `ExecutionEngine`；删除旧 `ToolExecutor`；配置改读 `config-v2.json`；端到端回归通过。

**当前分支 / worktree**：`feature/phase-0-m3-switch-to-v2`，worktree `.worktrees/phase-0-m3`

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
| M3.2 | 触发链端到端验收 | ⏳ 部分完成 | CLI targeted tests 完成；Safari / `⌥Space` / cancel / single-flight stress 待手工 |
| M3.3 | 4 个启动场景验证 | ⏳ 部分完成 | `ConfigurationStoreTests` 完成；真实 app/config 文件场景待手工 |
| M3.4 | grep validation 收尾 | ✅ CLI 已完成 | v1 / V2* / `PresentationMode` / `SelectionOrigin` 源码测试范围 0 命中 |
| M3.5 | 13 项手工回归 | ⏳ 下一步 | 用户在真实 macOS 桌面环境执行 |
| M3.6 | 文档归档 + `v0.2.0` DMG / release | ⏳ 待 M3.5 全过 | 不要在 M3.5 前提前 release |

**Exit criteria（DoD）**：

- [ ] `swift build` / `swift test --parallel` / `swiftlint lint --strict` / `xcodebuild` 全绿
- [ ] §4.2.5 回归清单**手工**跑完全过
- [ ] 原 4 个内置工具（翻译 / 润色 / 总结 / 解释）在实机行为与 v0.1 等价
- [ ] `config-v2.json` 实际生成；旧 `config.json` 未被修改
- [ ] 旧分支 app（切回 v0.1 worktree）仍能打开旧 `config.json` 正常工作
- [ ] **V2 命名已回归 spec 原名**：没有任何 `V2Tool` / `V2Provider` / `PresentationMode` / `SelectionOrigin` 残留

#### M3.5 手工回归执行方式（下一步）

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

- [ ] 1. Safari 划词 → 浮条 → Translate → ResultPanel 正常流式输出。
- [ ] 2. `⌥Space` → 命令面板 → 选择工具 → ResultPanel 正常流式输出。
- [ ] 3. ResultPanel 操作：Regenerate / Copy / Pin / Close / Retry / Open Settings 均与 v0.1 行为等价；Regenerate 时旧 invocation 不应污染新输出。
- [ ] 4. Accessibility 降级：关闭 AX 后划词不弹虚假浮条、`⌥Space` 不走 startupError；恢复 AX 后在 AX 文本不可读 app 中验证 Cmd+C fallback 命中。
- [ ] 5. 清空 API Key 后触发工具，应出现可理解的配置错误提示；验证后恢复 API Key。
- [ ] 6. 修改 Tool / Provider 后立即写入 `config-v2.json` 且执行生效；不得写坏旧 `config.json`。
- [ ] 7. 删除 `config-v2.json` 后重启，app 能从旧 `config.json` 重新 migrate；旧 `config.json` 内容不变。
- [ ] 8. 切回旧分支 / 旧 build，旧 app 仍能读取原 `config.json` 正常工作。
- [ ] 9. 编辑自定义变量并在 prompt 中使用 `{{key}}`，验证 `config-v2.json` 写盘且执行时占位符被替换。
- [ ] 10. 全新安装场景：临时移走整个 app support 目录后启动，自动生成 `config-v2.json` / `cost.sqlite` / `audit.jsonl`，且不生成 `config.json`。
- [ ] 11. v1 `displayMode = "bubble"` / `"replace"` 经 migrator 后仍 fallback 到 ResultPanel 流式，不报 `.notImplemented`。
- [ ] 12. app support 目录不可写时启动，应弹 “SliceAI 启动失败” NSAlert 并退出；验证后恢复目录权限。
- [ ] 13. ToolEditorView 切换 Provider 时清空旧 `modelId`；`config-v2.json` 中对应 prompt provider 的 `modelId` 为 `null` 或缺省。

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

- [ ] 更新 `README.md`：项目状态、模块说明、Phase 0 M3 变更记录。
- [ ] 更新 `CLAUDE.md`：架构总览从 v1 `ToolExecutor` 改为 v2 `ExecutionEngine`。
- [ ] 创建 / 更新 `docs/Module/SliceCore.md`、`docs/Module/Orchestration.md`、`docs/Module/Capabilities.md`。
- [ ] 更新 `docs/Task_history.md`，补 M3 implementation 索引。
- [ ] 更新本文件：Phase 0 / M3 / 历史 snapshot 标为完成。
- [ ] 最后一次跑 4 关 gate：`swift build`、`swift test --parallel --enable-code-coverage`、`xcodebuild`、`swiftlint lint --strict`。
- [ ] `scripts/build-dmg.sh 0.2.0`，计算并记录 `build/SliceAI-0.2.0.dmg.sha256`。
- [ ] 验证 DMG 可安装 / 可启动。
- [ ] merge PR 后打 `v0.2.0` tag，并创建 GitHub Release / 上传 unsigned DMG。

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
- [ ] 发布 **v0.2.0** tag（Release Notes 按 `scripts/build-dmg.sh 0.2.0` 打包 unsigned DMG）

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
