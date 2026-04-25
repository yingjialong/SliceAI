# Task History

SliceAI 项目任务历史记录索引。每条记录对应 `docs/Task-detail/` 目录下的详细文件。

---

## Task 33 · Phase 0 M1 · 核心类型与配置迁移

- **时间**：2026-04-24
- **描述**：落地 v2.0 spec §3.3 / §3.7 / §3.9 定义的领域模型——**以独立 V2* 类型** 新建（V2Tool / V2Provider / V2Configuration / V2ConfigurationStore），不改动现有 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `DefaultConfiguration`；新建 Orchestration / Capabilities 空 target；ConfigMigratorV1ToV2 纯函数 migrator 产出 V2Configuration
- **详情**：[docs/Task-detail/2026-04-24-phase-0-m1-core-types.md](Task-detail/2026-04-24-phase-0-m1-core-types.md)
- **结果**：20 个 sub-task 全部完成（35 commit，26 个新源文件 + 22 个新测试文件 + 2 个 fixture JSON）；`swift build` / `swift test --parallel --enable-code-coverage`（320/320 pass）/ `xcodebuild ... SliceAI`（BUILD SUCCEEDED）/ `swiftlint lint --strict`（0/0 in 106 files）全绿；v1 `Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` / `SelectionPayload` / `ToolExecutor.swift` / `AppContainer.swift` 字节不变（`git diff main..HEAD` 为空）；V2 canonical JSON schema 由 golden 测试锁定（10 个手写 Codable enum + 单键闸门 + `_0` 禁入）；两处 plan 内部冲突就地修订（`DisplayMode → PresentationMode` 避开 Tool.swift 冲突；Task 17/18 顺序互换解决依赖倒置）。分支 `feature/phase-0-m1-core-types`，HEAD `<本次 commit>`；未 push，等待用户审阅后决定 PR

---

## Task 32 · 基于 Codex 第七轮评审（CONDITIONAL_APPROVE）收尾 M1 Plan

- **时间**：2026-04-23
- **描述**：针对 Codex 第七轮 `CONDITIONAL_APPROVE`（79/100）的 1 条 P1 + 2 条 P2 全部接受并落地。(P1) golden JSON 测试从顶部模板引用落实为 **Task 3/8/10/11/13/14 测试代码块里的具体断言**：PermissionTests 加 `test_permission_goldenJSON_fileRead_usesSingleKeyWithStringValue` 等 5 个 + ProvenanceTests 2 个；ContextRequestTests 加 CachePolicy 2 个；OutputBindingTests 加 SideEffect 4 个；ProviderSelectionTests 加 ProviderSelection / ConditionExpr 4 个（含 `"requires":["promptCaching","toolCalling","vision"]` 按 rawValue 字母序断言）；MCPDescriptorTests 加 MCPCapability 2 个；ToolKindTests 加 ToolKind / PipelineStep / TransformOp 6 个——**所有 golden 都断言 `.hasPrefix` single-key discriminator + `XCTAssertFalse(json.contains("_0"))`**。(P2-1) V2Provider 手写 `init(from:)`：即使用户手改 `config-v2.json` 带重复 / 乱序 capabilities，decoder 也做 `Array(Set(raw)).sorted { $0.rawValue < $1.rawValue }` 归一化；`encode(to:)` 仍走自动合成（因 self 已规范化）。(P2-2) 三处残留文案清理：Architecture 顶部的 `ContextValue` 从 golden 锁定清单移除 + 明确标注"不 Codable"；Task 4 文件清单"Modify SelectionPayloadTests.swift"改为"Keep（零改动）"；Task 20 归档列表里的 "ContextValue" 从 golden 清单替换为正确的 10 个 enum
- **详情**：直接修订 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（Architecture 顶部 / Task 3 / Task 4 文件清单 / Task 8 / Task 10 / Task 11 / Task 12 V2Provider / Task 13 / Task 14 / Task 20 归档清单）
- **结果**：plan 第七轮修订完成；Codex `CONDITIONAL_APPROVE` 三条收尾全部落地；下一步可正式进入实施

---

