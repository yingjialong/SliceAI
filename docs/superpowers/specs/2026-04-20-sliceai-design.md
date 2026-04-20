# SliceAI 设计方案

- **日期**：2026-04-20
- **作者**：通过 brainstorming 与 Claude 共同产出
- **状态**：Design Freeze · 待进入 writing-plans 阶段
- **范围**：MVP v0.1 的设计与技术决策；v0.2+ 列在 Roadmap 作为扩展方向

---

## 1. 概述

### 1.1 产品定义

SliceAI 是一款 **macOS 原生、开源、可配置** 的划词触发 LLM 工具链。用户在任意应用中选中文字后，可以通过两种方式唤出工具栏：

- **A 通路：划词浮条**（PopClip 风格）—— 选区旁立即出现紧贴的图标工具栏
- **C 通路：快捷键中央面板** —— 按 `⌥Space` 调出类似 Raycast 的命令面板

用户选择某个工具后，SliceAI 用预设的 prompt 模板渲染选中文字，调用 OpenAI 兼容协议的 LLM，流式展示 Markdown 结果在独立浮窗中。

### 1.2 价值主张

- **相比 PopClip + GPT 插件**：不再被锁定在少数厂商插件；用户可任意定义 prompt、切换供应商。
- **相比 ChatGPT 官方 macOS app**：划词即用，不打断上下文；支持 OpenAI 兼容生态（DeepSeek / Moonshot / OpenRouter / 自建中转）。
- **相比 Bob / OpenAI Translator**：不仅仅是翻译；可扩展到任意 LLM 任务。
- **长期差异化**：v0.2+ 将支持 Skill 和 MCP，让每一个工具都可调用外部能力。

### 1.3 Non-goals（明确不做）

- ❌ 跨平台（iOS / Linux / Windows）—— Mac-only，保持专注
- ❌ 上架 Mac App Store —— 划词需要 Accessibility 权限，App Store 基本不过审
- ❌ MVP v0.1 不做：历史记录、追问、B 气泡、C 替换原文、Ollama 原生、Gemini 原生、浏览器扩展、开机自启、自动更新
- ❌ 自研 prompt DSL —— 只用 `{{variable}}` 简单模板
- ❌ 团队协作 / 云同步 —— 本地优先

### 1.4 成功标准（MVP v0.1）

1. 在 Safari / Notes / 预览 / Xcode 等原生应用内划词，浮条能在 200ms 内出现
2. 在 VSCode / Figma / Slack 等 Electron 应用内划词，通过 Cmd+C fallback 工作
3. 4 个内置工具（Translate / Polish / Summarize / Explain）开箱可用
4. 用户能在 Settings 界面添加新工具 / 新供应商
5. 能在普通 Mac 上 unsigned 安装并运行（用户 `xattr -d com.apple.quarantine` 后直接开）
6. 单元测试覆盖率：SliceCore ≥ 90%，LLMProviders ≥ 80%
7. CI 在每次 PR 时 `swift build && swift test` 全绿

---

## 2. 系统架构

### 2.1 分层与模块

SliceAI 采用 **Xcode App target + 单一 Local Swift Package（`SliceAIKit`）** 的组合结构。App target 仅负责 `@main` 入口、菜单栏图标、Asset、Entitlements；所有业务代码在 Package 的 7 个 module 中。

```
┌──────────────────────────────────────────────────┐
│  SliceAI.app  (Xcode App target)                 │
│  • @main  • MenuBarItem  • Assets.xcassets       │
│  • Entitlements  • Info.plist                    │
└──────────────────┬───────────────────────────────┘
                   │ depends on → SliceAIKit
                   ▼
┌──────────────────────────────────────────────────┐
│  Windowing   │  SettingsUI   │   Permissions     │
│  (NSPanel)   │  (SwiftUI)    │   (Onboarding)    │
└──────┬───────┴──────┬────────┴───────────────────┘
       │              │
       ▼              ▼
┌──────────────────────────────────────────────────┐
│  HotkeyManager  │  SelectionCapture  │ LLMProv.  │
│  (Carbon API)   │  (AX + Cmd+C)      │ (OpenAI)  │
└────────┬────────┴──────────┬─────────┴─────┬─────┘
         │                   │               │
         ▼                   ▼               ▼
┌──────────────────────────────────────────────────┐
│            SliceCore  (领域层)                    │
│  Tool / Provider(protocol) / ToolExecutor /      │
│  PromptTemplate / Configuration / SelectionPayload│
│                                                   │
│               Foundation only · No UI             │
└──────────────────────────────────────────────────┘
```

