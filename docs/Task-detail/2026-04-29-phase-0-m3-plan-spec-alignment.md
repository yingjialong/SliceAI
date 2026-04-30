---
task: Phase 0 M3 plan/spec 口径对齐修复
date: 2026-04-29
status: completed
---

# Phase 0 M3 plan/spec 口径对齐修复

## 背景

用户要求对 `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md` 与 `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md` 的口径进行修复。此前 review 发现 plan fresh review 已新增第 13 项手工回归、将 release tag 修为 `v0.2.0`，但 mini-spec 仍停留在 12 项和裸 `v0.2` tag；plan 也存在前几个 task commit 前未完整跑 4 关 CI gate、Task 4/5 允许不可编译中间态的描述风险。

## ToDoList

- [x] 统一 M3.5 手工回归口径为 13 项。
- [x] 统一 release tag 口径为 SemVer `v0.2.0`，保留 v0.2 作为里程碑语义。
- [x] 明确 M3.1 Sub-step C + D 为同一原子实现 / 提交单元。
- [x] 补齐 plan Task 1 / 2 / 3 commit 前的 4 关 CI gate。
- [x] 将 plan 内多行 4 关 CI gate 改成 subshell 形式，避免整段粘贴执行时 `cd SliceAIKit` 状态泄漏。
- [x] 修正手工回归中 app support 备份 / 权限恢复命令，避免固定 `/tmp/SliceAI-backup` 和不可恢复的 `chmod 755`。
- [x] 2026-04-30 优化：同步 mini-spec 与 plan 的 Accessibility 回归语义，消除 plan/spec drift。
- [x] 2026-04-30 优化：清理 ToolEditorView 展示模式步骤中的历史残留指令，避免"不要删旧 DisplayMode extension"与后文"必须删除"互相矛盾。
- [x] 2026-04-30 优化：统一 ToolEditorView displayMode 表格口径为 `editablePresentationModes` 白名单，避免前表写 `PresentationMode.allCases`、后文又禁止 allCases。
- [x] 2026-04-30 优化：统一 D-28 / SelectionReader 口径，删除真实代码不存在的错误枚举与旧文件名残留。
- [x] 2026-04-30 优化：补齐 `InvocationGate` / `InvocationGateTests` 文件总览，并修正 plan 内测试名映射。
- [x] 2026-04-30 优化：清理 plan / spec 的陈旧元信息。
- [x] 2026-04-30 短审收尾：修正 plan 内 “mini-spec 已 R10 approve 锁定” 的过期说明。
- [x] 更新 Task_history 索引。

## 修改文件

- `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`
- `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-04-29-phase-0-m3-plan-spec-alignment.md`

## 修改逻辑

1. 选择保留 plan fresh review 新增的第 13 项，而不是把 plan 降回 12 项。原因是"ToolEditorView 切 Provider 时清空 modelId"对应真实跨 provider 请求失败风险，属于应该进入验收的行为。
2. 将 tag 统一到 `v0.2.0`。`v0.2` 仅保留为 milestone 语义；实际 git tag、build-dmg 版本和 release.yml 产物名必须保持 `0.2.0` 三段一致。
3. 把 AppContainer additive 装配和 AppDelegate async bootstrap 视为一个原子实现单元。这样避免 AppContainer 改完、AppDelegate 尚未改完时出现不可编译状态，却被文档误认为 task 可完成。
4. 将 plan-wide invariant "每个 commit 前四关 CI gate" 落到 Task 1 / 2 / 3 的具体命令块中。
5. 将多行 gate 命令从 `cd SliceAIKit && ...` 改为 `(cd SliceAIKit && ...)`，确保整段复制到同一个 shell 时仍从仓库根目录正确执行。
6. 将手工回归命令改为可恢复：备份目录使用 `mktemp -d`，权限测试先记录原权限并按原值恢复。
7. 将 Accessibility 回归从"AX revoke 后验证 Cmd+C fallback"改为两个真实可达场景：AX revoke 验证失败 UX / onboarding；AX 已授权但目标 app 不暴露 AX 文本时验证 Cmd+C fallback。
8. 将 ToolEditorView 展示模式步骤改成单一最终指令：新增 `PresentationMode.displayLabel` extension 的同时删除旧 `DisplayMode.displayLabel` extension。
9. 将 ToolEditorView displayMode 的 binding 表和增量替换表统一到 `editablePresentationModes` 白名单，不再给 implementer 留 `PresentationMode.allCases` 误用入口。
10. 将 D-28 / SelectionReader 口径统一到真实代码：`SelectionReader.swift` 只迁移 `SelectionReadResult`，不新增额外错误枚举；实现类为 `ClipboardSelectionSource` / `AXSelectionSource`。
11. 补齐 plan 顶部新增文件总览中的 `InvocationGate.swift` / `InvocationGateTests.swift`，并把 mini-spec 映射表里的测试名改为 plan 实际模板中的 `test_overlappingInvocations_dropStale` / `test_staleClearAfterSwitch_doesNotEvictNew`。
12. 更新 plan 的 mini-spec 引用说明和末尾行数说明，避免文档元信息继续停留在旧版本。
13. 将测试名映射段的尾注改为 R11/R12 已同步后的说明，避免继续暗示 mini-spec 只能停留在 R10 锁定状态。

## 验证结果

- 已做文本级口径校验：`12 项`、`13 项`、`v0.2.0`、裸 v0.2 tag 命令模式、`swift build` / `swift test` / `xcodebuild` / `swiftlint` 等关键模式逐项检查。
- 已做针对性残留校验：旧 D-28 文件名 / 不存在的错误枚举 / 过期测试名 / 旧行数说明均已清理。
- 本次只修改 Markdown 文档，没有运行 Swift 编译 / 测试。
