# Phase 0 M3 Mini-Spec 归档

## 任务背景

Phase 0 M3 负责把前两轮已落地的 v2 数据模型、Orchestration 与 Capabilities 接入真实 App，完成从 v1 执行链到 v2 `ExecutionEngine` 的切换，并删除 v1 冲突类型族。

mini-spec 文件：

- `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`

implementation plan 文件：

- `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`

Codex review loop 的历史草稿未纳入本次归档提交；本文件只保留最终对齐后的 mini-spec 结论，避免正式任务文档依赖临时会话记录。

## 设计目标

- AppContainer / AppDelegate 装配 v2 runtime，并让启动期 fail-fast 到明确的 NSAlert。
- 触发链从旧 `ToolExecutor` 切到 `ExecutionEngine.execute(tool:seed:)`。
- 删除 v1 `Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` / `ToolExecutor` 等冲突类型族。
- 将 M1 阶段的 `V2*` 独立类型回归 spec canonical 名称。
- 将 `PresentationMode` 回归为 `DisplayMode`，将 `SelectionOrigin` 回归为 `SelectionSource`。
- 保留旧 `config.json` 兼容能力，真实运行改读写独立 `config-v2.json`。
- 完成触发链、配置迁移、命名残留、手工 GUI 和 release 前置验收。

## 关键决议

- M3.1 先做 additive 装配，再执行 M3.0 caller switch。原因是 caller switch 依赖 `ExecutionEngine`、`OutputDispatcher`、`InvocationGate` 与 `ResultPanelWindowSinkAdapter` 已在 App target 中可用。
- `SelectionReader` 是读取器协议名，`SelectionSource` 是选区来源枚举名；两者不能混用。
- `OutputDispatcher` 在 v0.2.0 对 non-window `DisplayMode` 统一 fallback 到 window sink，避免旧 bubble / replace 配置迁移后不可用。
- `InvocationGate` 放在 Orchestration target，生产 adapter 和测试都使用同一份 single-flight 状态实现，避免 spy copy 契约假阳性。
- `config-v2.json` 损坏或 app support 不可写时属于启动失败路径，由 `AppDelegate` 展示 “SliceAI 启动失败” 并退出；Settings 页面横幅不作为 v0.2.0 验收路径。
- Release tag 统一为 SemVer `v0.2.0`，本地 DMG、CI DMG 与 GitHub Release 文件名都使用 `SliceAI-0.2.0.dmg`。

## 任务结果

- mini-spec 与 implementation plan 已完成多轮 review / 修订，并在实施前对齐到同一口径。
- M3.0–M3.4 自动化验收已通过。
- M3.5 13 项手工回归已由用户反馈全部通过。
- M3.6 已完成文档归档、最后 4 关 gate、`SliceAI-0.2.0.dmg` 打包、SHA256、DMG 挂载结构校验与临时安装 / 启动校验；远端 release 仍需执行前确认。

## 风险与后续

- Phase 1 才实现真实 MCP stdio / SSE client；当前仍是 production-side mock。
- Phase 2 才实现 Skill registry 真实文件扫描，以及 bubble / replace / structured / silent / file 等 display mode 的真实输出 UI。
- 当前 unsigned DMG 未做代码签名和公证；发布说明必须明确安装方式与 SHA256。