### 2.2 模块职责

| 模块 | 职责 | 关键类型 | 测试策略 |
|---|---|---|---|
| **SliceCore** | 领域模型 + 业务逻辑；零 UI 依赖；可跑 CLI / 嵌入 MCP | `Tool`, `Provider`(protocol), `ToolExecutor`, `PromptTemplate`, `Configuration`, `SelectionPayload`, `SliceError` | 100% 单测 |
| **LLMProviders** | OpenAI 兼容协议实现 + SSE 流式 | `OpenAICompatibleProvider`, `SSEDecoder`, `ProviderError` | Mock `URLProtocol` + SSE 固件 |
| **SelectionCapture** | 划词捕获；AX 优先 + Cmd+C fallback | `AXSelectionSource`, `ClipboardSelectionSource`, `SelectionService` | Clipboard 单测 + AX UI 测试 |
| **HotkeyManager** | 全局快捷键注册（`⌥Space` 默认） | `Hotkey`, `HotkeyRegistrar`（Carbon `RegisterEventHotKey`） | 逻辑单测 + 手动验收 |
| **Windowing** | 三类 NSPanel + 屏幕定位 | `FloatingToolbarPanel`, `CommandPalettePanel`, `ResultPanel`, `ScreenAwarePositioner` | 定位算法单测 + Preview |
| **SettingsUI** | SwiftUI Settings Scene + 工具 / 供应商编辑 | `SettingsScene`, `ToolEditorView`, `ProviderEditorView`, `ConfigurationStore` | Store 单测 + Preview |
| **Permissions** | Accessibility 权限检测 + 首启向导 | `AccessibilityMonitor`, `OnboardingFlow` | 手动验收 |

### 2.3 核心设计不变量

1. **SliceCore 零 UI 依赖**：确保任意时候都能拉出来跑 CLI 或嵌入外部宿主（v0.2+ MCP server 即复用此层）
2. **Provider 是 protocol**：即使当前只实现 OpenAI 兼容，协议抽象让社区 PR 增加 Claude / Gemini / Ollama 零改动
3. **模块间只通过 SliceCore 的 protocol 通信**：替换某一层不影响其他层（例：把 `SelectionCapture` 换成浏览器扩展 via XPC，上层无感知）
4. **配置与密钥严格分离**：`Configuration` JSON 可导出 / 分享 / git 托管；API Key 永远在 Keychain

### 2.4 为什么选这种物理结构

- **不用 XcodeGen / Tuist**：增加贡献者门槛，`SliceAIKit` 作为 local SPM 在现代 Xcode 里 diff 已足够干净
- **7 个 module 而非大单体**：每个 module 都有独立的测试边界和贡献切入点，符合开源项目"欢迎外部 PR"目标
- **不提前分 Services 层**：`ToolExecutor` 直接扮演业务入口，避免过度分层

---

## 3. 核心数据流

### 3.1 Happy Path：从划词到流式结果