## Task 31 · 基于 Codex 第六轮评审修订 M1 Plan（手写 Codable 实际落地 + internal 访问控制修复）

- **时间**：2026-04-23
- **描述**：针对 Codex 第六轮 `REWORK_REQUIRED`（2 条 P1 + 4 条 P2）全部接受并落地。(P1-1) 手写 Codable 真正落地：plan 顶部新增 **"Canonical JSON Schema：手写 Codable 模板"独立章节**，定义模板 A（single-key discriminator + empty marker）、模板 B（多 associated value 用 nested Repr struct）、模板 C（单值简化）、模板 D（golden JSON 测试）；对 10 个关键 enum（`Permission` / `Provenance` / `CachePolicy` / `SideEffect` / `ProviderSelection` / `ConditionExpr` / `MCPCapability` / `ToolKind` / `PipelineStep` / `TransformOp`）全部补齐 `init(from:) / encode(to:)` + CodingKeys + private Repr struct，产出形如 `{"prompt":{...}}` / `{"clipboard":{}}` / `{"mcp":{"server":"x","tools":[...]}}` 的可读 JSON，保证 golden test 里 `XCTAssertFalse(json.contains("_0"))` 能真实通过；`ContextValue` 明确不 Codable（与 Task 7 一致），从 golden 清单排除。(P1-2) `LegacyConfigV1` 访问控制修复：把 `ConfigMigratorV1ToV2` 和 `migrate(_:)` 从 `public` 改为 `internal`，避免 "public API uses internal type" 编译错误；V2ConfigurationStore 的 private method 调 internal Migrator 合法。(P2-1) Task 4 标题 / 文件清单里残留的 "重命名 + typealias" 措辞彻底清理。(P2-2) Self-Review 里 ContextValue golden 矛盾消除。(P2-3) `V2Provider.capabilities` 从 `Set<ProviderCapability>` 改为 `[ProviderCapability]`，`init` 接受 `some Sequence<ProviderCapability>` 并自动去重 + 按 rawValue 排序，保证 JSON 数组顺序稳定；`ProviderSelection.capability` 手写 Codable 的 encoder 对 `Set<ProviderCapability>` 同样先排序再编码。(P2-4) 在 plan 顶部明确列出 M3 rename pass 的 7 项主任务（删除 V1 全族 / 重命名 V2* / 同步改引用 / 切 config 路径 / 触发首次迁移 / UI kind-aware / 更新测试），要求 spec §4.2 M3 启动前独立 spec 一次
- **详情**：直接修订 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（新增 Canonical JSON Schema 章节 + 10 个 enum 补手写 Codable + LegacyConfigV1/Migrator 改 internal + Task 4 清理 + V2Provider.capabilities 改 Array + Self-Review 更新 + M3 技术债强化段落）
- **结果**：plan 第六轮修订完成；v2 canonical JSON 由手写 Codable 与 golden test 真正锁定（不再是空口声明）；`LegacyConfigV1` 可编译通过；`Set` 相关顺序问题统一修正

---

## Task 30 · 基于 Codex 第五轮评审修订 M1 Plan（V2* 独立类型化 + golden JSON + 文档前置）

