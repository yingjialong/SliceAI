# Phase 0 M1 · 核心类型与配置迁移 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 SliceAI v2.0 spec §3.3 的领域模型（Tool 三态 / ExecutionSeed / ResolvedExecutionContext / Permission / Provenance / ContextProvider / OutputBinding / ProviderSelection / Skill / MCPDescriptor）落地为 `SliceCore` 中的正式 Swift 类型，同时新建 `Orchestration` / `Capabilities` 两个空 target；完成 `config.json` (v1) → `config-v2.json` (v2) 的独立路径迁移器，**app 行为保持 v0.1 不变**。

**Architecture（第五轮评审修订，彻底隔离 v1 / v2 类型）:** 纯领域层扩展——**v2 所有核心结构以独立 `V2*` 命名新建，v1 类型完全不动**。
- `SliceCore` 新增 `V2Tool` / `V2Provider` / `V2Configuration` / `V2ConfigurationStore` 等独立类型；现有 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` struct 保持 v1 形状原封不动
- `Orchestration` / `Capabilities` 仅建 target + 占位文件让 CI 先绿
- **零触及**：`ToolExecutor` / `AppContainer` / `ToolEditorView` / `SettingsViewModel` / `OpenAICompatibleProvider` / `FileConfigurationStore` / `SelectionPayload`
- `SelectionSnapshot` 是新独立类型（仅用于 `ExecutionSeed.selection`）；`SelectionPayload.swift` 原封保留
- **v1 `config.json` 绝不会被 v2 形状 JSON 写入**：`Configuration.currentSchemaVersion` **保持 `1`**（升级到 2 是 M3 的事）；`FileConfigurationStore` 签名不变、读写的仍是现有 `Configuration`（含扁平 `Tool`）；v2 配置 schema 用独立的 `V2Configuration` + 新增 `V2ConfigurationStore` actor，**仅供 migrator 单测和 M3 未来启用**；M1 不在真实 app 启动路径上启用
- v2 canonical JSON schema 由**手写 Codable + golden JSON 测试**锁定（Permission / Provenance / CachePolicy / SideEffect / ProviderSelection / ConditionExpr / MCPCapability / ToolKind / PipelineStep / TransformOp），不依赖 Swift 编译器自动合成（避免 `_0` 等实现细节泄漏进用户可见配置）。**`ContextValue` 不 Codable、不进入 JSON**（见 Task 7）
- `V2Provider.baseURL: URL?`（允许 Anthropic/Gemini 等协议族 nil）；**但现有 `Provider.baseURL: URL`** 非 optional 保持不变，LLMProviders / SettingsUI 编译不受影响
- **M3 承担的技术债（评审 P2-4 第六轮）**：本 plan 通过"新建 V2* 独立类型"隔离 v1，代价是把 rename 工作推到 M3。M3 plan **必须把以下任务列为一等主任务**，而非附带清理（spec §4.2 M3 需要相应更新，**不能轻描淡写**）：
  1. 删除 `Tool.swift` / `Provider.swift` / `Configuration.swift` / `DefaultConfiguration.swift` / `SelectionPayload.swift` / `ConfigurationStore.swift` 全部旧文件
  2. 把 `V2Tool.swift` → `Tool.swift`（类型 + 文件名双重 rename），同理 V2Provider / V2Configuration / V2ConfigurationStore / DefaultV2Configuration
  3. 同步改 `ToolExecutor` / `AppContainer` / `ToolEditorView` / `SettingsViewModel` / `OpenAICompatibleProvider` / `SelectionCapture` / `Windowing` 等**所有**对旧类型名 / 旧字段（systemPrompt / userPrompt / providerId 等扁平字段）的引用
  4. 把 config 文件路径从 `config.json` 切到 `config-v2.json`（AppContainer 换用 V2ConfigurationStore）
  5. 处理既有用户的 `~/Library/Application Support/SliceAI/config.json` migration（首次启动时触发）
  6. 同步更新 `ToolEditorView` 的 UI（v1 编辑 Tool 扁平字段 → v2 按 `ToolKind` 分派到 prompt/agent/pipeline 编辑器）
  7. 更新所有涉及 `Tool` / `Provider` / `Configuration` 的测试引用

预估 M3 单独约 3–5 人天（比原 spec §4.2 的 "3–5 人天"是同量级，但重点完全不同：spec 的 3–5 天主要是"删旧 ToolExecutor + 切 AppContainer"，本 plan 落地后 M3 的 3–5 天主要是"rename 整个类型族 + UI kind-aware 编辑器"）。这意味着 spec §4.2 M3 的任务清单需要在 M3 启动前独立 spec 一次

**Tech Stack:** Swift 6.0 / XCTest / `swift build` / `swift test --parallel --enable-code-coverage` / SwiftLint strict / `Codable` / Foundation only（SliceCore 零 UI 依赖）。

**References:**
- Spec: `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md` §3.3 / §3.7 / §3.9 / §4.2 M1
- 决策：D-16（两阶段 context）/ D-18（独立 config 路径）/ D-19（冻结收敛）/ D-20（M1/M2/M3 拆分）/ D-22（能力下限）/ D-23（Provenance + MCP 威胁）/ D-24（权限声明闭环）/ D-25（firstParty 不跳过首次确认）
- **本 plan 第四轮评审修订**（Codex 2026-04-23）：三条 P1 全部接受并落地——(1) `SelectionSnapshot` 不再做"重命名 + 兼容"双头路线，改为干净 v2 新类型，`SelectionPayload` 原封保留；(2) `Tool` 的 v1 bridge 对非 `.prompt` 形态 `assertionFailure` + 生产 no-op，避免静默篡改；(3) M1 DoD 口径收紧，不再声称真实 app 启动路径已完成迁移，只承诺"migrator 对 fixture 全绿、v2 路径 API 由单测覆盖"。详见评审记录 `docs/Task-detail/phase-0-m1-plan-review-2026-04-24.md`。

---

## 评审修正索引（Review Amendments）

> 本 plan 在撰写与实施期间经历多轮 Codex 评审，关键改动集中在此（按时序）。
>
> **代码块快照约定（第八轮评审补记）**：plan 正文里的 Swift 代码块是"实施期路径指南"，记录 Task N 那一刻的实现蓝本，**不会**回填后续 fix commit 的更新。后续 worker 需要**最终源码**时应读 `SliceAIKit/Sources/SliceCore/` 下的对应文件，而非 plan 里的代码块。当落地代码与本 plan 叙述/代码块不一致时，**以本索引 + 最终源码为准**。

### A. 实施期改名（与旧设计文字不一致）

| 旧名（spec / plan 初稿） | 新名（M1 实际落地） | 原因 | 影响范围 |
|---|---|---|---|
| `DisplayMode`（v2 六态新枚举） | **`PresentationMode`** | `SliceAIKit/Sources/SliceCore/Tool.swift:85` 已存在 v1 `public enum DisplayMode`（3-case，v1 Tool 专用），v2 直接复用名字会造成 API 歧义；rawValue 完全超集 v1，migrator 零损失 | `OutputBinding.primary` / `V2Tool.displayMode` 字段类型 |
| `SelectionSource`（v2 枚举：`.accessibility` / `.clipboardFallback` / `.inputBox`） | **`SelectionOrigin`** | `SliceAIKit/Sources/SelectionCapture/SelectionSource.swift` 已存在 v1 `public protocol SelectionSource`，v2 直接复用名字会造成跨 target 命名冲突 | `SelectionSnapshot.source` 字段类型 |

**M3 rename pass 统一处理**：M3 删除 v1 `DisplayMode` enum 与 `SelectionSource` protocol 之后，再把 `PresentationMode` → `DisplayMode` / `SelectionOrigin` → `SelectionSource` 重命名回 spec 原始意图。

### B. 第七轮评审（Codex 2026-04-24，M1 merge 前）

> 针对已完成 36 commit 的 M1 实施做最终质量评审；三条 findings 全部接受并落地为独立 fix commit，**不影响 M1 功能范围**，只收紧类型不变量。

| Finding | 问题 | 修复 commit | 修复范围 |
|---|---|---|---|
| **P1** `V2ConfigurationStore.current()` 吞错误 | `try? await load()` 把"v2 JSON 损坏 / schema 太新 / v1 JSON 损坏"都静默回退到 `DefaultV2Configuration.initial()`；M3 接入后下一次 `update()` 会**永久覆盖**用户配置文件 = 真实数据丢失 | `e64c3d3` | `current()` 签名改为 `async throws`，让 `load()` 的错误原样外抛；"两份文件都不存在"继续走 `load()` 内部的 first-launch 默认分支。+4 tests（corrupted v2 / schemaTooNew / corrupted legacy / both missing）|
| **P2a** `V2Provider.baseURL` 类型层无约束 | 注释声明 "Anthropic/Gemini 允许 nil" 的 intent，但 `ProviderKind.openAICompatible` / `.ollama`（必须用户填 endpoint 才能工作）的 baseURL 也能是 nil；手改 `config-v2.json` 写 `"kind":"openAICompatible","baseURL":null` 能解码成功，只在真实调用时才炸 | `2b7095c` | `init(from:)` 加 fail-fast 校验：`kind == .openAICompatible \|\| .ollama` 且 `baseURL == nil` 时 throw `DecodingError.dataCorrupted`；主构造器 `init(id:...)` 非 throws 保持不变（`DefaultV2Configuration.openAIDefault` 作为开发期 `static let` 由 review 保证不变量）。+4 decoder tests |
| **P2b** `V2Tool.displayMode` vs `outputBinding.primary` 单一事实源 | `displayMode: PresentationMode`（必填）与 `outputBinding: OutputBinding?`（`primary` 也是 `PresentationMode`）共存，允许 `displayMode = .window + outputBinding.primary = .replace`，未来 `ExecutionEngine` 读哪个都对不上另一个 | `d141c05` | V2Tool 从自动合成 Codable 改为手写 `init(from:) / encode(to:)`（JSON shape 不变，既有 golden 测试全绿），解码时当 `outputBinding != nil && outputBinding.primary != displayMode` 时 throw `DecodingError.dataCorrupted`；未来 ExecutionEngine 以 `displayMode` 为 primary truth，`outputBinding.primary` 仅作对称展示以兼容 OutputBinding 数据模型 | +4 tests |

**M3 承接**：M3 重命名阶段，AppContainer 接入 `V2ConfigurationStore.current()` 时必须处理 `throws`——建议在启动时用 alert 告警并中止启动，**不要**静默回退（这条正是 P1 修复的原始意图）。

### C. 第八轮评审（Codex 2026-04-24，收紧类型层不变量）

> 承接第七轮：第七轮把不变量锁在 decoder（只挡"外部 JSON 输入"），第八轮把相同不变量延伸到**写入边界**（挡"代码构造非法对象再保存"）+ **migrator 校验 schema**。M1 本身无真实生产路径不会立即爆炸，但 M3 UI / AppContainer 一接入这些 public init 就是用户入口——不能等到那时才守。

| Finding | 问题 | 修复 commit | 修复范围 |
|---|---|---|---|
| **P2-1** `V2Provider` 的 `baseURL` 必填约束只覆盖 decoder | `init(from:)` 拒绝 `.openAICompatible` / `.ollama` + nil baseURL，但 public `init(id:...)` 非 throws 仍允许同样的非法对象被代码构造后写入 `config-v2.json`。类型层不变量没被完全锁定 | `03fa632` | 加 `public func validate() throws`（镜像 decoder 校验，抛 `SliceError.configuration(.validationFailed(msg))`）；`V2ConfigurationStore.save()` 在 `writeV2` 前逐个 `try p.validate()`；主 `init(id:...)` 非 throws 保持不变（保护 `DefaultV2Configuration.openAIDefault` 作为 `static let` 的可行性）；decoder 既有校验不变。+2 tests |
| **P2-2** `V2Tool.displayMode` / `outputBinding.primary` 一致性同问题 | 同 P2-1，手改 JSON 被挡但代码构造非法 V2Tool 仍可被 `V2ConfigurationStore.update()` 保存 | `03fa632` | 同方案：`V2Tool.validate()` + `V2ConfigurationStore.save()` 写入边界调用。**拒绝**备选方案"自动规范化 outputBinding.primary = displayMode"——静默修改用户显式声明违反最小意外原则。+2 tests |
| **P2-3** `ConfigMigratorV1ToV2` 不校验 `v1.schemaVersion` | migrator 读了 `LegacyConfigV1.schemaVersion` 但从未校验；手改 `config.json` 为 `schemaVersion: 2` 且字段碰巧兼容时会被盲目迁移，导致数据含义错乱 | `2f4f8d9` | `migrate(_ v1:)` 改 throwing，首行 `guard v1.schemaVersion == 1 else throw SliceError.configuration(.schemaVersionTooNew(v1.schemaVersion))`；`V2ConfigurationStore.migrateFromLegacy` 调用加 `try`。+2 tests（migrator 单测 + load 端到端）|

**配套改动**：`SliceError.ConfigurationError` 加 `case validationFailed(String)`（`14a5500`）：`userMessage` 透传 msg，`developerContext` 按脱敏规则输出 `"configuration.validationFailed(<redacted>)"`。+1 test。

**M3 承接**：AppContainer 的 settings UI 写入新 Provider / Tool 前，应当在 UI 层先 call `.validate()` 给用户即时反馈（save() 是最后一道防线、不应该是首次反馈）。

---

## 文件清单（File Structure）

| 类型 | 路径 | 责任 |
|---|---|---|
| Modify | `SliceAIKit/Package.swift` | 注册 `Orchestration` / `Capabilities` library + target + testTarget |
| Create | `SliceAIKit/Sources/Orchestration/Placeholder.swift` | 让空 target 可 build（SwiftPM 不允许空目录） |
| Create | `SliceAIKit/Sources/Orchestration/README.md` | target 定位说明（M2 填实） |
| Create | `SliceAIKit/Sources/Capabilities/Placeholder.swift` | 同上 |
| Create | `SliceAIKit/Sources/Capabilities/README.md` | target 定位说明 |
| Create | `SliceAIKit/Tests/OrchestrationTests/PlaceholderTests.swift` | 空 target 的占位测试 |
| Create | `SliceAIKit/Tests/CapabilitiesTests/PlaceholderTests.swift` | 同上 |
| Create | `SliceAIKit/Sources/SliceCore/ContextKey.swift` | `ContextKey` struct + `Requiredness` enum |
| Create | `SliceAIKit/Sources/SliceCore/Permission.swift` | `Permission` / `PermissionGrant` / `Provenance` / `GrantSource` / `GrantScope` |
| Create | `SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift` | v2 干净类型：`text` / `source` / `length` / `language` / `contentType`；**不含** v1 `appBundleID` / `url` / `screenPoint` / `timestamp`；**不提供 typealias 到 SelectionPayload** |
| Keep | `SliceAIKit/Sources/SliceCore/SelectionPayload.swift` | **原封不动**；v1 触发链继续使用；M3 才做 `SelectionPayload → ExecutionSeed` 一次性映射 |
| Create | `SliceAIKit/Sources/SliceCore/SelectionContentType.swift` | `SelectionContentType` / `SelectionOrigin`（新 enum；`SelectionPayload.Source` 原样保留独立；命名避开 `SelectionCapture/SelectionSource.swift` 的 `protocol SelectionSource` 冲突——详见 Task 4） |
| Create | `SliceAIKit/Sources/SliceCore/AppSnapshot.swift` | 包装 `appBundleID` / `appName` / `url` / `windowTitle` |
| Create | `SliceAIKit/Sources/SliceCore/TriggerSource.swift` | `TriggerSource` enum |
| Create | `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift` | 不可变 seed |
| Create | `SliceAIKit/Sources/SliceCore/ContextBag.swift` | `ContextBag` + `ContextValue` |
| Create | `SliceAIKit/Sources/SliceCore/ResolvedExecutionContext.swift` | 不可变解析后 context |
| Create | `SliceAIKit/Sources/SliceCore/Context.swift` | `ContextRequest` + `ContextProvider` protocol（含 `inferredPermissions`，D-24） |
| Create | `SliceAIKit/Sources/SliceCore/OutputBinding.swift` | `OutputBinding` + `PresentationMode`（六态）+ `SideEffect` + `inferredPermissions` extension |
| Create | `SliceAIKit/Sources/SliceCore/ProviderSelection.swift` | `ProviderSelection` + `ProviderCapability` + `CascadeRule` + `ConditionExpr`（手写 Codable） |
| Create | `SliceAIKit/Sources/SliceCore/V2Provider.swift` | **独立 v2 类型** `V2Provider` + `ProviderKind`；`baseURL: URL?` 允许 Anthropic/Gemini 等协议族 nil；**不改** 现有 `Provider.swift` |
| Keep | `SliceAIKit/Sources/SliceCore/Provider.swift` | **原封不动**；LLMProviders / SettingsUI 继续消费 |
| Create | `SliceAIKit/Sources/SliceCore/Skill.swift` | `Skill` / `SkillManifest` / `SkillReference` / `SkillResource` |
| Create | `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift` | `MCPDescriptor` / `MCPTransport` / `MCPToolRef` / `MCPCapability` |
| Create | `SliceAIKit/Sources/SliceCore/ToolKind.swift` | `ToolKind` + `PromptTool` / `AgentTool` / `PipelineTool` + 附属类型（手写 Codable） |
| Create | `SliceAIKit/Sources/SliceCore/V2Tool.swift` | **独立 v2 类型** `V2Tool`（三态 kind + provenance + permissions + outputBinding + visibleWhen + budget + hotkey + tags）；**无** v1 扁平字段、**无** v1 init、**无** v1 accessor |
| Keep | `SliceAIKit/Sources/SliceCore/Tool.swift` | **原封不动**；ToolExecutor / ToolEditorView / DefaultConfiguration 继续消费 |
| Create | `SliceAIKit/Sources/SliceCore/ToolBudget.swift` | `ToolBudget` struct |
| Create | `SliceAIKit/Sources/SliceCore/ToolMatcher.swift` | `ToolMatcher` struct |
| Create | `SliceAIKit/Sources/SliceCore/LegacyConfigV1.swift` | v1 扁平快照结构，仅 migration 使用 |
| Create | `SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift` | `ConfigMigratorV1ToV2.migrate(_:) -> V2Configuration` |
| Create | `SliceAIKit/Sources/SliceCore/V2Configuration.swift` | **独立 v2 类型** `V2Configuration`（含 `tools: [V2Tool]` / `providers: [V2Provider]`）；`currentSchemaVersion = 2` 是 V2Configuration 的静态常量，不影响旧 `Configuration` |
| Create | `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift` | **独立 v2 actor**；读写 `config-v2.json`；启动时若 v2 文件缺失但 v1 存在则跑 migrator；**不被 AppContainer 使用**，仅供单测 + M3 |
| Keep | `SliceAIKit/Sources/SliceCore/Configuration.swift` | **原封不动**；`currentSchemaVersion = 1` |
| Keep | `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift` | **原封不动**；`FileConfigurationStore(fileURL:)` 继续读写 v1 |
| Keep | `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift` | **原封不动**；仍产出 v1 Tool/Provider |
| Create | `SliceAIKit/Sources/SliceCore/DefaultV2Configuration.swift` | v2 的默认配置（migrator 无 v1 文件时 fallback）；产出 V2Tool/V2Provider |
| Create | 17 个测试文件 | 见各 Task 内 |

全部改动限定在 `SliceAIKit/Package.swift` + `SliceAIKit/Sources/Orchestration/` + `SliceAIKit/Sources/Capabilities/` + `SliceAIKit/Sources/SliceCore/`（**仅新增文件**，不修改现有 `Tool.swift` / `Provider.swift` / `Configuration.swift` / `ConfigurationStore.swift` / `DefaultConfiguration.swift`） + `SliceAIKit/Tests/SliceCoreTests/` + 两个新 Tests 目录；**零触及** `LLMProviders` / `SelectionCapture` / `HotkeyManager` / `DesignSystem` / `Windowing` / `Permissions` / `SettingsUI` / `SliceAIApp`（除 M3 才动）。

---

## Canonical JSON Schema：手写 Codable 模板（**所有 associated-value enum 强制遵循**）

> **评审修正（Codex 第六轮 P1-1）**：上一版虽然声称"手写 Codable + golden test"，但实际 enum 定义仍用 `: Codable` 依赖 Swift 自动合成。Swift 5.9+ 对 `case a(Payload)` 的自动合成产出是 `{"a":{"_0":{...}}}`——golden test 要求"不含 `_0`"将直接失败。本节定义一次性的手写 Codable 模式，所有后续 associated-value enum 必须按此实现；个别 Task 的代码块只需照抄模板。

### 模板 A：single-key discriminator（单 associated value + 无值 case 混合）

适用 `ToolKind` / `PipelineStep` / `SideEffect` / `MCPCapability` / `TransformOp` / `ProviderSelection` / `ConditionExpr` / `CachePolicy` / `Provenance`。

```swift
public enum Foo: Codable, Sendable, Equatable {
    case a(PayloadA)
    case b(PayloadB)
    case c                              // 无 associated value
    // ... 多 associated value 的 case 见模板 B

    private enum CodingKeys: String, CodingKey {
        case a, b, c
    }

    /// 空对象哨兵，用于编码无 associated value 的 case 为 `{"c":{}}`
    private struct EmptyCaseMarker: Codable, Equatable {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let p = try container.decodeIfPresent(PayloadA.self, forKey: .a) {
            self = .a(p); return
        }
        if let p = try container.decodeIfPresent(PayloadB.self, forKey: .b) {
            self = .b(p); return
        }
        if container.contains(.c) {
            _ = try container.decode(EmptyCaseMarker.self, forKey: .c)
            self = .c; return
        }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.a, in: container,
            debugDescription: "Foo requires exactly one of: a, b, c"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .a(let p): try container.encode(p, forKey: .a)
        case .b(let p): try container.encode(p, forKey: .b)
        case .c:        try container.encode(EmptyCaseMarker(), forKey: .c)
        }
    }
}
```

产出 JSON：`{"a":{...PayloadA...}}` / `{"b":{...PayloadB...}}` / `{"c":{}}`。**保证不含 `_0`**。

### 模板 B：多 associated value 的 case（嵌套中转 struct）

适用 `Permission.mcp(server:tools:)` 这类有多个 named associated value 的 case。API 保持原样（`.mcp(server: "x", tools: ["y"])`），内部用 private struct 做 Codable 中转：

```swift
public enum Permission: Codable, Sendable, Hashable {
    case mcp(server: String, tools: [String]?)
    case fileRead(path: String)
    case clipboard
    // ...

    /// Codable 中转 struct：仅用于 JSON 序列化，不暴露 API
    private struct MCPAccessRepr: Codable, Equatable {
        let server: String
        let tools: [String]?
    }

    // init(from:) 中：
    //   if let repr = try c.decodeIfPresent(MCPAccessRepr.self, forKey: .mcp) {
    //       self = .mcp(server: repr.server, tools: repr.tools); return
    //   }

    // encode(to:) 中：
    //   case .mcp(let server, let tools):
    //       try c.encode(MCPAccessRepr(server: server, tools: tools), forKey: .mcp)
}
```

产出 JSON：`{"mcp":{"server":"postgres","tools":["query"]}}` / `{"fileRead":"~/Docs"}` / `{"clipboard":{}}`。

### 模板 C：单 raw-string associated value（可选简化）

对 `.fileRead(path: String)` 之类 single-String 的 case，可**直接 encode 字符串**而不是包装对象，JSON 更紧凑：

```swift
case .fileRead(let path): try container.encode(path, forKey: .fileRead)
// decode:
if let path = try container.decodeIfPresent(String.self, forKey: .fileRead) {
    self = .fileRead(path: path); return
}
```

产出：`{"fileRead":"~/Docs"}`（无嵌套对象层）。**这是可选优化**，不强制；若选择用模板 C，后续 golden test 必须按单值断言。

### 模板 D：Golden JSON 测试（每个手写 Codable enum 必须配一个）

```swift
func test_fooKind_goldenJSON_usesSingleKeyDiscriminator() throws {
    let enc = JSONEncoder()
    enc.outputFormatting = [.sortedKeys]
    let data = try enc.encode(Foo.a(PayloadA(x: "u")))
    let json = try XCTUnwrap(String(data: data, encoding: .utf8))

    // 1. single-key discriminator 形式
    XCTAssertTrue(json.hasPrefix("{\"a\":"), "got: \(json)")
    // 2. 禁止 Swift 合成的 _0 泄漏
    XCTAssertFalse(json.contains("\"_0\""), "got: \(json)")
    // 3. round-trip 恒等
    let decoded = try JSONDecoder().decode(Foo.self, from: data)
    XCTAssertEqual(decoded, Foo.a(PayloadA(x: "u")))
}
```

### 不需要手写 Codable 的类型

- **raw-value enum**（如 `ProviderKind: String, Codable`、`ProviderCapability: String, Codable`、`PresentationMode: String, Codable`、`GrantSource: String, Codable`、`TriggerSource: String, Codable`、`SelectionContentType: String, Codable`、`ToolbarSize: String, Codable`、`MCPTransport: String, Codable`、`Requiredness: String, Codable`、`StepFailurePolicy: String, Codable`、`StopCondition: String, Codable`、`BuiltinCapability: String, Codable`、`AppearanceMode: String, Codable`、`ToolLabelStyle: String, Codable`）：合成的产物就是字符串，稳定且人类可读，保留自动合成。
- **struct**（`PromptTool` / `AgentTool` / `PipelineTool` / `V2Tool` / `V2Provider` / `V2Configuration` / `PermissionGrant` / `ContextRequest` / `ToolBudget` / `ToolMatcher` / `Skill` / `SkillManifest` / `SkillReference` / `SkillResource` / `MCPDescriptor` / `MCPToolRef` / `CascadeRule` / `OutputBinding` / `SelectionSnapshot` / `AppSnapshot` / `ExecutionSeed` 等）：字段都是标量或前面已手写 Codable 的 enum，自动合成可预测且稳定。

### 手写 Codable 强制覆盖清单

| Enum | 所在 Task | Case 模式 |
|---|---|---|
| `Permission` | Task 3 | 模板 B + C 混合（多 case 有 associated value；clipboard/screen 等无值） |
| `Provenance` | Task 3 | 模板 A（firstParty / communitySigned / selfManaged / unknown） |
| `CachePolicy` | Task 8 | 模板 A（none 无值，ttl 有值） |
| `SideEffect` | Task 10 | 模板 A + B 混合 |
| `ProviderSelection` | Task 11 | 模板 A（fixed / capability / cascade 都是嵌套 struct payload） |
| `ConditionExpr` | Task 11 | 模板 A + C（always 无值，其余单 associated） |
| `MCPCapability` | Task 13 | 模板 C（tools / resources / prompts 都是 [String]） |
| `ToolKind` | Task 14 | 模板 A（prompt / agent / pipeline 都是 struct） |
| `PipelineStep` | Task 14 | 模板 A + B（tool / prompt / mcp / transform / branch 混合） |
| `TransformOp` | Task 14 | 模板 A + B（jq 单值，regex 多值，jsonPath 单值） |
| `ContextValue` | Task 7 | **不适用**——本 enum 不实现 Codable（见 Task 7） |

每一项都必须在对应 Task 的 "实现" step 里按模板写出 init(from:) / encode(to:)，并在 "测试" step 里加至少一个模板 D 的 golden test。

---

## 任务依赖图

```
Task 0 (Task-detail + Task_history 初始化，前置)
  │
Task 1 (Package + 空 target + 两个 README exclude)  ──┐
Task 2 (ContextKey)                                    ├──> Task 8 (Context protocol) ──┐
Task 3 (Permission + Provenance)─────┤                                                   │
Task 4 (新建干净 SelectionSnapshot，不动 SelectionPayload)                               │
Task 5 (AppSnapshot + TriggerSource + SelectionContentType)                              │
Task 6 (ExecutionSeed) 依赖 Task 4 / 5                                                   │
Task 7 (ContextBag + ContextValue，非 Codable) 依赖 Task 2                              │
                                                                                         ├──> Task 13 (ToolKind + 手写 Codable + golden JSON) ──┐
Task 9 (ResolvedExecutionContext) 依赖 Task 6 / 7                                        │                                                        │
Task 10 (OutputBinding + SideEffect，手写 Codable + golden JSON) 依赖 Task 3             │                                                        │
Task 11 (ProviderSelection，手写 Codable + golden JSON) ─────────────────────────────────┘                                                        │
Task 12 (V2Provider 独立新类型，baseURL: URL?；不碰现有 Provider) 依赖 Task 11                                                                    │
Task 14 (Skill + MCPDescriptor，手写 Codable 关键 enum) 依赖 Task 3                                                                              │
                                                                                                                                                  │
                                                                                                                                                  ▼
                                                    Task 15 (V2Tool 独立新类型，干净三态无 v1 accessor；不碰现有 Tool)
                                                              │
                                                              ▼