```
┌─ User selects text in app (e.g. Safari) ─────────────────────┐
│                                                                │
│  ↓ mouseUp event                                              │
│                                                                │
│  SelectionCapture · debounce 150ms                             │
│    ↓                                                           │
│  AXSelectionSource.read()                                      │
│    ├─ success → SelectionPayload                               │
│    └─ fail → ClipboardSelectionSource.fallback()               │
│              (backup clipboard → ⌘C → read → restore)          │
│    ↓                                                           │
│  SelectionPayload { text, app, url?, screenPoint }             │
│    ↓                                                           │
│  Windowing.FloatingToolbarPanel.show(payload, at: screenPoint) │
│    ↓                                                           │
│  User clicks tool button (e.g. "🌐 Translate")                 │
│    ↓                                                           │
│  ToolExecutor.execute(tool, payload)                           │
│    ├─ PromptTemplate.render(tool.userPrompt, vars)             │
│    ↓                                                           │
│  OpenAICompatibleProvider.stream(messages) → AsyncStream<Chunk>│
│    ↓                                                           │
│  Windowing.ResultPanel.open() · Markdown 流式渲染               │
│    ↓                                                           │
│  User copies / closes (v0.2: 追问 / 替换原文)                   │
└───────────────────────────────────────────────────────────────┘
```

### 3.2 快捷键通路差异

快捷键面板（`⌥Space`）复用 **后半段完全相同** 的路径，只有前半段：

- **划词通路**：`mouseUp → debounce → AX/Cmd+C → FloatingToolbarPanel`
- **快捷键通路**：`HotkeyManager → AX/Cmd+C → CommandPalettePanel`

即 `CommandPalettePanel` 替代 `FloatingToolbarPanel`，后续工具执行流完全一致。

### 3.3 关键时序约束

| 阶段 | 目标耗时 | 备注 |
|---|---|---|
| `mouseUp → 浮条出现` | ≤ 200ms | 150ms debounce + 50ms 容忍 |
| AX 读取 | ≤ 10ms | 本地 API 调用 |
| Cmd+C fallback | ≤ 100ms | 含剪贴板备份恢复 |
| `点击工具 → 首 token` | ≤ 1s | 主要在 LLM，Provider 层零延迟 |
| `首 token → 结果窗口打开` | ≤ 50ms | 窗口创建是并行的 |

---

## 4. 核心组件接口

以下是 `SliceCore` 中的关键类型定义（Swift pseudocode）。完整实现细节在 plan 阶段展开。

### 4.1 `SelectionPayload`

```swift
public struct SelectionPayload: Sendable, Equatable {
    public let text: String           // 选中的文字
    public let appBundleID: String    // 如 "com.apple.Safari"
    public let appName: String        // 如 "Safari"
    public let url: URL?              // 浏览器场景下的页面 URL（via AX）
    public let screenPoint: CGPoint   // 触发时鼠标位置（屏幕坐标）
    public let source: Source         // .accessibility / .clipboardFallback
    public let timestamp: Date
    public enum Source: String, Codable, Sendable {
        case accessibility, clipboardFallback
    }
}
```

### 4.2 `Tool` 与 `Provider`

```swift
public struct Tool: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var icon: String              // emoji or SF Symbol 名
    public var description: String?
    public var systemPrompt: String?
    public var userPrompt: String        // 支持 {{var}} 模板
    public var providerId: String        // 引用 Provider.id
    public var modelId: String?          // nil → 用 provider.defaultModel
    public var temperature: Double?
    public var displayMode: DisplayMode  // .window (MVP 只支持这个)
    public var variables: [String: String]
}

public enum DisplayMode: String, Codable, Sendable {
    case window    // A · MVP
    case bubble    // B · v0.2
    case replace   // C · v0.2
}

public struct Provider: Identifiable, Codable, Sendable {
    public let id: String
    public var name: String
    public var baseURL: URL
    public var apiKeyRef: String         // "keychain:<id>"，绝不存明文
    public var defaultModel: String
}
```

### 4.3 `LLMProvider` Protocol

```swift
public protocol LLMProvider: Sendable {
    /// 发送消息并以 AsyncStream 返回流式 chunk
    func stream(
        request: ChatRequest
    ) async throws -> AsyncThrowingStream<ChatChunk, Error>
}

public struct ChatRequest: Sendable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?   // nil → 不向 API 发送此字段，使用服务端默认
    public let maxTokens: Int?        // nil → 同上
}

public struct ChatMessage: Sendable {
    public let role: Role        // .system / .user / .assistant
    public let content: String
}

public struct ChatChunk: Sendable {
    public let delta: String     // 增量文本
    public let finishReason: FinishReason?
}
```