- **时间**：2026-04-23
- **描述**：针对 Codex 第五轮 `REWORK_REQUIRED`（3 条 P1 + 4 条 P2）全部接受并落地。(P1-1) 真实 app 可能写坏 v1 config 的核心风险修复：**取消原地改造 Tool / Provider / Configuration / ConfigurationStore 的方案**，改为新建独立 `V2Tool` / `V2Provider` / `V2Configuration` / `DefaultV2Configuration` / `V2ConfigurationStore`；现有 v1 类型全部保持不变；migrator 产出 `V2Configuration` 而非 v1 `Configuration`；V2ConfigurationStore 是独立 actor，不替换现有 FileConfigurationStore；真实 app 启动路径继续读写 v1 `config.json` + schemaVersion=1。(P1-2) Provider.baseURL: URL? 破坏 LLMProviders 编译的问题天然解决：V2Provider 独立，baseURL 可为 URL?；现有 Provider.baseURL 保持 URL 非 optional。(P1-3) v2 canonical JSON schema 锁定：对 ToolKind / PipelineStep / SideEffect / MCPCapability / TransformOp / ProviderSelection / ContextValue 等 associated-value enum 要求增加 golden JSON shape 测试，禁止 Swift 合成 `_0` 泄漏（V2ToolTests 中 `test_v2tool_goldenJSON_promptKind_usesKindDiscriminator` 是典型示例）。(P2-1) SelectionSnapshot 残留文案清理（文件清单 / 依赖图 / 测试注释统一为"新增干净类型，保留 SelectionPayload"）。(P2-2) Package.swift 给 Orchestration / Capabilities 两个新 target 加 `exclude: ["README.md"]`。(P2-3) ContextBag / ContextValue 明确**不实现 Codable**，删除 Codable 分支指令。(P2-4) 新增 Task 0：文档初始化前置（创建 Task-detail 骨架 + Task_history 索引，编号按 grep 取下一个可用值不硬编码）；Task 20 只做"填充完成态字段"
- **详情**：直接修订 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（Architecture / 文件清单 / 依赖图 / Task 0（新）/ Task 1 / Task 7 / Task 12 / Task 15 / Task 17 / Task 18 / Task 19 / Task 20 / Self-Review）
- **结果**：plan 第五轮修订完成；v1 config.json 在真实运行路径上**从架构上不可能**被写入 v2 形状（V2 / v1 类型完全独立，无共享 Codable）；LLMProviders / SettingsUI / AppContainer / DefaultConfiguration 零改动；下一步可进入实施

---

## Task 29 · 基于 Codex 第四轮评审修订 M1 Plan

- **时间**：2026-04-23
- **描述**：针对 Task 28 的 `REWORK_REQUIRED` 三条 P1/P2 全部接受并落地。(P1-1) `SelectionSnapshot` 收缩为干净 v2 类型：删除"重命名 + v1 兼容 init + _legacyXxx stored + v1 Codable key + v1 accessor + typealias SelectionPayload = SelectionSnapshot"整套反模式；`SelectionPayload.swift` 原封保留，`SelectionSnapshot` 只含 `text/source/length/language/contentType` 五字段，两类型独立共存，M3 才做触发层映射。(P1-2) Tool 的 v1 bridge 对**非 .prompt 形态**一律 `assertionFailure` + 生产 no-op：`v1CompatRead` / `v1CompatWrite` 两个 helper 收敛所有 accessor；`providerId` / `modelId` setter 对非 .fixed ProviderSelection 直接拒绝（不再把 .capability / .cascade 强转 .fixed 静默篡改）。(P1-3, Codex P2-1) M1 DoD 口径收紧：不再承诺"真实 app 启动路径已完成迁移"；Task 19 改为"v2 路径 API + migration 能力就绪"，`standardFileURL()` 保持返回 v1；Task 20 Step 5 改为"migrator fixture 单测全绿 + 可选作者 config 干跑"，显式不做"删除/移动作者 config.json / 创建 config-v2.json 在 home"；Self-Review 新增 DoD 口径条目
- **详情**：直接修订 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`（Architecture / 文件清单 / Task 4 / Task 15 / Task 19 / Task 20 / Self-Review）
- **结果**：plan 收敛完成，canonical v2 模型不再被兼容层反向污染，DoD 与真实运行路径一致；下一步可进入实施

---

## Task 28 · Phase 0 M1 实施计划评审

- **时间**：2026-04-23
- **描述**：评审 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`，重点审查它是否与已冻结的 v2 roadmap 一致、是否把 M1 范围控制在“核心类型 + 配置迁移”内，以及兼容层设计是否会污染 v2 数据模型或引入静默语义破坏
- **详情**：[docs/Task-detail/phase-0-m1-plan-review-2026-04-24.md](Task-detail/phase-0-m1-plan-review-2026-04-24.md)
- **结果**：完成评审；结论为 `REWORK_REQUIRED`，需先收敛 `SelectionSnapshot` 兼容方案、`Tool` 的 v1 读写桥策略，以及 M1 对 ConfigurationStore/migrator 的验收口径

