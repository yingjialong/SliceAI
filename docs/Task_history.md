# Task History

SliceAI 项目任务历史记录索引。每条记录对应 `docs/Task-detail/` 目录下的详细文件。

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