### 4.4 `ToolExecutor`

```swift
public actor ToolExecutor {
    public init(
        configurationProvider: ConfigurationProviding,
        providerFactory: LLMProviderFactory,
        keychain: KeychainAccessing
    )

    /// 给定一个 Tool 和选中文字，产出流式结果
    public func execute(
        tool: Tool,
        payload: SelectionPayload
    ) async throws -> AsyncThrowingStream<ChatChunk, Error>
}
```

### 4.5 `PromptTemplate`

```swift
public enum PromptTemplate {
    /// 渲染 {{variable}} 占位符
    /// 保留变量：selection, app, url, language
    /// 用户自定义变量：从 tool.variables 注入
    public static func render(
        _ template: String,
        variables: [String: String]
    ) -> String
}
```

**语法规则**：
- 占位符 `{{name}}` → 在 `variables[name]` 中查找替换
- 未定义变量保留原样（开发期在日志中警告）
- 不支持条件 / 循环 / filter；复杂需求让用户写 Skill

---

## 5. 关键流程

### 5.1 首次启动（Onboarding）

```
App launch (first time)
    ↓
检测 Accessibility 权限
    ├─ 已授予 → 跳到 "API Key 录入"
    └─ 未授予 ↓
        OnboardingView (Step 1/3)
            "SliceAI 需要辅助功能权限才能读取划词"
            [打开系统偏好] → AXIsProcessTrustedWithOptions
            (监听权限状态变化，授予后自动进入下一步)
    ↓
OnboardingView (Step 2/3)
    "选择你的 LLM 供应商"
    - OpenAI 官方（默认）
    - DeepSeek
    - 自定义（填 baseURL）
    [下一步]
    ↓
OnboardingView (Step 3/3)
    "录入 API Key"（存 Keychain）
    [完成并启动]
    ↓
默认 4 个内置工具已就位，菜单栏图标显示，应用进入运行状态
```

### 5.2 划词浮条弹出

```
macOS global event monitor 捕获 mouseUp (NSEvent.addGlobalMonitorForEvents)
    ↓
检查前置条件：
    • 焦点应用不在黑名单（比如 Password 类应用，用 bundleID 过滤）
    • 用户未关闭 triggers.floatingToolbarEnabled
    ↓
启动 debounce 计时器 (triggerDelayMs: 150)
    ↓
SelectionService.capture()
    1. AXUIElementCopyAttributeValue(kAXFocusedUIElementAttribute)
    2. AXUIElementCopyAttributeValue(kAXSelectedTextAttribute)
    3. 若文字非空且长度 ≥ minimumSelectionLength (默认 1) → 返回 SelectionPayload
    4. 失败 or 空 → 进入 fallback
       - 保存 NSPasteboard.general 的 items 和 changeCount
       - CGEventCreateKeyboardEvent(⌘C) post 到 system event
       - 10-50ms polling 直到 changeCount 变化
       - 读新 pasteboard 内容
       - 恢复原 pasteboard items
       - 返回 SelectionPayload(source: .clipboardFallback)
    ↓
Windowing.ScreenAwarePositioner.position(for: payload.screenPoint)
    - 优先放在选区正下方偏移 8px
    - 若超出屏幕 → 翻到上方
    - 若接近屏幕右边 → 向左对齐
    - 多屏：选 payload.screenPoint 所在屏幕
    ↓
FloatingToolbarPanel.show(at: positioned)
    - NSPanel + .nonactivating + .canJoinAllSpaces
    - SwiftUI 填充工具图标，点击触发 ToolExecutor
    - 自动消失条件：失焦 / Esc / 5 秒无交互
```

### 5.3 快捷键面板（⌥Space）

```
HotkeyRegistrar 注册 ⌥Space via RegisterEventHotKey (Carbon)
    ↓ 用户按下 ⌥Space
SelectionService.capture()  (流程同 5.2)
    ↓
若 payload.text 为空 → 仍然打开 CommandPalettePanel，提示"请先选中文字"
若 payload.text 非空 → 打开 CommandPalettePanel，顶部预览选区
    ↓
CommandPalettePanel (NSPanel, 居中；可 activating 以接受文本输入)
    - 搜索框（可过滤工具名 / description）
    - 工具列表（键盘方向键导航，Enter 触发）
    - 关闭条件：Esc / 失焦（clickOutside）/ 选中工具触发后自动关闭
```