---

## Task 27 · 基于 Codex 第三轮评审再次修订 v2.0 Roadmap

- **时间**：2026-04-23
- **描述**：针对 Codex 第三轮 `REWORK_REQUIRED`（2 条 P1，已收敛到 CONDITIONAL_APPROVE 边界）全部接受。(D-24 补全) canonical schema 闭合：`Tool` / `Skill` / `MCPDescriptor` 正式结构加 `provenance: Provenance`；`ContextProvider` protocol 加 `static inferredPermissions(for:)`；`SideEffect` 加 computed `inferredPermissions`；`Provenance` enum 唯一 canonical 定义上移到 §3.3.5，§3.9 的两处重复定义删除；附录 B 伪代码同步。(D-25) firstParty 授权规则收敛：删除 §3.9.1 的"已声明即授权"描述；§3.9.2 下限列改为"所有来源均适用"；三处规则（§3.9.1 / §3.9.2 / §3.9.6）统一为"默认未授权 → 按下限触发确认 → provenance 只调整 UX 文案"，`firstParty` 对 `readonly-network` / `local-write` 不再跳过首次确认
- **详情**：直接修订 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（§0 追加第三轮评审条目、§3.3.1 / §3.3.3 / §3.3.5 / §3.3.6 / §3.3.8 数据模型补字段、§3.9.1 / §3.9.2 / §3.9.4.2 重写、§5.2 追加 D-25、附录 B 同步）
- **结果**：spec 第三轮修订完成；Provenance / inferredPermissions / firstParty 规则三处收敛；下一步应出 M1 plan.md 进入实施

---

## Task 26 · 基于 Codex 第二轮评审再次修订 v2.0 Roadmap

- **时间**：2026-04-23
- **描述**：针对 Codex 第二轮 `REWORK_REQUIRED` 的 3 条安全硬伤 + 1 条一致性清理逐条修订 spec。**三条硬伤全部接受**：(D-22) 重写 §3.9.1 / §3.9.2——能力分级为最低下限、Provenance 只放宽 UX 不突破下限，`exec` / `network-write` 无论来源都要每次确认；(D-23) §3.9.4.2 升级 MCP 威胁建模——stdio server ≡ 用户身份下本地代码执行，Phase 1 只允许 `firstParty` / `selfManaged`（新增 Provenance case），`unknown` 来源直接拒绝导入；(D-24) §3.9.6.5 + §3.4 流程 Step 2 加入权限声明闭环——执行前静态计算 effectivePermissions 必须 ⊆ tool.permissions。一致性清理：§0 状态行、§2.3 哲学表、§3.1 分层图、§3.2 模块表、§3.4 Agent 伪代码、附录 A、附录 C 全部统一为新命名与新 milestone 编号。M2 任务表新增 M2.3a（PermissionGraph），Phase 0 合计人天从 14–20 上调到 15–21
- **详情**：直接修订 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（§0 追加第二轮评审条目、§3.9 重写、§3.4 Step 2/2.5 新增、§5.2 追加 D-22/D-23/D-24、§4.2 M2.3a 新增、附录清理）
- **结果**：spec 第二轮修订完成；Phase 0–1 仍处 Design Freeze，下一步出 M1 plan.md

---

## Task 25 · 基于 Codex 评审修订 v2.0 Roadmap

- **时间**：2026-04-23
- **描述**：针对 Task 24 的 `REWORK_REQUIRED` 结论逐条评估并修订 spec。接受的修改：ExecutionContext → `ExecutionSeed` + `ResolvedExecutionContext` 两阶段（修内部矛盾，D-16）；放弃 Context DAG 改平铺并发（D-17）；新增 §3.9 Security Model（D-21）；Phase 0 拆 M1/M2/M3 三个独立 PR（D-20）；Freeze 范围收敛到 Phase 0–1、Phase 2–5 降为 Directional（D-19）；v2 使用独立 `config-v2.json` 路径不覆盖 v1（D-18）。部分不接受：不做双读双写（用户已 worktree 隔离 + 独立路径足够）；不按"兼容 vs 破坏"二分拆 Phase 0（用户明确"破坏性重构问题不大"）
- **详情**：直接修订 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（原文档同位版本升级，变更点见 §0 "评审与修订"与 §5.2 D-16 ~ D-21）
- **结果**：spec 完成修订；Phase 0–1 进入 Design Freeze，下一步可直接建 M1 的 plan.md 进入实施

