# SliceAI

> macOS 开源划词触发 LLM 工具栏

SliceAI 让你在任何 Mac 应用里选中文字后，通过快捷工具栏或 `⌥Space` 命令面板调用 OpenAI 兼容的大模型，流式查看结果。

## Status

v0.2.0 Phase 0 底层重构已正式发布：v2 数据模型、Orchestration 执行引擎、Capabilities 能力边界已接入真实 App 触发链。Release: <https://github.com/yingjialong/SliceAI/releases/tag/v0.2.0>。参见 [docs/v2-refactor-master-todolist.md](docs/v2-refactor-master-todolist.md) 跟踪后续 Phase。

## Features (MVP v0.2)

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

## Architecture Modules

| 模块 | 职责 |
|---|---|
| `SliceAIApp` | macOS App 薄壳：菜单栏、Onboarding、全局触发监听、Composition Root、ResultPanel 生命周期。 |
| `SliceCore` | 领域模型与配置：`Tool` / `Provider` / `Configuration` / `ExecutionSeed` / `ResolvedExecutionContext` / 权限 / 输出绑定。 |
| `Orchestration` | v2 执行引擎：`ExecutionEngine`、上下文采集、权限闭环、PromptExecutor、OutputDispatcher、成本记账、审计日志。 |
| `Capabilities` | Phase 1+ 能力边界：`PathSandbox`、MCP client 协议、Skill registry 协议和生产侧 mock。 |
| `LLMProviders` | OpenAI 兼容协议实现与 provider factory，负责 Chat Completions / SSE 流式解析。 |
| `SelectionCapture` | 选区捕获：AX 主路径 + Cmd+C fallback，统一产出 `SelectionPayload`。 |
| `HotkeyManager` | Carbon `RegisterEventHotKey` 全局快捷键注册与解析。 |
| `Windowing` | FloatingToolbar、CommandPalette、ResultPanel 与屏幕定位算法。 |
| `SettingsUI` | SwiftUI 设置界面、KeychainStore、Provider / Tool 编辑器、配置即时保存。 |
| `DesignSystem` / `Permissions` | 设计 token、主题管理、共享控件与 Accessibility onboarding / monitor。 |

## 项目修改变动记录

### 2026-05-04 · Phase 0 M3 · Switch to V2

**范围**：plan `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`，分支 `feature/phase-0-m3-switch-to-v2`

**主要变更**：
- **触发链切到 v2**：`AppDelegate` 的浮条与 `⌥Space` 命令面板执行入口改为构造 `ExecutionSeed`，通过 `ExecutionEngine.execute(tool:seed:)` 消费 `ExecutionEvent` stream，再由 `ExecutionEventConsumer` 翻译到既有 `ResultPanel`。
- **配置切到 `config-v2.json`**：`AppContainer.bootstrap()` 启动期 eager load `ConfigurationStore.current()`；首次启动写入默认 v2 配置，已有 `config.json` 时通过 migrator 迁移，旧 `config.json` 保持兼容不被覆写。
- **删除 v1 冲突类型族**：移除旧 `ToolExecutor`、`Tool` / `Provider` / `Configuration` / `ConfigurationStore` / `DefaultConfiguration` v1 文件；`V2*` 类型回归 spec canonical 名称。
- **命名回归 spec**：`PresentationMode` → `DisplayMode`，`SelectionOrigin` → `SelectionSource`；保留 `SelectionReader` 作为读取器接口，避免与来源枚举混淆。
- **ResultPanel single-flight**：新增 `InvocationGate` 与 `ResultPanelWindowSinkAdapter`，旧 invocation 的 chunk / terminal event 不会污染新 invocation。
- **Provider factory 升级**：`LLMProviderFactory` 直接接收 canonical `Provider`，并在读取 Keychain 前先做 provider kind / baseURL preflight，避免配置错误被误报为 API Key 缺失。

**验证状态**：
- CLI gate：`swift build`、`swift test --parallel --enable-code-coverage`、`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`、`swiftlint lint --strict` 已通过。
- M3.4 grep validation：v1 / `V2*` / `PresentationMode` / `SelectionOrigin` 源码测试范围 0 命中。
- M3.5 13 项手工回归：用户反馈剩余项均已测试通过；2026-05-04 已记录安全子集实机证据。
- M3.6：本地文档归档、最后 4 关 gate、`SliceAI-0.2.0.dmg` 打包、SHA256、DMG 挂载结构校验与临时安装 / 启动校验已完成；PR #3 已 merge，`v0.2.0` tag 已发布，GitHub Release 已正式发布。Release DMG SHA256 为 `2d7749a1405e1ec4051b90b8b3ee5e029f5819e18a2cf69eda074f2de5b98aea`。

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