### 5.4 工具执行

```
用户点击某工具（from 浮条 or 面板）
    ↓
ToolExecutor.execute(tool: Tool, payload: SelectionPayload)
    ↓
构造 variables：
    merged = tool.variables
           .merging(["selection": payload.text,
                     "app": payload.appName,
                     "url": payload.url?.absoluteString ?? ""])
    ↓
PromptTemplate.render(tool.userPrompt, variables: merged) → String userText
PromptTemplate.render(tool.systemPrompt ?? "", variables: merged) → String systemText
    ↓
构造 ChatRequest(
    model: tool.modelId ?? provider.defaultModel,      // 工具级 model 覆盖 Provider 默认
    messages: [
        .system(systemText)（systemText 为空字符串时省略该条消息）,
        .user(userText)
    ],
    temperature: tool.temperature                      // nil 时不传，用服务端默认
)

备注：用户修改 Provider.defaultModel 后，所有 modelId == nil 的工具会在下次执行时自动使用新 model。
这是预期行为（"全局换模型"只需改一处）。
    ↓
provider.stream(request) → AsyncThrowingStream<ChatChunk, Error>
    ↓
Windowing.ResultPanel.open(toolName, model) 立即显示空窗口
    ↓
for try await chunk in stream {
    ResultPanel.append(chunk.delta)   // Markdown 增量渲染
}
    ↓
stream 结束 → 显示"复制" / "关闭"按钮
stream 出错 → 显示友好错误 + "重试" / "打开设置"按钮
```

---

## 6. 配置系统

### 6.1 配置文件位置与格式

- **路径**：`~/Library/Application Support/SliceAI/config.json`
- **格式**：JSON，`schemaVersion: 1`
- **伴随文件**：`~/Library/Application Support/SliceAI/config.schema.json`（JSON Schema，提供给 IDE 补全 / 校验）

### 6.2 完整 Schema（v1）

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
      "id": "translate-zh",
      "name": "Translate to Chinese",
      "icon": "🌐",
      "description": "翻译选中的文字",
      "systemPrompt": "You are a professional translator.",
      "userPrompt": "Translate the following to {{language}}:\n\n{{selection}}",
      "providerId": "openai-official",
      "modelId": null,
      "temperature": 0.3,
      "displayMode": "window",
      "variables": { "language": "Simplified Chinese" }
    }
  ],
  "hotkeys": {
    "toggleCommandPalette": "option+space"
  },
  "triggers": {
    "floatingToolbarEnabled": true,
    "commandPaletteEnabled": true,
    "minimumSelectionLength": 1,
    "triggerDelayMs": 150
  },
  "telemetry": {
    "enabled": false
  },
  "appBlocklist": [
    "com.apple.keychainaccess",
    "com.1password.1password"
  ]
}
```

### 6.3 API Key 存储

- Keychain `kSecClassGenericPassword`
- `service` 字段统一为 `"com.sliceai.app.providers"`
- `account` 字段为 `provider.id`
- 读写通过 `KeychainAccessing` protocol，单元测试时注入 in-memory 假实现

### 6.4 默认配置（首次启动注入）

4 个内置工具 + 1 个 Provider（OpenAI，API Key 留待用户在 onboarding 录入）：
- 🌐 **Translate** — 目标语言默认 Simplified Chinese，可用户改
- 📝 **Polish** — 保持作者风格的润色
- ✨ **Summarize** — 要点总结
- 💡 **Explain** — 解释专业术语 / 陌生词

具体 prompt 初始值在实现阶段根据实战迭代确定，但都是"短 systemPrompt + `{{selection}}` 用户 prompt"的结构。

### 6.5 导入 / 导出

- `Settings` 界面提供"导出配置"按钮 → 保存 `*.slice.json`（**不含** API Key 引用指向的真实 key）
- "导入配置"按钮 → 覆盖 / 合并两种模式，schemaVersion 不兼容时拒绝并提示
- 未来可作为"工具商店"的分享格式

---

## 7. 错误处理与降级

### 7.1 错误分层

```swift
public enum SliceError: Error, Sendable {
    case selection(SelectionError)
    case provider(ProviderError)
    case configuration(ConfigurationError)
    case permission(PermissionError)