Task 16 (LegacyConfigV1) ──┐
Task 17 (ConfigMigrator 产出 V2Configuration)   ├─> Task 18 (V2Configuration 独立类型；不改现有 Configuration) ──> Task 19 (V2ConfigurationStore 独立 actor；不改现有 FileConfigurationStore)
                                                                      │
                                                                      ▼
                                                       Task 20 (集成验证 + 文档归档)
```

---

## Task 0: 文档初始化（前置；项目规则要求）

> **评审修正（Codex 第五轮 P2-4）**：项目规则（CLAUDE.md）要求任务开始前创建 Task-detail 并持续更新；Task 编号必须按 Task_history 现状取下一个可用值，不硬编码。

**Files:**
- Create: `docs/Task-detail/<YYYY-MM-DD>-phase-0-m1-core-types.md`
- Modify: `docs/Task_history.md`（追加索引条目）

- [ ] **Step 1: 查看 Task_history 现状取下一个 Task 编号**

Run: `grep -E "^## Task [0-9]+" docs/Task_history.md | head -3`

从输出的最大编号 +1 作为本次 Task 编号（不硬编码；撰写时 Task_history 可能已被其他活动更新）。

- [ ] **Step 2: 创建 Task-detail 骨架（留空"实施内容 / 结果"待完成后填充）**

Create `docs/Task-detail/<今日日期>-phase-0-m1-core-types.md`:

```markdown
# Phase 0 M1 · 核心类型与配置迁移

- **时间**：<今日日期> 起
- **Plan**: [docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md](../superpowers/plans/2026-04-24-phase-0-m1-core-types.md)
- **Spec 参考**：[docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md](../superpowers/specs/2026-04-23-sliceai-v2-roadmap.md) §3.3 / §3.7 / §3.9 / §4.2 M1

## 任务背景（实施中可补充）

_待 Task 1 启动时更新_

## 实施内容

_按 Plan 推进时逐步填充；完成后归档整体 19 个 task 的产出_

## 修改文件清单

_完成后整理_

## 测试用例与结果

_完成后整理_

## 下一步

_完成后填_
```

- [ ] **Step 3: 在 Task_history.md 头部追加索引**

Modify `docs/Task_history.md`，在第二个 `---` 分隔符后（即 Task List 顶部）追加（把 `<N>` 替换为 Step 1 得到的编号）：

```markdown
## Task <N> · Phase 0 M1 · 核心类型与配置迁移（进行中）

- **时间**：<今日日期> 起
- **描述**：落地 v2.0 spec §3.3 / §3.7 / §3.9 定义的领域模型——**以独立 V2* 类型** 新建（V2Tool / V2Provider / V2Configuration / V2ConfigurationStore），不改动现有 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `DefaultConfiguration`；新建 Orchestration / Capabilities 空 target；ConfigMigratorV1ToV2 纯函数 migrator 产出 V2Configuration
- **详情**：[docs/Task-detail/<今日日期>-phase-0-m1-core-types.md](Task-detail/<今日日期>-phase-0-m1-core-types.md)
- **结果**：进行中 / 完成时更新

---
```

- [ ] **Step 4: Commit（Task 1 启动前的 snapshot）**

```bash
git add docs/Task-detail/<今日日期>-phase-0-m1-core-types.md docs/Task_history.md
git commit -m "docs(phase-0/m1): initialize Task-detail and history index

Create Task-detail skeleton and add Task history entry before implementation
begins, per project documentation rules. Body fields stay placeholder until
Task 20 (final archival)."
```

---

## Task 1: 新建 Orchestration + Capabilities 空 target

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Placeholder.swift`
- Create: `SliceAIKit/Sources/Orchestration/README.md`
- Create: `SliceAIKit/Sources/Capabilities/Placeholder.swift`
- Create: `SliceAIKit/Sources/Capabilities/README.md`
- Create: `SliceAIKit/Tests/OrchestrationTests/PlaceholderTests.swift`
- Create: `SliceAIKit/Tests/CapabilitiesTests/PlaceholderTests.swift`
- Modify: `SliceAIKit/Package.swift`

- [ ] **Step 1: 创建 Orchestration target 骨架**

Create `SliceAIKit/Sources/Orchestration/Placeholder.swift`:

```swift
import Foundation

/// Orchestration 执行层的占位符，仅用于让 SwiftPM 可构建空 target
/// M2 里会被真实类型（ExecutionEngine / ContextCollector / PermissionBroker 等）替代并删除
internal enum OrchestrationPlaceholder {}
```

Create `SliceAIKit/Sources/Orchestration/README.md`:

