# SliceAI

> macOS 开源划词触发 LLM 工具栏

SliceAI 让你在任何 Mac 应用里选中文字后，通过快捷工具栏或 `⌥Space` 命令面板调用 OpenAI 兼容的大模型，流式查看结果。

## Status

v0.1 开发中。参见 [docs/superpowers/plans](docs/superpowers/plans/) 跟踪进度。

## Features (MVP v0.1)

- 划词后自动弹出浮条工具栏（PopClip 风格）
- `⌥Space` 快捷键唤起中央命令面板
- 独立浮窗 Markdown 流式渲染
- 支持 OpenAI 兼容协议（OpenAI、DeepSeek、Moonshot、OpenRouter、自建中转…）
- 4 个内置工具：Translate / Polish / Summarize / Explain
- 自定义 prompt、供应商、模型
- API Key 存 macOS Keychain

## Build from source

```bash
git clone https://github.com/<you>/SliceAI.git
cd SliceAI
open SliceAI.xcodeproj
# Product → Run
```

## Requirements

- macOS 14 Sonoma 或更新
- Xcode 26 或更新
- Swift 6.0

## 项目修改变动记录

### 2026-04-27 · Phase 0 M2 · Orchestration + Capabilities 骨架

**范围**：Task 0–14（plan `docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`，39 commits 自 M1 PR #1 merge `5cdf0f7`）

**主要变更**：
- **Orchestration 模块完整落地**：`ExecutionEngine` actor 主流程串起 spec §3.4 Step 1-10（PermissionGraph 静态闭环 → PermissionBroker.gate → ContextCollector 平铺并发 → ProviderResolver → PromptExecutor → OutputDispatcher → CostAccounting → JSONLAuditLog → finishSuccess）；事件流 `ExecutionEvent` + 终态报告 `InvocationReport`（含 declared/effective 权限差异 + flags + outcome）
- **Capabilities 模块 + SecurityKit**：`PathSandbox`（路径规范化 + 默认白名单 + 硬禁止表，含 macOS `/private/etc` symlink 展开后的兜底）+ `MCPClientProtocol` / `SkillRegistryProtocol` 完整接口 + production-side `MockMCPClient` / `MockSkillRegistry`（Phase 1 才实现真实 stdio/SSE）
- **权限闭环（spec §3.9.6.5）**：`EffectivePermissions` 5 字段（context/sideEffect/mcp/builtin/declared）+ `PermissionGraph.compute` D-24 静态闭环 + `PermissionBroker` 4 态决策（approved / denied / requiresUserConsent / wouldRequireConsent）+ `ConsentUXHint` 5×4 矩阵（spec §3.9.2 下限 × provenance）
- **遥测 + 安全下限**：`CostAccounting` actor + sqlite append（毫秒精度 `recorded_at` + `usd: TEXT` Decimal 精度）；`JSONLAuditLog` actor + `Redaction.scrub` 4 模式脱敏（Bearer / sk- / Authorization / Cookie）+ `AuditEntry` enum 3 case（含 `.logCleared`）；`SliceCore.SliceError` 加 `.context` / `.toolPermission` 顶层 case，全部 String payload 严格 `<redacted>`
- **PromptExecutor 复制非替换**（§C-7）：从 `SliceCore/ToolExecutor.swift` 复制 prompt 渲染逻辑到 `Orchestration/Executors/PromptExecutor.swift`（升级到 V2 类型 + `PromptStreamElement` enum + `UsageStats` token 估算），**v1 ToolExecutor.swift 0 行 diff**——M3 才删旧文件
- **§C-1 Zero-touch v1**：v1 8 模块（LLMProviders / SelectionCapture / HotkeyManager / DesignSystem / Windowing / Permissions / SettingsUI）+ SliceAIApp 自 baseline 起严格 0 行 diff；SliceCore 仅白名单 3 文件（SliceError + ContextError + ToolPermissionError）

**验证状态**：
- `swift build`：Build complete (0.20s)
- `swift test --parallel --enable-code-coverage`：**545/545 tests pass** (0.48s)
- `swiftlint lint --strict`：**133 files / 0 violations / 0 serious**
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：**BUILD SUCCEEDED**
- 覆盖率（行覆盖）：**Orchestration 89.12%（≥75%）/ Capabilities 97.64%（≥60%）/ SliceCore 92.73%（≥90%）**
- Zero-touch：v1 8 模块 + SliceAIApp + ToolExecutor 共 0 行 diff；SliceCore 仅 3 个白名单文件
- enum-switch `default:` 反向断言：PermissionBroker / ExecutionEngine / ExecutionEngine+Steps / InvocationReport 全部 0 个 default 兜底（C-3 / C-10 不变量持守）

**M2 不做（保留给后续 Phase）**：
- AppContainer 接入 ExecutionEngine 与触发链（M3）
- 删除 `SliceCore/ToolExecutor.swift` + rename pass（M3）
- 真实 MCPClient（stdio/SSE，Phase 1）+ 真实 SkillRegistry（fs scan，Phase 2）
- OutputDispatcher 的 `.clipboard` / `.replaceSelection` / `.notification` / `.sideOnly` / `.window+notification` 5 种 mode（Phase 2，M2 仅 `.window` 真实分发，其余 `.notImplemented`）

### 2026-04-21 · UI 全面美化 + Task 22 收官

**范围**：Task 18–22（跨越约 4 周的 MVP v0.1 UI 迭代）

**主要变更**：
- 新增 `DesignSystem` SwiftPM target：颜色/字体/间距/圆角/阴影/动画 token + 交互 modifier（GlassBackground、HoverHighlight、PressScale）+ 基础组件（IconButton、PillButton、Chip、KbdKey、SectionCard）
- `ThemeManager` + `AppearanceMode`：全局浅色/深色/跟随系统主题切换，`onModeChange` 回调持久化到 config.json
- 重构所有面板（FloatingToolbarPanel / CommandPalettePanel / ResultPanel）使用 DesignSystem token，删除旧 `PanelStyle.swift`
- 设置界面迁移为 `NavigationSplitView`，新增外观页（Appearance）；填充所有设置子页内容
- `OnboardingFlow` 重设计：560×520 步骤指示器 + Hero 图标风格
- `MenuBarController` 增强：外观子菜单（跟随系统/浅色/深色）+ 未配置 Provider 时图标右上角叠加紫色小红点
- SwiftLint strict 清零：修复 `implicit_return`、`opening_brace`、`sorted_imports`、`line_length`、`force_unwrapping` 共 6 处（4 项真实修复，2 项加 disable 注释说明原因）

**验证状态**：
- `swift build`：Build complete
- `swift test --parallel`：All tests passed
- `swiftlint lint --strict`：0 violations, 0 serious
- `xcodebuild`：BUILD SUCCEEDED

## License

MIT — see [LICENSE](LICENSE)