    public var userMessage: String { ... }  // 面向用户的友好文案
    public var developerContext: String { ... }  // 日志记录
}

public enum SelectionError: Error {
    case axUnavailable       // AX 权限未授予
    case axEmpty             // AX 返回空或失败
    case clipboardTimeout    // Cmd+C 超时未拿到
    case textTooLong(Int)    // 超过配置 maxSelectionLength
}

public enum ProviderError: Error {
    case unauthorized        // 401
    case rateLimited(retryAfter: TimeInterval?)  // 429
    case serverError(Int)    // 5xx
    case networkTimeout
    case invalidResponse(String)
    case sseParseError(String)
}

public enum ConfigurationError: Error {
    case fileNotFound
    case schemaVersionTooNew(Int)
    case invalidJSON(String)
    case referencedProviderMissing(String)
}

public enum PermissionError: Error {
    case accessibilityDenied
    case inputMonitoringDenied  // Cmd+C 模拟需要
}
```

### 7.2 降级策略

| 场景 | 降级动作 |
|---|---|
| AX 读取为空 / 失败 | 自动切到 Cmd+C fallback（对用户透明） |
| Cmd+C 也拿不到 | 浮条改为"Cannot read selection" 提示态，提供"打开设置"引导 |
| Provider 429 | 自动退避重试一次（指数），再失败展示"速率限制"可点击重试 |
| Provider 5xx | 展示可重试按钮 + error detail |
| Provider 401 | 直接跳 Settings 的 Provider 页，高亮该 Provider 的 API Key 入口 |
| 网络超时 | 默认 30s 超时；超时后展示"重试" |
| SSE 解析错误 | 收集问题 chunk，记日志，展示"服务端响应异常" |

### 7.3 用户可见错误样式

ResultPanel 在错误态下：
- 顶部红色 banner + 简短错误（如 "API Key 无效"）
- 下方按钮：`[打开设置]` / `[复制错误详情]` / `[重试]`
- 详情折叠区（默认收起）：堆栈、请求 ID、Provider raw response

---

## 8. 测试策略

### 8.1 测试层次

| 层 | 工具 | 覆盖目标 |
|---|---|---|
| **单元测试** | XCTest | `SliceCore` 100%，`LLMProviders` 80%+，`SelectionCapture.Clipboard` 80%+，`Windowing.ScreenAwarePositioner` 算法分支 100% |
| **集成测试** | XCTest + Mock URLProtocol | Provider 接 Mock server 跑通"发 request → SSE 流 → 结构化 chunk" |
| **UI 测试** | XCUITest | 首启 onboarding、浮条出现 / 消失、Settings 基本流（少量，高价值） |
| **手动验收** | 测试脚本（Markdown checklist） | AX 不可测部分：Safari / VSCode / Figma / Slack 四款应用的划词通路 |

### 8.2 测试数据与固件

- `Tests/Fixtures/sse_responses/` 存放 SSE 原始文本固件（含正常、截断、错误、心跳等场景）
- `Tests/Fixtures/configs/` 存放各种 config.json 样本（有效、schemaVersion 高、缺失字段、引用 provider 不存在）

### 8.3 Mock 与依赖注入

- 所有外部依赖都通过 protocol 注入（`ConfigurationProviding`, `KeychainAccessing`, `URLSessionProtocol`）
- 单测里用 in-memory 假实现
- 禁止 singleton 全局状态，`ToolExecutor` 等业务 actor 都接收构造注入

### 8.4 CI 中的测试

```yaml
# .github/workflows/ci.yml (简化)
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-15
    steps:
      - uses: actions/checkout@v4
      - uses: swift-actions/setup-swift@v2
        with: { swift-version: "6.0" }
      - run: swift build --package-path SliceAIKit
      - run: swift test --package-path SliceAIKit --parallel
      - run: swiftlint --strict