---

## Task 24 · SliceAI v2.0 Roadmap 规范评审

- **时间**：2026-04-23
- **描述**：对 `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md` 做架构与产品规划评审，重点审查定位收敛度、架构重构边界、迁移/回滚策略、安全模型、实施顺序和与当前代码基线的一致性
- **详情**：[docs/Task-detail/sliceai-v2-roadmap-review-2026-04-23.md](Task-detail/sliceai-v2-roadmap-review-2026-04-23.md)
- **结果**：完成评审；结论为 `REWORK_REQUIRED`，建议先修正 Phase 0 范围、补齐迁移/回滚与安全模型，再进入实施计划

---

## Task 23 · 产品 v2.0 规划制定（定位重塑 + 底层架构重构方案）

- **时间**：2026-04-23
- **描述**：基于用户纠正后的产品定位（"划词触发型 AI Agent 配置框架"，非 AI Writing 工具），重新制定产品愿景、五大不变量、底层架构（新增 Orchestration + Capabilities 两个 target）、Tool 三态模型（prompt/agent/pipeline）、ExecutionContext / Permission / OutputBinding 抽象，以及 Phase 0–5 的分阶段路线图（底层重构 → MCP → Skill → Prompt IDE + 本地模型 → 生态 → 高级编排）
- **详情**：[docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md](superpowers/specs/2026-04-23-sliceai-v2-roadmap.md)
- **结果**：规划文档冻结；下一步需新建 `docs/superpowers/plans/2026-04-24-phase-0-refactor.md` 展开 Phase 0 任务级计划

---

## Task 22 · MenuBarController 增强 + PanelStyle 清理 + SwiftLint 总验收

- **时间**：2026-04-21
- **描述**：MVP v0.1 UI 美化阶段收官任务，清理历史技术债、补全菜单栏功能并通过 SwiftLint strict 总验收
- **详情**：[docs/Task-detail/ui-polish-2026-04-21.md](Task-detail/ui-polish-2026-04-21.md)
- **结果**：完成，swift build / swift test / xcodebuild / swiftlint --strict 全绿

---

## Task 21 · OnboardingFlow 重构

- **时间**：2026-04-20
- **描述**：重新设计首次启动引导流程，560×520 三步骤 + 步骤指示器 + Hero 图标风格
- **结果**：完成

---

## Task 18–20 · SettingsScene 重构 + 所有子页填充

- **时间**：2026-04-15 – 2026-04-19
- **描述**：Settings 迁移为 NavigationSplitView；依次填充 Hotkey/Trigger/Permissions/About/Providers/Tools 页面；新增 Appearance 外观切换页
- **结果**：完成

---

## Task 12–17 · 面板 UI 全面重构

- **时间**：2026-04-08 – 2026-04-14
- **描述**：FloatingToolbarPanel / ResultPanel / CommandPalettePanel 使用 DesignSystem token 彻底重构；ResultPanel 拖拽把手 / Header 4 按钮 / StreamingMarkdownView 增强
- **结果**：完成

---

## Task 1–11 · DesignSystem target 搭建

- **时间**：2026-03-28 – 2026-04-07
- **描述**：新建 DesignSystem SwiftPM target；依次完成颜色/字体/间距/圆角/阴影/动画 token、交互 modifier（GlassBackground/HoverHighlight/PressScale）、基础组件（IconButton/PillButton/Chip/KbdKey/SectionCard）、动画组件（DragHandle/ProgressStripe/ThinkingDots）、Onboarding 组件（StepIndicator/HeroIcon/ErrorBlock）；ThemeManager + AppearanceMode；AppContainer 注入 ThemeManager；Configuration.appearance 字段扩展
- **结果**：完成