```markdown
# Orchestration

执行层（M2 填实）。职责：ExecutionEngine、ContextCollector、PermissionBroker、CostAccounting、AuditLog、OutputDispatcher、PromptExecutor、PermissionGraph。

## Phase 0 M1 状态
仅建空 target + 占位 Swift 文件，让 `swift build` 可成功。所有实现将在 M2 (`docs/superpowers/plans/*-phase-0-m2-*.md`) 加入。

依赖：`SliceCore` / `Capabilities`（后者暂未依赖，M2 再加）。
```

- [ ] **Step 2: 创建 Capabilities target 骨架**

Create `SliceAIKit/Sources/Capabilities/Placeholder.swift`:

```swift
import Foundation

/// Capabilities 能力层的占位符，仅用于让 SwiftPM 可构建空 target
/// M2 会加入 MCPClientProtocol / SkillRegistryProtocol 接口；Phase 1 填实
internal enum CapabilitiesPlaceholder {}
```

Create `SliceAIKit/Sources/Capabilities/README.md`:

```markdown
# Capabilities

能力层（M2 起填实）。职责：MCPClient、SkillRegistry、Memory、Filesystem / Shell / Vision / TTS 等外部能力 adapter、PathSandbox。

## Phase 0 M1 状态
仅建空 target + 占位 Swift 文件。

依赖：`SliceCore`。
```

- [ ] **Step 3: 创建占位测试**

Create `SliceAIKit/Tests/OrchestrationTests/PlaceholderTests.swift`:

```swift
import XCTest
@testable import Orchestration

/// M1 阶段的占位测试，仅保证 target 被编译与测试框架挂起
final class PlaceholderTests: XCTestCase {
    func test_targetCompiles() {
        // 无断言，编译通过即认为通过；M2 起替换为真实测试
        XCTAssertTrue(true)
    }
}
```

Create `SliceAIKit/Tests/CapabilitiesTests/PlaceholderTests.swift`:

```swift
import XCTest
@testable import Capabilities

final class PlaceholderTests: XCTestCase {
    func test_targetCompiles() {
        XCTAssertTrue(true)
    }
}
```

- [ ] **Step 4: 更新 Package.swift**

Modify `SliceAIKit/Package.swift`:

```swift
// swift-tools-version:6.0
// SliceAIKit - SliceAI 核心功能包，10 个 target 承载领域层、LLM、划词、快捷键、窗口、权限、设置、编排、能力、UI tokens
import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .enableExperimentalFeature("StrictConcurrency=complete"),
]

let package = Package(
    name: "SliceAIKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SliceCore", targets: ["SliceCore"]),
        .library(name: "LLMProviders", targets: ["LLMProviders"]),
        .library(name: "SelectionCapture", targets: ["SelectionCapture"]),
        .library(name: "HotkeyManager", targets: ["HotkeyManager"]),
        .library(name: "Windowing", targets: ["Windowing"]),
        .library(name: "Permissions", targets: ["Permissions"]),
        .library(name: "SettingsUI", targets: ["SettingsUI"]),
        .library(name: "DesignSystem", targets: ["DesignSystem"]),
        .library(name: "Orchestration", targets: ["Orchestration"]),
        .library(name: "Capabilities", targets: ["Capabilities"]),
    ],
    targets: [
        .target(name: "SliceCore", swiftSettings: swiftSettings),
        .target(name: "Capabilities",
                dependencies: ["SliceCore"],
                exclude: ["README.md"],
                swiftSettings: swiftSettings),
        .target(name: "Orchestration",
                dependencies: ["SliceCore"],
                exclude: ["README.md"],
                swiftSettings: swiftSettings),
        .target(name: "LLMProviders", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .target(name: "SelectionCapture", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .target(name: "HotkeyManager", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .target(name: "DesignSystem",
                dependencies: ["SliceCore"],
                exclude: ["README.md"],
                resources: [.process("Colors/Resources/Assets.xcassets")],
                swiftSettings: swiftSettings),
        .target(name: "Windowing", dependencies: ["SliceCore", "DesignSystem"], swiftSettings: swiftSettings),
        .target(name: "Permissions", dependencies: ["SliceCore", "DesignSystem"], swiftSettings: swiftSettings),
        .target(name: "SettingsUI",
                dependencies: ["SliceCore", "LLMProviders", "HotkeyManager", "DesignSystem", "Permissions"],
                swiftSettings: swiftSettings),
        .testTarget(name: "SliceCoreTests", dependencies: ["SliceCore"], swiftSettings: swiftSettings),
        .testTarget(name: "OrchestrationTests", dependencies: ["Orchestration", "SliceCore"], swiftSettings: swiftSettings),
        .testTarget(name: "CapabilitiesTests", dependencies: ["Capabilities", "SliceCore"], swiftSettings: swiftSettings),
        .testTarget(name: "LLMProvidersTests",
                    dependencies: ["LLMProviders", "SliceCore"],
                    resources: [.copy("Fixtures")],
                    swiftSettings: swiftSettings),
        .testTarget(name: "SelectionCaptureTests",
                    dependencies: ["SelectionCapture", "SliceCore"],
                    swiftSettings: swiftSettings),
        .testTarget(name: "HotkeyManagerTests",
                    dependencies: ["HotkeyManager", "SliceCore"],
                    swiftSettings: swiftSettings),
        .testTarget(name: "WindowingTests",
                    dependencies: ["Windowing", "SliceCore"],
                    swiftSettings: swiftSettings),
        .testTarget(name: "DesignSystemTests",
                    dependencies: ["DesignSystem", "SliceCore"],
                    swiftSettings: swiftSettings),
    ]
)
```

注：README.md 在 target 根目录时 SwiftPM 会发 warning（resource ambiguity）。已在 Package.swift 中给 Orchestration / Capabilities 两个 target 显式 `exclude: ["README.md"]`，参照现有 `DesignSystem` target 做法，避免实施阶段被 SwiftPM 诊断干扰。

- [ ] **Step 5: 跑编译与测试**

Run: `cd SliceAIKit && swift build`
Expected: `Build complete!`（全 10 个 library 通过）

Run: `cd SliceAIKit && swift test --filter OrchestrationTests`
Expected: `Test Suite 'OrchestrationTests' passed`

Run: `cd SliceAIKit && swift test --filter CapabilitiesTests`
Expected: `Test Suite 'CapabilitiesTests' passed`

- [ ] **Step 6: Commit**

```bash
cd /Users/majiajun/workspace/SliceAI
git add SliceAIKit/Package.swift \
        SliceAIKit/Sources/Orchestration/ \
        SliceAIKit/Sources/Capabilities/ \
        SliceAIKit/Tests/OrchestrationTests/ \
        SliceAIKit/Tests/CapabilitiesTests/
git commit -m "feat(package): add Orchestration + Capabilities empty targets

Scaffold two new library targets for Phase 0 M2 implementation. Placeholder
Swift files and test targets keep swift build/test green while the real types
(ExecutionEngine, ContextCollector, PermissionBroker, MCPClient, etc.) land in
M2. No existing module dependencies change."
```

---

## Task 2: ContextKey + Requiredness

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ContextKey.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ContextKeyTests.swift`

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/ContextKeyTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ContextKeyTests: XCTestCase {

    func test_rawValue_preservesString() {
        let key = ContextKey(rawValue: "file.read.result")
        XCTAssertEqual(key.rawValue, "file.read.result")
    }

    func test_equality_byRawValue() {
        XCTAssertEqual(ContextKey(rawValue: "a"), ContextKey(rawValue: "a"))
        XCTAssertNotEqual(ContextKey(rawValue: "a"), ContextKey(rawValue: "b"))
    }

    func test_hashable_usableAsDictionaryKey() {
        var map: [ContextKey: Int] = [:]
        map[ContextKey(rawValue: "x")] = 1
        map[ContextKey(rawValue: "y")] = 2
        XCTAssertEqual(map[ContextKey(rawValue: "x")], 1)
        XCTAssertEqual(map.count, 2)
    }

    func test_codable_roundtrip() throws {
        let original = ContextKey(rawValue: "vocab")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContextKey.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_requiredness_allCases() {
        XCTAssertEqual(Requiredness.allCases.count, 2)
        XCTAssertTrue(Requiredness.allCases.contains(.required))
        XCTAssertTrue(Requiredness.allCases.contains(.optional))
    }

    func test_requiredness_codable() throws {
        let req = Requiredness.required
        let data = try JSONEncoder().encode(req)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"required\"")
    }
}
```

- [ ] **Step 2: 运行测试看失败**

Run: `cd SliceAIKit && swift test --filter ContextKeyTests`
Expected: FAIL with `cannot find 'ContextKey' in scope` / `cannot find 'Requiredness' in scope`

- [ ] **Step 3: 写最小实现**

Create `SliceAIKit/Sources/SliceCore/ContextKey.swift`:

```swift
import Foundation

/// 上下文键：在 Tool.contexts 声明处 + ContextBag 存取处共用的强类型标识
///
/// 使用 `RawRepresentable(String)` 而非 String 别名，是为了让"键"与普通字符串在类型层面区分——
/// API 调用者必须显式构造 `ContextKey(rawValue:)` 才能把它当键用，避免把业务字符串误当 key。
///
/// 命名约定（非语言强制）：使用点分路径，例：`selection`、`app.url`、`file.read.result`、`mcp.result`。
public struct ContextKey: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    /// 构造 ContextKey
    /// - Parameter rawValue: 键名字符串，调用方负责保证唯一性
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// ContextRequest 的失败容忍策略
///
/// - `.required`：采集失败 → `ExecutionEngine` 中止流程，返回 `.failed(.selection(...))`
/// - `.optional`：采集失败 → 记入 `ResolvedExecutionContext.failures`，执行继续，Prompt 可读不到这个 context
public enum Requiredness: String, Codable, Sendable, CaseIterable {
    case required
    case optional
}
```

- [ ] **Step 4: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter ContextKeyTests`
Expected: `Test Suite 'ContextKeyTests' passed`, 6/6 tests.

- [ ] **Step 5: SwiftLint 检查**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/ContextKey.swift --strict`
Expected: `Done linting! Found 0 violations, 0 serious in 1 file.`

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/ContextKey.swift \
        SliceAIKit/Tests/SliceCoreTests/ContextKeyTests.swift
git commit -m "feat(core): add ContextKey and Requiredness types

ContextKey is the strongly-typed identifier used by Tool.contexts declarations
and ContextBag lookups. Requiredness drives ExecutionEngine's failure handling
when ContextCollector fails to produce a given context value."
```

---

## Task 3: Permission + PermissionGrant + Provenance

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/Permission.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/PermissionTests.swift`

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/PermissionTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class PermissionTests: XCTestCase {

    // MARK: - Permission equality & hashable

    func test_permission_equality_byAssociatedValues() {
        XCTAssertEqual(Permission.fileRead(path: "~/Docs"), Permission.fileRead(path: "~/Docs"))
        XCTAssertNotEqual(Permission.fileRead(path: "~/Docs"), Permission.fileRead(path: "~/Desktop"))
        XCTAssertNotEqual(Permission.fileRead(path: "~/Docs"), Permission.fileWrite(path: "~/Docs"))
    }

    func test_permission_usableInSet() {
        let set: Set<Permission> = [
            .clipboard,
            .fileRead(path: "a"),
            .fileRead(path: "a"),   // 去重
            .fileRead(path: "b")
        ]
        XCTAssertEqual(set.count, 3)
    }

    // MARK: - Permission Codable

    func test_permission_codable_fileRead() throws {
        let original = Permission.fileRead(path: "~/Documents/**/*.md")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Permission.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_permission_codable_mcp_withAllTools() throws {
        let original = Permission.mcp(server: "postgres", tools: ["query", "schema"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Permission.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_permission_codable_mcp_nilTools() throws {
        // tools=nil 语义上 = 允许该 server 全部 tool，必须能 round-trip
        let original = Permission.mcp(server: "fs", tools: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Permission.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Provenance

    func test_provenance_firstParty_codable() throws {
        let original = Provenance.firstParty
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_provenance_selfManaged_preservesDate() throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Provenance.selfManaged(userAcknowledgedAt: t)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_provenance_unknown_preservesURL() throws {
        let url = URL(string: "https://example.com/pack.slicepack")
        let original = Provenance.unknown(importedFrom: url, importedAt: Date(timeIntervalSince1970: 1))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_provenance_communitySigned_preservesPublisher() throws {
        let original = Provenance.communitySigned(publisher: "anthropic-labs", signedAt: Date(timeIntervalSince1970: 2))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - PermissionGrant

    func test_permissionGrant_codable() throws {
        let grant = PermissionGrant(
            permission: .network(host: "api.openai.com"),
            grantedAt: Date(timeIntervalSince1970: 100),
            grantedBy: .userConsent,
            scope: .session
        )
        let data = try JSONEncoder().encode(grant)
        let decoded = try JSONDecoder().decode(PermissionGrant.self, from: data)
        XCTAssertEqual(grant, decoded)
    }

    func test_grantScope_allCases() {
        XCTAssertEqual(Set(GrantScope.allCases), [.oneTime, .session, .persistent])
    }

    func test_grantSource_allCases() {
        XCTAssertEqual(Set(GrantSource.allCases), [.userConsent, .toolInstall, .developer])
    }

    // MARK: - Golden JSON shape（锁定 canonical schema；模板 D，禁 Swift 合成的 `_0`）

    func test_permission_goldenJSON_fileRead_usesSingleKeyWithStringValue() throws {
        let data = try sortedJSONEncoder().encode(Permission.fileRead(path: "~/Docs"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, #"{"fileRead":"~\/Docs"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_permission_goldenJSON_clipboard_usesEmptyObjectMarker() throws {
        let data = try sortedJSONEncoder().encode(Permission.clipboard)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, #"{"clipboard":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_permission_goldenJSON_mcp_usesNestedStruct() throws {
        let data = try sortedJSONEncoder().encode(Permission.mcp(server: "postgres", tools: ["query"]))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"mcp":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""server":"postgres""#))
        XCTAssertTrue(json.contains(#""tools":["query"]"#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_provenance_goldenJSON_firstParty_isEmptyObjectMarker() throws {
        let data = try sortedJSONEncoder().encode(Provenance.firstParty)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, #"{"firstParty":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_provenance_goldenJSON_communitySigned_nestedStruct() throws {
        let signed = Provenance.communitySigned(publisher: "anthropic-labs", signedAt: Date(timeIntervalSince1970: 100))
        let data = try sortedJSONEncoder().encode(signed)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"communitySigned":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""publisher":"anthropic-labs""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    private func sortedJSONEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }
}
```

- [ ] **Step 2: 运行测试看失败**

Run: `cd SliceAIKit && swift test --filter PermissionTests`
Expected: FAIL with `cannot find 'Permission' in scope` 等。

- [ ] **Step 3: 写实现**

Create `SliceAIKit/Sources/SliceCore/Permission.swift`:

```swift
import Foundation

/// 细粒度权限，Tool 静态声明在 `tool.permissions`；`ExecutionEngine` 执行前做 `effectivePermissions ⊆ tool.permissions` 校验（D-24）
///
/// 设计要点：
/// - 每个 case 的关联值必须能让 `PermissionBroker` 判定"允许 / 拒绝"不需要额外上下文
/// - 路径字段使用用户目录相对（`~/Documents/**/*.md`）或绝对路径；比较前由 `PathSandbox` 规范化
/// - 同一 case 不同关联值视为不同权限（`.fileRead("a") != .fileRead("b")`）
public enum Permission: Codable, Sendable, Hashable {
    /// 访问特定域名（HTTPS）；host 为精确匹配
    case network(host: String)
    /// 读文件；path 支持通配（`~/Documents/**/*.md`）
    case fileRead(path: String)
    /// 写文件；同上
    case fileWrite(path: String)
    /// 剪贴板读 / 写（单一权限，不区分方向——macOS pasteboard 模型如此）
    case clipboard
    /// 剪贴板历史访问（Phase 1+ 才用）
    case clipboardHistory
    /// 执行 shell 命令；commands 为允许的命令串白名单（精确匹配）
    case shellExec(commands: [String])
    /// 调用 MCP server；tools=nil 表示允许该 server 全部 tool，否则为白名单
    case mcp(server: String, tools: [String]?)
    /// 屏幕录制 / 抓图
    case screen
    /// 系统音频输出（TTS / 朗读）
    case systemAudio
    /// Tool 级 memory 访问；scope 一般是 tool id
    case memoryAccess(scope: String)
    /// 触发其他 App 的 AppIntent / Shortcut
    case appIntents(bundleId: String)

    // MARK: - 手写 Codable（见 plan 开头 Canonical JSON Schema 章节：模板 B + C 混合）
    // 产出形式：
    //   {"network":"api.openai.com"}   (模板 C, single String)
    //   {"fileRead":"~/Docs/**/*.md"}
    //   {"clipboard":{}}                (empty marker)
    //   {"mcp":{"server":"postgres","tools":["query"]}}  (模板 B, nested struct)

    private enum CodingKeys: String, CodingKey {
        case network, fileRead, fileWrite, clipboard, clipboardHistory, shellExec,
             mcp, screen, systemAudio, memoryAccess, appIntents
    }

    /// 空对象哨兵，用于无 associated value 的 case
    private struct EmptyMarker: Codable, Equatable {}

    /// 多 associated value 的 mcp case 的 Codable 中转
    private struct MCPAccessRepr: Codable, Equatable {
        let server: String
        let tools: [String]?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(String.self, forKey: .network) { self = .network(host: v); return }
        if let v = try c.decodeIfPresent(String.self, forKey: .fileRead) { self = .fileRead(path: v); return }
        if let v = try c.decodeIfPresent(String.self, forKey: .fileWrite) { self = .fileWrite(path: v); return }
        if c.contains(.clipboard) {
            _ = try c.decode(EmptyMarker.self, forKey: .clipboard); self = .clipboard; return
        }
        if c.contains(.clipboardHistory) {
            _ = try c.decode(EmptyMarker.self, forKey: .clipboardHistory); self = .clipboardHistory; return
        }
        if let v = try c.decodeIfPresent([String].self, forKey: .shellExec) { self = .shellExec(commands: v); return }
        if let v = try c.decodeIfPresent(MCPAccessRepr.self, forKey: .mcp) {
            self = .mcp(server: v.server, tools: v.tools); return
        }
        if c.contains(.screen) {
            _ = try c.decode(EmptyMarker.self, forKey: .screen); self = .screen; return
        }
        if c.contains(.systemAudio) {
            _ = try c.decode(EmptyMarker.self, forKey: .systemAudio); self = .systemAudio; return
        }
        if let v = try c.decodeIfPresent(String.self, forKey: .memoryAccess) { self = .memoryAccess(scope: v); return }
        if let v = try c.decodeIfPresent(String.self, forKey: .appIntents) { self = .appIntents(bundleId: v); return }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.network, in: c,
            debugDescription: "Permission requires exactly one known case key"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .network(let host):           try c.encode(host, forKey: .network)
        case .fileRead(let path):          try c.encode(path, forKey: .fileRead)
        case .fileWrite(let path):         try c.encode(path, forKey: .fileWrite)
        case .clipboard:                   try c.encode(EmptyMarker(), forKey: .clipboard)
        case .clipboardHistory:            try c.encode(EmptyMarker(), forKey: .clipboardHistory)
        case .shellExec(let commands):     try c.encode(commands, forKey: .shellExec)
        case .mcp(let server, let tools):  try c.encode(MCPAccessRepr(server: server, tools: tools), forKey: .mcp)
        case .screen:                      try c.encode(EmptyMarker(), forKey: .screen)
        case .systemAudio:                 try c.encode(EmptyMarker(), forKey: .systemAudio)
        case .memoryAccess(let scope):     try c.encode(scope, forKey: .memoryAccess)
        case .appIntents(let bundleId):    try c.encode(bundleId, forKey: .appIntents)
        }
    }
}

/// 权限授予记录
public struct PermissionGrant: Codable, Sendable, Equatable {
    /// 被授予的权限
    public let permission: Permission
    /// 授予时间
    public let grantedAt: Date
    /// 授予来源（用户同意 / 安装时确认 / 开发者）
    public let grantedBy: GrantSource
    /// 授权时长
    public let scope: GrantScope

    /// 构造权限授予记录
    /// - Parameters:
    ///   - permission: 被授予的权限
    ///   - grantedAt: 授予时间戳
    ///   - grantedBy: 授予来源
    ///   - scope: 授权时长
    public init(permission: Permission, grantedAt: Date, grantedBy: GrantSource, scope: GrantScope) {
        self.permission = permission
        self.grantedAt = grantedAt
        self.grantedBy = grantedBy
        self.scope = scope
    }
}

/// 授予来源
public enum GrantSource: String, Codable, Sendable, CaseIterable {
    /// 运行时弹窗由用户确认
    case userConsent
    /// Tool 安装流程中批量确认
    case toolInstall
    /// 开发 / 测试环境直接放行（仅 DEBUG 构建）
    case developer
}

/// 授权时长
public enum GrantScope: String, Codable, Sendable, CaseIterable {
    /// 本次调用后失效
    case oneTime
    /// App 进程生命周期内有效
    case session
    /// 写入 config，跨启动保留
    case persistent
}

/// 信任来源分级（D-23 / D-25）
///
/// 由安装 / 导入流程写入 `Tool` / `Skill` / `MCPDescriptor` 等顶层资源的 `provenance` 字段；
/// 运行时只读。`PermissionBroker` 决策规则：**能力分级决定最低下限（§3.9.2），Provenance 只能
/// 在下限之上调节 UX 文案，不能减少确认次数**（D-25）。
///
/// canonical 定义仅在本文件；spec §3.9.1 / §3.9.4.2 只做引用。
public enum Provenance: Codable, Sendable, Equatable {
    /// 随 App 打包的 Starter Pack / 内置工具
    case firstParty
    /// 从官方 Marketplace 安装且签名校验通过（Phase 4+）
    case communitySigned(publisher: String, signedAt: Date)
    /// 用户本地 clone / 自己写的资源，安装时已显式承认"我已审读来源"
    /// Phase 1 仅 `MCPDescriptor` 使用此态（见 spec §3.9.4.2）
    case selfManaged(userAcknowledgedAt: Date)
    /// 手动导入文件 / URL clone / sideload；`MCPDescriptor` 不允许此态——Phase 1 安装流程直接拒绝
    case unknown(importedFrom: URL?, importedAt: Date)

    // MARK: - 手写 Codable（模板 A + B；产出 `{"firstParty":{}}` / `{"communitySigned":{"publisher":...,"signedAt":...}}` 等）

    private enum CodingKeys: String, CodingKey {
        case firstParty, communitySigned, selfManaged, unknown
    }

    private struct EmptyMarker: Codable, Equatable {}
    private struct CommunitySignedRepr: Codable, Equatable { let publisher: String; let signedAt: Date }
    private struct SelfManagedRepr: Codable, Equatable { let userAcknowledgedAt: Date }
    private struct UnknownRepr: Codable, Equatable { let importedFrom: URL?; let importedAt: Date }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.firstParty) {
            _ = try c.decode(EmptyMarker.self, forKey: .firstParty); self = .firstParty; return
        }
        if let r = try c.decodeIfPresent(CommunitySignedRepr.self, forKey: .communitySigned) {
            self = .communitySigned(publisher: r.publisher, signedAt: r.signedAt); return
        }
        if let r = try c.decodeIfPresent(SelfManagedRepr.self, forKey: .selfManaged) {
            self = .selfManaged(userAcknowledgedAt: r.userAcknowledgedAt); return
        }
        if let r = try c.decodeIfPresent(UnknownRepr.self, forKey: .unknown) {
            self = .unknown(importedFrom: r.importedFrom, importedAt: r.importedAt); return
        }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.firstParty, in: c,
            debugDescription: "Provenance requires one of: firstParty, communitySigned, selfManaged, unknown"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .firstParty:
            try c.encode(EmptyMarker(), forKey: .firstParty)
        case .communitySigned(let publisher, let signedAt):
            try c.encode(CommunitySignedRepr(publisher: publisher, signedAt: signedAt), forKey: .communitySigned)
        case .selfManaged(let at):
            try c.encode(SelfManagedRepr(userAcknowledgedAt: at), forKey: .selfManaged)
        case .unknown(let from, let at):
            try c.encode(UnknownRepr(importedFrom: from, importedAt: at), forKey: .unknown)
        }
    }
}
```

- [ ] **Step 4: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter PermissionTests`
Expected: 12/12 passed.

- [ ] **Step 5: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/Permission.swift --strict`
Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/Permission.swift \
        SliceAIKit/Tests/SliceCoreTests/PermissionTests.swift
git commit -m "feat(core): add Permission, PermissionGrant, Provenance types

Implements spec §3.3.5 canonical Permission model. Provenance carries the four
trust levels (firstParty / communitySigned / selfManaged / unknown) used by
PermissionBroker at runtime to adjust gate UX without weakening the capability
lower bound (D-22, D-25)."
```

---

## Task 4: 新增干净 SelectionSnapshot（SelectionPayload 保留不动）

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/SelectionContentType.swift`
- Create: `SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift`（**全新文件**，与 `SelectionPayload.swift` 完全独立；不重命名、不共享类型、不加 typealias）
- Keep: `SliceAIKit/Sources/SliceCore/SelectionPayload.swift`（**零改动**）
- Create: `SliceAIKit/Tests/SliceCoreTests/SelectionSnapshotTests.swift`
- Keep: `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift`（**零改动**；v1 `SelectionPayload.swift` 未改动，现有测试继续绿）

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/SelectionSnapshotTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class SelectionSnapshotTests: XCTestCase {

    func test_init_preservesAllFields() {
        let snap = SelectionSnapshot(
            text: "hello",
            source: .accessibility,
            length: 5,
            language: "en",
            contentType: .prose
        )
        XCTAssertEqual(snap.text, "hello")
        XCTAssertEqual(snap.source, .accessibility)
        XCTAssertEqual(snap.length, 5)
        XCTAssertEqual(snap.language, "en")
        XCTAssertEqual(snap.contentType, .prose)
    }

    func test_init_allowsNilOptionals() {
        let snap = SelectionSnapshot(
            text: "x",
            source: .clipboardFallback,
            length: 1,
            language: nil,
            contentType: nil
        )
        XCTAssertNil(snap.language)
        XCTAssertNil(snap.contentType)
    }

    func test_codable_roundtrip_withAllOptionals() throws {
        let snap = SelectionSnapshot(
            text: "let x = 1",
            source: .accessibility,
            length: 9,
            language: nil,
            contentType: .code
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(SelectionSnapshot.self, from: data)
        XCTAssertEqual(snap, decoded)
    }

    func test_selectionContentType_allCases_stable() {
        XCTAssertEqual(Set(SelectionContentType.allCases), [
            .prose, .code, .url, .email, .json, .commitHash, .date, .other
        ])
    }

    func test_selectionOrigin_rawValues() {
        XCTAssertEqual(SelectionOrigin.accessibility.rawValue, "accessibility")
        XCTAssertEqual(SelectionOrigin.clipboardFallback.rawValue, "clipboardFallback")
    }

    // 显式断言：SelectionSnapshot 与 SelectionPayload 是 **两个不同的类型**
    // （M1 不做 typealias 桥接；SelectionPayload 原封保留）
    func test_selectionSnapshot_isDistinctFromSelectionPayload() {
        // 两者不应互相赋值；若编译成功说明 typealias 误引入
        // 这里只做运行时类型对比，避免编译期断言
        let snap = SelectionSnapshot(text: "x", source: .accessibility, length: 1, language: nil, contentType: nil)
        XCTAssertEqual(String(describing: type(of: snap)), "SelectionSnapshot")
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter SelectionSnapshotTests`
Expected: FAIL (SelectionSnapshot 不存在；SelectionPayload 是 struct 不是 typealias)。

- [ ] **Step 3: 新建 SelectionContentType.swift**

Create `SliceAIKit/Sources/SliceCore/SelectionContentType.swift`:

```swift
import Foundation

/// 选中文字的内容类型启发式识别结果
///
/// Phase 0 M1 只定义枚举；真正的识别逻辑由 `SelectionCapture` 模块在 Phase 1+ 填充
/// （基于简单 heuristic：正则识别 URL / email / hash / 日期；代码围栏识别；兜底 .prose / .other）。
///
/// 工具可以通过 `ToolMatcher.contentTypes` 声明 "只对某些内容类型显示"，
/// 也可以在 Prompt 模板里读 `{{selection.contentType}}` 做条件分支。
public enum SelectionContentType: String, Codable, Sendable, CaseIterable {
    case prose
    case code
    case url
    case email
    case json
    case commitHash
    case date
    case other
}

/// 选中文字的来源渠道；从旧 `SelectionPayload.Source` 提升到独立类型便于复用
///
/// **命名说明**：命名有意避开 `SelectionCapture` 模块的既有 `public protocol SelectionSource`
/// （见 `SelectionCapture/SelectionSource.swift`，语义是"读取器接口"，被 AXSelectionSource /
/// ClipboardSelectionSource 实现）。两者名字同但语义正交；为不触动 `SelectionCapture/` 同时
/// 让测试链（`SelectionCaptureTests @testable import SliceCore` + `SelectionCapture` 同时存在
/// 时 Swift 解析会混淆）保持绿色，v2 enum 命名为 `SelectionOrigin`。
public enum SelectionOrigin: String, Codable, Sendable, CaseIterable {
    /// 通过 AX API 直接读取
    case accessibility
    /// 通过模拟 Cmd+C + 剪贴板备份恢复获取
    case clipboardFallback
    /// ⌥Space 命令面板中用户直接打字输入（无选区）
    case inputBox
}
```

- [ ] **Step 4: 新建干净 SelectionSnapshot.swift（不动 SelectionPayload.swift）**

> **评审修正（Codex 第四轮 P1-1）**：初版方案为"重命名 + v1 兼容 init + v1 Codable + v1 字段访问器 + typealias"，会让 `appBundleID` / `url` / `screenPoint` / `timestamp` 重新污染 v2 canonical 模型。收敛为**完全分离**：
> - 新建干净 `SelectionSnapshot.swift`，**只含** `text / source / length / language / contentType` 五个字段；无 v1 字段、无 v1 init、无 typealias、v2 Codable 不识别任何 v1 key。
> - 现有 `SliceAIKit/Sources/SliceCore/SelectionPayload.swift` **原封不动**——v1 触发链（SelectionCapture / Windowing / ToolExecutor）继续消费 `SelectionPayload`。
> - M3 `TriggerRouter` 新增一步 `SelectionPayload → ExecutionSeed` 一次性映射（不是本 plan 范围）。

**不执行** `rm SliceAIKit/Sources/SliceCore/SelectionPayload.swift`——该文件保持不变。

Create `SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift`:

```swift
import Foundation

/// 选中事件的文字内容快照；`ExecutionSeed.selection` 字段的类型
///
/// **干净 v2 类型**：只含 `text / source / length / language / contentType` 五字段。
/// 与 v1 `SelectionPayload` 是**两个独立类型**（不提供 typealias / v1 init / v1 字段 / v1 Codable key）。
/// v1 `SelectionPayload` 仍在 `SelectionPayload.swift` 原封保留，服务现有 SelectionCapture /
/// Windowing / ToolExecutor 链路；M3 的 `TriggerRouter` 在触发层做一次性 `SelectionPayload → ExecutionSeed` 映射。
///
/// 相对 v1 新增的三个字段为下游 D-24 / §3.9.5 / §3.3.7 留结构位：
/// - `length`：显式长度，让 AuditLog 能写 sha256+len 而不读原文
/// - `language`：BCP-47 语言代码（"en" / "zh-CN"）；M1 填 nil，Phase 1+ 由 SelectionCapture 填充
/// - `contentType`：内容类型启发式；同上
///
/// v1 `appBundleID` / `appName` / `url` / `screenPoint` / `timestamp` 字段**不在本类型里**——
/// 它们在 `ExecutionSeed.frontApp` / `ExecutionSeed.screenAnchor` / `ExecutionSeed.timestamp`。
public struct SelectionSnapshot: Sendable, Equatable, Codable {
    /// 选中文字
    public let text: String
    /// 来源（AX / clipboard fallback / 命令面板输入框）
    public let source: SelectionOrigin
    /// 字符长度（`text.count`，显式字段便于日志不写原文）
    public let length: Int
    /// BCP-47 语言代码；Phase 0 M1 可为 nil，Phase 1+ 填充
    public let language: String?
    /// 内容类型启发式；Phase 0 M1 可为 nil
    public let contentType: SelectionContentType?

    /// 构造选中文字快照
    /// - Parameters:
    ///   - text: 选中文字内容
    ///   - source: 来源渠道
    ///   - length: 字符数；调用方负责计算（通常 `text.count`）
    ///   - language: BCP-47 语言代码，未知传 nil
    ///   - contentType: 内容类型，未识别传 nil
    public init(text: String, source: SelectionOrigin, length: Int, language: String?, contentType: SelectionContentType?) {
        self.text = text
        self.source = source
        self.length = length
        self.language = language
        self.contentType = contentType
    }
}

// ❌ 不加 typealias SelectionPayload = SelectionSnapshot —— 两者是独立类型
// ❌ 不加 v1 字段 / v1 init / v1 Codable key / v1 compat accessor
```

**收敛原因**（评审 P1-1）：以下任何一项都会让 canonical model 被污染，本轮评审明确拒绝：
- `typealias SelectionPayload = SelectionSnapshot` → 两种语义混入同一类型
- `init(text:appBundleID:appName:url:screenPoint:source:timestamp:)` → v2 类型构造器依赖 v1 概念
- `_legacyAppBundleID` / `_legacyURL` / `_legacyScreenPoint` / `_legacyTimestamp` stored properties → v1 字段重新进入 v2 内存布局
- `CodingKeys.appBundleID / .url / .screenPoint / .timestamp` → v1 字段可能被写回 v2 JSON
- `var appBundleID: String { ... }` 等 computed accessor → 让消费方以为 v2 类型仍能读 v1 字段

- [ ] **Step 5: SelectionPayloadTests.swift 保持不动**

现有 `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift` 继续覆盖 `SelectionPayload`（它不变）；不需要改动，其中对 `appBundleID` / `url` / `screenPoint` / `timestamp` 字段的断言在 `SelectionPayload.swift` 原封保留的前提下继续绿。

**确认**：`SelectionPayloadTests.swift` 不动；`SelectionPayload.swift` 不动。

- [ ] **Step 6: 编译验证——外部模块不应出现任何编译错误**

Run: `cd SliceAIKit && swift build`
Expected: **Build complete!** —— 因为 `SelectionPayload.swift` 原封未动，所有外部模块（SelectionCapture / Windowing / SettingsUI / SliceAIApp）的现有引用点继续工作；`SelectionSnapshot` 是全新类型，此时只被 `SelectionSnapshotTests` 引用。

若 build 失败：
- 检查是否误删了 `SelectionPayload.swift`，把它恢复。
- 检查是否不小心在 SelectionSnapshot.swift 加了 `typealias SelectionPayload = SelectionSnapshot` —— **不能有**。
- **不要**靠给 `SelectionSnapshot` 加兼容字段 / init / Codable key / accessor 解决。

以下是评审中拒绝的反模式，**不要**在 SelectionSnapshot.swift 追加：

```swift
// ❌ 反模式 1：extension 加 v1 字段访问器（extension 无法加 stored property，
//    会被迫把 stored property 放回主 struct，污染 canonical model）
public extension SelectionSnapshot {
    var appBundleID: String { ... }
    var url: URL? { ... }
    // ...
}

// ❌ 反模式 2：主 struct 内加 _legacyXxx stored property + 双 init + Codable key
public struct SelectionSnapshot {
    internal let _legacyAppBundleID: String
    internal let _legacyURL: URL?
    // ...（均拒绝）
}

// ❌ 反模式 3：typealias 桥
public typealias SelectionPayload = SelectionSnapshot
```

**正解**：`SelectionPayload` 保持独立文件独立类型，`SelectionSnapshot` 保持 Step 4 的干净五字段结构。外部消费 `SelectionPayload` 的模块不会看到 `SelectionSnapshot`，反之亦然——两者在 M3 之前没有耦合点。

- [ ] **Step 7: 全量 SliceCoreTests**

Run: `cd SliceAIKit && swift test --filter SliceCoreTests`
Expected: 全绿——`SelectionPayloadTests` 和 `SelectionSnapshotTests` 并行通过；两者互不干扰。

- [ ] **Step 8: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift SliceAIKit/Sources/SliceCore/SelectionContentType.swift --strict`
Expected: 0 violations.

- [ ] **Step 9: Commit**

```bash
# 只 add 新建的干净类型；不动 SelectionPayload.swift / SelectionPayloadTests.swift
git add SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift \
        SliceAIKit/Sources/SliceCore/SelectionContentType.swift \
        SliceAIKit/Tests/SliceCoreTests/SelectionSnapshotTests.swift
git commit -m "feat(core): add SelectionSnapshot as clean v2 type

SelectionSnapshot is the minimal text-only snapshot ExecutionSeed.selection
will carry. v1 SelectionPayload is left untouched—SelectionCapture,
Windowing, ToolExecutor continue to consume it. M3's TriggerRouter will
perform a one-time SelectionPayload -> ExecutionSeed mapping at the trigger
boundary. No typealias, no v1 fields, no v1 codable keys in the new type."
```

---

## Task 5: AppSnapshot + TriggerSource

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/AppSnapshot.swift`
- Create: `SliceAIKit/Sources/SliceCore/TriggerSource.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/AppSnapshotTests.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/TriggerSourceTests.swift`

- [ ] **Step 1: 写 AppSnapshot 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/AppSnapshotTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class AppSnapshotTests: XCTestCase {

    func test_init_preservesAllFields() {
        let url = URL(string: "https://example.com")
        let snap = AppSnapshot(bundleId: "com.apple.Safari", name: "Safari", url: url, windowTitle: "Example")
        XCTAssertEqual(snap.bundleId, "com.apple.Safari")
        XCTAssertEqual(snap.name, "Safari")
        XCTAssertEqual(snap.url, url)
        XCTAssertEqual(snap.windowTitle, "Example")
    }

    func test_init_allowsNilUrlAndTitle() {
        let snap = AppSnapshot(bundleId: "com.apple.Notes", name: "Notes", url: nil, windowTitle: nil)
        XCTAssertNil(snap.url)
        XCTAssertNil(snap.windowTitle)
    }

    func test_codable_roundtrip() throws {
        let snap = AppSnapshot(
            bundleId: "com.microsoft.VSCode",
            name: "VSCode",
            url: nil,
            windowTitle: "main.swift - SliceAI"
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(AppSnapshot.self, from: data)
        XCTAssertEqual(snap, decoded)
    }
}
```

- [ ] **Step 2: 写 TriggerSource 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/TriggerSourceTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class TriggerSourceTests: XCTestCase {

    func test_allCases_stable() {
        XCTAssertEqual(Set(TriggerSource.allCases), [
            .floatingToolbar, .commandPalette, .hotkey, .shortcutsApp, .urlScheme, .servicesMenu
        ])
    }

    func test_rawValues() {
        XCTAssertEqual(TriggerSource.floatingToolbar.rawValue, "floatingToolbar")
        XCTAssertEqual(TriggerSource.commandPalette.rawValue, "commandPalette")
    }

    func test_codable_roundtrip() throws {
        for ts in TriggerSource.allCases {
            let data = try JSONEncoder().encode(ts)
            let decoded = try JSONDecoder().decode(TriggerSource.self, from: data)
            XCTAssertEqual(ts, decoded)
        }
    }
}
```

- [ ] **Step 3: 运行测试看失败**

Run: `cd SliceAIKit && swift test --filter AppSnapshotTests`
Run: `cd SliceAIKit && swift test --filter TriggerSourceTests`
Expected: FAIL `cannot find 'AppSnapshot' / 'TriggerSource' in scope`.

- [ ] **Step 4: 实现 AppSnapshot**

Create `SliceAIKit/Sources/SliceCore/AppSnapshot.swift`:

```swift
import Foundation

/// 触发时前台 app 的元数据快照；`ExecutionSeed.frontApp` 字段的类型
///
/// 含可从 AX 直接拿到的三要素（bundleId / name / windowTitle）和浏览器专属的 url。
/// windowTitle / url 可能读取失败（权限 / app 不暴露），允许 nil。
public struct AppSnapshot: Sendable, Equatable, Codable {
    /// 前台 app 的 bundle identifier（如 `com.apple.Safari`）
    public let bundleId: String
    /// 人类可读名称（如 `Safari`）
    public let name: String
    /// 浏览器类 app 的当前页面 URL；非浏览器或未读到时为 nil
    public let url: URL?
    /// 前台窗口标题；AX 读取失败时为 nil
    public let windowTitle: String?

    /// 构造前台 app 快照
    /// - Parameters:
    ///   - bundleId: Bundle identifier
    ///   - name: 人类可读名称
    ///   - url: 当前浏览器 URL，非浏览器传 nil
    ///   - windowTitle: 前台窗口标题，未读到传 nil
    public init(bundleId: String, name: String, url: URL?, windowTitle: String?) {
        self.bundleId = bundleId
        self.name = name
        self.url = url
        self.windowTitle = windowTitle
    }
}
```

- [ ] **Step 5: 实现 TriggerSource**

Create `SliceAIKit/Sources/SliceCore/TriggerSource.swift`:

```swift
import Foundation

/// 本次执行的触发通路；`ExecutionSeed.triggerSource` 字段的类型
///
/// 审计日志、Prompt 模板（`{{triggerSource}}`）、UI 可读此字段做差异化行为。
public enum TriggerSource: String, Sendable, Codable, CaseIterable {
    /// 划词后鼠标弹出的浮条
    case floatingToolbar
    /// ⌥Space 命令面板
    case commandPalette
    /// Per-tool hotkey 直接触发（Phase 1+）
    case hotkey
    /// 从 Shortcuts.app 的 AppIntent 调用（Phase 4+）
    case shortcutsApp
    /// URL Scheme `sliceai://run/<tool>`（Phase 4+）
    case urlScheme
    /// macOS Services 菜单（Phase 4+）
    case servicesMenu
}
```

- [ ] **Step 6: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter AppSnapshotTests --filter TriggerSourceTests`
Expected: 6/6 passed.

- [ ] **Step 7: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/AppSnapshot.swift SliceAIKit/Sources/SliceCore/TriggerSource.swift --strict`
Expected: 0 violations.

- [ ] **Step 8: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/AppSnapshot.swift \
        SliceAIKit/Sources/SliceCore/TriggerSource.swift \
        SliceAIKit/Tests/SliceCoreTests/AppSnapshotTests.swift \
        SliceAIKit/Tests/SliceCoreTests/TriggerSourceTests.swift
git commit -m "feat(core): add AppSnapshot and TriggerSource

AppSnapshot bundles the front-app metadata (bundleId / name / url / windowTitle)
that ExecutionSeed.frontApp will carry. TriggerSource enumerates the six entry
points covering current and future triggers (floating toolbar, command palette,
per-tool hotkey, Shortcuts, URL scheme, Services menu)."
```

---

## Task 6: ExecutionSeed

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ExecutionSeedTests.swift`

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/ExecutionSeedTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ExecutionSeedTests: XCTestCase {

    private func makeSeed(dryRun: Bool = false) -> ExecutionSeed {
        ExecutionSeed(
            invocationId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            selection: SelectionSnapshot(text: "hi", source: .accessibility, length: 2, language: "en", contentType: .prose),
            frontApp: AppSnapshot(bundleId: "com.apple.Safari", name: "Safari", url: nil, windowTitle: nil),
            screenAnchor: .zero,
            timestamp: Date(timeIntervalSince1970: 100),
            triggerSource: .floatingToolbar,
            isDryRun: dryRun
        )
    }

    func test_init_preservesAllFields() {
        let seed = makeSeed()
        XCTAssertEqual(seed.invocationId.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(seed.selection.text, "hi")
        XCTAssertEqual(seed.frontApp.bundleId, "com.apple.Safari")
        XCTAssertEqual(seed.triggerSource, .floatingToolbar)
        XCTAssertFalse(seed.isDryRun)
    }

    func test_init_dryRunFlagCarriedThrough() {
        let seed = makeSeed(dryRun: true)
        XCTAssertTrue(seed.isDryRun)
    }

    func test_equality_sameFields_isEqual() {
        XCTAssertEqual(makeSeed(), makeSeed())
    }

    func test_equality_differentInvocationId_isNotEqual() {
        let a = makeSeed()
        let b = ExecutionSeed(
            invocationId: UUID(),       // 随机
            selection: a.selection, frontApp: a.frontApp,
            screenAnchor: a.screenAnchor, timestamp: a.timestamp,
            triggerSource: a.triggerSource, isDryRun: a.isDryRun
        )
        XCTAssertNotEqual(a, b)
    }

    func test_codable_roundtrip() throws {
        let seed = makeSeed(dryRun: true)
        let data = try JSONEncoder().encode(seed)
        let decoded = try JSONDecoder().decode(ExecutionSeed.self, from: data)
        XCTAssertEqual(seed, decoded)
    }

    // INV-6：seed 构造后不可变；struct + let 天然保证，本测试显式确认编译期约束
    func test_immutability_fieldsAreLet() {
        let mirror = Mirror(reflecting: makeSeed())
        // displayStyle == .struct 已保证不可变；此处仅为文档化意图
        XCTAssertEqual(mirror.displayStyle, .struct)
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter ExecutionSeedTests`
Expected: FAIL `cannot find 'ExecutionSeed' in scope`.

- [ ] **Step 3: 实现 ExecutionSeed**

Create `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift`:

```swift
import CoreGraphics
import Foundation

/// 触发层（FloatingToolbar / CommandPalette / Hotkey / Shortcuts / URL Scheme / Services）
/// 产出的不可变执行种子；`ExecutionEngine.execute(tool:seed:)` 的入参
///
/// 含所有"一发即知"的信息；但**尚未**采集 Tool 声明的 `ContextRequest`。
/// 第二阶段由 `ContextCollector.resolve(seed:requests:)` 消费此 seed、产出
/// `ResolvedExecutionContext`——两者都不可 mutation（INV-6 / D-16）。
///
/// 任何需要新增字段的场景：
/// - 若信息在触发瞬间已知 → 加到 `ExecutionSeed`
/// - 若需要 I/O 或 MCP 采集才能获得 → 做成 `ContextProvider`，由 Tool 显式声明
public struct ExecutionSeed: Sendable, Equatable, Codable {
    /// 贯穿日志的追踪 id；同一次划词 / 快捷键触发只生成一次
    public let invocationId: UUID
    /// 选中文字快照
    public let selection: SelectionSnapshot
    /// 前台 app 快照
    public let frontApp: AppSnapshot
    /// 屏幕锚点（光标位置），浮条 / 结果面板定位使用
    public let screenAnchor: CGPoint
    /// 触发时间戳
    public let timestamp: Date
    /// 触发通路
    public let triggerSource: TriggerSource
    /// 预览模式；true 时 OutputDispatcher 跳过所有副作用、只展示流
    public let isDryRun: Bool

    /// 构造 ExecutionSeed
    /// - Parameters:
    ///   - invocationId: 本次调用的唯一 id
    ///   - selection: 选中文字快照
    ///   - frontApp: 前台 app 快照
    ///   - screenAnchor: 屏幕锚点（像素坐标，左下为原点）
    ///   - timestamp: 触发时间戳
    ///   - triggerSource: 触发通路
    ///   - isDryRun: 是否预览模式
    public init(
        invocationId: UUID,
        selection: SelectionSnapshot,
        frontApp: AppSnapshot,
        screenAnchor: CGPoint,
        timestamp: Date,
        triggerSource: TriggerSource,
        isDryRun: Bool
    ) {
        self.invocationId = invocationId
        self.selection = selection
        self.frontApp = frontApp
        self.screenAnchor = screenAnchor
        self.timestamp = timestamp
        self.triggerSource = triggerSource
        self.isDryRun = isDryRun
    }
}
```

- [ ] **Step 4: 运行通过**

Run: `cd SliceAIKit && swift test --filter ExecutionSeedTests`
Expected: 6/6 passed.

- [ ] **Step 5: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/ExecutionSeed.swift --strict`
Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/ExecutionSeed.swift \
        SliceAIKit/Tests/SliceCoreTests/ExecutionSeedTests.swift
git commit -m "feat(core): add ExecutionSeed (stage-1 execution context)

Immutable trigger-time snapshot that ExecutionEngine.execute consumes.
Carries invocationId, selection, frontApp, screenAnchor, timestamp,
triggerSource, and the dryRun flag. ContextCollector will later produce a
ResolvedExecutionContext from a seed plus tool.contexts requests (Task 9)."
```

---

## Task 7: ContextBag + ContextValue

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ContextBag.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ContextBagTests.swift`

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/ContextBagTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ContextBagTests: XCTestCase {

    func test_empty_bagHasNoValues() {
        let bag = ContextBag(values: [:])
        XCTAssertNil(bag[ContextKey(rawValue: "anything")])
    }

    func test_subscript_returnsInsertedValue() {
        let key = ContextKey(rawValue: "vocab")
        let bag = ContextBag(values: [key: .text("hello")])
        if case .text(let s) = bag[key] {
            XCTAssertEqual(s, "hello")
        } else {
            XCTFail("expected .text")
        }
    }

    func test_contextValue_textEquality() {
        XCTAssertEqual(ContextValue.text("a"), ContextValue.text("a"))
        XCTAssertNotEqual(ContextValue.text("a"), ContextValue.text("b"))
    }

    func test_contextValue_jsonEquality() {
        let d1 = try! JSONSerialization.data(withJSONObject: ["x": 1])
        let d2 = try! JSONSerialization.data(withJSONObject: ["x": 1])
        XCTAssertEqual(ContextValue.json(d1), ContextValue.json(d2))
    }

    func test_contextValue_fileEquality_byURLAndMime() {
        let u = URL(fileURLWithPath: "/tmp/a.md")
        XCTAssertEqual(ContextValue.file(u, mimeType: "text/markdown"), ContextValue.file(u, mimeType: "text/markdown"))
        XCTAssertNotEqual(ContextValue.file(u, mimeType: "text/markdown"), ContextValue.file(u, mimeType: "text/plain"))
    }

    func test_contextValue_errorCase_carriesSliceError() {
        let err = SliceError.configuration(.fileNotFound)
        let val = ContextValue.error(err)
        if case .error(let e) = val {
            XCTAssertEqual(e.userMessage, err.userMessage)
        } else {
            XCTFail("expected .error")
        }
    }

    func test_containsKey_returnsFalseForMissing() {
        let bag = ContextBag(values: [ContextKey(rawValue: "a"): .text("x")])
        XCTAssertNotNil(bag[ContextKey(rawValue: "a")])
        XCTAssertNil(bag[ContextKey(rawValue: "missing")])
    }
}
```

**设计决定（Codex 第五轮 P2-3）**：`ContextBag` / `ContextValue` **不实现 Codable**。理由：`ContextValue.error(SliceError)` 需要 `SliceError: Codable`，但当前 `SliceError` 只实现 `Equatable`；为了避免给 SliceError 追加 Codable 这种大范围改动，`ContextBag` 只走 Sendable + Equatable。ResolvedExecutionContext 本身也不需要 Codable（它是运行时构造的、不写 JSON）。

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter ContextBagTests`
Expected: FAIL `cannot find 'ContextBag' / 'ContextValue' in scope`.

- [ ] **Step 3: 实现 ContextBag + ContextValue（非 Codable）**

Create `SliceAIKit/Sources/SliceCore/ContextBag.swift`:

```swift
import Foundation

/// ContextCollector 采集的键值对容器；`ResolvedExecutionContext.contexts` 的类型
///
/// 仅 Sendable + Equatable，**不实现 Codable**（`ContextValue.error(SliceError)` 需要 SliceError 实现 Codable，
/// 为避免大面积侵入 SliceError，ContextBag 不参与 JSON 序列化；它是运行时构造产物）。
/// 不暴露可变 API——ContextCollector 一次性构造、使用者只读（INV-6）。
public struct ContextBag: Sendable, Equatable {
    /// 底层键值映射；保持 public 便于调试，但生产代码应优先用 subscript
    public let values: [ContextKey: ContextValue]

    /// 构造 ContextBag
    /// - Parameter values: 键值字典
    public init(values: [ContextKey: ContextValue]) {
        self.values = values
    }

    /// 只读下标；命中返回值，未命中返回 nil
    public subscript(key: ContextKey) -> ContextValue? { values[key] }
}

/// ContextProvider 产出的值类型
///
/// 仅 Sendable + Equatable（见 ContextBag 说明）。
public enum ContextValue: Sendable, Equatable {
    /// 纯文本
    case text(String)
    /// JSON 数据（由 provider 预解析后传入，调用方可按 schema 再解）
    case json(Data)
    /// 文件引用：URL + MIME；实际内容由消费方按需读
    case file(URL, mimeType: String)
    /// 图像数据：format 为 "png" / "jpeg" 等
    case image(Data, format: String)
    /// 采集失败也记录下来，供 prompt 模板降级（如 `{{vocab|default:""}}`）
    case error(SliceError)
}
```

- [ ] **Step 3.5: SliceError 加 Equatable conformance（若未加）**

Run: `grep -n "Equatable" SliceAIKit/Sources/SliceCore/SliceError.swift`

若 SliceError（以及嵌套的 SelectionError / ProviderError / ConfigurationError / PermissionError）尚未实现 Equatable，给它们都加上 `Equatable` conformance——关联值都是 `String` / `Int` / `TimeInterval` 等已 Equatable 类型，Swift 可自动合成。

- [ ] **Step 4: 确认 SliceError Equatable**

Run: `grep -n "Equatable\|public static func ==" SliceAIKit/Sources/SliceCore/SliceError.swift`

若未实现，Modify `SliceAIKit/Sources/SliceCore/SliceError.swift` 加 `Equatable` 到声明；让 associated values 都是已 Equatable 的 String / Int / TimeInterval：

```swift
public enum SliceError: Error, Sendable, Equatable {
    // ... 现有 cases
}

public enum SelectionError: Error, Sendable, Equatable { ... }
public enum ProviderError: Error, Sendable, Equatable { ... }
public enum ConfigurationError: Error, Sendable, Equatable { ... }
public enum PermissionError: Error, Sendable, Equatable { ... }
```

大多 case 是简单关联值或无关联值，自动合成即可。

- [ ] **Step 5: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter ContextBagTests`
Expected: 6 passed.

Run: `cd SliceAIKit && swift test --filter SliceCoreTests`
Expected: 全绿（SliceError Equatable 是非破坏性改动）。

- [ ] **Step 6: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/ContextBag.swift SliceAIKit/Sources/SliceCore/SliceError.swift --strict`
Expected: 0 violations.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/ContextBag.swift \
        SliceAIKit/Sources/SliceCore/SliceError.swift \
        SliceAIKit/Tests/SliceCoreTests/ContextBagTests.swift
git commit -m "feat(core): add ContextBag and ContextValue

ContextBag is the immutable key/value container ResolvedExecutionContext.contexts
will hold. ContextValue enumerates the five shapes a ContextProvider can
produce (text / json / file / image / error). SliceError gains Equatable so
the .error case can participate in ContextValue equality checks."
```

---

## Task 8: ContextRequest + ContextProvider protocol

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/Context.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ContextRequestTests.swift`

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/ContextRequestTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ContextRequestTests: XCTestCase {

    func test_init_preservesFields() {
        let req = ContextRequest(
            key: ContextKey(rawValue: "vocab"),
            provider: "file.read",
            args: ["path": "~/vocab.md"],
            cachePolicy: .session,
            requiredness: .optional
        )
        XCTAssertEqual(req.key.rawValue, "vocab")
        XCTAssertEqual(req.provider, "file.read")
        XCTAssertEqual(req.args["path"], "~/vocab.md")
        XCTAssertEqual(req.cachePolicy, .session)
        XCTAssertEqual(req.requiredness, .optional)
    }

    func test_codable_roundtrip() throws {
        let req = ContextRequest(
            key: ContextKey(rawValue: "x"),
            provider: "mcp.call",
            args: ["server": "postgres", "tool": "query"],
            cachePolicy: .ttl(300),
            requiredness: .required
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(ContextRequest.self, from: data)
        XCTAssertEqual(req, decoded)
    }

    func test_cachePolicy_ttl_codable() throws {
        let policy = CachePolicy.ttl(60)
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(CachePolicy.self, from: data)
        XCTAssertEqual(policy, decoded)
    }

    func test_cachePolicy_none_codable() throws {
        let data = try JSONEncoder().encode(CachePolicy.none)
        let decoded = try JSONDecoder().decode(CachePolicy.self, from: data)
        XCTAssertEqual(decoded, CachePolicy.none)
    }

    // MARK: - Golden JSON shape（模板 D；禁 `_0`）

    func test_cachePolicy_goldenJSON_none_usesEmptyObjectMarker() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(CachePolicy.none), encoding: .utf8))
        XCTAssertEqual(json, #"{"none":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_cachePolicy_goldenJSON_ttl_usesDirectNumber() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(CachePolicy.ttl(60)), encoding: .utf8))
        XCTAssertEqual(json, #"{"ttl":60}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    // D-24：ContextProvider.inferredPermissions 是 static 协议方法；
    // 测试通过一个具体 stub 验证协议契约
    func test_contextProvider_conformance_exposesInferredPermissions() {
        struct FileReadProviderStub: ContextProvider {
            let name = "file.read"
            static func inferredPermissions(for args: [String: String]) -> [Permission] {
                guard let path = args["path"] else { return [] }
                return [.fileRead(path: path)]
            }
            func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue {
                .text("stub")
            }
        }
        let perms = FileReadProviderStub.inferredPermissions(for: ["path": "~/Docs/x.md"])
        XCTAssertEqual(perms, [.fileRead(path: "~/Docs/x.md")])
    }

    func test_contextProvider_emptyArgs_returnsNoPermissions() {
        struct FileReadProviderStub: ContextProvider {
            let name = "file.read"
            static func inferredPermissions(for args: [String: String]) -> [Permission] {
                guard let path = args["path"] else { return [] }
                return [.fileRead(path: path)]
            }
            func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue {
                .text("stub")
            }
        }
        XCTAssertTrue(FileReadProviderStub.inferredPermissions(for: [:]).isEmpty)
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter ContextRequestTests`
Expected: FAIL `cannot find 'ContextRequest' / 'ContextProvider' / 'CachePolicy' in scope`.

- [ ] **Step 3: 实现 Context.swift**

Create `SliceAIKit/Sources/SliceCore/Context.swift`:

```swift
import Foundation

/// Tool 声明的一次上下文采集请求
///
/// 由 `ContextCollector` 解析 provider 名找到对应 `ContextProvider` 并传入 args 执行。
/// M1 定义数据结构；M2 填实 `ContextCollector.resolve(seed:requests:)`。
public struct ContextRequest: Sendable, Equatable, Codable {
    /// 采集结果在 `ContextBag` 中的键名
    public let key: ContextKey
    /// 采集器 provider 注册名（如 `file.read` / `clipboard.current` / `mcp.call`）
    public let provider: String
    /// 透传给 provider 的参数（如 `["path": "~/vocab.md"]`）
    public let args: [String: String]
    /// 缓存策略
    public let cachePolicy: CachePolicy
    /// 失败容忍策略
    public let requiredness: Requiredness

    /// 构造 ContextRequest
    public init(key: ContextKey, provider: String, args: [String: String], cachePolicy: CachePolicy, requiredness: Requiredness) {
        self.key = key
        self.provider = provider
        self.args = args
        self.cachePolicy = cachePolicy
        self.requiredness = requiredness
    }
}

/// 采集缓存策略
///
/// **手写 Codable（模板 A + C）**
public enum CachePolicy: Sendable, Equatable, Codable {
    case none
    case session
    case ttl(TimeInterval)

    private enum CodingKeys: String, CodingKey { case none, session, ttl }
    private struct EmptyMarker: Codable, Equatable {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.none) { _ = try c.decode(EmptyMarker.self, forKey: .none); self = .none; return }
        if c.contains(.session) { _ = try c.decode(EmptyMarker.self, forKey: .session); self = .session; return }
        if let t = try c.decodeIfPresent(TimeInterval.self, forKey: .ttl) { self = .ttl(t); return }
        throw DecodingError.dataCorruptedError(forKey: CodingKeys.none, in: c,
            debugDescription: "CachePolicy requires one of: none, session, ttl")
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:    try c.encode(EmptyMarker(), forKey: .none)
        case .session: try c.encode(EmptyMarker(), forKey: .session)
        case .ttl(let t): try c.encode(t, forKey: .ttl)
        }
    }
}

/// 上下文采集器契约；内置 provider 与第三方 provider 均实现此协议
///
/// 注册：M2 的 `ContextCollector` 维护一个 `[name: any ContextProvider]` 字典，
/// 在 app 启动时把所有内置 provider 装入。
///
/// 关键静态方法 `inferredPermissions(for:)` 是 D-24 权限声明闭环的基石：
/// - `PermissionGraph.compute(tool:)` 聚合所有 `tool.contexts` 中每个 request
///   的 `type(of: provider).inferredPermissions(for: request.args)` 结果；
/// - 要求该方法是纯函数、无副作用、不访问外部资源。
/// - 漏报 → 运行时"权限未声明"错误；多报 → 声明超出实际、影响 UX 无安全风险。
public protocol ContextProvider: Sendable {
    /// Provider 注册名，需全局唯一
    var name: String { get }

    /// 静态推导本次采集会触发哪些 Permission
    /// - Parameter args: ContextRequest.args 原样透传
    /// - Returns: 本次采集需要的权限；无权限需求返回空数组
    static func inferredPermissions(for args: [String: String]) -> [Permission]

    /// 实际执行采集；调用前 `PermissionBroker.gate` 已通过
    /// - Parameters:
    ///   - request: 原始 request
    ///   - seed: 当前 ExecutionSeed 中的 selection（便于基于选区参数化）
    ///   - app: 前台 app 快照
    /// - Returns: 采集结果 ContextValue
    func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue
}
```

- [ ] **Step 4: 运行看通过**

Run: `cd SliceAIKit && swift test --filter ContextRequestTests`
Expected: 6/6 passed.

- [ ] **Step 5: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/Context.swift --strict`
Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/Context.swift \
        SliceAIKit/Tests/SliceCoreTests/ContextRequestTests.swift
git commit -m "feat(core): add ContextRequest, CachePolicy, ContextProvider protocol

ContextProvider declares the static inferredPermissions(for:) method that
PermissionGraph.compute() will aggregate for the D-24 effectivePermissions ⊆
tool.permissions closed-loop check. M1 ships the protocol; built-in providers
(file.read / clipboard / mcp.call / ...) land in Phase 1."
```

---

## Task 9: ResolvedExecutionContext

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ResolvedExecutionContext.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ResolvedExecutionContextTests.swift`

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/ResolvedExecutionContextTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ResolvedExecutionContextTests: XCTestCase {

    private func makeSeed() -> ExecutionSeed {
        ExecutionSeed(
            invocationId: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            selection: SelectionSnapshot(text: "t", source: .accessibility, length: 1, language: nil, contentType: nil),
            frontApp: AppSnapshot(bundleId: "com.apple.Safari", name: "Safari", url: nil, windowTitle: nil),
            screenAnchor: .zero,
            timestamp: Date(timeIntervalSince1970: 50),
            triggerSource: .commandPalette,
            isDryRun: false
        )
    }

    func test_init_preservesAllFields() {
        let seed = makeSeed()
        let key = ContextKey(rawValue: "vocab")
        let rc = ResolvedExecutionContext(
            seed: seed,
            contexts: ContextBag(values: [key: .text("list")]),
            resolvedAt: Date(timeIntervalSince1970: 60),
            failures: [:]
        )
        XCTAssertEqual(rc.seed, seed)
        XCTAssertNotNil(rc.contexts[key])
        XCTAssertTrue(rc.failures.isEmpty)
    }

    func test_transparentAccessors_forwardToSeed() {
        let seed = makeSeed()
        let rc = ResolvedExecutionContext(seed: seed, contexts: ContextBag(values: [:]), resolvedAt: Date(), failures: [:])
        XCTAssertEqual(rc.invocationId, seed.invocationId)
        XCTAssertEqual(rc.selection, seed.selection)
        XCTAssertEqual(rc.frontApp, seed.frontApp)
        XCTAssertEqual(rc.isDryRun, seed.isDryRun)
    }

    func test_failures_carryOptionalRequestErrors() {
        let seed = makeSeed()
        let key = ContextKey(rawValue: "vocab")
        let err = SliceError.configuration(.fileNotFound)
        let rc = ResolvedExecutionContext(
            seed: seed,
            contexts: ContextBag(values: [:]),
            resolvedAt: Date(),
            failures: [key: err]
        )
        XCTAssertEqual(rc.failures[key]?.userMessage, err.userMessage)
    }

    func test_equality_sameFields_isEqual() {
        let seed = makeSeed()
        let rc1 = ResolvedExecutionContext(seed: seed, contexts: ContextBag(values: [:]), resolvedAt: Date(timeIntervalSince1970: 10), failures: [:])
        let rc2 = ResolvedExecutionContext(seed: seed, contexts: ContextBag(values: [:]), resolvedAt: Date(timeIntervalSince1970: 10), failures: [:])
        XCTAssertEqual(rc1, rc2)
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter ResolvedExecutionContextTests`
Expected: FAIL.

- [ ] **Step 3: 实现**

Create `SliceAIKit/Sources/SliceCore/ResolvedExecutionContext.swift`:

```swift
import Foundation

/// 二阶段执行上下文：由 `ContextCollector.resolve(seed:requests:)` 产出
///
/// 不可变（INV-6）；执行引擎真正消费的对象。相比 `ExecutionSeed` 增加：
/// - `contexts`：所有成功采集的 ContextValue
/// - `failures`：`requiredness == .optional` 的请求失败记录（required 失败则流程早已终止）
/// - `resolvedAt`：解析完成时间，便于延迟分析
///
/// 透传访问器仅为调用便利；底层数据源 = `seed.*`。
public struct ResolvedExecutionContext: Sendable, Equatable {
    /// 原始 seed（不可变）
    public let seed: ExecutionSeed
    /// 采集到的上下文值
    public let contexts: ContextBag
    /// 解析完成时间
    public let resolvedAt: Date
    /// optional 请求的失败记录；required 请求失败时流程直接中止、不会进入这里
    public let failures: [ContextKey: SliceError]

    /// 构造 ResolvedExecutionContext
    /// - Parameters:
    ///   - seed: 来源 seed
    ///   - contexts: 成功采集的键值
    ///   - resolvedAt: 解析完成时间
    ///   - failures: optional 请求的失败记录
    public init(seed: ExecutionSeed, contexts: ContextBag, resolvedAt: Date, failures: [ContextKey: SliceError]) {
        self.seed = seed
        self.contexts = contexts
        self.resolvedAt = resolvedAt
        self.failures = failures
    }

    // MARK: - Transparent accessors

    /// 透传 `seed.invocationId`
    public var invocationId: UUID { seed.invocationId }
    /// 透传 `seed.selection`
    public var selection: SelectionSnapshot { seed.selection }
    /// 透传 `seed.frontApp`
    public var frontApp: AppSnapshot { seed.frontApp }
    /// 透传 `seed.isDryRun`
    public var isDryRun: Bool { seed.isDryRun }
}
```

- [ ] **Step 4: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter ResolvedExecutionContextTests`
Expected: 4/4 passed.

- [ ] **Step 5: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/ResolvedExecutionContext.swift --strict`
Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/ResolvedExecutionContext.swift \
        SliceAIKit/Tests/SliceCoreTests/ResolvedExecutionContextTests.swift
git commit -m "feat(core): add ResolvedExecutionContext (stage-2 execution context)

Immutable output of ContextCollector.resolve(seed:requests:). Wraps the
original seed with the ContextBag and per-optional-request failure map.
Transparent accessors (invocationId/selection/frontApp/isDryRun) forward to
seed for caller ergonomics without exposing mutation."
```

---

## Task 10: OutputBinding + PresentationMode + SideEffect + inferredPermissions

> **评审修正（执行阶段 2026-04-24）**：原 plan 把新 6-case 枚举命名为 `DisplayMode`，与 `Tool.swift:85` 既有 `public enum DisplayMode` （3-case，v1）同名冲突，Swift 不允许同 module 两个同名 public enum。M1 要求 `Tool.swift` 零改动（否则还要连带改 `SettingsUI/ToolEditorView.swift` 的 switch，违反"零触及 SettingsUI"）。收敛为：v2 canonical 6-case enum 命名为 `PresentationMode`；v1 `Tool.DisplayMode` 原封保留。M3 rename 阶段再决定是否把 `V2Tool.presentationMode`/`PresentationMode` 一次性 rename 回 `displayMode`/`DisplayMode`。本修订已扩散到 Task 10 / 15 / 17 / 20 所有 `DisplayMode` 引用。

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/OutputBinding.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/OutputBindingTests.swift`

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/OutputBindingTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class OutputBindingTests: XCTestCase {

    // MARK: - PresentationMode

    func test_displayMode_allCases_stable() {
        XCTAssertEqual(Set(PresentationMode.allCases), [.window, .bubble, .replace, .file, .silent, .structured])
    }

    func test_displayMode_codable() throws {
        for mode in PresentationMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(PresentationMode.self, from: data)
            XCTAssertEqual(mode, decoded)
        }
    }

    // MARK: - SideEffect inferredPermissions (D-24)

    func test_appendToFile_inferredPermissions_fileWrite() {
        let se = SideEffect.appendToFile(path: "~/notes.md", header: nil)
        XCTAssertEqual(se.inferredPermissions, [.fileWrite(path: "~/notes.md")])
    }

    func test_copyToClipboard_inferredPermissions_clipboard() {
        XCTAssertEqual(SideEffect.copyToClipboard.inferredPermissions, [.clipboard])
    }

    func test_notify_inferredPermissions_empty() {
        // 本地通知不视为 permission
        XCTAssertTrue(SideEffect.notify(title: "t", body: "b").inferredPermissions.isEmpty)
    }

    func test_runAppIntent_inferredPermissions_appIntents() {
        let se = SideEffect.runAppIntent(bundleId: "com.culturedcode.ThingsMac", intent: "Add", params: [:])
        XCTAssertEqual(se.inferredPermissions, [.appIntents(bundleId: "com.culturedcode.ThingsMac")])
    }

    func test_callMCP_inferredPermissions_mcpWithTool() {
        let ref = MCPToolRef(server: "postgres", tool: "query")
        let se = SideEffect.callMCP(ref: ref, params: [:])
        XCTAssertEqual(se.inferredPermissions, [.mcp(server: "postgres", tools: ["query"])])
    }

    func test_writeMemory_inferredPermissions_memoryAccess() {
        let se = SideEffect.writeMemory(tool: "grammar-tutor", entry: "ok")
        XCTAssertEqual(se.inferredPermissions, [.memoryAccess(scope: "grammar-tutor")])
    }

    func test_tts_inferredPermissions_systemAudio() {
        XCTAssertEqual(SideEffect.tts(voice: nil).inferredPermissions, [.systemAudio])
    }

    // MARK: - OutputBinding Codable

    func test_outputBinding_codable_roundtrip() throws {
        let ref = MCPToolRef(server: "slack", tool: "send")
        let binding = OutputBinding(
            primary: .window,
            sideEffects: [.copyToClipboard, .callMCP(ref: ref, params: ["channel": "#general"])]
        )
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(OutputBinding.self, from: data)
        XCTAssertEqual(binding, decoded)
    }

    // MARK: - Golden JSON shape（模板 D；禁 `_0`）

    func test_sideEffect_goldenJSON_copyToClipboard_emptyObject() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(SideEffect.copyToClipboard), encoding: .utf8))
        XCTAssertEqual(json, #"{"copyToClipboard":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_appendToFile_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.appendToFile(path: "~/notes.md", header: "## 2026-04-23")
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"appendToFile":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""path":"~\/notes.md""#))
        XCTAssertTrue(json.contains(#""header":"## 2026-04-23""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_callMCP_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.callMCP(ref: MCPToolRef(server: "anki", tool: "createNote"), params: [:])
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"callMCP":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""server":"anki""#))
        XCTAssertTrue(json.contains(#""tool":"createNote""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_tts_nestedWithOptional() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.tts(voice: nil)
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        // nil voice → TTSRepr { voice: nil } → JSON `{"tts":{}}` 或 `{"tts":{"voice":null}}`（取决于 JSONEncoder）
        XCTAssertTrue(json.hasPrefix(#"{"tts":{"#), "got: \(json)")
        XCTAssertFalse(json.contains("\"_0\""))
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter OutputBindingTests`
Expected: FAIL（`PresentationMode` 等缺失或不完整）。

- [ ] **Step 3: 实现**

Create `SliceAIKit/Sources/SliceCore/OutputBinding.swift`:

```swift
import Foundation

/// Tool 的输出绑定；决定结果展示形态 + 并行副作用
public struct OutputBinding: Sendable, Equatable, Codable {
    /// 主展示方式
    public let primary: PresentationMode
    /// 并行副作用；按数组顺序触发
    public let sideEffects: [SideEffect]

    /// 构造 OutputBinding
    public init(primary: PresentationMode, sideEffects: [SideEffect]) {
        self.primary = primary
        self.sideEffects = sideEffects
    }
}

/// 结果展示模式；六种模式都作为正式成员进入数据模型（spec §3.3.6）
///
/// Phase 0 M1 仅定义 enum；各模式的 UI 实现按 phase 渐进：
/// - Phase 0 (v0.1 继承): `.window`
/// - Phase 2: `.replace` / `.bubble` / `.structured` / `.silent`（配合 InlineReplaceOverlay / BubblePanel / StructuredResultView）
/// - Phase 2+: `.file`
public enum PresentationMode: String, Sendable, Codable, CaseIterable {
    /// 独立浮窗（v0.1 默认）
    case window
    /// 小气泡，自动消失
    case bubble
    /// 替换选区（AX setSelectedText 或 paste fallback）
    case replace
    /// 写文件
    case file
    /// 无 UI，只做副作用
    case silent
    /// JSONSchema 结构化结果，UI 自动渲染表单/表格
    case structured
}

/// 副作用：声明式列表，执行引擎按顺序触发
///
/// D-24 要求每个 case 能**静态推导** 所需 Permission，见 `inferredPermissions` extension。
public enum SideEffect: Sendable, Equatable, Codable {
    case appendToFile(path: String, header: String?)
    case copyToClipboard
    case notify(title: String, body: String)
    case runAppIntent(bundleId: String, intent: String, params: [String: String])
    case callMCP(ref: MCPToolRef, params: [String: String])
    case writeMemory(tool: String, entry: String)
    case tts(voice: String?)

    // MARK: - 手写 Codable（模板 A + B）

    private enum CodingKeys: String, CodingKey {
        case appendToFile, copyToClipboard, notify, runAppIntent, callMCP, writeMemory, tts
    }
    private struct EmptyMarker: Codable, Equatable {}
    private struct AppendRepr: Codable, Equatable { let path: String; let header: String? }
    private struct NotifyRepr: Codable, Equatable { let title: String; let body: String }
    private struct AppIntentRepr: Codable, Equatable { let bundleId: String; let intent: String; let params: [String: String] }
    private struct CallMCPRepr: Codable, Equatable { let ref: MCPToolRef; let params: [String: String] }
    private struct MemoryRepr: Codable, Equatable { let tool: String; let entry: String }
    private struct TTSRepr: Codable, Equatable { let voice: String? }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let r = try c.decodeIfPresent(AppendRepr.self, forKey: .appendToFile) {
            self = .appendToFile(path: r.path, header: r.header); return
        }
        if c.contains(.copyToClipboard) {
            _ = try c.decode(EmptyMarker.self, forKey: .copyToClipboard); self = .copyToClipboard; return
        }
        if let r = try c.decodeIfPresent(NotifyRepr.self, forKey: .notify) {
            self = .notify(title: r.title, body: r.body); return
        }
        if let r = try c.decodeIfPresent(AppIntentRepr.self, forKey: .runAppIntent) {
            self = .runAppIntent(bundleId: r.bundleId, intent: r.intent, params: r.params); return
        }
        if let r = try c.decodeIfPresent(CallMCPRepr.self, forKey: .callMCP) {
            self = .callMCP(ref: r.ref, params: r.params); return
        }
        if let r = try c.decodeIfPresent(MemoryRepr.self, forKey: .writeMemory) {
            self = .writeMemory(tool: r.tool, entry: r.entry); return
        }
        if let r = try c.decodeIfPresent(TTSRepr.self, forKey: .tts) {
            self = .tts(voice: r.voice); return
        }
        throw DecodingError.dataCorruptedError(forKey: CodingKeys.appendToFile, in: c,
            debugDescription: "SideEffect requires one known case")
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appendToFile(let p, let h): try c.encode(AppendRepr(path: p, header: h), forKey: .appendToFile)
        case .copyToClipboard:            try c.encode(EmptyMarker(), forKey: .copyToClipboard)
        case .notify(let t, let b):       try c.encode(NotifyRepr(title: t, body: b), forKey: .notify)
        case .runAppIntent(let b, let i, let p): try c.encode(AppIntentRepr(bundleId: b, intent: i, params: p), forKey: .runAppIntent)
        case .callMCP(let r, let p):      try c.encode(CallMCPRepr(ref: r, params: p), forKey: .callMCP)
        case .writeMemory(let t, let e):  try c.encode(MemoryRepr(tool: t, entry: e), forKey: .writeMemory)
        case .tts(let v):                 try c.encode(TTSRepr(voice: v), forKey: .tts)
        }
    }
}

public extension SideEffect {

    /// D-24：静态推导本 side effect 会触发哪些 Permission
    ///
    /// 规则：
    /// - 不可读外部状态；只能基于 case 关联值推导
    /// - 新增 case 必须同步在此返回对应 Permission，否则 PermissionGraph 漏报
    /// - 本地通知（`.notify`）不计为 permission；macOS 首次通知时系统会独立弹框
    var inferredPermissions: [Permission] {
        switch self {
        case .appendToFile(let path, _):
            return [.fileWrite(path: path)]
        case .copyToClipboard:
            return [.clipboard]
        case .notify:
            return []
        case .runAppIntent(let bundleId, _, _):
            return [.appIntents(bundleId: bundleId)]
        case .callMCP(let ref, _):
            return [.mcp(server: ref.server, tools: [ref.tool])]
        case .writeMemory(let toolId, _):
            return [.memoryAccess(scope: toolId)]
        case .tts:
            return [.systemAudio]
        }
    }
}

/// 对某个 MCP tool 的引用；`AgentTool.mcpAllowlist` 与 `SideEffect.callMCP` 共用
public struct MCPToolRef: Sendable, Equatable, Hashable, Codable {
    /// MCP server 的本地注册名
    public let server: String
    /// server 暴露的 tool 名
    public let tool: String

    /// 构造 MCPToolRef
    public init(server: String, tool: String) {
        self.server = server
        self.tool = tool
    }
}
```

- [ ] **Step 4: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter OutputBindingTests`
Expected: 10/10 passed.

- [ ] **Step 5: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/OutputBinding.swift --strict`
Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/OutputBinding.swift \
        SliceAIKit/Tests/SliceCoreTests/OutputBindingTests.swift
git commit -m "feat(core): add OutputBinding, PresentationMode, SideEffect

Six PresentationMode values are defined as first-class members of the data model
(v0.1 only implements .window; Phase 2+ fills the rest). SideEffect carries
the D-24 inferredPermissions contract so PermissionGraph.compute() can
statically derive effective permissions without running the tool."
```

---

## Task 11: ProviderSelection + ProviderCapability

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ProviderSelection.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ProviderSelectionTests.swift`

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/ProviderSelectionTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ProviderSelectionTests: XCTestCase {

    func test_fixed_preservesProviderAndModel() {
        let sel = ProviderSelection.fixed(providerId: "openai-official", modelId: "gpt-5")
        if case .fixed(let p, let m) = sel {
            XCTAssertEqual(p, "openai-official")
            XCTAssertEqual(m, "gpt-5")
        } else {
            XCTFail("expected .fixed")
        }
    }

    func test_fixed_nilModel_allowed() {
        let sel = ProviderSelection.fixed(providerId: "p", modelId: nil)
        if case .fixed(_, let m) = sel {
            XCTAssertNil(m)
        } else {
            XCTFail()
        }
    }

    func test_capability_preservesRequiresAndPrefer() {
        let sel = ProviderSelection.capability(
            requires: [.toolCalling, .vision],
            prefer: ["claude", "gpt"]
        )
        if case .capability(let r, let p) = sel {
            XCTAssertEqual(r, [.toolCalling, .vision])
            XCTAssertEqual(p, ["claude", "gpt"])
        } else {
            XCTFail()
        }
    }

    func test_cascade_carriesRules() {
        let rule = CascadeRule(
            when: .selectionLengthGreaterThan(8000),
            providerId: "claude",
            modelId: "haiku"
        )
        let sel = ProviderSelection.cascade(rules: [rule])
        if case .cascade(let rs) = sel {
            XCTAssertEqual(rs.count, 1)
        } else {
            XCTFail()
        }
    }

    func test_providerCapability_rawValues_stable() {
        XCTAssertEqual(ProviderCapability.promptCaching.rawValue, "promptCaching")
        XCTAssertEqual(ProviderCapability.toolCalling.rawValue, "toolCalling")
        XCTAssertEqual(ProviderCapability.vision.rawValue, "vision")
        XCTAssertEqual(ProviderCapability.extendedThinking.rawValue, "extendedThinking")
        XCTAssertEqual(ProviderCapability.grounding.rawValue, "grounding")
        XCTAssertEqual(ProviderCapability.jsonSchemaOutput.rawValue, "jsonSchemaOutput")
        XCTAssertEqual(ProviderCapability.longContext.rawValue, "longContext")
    }

    func test_codable_roundtrip_fixed() throws {
        let sel = ProviderSelection.fixed(providerId: "openai", modelId: "gpt-5")
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(ProviderSelection.self, from: data)
        XCTAssertEqual(sel, decoded)
    }

    func test_codable_roundtrip_capability() throws {
        let sel = ProviderSelection.capability(requires: [.toolCalling], prefer: ["anthropic"])
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(ProviderSelection.self, from: data)
        XCTAssertEqual(sel, decoded)
    }

    func test_codable_roundtrip_cascade() throws {
        let rule = CascadeRule(when: .isCode, providerId: "claude", modelId: "sonnet")
        let sel = ProviderSelection.cascade(rules: [rule])
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(ProviderSelection.self, from: data)
        XCTAssertEqual(sel, decoded)
    }

    // MARK: - Golden JSON shape（模板 D）

    func test_providerSelection_goldenJSON_fixed_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let sel = ProviderSelection.fixed(providerId: "openai", modelId: "gpt-5")
        let json = try XCTUnwrap(String(data: try enc.encode(sel), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"fixed":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""providerId":"openai""#))
        XCTAssertTrue(json.contains(#""modelId":"gpt-5""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_providerSelection_goldenJSON_capability_requiresArraySorted() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        // 手写 Codable 把 requires Set 按 rawValue 排序后写 Array
        let sel = ProviderSelection.capability(
            requires: [.vision, .toolCalling, .promptCaching],  // 乱序输入
            prefer: ["claude"]
        )
        let json = try XCTUnwrap(String(data: try enc.encode(sel), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"capability":{"#), "got: \(json)")
        // 排序后：promptCaching < toolCalling < vision（按字母序）
        XCTAssertTrue(json.contains(#""requires":["promptCaching","toolCalling","vision"]"#), "requires 未按 rawValue 字母序排列，got: \(json)")
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_conditionExpr_goldenJSON_always_emptyObject() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(ConditionExpr.always), encoding: .utf8))
        XCTAssertEqual(json, #"{"always":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_conditionExpr_goldenJSON_selectionLength_directInt() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(ConditionExpr.selectionLengthGreaterThan(8000)), encoding: .utf8))
        XCTAssertEqual(json, #"{"selectionLengthGreaterThan":8000}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter ProviderSelectionTests`
Expected: FAIL.

- [ ] **Step 3: 实现**

Create `SliceAIKit/Sources/SliceCore/ProviderSelection.swift`:

```swift
import Foundation

/// Provider 选择策略；Tool 的 `kind.*.provider` 字段
///
/// 从 v1 的 `providerId: String` 升级：三种模式中 `.fixed` 与 v1 行为等价；
/// `.capability` 让工具声明"我需要什么能力"，运行时按 `Configuration.providers` 匹配；
/// `.cascade` 实现"长文用 Haiku，代码用 Sonnet"之类的条件路由。
public enum ProviderSelection: Sendable, Equatable, Codable {
    case fixed(providerId: String, modelId: String?)
    case capability(requires: Set<ProviderCapability>, prefer: [String])
    case cascade(rules: [CascadeRule])

    // MARK: - 手写 Codable（模板 A + B；Set<ProviderCapability> 先转 Array 排序以稳定 JSON）

    private enum CodingKeys: String, CodingKey { case fixed, capability, cascade }
    private struct FixedRepr: Codable, Equatable { let providerId: String; let modelId: String? }
    private struct CapabilityRepr: Codable, Equatable {
        let requires: [ProviderCapability]  // 编码前会 sort；解码后用 Set 恢复语义
        let prefer: [String]
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let r = try c.decodeIfPresent(FixedRepr.self, forKey: .fixed) {
            self = .fixed(providerId: r.providerId, modelId: r.modelId); return
        }
        if let r = try c.decodeIfPresent(CapabilityRepr.self, forKey: .capability) {
            self = .capability(requires: Set(r.requires), prefer: r.prefer); return
        }
        if let rules = try c.decodeIfPresent([CascadeRule].self, forKey: .cascade) {
            self = .cascade(rules: rules); return
        }
        throw DecodingError.dataCorruptedError(forKey: CodingKeys.fixed, in: c,
            debugDescription: "ProviderSelection requires one of: fixed, capability, cascade")
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixed(let p, let m):
            try c.encode(FixedRepr(providerId: p, modelId: m), forKey: .fixed)
        case .capability(let req, let prefer):
            // Set 编码顺序不稳定 → 转 Array 并按 rawValue 排序，保证 JSON 可 diff
            let sortedReq = req.sorted { $0.rawValue < $1.rawValue }
            try c.encode(CapabilityRepr(requires: sortedReq, prefer: prefer), forKey: .capability)
        case .cascade(let rules):
            try c.encode(rules, forKey: .cascade)
        }
    }
}

/// Provider 能力声明；`Provider.capabilities` 与 `ProviderSelection.capability.requires` 共用
public enum ProviderCapability: String, Sendable, Codable, CaseIterable {
    /// Anthropic / DeepSeek 的 prompt caching
    case promptCaching
    /// Function / tool calling
    case toolCalling
    /// 多模态视觉输入
    case vision
    /// Claude Extended Thinking
    case extendedThinking
    /// Gemini grounding / Google Search
    case grounding
    /// 强 JSON Schema 输出（非 prompt-hinted）
    case jsonSchemaOutput
    /// 长上下文（≥ 200k tokens）
    case longContext
}

/// 级联规则：条件命中则用指定 provider + model
public struct CascadeRule: Sendable, Equatable, Codable {
    /// 命中条件
    public let when: ConditionExpr
    /// 命中时使用的 provider id
    public let providerId: String
    /// 可选 modelId（nil 回落 provider.defaultModel）
    public let modelId: String?

    /// 构造 CascadeRule
    public init(when: ConditionExpr, providerId: String, modelId: String?) {
        self.when = when
        self.providerId = providerId
        self.modelId = modelId
    }
}

/// 简单条件表达式（刻意不做 DSL，枚举有限几种）
///
/// M1 定义枚举；M2+ 的 ProviderResolver 按 case 分派判定逻辑。
public enum ConditionExpr: Sendable, Equatable, Codable {
    case always
    case selectionLengthGreaterThan(Int)
    case isCode
    case languageEquals(String)
    case appBundleIdEquals(String)

    // MARK: - 手写 Codable（模板 A + C）

    private enum CodingKeys: String, CodingKey {
        case always, selectionLengthGreaterThan, isCode, languageEquals, appBundleIdEquals
    }
    private struct EmptyMarker: Codable, Equatable {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.always) { _ = try c.decode(EmptyMarker.self, forKey: .always); self = .always; return }
        if let n = try c.decodeIfPresent(Int.self, forKey: .selectionLengthGreaterThan) {
            self = .selectionLengthGreaterThan(n); return
        }
        if c.contains(.isCode) { _ = try c.decode(EmptyMarker.self, forKey: .isCode); self = .isCode; return }
        if let s = try c.decodeIfPresent(String.self, forKey: .languageEquals) {
            self = .languageEquals(s); return
        }
        if let s = try c.decodeIfPresent(String.self, forKey: .appBundleIdEquals) {
            self = .appBundleIdEquals(s); return
        }
        throw DecodingError.dataCorruptedError(forKey: CodingKeys.always, in: c,
            debugDescription: "ConditionExpr requires one known case")
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .always:                           try c.encode(EmptyMarker(), forKey: .always)
        case .selectionLengthGreaterThan(let n): try c.encode(n, forKey: .selectionLengthGreaterThan)
        case .isCode:                           try c.encode(EmptyMarker(), forKey: .isCode)
        case .languageEquals(let s):            try c.encode(s, forKey: .languageEquals)
        case .appBundleIdEquals(let s):         try c.encode(s, forKey: .appBundleIdEquals)
        }
    }
}
```

- [ ] **Step 4: 运行通过**

Run: `cd SliceAIKit && swift test --filter ProviderSelectionTests`
Expected: 8/8 passed.

- [ ] **Step 5: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/ProviderSelection.swift --strict`
Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/ProviderSelection.swift \
        SliceAIKit/Tests/SliceCoreTests/ProviderSelectionTests.swift
git commit -m "feat(core): add ProviderSelection, ProviderCapability, CascadeRule

Three-mode provider selection replaces v1's flat providerId string. .fixed
mode is backward compatible; .capability lets tools declare needed provider
features; .cascade enables cost-aware routing (long text -> cheaper model, etc.)."
```

---

## Task 12: V2Provider 独立新类型（不改现有 Provider）

> **评审修正（Codex 第五轮 P1-2）**：初版方案"在 Provider.swift 上直接加 `kind` + `capabilities` + `baseURL: URL?`"会把 baseURL 改成 optional，而 LLMProviders / SettingsUI 大量按非 optional 使用（`OpenAIProviderFactory` 直接传 `URL` 给 `OpenAICompatibleProvider(baseURL: URL)`、`ProviderEditorView` 读 `provider.baseURL.absoluteString`）——plan 又承诺 M1 零触及这些模块，矛盾。
>
> **收敛**：不改 `Provider.swift`；新建**独立 v2 类型** `V2Provider.swift`。现有 `Provider`（`baseURL: URL` 非 optional）服务 LLMProviders / SettingsUI 等现有链路不变；`V2Provider`（`baseURL: URL?`）只被 migrator / V2Configuration / V2ConfigurationStore 使用，M3 做一次性 rename 时再统一。

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/V2Provider.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/V2ProviderTests.swift`
- **不修改** `SliceAIKit/Sources/SliceCore/Provider.swift`

- [ ] **Step 1: 写 V2Provider 失败测试 + golden JSON**

Create `SliceAIKit/Tests/SliceCoreTests/V2ProviderTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class V2ProviderTests: XCTestCase {

    func test_init_anthropic_allowsNilBaseURL() {
        let p = V2Provider(
            id: "claude",
            kind: .anthropic,
            name: "Claude",
            baseURL: nil,
            apiKeyRef: "keychain:claude",
            defaultModel: "claude-sonnet-4-6",
            capabilities: [.promptCaching, .toolCalling, .extendedThinking, .vision, .longContext]
        )
        XCTAssertEqual(p.kind, .anthropic)
        XCTAssertNil(p.baseURL)
        XCTAssertTrue(p.capabilities.contains(.extendedThinking))
    }

    func test_init_openAICompatible_requiresBaseURL() {
        let p = V2Provider(
            id: "openai-official",
            kind: .openAICompatible,
            name: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1"),
            apiKeyRef: "keychain:openai-official",
            defaultModel: "gpt-5",
            capabilities: []
        )
        XCTAssertNotNil(p.baseURL)
    }

    func test_providerKind_codable_goldenShape() throws {
        // golden JSON shape for each kind
        XCTAssertEqual(try encodeString(ProviderKind.openAICompatible), "\"openAICompatible\"")
        XCTAssertEqual(try encodeString(ProviderKind.anthropic), "\"anthropic\"")
        XCTAssertEqual(try encodeString(ProviderKind.gemini), "\"gemini\"")
        XCTAssertEqual(try encodeString(ProviderKind.ollama), "\"ollama\"")
    }

    func test_v2Provider_codable_goldenShape() throws {
        let p = V2Provider(
            id: "claude",
            kind: .anthropic,
            name: "Claude",
            baseURL: nil,
            apiKeyRef: "keychain:claude",
            defaultModel: "claude-sonnet-4-6",
            capabilities: [.promptCaching]
        )
        let data = try encode(p)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"kind\":\"anthropic\""))
        XCTAssertTrue(json.contains("\"id\":\"claude\""))
        XCTAssertTrue(json.contains("\"capabilities\":[\"promptCaching\"]"))
        XCTAssertFalse(json.contains("\"baseURL\""))  // nil 字段不写出
    }

    func test_v2Provider_codable_roundtrip() throws {
        let p = V2Provider(
            id: "openai-official",
            kind: .openAICompatible,
            name: "OpenAI",
            baseURL: URL(string: "https://api.openai.com/v1"),
            apiKeyRef: "keychain:openai-official",
            defaultModel: "gpt-5",
            capabilities: []
        )
        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(V2Provider.self, from: data)
        XCTAssertEqual(p, decoded)
    }

    func test_v2Provider_keychainAccount() {
        let p = V2Provider(id: "x", kind: .anthropic, name: "X", baseURL: nil,
                            apiKeyRef: "keychain:custom-account", defaultModel: "m", capabilities: [])
        XCTAssertEqual(p.keychainAccount, "custom-account")
    }

    // MARK: - Helpers

    private func encode<T: Encodable>(_ value: T) throws -> Data {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return try enc.encode(value)
    }

    private func encodeString<T: Encodable>(_ value: T) throws -> String {
        let data = try encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter V2ProviderTests`
Expected: FAIL（`V2Provider` / `ProviderKind` 不存在）。

- [ ] **Step 3: 实现 V2Provider.swift**

Create `SliceAIKit/Sources/SliceCore/V2Provider.swift`:

```swift
import Foundation

/// v2 LLM 供应商配置（独立新类型；现有 `Provider` 保持 v1 形状不变）
///
/// 相对 v1 `Provider` 的变化：
/// - 新增 `kind: ProviderKind`：声明协议族
/// - 新增 `capabilities: [ProviderCapability]`：声明支持的高级能力（Set 语义 + 稳定顺序；见评审 P2-3）
/// - `baseURL: URL?`：`.anthropic` / `.gemini` 协议族可 nil
///
/// **评审修正（Codex 第六轮 P2-3）**：初版 `capabilities: Set<ProviderCapability>` 在 JSON 序列化中
/// 顺序不稳定（`JSONEncoder.outputFormatting = [.sortedKeys]` 只排字典 key，不排数组元素）。
/// 本版改为 `[ProviderCapability]`：`init` 中自动去重（保留首次出现顺序）并按 rawValue 排序，
/// 保证 round-trip 稳定；Set 语义由 init 保证，调用方读到的数组已有序无重复。
///
/// M3 rename pass：删除 Provider.swift，把本文件重命名为 Provider.swift、类型改名为 Provider。
public struct V2Provider: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var kind: ProviderKind
    public var name: String
    public var baseURL: URL?
    public var apiKeyRef: String
    public var defaultModel: String
    public var capabilities: [ProviderCapability]  // **[…] 而非 Set<…>**（P2-3）

    /// 构造 V2Provider
    /// - Note: `capabilities` 传入 Set 或 Array 都可；内部去重 + 按 rawValue 排序，保证 JSON 稳定
    public init(
        id: String,
        kind: ProviderKind,
        name: String,
        baseURL: URL?,
        apiKeyRef: String,
        defaultModel: String,
        capabilities: some Sequence<ProviderCapability>
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.defaultModel = defaultModel
        // 去重 + 按 rawValue 排序，保证 JSON 稳定（评审 P2-3）
        self.capabilities = Array(Set(capabilities)).sorted { $0.rawValue < $1.rawValue }
    }

    /// apiKeyRef 前缀，与 v1 保持一致
    public static let keychainRefPrefix = "keychain:"

    /// 解析 Keychain account；非 `keychain:` 前缀返回 nil
    public var keychainAccount: String? {
        guard apiKeyRef.hasPrefix(Self.keychainRefPrefix) else { return nil }
        return String(apiKeyRef.dropFirst(Self.keychainRefPrefix.count))
    }

    // MARK: - Codable（手写 init；保证解码路径也做 capabilities 去重+排序）
    //
    // 评审修正（Codex 第七轮 P2）：仅在 init(id:…:capabilities:) 里做归一化不够——
    // 用户手改 `config-v2.json`（如 `"capabilities":["toolCalling","promptCaching","toolCalling"]`）
    // 直接走自动合成的 decoder 会保留重复/乱序，违反"JSON 数组顺序稳定 + Set 语义"承诺。
    // 本版手写 `init(from:)` 在解码时跑同样的规范化；`encode(to:)` 走自动合成（因为 init 已保证 self.capabilities 有序无重）。

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, baseURL, apiKeyRef, defaultModel, capabilities
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decode(ProviderKind.self, forKey: .kind)
        self.name = try c.decode(String.self, forKey: .name)
        self.baseURL = try c.decodeIfPresent(URL.self, forKey: .baseURL)
        self.apiKeyRef = try c.decode(String.self, forKey: .apiKeyRef)
        self.defaultModel = try c.decode(String.self, forKey: .defaultModel)
        // 解码后同样做归一化，保证"外部 JSON 手改后 round-trip 结果稳定"
        let raw = try c.decode([ProviderCapability].self, forKey: .capabilities)
        self.capabilities = Array(Set(raw)).sorted { $0.rawValue < $1.rawValue }
    }
}

/// Provider 协议族
public enum ProviderKind: String, Sendable, Codable, CaseIterable {
    /// OpenAI Chat Completions 兼容（OpenAI / DeepSeek / Moonshot / OpenRouter / 自建中转）
    case openAICompatible
    /// Anthropic Messages API
    case anthropic
    /// Google Gemini API
    case gemini
    /// 本地 Ollama
    case ollama
}
```

注：本 struct 的 Codable 用 Swift 自动合成。所有字段都是标量或前面已手写 Codable 的类型（`ProviderKind` 是 raw-value enum、`URL?` 是标量、`[ProviderCapability]` 是 raw-value enum 数组），产物稳定。`capabilities` 已在 init 里排序并去重，所以 JSON 数组顺序稳定（评审 P2-3）。

- [ ] **Step 4: 运行测试**

Run: `cd SliceAIKit && swift test --filter V2ProviderTests`
Expected: 6/6 passed.

Run: `cd SliceAIKit && swift test --filter SliceCoreTests`
Expected: 全绿（`Provider.swift` 未改动，ConfigurationTests / DefaultConfigurationTests 等现有测试继续通过）。

- [ ] **Step 5: 整体 build**

Run: `cd SliceAIKit && swift build`
Expected: 全 10 个 target 编译成功。**关键验证**：LLMProviders / SettingsUI 未做任何改动，它们仍消费 `Provider`（非 optional baseURL）。

- [ ] **Step 6: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/V2Provider.swift --strict`
Expected: 0 violations.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/V2Provider.swift \
        SliceAIKit/Tests/SliceCoreTests/V2ProviderTests.swift
git commit -m "feat(core): add V2Provider as independent v2 type

V2Provider is a new struct with baseURL: URL? (allowing nil for Anthropic /
Gemini protocol families), ProviderKind enum, and Set<ProviderCapability>.
The existing Provider struct is untouched, so LLMProviders, SettingsUI, and
DefaultConfiguration continue to compile without changes. M3 will perform a
one-time rename (delete Provider, rename V2Provider to Provider)."
```

---

## Task 13: Skill + MCPDescriptor 骨架

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/Skill.swift`
- Create: `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/SkillTests.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/MCPDescriptorTests.swift`

- [ ] **Step 1: 写 Skill 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/SkillTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class SkillTests: XCTestCase {

    func test_skillManifest_codable() throws {
        let m = SkillManifest(
            name: "English Tutor",
            description: "Grammar + rewrite",
            version: "1.0.0",
            triggers: ["selection.language == en"],
            requiredCapabilities: [.toolCalling, .vision]
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(SkillManifest.self, from: data)
        XCTAssertEqual(m, decoded)
    }

    func test_skillReference_codable() throws {
        let r = SkillReference(id: "english-tutor@1.0.0", pinVersion: "1.0.0")
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(SkillReference.self, from: data)
        XCTAssertEqual(r, decoded)
    }

    func test_skillReference_nilPin() throws {
        let r = SkillReference(id: "english-tutor@1.0.0", pinVersion: nil)
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(SkillReference.self, from: data)
        XCTAssertEqual(r, decoded)
    }

    func test_skill_carriesProvenance() {
        let url = URL(fileURLWithPath: "/tmp/english-tutor")
        let s = Skill(
            id: "english-tutor@1.0.0",
            path: url,
            manifest: SkillManifest(name: "t", description: "d", version: "1.0.0", triggers: [], requiredCapabilities: []),
            resources: [],
            provenance: .firstParty
        )
        XCTAssertEqual(s.provenance, .firstParty)
    }
}
```

- [ ] **Step 2: 写 MCPDescriptor 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/MCPDescriptorTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class MCPDescriptorTests: XCTestCase {

    func test_stdio_descriptor_codable() throws {
        let d = MCPDescriptor(
            id: "postgres",
            transport: .stdio,
            command: "npx",
            args: ["-y", "@modelcontextprotocol/server-postgres", "postgresql://localhost"],
            url: nil,
            env: ["PGUSER": "me"],
            capabilities: [.tools(["query", "schema"])],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 100))
        )
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(MCPDescriptor.self, from: data)
        XCTAssertEqual(d, decoded)
    }

    func test_sse_descriptor_codable() throws {
        let d = MCPDescriptor(
            id: "remote-mcp",
            transport: .sse,
            command: nil,
            args: nil,
            url: URL(string: "https://mcp.example.com/events"),
            env: nil,
            capabilities: [],
            provenance: .firstParty
        )
        let data = try JSONEncoder().encode(d)
        let decoded = try JSONDecoder().decode(MCPDescriptor.self, from: data)
        XCTAssertEqual(d, decoded)
    }

    func test_mcpToolRef_hashable_forSet() {
        let a = MCPToolRef(server: "s", tool: "t")
        let b = MCPToolRef(server: "s", tool: "t")
        XCTAssertEqual(Set([a, b]).count, 1)
    }

    func test_mcpCapability_tools_codable() throws {
        let cap = MCPCapability.tools(["a", "b"])
        let data = try JSONEncoder().encode(cap)
        let decoded = try JSONDecoder().decode(MCPCapability.self, from: data)
        XCTAssertEqual(cap, decoded)
    }

    // MARK: - Golden JSON shape（模板 D）

    func test_mcpCapability_goldenJSON_tools_directArray() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(MCPCapability.tools(["query", "schema"])), encoding: .utf8))
        XCTAssertEqual(json, #"{"tools":["query","schema"]}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_mcpCapability_goldenJSON_resources_directArray() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(MCPCapability.resources(["/a", "/b"])), encoding: .utf8))
        XCTAssertEqual(json, #"{"resources":["\/a","\/b"]}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }
}
```

- [ ] **Step 3: 运行看失败**

Run: `cd SliceAIKit && swift test --filter SkillTests --filter MCPDescriptorTests`
Expected: FAIL.

- [ ] **Step 4: 实现 Skill.swift**

Create `SliceAIKit/Sources/SliceCore/Skill.swift`:

```swift
import Foundation

/// 本地 skill 资源；对应 `~/Library/Application Support/SliceAI/skills/<skill-id>/`
///
/// M1 只落数据模型；真正的 `SkillRegistry`（扫描目录、解析 SKILL.md、加载资源）在 Phase 2。
public struct Skill: Identifiable, Sendable, Codable, Equatable {
    /// 如 "english-tutor@1.2.0"
    public let id: String
    /// 本地 skill 目录路径
    public let path: URL
    /// 从 SKILL.md frontmatter 解析出的 manifest
    public var manifest: SkillManifest
    /// 资源文件列表（图片 / CSV / reference MD 等）
    public var resources: [SkillResource]
    /// 信任来源；安装流程写入，运行时只读
    public var provenance: Provenance

    /// 构造 Skill
    public init(id: String, path: URL, manifest: SkillManifest, resources: [SkillResource], provenance: Provenance) {
        self.id = id
        self.path = path
        self.manifest = manifest
        self.resources = resources
        self.provenance = provenance
    }
}

/// SKILL.md frontmatter 解析结果
public struct SkillManifest: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let version: String
    /// 激活条件（表达式字符串，Phase 2 解析）
    public let triggers: [String]
    /// 需要的 Provider 能力
    public let requiredCapabilities: [ProviderCapability]

    /// 构造 SkillManifest
    public init(name: String, description: String, version: String, triggers: [String], requiredCapabilities: [ProviderCapability]) {
        self.name = name
        self.description = description
        self.version = version
        self.triggers = triggers
        self.requiredCapabilities = requiredCapabilities
    }
}

/// Skill 资源描述
public struct SkillResource: Sendable, Codable, Equatable {
    /// 相对 skill 根的路径
    public let relativePath: String
    /// MIME 类型
    public let mimeType: String

    /// 构造 SkillResource
    public init(relativePath: String, mimeType: String) {
        self.relativePath = relativePath
        self.mimeType = mimeType
    }
}

/// Tool 引用 Skill 的方式
public struct SkillReference: Sendable, Codable, Equatable {
    /// 指向 SkillRegistry 的 id
    public let id: String
    /// 可选锁定版本；nil 时跟随 registry 最新
    public let pinVersion: String?

    /// 构造 SkillReference
    public init(id: String, pinVersion: String?) {
        self.id = id
        self.pinVersion = pinVersion
    }
}
```

- [ ] **Step 5: 实现 MCPDescriptor.swift**

Create `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`:

```swift
import Foundation

/// MCP server 配置描述；`mcp.json` 中一条记录对应一个 MCPDescriptor
///
/// 兼容 Claude Desktop `mcpServers` 格式：stdio 下填 `command + args + env`；
/// SSE / WebSocket 下填 `url`。Phase 1 的 `MCPClient` 消费此结构启动 / 连接 server。
///
/// `provenance` 由安装流程写入；`.unknown` 来源的 MCPDescriptor 在**安装流程入口**被拒绝，
/// 不会被构造出来（D-23 / §3.9.4.2）。
public struct MCPDescriptor: Identifiable, Sendable, Codable, Equatable {
    /// 本地注册名
    public let id: String
    /// 传输方式
    public let transport: MCPTransport
    /// stdio 的命令（如 `npx` / `node` / `python`）；非 stdio 时 nil
    public let command: String?
    /// stdio 的命令参数；非 stdio 时 nil
    public let args: [String]?
    /// SSE / WebSocket 端点；stdio 时 nil
    public let url: URL?
    /// 环境变量；stdio 用于 `ProcessInfo.processEnv`
    public let env: [String: String]?
    /// 声明能提供的能力
    public let capabilities: [MCPCapability]
    /// 信任来源（仅 `.firstParty` / `.communitySigned` / `.selfManaged`；不可为 `.unknown`）
    public var provenance: Provenance

    /// 构造 MCPDescriptor
    public init(
        id: String,
        transport: MCPTransport,
        command: String?,
        args: [String]?,
        url: URL?,
        env: [String: String]?,
        capabilities: [MCPCapability],
        provenance: Provenance
    ) {
        self.id = id
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.env = env
        self.capabilities = capabilities
        self.provenance = provenance
    }
}

/// MCP 传输方式
public enum MCPTransport: String, Sendable, Codable, CaseIterable {
    case stdio
    case sse
    case websocket
}

/// MCP server 能力声明
///
/// **手写 Codable（模板 C）**：三 case 都是 `[String]`，直接 encode 数组
public enum MCPCapability: Sendable, Equatable, Codable {
    case tools([String])
    case resources([String])
    case prompts([String])

    private enum CodingKeys: String, CodingKey { case tools, resources, prompts }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let a = try c.decodeIfPresent([String].self, forKey: .tools)     { self = .tools(a); return }
        if let a = try c.decodeIfPresent([String].self, forKey: .resources) { self = .resources(a); return }
        if let a = try c.decodeIfPresent([String].self, forKey: .prompts)   { self = .prompts(a); return }
        throw DecodingError.dataCorruptedError(forKey: CodingKeys.tools, in: c,
            debugDescription: "MCPCapability requires one of: tools, resources, prompts")
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tools(let a):     try c.encode(a, forKey: .tools)
        case .resources(let a): try c.encode(a, forKey: .resources)
        case .prompts(let a):   try c.encode(a, forKey: .prompts)
        }
    }
}
```

- [ ] **Step 6: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter SkillTests --filter MCPDescriptorTests`
Expected: SkillTests 4/4、MCPDescriptorTests 4/4 passed.

- [ ] **Step 7: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/Skill.swift SliceAIKit/Sources/SliceCore/MCPDescriptor.swift --strict`
Expected: 0 violations.

- [ ] **Step 8: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/Skill.swift \
        SliceAIKit/Sources/SliceCore/MCPDescriptor.swift \
        SliceAIKit/Tests/SliceCoreTests/SkillTests.swift \
        SliceAIKit/Tests/SliceCoreTests/MCPDescriptorTests.swift
git commit -m "feat(core): add Skill and MCPDescriptor data models

Skill mirrors Anthropic's skill manifest layout with a SliceAI provenance
field. MCPDescriptor carries stdio / SSE / websocket config compatible with
Claude Desktop's mcpServers JSON format. Both models ship as data-only in
M1; SkillRegistry lands in Phase 2, MCPClient in Phase 1."
```

---

## Task 14: ToolBudget + ToolMatcher + ToolKind + Prompt/Agent/Pipeline sub-types

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ToolBudget.swift`
- Create: `SliceAIKit/Sources/SliceCore/ToolMatcher.swift`
- Create: `SliceAIKit/Sources/SliceCore/ToolKind.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`

- [ ] **Step 1: 写 ToolKind 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ToolKindTests: XCTestCase {

    // MARK: - PromptTool

    func test_promptTool_codable_roundtrip() throws {
        let pt = PromptTool(
            systemPrompt: "You are an editor.",
            userPrompt: "Polish: {{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai", modelId: "gpt-5"),
            temperature: 0.4,
            maxTokens: 1000,
            variables: ["tone": "formal"]
        )
        let data = try JSONEncoder().encode(pt)
        let decoded = try JSONDecoder().decode(PromptTool.self, from: data)
        XCTAssertEqual(pt, decoded)
    }

    // MARK: - AgentTool

    func test_agentTool_codable_roundtrip() throws {
        let at = AgentTool(
            systemPrompt: "agent sys",
            initialUserPrompt: "{{selection}}",
            contexts: [],
            provider: .capability(requires: [.toolCalling], prefer: ["claude"]),
            skill: SkillReference(id: "english-tutor@1", pinVersion: nil),
            mcpAllowlist: [MCPToolRef(server: "anki", tool: "createNote")],
            builtinCapabilities: [.tts],
            maxSteps: 6,
            stopCondition: .finalAnswerProvided
        )
        let data = try JSONEncoder().encode(at)
        let decoded = try JSONDecoder().decode(AgentTool.self, from: data)
        XCTAssertEqual(at, decoded)
    }

    // MARK: - PipelineTool

    func test_pipelineTool_codable_roundtrip() throws {
        let pt = PipelineTool(
            steps: [
                .prompt(inline: PromptTool(
                    systemPrompt: nil, userPrompt: "Extract words: {{selection}}",
                    contexts: [],
                    provider: .fixed(providerId: "openai", modelId: nil),
                    temperature: nil, maxTokens: nil, variables: [:]
                ), input: "{{selection}}"),
                .mcp(ref: MCPToolRef(server: "anki", tool: "createNote"), args: ["deck": "English"])
            ],
            onStepFail: .abort
        )
        let data = try JSONEncoder().encode(pt)
        let decoded = try JSONDecoder().decode(PipelineTool.self, from: data)
        XCTAssertEqual(pt, decoded)
    }

    // MARK: - ToolKind dispatch

    func test_toolKind_prompt_codable() throws {
        let kind = ToolKind.prompt(PromptTool(
            systemPrompt: nil, userPrompt: "t",
            contexts: [], provider: .fixed(providerId: "p", modelId: nil),
            temperature: nil, maxTokens: nil, variables: [:]
        ))
        let data = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(ToolKind.self, from: data)
        XCTAssertEqual(kind, decoded)
    }

    func test_toolKind_agent_codable() throws {
        let kind = ToolKind.agent(AgentTool(
            systemPrompt: nil, initialUserPrompt: "t",
            contexts: [], provider: .fixed(providerId: "p", modelId: nil),
            skill: nil, mcpAllowlist: [], builtinCapabilities: [],
            maxSteps: 3, stopCondition: .finalAnswerProvided
        ))
        let data = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(ToolKind.self, from: data)
        XCTAssertEqual(kind, decoded)
    }

    // MARK: - StopCondition

    func test_stopCondition_allCases() {
        XCTAssertEqual(Set(StopCondition.allCases), [.finalAnswerProvided, .maxStepsReached, .noToolCall])
    }

    // MARK: - ToolMatcher

    func test_toolMatcher_codable_allFieldsNil() throws {
        let m = ToolMatcher(appAllowlist: nil, appDenylist: nil, contentTypes: nil, languageAllowlist: nil, minLength: nil, maxLength: nil, regex: nil)
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(ToolMatcher.self, from: data)
        XCTAssertEqual(m, decoded)
    }

    func test_toolMatcher_codable_fullFields() throws {
        let m = ToolMatcher(
            appAllowlist: ["com.apple.Safari"],
            appDenylist: nil,
            contentTypes: [.prose, .code],
            languageAllowlist: ["en"],
            minLength: 5,
            maxLength: 5000,
            regex: "^[A-Za-z]+$"
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(ToolMatcher.self, from: data)
        XCTAssertEqual(m, decoded)
    }

    // MARK: - ToolBudget

    func test_toolBudget_codable() throws {
        let b = ToolBudget(dailyUSD: 0.5, perCallUSD: 0.02)
        let data = try JSONEncoder().encode(b)
        let decoded = try JSONDecoder().decode(ToolBudget.self, from: data)
        XCTAssertEqual(b, decoded)
    }

    // MARK: - Golden JSON shape（模板 D；ToolKind / PipelineStep / TransformOp）

    func test_toolKind_goldenJSON_prompt_usesSingleKeyDiscriminator() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let kind = ToolKind.prompt(PromptTool(
            systemPrompt: nil, userPrompt: "u", contexts: [],
            provider: .fixed(providerId: "p", modelId: nil),
            temperature: nil, maxTokens: nil, variables: [:]
        ))
        let json = try XCTUnwrap(String(data: try enc.encode(kind), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"prompt":{"#), "got: \(json)")
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_toolKind_goldenJSON_agent_usesSingleKeyDiscriminator() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let kind = ToolKind.agent(AgentTool(
            systemPrompt: nil, initialUserPrompt: "x",
            contexts: [], provider: .fixed(providerId: "p", modelId: nil),
            skill: nil, mcpAllowlist: [], builtinCapabilities: [],
            maxSteps: 3, stopCondition: .finalAnswerProvided
        ))
        let json = try XCTUnwrap(String(data: try enc.encode(kind), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"agent":{"#), "got: \(json)")
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_pipelineStep_goldenJSON_mcp_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let step = PipelineStep.mcp(ref: MCPToolRef(server: "anki", tool: "createNote"), args: ["deck": "English"])
        let json = try XCTUnwrap(String(data: try enc.encode(step), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"mcp":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""server":"anki""#))
        XCTAssertTrue(json.contains(#""tool":"createNote""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_pipelineStep_goldenJSON_branch_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let step = PipelineStep.branch(condition: .isCode, onTrue: "a", onFalse: "b")
        let json = try XCTUnwrap(String(data: try enc.encode(step), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"branch":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""condition":{"isCode":{}}"#))
        XCTAssertTrue(json.contains(#""onFalse":"b""#))
        XCTAssertTrue(json.contains(#""onTrue":"a""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_transformOp_goldenJSON_jq_directString() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(TransformOp.jq(".items[]")), encoding: .utf8))
        XCTAssertEqual(json, #"{"jq":".items[]"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_transformOp_goldenJSON_regex_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(TransformOp.regex(pattern: "a", replacement: "b")), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"regex":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""pattern":"a""#))
        XCTAssertTrue(json.contains(#""replacement":"b""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter ToolKindTests`
Expected: FAIL.

- [ ] **Step 3: 实现 ToolBudget**

Create `SliceAIKit/Sources/SliceCore/ToolBudget.swift`:

```swift
import Foundation

/// Per-tool 成本上限；`CostAccounting`（Phase 0 M2）按此约束
public struct ToolBudget: Sendable, Codable, Equatable {
    /// 每日 USD 上限；nil 表示不限
    public let dailyUSD: Double?
    /// 单次调用 USD 上限；nil 表示不限
    public let perCallUSD: Double?

    /// 构造 ToolBudget
    public init(dailyUSD: Double?, perCallUSD: Double?) {
        self.dailyUSD = dailyUSD
        self.perCallUSD = perCallUSD
    }
}
```

- [ ] **Step 4: 实现 ToolMatcher**

Create `SliceAIKit/Sources/SliceCore/ToolMatcher.swift`:

```swift
import Foundation

/// Tool 可见性过滤器；UI 在渲染浮条 / 面板前按此过滤
///
/// 所有字段均可 nil（表示"不设约束"）。多字段同时存在时取 AND：
/// 比如 `appAllowlist + languageAllowlist` 要同时满足才显示。
public struct ToolMatcher: Sendable, Codable, Equatable {
    /// 只在这些 bundleId 下显示；nil 表示所有
    public let appAllowlist: [String]?
    /// 排除这些 bundleId；nil 表示无排除
    public let appDenylist: [String]?
    /// 只对这些内容类型显示；nil 表示所有
    public let contentTypes: [SelectionContentType]?
    /// 只对这些语言显示（BCP-47）；nil 表示所有
    public let languageAllowlist: [String]?
    /// 选区最小长度；nil 表示不限
    public let minLength: Int?
    /// 选区最大长度；nil 表示不限
    public let maxLength: Int?
    /// 正则匹配选区；nil 表示不做正则过滤
    public let regex: String?

    /// 构造 ToolMatcher
    public init(
        appAllowlist: [String]?,
        appDenylist: [String]?,
        contentTypes: [SelectionContentType]?,
        languageAllowlist: [String]?,
        minLength: Int?,
        maxLength: Int?,
        regex: String?
    ) {
        self.appAllowlist = appAllowlist
        self.appDenylist = appDenylist
        self.contentTypes = contentTypes
        self.languageAllowlist = languageAllowlist
        self.minLength = minLength
        self.maxLength = maxLength
        self.regex = regex
    }
}
```

- [ ] **Step 5: 实现 ToolKind + 三个子类型**

Create `SliceAIKit/Sources/SliceCore/ToolKind.swift`:

```swift
import Foundation

/// Tool 的三种执行形态；数据模型的封闭集合（新形态通过 Pipeline 组合，不加第四态）
///
/// **手写 Codable（模板 A）**：产出 `{"prompt":{...}}` / `{"agent":{...}}` / `{"pipeline":{...}}`
/// —— 不使用 Swift 合成的 `_0` 形式。所有三态 case 的 associated value 已经是 struct，
/// 所以直接 encode payload 即可（无需嵌套 Repr）。
public enum ToolKind: Sendable, Equatable, Codable {
    /// 单次 LLM 调用（v1 默认形态）
    case prompt(PromptTool)
    /// LLM + MCP + skill 的 ReAct loop
    case agent(AgentTool)
    /// 多 step 编排；每个 step 可再调 tool / prompt / mcp / transform
    case pipeline(PipelineTool)

    private enum CodingKeys: String, CodingKey { case prompt, agent, pipeline }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let p = try c.decodeIfPresent(PromptTool.self, forKey: .prompt) {
            self = .prompt(p); return
        }
        if let a = try c.decodeIfPresent(AgentTool.self, forKey: .agent) {
            self = .agent(a); return
        }
        if let p = try c.decodeIfPresent(PipelineTool.self, forKey: .pipeline) {
            self = .pipeline(p); return
        }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.prompt, in: c,
            debugDescription: "ToolKind requires exactly one of: prompt, agent, pipeline"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .prompt(let p):   try c.encode(p, forKey: .prompt)
        case .agent(let a):    try c.encode(a, forKey: .agent)
        case .pipeline(let p): try c.encode(p, forKey: .pipeline)
        }
    }
}

/// 单次 LLM 调用配置
public struct PromptTool: Sendable, Codable, Equatable {
    public var systemPrompt: String?
    public var userPrompt: String
    public var contexts: [ContextRequest]
    public var provider: ProviderSelection
    public var temperature: Double?
    public var maxTokens: Int?
    public var variables: [String: String]

    /// 构造 PromptTool
    public init(
        systemPrompt: String?,
        userPrompt: String,
        contexts: [ContextRequest],
        provider: ProviderSelection,
        temperature: Double?,
        maxTokens: Int?,
        variables: [String: String]
    ) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.contexts = contexts
        self.provider = provider
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.variables = variables
    }
}

/// Agentic 循环配置
public struct AgentTool: Sendable, Codable, Equatable {
    public var systemPrompt: String?
    public var initialUserPrompt: String
    public var contexts: [ContextRequest]
    public var provider: ProviderSelection
    public var skill: SkillReference?
    public var mcpAllowlist: [MCPToolRef]
    public var builtinCapabilities: [BuiltinCapability]
    public var maxSteps: Int
    public var stopCondition: StopCondition

    /// 构造 AgentTool
    public init(
        systemPrompt: String?,
        initialUserPrompt: String,
        contexts: [ContextRequest],
        provider: ProviderSelection,
        skill: SkillReference?,
        mcpAllowlist: [MCPToolRef],
        builtinCapabilities: [BuiltinCapability],
        maxSteps: Int,
        stopCondition: StopCondition
    ) {
        self.systemPrompt = systemPrompt
        self.initialUserPrompt = initialUserPrompt
        self.contexts = contexts
        self.provider = provider
        self.skill = skill
        self.mcpAllowlist = mcpAllowlist
        self.builtinCapabilities = builtinCapabilities
        self.maxSteps = maxSteps
        self.stopCondition = stopCondition
    }
}

/// Pipeline 工作流配置
public struct PipelineTool: Sendable, Codable, Equatable {
    public var steps: [PipelineStep]
    public var onStepFail: StepFailurePolicy

    /// 构造 PipelineTool
    public init(steps: [PipelineStep], onStepFail: StepFailurePolicy) {
        self.steps = steps
        self.onStepFail = onStepFail
    }
}

/// Pipeline 单个 step
///
/// **手写 Codable（模板 A + B）**：多 associated value 的 case 用嵌套 Repr struct 做中转。
public enum PipelineStep: Sendable, Equatable, Codable {
    case tool(toolRef: String, input: String)
    case prompt(inline: PromptTool, input: String)
    case mcp(ref: MCPToolRef, args: [String: String])
    case transform(TransformOp)
    case branch(condition: ConditionExpr, onTrue: String, onFalse: String)

    private enum CodingKeys: String, CodingKey { case tool, prompt, mcp, transform, branch }
    private struct ToolRepr: Codable, Equatable { let toolRef: String; let input: String }
    private struct PromptRepr: Codable, Equatable { let inline: PromptTool; let input: String }
    private struct MCPRepr: Codable, Equatable { let ref: MCPToolRef; let args: [String: String] }
    private struct BranchRepr: Codable, Equatable { let condition: ConditionExpr; let onTrue: String; let onFalse: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let r = try c.decodeIfPresent(ToolRepr.self, forKey: .tool) {
            self = .tool(toolRef: r.toolRef, input: r.input); return
        }
        if let r = try c.decodeIfPresent(PromptRepr.self, forKey: .prompt) {
            self = .prompt(inline: r.inline, input: r.input); return
        }
        if let r = try c.decodeIfPresent(MCPRepr.self, forKey: .mcp) {
            self = .mcp(ref: r.ref, args: r.args); return
        }
        if let op = try c.decodeIfPresent(TransformOp.self, forKey: .transform) {
            self = .transform(op); return
        }
        if let r = try c.decodeIfPresent(BranchRepr.self, forKey: .branch) {
            self = .branch(condition: r.condition, onTrue: r.onTrue, onFalse: r.onFalse); return
        }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.tool, in: c,
            debugDescription: "PipelineStep requires one of: tool, prompt, mcp, transform, branch"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tool(let toolRef, let input):
            try c.encode(ToolRepr(toolRef: toolRef, input: input), forKey: .tool)
        case .prompt(let inline, let input):
            try c.encode(PromptRepr(inline: inline, input: input), forKey: .prompt)
        case .mcp(let ref, let args):
            try c.encode(MCPRepr(ref: ref, args: args), forKey: .mcp)
        case .transform(let op):
            try c.encode(op, forKey: .transform)
        case .branch(let condition, let onTrue, let onFalse):
            try c.encode(BranchRepr(condition: condition, onTrue: onTrue, onFalse: onFalse), forKey: .branch)
        }
    }
}

/// Pipeline 失败策略
public enum StepFailurePolicy: String, Sendable, Codable, CaseIterable {
    /// 任一 step 失败 → Pipeline 直接失败
    case abort
    /// 失败 step 跳过，继续下一 step
    case skip
}

/// Agent 停止条件
public enum StopCondition: String, Sendable, Codable, CaseIterable {
    /// LLM 返回 finalAnswer（finish_reason == stop 且无 tool call）
    case finalAnswerProvided
    /// 达到 maxSteps
    case maxStepsReached
    /// 某一轮 LLM 未发起 tool call（视作 agent 认为已答完）
    case noToolCall
}

/// 内置能力引用；`AgentTool.builtinCapabilities` 使用
public enum BuiltinCapability: String, Sendable, Codable, CaseIterable {
    case filesystem
    case shell
    case vision
    case tts
    case memory
    case screen
}

/// Pipeline `transform` step 的操作类型；M1 只定义少量 case
///
/// **手写 Codable（模板 C + B）**
public enum TransformOp: Sendable, Equatable, Codable {
    case jq(String)
    case regex(pattern: String, replacement: String)
    case jsonPath(String)

    private enum CodingKeys: String, CodingKey { case jq, regex, jsonPath }
    private struct RegexRepr: Codable, Equatable { let pattern: String; let replacement: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let s = try c.decodeIfPresent(String.self, forKey: .jq) { self = .jq(s); return }
        if let r = try c.decodeIfPresent(RegexRepr.self, forKey: .regex) {
            self = .regex(pattern: r.pattern, replacement: r.replacement); return
        }
        if let s = try c.decodeIfPresent(String.self, forKey: .jsonPath) { self = .jsonPath(s); return }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.jq, in: c,
            debugDescription: "TransformOp requires one of: jq, regex, jsonPath"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .jq(let s):                      try c.encode(s, forKey: .jq)
        case .regex(let p, let r):            try c.encode(RegexRepr(pattern: p, replacement: r), forKey: .regex)
        case .jsonPath(let s):                try c.encode(s, forKey: .jsonPath)
        }
    }
}
```

- [ ] **Step 6: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter ToolKindTests`
Expected: 10/10 passed.

- [ ] **Step 7: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/ToolKind.swift SliceAIKit/Sources/SliceCore/ToolMatcher.swift SliceAIKit/Sources/SliceCore/ToolBudget.swift --strict`
Expected: 0 violations.

- [ ] **Step 8: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/ToolKind.swift \
        SliceAIKit/Sources/SliceCore/ToolMatcher.swift \
        SliceAIKit/Sources/SliceCore/ToolBudget.swift \
        SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift
git commit -m "feat(core): add ToolKind (prompt/agent/pipeline) and related types

Closes the v2 Tool data model: PromptTool mirrors v1 semantics, AgentTool
captures the ReAct + MCP + skill loop, PipelineTool composes multi-step
workflows. StopCondition / StepFailurePolicy / BuiltinCapability / TransformOp
enums lock the state space for ExecutionEngine (M2) to dispatch on."
```

---

## Task 15: V2Tool 独立新类型（不改现有 Tool）

> **评审修正（Codex 第五轮 P1-1 + P1-2）**：初版方案"原地改造 Tool 为三态 + v1 compat accessor"会让 `Tool.kind: ToolKind` 进入 `Configuration.tools` 的序列化路径；当 AppContainer 通过 `FileConfigurationStore.update(...)` 写配置时，v2 形状（嵌套 kind）会被写回 v1 `config.json`，**直接破坏 v1 原文件** —— 违反 "v1 原文件不动" DoD。
>
> **收敛**：不改 `Tool.swift`；新建**独立 v2 类型** `V2Tool.swift`。v1 `Tool` 继续被 `Configuration.tools` / ToolExecutor / ToolEditorView / DefaultConfiguration 消费；`V2Tool` 只出现在 migrator / V2Configuration / V2ConfigurationStore 的序列化路径；两种类型互不相识，**没有** v1 compat accessor、**没有** assertionFailure 风险。M3 rename 时统一。

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/V2Tool.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/V2ToolTests.swift`
- **不修改** `SliceAIKit/Sources/SliceCore/Tool.swift`
- **不修改** `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift`

- [ ] **Step 1: 写 V2Tool 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/V2ToolTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class V2ToolTests: XCTestCase {

    // MARK: - v2 主路径：V2Tool 的三态 kind

    func test_v2tool_init_promptKind() {
        let tool = V2Tool(
            id: "translate",
            name: "Translate",
            icon: "🌐",
            description: "Translate",
            kind: .prompt(PromptTool(
                systemPrompt: "sys", userPrompt: "u",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
                temperature: 0.3, maxTokens: nil, variables: ["language": "zh"]
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
        if case .prompt(let p) = tool.kind {
            XCTAssertEqual(p.userPrompt, "u")
        } else {
            XCTFail("expected .prompt kind")
        }
        XCTAssertEqual(tool.provenance, .firstParty)
    }

    // MARK: - 三态 kind 分别构造与 round-trip

    func test_v2tool_init_agentKind() {
        let tool = V2Tool(
            id: "grammar-tutor", name: "Grammar Tutor", icon: "📝", description: nil,
            kind: .agent(AgentTool(
                systemPrompt: "agentSys", initialUserPrompt: "{{selection}}",
                contexts: [],
                provider: .capability(requires: [.toolCalling], prefer: ["claude"]),
                skill: nil, mcpAllowlist: [], builtinCapabilities: [],
                maxSteps: 6, stopCondition: .finalAnswerProvided
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        if case .agent(let a) = tool.kind {
            XCTAssertEqual(a.maxSteps, 6)
        } else {
            XCTFail("expected .agent")
        }
    }

    func test_v2tool_codable_roundtrip_promptKind() throws {
        let tool = V2Tool(
            id: "t", name: "n", icon: "i", description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: nil, userPrompt: "u", contexts: [],
                provider: .fixed(providerId: "p", modelId: nil),
                temperature: 0.3, maxTokens: nil, variables: [:]
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(V2Tool.self, from: data)
        XCTAssertEqual(tool, decoded)
    }

    func test_v2tool_codable_roundtrip_agentKind_preservesKind() throws {
        let original = V2Tool(
            id: "t", name: "n", icon: "i", description: nil,
            kind: .agent(AgentTool(
                systemPrompt: nil, initialUserPrompt: "x",
                contexts: [],
                provider: .fixed(providerId: "p", modelId: nil),
                skill: nil, mcpAllowlist: [], builtinCapabilities: [],
                maxSteps: 3, stopCondition: .finalAnswerProvided
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(V2Tool.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Golden JSON shape（锁定 canonical schema，避免 Swift 自动合成 _0 等实现细节泄漏）

    func test_v2tool_goldenJSON_promptKind_usesKindDiscriminator() throws {
        let tool = V2Tool(
            id: "t", name: "n", icon: "🌐", description: "d",
            kind: .prompt(PromptTool(
                systemPrompt: nil, userPrompt: "u", contexts: [],
                provider: .fixed(providerId: "p", modelId: nil),
                temperature: nil, maxTokens: nil, variables: [:]
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(tool)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // 锁定 canonical shape：kind 的 discriminator + payload 结构可人工可读
        XCTAssertTrue(json.contains("\"kind\":{\"prompt\":{"), "kind should use named case discriminator, got: \(json)")
        // 不允许 Swift 合成的 "_0" 泄漏
        XCTAssertFalse(json.contains("\"_0\""), "canonical JSON must not contain synthesized _0; got: \(json)")
        // Provenance 也是 discriminator 形式
        XCTAssertTrue(json.contains("\"provenance\":\"firstParty\"") || json.contains("\"provenance\":{\"firstParty\""), "provenance unexpected shape")
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter V2ToolTests`
Expected: FAIL（`V2Tool` 不存在）。

- [ ] **Step 3: 实现 V2Tool.swift（独立新类型，不改 Tool.swift）**

Create `SliceAIKit/Sources/SliceCore/V2Tool.swift`:

```swift
import Foundation

/// v2 工具定义（独立新类型；现有 `Tool` 保持 v1 形状不变）
///
/// `V2Tool` 是 canonical v2 数据模型：三态 kind（prompt/agent/pipeline）+ provenance +
/// permissions + outputBinding + visibleWhen + budget + hotkey + tags。
///
/// **不**与 v1 `Tool` 共享 Codable：v1 JSON 由旧 `Tool` 读写、v2 JSON 由 `V2Tool` 读写；
/// migrator 是唯一的 v1 → v2 转换路径。
///
/// **没有** v1 兼容 accessor（systemPrompt / userPrompt / providerId / modelId / temperature / variables）——
/// ToolEditorView / ToolExecutor 继续消费现有 `Tool` 类型；访问 V2Tool 字段必须通过 `kind` 的
/// pattern matching 或专用 kind-aware 编辑器（M3+ 引入）。
///
/// M3 的 rename pass 会：
/// 1. 删除现有 `Tool.swift`
/// 2. 把本文件重命名为 `Tool.swift`、类型改名为 `Tool`
/// 3. 同步改 ToolExecutor / ToolEditorView / DefaultConfiguration 等所有引用
public struct V2Tool: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var name: String
    public var icon: String
    public var description: String?
    public var kind: ToolKind
    public var visibleWhen: ToolMatcher?
    public var displayMode: PresentationMode
    public var outputBinding: OutputBinding?
    public var permissions: [Permission]
    public var provenance: Provenance
    public var budget: ToolBudget?
    public var hotkey: String?
    public var labelStyle: ToolLabelStyle
    public var tags: [String]

    /// v2 主初始化器
    public init(
        id: String,
        name: String,
        icon: String,
        description: String?,
        kind: ToolKind,
        visibleWhen: ToolMatcher?,
        displayMode: PresentationMode,
        outputBinding: OutputBinding?,
        permissions: [Permission],
        provenance: Provenance,
        budget: ToolBudget?,
        hotkey: String?,
        labelStyle: ToolLabelStyle,
        tags: [String]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.kind = kind
        self.visibleWhen = visibleWhen
        self.displayMode = displayMode
        self.outputBinding = outputBinding
        self.permissions = permissions
        self.provenance = provenance
        self.budget = budget
        self.hotkey = hotkey
        self.labelStyle = labelStyle
        self.tags = tags
    }

    // Codable 自动合成；Task 14 的 ToolKind 提供手写 Codable 保证 `{"kind":{"prompt":{...}}}` 稳定 shape（无 _0）
}
```

注：`V2Tool` 本身 struct 字段都是 Codable 标量（枚举 / 集合 / 基础类型），Swift 合成 Codable 的产物可预测；不确定的是 **`ToolKind` 这个 associated-value enum**——见 Task 14 的 golden JSON 测试。

- [ ] **Step 4: 运行测试**

Run: `cd SliceAIKit && swift test --filter V2ToolTests`
Expected: 4/4 passed.

Run: `cd SliceAIKit && swift test --filter SliceCoreTests`
Expected: 全绿（`Tool.swift` / `ToolTests.swift` 未改动，原 v1 Tool 测试继续通过）。

- [ ] **Step 5: 整体 build**

Run: `cd SliceAIKit && swift build`
Expected: 全 10 个 target 编译成功。**关键验证**：ToolEditorView / ToolExecutor / DefaultConfiguration 未做任何改动，它们仍消费 v1 `Tool`（扁平字段）。

- [ ] **Step 6: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/V2Tool.swift --strict`
Expected: 0 violations.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/V2Tool.swift \
        SliceAIKit/Tests/SliceCoreTests/V2ToolTests.swift
git commit -m "feat(core): add V2Tool as independent v2 type

V2Tool is a new canonical struct with three-state kind (prompt/agent/pipeline)
and all v2 fields (provenance, permissions, outputBinding, visibleWhen, budget,
hotkey, tags). The existing Tool struct is untouched, so ToolExecutor,
ToolEditorView, DefaultConfiguration continue to compile without changes.
Golden JSON tests lock the canonical schema (kind discriminator, no _0 leaks).
M3 will perform a one-time rename (delete Tool, rename V2Tool to Tool)."
```

---

## Task 16: LegacyConfigV1 snapshot struct

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/LegacyConfigV1.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/LegacyConfigV1Tests.swift`

用途：migrator 从磁盘读 v1 `config.json` 时**不经过 v2 Tool/Provider 的 Codable**，避免宽松解码掩盖字段遗漏。独立的 `LegacyConfigV1` 结构精确匹配 v1 schema，decode 后由 migrator 显式映射到 v2 类型。

- [ ] **Step 1: 写失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/LegacyConfigV1Tests.swift`:

```swift
import XCTest
@testable import SliceCore

final class LegacyConfigV1Tests: XCTestCase {

    func test_decode_minimalV1Config() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "providers": [
            {
              "id": "openai-official",
              "name": "OpenAI",
              "baseURL": "https://api.openai.com/v1",
              "apiKeyRef": "keychain:openai-official",
              "defaultModel": "gpt-5"
            }
          ],
          "tools": [
            {
              "id": "translate", "name": "Translate", "icon": "🌐",
              "systemPrompt": "sys", "userPrompt": "u",
              "providerId": "openai-official", "modelId": null, "temperature": 0.3,
              "displayMode": "window", "variables": {"language": "zh"}
            }
          ],
          "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {
            "floatingToolbarEnabled": true,
            "commandPaletteEnabled": true,
            "minimumSelectionLength": 1,
            "triggerDelayMs": 150
          },
          "telemetry": {"enabled": false},
          "appBlocklist": []
        }
        """#.data(using: .utf8)!

        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: json)
        XCTAssertEqual(v1.schemaVersion, 1)
        XCTAssertEqual(v1.providers.count, 1)
        XCTAssertEqual(v1.tools.count, 1)
        XCTAssertEqual(v1.tools[0].systemPrompt, "sys")
        XCTAssertEqual(v1.tools[0].userPrompt, "u")
        XCTAssertEqual(v1.tools[0].variables["language"], "zh")
    }

    func test_decode_v1WithOptionalFields() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "providers": [],
          "tools": [],
          "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {
            "floatingToolbarEnabled": true,
            "commandPaletteEnabled": true,
            "minimumSelectionLength": 1,
            "triggerDelayMs": 150,
            "floatingToolbarMaxTools": 8,
            "floatingToolbarSize": "regular",
            "floatingToolbarAutoDismissSeconds": 10
          },
          "telemetry": {"enabled": true},
          "appBlocklist": ["com.example.secrets"],
          "appearance": "dark"
        }
        """#.data(using: .utf8)!

        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: json)
        XCTAssertEqual(v1.triggers.floatingToolbarMaxTools, 8)
        XCTAssertEqual(v1.triggers.floatingToolbarSize, "regular")
        XCTAssertEqual(v1.triggers.floatingToolbarAutoDismissSeconds, 10)
        XCTAssertTrue(v1.telemetry.enabled)
        XCTAssertEqual(v1.appBlocklist, ["com.example.secrets"])
        XCTAssertEqual(v1.appearance, "dark")
    }

    func test_decode_v1WithLabelStyle() throws {
        let json = #"""
        {
          "schemaVersion": 1, "providers": [], "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {"floatingToolbarEnabled": true, "commandPaletteEnabled": true, "minimumSelectionLength": 1, "triggerDelayMs": 150},
          "telemetry": {"enabled": false}, "appBlocklist": [],
          "tools": [{
            "id": "t", "name": "n", "icon": "i",
            "systemPrompt": null, "userPrompt": "u",
            "providerId": "p", "modelId": null, "temperature": null,
            "displayMode": "window", "variables": {}, "labelStyle": "iconAndName"
          }]
        }
        """#.data(using: .utf8)!
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: json)
        XCTAssertEqual(v1.tools[0].labelStyle, "iconAndName")
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter LegacyConfigV1Tests`
Expected: FAIL `cannot find 'LegacyConfigV1' in scope`.

- [ ] **Step 3: 实现**

Create `SliceAIKit/Sources/SliceCore/LegacyConfigV1.swift`:

```swift
import Foundation

/// v1 `config.json` 的精确快照结构；**仅用于 ConfigMigratorV1ToV2**
///
/// 与 `Configuration` / `Tool` / `Provider` 的 v2 Codable 完全解耦——避免 v2 的
/// 宽松反序列化（`decodeIfPresent` 兜底）掩盖字段缺失。本结构要求 v1 必填字段严格存在，
/// 任何 decode 失败都意味着 v1 JSON 本身破损或格式非 v1。
internal struct LegacyConfigV1: Decodable {
    let schemaVersion: Int
    let providers: [Provider]
    let tools: [Tool]
    let hotkeys: Hotkeys
    let triggers: Triggers
    let telemetry: Telemetry
    let appBlocklist: [String]
    let appearance: String?   // v1 后期加的可选字段

    struct Provider: Decodable {
        let id: String
        let name: String
        let baseURL: URL
        let apiKeyRef: String
        let defaultModel: String
    }

    struct Tool: Decodable {
        let id: String
        let name: String
        let icon: String
        let description: String?
        let systemPrompt: String?
        let userPrompt: String
        let providerId: String
        let modelId: String?
        let temperature: Double?
        let displayMode: String
        let variables: [String: String]
        let labelStyle: String?
    }

    struct Hotkeys: Decodable {
        let toggleCommandPalette: String
    }

    struct Triggers: Decodable {
        let floatingToolbarEnabled: Bool
        let commandPaletteEnabled: Bool
        let minimumSelectionLength: Int
        let triggerDelayMs: Int
        let floatingToolbarMaxTools: Int?
        let floatingToolbarSize: String?
        let floatingToolbarAutoDismissSeconds: Int?
    }

    struct Telemetry: Decodable {
        let enabled: Bool
    }
}
```

注：`internal` 保持此结构不对外暴露——它是 SliceCore 内部 migration 工具的私有细节。

- [ ] **Step 4: 运行看通过**

Run: `cd SliceAIKit && swift test --filter LegacyConfigV1Tests`
Expected: 3/3 passed.

- [ ] **Step 5: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/LegacyConfigV1.swift --strict`
Expected: 0 violations.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/LegacyConfigV1.swift \
        SliceAIKit/Tests/SliceCoreTests/LegacyConfigV1Tests.swift
git commit -m "feat(core): add LegacyConfigV1 snapshot struct for migration

LegacyConfigV1 exactly matches v1 config.json schema and is consumed only by
ConfigMigratorV1ToV2 (Task 17). Keeping it separate from v2 Configuration
Codable means migration cannot silently drop fields via decodeIfPresent
fallbacks; any v1 decode failure is a data integrity issue worth surfacing."
```

---

## Task 17: ConfigMigratorV1ToV2

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/ConfigMigratorV1ToV2Tests.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/Fixtures/config-v1-minimal.json`
- Create: `SliceAIKit/Tests/SliceCoreTests/Fixtures/config-v1-full.json`

- [ ] **Step 1: 准备 fixtures**

Create `SliceAIKit/Tests/SliceCoreTests/Fixtures/config-v1-minimal.json`:

```json
{
  "schemaVersion": 1,
  "providers": [
    {
      "id": "openai-official",
      "name": "OpenAI",
      "baseURL": "https://api.openai.com/v1",
      "apiKeyRef": "keychain:openai-official",
      "defaultModel": "gpt-5"
    }
  ],
  "tools": [
    {
      "id": "translate",
      "name": "Translate",
      "icon": "🌐",
      "description": "Translate selection",
      "systemPrompt": "You are a translator.",
      "userPrompt": "Translate to {{language}}:\n\n{{selection}}",
      "providerId": "openai-official",
      "modelId": null,
      "temperature": 0.3,
      "displayMode": "window",
      "variables": {"language": "Simplified Chinese"}
    }
  ],
  "hotkeys": {"toggleCommandPalette": "option+space"},
  "triggers": {
    "floatingToolbarEnabled": true,
    "commandPaletteEnabled": true,
    "minimumSelectionLength": 1,
    "triggerDelayMs": 150
  },
  "telemetry": {"enabled": false},
  "appBlocklist": ["com.apple.keychainaccess"]
}
```

Create `SliceAIKit/Tests/SliceCoreTests/Fixtures/config-v1-full.json`:

```json
{
  "schemaVersion": 1,
  "appearance": "dark",
  "providers": [
    {
      "id": "openai-official",
      "name": "OpenAI",
      "baseURL": "https://api.openai.com/v1",
      "apiKeyRef": "keychain:openai-official",
      "defaultModel": "gpt-5"
    },
    {
      "id": "deepseek",
      "name": "DeepSeek",
      "baseURL": "https://api.deepseek.com/v1",
      "apiKeyRef": "keychain:deepseek",
      "defaultModel": "deepseek-chat"
    }
  ],
  "tools": [
    {
      "id": "translate",
      "name": "Translate",
      "icon": "🌐",
      "description": "Translate",
      "systemPrompt": "sys",
      "userPrompt": "u",
      "providerId": "openai-official",
      "modelId": null,
      "temperature": 0.3,
      "displayMode": "window",
      "variables": {"language": "zh"},
      "labelStyle": "iconAndName"
    },
    {
      "id": "polish",
      "name": "Polish",
      "icon": "📝",
      "description": "Polish text",
      "systemPrompt": null,
      "userPrompt": "Polish: {{selection}}",
      "providerId": "deepseek",
      "modelId": "deepseek-reasoner",
      "temperature": null,
      "displayMode": "window",
      "variables": {}
    }
  ],
  "hotkeys": {"toggleCommandPalette": "option+shift+space"},
  "triggers": {
    "floatingToolbarEnabled": true,
    "commandPaletteEnabled": true,
    "minimumSelectionLength": 3,
    "triggerDelayMs": 200,
    "floatingToolbarMaxTools": 8,
    "floatingToolbarSize": "regular",
    "floatingToolbarAutoDismissSeconds": 0
  },
  "telemetry": {"enabled": true},
  "appBlocklist": ["com.1password.1password", "com.bitwarden.desktop"]
}
```

需要让 `SliceCoreTests` target 知道这些 fixture。参考 `LLMProvidersTests` 的 `resources: [.copy("Fixtures")]` 做法。

Modify `SliceAIKit/Package.swift` 的 `SliceCoreTests`：

```swift
.testTarget(name: "SliceCoreTests",
            dependencies: ["SliceCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: swiftSettings),
```

- [ ] **Step 2: 写 Migrator 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/ConfigMigratorV1ToV2Tests.swift`:

```swift
import XCTest
@testable import SliceCore

final class ConfigMigratorV1ToV2Tests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        guard let url else {
            XCTFail("fixture \(name).json not found")
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    // MARK: - Minimal v1

    func test_migrate_minimal_preservesProviderId() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.schemaVersion, 2)
        XCTAssertEqual(v2.providers.count, 1)
        XCTAssertEqual(v2.providers[0].id, "openai-official")
        XCTAssertEqual(v2.providers[0].kind, .openAICompatible)
        XCTAssertEqual(v2.providers[0].capabilities, [])
    }

    func test_migrate_minimal_toolToPromptKind() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.tools.count, 1)
        let tool = v2.tools[0]
        XCTAssertEqual(tool.id, "translate")
        XCTAssertEqual(tool.provenance, .firstParty)

        guard case .prompt(let pt) = tool.kind else {
            XCTFail("expected .prompt kind"); return
        }
        XCTAssertEqual(pt.systemPrompt, "You are a translator.")
        XCTAssertEqual(pt.userPrompt, "Translate to {{language}}:\n\n{{selection}}")
        XCTAssertEqual(pt.temperature, 0.3)
        XCTAssertEqual(pt.variables["language"], "Simplified Chinese")
        XCTAssertEqual(pt.provider, .fixed(providerId: "openai-official", modelId: nil))
    }

    func test_migrate_minimal_preservesHotkeys_andTriggers_defaults() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.hotkeys.toggleCommandPalette, "option+space")
        XCTAssertEqual(v2.triggers.floatingToolbarEnabled, true)
        XCTAssertEqual(v2.triggers.commandPaletteEnabled, true)
        XCTAssertEqual(v2.triggers.minimumSelectionLength, 1)
        XCTAssertEqual(v2.triggers.triggerDelayMs, 150)
        // v1 fixture 未提供这些字段 → 用 DefaultConfiguration 默认
        XCTAssertEqual(v2.triggers.floatingToolbarMaxTools, 6)
        XCTAssertEqual(v2.triggers.floatingToolbarSize, .compact)
        XCTAssertEqual(v2.triggers.floatingToolbarAutoDismissSeconds, 5)
    }

    func test_migrate_minimal_appearanceDefaultsAuto() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.appearance, .auto)
    }

    // MARK: - Full v1

    func test_migrate_full_preservesAllFields() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.schemaVersion, 2)
        XCTAssertEqual(v2.appearance, .dark)
        XCTAssertEqual(v2.providers.count, 2)
        XCTAssertEqual(v2.tools.count, 2)
        XCTAssertEqual(v2.triggers.triggerDelayMs, 200)
        XCTAssertEqual(v2.triggers.floatingToolbarMaxTools, 8)
        XCTAssertEqual(v2.triggers.floatingToolbarSize, .regular)
        XCTAssertEqual(v2.triggers.floatingToolbarAutoDismissSeconds, 0)
        XCTAssertTrue(v2.telemetry.enabled)
        XCTAssertEqual(v2.appBlocklist.count, 2)
        XCTAssertEqual(v2.hotkeys.toggleCommandPalette, "option+shift+space")
    }

    func test_migrate_full_preservesLabelStyle() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.tools[0].labelStyle, .iconAndName)
        XCTAssertEqual(v2.tools[1].labelStyle, .icon)
    }

    func test_migrate_full_nullFieldsPreserved() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        guard case .prompt(let polishPT) = v2.tools[1].kind else { XCTFail(); return }
        XCTAssertNil(polishPT.systemPrompt)
        XCTAssertNil(polishPT.temperature)
        XCTAssertEqual(polishPT.provider, .fixed(providerId: "deepseek", modelId: "deepseek-reasoner"))
    }

    func test_migrate_allTools_provenanceIsFirstParty() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)
        for tool in v2.tools {
            XCTAssertEqual(tool.provenance, .firstParty)
        }
    }

    func test_migrate_unknownPresentationModeFallsBackToWindow() throws {
        // 手工构造一个 v1 结构含非标 displayMode
        let badJSON = #"""
        {
          "schemaVersion": 1, "providers": [], "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {"floatingToolbarEnabled": true, "commandPaletteEnabled": true, "minimumSelectionLength": 1, "triggerDelayMs": 150},
          "telemetry": {"enabled": false}, "appBlocklist": [],
          "tools": [{
            "id": "t", "name": "n", "icon": "i",
            "systemPrompt": null, "userPrompt": "u",
            "providerId": "p", "modelId": null, "temperature": null,
            "displayMode": "nonexistent", "variables": {}
          }]
        }
        """#.data(using: .utf8)!
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: badJSON)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.tools[0].displayMode, .window)
    }
}
```

- [ ] **Step 3: 运行看失败**

Run: `cd SliceAIKit && swift test --filter ConfigMigratorV1ToV2Tests`
Expected: FAIL（`ConfigMigratorV1ToV2` 不存在；fixture bundle 访问失败若 `resources: [.copy("Fixtures")]` 未加上）。

- [ ] **Step 4: 实现 Migrator**

Create `SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift`:

```swift
import Foundation
import OSLog

private let migrationLog = Logger(subsystem: "com.sliceai.core", category: "ConfigMigration")

/// v1 → v2 配置迁移器
///
/// 纯函数转换；不做磁盘 IO。调用流程：
///   1. 调用方读 `config.json` 原文 → JSONDecode 为 `LegacyConfigV1`
///   2. `ConfigMigratorV1ToV2.migrate(v1)` 返回 `V2Configuration`
///   3. 调用方（V2ConfigurationStore）写入 `config-v2.json`
///
/// 迁移规则：
/// - v1 扁平 Tool → `V2Tool.kind = .prompt(PromptTool)`，provenance = `.firstParty`
/// - v1 Provider → `V2Provider`（kind=.openAICompatible, capabilities=[]）
/// - v1 可选 UI 字段缺失时 → 用 DefaultV2Configuration 默认
/// - v1 `displayMode` 解析失败 → 回退 `.window`
internal enum ConfigMigratorV1ToV2 {

    /// 执行迁移
    /// - Parameter v1: v1 配置快照
    /// - Returns: V2Configuration（独立 v2 类型）
    ///
    /// 访问控制说明（评审修正 Codex 第六轮 P1-2）：`LegacyConfigV1` 是 `internal`，
    /// 因此 `ConfigMigratorV1ToV2` 与 `migrate(_:)` 也必须是 `internal`——否则 Swift
    /// 会报"public API uses internal type"编译错误。M1 只有 SliceCore 内部与
    /// `@testable import SliceCore` 的测试需要访问；外部模块不直接调 migrator。
    internal static func migrate(_ v1: LegacyConfigV1) -> V2Configuration {
        let providers = v1.providers.map(migrateProvider)
        let tools = v1.tools.map(migrateTool)
        let hotkeys = HotkeyBindings(toggleCommandPalette: v1.hotkeys.toggleCommandPalette)
        let triggers = TriggerSettings(
            floatingToolbarEnabled: v1.triggers.floatingToolbarEnabled,
            commandPaletteEnabled: v1.triggers.commandPaletteEnabled,
            minimumSelectionLength: v1.triggers.minimumSelectionLength,
            triggerDelayMs: v1.triggers.triggerDelayMs,
            floatingToolbarMaxTools: v1.triggers.floatingToolbarMaxTools ?? 6,
            floatingToolbarSize: migrateToolbarSize(v1.triggers.floatingToolbarSize),
            floatingToolbarAutoDismissSeconds: v1.triggers.floatingToolbarAutoDismissSeconds ?? 5
        )
        let telemetry = TelemetrySettings(enabled: v1.telemetry.enabled)
        let appearance = migrateAppearance(v1.appearance)

        migrationLog.info("migrated v1 → v2: providers=\(providers.count, privacy: .public) tools=\(tools.count, privacy: .public)")

        return V2Configuration(
            schemaVersion: V2Configuration.currentSchemaVersion,
            providers: providers,
            tools: tools,
            hotkeys: hotkeys,
            triggers: triggers,
            telemetry: telemetry,
            appBlocklist: v1.appBlocklist,
            appearance: appearance
        )
    }

    // MARK: - Helpers

    /// v1 Provider → V2Provider
    private static func migrateProvider(_ v1p: LegacyConfigV1.Provider) -> V2Provider {
        V2Provider(
            id: v1p.id,
            kind: .openAICompatible,
            name: v1p.name,
            baseURL: v1p.baseURL,
            apiKeyRef: v1p.apiKeyRef,
            defaultModel: v1p.defaultModel,
            capabilities: []
        )
    }

    /// v1 Tool → V2Tool（.prompt kind + firstParty provenance）
    private static func migrateTool(_ v1t: LegacyConfigV1.Tool) -> V2Tool {
        let displayMode = PresentationMode(rawValue: v1t.displayMode) ?? .window
        if displayMode.rawValue != v1t.displayMode {
            migrationLog.warning("unknown displayMode '\(v1t.displayMode, privacy: .public)' in tool '\(v1t.id, privacy: .public)', falling back to window")
        }
        let labelStyle = ToolLabelStyle(rawValue: v1t.labelStyle ?? "icon") ?? .icon

        let pt = PromptTool(
            systemPrompt: v1t.systemPrompt,
            userPrompt: v1t.userPrompt,
            contexts: [],
            provider: .fixed(providerId: v1t.providerId, modelId: v1t.modelId),
            temperature: v1t.temperature,
            maxTokens: nil,
            variables: v1t.variables
        )

        return V2Tool(
            id: v1t.id,
            name: v1t.name,
            icon: v1t.icon,
            description: v1t.description,
            kind: .prompt(pt),
            visibleWhen: nil,
            displayMode: displayMode,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: labelStyle,
            tags: []
        )
    }

    private static func migrateToolbarSize(_ raw: String?) -> ToolbarSize {
        guard let raw, let size = ToolbarSize(rawValue: raw) else { return .compact }
        return size
    }

    private static func migrateAppearance(_ raw: String?) -> AppearanceMode {
        guard let raw, let mode = AppearanceMode(rawValue: raw) else { return .auto }
        return mode
    }
}
```

> **注意（评审修正 Codex 第五轮 P1-1）**：migrator 的返回类型从 `Configuration`（v1）改为 `V2Configuration`（独立 v2 类型）；调用方只能用 `V2ConfigurationStore.writeV2(_:)` 写入 v2 路径，**不存在**"把 V2Configuration 写到 v1 `config.json` 路径"的可能。

- [ ] **Step 5: 运行测试看通过**

Run: `cd SliceAIKit && swift test --filter ConfigMigratorV1ToV2Tests`
Expected: 9/9 passed.

若 `Bundle.module` 找不到 fixture：确保 Package.swift 的 SliceCoreTests 已加 `resources: [.copy("Fixtures")]`。

- [ ] **Step 6: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift --strict`
Expected: 0 violations.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift \
        SliceAIKit/Tests/SliceCoreTests/ConfigMigratorV1ToV2Tests.swift \
        SliceAIKit/Tests/SliceCoreTests/Fixtures/ \
        SliceAIKit/Package.swift
git commit -m "feat(core): add ConfigMigratorV1ToV2 pure-function migrator

Migrator consumes a LegacyConfigV1 snapshot and produces a v2 Configuration:
every v1 Tool becomes .prompt kind with .firstParty provenance; every v1
Provider gets kind=.openAICompatible and empty capabilities; missing optional
UI fields fall back to DefaultConfiguration defaults. Includes nine
fixture-driven tests covering minimal/full v1 payloads and edge cases
(unknown displayMode, null fields, labelStyle)."
```

---

## Task 18: V2Configuration + DefaultV2Configuration（独立类型；不改现有 Configuration）

> **评审修正（Codex 第五轮 P1-1）**：初版方案"把 `Configuration.currentSchemaVersion` 改为 2"会直接让真实 app 的 `FileConfigurationStore.save(...)` 写出 `schemaVersion: 2` 到 v1 `config.json` 路径——破坏 v1 原文件。**收敛**：`Configuration.swift` 原封不动（`currentSchemaVersion = 1`）；新建独立 `V2Configuration.swift` + `DefaultV2Configuration.swift`，只被 migrator / V2ConfigurationStore 消费。

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/V2Configuration.swift`
- Create: `SliceAIKit/Sources/SliceCore/DefaultV2Configuration.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationTests.swift`
- **不修改** `SliceAIKit/Sources/SliceCore/Configuration.swift`
- **不修改** `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`

- [ ] **Step 1: 写 V2Configuration 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class V2ConfigurationTests: XCTestCase {

    func test_v2Configuration_currentSchemaVersion_is2() {
        XCTAssertEqual(V2Configuration.currentSchemaVersion, 2)
    }

    func test_defaultV2Configuration_usesSchemaVersion2() {
        let cfg = DefaultV2Configuration.initial()
        XCTAssertEqual(cfg.schemaVersion, 2)
    }

    func test_defaultV2Configuration_hasFourPromptTools_firstPartyProvenance() {
        let cfg = DefaultV2Configuration.initial()
        XCTAssertEqual(cfg.tools.count, 4)
        for tool in cfg.tools {
            XCTAssertEqual(tool.provenance, .firstParty)
            guard case .prompt = tool.kind else {
                XCTFail("tool \(tool.id) is not .prompt kind"); continue
            }
        }
    }

    func test_defaultV2Configuration_providerIsOpenAICompatible() {
        let cfg = DefaultV2Configuration.initial()
        XCTAssertEqual(cfg.providers.count, 1)
        XCTAssertEqual(cfg.providers[0].kind, .openAICompatible)
    }

    func test_v2Configuration_roundtrip() throws {
        let cfg = DefaultV2Configuration.initial()
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(V2Configuration.self, from: data)
        XCTAssertEqual(cfg, decoded)
    }

    // 关键不变量：v1 Configuration 的 currentSchemaVersion 保持为 1
    func test_v1Configuration_currentSchemaVersion_unchanged() {
        XCTAssertEqual(Configuration.currentSchemaVersion, 1)
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter V2ConfigurationTests`
Expected: FAIL（`V2Configuration` / `DefaultV2Configuration` 不存在）。

- [ ] **Step 3: 实现 V2Configuration.swift**

Create `SliceAIKit/Sources/SliceCore/V2Configuration.swift`:

```swift
import Foundation

/// v2 应用配置聚合（独立新类型；现有 `Configuration` 保持 v1 形状，`currentSchemaVersion = 1`）
///
/// 由 `ConfigMigratorV1ToV2.migrate(_:)` 产出、由 `V2ConfigurationStore` 读写。
/// 真实 app 启动路径在 M1 阶段**不消费**此类型（它们仍用 v1 `Configuration`）。
///
/// M3 的 rename pass 会把本文件改名为 `Configuration.swift` 并删除旧 v1 `Configuration`。
public struct V2Configuration: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public var providers: [V2Provider]
    public var tools: [V2Tool]
    public var hotkeys: HotkeyBindings
    public var triggers: TriggerSettings
    public var telemetry: TelemetrySettings
    public var appBlocklist: [String]
    public var appearance: AppearanceMode

    /// 当前 v2 schema 版本
    public static let currentSchemaVersion = 2

    /// 构造 V2Configuration
    public init(
        schemaVersion: Int = V2Configuration.currentSchemaVersion,
        providers: [V2Provider],
        tools: [V2Tool],
        hotkeys: HotkeyBindings,
        triggers: TriggerSettings,
        telemetry: TelemetrySettings,
        appBlocklist: [String],
        appearance: AppearanceMode = .auto
    ) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.tools = tools
        self.hotkeys = hotkeys
        self.triggers = triggers
        self.telemetry = telemetry
        self.appBlocklist = appBlocklist
        self.appearance = appearance
    }
}
```

`HotkeyBindings` / `TriggerSettings` / `TelemetrySettings` / `AppearanceMode` / `ToolbarSize` 等辅助结构**复用 v1 现有定义**（它们没有 v2 特异行为；为了避免类型膨胀）。

- [ ] **Step 4: 实现 DefaultV2Configuration.swift**

Create `SliceAIKit/Sources/SliceCore/DefaultV2Configuration.swift`:

```swift
import Foundation

/// v2 默认配置（migrator 无 v1 文件时 fallback，以及 V2ConfigurationStore 首次启动使用）
///
/// 内容与 v1 `DefaultConfiguration.initial()` 同构：1 个 OpenAI Provider + 4 个内置 Prompt Tool。
/// 不复用 `DefaultConfiguration` 的产物——直接用 V2Tool / V2Provider 类型构造。
public enum DefaultV2Configuration {

    /// 生成 v2 默认配置
    public static func initial() -> V2Configuration {
        V2Configuration(
            schemaVersion: V2Configuration.currentSchemaVersion,
            providers: [openAIDefault],
            tools: [translate, polish, summarize, explain],
            hotkeys: HotkeyBindings(toggleCommandPalette: "option+space"),
            triggers: TriggerSettings(
                floatingToolbarEnabled: true,
                commandPaletteEnabled: true,
                minimumSelectionLength: 1,
                triggerDelayMs: 150,
                floatingToolbarAutoDismissSeconds: 5
            ),
            telemetry: TelemetrySettings(enabled: false),
            appBlocklist: [
                "com.apple.keychainaccess",
                "com.1password.1password",
                "com.1password.1password7",
                "com.bitwarden.desktop"
            ],
            appearance: .auto
        )
    }

    public static let openAIDefault = V2Provider(
        id: "openai-official",
        kind: .openAICompatible,
        name: "OpenAI",
        // swiftlint:disable:next force_unwrapping
        baseURL: URL(string: "https://api.openai.com/v1")!,
        apiKeyRef: "keychain:openai-official",
        defaultModel: "gpt-5",
        capabilities: []
    )

    // 四个内置工具的 V2Tool 定义（复用 v1 prompt 内容，三态使用 .prompt kind）
    public static let translate = makePromptTool(
        id: "translate", name: "Translate", icon: "🌐",
        description: "将选中文字翻译为指定语言",
        systemPrompt: "You are a professional translator. Translate faithfully and naturally. Output only the translation without explanations.",
        userPrompt: "Translate the following to {{language}}:\n\n{{selection}}",
        temperature: 0.3,
        variables: ["language": "Simplified Chinese"]
    )
    public static let polish = makePromptTool(
        id: "polish", name: "Polish", icon: "📝",
        description: "在保持原意的前提下润色文字",
        systemPrompt: "You are an expert editor. Polish the text while preserving the author's voice and meaning. Output only the polished version.",
        userPrompt: "Polish the following text:\n\n{{selection}}",
        temperature: 0.4, variables: [:]
    )
    public static let summarize = makePromptTool(
        id: "summarize", name: "Summarize", icon: "✨",
        description: "总结关键要点",
        systemPrompt: "You are an expert summarizer. Produce concise, structured summaries.",
        userPrompt: "Summarize the key points of the following text. Use Markdown bullet points:\n\n{{selection}}",
        temperature: 0.3, variables: [:]
    )
    public static let explain = makePromptTool(
        id: "explain", name: "Explain", icon: "💡",
        description: "解释专业术语或生词",
        systemPrompt: "You are a patient teacher. Explain concepts clearly, assuming an educated but non-expert audience.",
        userPrompt: "Explain the following in simple terms. If it's a technical term or acronym, expand and contextualize:\n\n{{selection}}",
        temperature: 0.4, variables: [:]
    )

    /// 共用 helper，构造一个 .prompt kind 的 V2Tool（均使用 openAIDefault 作为 fixed provider）
    private static func makePromptTool(
        id: String, name: String, icon: String, description: String,
        systemPrompt: String, userPrompt: String, temperature: Double,
        variables: [String: String]
    ) -> V2Tool {
        V2Tool(
            id: id, name: name, icon: icon, description: description,
            kind: .prompt(PromptTool(
                systemPrompt: systemPrompt, userPrompt: userPrompt, contexts: [],
                provider: .fixed(providerId: openAIDefault.id, modelId: nil),
                temperature: temperature, maxTokens: nil, variables: variables
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
    }
}
```

- [ ] **Step 5: 运行测试**

Run: `cd SliceAIKit && swift test --filter V2ConfigurationTests`
Expected: 6/6 passed.

Run: `cd SliceAIKit && swift test --filter SliceCoreTests`
Expected: 全绿——**关键验证** `test_v1Configuration_currentSchemaVersion_unchanged` 保证旧 `Configuration.currentSchemaVersion = 1` 未被意外改动；ConfigurationTests / DefaultConfigurationTests 等现有测试保持不动。

- [ ] **Step 6: 整体 build**

Run: `cd SliceAIKit && swift build`
Expected: 全 10 个 target 成功。

- [ ] **Step 7: SwiftLint**

Run: `swiftlint lint SliceAIKit/Sources/SliceCore/V2Configuration.swift SliceAIKit/Sources/SliceCore/DefaultV2Configuration.swift --strict`
Expected: 0 violations.

- [ ] **Step 8: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/V2Configuration.swift \
        SliceAIKit/Sources/SliceCore/DefaultV2Configuration.swift \
        SliceAIKit/Tests/SliceCoreTests/V2ConfigurationTests.swift
git commit -m "feat(core): add V2Configuration and DefaultV2Configuration

V2Configuration is an independent struct with schemaVersion=2 and V2Tool /
V2Provider collections. The existing Configuration.currentSchemaVersion stays
at 1, so FileConfigurationStore never writes v2 shape JSON into the v1
config.json path. DefaultV2Configuration mirrors the v1 starter pack using
V2Tool .prompt kind and .firstParty provenance."
```

---

## Task 19: V2ConfigurationStore 独立 actor（不改 FileConfigurationStore）

> **评审修正（Codex 第五轮 P1-1）**：初版方案"往现有 `FileConfigurationStore` 加 v2 路径 API"虽然不改 `AppContainer` 直接调用的 `init(fileURL:)`，但**现有 store 持有 `Configuration` 类型**——如果 Task 18 把 `currentSchemaVersion` 改到 2（已在 Task 18 修正为不改），store.save() 写出去的 JSON 仍会是 v2 形状。收敛为：**不改 `ConfigurationStore.swift`**；新建 `V2ConfigurationStore.swift` 独立 actor，它持有的是 `V2Configuration` 类型，与 v1 store 完全隔离。

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift`
- Create: `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift`
- **不修改** `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift`

M1 Task 19 DoD：**V2ConfigurationStore 实现 + 单测就绪**；现有 `FileConfigurationStore` 零改动；`AppContainer` 仍通过 `FileConfigurationStore.standardFileURL()` 读写 v1 `config.json`，v0.1 行为完全保留。

- [ ] **Step 1: 写 V2ConfigurationStore 失败测试**

Create `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift`:

```swift
import XCTest
@testable import SliceCore

final class V2ConfigurationStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sliceai-v2test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Path selection

    func test_standardV2FileURL_endsWith_config_v2_json() {
        let url = V2ConfigurationStore.standardV2FileURL()
        XCTAssertEqual(url.lastPathComponent, "config-v2.json")
        XCTAssertTrue(url.path.contains("/SliceAI/"))
    }

    func test_legacyV1FileURL_endsWith_config_json() {
        let url = V2ConfigurationStore.legacyV1FileURL()
        XCTAssertEqual(url.lastPathComponent, "config.json")
    }

    // MARK: - Migration on first launch

    func test_load_withV1Only_migratesToV2AndLeavesV1Intact() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        // 准备 v1 文件
        let v1Data = try fixtureData("config-v1-minimal")
        try v1Data.write(to: v1URL, options: .atomic)

        // 构造 v2 store 读 v2 路径；应触发自动迁移
        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.load()

        XCTAssertEqual(cfg.schemaVersion, 2)
        XCTAssertEqual(cfg.tools.count, 1)

        // v2 文件已被写入
        XCTAssertTrue(FileManager.default.fileExists(atPath: v2URL.path))
        // v1 文件原样保留（bytes 不变）
        let preservedV1 = try Data(contentsOf: v1URL)
        XCTAssertEqual(preservedV1, v1Data)
    }

    func test_load_withV2Existing_readsV2_ignoresV1() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        // 准备 v2 文件（用 DefaultV2Configuration 做样本，改一个可辨识字段）
        var v2Template = DefaultV2Configuration.initial()
        v2Template = V2Configuration(
            schemaVersion: v2Template.schemaVersion,
            providers: [], tools: [],
            hotkeys: HotkeyBindings(toggleCommandPalette: "option+z"),
            triggers: v2Template.triggers,
            telemetry: v2Template.telemetry,
            appBlocklist: v2Template.appBlocklist,
            appearance: v2Template.appearance
        )
        let v2Data = try JSONEncoder().encode(v2Template)
        try v2Data.write(to: v2URL, options: .atomic)

        // 同时准备一个 v1 文件——应被忽略
        let v1Data = try fixtureData("config-v1-minimal")
        try v1Data.write(to: v1URL, options: .atomic)

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.load()

        XCTAssertEqual(cfg.hotkeys.toggleCommandPalette, "option+z")
        XCTAssertEqual(cfg.tools.count, 0)
    }

    func test_load_withNeither_returnsDefaultV2() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.load()

        XCTAssertEqual(cfg.schemaVersion, 2)
        XCTAssertEqual(cfg.tools.count, 4)  // 4 个内置工具（DefaultV2Configuration）
    }

    // MARK: - Write behaviour

    func test_save_writesOnlyToV2Path_neverTouchesV1() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        let v1Data = try fixtureData("config-v1-minimal")
        try v1Data.write(to: v1URL, options: .atomic)

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = DefaultV2Configuration.initial()
        try await store.save(cfg)

        XCTAssertTrue(FileManager.default.fileExists(atPath: v2URL.path))
        let preservedV1 = try Data(contentsOf: v1URL)
        XCTAssertEqual(preservedV1, v1Data)
    }

    // 关键不变量：v1 FileConfigurationStore 与 V2ConfigurationStore 完全隔离；
    // v1 store 的 currentSchemaVersion 仍是 1
    func test_v1Store_unchanged_stillWritesSchemaVersion1() async throws {
        let v1URL = tempDir.appendingPathComponent("config-v1-test.json")
        let v1Store = FileConfigurationStore(fileURL: v1URL)  // 现有 v1 API
        try await v1Store.save(DefaultConfiguration.initial())

        let data = try Data(contentsOf: v1URL)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"), "v1 store must write schemaVersion=1; got: \(json)")
    }

    // MARK: - Helper

    private func fixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
```

- [ ] **Step 2: 运行看失败**

Run: `cd SliceAIKit && swift test --filter V2ConfigurationStoreTests`
Expected: FAIL（`V2ConfigurationStore` 不存在）。

- [ ] **Step 3: 实现 V2ConfigurationStore.swift**

Create `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift`:

```swift
import Foundation
import OSLog

private let v2ConfigLog = Logger(subsystem: "com.sliceai.core", category: "V2ConfigurationStore")

/// v2 配置的读写 actor（独立于现有 `FileConfigurationStore`）
///
/// 持有 `V2Configuration` 类型；与 v1 store 完全隔离：
/// - 不继承、不包装 `FileConfigurationStore`
/// - 不共享 Configuration Codable
/// - 仅被 M3 的 AppContainer 启用；M1 的真实 app 启动路径不经过此 store
///
/// 规则（对齐 spec §3.7）：
/// 1. v2 文件存在 → 直接 decode V2Configuration
/// 2. v2 不存在但 v1 存在 → 读 v1 原文 → `ConfigMigratorV1ToV2.migrate(_:)` → 写 v2 → 返回 v2；**不改 v1**
/// 3. 两者都不存在 → 返回 `DefaultV2Configuration.initial()`
/// 4. `save()` 始终写 v2 路径；v1 永不被写
public actor V2ConfigurationStore {

    private let fileURL: URL
    private let legacyFileURL: URL?
    private var cached: V2Configuration?

    /// 构造 V2ConfigurationStore
    /// - Parameters:
    ///   - fileURL: v2 目标 JSON 路径（`config-v2.json`）
    ///   - legacyFileURL: v1 旧文件路径；nil 表示不做 v1 迁移
    public init(fileURL: URL, legacyFileURL: URL?) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
    }

    /// 获取当前 v2 配置：优先缓存 → v2 文件 → migrator → 默认配置
    public func current() async -> V2Configuration {
        if let cached { return cached }
        if let loaded = try? await load() {
            cached = loaded
            v2ConfigLog.debug("current() loaded v2 config")
            return loaded
        }
        let fallback = DefaultV2Configuration.initial()
        cached = fallback
        v2ConfigLog.debug("current() falling back to DefaultV2Configuration.initial()")
        return fallback
    }

    /// 更新并持久化到 v2 路径
    public func update(_ configuration: V2Configuration) async throws {
        try await save(configuration)
        cached = configuration
    }

    /// 加载配置（按 §3.7 规则）
    public func load() async throws -> V2Configuration {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try loadV2Direct()
        }
        if let legacyFileURL, FileManager.default.fileExists(atPath: legacyFileURL.path) {
            v2ConfigLog.info("v2 missing, migrating from v1 at \(legacyFileURL.path, privacy: .public)")
            let v2 = try migrateFromLegacy(at: legacyFileURL)
            try writeV2(v2)
            return v2
        }
        v2ConfigLog.debug("load() neither v2 nor v1 exists, returning DefaultV2Configuration.initial()")
        return DefaultV2Configuration.initial()
    }

    /// 写 v2；永不碰 v1
    public func save(_ configuration: V2Configuration) async throws {
        try writeV2(configuration)
    }

    // MARK: - Path helpers

    /// v2 默认路径 `~/Library/Application Support/SliceAI/config-v2.json`
    public static func standardV2FileURL() -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("config-v2.json")
    }

    /// v1 旧路径（只供参考；v1 store 自己的 standardFileURL() 才是 AppContainer 读到的）
    public static func legacyV1FileURL() -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("config.json")
    }

    // MARK: - Private

    /// 直接读 v2 文件
    private func loadV2Direct() throws -> V2Configuration {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            v2ConfigLog.error("v2 read failed: \(error.localizedDescription, privacy: .public)")
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }

        let cfg: V2Configuration
        do {
            cfg = try JSONDecoder().decode(V2Configuration.self, from: data)
        } catch {
            v2ConfigLog.error("v2 decode failed: \(error.localizedDescription, privacy: .public)")
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }

        if cfg.schemaVersion > V2Configuration.currentSchemaVersion {
            throw SliceError.configuration(.schemaVersionTooNew(cfg.schemaVersion))
        }
        return cfg
    }

    /// 读 v1 原文 → LegacyConfigV1 → V2Configuration
    private func migrateFromLegacy(at legacyURL: URL) throws -> V2Configuration {
        let data: Data
        do {
            data = try Data(contentsOf: legacyURL)
        } catch {
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }
        let v1: LegacyConfigV1
        do {
            v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        } catch {
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }
        return ConfigMigratorV1ToV2.migrate(v1)
    }

    /// 原子写 v2 文件
    private func writeV2(_ configuration: V2Configuration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        v2ConfigLog.debug("writeV2: wrote \(data.count, privacy: .public) bytes")
    }
}
```

- [ ] **Step 4: 运行测试**

Run: `cd SliceAIKit && swift test --filter V2ConfigurationStoreTests`
Expected: 7/7 passed；**关键** `test_v1Store_unchanged_stillWritesSchemaVersion1` 保证现有 FileConfigurationStore 写出的 JSON schemaVersion 仍是 1。

Run: `cd SliceAIKit && swift test --filter ConfigurationStoreTests`
Expected: 原有测试全绿（`ConfigurationStore.swift` / `Configuration.swift` 未改动）。

- [ ] **Step 5: 整体 build**

Run: `cd SliceAIKit && swift build`
Expected: 全 10 个 target 成功。**关键验证**：`AppContainer.swift` 未改动；它继续用 `FileConfigurationStore(fileURL: FileConfigurationStore.standardFileURL())` 读写 v1 `config.json`。

- [ ] **Step 6: SwiftLint（整体，含 M1 所有新文件）**

Run: `swiftlint lint --strict`
Expected: `Done linting! Found 0 violations, 0 serious`.

若某文件 function_body_length 超限（80 行警戒），参考现有模式拆 private helper。

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift \
        SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift
git commit -m "feat(core): add V2ConfigurationStore as independent actor

V2ConfigurationStore holds V2Configuration (schemaVersion=2, V2Tool /
V2Provider) and reads/writes config-v2.json. The existing FileConfigurationStore
is untouched and keeps serving v1 config.json — AppContainer continues reading
v1 in M1. Migration on first launch only fires on explicit V2ConfigurationStore
instances (tests and future M3). A regression test asserts FileConfigurationStore
still writes schemaVersion=1 so v1 config.json can never be corrupted in M1."
```

---

## Task 20: 集成验证 + 覆盖率检查 + Task-detail 归档

> **评审修正（Codex 第五轮 P2-4）**：Task-detail / Task_history 已在 Task 0 前置创建；本 task 只做"完成后填充/更新"，不硬编码 Task 编号。

**Files:**
- Modify: `docs/Task-detail/<Task 0 创建的文件>`（填充"实施内容 / 文件清单 / 测试结果 / 下一步"等完成态字段）
- Modify: `docs/Task_history.md`（把 Task 0 那一条索引从"进行中"改为"完成 + 结果描述"）
- Modify: `docs/Module/SliceCore.md`（若存在）记录新 V2* 类型

- [ ] **Step 1: 全量跑 swift test 看覆盖率**

Run: `cd SliceAIKit && swift test --parallel --enable-code-coverage`
Expected: 所有 test target 全绿；SliceCoreTests 覆盖率 ≥ 90%。

Run: `cd SliceAIKit && swift test --filter SliceCoreTests 2>&1 | tail -20`
查看测试数量：应 ≥ (v1 原有) + 12 + 3（Permission + ContextKey + SelectionSnapshot 等）+ ... ≈ 新增 70+ 测试。

- [ ] **Step 2: 查看 code coverage（可选）**

Run: `cd SliceAIKit && xcrun llvm-cov report .build/debug/SliceAIKitPackageTests.xctest/Contents/MacOS/SliceAIKitPackageTests -instr-profile=.build/debug/codecov/default.profdata 2>/dev/null | grep -E "SliceCore|TOTAL"`

Expected: SliceCore 行覆盖率 ≥ 90%。

- [ ] **Step 3: xcodebuild 检查 App target 可编译**

Run: `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build 2>&1 | tail -10`
Expected: `BUILD SUCCEEDED`。

（此步验证 SliceAIApp / AppContainer 使用旧 API 与新 SliceCore 无兼容问题——M1 的关键 DoD）。

- [ ] **Step 4: SwiftLint strict 最终验收**

Run: `swiftlint lint --strict`
Expected: `Done linting! Found 0 violations, 0 serious`.

- [ ] **Step 5: migrator fixture 验证 + 可选的作者 config 干跑**

> **评审修正（Codex 第四轮 P2-1）**：不再描述为"作者 config 迁移烟雾测试"——这个表述暗示 app 真实启动路径已完成迁移，和"M3 才切 AppContainer"矛盾。本 step 的真实目的是：确认 migrator 对**多种 v1 JSON 形状**都能产出合法 v2。

**必做**：fixture 单测（前置 Task 已定义）全绿：

```bash
cd SliceAIKit && swift test --filter ConfigMigratorV1ToV2Tests --filter ConfigurationStoreV2PathTests
# 期望：ConfigMigratorV1ToV2Tests 9/9、ConfigurationStoreV2PathTests 5/5 全绿
```

**可选**：把作者当前的 `~/Library/Application Support/SliceAI/config.json` 复制到 `Tests/SliceCoreTests/Fixtures/` 作为新 fixture 文件，加一个临时测试用例跑一次迁移，确认不抛 decode 错误：

```bash
# 仅复制（不移动、不修改原文件）
cp ~/Library/Application\ Support/SliceAI/config.json \
   SliceAIKit/Tests/SliceCoreTests/Fixtures/author-config-smoke.json

# 临时 add 一个 test case：`test_migrate_authorsCurrentConfig_decodes`
# 跑完后 git checkout 该 fixture / 或直接删除；不合入 PR（含个人 API Key 引用等信息）
```

**显式不做**：
- ❌ 不启动真 app 触发迁移——AppContainer 在 M1 仍读 v1 `config.json`，真实启动路径**无 v2 行为**
- ❌ 不删除 / 移动作者的 `config.json` —— 它继续被 v0.1 app 消费
- ❌ 不创建 `config-v2.json` 在作者 home 目录 —— 只有 M3 切换 AppContainer 后才应该创建

- [ ] **Step 6: 填充 Task-detail 完成态字段**

Task 0 已经创建了 `docs/Task-detail/<今日日期>-phase-0-m1-core-types.md` 的骨架。现在把"实施内容 / 修改文件清单 / 测试结果 / 下一步"填满：

```markdown
## 实施内容（完成后填）

按 Plan 20 个 task 顺序执行。核心产出：

- **新增 10 个 library target 中的 2 个**：`Orchestration` / `Capabilities` 空 target + placeholder + test target（Package.swift 两个新 target 都 exclude README.md）
- **SliceCore 新增 v2 独立类型**：ContextKey / Requiredness / Permission / PermissionGrant / Provenance / GrantSource / GrantScope / SelectionContentType / SelectionOrigin / SelectionSnapshot / AppSnapshot / TriggerSource / ExecutionSeed / ContextBag / ContextValue / ResolvedExecutionContext / ContextRequest / CachePolicy / ContextProvider protocol / OutputBinding / PresentationMode / SideEffect (+inferredPermissions) / MCPToolRef / ProviderSelection / ProviderCapability / CascadeRule / ConditionExpr / Skill / SkillManifest / SkillReference / SkillResource / MCPDescriptor / MCPTransport / MCPCapability / ToolBudget / ToolMatcher / ToolKind / PromptTool / AgentTool / PipelineTool / PipelineStep / StepFailurePolicy / StopCondition / BuiltinCapability / TransformOp / LegacyConfigV1 / ProviderKind / **V2Provider** / **V2Tool** / **V2Configuration** / **DefaultV2Configuration** / **V2ConfigurationStore**
- **SliceCore 零改动**：`Tool.swift` / `Provider.swift` / `Configuration.swift` / `ConfigurationStore.swift` / `DefaultConfiguration.swift` / `SelectionPayload.swift` 全部保持 v1 形状
- **Migration**：ConfigMigratorV1ToV2 纯函数 migrator 产出 `V2Configuration`；V2ConfigurationStore 独立 actor 读写 `config-v2.json`；**真实 app 启动路径不经过 migrator**，仍走 v1 `FileConfigurationStore(fileURL: FileConfigurationStore.standardFileURL())`

## 修改文件清单（完成后填）

见 Plan §文件清单。估计 35–40 个 `.swift` 新建；约 18 个测试文件；2 个 JSON fixture。

## 测试用例与结果（完成后填）

- `swift test --parallel --enable-code-coverage`: 全绿；SliceCore 行覆盖率 ≥ 90%
- `swift build`: 10 个 target 全部成功
- `swiftlint lint --strict`: 0 violations
- `xcodebuild ... SliceAI`: BUILD SUCCEEDED
- migrator fixture 测试（`config-v1-minimal` / `config-v1-full` / edge cases）: 全绿
- golden JSON 测试：`Permission` / `Provenance` / `CachePolicy` / `SideEffect` / `ProviderSelection` / `ConditionExpr` / `MCPCapability` / `ToolKind` / `PipelineStep` / `TransformOp` 的 canonical JSON shape 已锁定（`ContextValue` 不 Codable，不进入此清单）
- 关键回归：`FileConfigurationStore` 写出的 JSON 仍 `schemaVersion=1`（v1 不被污染）
- **显式不承诺**：真实 app 启动路径已完成迁移（此动作在 M3.3）

## 下一步

- M2 Plan: `docs/superpowers/plans/<TBD>-phase-0-m2-orchestration.md`
- 实施：ExecutionEngine / ContextCollector / PermissionBroker / PermissionGraph / CostAccounting / AuditLog / PathSandbox / PromptExecutor 骨架
```

- [ ] **Step 7: 更新 Task_history.md 对应 Task 条目**

把 Task 0 创建的"进行中"条目改为"完成"：找到 `## Task <N> · Phase 0 M1 · 核心类型与配置迁移（进行中）`，删除"（进行中）"，补完"结果"字段：

```markdown
- **结果**：20 个 sub-task 全部完成；swift build / swift test / xcodebuild / swiftlint --strict 全绿；v1 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `SelectionPayload` 零改动；V2 canonical JSON schema 由 golden 测试锁定
```

- [ ] **Step 8: 终验收 commit**

```bash
git add docs/Task-detail/<今日日期>-phase-0-m1-core-types.md \
        docs/Task_history.md
git commit -m "docs(phase-0/m1): fill Task-detail and mark Task complete

M1 is complete: 20 sub-tasks landed as independent V2* types with v1
code paths untouched. All CI gates green. Ready for M2 plan to take over
Orchestration and Capabilities implementation. config.json remains v1
byte-identical; config-v2.json path is reachable only through explicit
V2ConfigurationStore instances, which M3 will wire into AppContainer."
```

- [ ] **Step 9: Final sanity check**

```bash
cd /Users/majiajun/workspace/SliceAI

# 所有 M1 commit 列表
git log --oneline $(git merge-base HEAD main)..HEAD

# 统计 M1 新增 swift 文件数
git diff --name-only --diff-filter=A $(git merge-base HEAD main)..HEAD -- 'SliceAIKit/Sources/SliceCore/*.swift' 'SliceAIKit/Sources/Orchestration/*.swift' 'SliceAIKit/Sources/Capabilities/*.swift' | wc -l
# 期望: ≥ 25

# 统计 M1 新增测试文件数
git diff --name-only --diff-filter=A $(git merge-base HEAD main)..HEAD -- 'SliceAIKit/Tests/SliceCoreTests/*.swift' 'SliceAIKit/Tests/OrchestrationTests/*.swift' 'SliceAIKit/Tests/CapabilitiesTests/*.swift' | wc -l
# 期望: ≥ 17

# 确认 ToolExecutor 未改
git diff $(git merge-base HEAD main)..HEAD -- SliceAIKit/Sources/SliceCore/ToolExecutor.swift | head -5
# 期望: 空（无 diff）

# 确认 AppContainer 未改
git diff $(git merge-base HEAD main)..HEAD -- SliceAIApp/AppContainer.swift | head -5
# 期望: 空（无 diff）
```

以上 4 个指标全部符合即认定 M1 达到 DoD；可以发 PR。

---

## Self-Review Checklist（plan 写完后的交叉检查）

- [x] **Spec §3.3.1 Tool 三态** → Task 15 改造 Tool + Task 14 定义 ToolKind / PromptTool / AgentTool / PipelineTool
- [x] **Spec §3.3.2 ExecutionSeed / ResolvedExecutionContext 两阶段** → Task 6 / Task 9
- [x] **Spec §3.3.3 ContextProvider.inferredPermissions (D-24)** → Task 8 protocol 定义 + test
- [x] **Spec §3.3.4 ProviderSelection** → Task 11
- [x] **Spec §3.3.5 Permission / Provenance canonical** → Task 3 单一定义
- [x] **Spec §3.3.6 OutputBinding / SideEffect + inferredPermissions** → Task 10
- [x] **Spec §3.3.7 ToolMatcher** → Task 14
- [x] **Spec §3.3.8 Skill / MCPDescriptor + provenance** → Task 13
- [x] **Spec §3.7 config-v2.json 独立路径 + v1 read-only** → Task 17 (migrator) + Task 19 (store)
- [x] **Spec §3.9.1 / §3.9.2 / §3.9.6 一致性** → Permission.swift 只定义数据；策略由 PermissionBroker 执行（M2），M1 不做策略代码
- [x] **Spec §3.9.6.5 effectivePermissions ⊆ declared (D-24)** → Task 8 ContextProvider.inferredPermissions + Task 10 SideEffect.inferredPermissions 为 M2 PermissionGraph 留 hook
- [x] **Spec §4.2 M1.1** → Task 1 (两个空 target)
- [x] **Spec §4.2 M1.2** → Task 4 / 5 / 6 / 9
- [x] **Spec §4.2 M1.3** → Task 2 + Task 8
- [x] **Spec §4.2 M1.4** → Task 3 + Task 10 的 SideEffect.inferredPermissions
- [x] **Spec §4.2 M1.5** → Task 14 + Task 15
- [x] **Spec §4.2 M1.6** → Task 12 + Task 11
- [x] **Spec §4.2 M1.7** → Task 10
- [x] **Spec §4.2 M1.8** → Task 13
- [x] **Spec §4.2 M1.9** → Task 16 + Task 17 + Task 18 + Task 19
- [x] **Spec §4.2 M1 DoD**: swift test 全绿 / app 行为不变 / SwiftLint 0 / v1 原文件不动 → Task 20 全部验证
- [x] **Placeholder scan**: 无 TODO / TBD；所有代码块完整；无 "similar to Task N"
- [x] **Type consistency**:
  - `ContextProvider.inferredPermissions(for args:)` 在 Task 8 定义 → Task 10 SideEffect 仿用同样命名
  - `Provenance` canonical 仅在 Task 3 定义；Skill / MCPDescriptor / V2Tool 的 provenance 字段都引用同一 enum
  - `ProviderSelection.fixed(providerId:modelId:)` 在 Task 11 定义 → Task 15 V2Tool / Task 17 migrator 使用同一签名
  - `SelectionSnapshot` vs `SelectionPayload`：**两个独立类型**（评审修正 P1-1），全文无 typealias、无 v1 字段互染
  - `PresentationMode` 唯一定义在 Task 10 OutputBinding.swift；不在 V2Tool.swift 重复定义
  - **V2* 命名一致性**（评审修正第五轮 P1-1 / P1-2）：v2 canonical 类型一律以 `V2` 前缀命名（V2Tool / V2Provider / V2Configuration / V2ConfigurationStore / DefaultV2Configuration），现有 `Tool` / `Provider` / `Configuration` / `FileConfigurationStore` / `DefaultConfiguration` 全部保持 v1 形状零改动
- [x] **向后兼容与隔离（评审修正第五轮）**: v1 代码路径（ToolExecutor / AppContainer / ToolEditorView / SettingsViewModel / OpenAICompatibleProvider / FileConfigurationStore / DefaultConfiguration）消费**现有 Tool / Provider / Configuration**；v2 代码路径（migrator / V2ConfigurationStore）消费 V2Tool / V2Provider / V2Configuration；两条路径**没有共享 Codable、没有共享 init、没有共享 accessor**，canonical model 不会被 v1 写入污染
- [x] **M1 DoD 口径**：只承诺"migrator fixture 单测全绿 + V2ConfigurationStore 独立 actor 就绪 + v1 config.json 在真实运行路径上仍只会被写入 schemaVersion=1（由 `test_v1Store_unchanged_stillWritesSchemaVersion1` 断言保证）"；**不**承诺真实 app 启动路径已完成迁移（那在 M3.3）
- [x] **v2 canonical JSON schema 锁定（第五轮 P1-3 + 第六轮 P1-1 补全）**：所有会进入 `config-v2.json` 的 associated-value enum（`ToolKind` / `PipelineStep` / `SideEffect` / `MCPCapability` / `TransformOp` / `ProviderSelection` / `ConditionExpr` / `CachePolicy` / `Permission` / `Provenance`）已在定义处**手写** `init(from:) / encode(to:)`（按 plan 顶部 Canonical JSON Schema 章节模板 A/B/C）；`ContextValue` **不 Codable**（不进入 JSON），从 golden 锁定范围中排除（P2-2 评审修正）
- [x] **Package.swift**（评审修正第五轮 P2-2）：Orchestration / Capabilities 两个新 target 都 `exclude: ["README.md"]`，不留 SwiftPM warning 给实施阶段
- [x] **ContextBag 确定性**（评审修正第五轮 P2-3）：`ContextBag` / `ContextValue` 明确**不实现 Codable**（因 SliceError 非 Codable），Task 7 不再给 "Codable 分支"指令
- [x] **文档前置 + 不硬编码 Task 编号**（评审修正第五轮 P2-4）：Task 0 前置创建 Task-detail 骨架和 Task_history 索引（编号按"查 grep 取下一个可用值"，不硬编码）；Task 20 只做"填充完成态字段"

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`. Two execution options:

1. **Subagent-Driven (recommended)** – dispatch a fresh subagent per task, review between tasks, fast iteration
2. **Inline Execution** – execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