```

UI 测试 / 手动验收不在 CI 强制跑，由 release 前 checklist 执行。

---

## 9. 项目结构与开发流程

### 9.1 目录结构

```
SliceAI/
├── README.md                         # 项目介绍 + 截图 + 安装说明
├── LICENSE                           # MIT
├── .gitignore
├── .swiftlint.yml
├── .swift-format
├── SliceAI.xcodeproj/                # App target
├── SliceAIKit/                       # Local SPM
│   ├── Package.swift
│   ├── Sources/
│   │   ├── SliceCore/
│   │   ├── LLMProviders/
│   │   ├── SelectionCapture/
│   │   ├── HotkeyManager/
│   │   ├── Windowing/
│   │   ├── SettingsUI/
│   │   └── Permissions/
│   └── Tests/
│       ├── SliceCoreTests/
│       ├── LLMProvidersTests/
│       ├── SelectionCaptureTests/
│       └── WindowingTests/
├── docs/
│   ├── superpowers/specs/            # 设计文档
│   ├── Module/                       # 按 CLAUDE.md 要求的模块文档
│   ├── Task-detail/                  # 每个任务的详细文档
│   └── Task_history.md               # 任务历史索引
├── scripts/
│   ├── build-dmg.sh                  # 打包 unsigned DMG
│   └── install-dev.sh                # 开发版直接拷到 /Applications
└── .github/
    ├── workflows/
    │   ├── ci.yml
    │   └── release.yml
    └── PULL_REQUEST_TEMPLATE.md
```

### 9.2 Git 工作流

- 单一 `main` 分支
- Feature 分支命名：`feat/<short-topic>`、`fix/<short-topic>`、`docs/<topic>`
- PR → Squash merge
- Commit 消息遵循 Conventional Commits（`feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`）
- 版本：SemVer（`0.1.0` → `0.2.0` → ...），tag 触发 Release

### 9.3 代码规范

- `SwiftLint` 配置见仓库，严格模式 CI enforce
- `swift-format` 按 Apple 官方默认
- 文件行数 ≤ 500 行（比 CLAUDE.md 的 1000 更严）
- 所有 public API 必须有 DocC 注释
- 所有函数必须有函数级中文注释（贡献者层面不强制，但仓库核心维护者按此标准）

### 9.4 发布流程（v0.1 unsigned）

1. `git tag v0.1.0 && git push --tags`
2. `release.yml` workflow 触发：
   - `swift build -c release`
   - `xcodebuild archive` 生成 `.app`
   - `scripts/build-dmg.sh` 打包 `SliceAI-0.1.0.dmg`
   - 创建 GitHub Release 并上传 dmg
3. Release notes 模板：
   ```
   ## What's new
   - ...
   ## Installation
   1. Download SliceAI-0.1.0.dmg
   2. Open the dmg and drag SliceAI.app to /Applications
   3. First launch: right-click → Open (since unsigned)
      Or: `xattr -d com.apple.quarantine /Applications/SliceAI.app`
   4. Follow the onboarding to grant Accessibility + enter your API Key
   ```
4. 社区反馈后评估是否在 v0.2 申请 Apple Developer 账号启用 notarization

### 9.5 文档约定（沿用 CLAUDE.md）

- 每个 module 对应 `docs/Module/<ModuleName>.md`
- 每个任务对应 `docs/Task-detail/<TaskID>-<slug>.md`
- `docs/Task_history.md` 是任务索引
- README.md 保持"能进来就知道项目是什么 + 当前进度"

---

## 10. Roadmap

### v0.1 · MVP（本次设计范围）

✅ 所有"MUST"项目：
- 双通路触发（划词浮条 + ⌥Space 面板）
- 独立浮窗结果展示 · Markdown 流式
- OpenAI 兼容 Provider
- 4 个内置工具
- Settings 界面
- Keychain 存 Key
- 菜单栏图标 + Onboarding + Accessibility 向导
- 完整 7 modules + CI + unsigned DMG 发布

### v0.2

- **MCP 集成**：每个 Tool 可声明它调用的 MCP servers，ToolExecutor 在渲染 prompt 前 / 产出后注入 MCP tool calls
- **Skill 集成**：接入 Anthropic Skills 规范，让工具可引用 skill 作为 system prompt
- **B 气泡 + C 替换**：补全 DisplayMode 的剩余两种
- **历史记录 + 追问**：在 ResultPanel 增加"追问"按钮，多轮会话本地存储
- **本地 Ollama 原生适配**：虽然 Ollama 提供 OpenAI 兼容 API，但原生协议能用更多特性（如 model 列表、pull）
- **多语言 UI（i18n）**：至少英文 + 简中

### v0.3

- **浏览器扩展**（Chrome / Safari / Firefox）：覆盖 iframe、PDF 内置阅读器等 AX 难点
- **自动更新**（Sparkle 框架）
- **Apple Developer 账号 + Notarization**（升级到签名 DMG）
- **工具商店 / 社区分享**：`.slice.json` 配置文件分享站
- **Homebrew cask**：`brew install --cask sliceai`

### 未决 / 后续考虑

- Anthropic / Gemini 原生 Provider（社区反馈决定优先级）
- 快捷键多组合支持（单个工具可以绑专属快捷键）
- 跨 Mac 配置同步（iCloud Documents）
- 团队协作模式（共享 prompt 库）

---

## 附录 A. 关键决策记录（与 brainstorming 对齐）

| 决策 | 选项 | 理由 |
|---|---|---|
| 定位 | 开源项目（非商业产品） | 用户明确选择 B |
| 技术栈 | Swift/SwiftUI 原生（非 Electron/Tauri） | 划词毫秒级延迟 + AX/NSPanel 原生 API 要求 |
| 交互模型 | A 浮条 + C 快捷键面板 双通道 | 兼顾"即划即用"和"不打扰" |
| 结果展示 | 架构 D，MVP 实现 A | 不同工具天然需要不同展示，但 MVP 收敛到一个 |
| Provider | 只做 OpenAI 兼容 | 覆盖 80% 场景，一键复用中转生态 |
| 划词捕获 | AX + Cmd+C fallback | PopClip 验证过的最优组合 |
| 配置 | JSON · `{{var}}` 模板 | 原生 Codable、零依赖、简单 |
| License | MIT | 开源社区主流、降低贡献门槛 |
| 快捷键 | ⌥Space | 不撞系统 Spotlight |
| 发布 | 先 unsigned DMG | 暂无 Apple Developer 账号 |

## 附录 B. 批判性遗留风险（需要在实现阶段监控）

1. **AX 在 Sonoma/Sequoia 上的实际可用率**：近几年 Apple 对 AX 权限越来越严，需要在真机上覆盖率测试
2. **Cmd+C fallback 的剪贴板丢字窗口**：50-100ms 竞态，需要压力测试
3. **SwiftUI 在 NSPanel 里的焦点管理**：MVP 中 FloatingToolbar 不 activate、CommandPalette 要求输入焦点——两个 panel 的策略不同，需要分别验证
4. **SSE 解析鲁棒性**：不同 OpenAI 兼容实现对 SSE 格式的细节可能不一致（换行、结束标记），需要 fixture 覆盖 OpenAI / DeepSeek / Moonshot / Ollama 等至少 4 家
5. **项目名 `SliceAI` 重名风险**：发布前必须 grep GitHub + App 名字库，必要时备选 `SliceIt` / `SliceBar` 等
6. **首启向导的 Accessibility 权限流程**：Apple 原生 API `AXIsProcessTrustedWithOptions` 无法监听权限变化，需要轮询或重启检测

---

_本 spec 由 `superpowers:brainstorming` skill 与用户对齐产出。进入 `superpowers:writing-plans` 后将展开为带里程碑的实施计划。_
