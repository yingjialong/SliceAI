# 续聊（多轮追问）+ 历史 实施 Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 让 SliceAI 的任一 window 结果支持多轮追问（带上下文管理），并在 Settings 提供历史页查看/删除过往交互。

**Architecture:** 给 `ExecutionSeed` 增一个可选 `followUp` 字段承载历史，两个 executor 读 `resolved.seed.followUp` 分支组装 `[system, ...历史, user(追问)]`，不改 run() 签名、不旁路 ExecutionEngine。会话历史的累积/窗口裁剪做成 SliceCore 的纯 reducer `ConversationSession`（可单测），由 App 层持有并驱动续聊 execute + 落盘到 Capabilities `ConversationStore`（明文本地、独立于 config）。ResultPanel 以 transcript 追加方式呈现多轮，不重置已有文本。History 页照 MCPServersPage 模式新增只读列表 + 查看 + 删除。

**Tech Stack:** Swift 6（strict concurrency）、SwiftPM 多 target、SwiftUI + AppKit（NSPanel）、XCTest、JSON 落盘到 `~/Library/Application Support/SliceAI/`。

---

## 关键架构决策（实施前必读，避免走偏）

- **D1 — 历史承载在 `ExecutionSeed.followUp`**：history "在触发瞬间已知"，按 `ExecutionSeed.swift` 文件头官方指引加为新字段。`ResolvedExecutionContext` 透传 `seed`，故 `PromptExecutor` / `AgentExecutor` 直接读 `resolved.seed.followUp`，**两个 run() 签名都不改**。
- **D2 — 续聊消息形状**：`[system?(工具/agent 的), ...priorMessages, user(followUpText)]`。priorMessages 只含**用户可见的 [user, assistant] 对**（不含 agent 内部 tool_call/tool_result 消息）。agent 续聊在新 user 消息尾部重挂 skill metadata（保持 `sliceai_load_skill` 可用），**不重复注入 context bag**（选区等已在历史首轮里）。
- **D3 — 持久化由 App 层驱动，不碰 ExecutionEngine 写路径**：App 持有纯逻辑 `ConversationSession`（SliceCore），每轮 finish 后 upsert `ConversationRecord` 到 `ConversationStore`（Capabilities）。这样避开"在执行链内部取多轮 messages"的最大未定项。
- **D4 — 上下文窗口**：默认 **10 轮**（1 轮 = 一对 user+assistant）滑动窗口用于**发给 provider 的 priorMessages**；**落盘 record 保留完整历史**。窗口触发裁剪时通过面板 `contextNotice` 给非阻塞友好提示。窗口大小与历史容量上限是**常量**（不引入 config 字段、不 bump schema v4）。
- **D5 — 会话存储**：Capabilities `actor ConversationStore`，单个 `conversations.json`（`ConversationLog { schemaVersion, conversations: [ConversationRecord] }`），`update { inout }` 原子读改写，容量上限 200（超出淘汰最旧）。存完整明文；日志只记条数/字节，**绝不记内容**；与 `config-v2.json`、Keychain、`audit.jsonl` 物理分离。
- **D6 — ResultPanel 多轮 = transcript 追加**：续聊**绝不调 `ResultViewModel.reset()`**（会清空上一轮）；改为追加分隔块（`\n\n---\n\n**你：** <追问>\n\n`）再让新流 append 答案，复用现有 `StreamingMarkdownView`。bubble 化留作 v1.0 之后 polish。
- **D7 — 续聊只作用于 window/ResultPanel**：`.bubble` / `.tts` 不支持续聊。
- **D8 — 隐私护栏**：续聊/历史明文绝不进日志或 audit。新增的事件/日志路径若会带 follow-up 文本，必须脱敏或不记录。

## 文件结构（创建 / 修改清单）

**新建**
- `SliceAIKit/Sources/SliceCore/FollowUpContext.swift` — 续聊上下文值类型。
- `SliceAIKit/Sources/SliceCore/ConversationRecord.swift` — `ConversationRecord` + `ConversationSummary` + `ConversationLog`。
- `SliceAIKit/Sources/SliceCore/ConversationSession.swift` — 纯 reducer（累积、10 轮窗口、生成 record）。
- `SliceAIKit/Sources/Capabilities/Conversations/ConversationStore.swift` — 落盘 actor。
- `SliceAIKit/Sources/SettingsUI/HistoryViewModel.swift` — History 页 VM。
- `SliceAIKit/Sources/SettingsUI/Pages/HistoryPage.swift` — History 页视图（列表 + 只读详情 sheet）。
- `SliceAIApp/ConversationCoordinator.swift` — App 层续聊编排（持有 session、驱动续聊 execute、落盘）。
- 测试：`SliceCoreTests/FollowUpContextTests.swift`、`ConversationRecordTests.swift`、`ConversationSessionTests.swift`、`CapabilitiesTests/ConversationStoreTests.swift`、`SettingsUITests/HistoryViewModelTests.swift`。

**修改**
- `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift` — 加 `followUp: FollowUpContext?`。
- `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift` — `renderMessages` 分支 followUp。
- `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift` — `buildInitialMessages` 分支 followUp。
- `SliceAIKit/Sources/Windowing/ResultViewModel.swift` — 加 `onSubmitFollowUp` / `contextNotice` / `beginFollowUpTurn(_:)`。
- `SliceAIKit/Sources/Windowing/ResultContentView.swift` — 加 `FollowUpInputBar`。
- `SliceAIKit/Sources/Windowing/ResultPanel.swift` — 加 `continueConversation(...)`（不 reset）。
- `SliceAIKit/Sources/SettingsUI/SettingsScene.swift` — 注册 History tab（5 处）。
- `SliceAIApp/AppContainer+Factories.swift` — `makeConversationStore`。
- `SliceAIApp/AppContainer.swift` — 装配 `conversationStore` + `conversationCoordinator`。
- `SliceAIApp/AppDelegate+Execution.swift` — 续聊回调接入 coordinator + per-invocation `currentAssistantText` 累积。
- `SliceAIApp/AppDelegate.swift` — `showSettings` 处把共享 `conversationStore` 注入 `SettingsScene`。
- `SliceAI.xcodeproj/project.pbxproj` — 注册新 App-target 文件 `ConversationCoordinator.swift`（4 处）。
- 文档：README / AGENTS / CLAUDE / master-todolist / Task_history / Module docs。

---

# Phase 1：会话模型 / 持久化基座

## Task 1：`FollowUpContext` 值类型 + `ExecutionSeed.followUp`

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/FollowUpContext.swift`
- Modify: `SliceAIKit/Sources/SliceCore/ExecutionSeed.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/FollowUpContextTests.swift`

- [ ] **Step 1：写失败测试** — `FollowUpContextTests.swift`

```swift
import XCTest
@testable import SliceCore

/// FollowUpContext 与 ExecutionSeed.followUp 的编解码 / 默认值测试
final class FollowUpContextTests: XCTestCase {
    /// followUp 默认为 nil，旧调用点不传也能构造 seed
    func test_executionSeed_defaultsFollowUpToNil() {
        let seed = ExecutionSeed(
            invocationId: UUID(),
            selection: SelectionSnapshot(text: "hi", source: .accessibility, length: 2, language: nil, contentType: nil),
            frontApp: AppSnapshot(bundleId: "com.apple.Safari", name: "Safari", url: nil, windowTitle: nil),
            screenAnchor: .zero,
            timestamp: Date(timeIntervalSince1970: 0),
            triggerSource: .floatingToolbar,
            isDryRun: false
        )
        XCTAssertNil(seed.followUp)
    }

    /// FollowUpContext 含历史 messages + 追问文本，可 Codable round-trip
    func test_followUpContext_codableRoundTrip() throws {
        let ctx = FollowUpContext(
            priorMessages: [
                ChatMessage(role: .user, content: "原文"),
                ChatMessage(role: .assistant, content: "译文")
            ],
            userText: "这个词怎么用？"
        )
        let data = try JSONEncoder().encode(ctx)
        let decoded = try JSONDecoder().decode(FollowUpContext.self, from: data)
        XCTAssertEqual(decoded, ctx)
        XCTAssertEqual(decoded.priorMessages.count, 2)
        XCTAssertEqual(decoded.userText, "这个词怎么用？")
    }
}
```

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter SliceCoreTests.FollowUpContextTests`
Expected: 编译失败（`FollowUpContext` / `ExecutionSeed.followUp` 未定义）。

- [ ] **Step 3：创建 `FollowUpContext.swift`**

```swift
import Foundation

/// 续聊（多轮追问）上下文。
///
/// 当一次执行是"对前一条结果的追问"时，`ExecutionSeed.followUp` 携带本类型：
/// - `priorMessages`：之前轮次的用户可见消息（仅 `user` / `assistant`，不含 agent 内部 tool 调用消息），
///   已由调用方按 10 轮滑动窗口裁剪。
/// - `userText`：本轮用户输入的追问原文（executor 直接作为新的 `user` 消息，不再套用工具的 prompt 模板）。
///
/// executor 看到非 nil 的 followUp 时，组装 `[system?, ...priorMessages, user(userText)]`，
/// 不重新渲染工具模板、不重复注入 context（选区等已在历史首轮里）。
public struct FollowUpContext: Sendable, Equatable, Codable {
    /// 窗口内的历史消息（user / assistant 交替），不含 system 与 agent 内部 tool 消息
    public let priorMessages: [ChatMessage]
    /// 本轮追问原文
    public let userText: String

    /// - Parameters:
    ///   - priorMessages: 窗口内历史消息
    ///   - userText: 本轮追问原文
    public init(priorMessages: [ChatMessage], userText: String) {
        self.priorMessages = priorMessages
        self.userText = userText
    }
}
```

- [ ] **Step 4：给 `ExecutionSeed` 加字段** — 修改 `ExecutionSeed.swift`

在结构体字段区（`runPolicy` 之后）加：

```swift
    /// 续聊上下文；nil 表示这是一次普通（首轮）执行。非 nil 时 executor 走多轮组装。
    public let followUp: FollowUpContext?
```

在 `public init(...)` 形参列表末尾加 `followUp: FollowUpContext? = nil`（带默认值，保证旧调用点不变），并在 init body 末尾加 `self.followUp = followUp`。

- [ ] **Step 5：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter SliceCoreTests.FollowUpContextTests`
Expected: PASS（2 tests）。同时 `swift build --package-path SliceAIKit` 通过，确认 `ExecutionSeed` 既有 Equatable/Codable 测试不被新可选字段破坏（可选字段缺省解码为 nil）。

- [ ] **Step 6：commit**

```bash
git add SliceAIKit/Sources/SliceCore/FollowUpContext.swift SliceAIKit/Sources/SliceCore/ExecutionSeed.swift SliceAIKit/Tests/SliceCoreTests/FollowUpContextTests.swift
git commit -m "feat(core): add FollowUpContext and ExecutionSeed.followUp for conversation follow-up"
```

---

## Task 2：`ConversationRecord` / `ConversationSummary` / `ConversationLog`

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ConversationRecord.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ConversationRecordTests.swift`

- [ ] **Step 1：写失败测试**

```swift
import XCTest
@testable import SliceCore

final class ConversationRecordTests: XCTestCase {
    private func record(id: String, turns: Int) -> ConversationRecord {
        var messages: [ChatMessage] = []
        for i in 0..<turns {
            messages.append(ChatMessage(role: .user, content: "q\(i)"))
            messages.append(ChatMessage(role: .assistant, content: "a\(i)"))
        }
        return ConversationRecord(
            id: id, toolId: "translate", toolName: "翻译",
            providerId: "p1", model: "m1",
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1),
            messages: messages
        )
    }

    /// summary 取首条 user 文本作为标题、统计轮数，并透传 provider/model（History 列表展示数据链）
    func test_summary_derivesTitleAndTurnCount() {
        let r = record(id: "c1", turns: 3)
        let s = r.summary
        XCTAssertEqual(s.id, "c1")
        XCTAssertEqual(s.toolName, "翻译")
        XCTAssertEqual(s.turnCount, 3)
        XCTAssertEqual(s.title, "q0")
        XCTAssertEqual(s.providerId, "p1")
        XCTAssertEqual(s.model, "m1")
    }

    /// 空 messages 时标题降级为占位、轮数为 0
    func test_summary_handlesEmptyMessages() {
        let r = ConversationRecord(id: "c2", toolId: "t", toolName: "T", providerId: nil, model: nil,
                                   createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: 0),
                                   messages: [])
        XCTAssertEqual(r.summary.turnCount, 0)
        XCTAssertEqual(r.summary.title, "(空会话)")
    }

    /// ConversationLog round-trip
    func test_log_codableRoundTrip() throws {
        let log = ConversationLog(schemaVersion: ConversationLog.currentSchemaVersion, conversations: [record(id: "c1", turns: 1)])
        let data = try JSONEncoder().encode(log)
        let decoded = try JSONDecoder().decode(ConversationLog.self, from: data)
        XCTAssertEqual(decoded, log)
    }
}
```

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter SliceCoreTests.ConversationRecordTests`
Expected: 编译失败（类型未定义）。

- [ ] **Step 3：创建 `ConversationRecord.swift`**

```swift
import Foundation

/// 一次完整会话的落盘记录（首轮 + 所有续聊轮的用户可见消息）。
///
/// 只保存"用户可见轮次"（`user` / `assistant`），不含 agent 内部 tool_call/tool_result——
/// 既匹配 History 的展示需求，也避免 MCP 结果原文落入明文存储。
public struct ConversationRecord: Sendable, Equatable, Codable, Identifiable {
    /// 会话 id（= 首轮 invocationId 字符串）
    public let id: String
    /// 发起工具 id
    public let toolId: String
    /// 发起工具显示名（History 列表展示）
    public let toolName: String
    /// 发起时 provider id（可空）
    public let providerId: String?
    /// 发起时 model（可空）
    public let model: String?
    /// 首轮创建时间
    public let createdAt: Date
    /// 最近一轮更新时间
    public let updatedAt: Date
    /// 用户可见消息（user / assistant 交替）
    public let messages: [ChatMessage]

    public init(id: String, toolId: String, toolName: String, providerId: String?, model: String?,
                createdAt: Date, updatedAt: Date, messages: [ChatMessage]) {
        self.id = id
        self.toolId = toolId
        self.toolName = toolName
        self.providerId = providerId
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.messages = messages
    }

    /// 列表展示用的轻量摘要（不含完整 messages）
    public var summary: ConversationSummary {
        let firstUser = messages.first(where: { $0.role == .user })?.content
        let title: String
        if let firstUser, !firstUser.isEmpty { title = String(firstUser.prefix(80)) } else { title = "(空会话)" }
        // 一轮 = 一对 user+assistant；按 assistant 条数计更稳（避免末轮无答时多计）
        let turns = messages.filter { $0.role == .assistant }.count
        return ConversationSummary(id: id, toolName: toolName, title: title, turnCount: turns,
                                   updatedAt: updatedAt, providerId: providerId, model: model)
    }
}

/// History 列表行用的轻量摘要。
public struct ConversationSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let toolName: String
    public let title: String
    public let turnCount: Int
    public let updatedAt: Date
    /// 会话锁定的 provider id（首轮 resolved 值，spec §4.1 列表展示用；可空）
    public let providerId: String?
    /// 会话锁定的 model（首轮 resolved 值，spec §4.1 列表展示用；可空）
    public let model: String?

    public init(id: String, toolName: String, title: String, turnCount: Int, updatedAt: Date,
                providerId: String?, model: String?) {
        self.id = id
        self.toolName = toolName
        self.title = title
        self.turnCount = turnCount
        self.updatedAt = updatedAt
        self.providerId = providerId
        self.model = model
    }
}

/// `conversations.json` 的顶层落盘形状。
public struct ConversationLog: Sendable, Equatable, Codable {
    /// 当前会话存储 schema 版本（独立于 Configuration.currentSchemaVersion）
    public static let currentSchemaVersion = 1
    public let schemaVersion: Int
    public let conversations: [ConversationRecord]

    public init(schemaVersion: Int, conversations: [ConversationRecord]) {
        self.schemaVersion = schemaVersion
        self.conversations = conversations
    }

    /// 空日志
    public static var empty: ConversationLog { ConversationLog(schemaVersion: currentSchemaVersion, conversations: []) }
}
```

- [ ] **Step 4：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter SliceCoreTests.ConversationRecordTests`
Expected: PASS（3 tests）。

> 注意：`ConversationSummary` 故意不带 `Codable`（纯运行时派生，照 `ResolvedExecutionContext` 不落盘惯例）；`force_unwrapping`（`firstUser!`）已被前一行 `?.isEmpty == false` guard 保证安全，但 SwiftLint 启用了 `force_unwrapping`——改写为 `if let firstUser, !firstUser.isEmpty { title = firstUser } else { title = "(空会话)" }` 形式避免强解包与豁免注释。实施时用该非强解包写法。

- [ ] **Step 5：commit**

```bash
git add SliceAIKit/Sources/SliceCore/ConversationRecord.swift SliceAIKit/Tests/SliceCoreTests/ConversationRecordTests.swift
git commit -m "feat(core): add ConversationRecord/Summary/Log value types"
```

---

## Task 3：`ConversationSession` 纯 reducer（累积 + 10 轮窗口）

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/ConversationSession.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ConversationSessionTests.swift`

- [ ] **Step 1：写失败测试**

```swift
import XCTest
@testable import SliceCore

final class ConversationSessionTests: XCTestCase {
    private func makeSession() -> ConversationSession {
        ConversationSession(
            id: "c1", toolId: "translate", toolName: "翻译",
            firstUserText: "hello", createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 首轮 finish 后：messages = [user(原文), assistant(答案)]；provider/model 被锁定到 record。
    func test_recordFirstTurn_buildsPairAndLocksProviderModel() {
        var s = makeSession()
        s.recordAssistantTurn(assistantText: "你好", providerId: "p1", model: "m1", at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(s.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(s.messages[0].content, "hello")
        XCTAssertEqual(s.messages[1].content, "你好")
        XCTAssertEqual(s.toRecord().messages.count, 2)
        XCTAssertEqual(s.lockedProviderId, "p1")
        XCTAssertEqual(s.toRecord().model, "m1")
    }

    /// 续聊：makeFollowUp 返回 priorMessages(=当前累积) + userText，未超窗口不裁剪
    func test_makeFollowUp_carriesPriorMessages_noTruncationUnderWindow() {
        var s = makeSession()
        s.recordAssistantTurn(assistantText: "你好", providerId: "p1", model: "m1", at: Date(timeIntervalSince1970: 1))
        let fu = s.makeFollowUp(userText: "再说一次")
        XCTAssertEqual(fu.context.priorMessages.map(\.role), [.user, .assistant])
        XCTAssertEqual(fu.context.userText, "再说一次")
        XCTAssertFalse(fu.truncated)
    }

    /// 续聊推进：先 makeFollowUp 再 recordFollowUpTurn，messages 增长为 4 条
    func test_recordFollowUpTurn_appendsUserThenAssistant() {
        var s = makeSession()
        s.recordAssistantTurn(assistantText: "你好", providerId: "p1", model: "m1", at: Date(timeIntervalSince1970: 1))
        _ = s.makeFollowUp(userText: "再说一次")
        s.recordFollowUpTurn(userText: "再说一次", assistantText: "你好你好", at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(s.messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(s.messages.last?.content, "你好你好")
    }

    /// 超过 10 轮：priorMessages 只保留最近 10 对，truncated == true
    func test_makeFollowUp_truncatesToWindow_andFlagsTruncated() {
        var s = makeSession()
        s.recordAssistantTurn(assistantText: "a0", providerId: "p1", model: "m1", at: Date(timeIntervalSince1970: 1))
        // 再补 10 个 user+assistant 对，使总轮数 = 11
        for i in 1...10 {
            s.recordFollowUpTurn(userText: "u\(i)", assistantText: "a\(i)", at: Date(timeIntervalSince1970: TimeInterval(i + 1)))
        }
        let fu = s.makeFollowUp(userText: "u11")
        // 窗口 = 10 对 = 20 条
        XCTAssertEqual(fu.context.priorMessages.count, ConversationSession.contextWindowTurns * 2)
        XCTAssertTrue(fu.truncated)
        // 但 record 仍保留完整历史（11 对 = 22 条）
        XCTAssertEqual(s.toRecord().messages.count, 22)
    }
}
```

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter SliceCoreTests.ConversationSessionTests`
Expected: 编译失败。

- [ ] **Step 3：创建 `ConversationSession.swift`**

```swift
import Foundation

/// 一次会话的纯逻辑状态机（App 层持有，单测覆盖）。
///
/// 职责：累积用户可见 messages、按 10 轮滑动窗口生成发给 provider 的 priorMessages、生成落盘 record。
/// 不做任何 IO / UI；窗口大小与"是否裁剪"是确定性纯函数，便于测试。
public struct ConversationSession: Sendable, Equatable {
    /// 上下文滑动窗口轮数（1 轮 = 一对 user+assistant）。质量优先、不激进裁剪。
    public static let contextWindowTurns = 10

    public let id: String
    public let toolId: String
    public let toolName: String
    public let createdAt: Date
    /// 发起时实际 resolved 的 provider/model；首轮 finish 时由 InvocationReport 锁定（仅锁一次），
    /// 后续 follow-up 沿用——满足 spec §7"会话内锁定发起时 provider/model"。
    public private(set) var lockedProviderId: String?
    public private(set) var lockedModel: String?
    /// 用户可见消息（user/assistant 交替）。首轮以 firstUserText 作为第一条 user。
    public private(set) var messages: [ChatMessage]
    public private(set) var updatedAt: Date

    public init(id: String, toolId: String, toolName: String, firstUserText: String, createdAt: Date) {
        self.id = id
        self.toolId = toolId
        self.toolName = toolName
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.messages = [ChatMessage(role: .user, content: firstUserText)]
    }

    /// 首轮答案到达：锁定 resolved provider/model（仅锁一次），记录 assistant 消息。
    public mutating func recordAssistantTurn(assistantText: String, providerId: String?, model: String?, at now: Date) {
        if lockedProviderId == nil { lockedProviderId = providerId }
        if lockedModel == nil { lockedModel = model }
        messages.append(ChatMessage(role: .assistant, content: assistantText))
        updatedAt = now
    }

    /// 生成续聊上下文：priorMessages 取窗口内、userText 为本轮追问。
    /// - Returns: context 给 ExecutionSeed.followUp；truncated 指示是否发生窗口裁剪（用于面板提示）。
    public func makeFollowUp(userText: String) -> (context: FollowUpContext, truncated: Bool) {
        let windowMessages = Self.contextWindowTurns * 2
        let truncated = messages.count > windowMessages
        let prior = truncated ? Array(messages.suffix(windowMessages)) : messages
        return (FollowUpContext(priorMessages: prior, userText: userText), truncated)
    }

    /// 续聊一轮完成后记录 user + assistant。
    public mutating func recordFollowUpTurn(userText: String, assistantText: String, at now: Date) {
        messages.append(ChatMessage(role: .user, content: userText))
        messages.append(ChatMessage(role: .assistant, content: assistantText))
        updatedAt = now
    }

    /// 生成落盘 record（保留完整历史，不受窗口影响；provider/model 用锁定值）。
    public func toRecord() -> ConversationRecord {
        ConversationRecord(id: id, toolId: toolId, toolName: toolName,
                           providerId: lockedProviderId, model: lockedModel,
                           createdAt: createdAt, updatedAt: updatedAt, messages: messages)
    }
}
```

- [ ] **Step 4：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter SliceCoreTests.ConversationSessionTests`
Expected: PASS（4 tests）。

- [ ] **Step 5：commit**

```bash
git add SliceAIKit/Sources/SliceCore/ConversationSession.swift SliceAIKit/Tests/SliceCoreTests/ConversationSessionTests.swift
git commit -m "feat(core): add ConversationSession reducer with 10-turn sliding window"
```

---

## Task 4：`ConversationStore` 落盘 actor（Capabilities）

**Files:**
- Create: `SliceAIKit/Sources/Capabilities/Conversations/ConversationStore.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/ConversationStoreTests.swift`

- [ ] **Step 1：写失败测试**

```swift
import Foundation
import SliceCore
import XCTest
@testable import Capabilities

final class ConversationStoreTests: XCTestCase {
    private func makeTemporaryFileURL() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sliceai-conv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("conversations.json")
    }

    private func record(_ id: String, updated: TimeInterval) -> ConversationRecord {
        ConversationRecord(id: id, toolId: "t", toolName: "T", providerId: nil, model: nil,
                           createdAt: Date(timeIntervalSince1970: 0), updatedAt: Date(timeIntervalSince1970: updated),
                           messages: [ChatMessage(role: .user, content: "q"), ChatMessage(role: .assistant, content: "a")])
    }

    /// upsert 新会话 → 落盘 → 读回
    func test_upsert_persistsAndRoundTrips() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL())
        try await store.upsert(record("c1", updated: 1))
        let all = try await store.recentSummaries(limit: 50)
        XCTAssertEqual(all.map(\.id), ["c1"])
        let full = try await store.record(id: "c1")
        XCTAssertEqual(full?.messages.count, 2)
    }

    /// 同 id upsert → 覆盖而非重复
    func test_upsert_sameId_replaces() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL())
        try await store.upsert(record("c1", updated: 1))
        try await store.upsert(record("c1", updated: 2))
        let all = try await store.recentSummaries(limit: 50)
        XCTAssertEqual(all.count, 1)
        XCTAssertEqual(all.first?.updatedAt, Date(timeIntervalSince1970: 2))
    }

    /// recentSummaries 按 updatedAt 倒序
    func test_recentSummaries_sortedByUpdatedDesc() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL())
        try await store.upsert(record("old", updated: 1))
        try await store.upsert(record("new", updated: 9))
        XCTAssertEqual(try await store.recentSummaries(limit: 50).map(\.id), ["new", "old"])
    }

    /// 超容量上限 → 淘汰最旧
    func test_upsert_evictsBeyondCap() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL(), maxConversations: 2)
        try await store.upsert(record("a", updated: 1))
        try await store.upsert(record("b", updated: 2))
        try await store.upsert(record("c", updated: 3))
        XCTAssertEqual(try await store.recentSummaries(limit: 50).map(\.id), ["c", "b"])
    }

    /// delete / clear
    func test_deleteAndClear() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL())
        try await store.upsert(record("a", updated: 1))
        try await store.upsert(record("b", updated: 2))
        try await store.delete(id: "a")
        XCTAssertEqual(try await store.recentSummaries(limit: 50).map(\.id), ["b"])
        try await store.clear()
        XCTAssertTrue(try await store.recentSummaries(limit: 50).isEmpty)
    }

    /// 空文件路径：读为空、不报错
    func test_loadMissingFile_returnsEmpty() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL())
        XCTAssertTrue(try await store.recentSummaries(limit: 50).isEmpty)
    }

    /// 防复活：delete 后，仍活动的内存 session 再 upsert 同 id 不得把已删会话写回
    func test_delete_thenUpsertSameId_doesNotResurrect() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL())
        try await store.upsert(record("active", updated: 1))
        try await store.delete(id: "active")
        try await store.upsert(record("active", updated: 2))   // 模拟删除后 follow-up finishTurn 再写回
        XCTAssertTrue(try await store.recentSummaries(limit: 50).isEmpty, "delete 后同 id 不得复活")
    }

    /// 防复活：clear 后，创建时刻早于清空水位的会话（含尚未 finish 的活动会话）再 upsert 不得写回
    func test_clear_thenUpsertOlderSession_doesNotResurrect() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL())
        try await store.upsert(record("active", updated: 1))   // createdAt = epoch 0
        try await store.clear()                                // clearedAt = now（real）
        try await store.upsert(record("active", updated: 2))   // createdAt epoch 0 ≤ clearedAt → 忽略
        XCTAssertTrue(try await store.recentSummaries(limit: 50).isEmpty, "clear 后旧会话不得复活")
    }

    /// 防复活水位不过度：clear 后**新**会话（创建时刻晚于水位）仍能正常保存
    func test_clear_thenNewerConversation_isSaved() async throws {
        let store = ConversationStore(fileURL: try makeTemporaryFileURL())
        try await store.upsert(record("old", updated: 1))
        try await store.clear()
        let fresh = ConversationRecord(
            id: "fresh", toolId: "t", toolName: "T", providerId: nil, model: nil,
            createdAt: Date(timeIntervalSinceNow: 60),         // 晚于 clearedAt(now)
            updatedAt: Date(timeIntervalSinceNow: 60),
            messages: [ChatMessage(role: .user, content: "q"), ChatMessage(role: .assistant, content: "a")]
        )
        try await store.upsert(fresh)
        XCTAssertEqual(try await store.recentSummaries(limit: 50).map(\.id), ["fresh"], "clear 后新会话应可保存")
    }

    /// clear 写盘失败应抛错传播（供 HistoryVM 提示用户）。"先写盘后提交水位"的顺序保证失败时
    /// clearedAt 不被改写（抛错后赋值行不执行）——不会让一次失败的清空静默吞掉后续合法 upsert。
    func test_clear_writeFailure_throws() async throws {
        // 构造不可写路径：父级位置放一个文件 → createDirectory(at: 父级) 抛错 → write 抛错
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("sliceai-conv-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        let fileAsParent = base.appendingPathComponent("not-a-dir")
        try Data().write(to: fileAsParent)                       // 占位文件，使其无法作为目录
        let store = ConversationStore(fileURL: fileAsParent.appendingPathComponent("conversations.json"))
        do {
            try await store.clear()
            XCTFail("clear 在不可写路径应抛错")
        } catch {
            // 期望：write 失败抛错传播；水位提交在 write 之后，故此处未提交（由代码顺序保证）
        }
    }
}
```

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter CapabilitiesTests.ConversationStoreTests`
Expected: 编译失败（`ConversationStore` 未定义）。

- [ ] **Step 3：创建 `ConversationStore.swift`**

```swift
import Foundation
import OSLog
import SliceCore

/// 会话历史落盘存储。明文本地、独立于 config-v2.json / Keychain / audit.jsonl。
///
/// 单个 `conversations.json`（`ConversationLog`），`update { inout }` 原子读改写，照 MCPServerStore 模式。
/// 日志只记条数/字节，绝不记会话内容（隐私护栏 D8）。
public actor ConversationStore {
    private let fileURL: URL
    private let maxConversations: Int
    private let log = Logger(subsystem: "com.sliceai.capabilities", category: "ConversationStore")

    /// 进程内"防复活"状态：已删除的会话 id（tombstone）+ 最近一次清空的水位时刻。
    /// 场景：用户在活动会话仍开 / 首轮未 finish 时删除该会话或清空全部历史，内存里的
    /// `ConversationSession` 仍持旧明文，之后 `finishTurn` 会再 `upsert` → 把已删内容写回磁盘，
    /// 撤销用户删除（违反 spec「必须给删除权」+ D8 隐私）。据此忽略这类写回。
    /// **仅进程内**：重启后磁盘已是删除后的状态、内存 session 也不存在，故无需持久化。
    private var deletedIDs: Set<String> = []
    private var clearedAt: Date?

    /// - Parameters:
    ///   - fileURL: 落盘路径；nil 走标准 App Support 路径。
    ///   - maxConversations: 容量上限，超出淘汰最旧；默认 200。
    public init(fileURL: URL? = nil, maxConversations: Int = 200) {
        self.fileURL = fileURL ?? Self.standardFileURL()
        self.maxConversations = max(1, maxConversations)
    }

    /// 标准路径 `~/Library/Application Support/SliceAI/conversations.json`
    public static func standardFileURL() -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("conversations.json")
    }

    /// upsert 一条会话（同 id 覆盖），按 updatedAt 排序并裁到容量上限后原子写盘。
    /// 防复活：若该 id 已被本进程删除、或会话创建时刻 ≤ 最近清空水位（即清空发生在其之后），
    /// 则忽略这次写回（多半来自仍活动的内存 session 的后续 finishTurn），不撤销用户删除。
    public func upsert(_ record: ConversationRecord) throws {
        if deletedIDs.contains(record.id) {
            log.debug("upsert ignored: id tombstoned (deleted in this session)")
            return
        }
        if let clearedAt, record.createdAt <= clearedAt {
            log.debug("upsert ignored: record predates clearAll watermark")
            return
        }
        try update { conversations in
            conversations.removeAll { $0.id == record.id }
            conversations.append(record)
        }
    }

    /// 最近会话摘要（按 updatedAt 倒序，取前 limit 条）。
    public func recentSummaries(limit: Int) throws -> [ConversationSummary] {
        let log = try load()
        return log.conversations
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(max(0, limit))
            .map { $0.summary }
    }

    /// 取某条完整会话。
    public func record(id: String) throws -> ConversationRecord? {
        try load().conversations.first { $0.id == id }
    }

    /// 删除一条，并 tombstone 该 id：阻止仍活动的内存 session 之后把它写回（防复活）。
    public func delete(id: String) throws {
        try update { $0.removeAll { $0.id == id } }
        deletedIDs.insert(id)
    }

    /// 清空全部，并记录清空水位：忽略此刻之前创建的会话之后的写回（含尚未 finish 的活动会话，防复活）。
    /// 顺序关键：**先 durable 写盘成功，再提交水位**——否则一次失败的清空（写盘异常）会留下水位，
    /// 静默吞掉后续合法 upsert（失败操作不应改变持久化语义）。`try write` 抛错时下一行不执行，水位不变。
    public func clear() throws {
        let watermark = Date()
        try write(.empty)
        clearedAt = watermark
    }

    // MARK: - Private

    private func update(_ mutate: (inout [ConversationRecord]) -> Void) throws {
        var conversations = try load().conversations
        mutate(&conversations)
        // 容量上限：按 updatedAt 保留最近 maxConversations 条
        if conversations.count > maxConversations {
            conversations = Array(conversations.sorted { $0.updatedAt > $1.updatedAt }.prefix(maxConversations))
        }
        try write(ConversationLog(schemaVersion: ConversationLog.currentSchemaVersion, conversations: conversations))
    }

    private func load() throws -> ConversationLog {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return .empty }
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            log.error("conversations read failed: \(error.localizedDescription, privacy: .private)")
            throw SliceError.configuration(.invalidJSON("<redacted>"))
        }
        do {
            return try JSONDecoder().decode(ConversationLog.self, from: data)
        } catch {
            log.error("conversations decode failed: \(error.localizedDescription, privacy: .private)")
            throw SliceError.configuration(.invalidJSON("<redacted>"))
        }
    }

    private func write(_ logValue: ConversationLog) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(logValue)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
        log.debug("conversations wrote \(data.count, privacy: .public) bytes, count=\(logValue.conversations.count, privacy: .public)")
    }
}
```

- [ ] **Step 4：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter CapabilitiesTests.ConversationStoreTests`
Expected: PASS（10 tests）。

- [ ] **Step 5：commit**

```bash
git add SliceAIKit/Sources/Capabilities/Conversations/ConversationStore.swift SliceAIKit/Tests/CapabilitiesTests/ConversationStoreTests.swift
git commit -m "feat(capabilities): add ConversationStore for local plaintext history"
```

---

# Phase 2：续聊执行链 + ResultPanel 多轮 UX

## Task 5：`PromptExecutor` 续聊分支

**Files:**
- Modify: `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`（`renderMessages`, ~L240-260）
- Test: `SliceAIKit/Tests/OrchestrationTests/PromptExecutorTests.swift`（新增 case）

- [ ] **Step 1：写失败测试**（新增到现有 `PromptExecutorTests`）

```swift
/// 续聊：resolved.seed.followUp 非 nil 时，messages = [system?, ...priorMessages, user(followUpText)]，
/// 不再渲染工具 userPrompt 模板。
func test_run_withFollowUp_assemblesHistoryAndFollowUpUser() async throws {
    let prior = [ChatMessage(role: .user, content: "原文"), ChatMessage(role: .assistant, content: "译文")]
    let seed = makeSeed(followUp: FollowUpContext(priorMessages: prior, userText: "这个词怎么用"))
    let resolved = makeResolved(seed: seed)               // helper：把 seed 包进 ResolvedExecutionContext
    let promptTool = makePromptTool(system: "你是翻译", userPrompt: "翻译：{{selection}}")
    let provider = makeProvider()
    let mockLLM = MockLLMProvider(chunks: [ChatChunk(delta: "用法是", finishReason: nil)])
    let executor = makePromptExecutor(llm: mockLLM)       // 现有 helper

    let stream = await executor.run(promptTool: promptTool, resolved: resolved, provider: provider)
    _ = try await collectPromptElements(stream)

    let sent = try XCTUnwrap(mockLLM.capturedRequest)
    XCTAssertEqual(sent.messages.map(\.role), [.system, .user, .assistant, .user])
    XCTAssertEqual(sent.messages[0].content, "你是翻译")     // system 仍来自工具
    XCTAssertEqual(sent.messages[1].content, "原文")
    XCTAssertEqual(sent.messages[2].content, "译文")
    XCTAssertEqual(sent.messages[3].content, "这个词怎么用") // 末条 = 追问原文，未套模板
}
```

> 若现有 `PromptExecutorTests` 缺 `makeSeed(followUp:)` / `makeResolved(seed:)` helper，在测试文件内新增最小 helper（参照本测试 target 既有 `makeStubSeed` / `makeResolved`）。

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.PromptExecutorTests/test_run_withFollowUp_assemblesHistoryAndFollowUpUser`
Expected: FAIL（当前 renderMessages 忽略 followUp，断言 `[.system,.user]` 长度不符）。

- [ ] **Step 3：改 `renderMessages` 加分支**

把 `renderMessages(promptTool:resolved:)` body 改为：先算 system（保持原模板渲染），再按 followUp 分支：

```swift
private func renderMessages(promptTool: PromptTool, resolved: ResolvedExecutionContext) -> [ChatMessage] {
    var variables: [String: String] = promptTool.variables
    variables["selection"] = resolved.selection.text
    variables["app"] = resolved.frontApp.name
    variables["url"] = resolved.frontApp.url?.absoluteString ?? ""
    if variables["language"] == nil { variables["language"] = "" }

    var messages: [ChatMessage] = []
    if let sys = promptTool.systemPrompt, !sys.isEmpty {
        messages.append(ChatMessage(role: .system, content: PromptTemplate.render(sys, variables: variables)))
    }
    if let followUp = resolved.seed.followUp {
        // 续聊：system 之后接历史，再接本轮追问原文（不套用 userPrompt 模板）
        messages.append(contentsOf: followUp.priorMessages)
        messages.append(ChatMessage(role: .user, content: followUp.userText))
    } else {
        // 首轮：渲染工具 userPrompt 模板
        messages.append(ChatMessage(role: .user, content: PromptTemplate.render(promptTool.userPrompt, variables: variables)))
    }
    return messages
}
```

- [ ] **Step 4：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.PromptExecutorTests`
Expected: PASS（含新 case + 既有 case 不回归）。

- [ ] **Step 5：commit**

```bash
git add SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift SliceAIKit/Tests/OrchestrationTests/PromptExecutorTests.swift
git commit -m "feat(orchestration): assemble history+followup messages in PromptExecutor"
```

---

## Task 6：`AgentExecutor` 续聊分支（继承 skill + MCP）

**Files:**
- Modify: `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`（`buildInitialMessages`, ~L20-40）
- Test: `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`（新增 case）

- [ ] **Step 1：写失败测试**

```swift
/// agent 续聊：followUp 非 nil 时，messages = [system?, ...priorMessages, user(追问 + skill metadata)]，
/// 且 catalog（skill+MCP）由同一 agent 重建——验证请求里 tools 仍含 MCP/skill pseudo-tool。
func test_run_withFollowUp_carriesHistory_andRebuildsSkillMcpCatalog() async throws {
    let prior = [ChatMessage(role: .user, content: "翻译这段"), ChatMessage(role: .assistant, content: "结果")]
    let seed = makeSeed(followUp: FollowUpContext(priorMessages: prior, userText: "查下这个词"))
    let resolved = makeResolved(seed: seed)
    let agent = makeAgentTool(system: "你是助手", skills: [makeSkillRef()], mcpAllowlist: [makeMCPRef()])
    let mockLLM = MockToolCallingLLMProvider(turns: [[.textDelta("好的"), .finished]])
    let executor = makeAgentExecutor(llm: mockLLM, mcp: MockMCPClient(tools: [makeMCPTool()]))

    let stream = await executor.run(tool: makeTool(agent), agent: agent, resolved: resolved, provider: makeProvider())
    _ = try await collectEvents(stream)

    let req = try XCTUnwrap(mockLLM.capturedToolRequests.first)
    XCTAssertEqual(req.messages.first?.role, .system)
    XCTAssertEqual(req.messages.map(\.role), [.system, .user, .assistant, .user])
    XCTAssertEqual(req.messages[1].content, "翻译这段")
    XCTAssertTrue(req.messages.last?.content?.contains("查下这个词") == true)
    XCTAssertTrue(req.messages.last?.content?.contains("Available SliceAI skills") == true) // 重挂 skill metadata
    XCTAssertFalse(req.tools.isEmpty)                                                        // MCP+skill catalog 重建
}
```

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests/test_run_withFollowUp_carriesHistory_andRebuildsSkillMcpCatalog`
Expected: FAIL（buildInitialMessages 当前忽略 followUp）。

- [ ] **Step 3：改 `AgentPromptBuilder.buildInitialMessages` 加 follow-up 分支（保留既有渲染）**

> 关键（Finding 1）：**保留现有 `makeVariables` + `PromptTemplate.render` 渲染与非 follow-up 分支原样**，只在 system 之后插入 follow-up 早返回分支——否则既有 Agent 的 `{{selection}}`/`{{app}}` 占位符会泄漏给模型，回归现有读取链。`appendContextBag(_:resolved:)` 与 `appendSkillMetadata(_:boundSkills:)` 是返回 `String` 的现有 `private static` helper（**非 inout**）；`boundSkills` 类型是 `[Skill]`。

```swift
static func buildInitialMessages(
    agent: AgentTool,
    resolved: ResolvedExecutionContext,
    boundSkills: [Skill] = []
) -> [ChatMessage] {
    let variables = makeVariables(resolved: resolved)
    var messages: [ChatMessage] = []
    if let systemPrompt = agent.systemPrompt, !systemPrompt.isEmpty {
        messages.append(ChatMessage(role: .system, content: PromptTemplate.render(systemPrompt, variables: variables)))
    }
    if let followUp = resolved.seed.followUp {
        // 续聊：system 仍走上面的模板渲染；接历史；本轮 user = 追问原文 + 重挂 skill metadata。
        // 不渲染 initialUserPrompt 模板、不注入 context bag（选区等已在历史首轮里）。
        messages.append(contentsOf: followUp.priorMessages)
        messages.append(ChatMessage(role: .user, content: appendSkillMetadata(followUp.userText, boundSkills: boundSkills)))
        return messages
    }
    // 首轮：原逻辑保持不变（渲染 initialUserPrompt + context bag + skill metadata）
    let userPrompt = PromptTemplate.render(agent.initialUserPrompt, variables: variables)
    let promptWithContext = appendContextBag(userPrompt, resolved: resolved)
    messages.append(ChatMessage(role: .user, content: appendSkillMetadata(promptWithContext, boundSkills: boundSkills)))
    return messages
}
```

- [ ] **Step 4：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests`
Expected: PASS（含新 case + 既有 ReAct case 不回归）。

- [ ] **Step 5：commit**

```bash
git add SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift
git commit -m "feat(orchestration): agent follow-up inherits skills+mcp and carries history"
```

---

## Task 7：`ResultViewModel` 续聊状态（回调 + 上下文提示 + 不重置追加）

**Files:**
- Modify: `SliceAIKit/Sources/Windowing/ResultViewModel.swift`
- Test: `SliceAIKit/Tests/WindowingTests/ResultViewModelFollowUpTests.swift`（新建，纯逻辑）

- [ ] **Step 1：写失败测试**

```swift
import XCTest
@testable import Windowing

@MainActor
final class ResultViewModelFollowUpTests: XCTestCase {
    /// beginFollowUpTurn：不清空已有 text，追加分隔 + "你：" 块，状态回到 thinking
    func test_beginFollowUpTurn_appendsSeparatorWithoutReset() {
        let vm = ResultViewModel()
        vm.reset(toolName: "翻译", model: "m")
        vm.append("译文")
        vm.finish()
        vm.beginFollowUpTurn("这个词怎么用")
        XCTAssertTrue(vm.text.contains("译文"))         // 上一轮保留
        XCTAssertTrue(vm.text.contains("这个词怎么用"))   // 追问回显
        XCTAssertEqual(vm.streamingState, .thinking)     // 等待新答案
    }

    /// contextNotice 可设置/清除，供 UI 展示窗口裁剪提示
    func test_contextNotice_setAndClear() {
        let vm = ResultViewModel()
        vm.contextNotice = "会话较长，较早内容已不在上下文"
        XCTAssertNotNil(vm.contextNotice)
        vm.reset(toolName: "x", model: "")               // model 非可选 String
        XCTAssertNil(vm.contextNotice)                   // reset 清除
    }

    /// retryFollowUpTurn：失败后回滚本轮 partial（保留上一轮 + 用户块），清错误，状态回 thinking
    func test_retryFollowUpTurn_rewindsPartialAndClearsError() {
        let vm = ResultViewModel()
        vm.reset(toolName: "翻译", model: "m")
        vm.append("译文")                                 // 首轮答案
        vm.finish()
        vm.beginFollowUpTurn("这个词怎么用")               // 追问回显 + 记 checkpoint
        vm.append("部分答案")                             // 续聊轮流出 partial 后失败
        vm.fail(message: "网络错误", detail: "<redacted>", onRetry: {}, onOpenSettings: nil)
        XCTAssertEqual(vm.streamingState, .error)

        vm.retryFollowUpTurn()
        XCTAssertTrue(vm.text.contains("译文"))            // 上一轮保留
        XCTAssertTrue(vm.text.contains("这个词怎么用"))     // 用户块保留
        XCTAssertFalse(vm.text.contains("部分答案"))        // 失败轮 partial 已回滚
        XCTAssertNil(vm.errorMessage)                     // 错误态已清
        XCTAssertEqual(vm.streamingState, .thinking)      // 回到等待答案
    }
}
```

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter WindowingTests.ResultViewModelFollowUpTests`
Expected: 编译失败（`beginFollowUpTurn` / `contextNotice` 未定义）。

- [ ] **Step 3：改 `ResultViewModel.swift`**

> 注意：`ResultViewModel` 是 internal `final class`，新增成员一律 internal（不可 `public`，否则成员可见性高于 enclosing type，编译失败）。ResultPanel 同模块、测试用 `@testable import Windowing`，internal 即可访问。

加 `@Published`（internal）：

```swift
    /// 上下文窗口裁剪等非阻塞提示；nil 表示无提示。reset 时清除。
    @Published var contextNotice: String?
    /// 是否允许续聊（仅 window DisplayMode 为 true；reset 默认 false，App 绑定 handler 时置 true）。
    @Published var canFollowUp = false
    /// 是否显示 header「重新生成」按钮（仅非 window 一次性结果模式为 true；window 会话禁用——
    /// 避免重跑首轮/覆盖会话/污染 History）。由 `ResultPanel.open` 按打开进面板的模式设定，
    /// 与 `canFollowUp` **解耦**：否则非 window 执行清 canFollowUp 时会让被钉 window 会话错误重现
    /// regenerate（round-9）。默认 true（非会话面板可重新生成，沿用既有行为）。
    @Published var allowsRegenerate = true
    /// 用户提交追问的回调（App 层接管：带 history 再 execute）。
    var onSubmitFollowUp: (@MainActor (String) -> Void)?
    /// 本轮续聊「assistant 输出前」的 transcript 快照（含刚追加的用户块）；失败重试据此回滚。
    /// 非 `@Published`：纯内部锚点，不直接驱动 UI（由 text 的变化驱动渲染）。
    private var followUpCheckpoint = ""
```

在 `reset(toolName:model:)` body 内补 `contextNotice = nil`、`canFollowUp = false`、`allowsRegenerate = true`。这是**瞬态会话模型**的核心（round-14，用户拍板）：`ResultPanel.open()` 每次开窗/接管面板都调 `reset()`，故 reset 必须把上一占用者的会话 UI 状态清回"无会话"默认（无续聊入口、允许重新生成）；随后由 `openResultPanel` 按当前 tool 模式重设（见 Task 10 (c)）。**无条件清空是正确的**——被其他执行/失败接管面板时，旧会话面板内 UI 本就该结束（会话仍在 History）。

加方法（不清 `text`）：

```swift
    /// 开始一轮续聊：保留已有 transcript，追加分隔与用户追问块，状态回到等待答案。
    func beginFollowUpTurn(_ userText: String) {
        text += "\n\n---\n\n**你：** \(userText)\n\n"
        followUpCheckpoint = text      // 锚点：本轮 assistant 输出前的 transcript（含用户块），供失败重试回滚
        toolCallStore.reset()          // 新一轮 tool-call 行从空开始：必须重置 store，否则下一轮 upsert 会把上一轮旧调用一并 republish
        toolCalls = toolCallStore.calls
        structuredFields = nil
        errorMessage = nil             // 进入新一轮，清掉上一轮可能残留的错误态
        errorDetail = nil
        streamingState = .thinking
    }

    /// 失败后重试当前续聊轮：把 transcript 回滚到本轮 assistant 输出前（保留用户块），清错误/工具行/结构化，
    /// 状态回到等待答案。镜像首轮「retry 走 reset 清空再重来」的语义——否则 append 只从 .thinking→.streaming、
    /// 不会从 .error 恢复，新答案会拼到失败轮的 partial 文本之后，且面板卡在错误态直到 finished。
    func retryFollowUpTurn() {
        text = followUpCheckpoint
        errorMessage = nil
        errorDetail = nil
        toolCallStore.reset()          // 同 beginFollowUpTurn：重置 store 而非只清已发布数组
        toolCalls = toolCallStore.calls
        structuredFields = nil
        streamingState = .thinking
    }
```

- [ ] **Step 4：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter WindowingTests.ResultViewModelFollowUpTests`
Expected: PASS（3 tests）。

- [ ] **Step 5：commit**

```bash
git add SliceAIKit/Sources/Windowing/ResultViewModel.swift SliceAIKit/Tests/WindowingTests/ResultViewModelFollowUpTests.swift
git commit -m "feat(windowing): add follow-up turn state to ResultViewModel"
```

---

## Task 8：`FollowUpInputBar` 视图 + ResultContent 接入（手测 UI）

**Files:**
- Modify: `SliceAIKit/Sources/Windowing/ResultContentView.swift`

- [ ] **Step 1：加 `FollowUpInputBar` 子视图**（文件内 `private struct`）

```swift
/// 结果流结束后出现的追问输入条：单行输入 + 发送按钮，仅 finished 态可用。
private struct FollowUpInputBar: View {
    @ObservedObject var viewModel: ResultViewModel
    @State private var draft = ""

    var body: some View {
        VStack(spacing: 4) {
            if let notice = viewModel.contextNotice {
                Text(notice)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                TextField("继续追问…", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .onSubmit(submit)
                Button("发送", action: submit)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func submit() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        viewModel.onSubmitFollowUp?(text)
    }
}
```

- [ ] **Step 2：接入 `ResultContent.body`**

在 `VStack` 底部、`contentArea` 之后插入（仅 **window 模式**`canFollowUp` 且 finished 态显示——满足 spec D7：structured/bubble/tts 不出续聊入口；且避免流式中输入）：

```swift
            if viewModel.canFollowUp && viewModel.streamingState == .finished {
                Divider()
                FollowUpInputBar(viewModel: viewModel)
            }
```

- [ ] **Step 3：窗口模式禁用 header『重新生成』按钮**

`ResultContentView.headerBar` 现有「重新生成」`IconButton`（约 L136-139，调 `viewModel.onRegenerate?()`）在续聊/窗口模式下是错误的 re-trigger 入口：它绑定到首轮 `execute`（`openResultPanel` 的 `open(onRegenerate:)`），续聊中/后点击会重跑首轮、reset 面板、覆盖 `ConversationCoordinator` 当前 session，并在 History 多生成一条首轮记录。v1.0 决策（用户确认）：**窗口/续聊模式隐藏该按钮**，仅在非窗口模式保留。门控信号用**独立**的 `allowsRegenerate`（由 `ResultPanel.open` 按打开进面板的模式设定：window=false、其余=true）——**不复用 `canFollowUp`**，否则非 window 执行清 `canFollowUp` 会让被钉 window 会话错误重现 regenerate（round-9）：

把现有按钮：

```swift
            // 重新生成：cancel 旧 stream 并重新触发同一 tool + payload
            IconButton(systemName: "arrow.clockwise", size: .small, help: "重新生成") {
                viewModel.onRegenerate?()
            }
```

改为仅 `allowsRegenerate` 时显示：

```swift
            // 重新生成：仅非窗口一次性结果模式可用——窗口/续聊模式隐藏，避免重跑首轮/覆盖会话/污染 History。
            // 续聊轮的「重做」由失败态 Retry（mode-aware，见 Task 10）承担；正确的多轮重新生成推后到 1.0 之后。
            if viewModel.allowsRegenerate {
                IconButton(systemName: "arrow.clockwise", size: .small, help: "重新生成") {
                    viewModel.onRegenerate?()
                }
            }
```

> 注：`allowsRegenerate` 由 App 层在 `openResultPanel`（仅 window / structured 运行）调 `setAllowsRegenerate(tool.displayMode != .window)` 设定；非面板模式（bubble/replace/file/silent）不经此、不动共享面板。故此门控等价于"仅 structured 等一次性结果模式显示重新生成"，与 spec D7「续聊入口仅 window」对称，且不受"被钉 window 会话 + 后续非 window 工具"干扰（round-9）。

- [ ] **Step 4：构建确认**

Run: `swift build --package-path SliceAIKit` 然后 `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
Expected: BUILD SUCCEEDED。（NSPanel/SwiftUI 渲染靠手测，见最终 smoke。）

- [ ] **Step 5：commit**

```bash
git add SliceAIKit/Sources/Windowing/ResultContentView.swift
git commit -m "feat(windowing): add follow-up input bar; gate regenerate to non-window modes"
```

---

## Task 9：`ResultPanel.continueConversation`（续聊入口，不 reset）

**Files:**
- Modify: `SliceAIKit/Sources/Windowing/ResultPanel.swift`

- [ ] **Step 1：加方法**（`append`/`finish` 附近）

```swift
    /// 进入续聊一轮：保留面板与已有 transcript（不 open / 不 reset），追加用户追问块。
    /// - Parameters:
    ///   - userText: 追问原文（用于 transcript 回显）
    ///   - contextNotice: 窗口裁剪提示；nil 清除
    public func continueConversation(userText: String, contextNotice: String?) {
        viewModel.contextNotice = contextNotice
        viewModel.beginFollowUpTurn(userText)
    }

    /// 续聊轮失败后重试：回滚本轮 partial 到用户块之后、清错误态（不重复追加用户块）。
    /// App 层的 follow-up retry 闭包在重启执行流前调用，避免新答案拼到失败 partial 之后。
    public func retryFollowUpTurn() {
        viewModel.retryFollowUpTurn()
    }

    /// 设置/更新续聊提交回调并开启续聊入口（App 层仅在 window 模式 open 后绑定）。
    public func setFollowUpHandler(_ handler: (@MainActor (String) -> Void)?) {
        viewModel.onSubmitFollowUp = handler
        viewModel.canFollowUp = (handler != nil)
    }

    /// 设定 header「重新生成」按钮是否可用（App 层在 open 后按打开进面板的模式设定：window=false、其余=true）。
    /// 与续聊入口解耦，避免非 window 执行清 canFollowUp 时被钉 window 会话错误重现 regenerate（round-9）。
    public func setAllowsRegenerate(_ value: Bool) {
        viewModel.allowsRegenerate = value
    }
```

- [ ] **Step 2：构建确认**

Run: `swift build --package-path SliceAIKit`
Expected: 通过。

- [ ] **Step 3：commit**

```bash
git add SliceAIKit/Sources/Windowing/ResultPanel.swift
git commit -m "feat(windowing): add continueConversation entry to ResultPanel"
```

---

## Task 10：`InvocationReport` resolved 元数据 + App 层 `ConversationCoordinator` + 装配 + 落盘 + pbxproj

**Files:**
- Modify（Step 0，Orchestration）：`SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`、`SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Terminal.swift`、`SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`、`SliceAIKit/Sources/Orchestration/Telemetry/JSONLAuditLog.swift`
- Test（Step 0）：`SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- Create: `SliceAIApp/ConversationCoordinator.swift`
- Modify: `SliceAIApp/AppDelegate.swift`（新增实例存储属性，见下）、`SliceAIApp/AppContainer+Factories.swift`、`SliceAIApp/AppContainer.swift`、`SliceAIApp/AppDelegate+Execution.swift`、`SliceAI.xcodeproj/project.pbxproj`

> 本任务分两段：**Step 0 是 Orchestration 改动（有 OrchestrationTests 单测）**，让 `.finished(report:)` 携带运行时 resolved provider/model；Step 1-8 是 App-target 装配（无单测，靠 `xcodebuild` 编译 + 真实 App smoke 验收）。会话纯逻辑（窗口/累积/锁定）已在 Task 3 单测覆盖。
>
> **为什么需要 Step 0（spec §7 对齐 + Finding 1/round-4 根因）**：续聊必须锁定首轮"实际生效"的 provider/model，否则用户中途改配置会把后续追问路由到另一端点，撕裂同一会话的语义；History 也要展示真实用过的 provider/model。`ProviderSelection.fixed` 的静态 `modelId` 可能为 `nil`（由 `provider.defaultModel` 兜底），且 `.cascade`/`.capability` 根本不带具体值——**只能从执行链运行时 resolved 的 `Provider` + `resolveSelectedModel` 捕获**（与 `CostRecord.providerId/model` 同源）。因此把这两个值补进 `InvocationReport`，由 App 层在首轮 `.finished` 时锁定。

- [ ] **Step 0a：写失败测试（OrchestrationTests）**

在 `ExecutionEngineTests.swift` 追加（紧跟现有 happy-path 测试；复用其 `makeEngine` / `makeStubTool` / `makeStubSeed` / `collectEvents` 骨架）：

```swift
    /// round-4：成功终态 `.finished(report)` 必须携带运行时 resolved provider/model，
    /// 这是续聊会话锁定 + History 展示的唯一可靠来源（静态 ProviderSelection.fixed.modelId 可能为 nil）。
    func test_execute_happy_reportCarriesResolvedProviderAndModel() async throws {
        let bundle = try makeEngine(
            chunks: [ChatChunk(delta: "hi", finishReason: nil)]
        )
        let tool = makeStubTool()       // 默认 .fixed(providerId: "test-provider", modelId: nil)
        let seed = makeStubSeed()

        let events = await collectEvents(from: bundle.engine.execute(tool: tool, seed: seed))

        let report = try XCTUnwrap(events.compactMap { event -> InvocationReport? in
            if case .finished(let report) = event { return report }
            return nil
        }.first, "happy path should yield a .finished report")
        // MockProviderResolver 默认返回 openAIStub（id="openai-stub", defaultModel="gpt-5"）；
        // tool 选 modelId=nil → resolveSelectedModel 兜底 provider.defaultModel。
        XCTAssertEqual(report.resolvedProviderId, "openai-stub")
        XCTAssertEqual(report.resolvedModel, "gpt-5")
    }
```

- [ ] **Step 0b：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.ExecutionEngineTests/test_execute_happy_reportCarriesResolvedProviderAndModel`
Expected: 编译失败（`InvocationReport` 无 `resolvedProviderId` / `resolvedModel` 成员）。

- [ ] **Step 0c：实现 —— `InvocationReport` 加两可选字段 + 引擎在成功终态填充 + audit 透传**

(1) `InvocationReport.swift`：在 `outcome` 后加两个可选 `let` 字段 + memberwise init 形参（**`= nil` 默认值保证向后兼容**，所有旧构造点不破）+ `#if DEBUG stub` 同步加 `= nil` 形参：

```swift
    /// 本次执行运行时实际解析出的 provider id（续聊锁定 + History 展示用）；
    /// 失败 / 未实现 / 早期短路路径为 nil（彼时尚未 resolve provider）。
    public let resolvedProviderId: String?
    /// 本次执行实际请求的 model（= CostRecord.model 同源：fixed.modelId ?? provider.defaultModel）；同上为可选。
    public let resolvedModel: String?
```

init 形参表在 `outcome: InvocationOutcome` 后追加：

```swift
        outcome: InvocationOutcome,
        resolvedProviderId: String? = nil,
        resolvedModel: String? = nil
```

init 体末尾追加：

```swift
        self.resolvedProviderId = resolvedProviderId
        self.resolvedModel = resolvedModel
```

`stub(...)` 形参表追加 `resolvedProviderId: String? = nil, resolvedModel: String? = nil`，并在内部 `InvocationReport(...)` 调用末尾透传这两个值。

(2) `ExecutionEngine+Terminal.swift` 的 `makeReport(...)`：形参表加 `resolvedProviderId: String? = nil, resolvedModel: String? = nil`，并在其构造的 `InvocationReport(...)` 末尾透传。`finishFailure` / `finishNotImplementedKind` 不传（保持 nil——失败/未实现没有可靠 resolved 值）。

(3) `ExecutionEngine+Steps.swift` 的 `recordCostAndFinishSuccess(...)`：`makeReport(...)` 调用处补两个实参——它们与上一行 `CostRecord` 用的是**同源** `provider.id` / `model`：

```swift
        let report = makeReport(
            context: context,
            finishedAt: Date(),
            tokens: usage.inputTokens + usage.outputTokens,
            costUSD: costUSD,
            outcome: context.runPolicy.sideEffects == .dryRun ? .dryRunCompleted : .success,
            resolvedProviderId: provider.id,
            resolvedModel: model
        )
```

（prompt 与 agent 两条流水线都经此 helper 收口，一处改动两条路径都覆盖。）

(4) `JSONLAuditLog.swift` 的 `scrubEntry(_:)` 重建 `InvocationReport` 处：透传 `resolvedProviderId: report.resolvedProviderId, resolvedModel: report.resolvedModel`。provider id / model 是稳定非 PII 标识（与已保留的 `Permission` host/bundleId/path 同类，见该函数现有"稳定标识符保留"注释），不脱敏；否则 audit 与 `.finished` 事件会出现字段漂移。

- [ ] **Step 0d：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.ExecutionEngineTests`
Expected: PASS（新测试 + 原有用例全绿——新字段 `= nil` 默认值不破坏既有断言）。

- [ ] **Step 1：创建 `ConversationCoordinator.swift`**

```swift
import Capabilities
import Foundation
import SliceCore

/// App 层续聊编排：持有当前会话 ConversationSession，驱动续聊 execute，并把每轮结果落盘到 ConversationStore。
/// @MainActor：与 ResultPanel / AppDelegate 同 actor，便于读取 viewModel.text 取上一轮答案。
@MainActor
final class ConversationCoordinator {
    private let store: ConversationStore
    /// 当前活动会话（一次 open 一个；新 open 覆盖）。
    private var session: ConversationSession?

    init(store: ConversationStore) {
        self.store = store
    }

    /// 首轮开始：用首条用户文本（选区原文）建会话。
    /// provider/model **不**在此锁定——发起时只有静态 `ProviderSelection`（可能不含具体 model，或为 .cascade/.capability）；
    /// 真实 resolved 值在首轮 `finishTurn` 时由 `InvocationReport` 注入并锁定（见本任务 Step 0）。
    func startConversation(invocationId: UUID, toolId: String, toolName: String,
                           firstUserText: String, now: Date) {
        session = ConversationSession(id: invocationId.uuidString, toolId: toolId, toolName: toolName,
                                      firstUserText: firstUserText, createdAt: now)
    }

    /// 一轮（首轮或续聊）答案完成：记录 assistant，落盘。
    /// - Parameters:
    ///   - isFollowUp: true 表示这轮是续聊（需先记 user 再记 assistant）。
    ///   - providerId/model: 本轮 `.finished(report)` 的 resolved 值；仅首轮真正锁定（`ConversationSession` 内 lock-once，续聊轮忽略）。
    func finishTurn(userText: String?, assistantText: String, isFollowUp: Bool,
                    providerId: String?, model: String?, now: Date) async {
        guard var s = session else { return }
        if isFollowUp, let userText { s.recordFollowUpTurn(userText: userText, assistantText: assistantText, at: now) }
        else { s.recordAssistantTurn(assistantText: assistantText, providerId: providerId, model: model, at: now) }
        session = s
        do { try await store.upsert(s.toRecord()) }
        catch { /* 落盘失败不阻断 UI；隐私护栏：不打印内容 */ }
    }

    /// 生成续聊 follow-up（供构造新 seed）。
    func makeFollowUp(userText: String) -> (context: FollowUpContext, truncated: Bool)? {
        session?.makeFollowUp(userText: userText)
    }

    /// 当前会话已锁定的 provider/model（首轮答案落盘后非 nil）；续聊据此把 tool 的 `ProviderSelection`
    /// 覆写为 `.fixed(lockedProviderId, lockedModel)`，避免用户中途改配置改了后续追问的路由（spec §7 会话内锁定）。
    var lockedProviderId: String? { session?.lockedProviderId }
    var lockedModel: String? { session?.lockedModel }

    /// 结束当前会话（面板 dismiss 时调用）。
    func endConversation() { session = nil }
}
```

- [ ] **Step 2：`AppContainer+Factories.swift` 加工厂**

参照第 41 行 MCPServerStore / `static func makeMCPRuntime`，在 store 工厂区加（**必须 `static`**——现有 `AppContainer+Factories` 全是 static 上下文）：

```swift
    /// 会话历史存储（落盘到 App Support/conversations.json）。
    static func makeConversationStore(appSupport: URL) -> ConversationStore {
        ConversationStore(fileURL: appSupport.appendingPathComponent("conversations.json"))
    }
```

- [ ] **Step 3：`AppContainer.swift` 装配**

- 加字段（第 90 行区，与其他 store 并列）：`let conversationStore: ConversationStore` 和 `let conversationCoordinator: ConversationCoordinator`。
- bootstrap 里（`makeAppSupportDir()` 拿到 appSupport 后）：
```swift
let conversationStore = makeConversationStore(appSupport: appSupport)
let conversationCoordinator = ConversationCoordinator(store: conversationStore)
```
- 在容器 init 把这两个赋给字段；并把 `conversationCoordinator` 暴露给 `AppDelegate`（如其它依赖一样通过 `container.conversationCoordinator` 访问）。

- [ ] **Step 4：`AppDelegate+Execution.swift` 接入续聊**

按现有 `AppDelegate+Execution.swift` 的**真实方法签名**做以下定点修改（不是新写一套）：

```swift
// (a) private struct ExecutionStreamContext 增三个字段
let recordsHistory: Bool        // 新增：仅 window 会话进 History（Finding 1 walk-back）
let isFollowUp: Bool            // 新增
let followUpUserText: String?   // 新增（续聊本轮用户输入，落盘用；首轮 nil）

// (b) execute(tool:payload:triggerSource:) 内 setActiveInvocation 之后：
//     仅 window 会话设 active* + 起会话 + 进 History。面板的续聊入口 + regenerate 门控统一在 (c)
//     openResultPanel 按"打开进面板的模式"设定——**不**在此对非 window 执行改写共享面板的
//     续聊入口 / regenerate 门控状态：bubble/replace/file/silent 不开 ResultPanel，若用户钉住了某个
//     window 会话，在此清这些状态会让被钉会话错误重现「重新生成」/丢失续聊栏（round-9 finding）。
//     round-3 关心的 structured 复用面板残留续聊入口，已由 (c) 的 else 分支在 open 时清除。
//     （注：面板的 transient 内容——error/tool-call 行/streamingState——仍由 (f) 的 consumer.handle
//       写入，那是与 displayMode 无关的既有路径，不在本切片范围；见 Step 4 末尾"已知限制"。）
let isWindow = tool.displayMode == .window
if isWindow {
    activeTool = tool; activePayload = payload; activeTriggerSource = triggerSource
    currentAssistantText = ""
    // provider/model 不在发起时锁定——首轮 .finished(report) 才有 resolved 值（见 (f) + Step 0）。
    container.conversationCoordinator.startConversation(
        invocationId: invocationId, toolId: tool.id, toolName: tool.name,
        firstUserText: payload.text, now: Date()
    )
}
// 随后照原样 openResultPanel(...) + startExecutionStream(..., recordsHistory: isWindow, isFollowUp: false, followUpUserText: nil)

// (c) openResultPanel(...) 内 container.resultPanel.open(...) 之后：按**当前** tool 模式设定会话状态。
//     ┌ 会话生命周期模型 = **瞬态**（用户拍板，round-14）：会话 = 面板当前占用者的多轮状态。
//     │ open() 必调 `viewModel.reset()`（ResultPanel.swift:99），reset 已把 canFollowUp/contextNotice 清掉、
//     │ allowsRegenerate 复位 true（Task 7）——即每次开窗/接管面板都先清掉上一占用者的会话 UI。
//     │ 故这里**无需任何"保护被钉会话"的 gate/param**：被其他执行 / 失败接管面板时，旧会话的面板内 UI
//     │ 本就该结束（会话仍保存在 History）。只按**当前** tool 模式重设即可。
//     └ 这是 round-9/10/13/14 同一根因（共享面板被复用 reset）的 walk-back：停止逐路径加 guard，
//       改用"reset 清空 + 按当前占用者重设"的无状态模型。
//   - showExecutionFailure 对非 window 失败也会调 openResultPanel：那里 tool 是失败的非 window 工具，
//     走下面 else → setFollowUpHandler(nil)（与 reset 一致）+ setAllowsRegenerate(true)（失败面板可重试/重生成）。**正确**。
//   - open(...) 的 onDismiss 闭包末尾追加 self?.container?.conversationCoordinator.endConversation()（无条件；
//     失败面板 dismiss 顺带清掉可能残留的会话 session，无害）。
if tool.displayMode == .window {
    container.resultPanel.setFollowUpHandler { [weak self] text in self?.continueConversation(text) }
} else {
    container.resultPanel.setFollowUpHandler(nil)   // 一次性结果（structured / 非 window 失败面板）：无续聊入口
}
// regenerate 仅非 window（一次性结果）允许；window 会话不提供（避免重跑首轮/覆盖会话/污染 History）。
// 用独立 allowsRegenerate（不复用 canFollowUp，round-9）；reset 默认 true，window 开窗在此设 false。
container.resultPanel.setAllowsRegenerate(tool.displayMode != .window)

// 注：`showExecutionFailure(_:context:)` 与 `openResultPanel` 的形参均**无需**改动——瞬态模型下，
//     失败面板经 open()→reset() 自然清掉上一会话 UI，再按非 window 模式重设（无续聊 + 可重试），均正确。

// (d) 续聊入口：复用活动 window tool/payload，锁定 provider，追加用户块，再交给 runFollowUpStream 跑流。
@MainActor private func continueConversation(_ userText: String) {
    guard let container, let tool = activeTool, let payload = activePayload,
          tool.displayMode == .window,                        // 防御：续聊只对 window（Finding 1）
          let fu = container.conversationCoordinator.makeFollowUp(userText: userText) else { return }
    let notice = fu.truncated ? "会话轮数较长，较早内容已不在上下文，可能影响回答质量" : nil
    container.resultPanel.continueConversation(userText: userText, contextNotice: notice)  // 仅首次提交追加一次用户块
    // 会话内锁定：用首轮 resolved provider/model 覆写 ProviderSelection（lockedProviderId 为 nil 时回退原 tool）。
    let lockedTool = Self.lockingProvider(
        in: tool,
        providerId: container.conversationCoordinator.lockedProviderId,
        model: container.conversationCoordinator.lockedModel
    )
    runFollowUpStream(tool: lockedTool, payload: payload, followUp: fu.context, userText: userText)
}

// (d-runner) 跑一轮 follow-up 执行流——首次提交与「失败后 Retry」共用。**不**在此追加用户块、**不**再调
//   makeFollowUp（session 未变、用户块已在面板上）；每次造新 invocationId、复用同一 FollowUpContext + 锁定 tool。
//   retry 闭包递归指向自身：续聊失败点 Retry 仍是「重试这条 follow-up」，而非退回首轮 execute（Finding 3 根因）。
@MainActor private func runFollowUpStream(tool: SliceCore.Tool, payload: SelectionPayload,
                                          followUp: FollowUpContext, userText: String,
                                          isRetry: Bool = false) {
    guard let container else { return }
    streamTask?.cancel()
    // 失败重试：先把面板回滚到本轮 assistant 输出前（保留用户块、清错误态、状态回 .thinking），
    // 否则新答案会拼到失败轮的 partial 文本之后、面板卡在 .error（Finding：retry UI 状态恢复）。
    if isRetry { container.resultPanel.retryFollowUpTurn() }
    let seed = payload.toExecutionSeed(triggerSource: activeTriggerSource).withFollowUp(followUp)  // Step 5 helper
    container.invocationGate.setActiveInvocation(seed.invocationId)
    currentAssistantText = ""
    startExecutionStream(tool: tool, payload: payload, triggerSource: activeTriggerSource,
                         seed: seed, invocationId: seed.invocationId,
                         recordsHistory: true, isFollowUp: true, followUpUserText: userText,
                         retry: { [weak self] in
                             self?.runFollowUpStream(tool: tool, payload: payload,
                                                     followUp: followUp, userText: userText, isRetry: true)
                         })
}

// (d-helper) 把 tool 的 ProviderSelection 覆写为会话锁定的 .fixed(providerId, model)。
// providerId 为 nil（首轮 resolved 异常的极端情况）则原样返回，不强制锁定。
// 依赖：Tool.kind 为 var，PromptTool/AgentTool 的 provider 为 var（见 SliceCore/Tool.swift、ToolKind.swift）。
private static func lockingProvider(in tool: SliceCore.Tool, providerId: String?, model: String?) -> SliceCore.Tool {
    guard let providerId else { return tool }
    var t = tool
    let locked = ProviderSelection.fixed(providerId: providerId, modelId: model)
    switch t.kind {
    case .prompt(var p): p.provider = locked; t.kind = .prompt(p)
    case .agent(var a): a.provider = locked; t.kind = .agent(a)
    case .pipeline: break   // pipeline 未实现且不进 window 续聊，不覆写
    }
    return t
}

// (e) startExecutionStream(...) 形参表加
//     `recordsHistory: Bool = false, isFollowUp: Bool = false, followUpUserText: String? = nil,
//      retry: (@MainActor () -> Void)? = nil`：
//     - 前三个放进它构造的 ExecutionStreamContext（沿用 (a)）。
//     - 现有 consumer 的 onRetry（固定 `self?.execute(tool:payload:triggerSource:)`）改为
//       `retry ?? { [weak self] in self?.execute(tool: tool, payload: payload, triggerSource: triggerSource) }`。
//       首轮调用不传 retry → 保持原「重试 = 重开首轮 execute」语义不变；续聊由 runFollowUpStream 传入 retry，
//       失败重试复用同一 FollowUpContext + 锁定 tool，不退回首轮、不覆盖 session、不污染 History（Finding 3 根因修复）。

// (f) consumeExecutionStream(_:consumer:context:) 的事件循环内——在现有
//     `guard ... shouldAccept(invocationId: context.invocationId) ...` 与 `guard let panel ...` 之后：
if context.recordsHistory, case .llmChunk(let delta) = event { currentAssistantText += delta }
consumer.handle(event, panel: panel)                                     // 现有调用
if context.recordsHistory, case .finished(let report) = event {
    await container?.conversationCoordinator.finishTurn(
        userText: context.followUpUserText, assistantText: currentAssistantText,
        isFollowUp: context.isFollowUp,
        providerId: report.resolvedProviderId, model: report.resolvedModel, now: Date()
    )
}

// 注：provider/model 不再从静态 tool.kind 捕获（旧 conversationProviderMetadata 已移除）——
//     改由 (f) 在首轮 .finished(report) 时用运行时 resolved 值锁定（见 Step 0）。
```

辅助改动：
- `ExecutionSeed.withFollowUp(_:)`：见 Step 5（SliceCore 加便捷副本构造，保留 selection/app/anchor/triggerSource，换新 invocationId + 注入 followUp）。
- **在 `SliceAIApp/AppDelegate.swift` 主类内**（靠近既有 `var streamTask: Task<Void, Never>?`，约第 54 行）新增实例存储属性。**关键：Swift 不允许在 extension 里加存储属性；且 `private` 是文件级、会挡住另一文件的 `AppDelegate+Execution.swift` extension 访问**——故必须声明在主类、用 `internal`（无修饰符，沿用 `streamTask` 既有模式），不可写进 extension、不可用 `private`：`var activeTool: SliceCore.Tool?`、`var activePayload: SelectionPayload?`、`var activeTriggerSource: TriggerSource = .floatingToolbar`、`var currentAssistantText = ""`。这些字段由 `AppDelegate+Execution.swift` extension 读写（与 `streamTask` 同模式）。
- 续聊**复用原 `triggerSource`，不新增 `.followUp` TriggerSource case**（避免改动多处 exhaustive switch；区分续聊来源的遥测留 v1.0 之后）。
- **mode-aware retry**（Finding 3 根因修复）：现有 `startExecutionStream` 写死的 `onRetry = execute(tool:payload:triggerSource:)` 是首轮语义；续聊直接复用会让"续聊失败→Retry"退回首轮、用原 selection 重开会话并覆盖 session。修法：`startExecutionStream` 加可选 `retry` 形参，首轮不传（保持原语义），续聊由 `runFollowUpStream` 传入"重跑同一 follow-up（同 FollowUpContext + 锁定 tool、新 invocationId、不重复追加用户块）"的闭包。`runFollowUpStream` 同时是续聊首次提交与失败重试的唯一执行入口；其 `isRetry` 分支在重启流前先 `resultPanel.retryFollowUpTurn()` 把面板回滚到本轮 assistant 输出前（保留用户块、清错误态、状态回 `.thinking`），镜像首轮 retry 走 `reset()` 的语义——否则 `append` 不会从 `.error` 恢复，新答案会拼到失败轮 partial 之后、transcript 与落盘 History 不一致。
- **窗口模式禁用 header『重新生成』**（Task 8 Step 3，用户确认）：header 的 `onRegenerate` 在 `openResultPanel.open(onRegenerate:)` 绑死首轮 `execute`，是与 retry 同根的第 3 个 re-trigger 入口；续聊中/后点它会重跑首轮、覆盖 session、污染 History。正确的"多轮重新生成"需会话回滚（避免重复记录已落盘轮），对精简 v1.0 偏重——故 v1.0 在窗口模式隐藏该按钮（用**独立** `allowsRegenerate` 门控，由 `openResultPanel` 按模式设 `tool.displayMode != .window`；**不复用** `canFollowUp`，否则被钉 window 会话遇后续非 window 工具会错误重现 regenerate，见 round-9），续聊轮的"重做"由失败态 mode-aware Retry 承担，正确的多轮重新生成推后到 1.0 之后。**瞬态会话模型**（round-14）：会话状态（续聊入口/regenerate 门控）由 `ResultPanel.open()→reset()` 在每次开窗/接管面板时清回默认，再由 `openResultPanel` 按**当前** tool 模式重设；非 window **成功**不开面板故不影响被钉会话，会接管面板的执行（structured/失败面板）会按瞬态语义结束旧会话面板 UI（详见 Step 4 末尾"会话生命周期模型 + 已知限制"）。
- 持久化**仅 window 会话进 History**（Finding 1 walk-back）：非 window（structured / bubble / replace / file / silent）一次性执行不记历史、不可续聊，并在执行时 `setFollowUpHandler(nil)` 清掉复用面板上残留的续聊入口。理由：单 coordinator session + 单复用面板，与"落盘所有模式"会互相串话（session 被后一次执行覆盖、旧输入框对新工具提交触发副作用）；窗内化后状态模型最简最安全。`structured` 虽开面板但属一次性结构化结果，v1.0 不记历史 / 不续聊（如需，后续单独 spec）。续聊输入入口仍由 `canFollowUp` 门控（仅 window 绑定）。
- `finishTurn` 落盘是 `await`，在现有 `startExecutionStream` 的 `Task { @MainActor ... }` 内已是 async 上下文，无需额外改造。
- `firstUserText` 用 `payload.text`（`SelectionPayload` 无 `.selection` 字段）。
- **会话内 provider/model 锁定**（spec §7）：首轮 `.finished(report)` 把 `report.resolvedProviderId/resolvedModel` 经 `finishTurn` 传给 `ConversationSession`（lock-once）；续聊时 `lockingProvider(in:providerId:model:)` 用锁定值把 tool 的 `ProviderSelection` 覆写为 `.fixed(...)`，确保用户中途改配置不会把后续追问路由到别的端点。依赖 `Tool.kind` / `PromptTool.provider` / `AgentTool.provider` 均为 `var`（SliceCore 既有定义，已核对）。`lockedProviderId` 为 nil（首轮 resolve 异常）则回退原 tool，不阻断续聊。
  - 边界（可接受）：若用户在会话中途**删除**了被锁定的 provider，续聊时 `ProviderResolver` 抛 `.notFound(lockedProviderId)` → 执行链以 `.configuration(.referencedProviderMissing)` 失败 → `ResultPanel.fail(...)` 提示。这是锁定语义的**正确**结果（端点已不存在则明确报错，而非静默改用别的 provider），v1.0 不为此做额外迁移。

**会话生命周期模型 = 瞬态（用户拍板，round-14）+ 由此界定的已知限制**：

会话 = 单个共享 `ResultPanel` 当前占用者的多轮状态。`ResultPanel.open()` 每次开窗/接管面板都调 `viewModel.reset()`（清回"无会话"），随后 `openResultPanel` 按当前 tool 模式重设。由此：
- **预期行为（非限制）**：另一个工具**接管面板**（structured 初次结果、或 `showExecutionFailure` 为非 window 失败开的失败面板）时，旧会话的面板内 UI（续聊栏/regenerate）随 reset 结束——这是瞬态模型的设计，不是 bug。会话本身仍**完整保存在 History**。非 window **成功**不调 openResultPanel（`shouldOpenResultPanelInitially=false`）、不 reset 面板，故**不影响**被钉会话。这把 round-9/10/13/14 同一根因（共享面板被复用 reset）从"逐路径加 guard 保护被钉会话"walk-back 成"reset 清空 + 按当前占用者重设"的无状态模型，净减代码。
- **已知限制①（瞬态模型的代价）**：用户钉住会话 A、又触发别的工具**接管了面板**后，无法再在面板内继续 A（A 已被新占用者替换）。A 仍在 History；"从 History 重开会话继续追问"是 spec §4.1 明确推后到 1.0 之后的功能。属可接受边角。
- **已知限制②（预存在的内容层共享，超出本切片）**：`consumeExecutionStream`（`AppDelegate+Execution.swift:155-160`）对**所有** displayMode 都把事件交给同一共享 `ResultPanel` 的 `consumer.handle`（`.failed`→`panel.fail`、tool-call→`showToolCall*`、`.finished`→`panel.finish`）。故被钉会话 A 在屏时，另一非 window 工具（即便**成功**、不开面板）的 tool-call/finish 事件仍可能写到 A 的面板 **transient 内容**（streamingState / tool-call 行）。这是改动**前就存在**的 ResultPanel-as-primary 架构（早于会话特性），**非本切片引入**；彻底修需"多面板隔离 + 非 window 失败/事件独立呈现"重构（否则 gate 掉会让非 window 失败无 UI＝回归），与"续聊+History"正交，留待 1.0 之后。注意它只改写 *transient 内容*，**不**改写 `canFollowUp/allowsRegenerate/session 存活`（consumer.handle 不碰这三者），故被钉会话的可续聊性不受②影响。
- 影响有界：均为"pin 会话 + 交错其他工具"的边角；落盘 History 完整、删除权（含防复活）不受影响。

- [ ] **Step 5：`ExecutionSeed` 加 `withFollowUp`（SliceCore）**

```swift
    /// 返回替换 followUp 的副本（用于续聊：复用首轮 selection/app/anchor，仅换 followUp + 新 invocationId）。
    public func withFollowUp(_ followUp: FollowUpContext, invocationId: UUID = UUID()) -> ExecutionSeed {
        ExecutionSeed(invocationId: invocationId, selection: selection, frontApp: frontApp,
                      screenAnchor: screenAnchor, timestamp: timestamp, triggerSource: triggerSource,
                      isDryRun: isDryRun, runPolicy: runPolicy, followUp: followUp)
    }
```

补一条 SliceCoreTests：`withFollowUp` 换新 invocationId + 保留 selection、注入 followUp。

- [ ] **Step 6：`project.pbxproj` 注册 `ConversationCoordinator.swift`**（4 处，照 `AppDelegate+Factories` 的既有 4-entry 模式）

新建 UUID 对（如 `533BFAD1...` / `533BFAD2...`），分别加到：PBXBuildFile、PBXFileReference、SliceAIApp 组的 PBXGroup children、PBXSourcesBuildPhase。改完 `plutil -lint SliceAI.xcodeproj/project.pbxproj` 必须 OK。

- [ ] **Step 7：构建确认**

Run: `swift build --package-path SliceAIKit` + `plutil -lint SliceAI.xcodeproj/project.pbxproj` + `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
Expected: 全部成功。

- [ ] **Step 8：commit**

```bash
git add SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift \
        SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Terminal.swift \
        SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift \
        SliceAIKit/Sources/Orchestration/Telemetry/JSONLAuditLog.swift \
        SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift \
        SliceAIApp/ConversationCoordinator.swift SliceAIApp/AppContainer+Factories.swift \
        SliceAIApp/AppContainer.swift SliceAIApp/AppDelegate.swift SliceAIApp/AppDelegate+Execution.swift \
        SliceAIKit/Sources/SliceCore/ExecutionSeed.swift SliceAI.xcodeproj/project.pbxproj \
        SliceAIKit/Tests/SliceCoreTests/FollowUpContextTests.swift
git commit -m "feat: lock conversation provider/model and wire follow-up persistence"
```

---

# Phase 3：History 页

## Task 11：`HistoryViewModel`（SettingsUI）

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/HistoryViewModel.swift`
- Test: `SliceAIKit/Tests/SettingsUITests/HistoryViewModelTests.swift`

- [ ] **Step 1：写失败测试**（照 `MCPServersViewModelTests`：临时文件 store + 预置 + 断言内存/落盘）

```swift
import Capabilities
import Foundation
import SliceCore
@testable import SettingsUI
import XCTest

@MainActor
final class HistoryViewModelTests: XCTestCase {
    private func tempStore() throws -> ConversationStore {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("sliceai-hist-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return ConversationStore(fileURL: dir.appendingPathComponent("conversations.json"))
    }
    private func rec(_ id: String, updated: TimeInterval) -> ConversationRecord {
        ConversationRecord(id: id, toolId: "t", toolName: "T", providerId: nil, model: nil,
                           createdAt: .init(timeIntervalSince1970: 0), updatedAt: .init(timeIntervalSince1970: updated),
                           messages: [ChatMessage(role: .user, content: "q"), ChatMessage(role: .assistant, content: "a")])
    }

    func test_reload_loadsSummariesSortedDesc() async throws {
        let store = try tempStore()
        try await store.upsert(rec("old", updated: 1)); try await store.upsert(rec("new", updated: 9))
        let vm = HistoryViewModel(store: store)
        await vm.reload()
        XCTAssertEqual(vm.summaries.map(\.id), ["new", "old"])
    }

    func test_loadDetail_fetchesFullRecord() async throws {
        let store = try tempStore(); try await store.upsert(rec("c1", updated: 1))
        let vm = HistoryViewModel(store: store)
        await vm.loadDetail(id: "c1")
        XCTAssertEqual(vm.selectedRecord?.messages.count, 2)
    }

    func test_delete_removesAndReloads() async throws {
        let store = try tempStore(); try await store.upsert(rec("a", updated: 1)); try await store.upsert(rec("b", updated: 2))
        let vm = HistoryViewModel(store: store); await vm.reload()
        await vm.delete(id: "a")
        XCTAssertEqual(vm.summaries.map(\.id), ["b"])
    }

    func test_clearAll_empties() async throws {
        let store = try tempStore(); try await store.upsert(rec("a", updated: 1))
        let vm = HistoryViewModel(store: store); await vm.reload()
        await vm.clearAll()
        XCTAssertTrue(vm.summaries.isEmpty)
    }
}
```

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter SettingsUITests.HistoryViewModelTests`
Expected: 编译失败。

- [ ] **Step 3：创建 `HistoryViewModel.swift`**

```swift
import Capabilities
import Foundation
import SliceCore
import SwiftUI

/// History 页 VM：只读列出会话摘要、查看完整会话、删除/清空。
@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public private(set) var summaries: [ConversationSummary] = []
    @Published public var selectedRecord: ConversationRecord?
    @Published public var errorMessage: String?

    private let store: ConversationStore
    private let pageLimit = 200

    /// 必须注入 AppContainer 的**共享** ConversationStore 实例（不留生产默认）。
    /// 见 Finding 1 / D5 修订：App 写入与 Settings 删除必须经同一个 actor 实例串行化，
    /// 否则两个实例对同一文件 load-mutate-write 会丢更新 / 复活已删会话。
    public init(store: ConversationStore) {
        self.store = store
    }

    /// 重新加载摘要列表。
    public func reload() async {
        do { summaries = try await store.recentSummaries(limit: pageLimit); errorMessage = nil }
        catch { errorMessage = "历史读取失败" }            // 脱敏：不回显底层错误
    }

    /// 加载某条完整会话用于查看。先清空旧 record——避免异步加载完成前 / 失败时仍显示上一条会话的明文（串话）。
    public func loadDetail(id: String) async {
        selectedRecord = nil
        do { selectedRecord = try await store.record(id: id) }
        catch { errorMessage = "会话读取失败" }
    }

    /// 删除一条并刷新。
    public func delete(id: String) async {
        do { try await store.delete(id: id); await reload() }
        catch { errorMessage = "删除失败" }
    }

    /// 清空全部并刷新。
    public func clearAll() async {
        do { try await store.clear(); await reload() }
        catch { errorMessage = "清空失败" }
    }
}
```

- [ ] **Step 4：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter SettingsUITests.HistoryViewModelTests`
Expected: PASS（4 tests）。

- [ ] **Step 5：commit**

```bash
git add SliceAIKit/Sources/SettingsUI/HistoryViewModel.swift SliceAIKit/Tests/SettingsUITests/HistoryViewModelTests.swift
git commit -m "feat(settings): add HistoryViewModel"
```

---

## Task 12：`HistoryPage` 视图（列表 + 只读详情 sheet）

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/Pages/HistoryPage.swift`

> SwiftUI 渲染靠手测；本任务以 `xcodebuild` 编译为验收。照 `MCPServersPage` 结构（`SettingsPageShell` + `SectionCard` + 行组件 + `.task { reload }` + `.sheet`），去掉编辑/保存，只留查看/删除。

- [ ] **Step 1：创建 `HistoryPage.swift`**

```swift
import Capabilities
import DesignSystem
import SliceCore
import SwiftUI

/// Settings 历史页：只读列出过往会话，可查看完整多轮、删除单条或清空。
public struct HistoryPage: View {
    @StateObject private var viewModel: HistoryViewModel
    @State private var detailId: String?

    /// 注入 AppContainer 的**共享** ConversationStore（范式 B），据此构造 VM。
    public init(store: ConversationStore) {
        _viewModel = StateObject(wrappedValue: HistoryViewModel(store: store))
    }

    public var body: some View {
        SettingsPageShell(title: "历史", subtitle: "查看与删除过往的 LLM 交互（仅保存在本机）") {
            if viewModel.summaries.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .task { await viewModel.reload() }
        .sheet(item: Binding(get: { detailId.map { IdentifiedString($0) } }, set: { detailId = $0?.value })) { item in
            HistoryDetailSheet(viewModel: viewModel, id: item.value, onClose: { detailId = nil })
        }
    }

    private var emptyState: some View {
        SectionCard {
            VStack(spacing: 8) {
                Image(systemName: "clock").font(.largeTitle).foregroundStyle(.secondary)
                Text("暂无历史记录").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity).padding(.vertical, 24)
        }
    }

    private var list: some View {
        // 用 VStack 包裹：普通计算属性返回单一视图。直接并排返回 SectionCard + Button 两个 sibling
        // 需 @ViewBuilder（否则首个表达式被当未使用、只返回 Button，列表静默消失）；显式容器更稳、不依赖父布局。
        VStack(alignment: .leading, spacing: 8) {
            SectionCard("会话") {
                VStack(spacing: 0) {
                    ForEach(viewModel.summaries) { s in
                        HistoryRow(summary: s,
                                   onOpen: { detailId = s.id },
                                   onDelete: { Task { await viewModel.delete(id: s.id) } })
                    }
                }
            }
            // 清空按钮
            Button(role: .destructive) { Task { await viewModel.clearAll() } } label: { Text("清空全部历史") }
        }
    }
}

/// 列表行：标题 + 工具名/轮数/时间 + 查看/删除按钮。
private struct HistoryRow: View {
    let summary: ConversationSummary
    let onOpen: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.title).lineLimit(1)
                // spec §4.1 每条须显示「时间 · 来源工具 · 首条输入摘要 · provider/model」：
                // 首条输入摘要 = 上面的 title；这一行给出 时间 · 工具 · 轮数 · provider · model。
                // round-4 起 window 会话首轮锁定运行时 resolved provider/model，故二者通常都有值；
                // nil 兜底（首轮 resolve 异常）时该段省略，不展示空 ` · `。
                Text(summary.updatedAt.formatted(date: .abbreviated, time: .shortened)
                     + " · \(summary.toolName) · \(summary.turnCount) 轮"
                     + (summary.providerId.map { " · \($0)" } ?? "")
                     + (summary.model.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("查看", action: onOpen).buttonStyle(.plain).foregroundStyle(.tint)
            Button("删除", role: .destructive, action: onDelete).buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }
}

/// 只读详情：按顺序展示多轮消息。
private struct HistoryDetailSheet: View {
    @ObservedObject var viewModel: HistoryViewModel
    let id: String
    let onClose: () -> Void

    var body: some View {
        // 仅当已加载 record 的 id 与本 sheet 的 id 一致才渲染，否则按"加载中"处理（防串话/旧会话残留）。
        let messages = (viewModel.selectedRecord?.id == id) ? (viewModel.selectedRecord?.messages ?? []) : []
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("会话详情").font(.headline); Spacer(); Button("关闭", action: onClose) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    if messages.isEmpty {
                        Text("加载中…").foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        ForEach(Array(messages.enumerated()), id: \.offset) { _, msg in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(msg.role == .user ? "你" : "助手").font(.caption).foregroundStyle(.secondary)
                                Text(msg.content ?? "").textSelection(.enabled)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
        .padding(16).frame(minWidth: 420, minHeight: 360)
        .task { await viewModel.loadDetail(id: id) }
    }
}

/// sheet(item:) 用的可识别包装。
private struct IdentifiedString: Identifiable {
    let value: String
    var id: String { value }
    init(_ value: String) { self.value = value }
}
```

> 注：`SettingsPageShell` / `SectionCard` 的真实初始化签名以 `MCPServersPage.swift` 为准，若 `SectionCard` 只接受单 title 重载，按其签名适配。`HistoryRow`/`HistoryDetailSheet`/`IdentifiedString` 用 `private` 避免跨文件符号冲突。

- [ ] **Step 2：构建确认**

Run: `swift build --package-path SliceAIKit`
Expected: 通过（SettingsScene 尚未引用 HistoryPage，先确保自身编译）。

- [ ] **Step 3：commit**

```bash
git add SliceAIKit/Sources/SettingsUI/Pages/HistoryPage.swift
git commit -m "feat(settings): add read-only HistoryPage"
```

---

## Task 13：`SettingsScene` 注册 History tab（注入共享 store，范式 B）

**Files:**
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`（导航 5 处 + init 增 store 参数）
- Modify: `SliceAIApp/AppDelegate.swift`（`showSettings` 构造 `SettingsScene` 处，传入 `container.conversationStore`）

> Finding 1 修订：HistoryPage 不再自持默认 store，必须由 AppContainer 的**共享** `ConversationStore` 经 SettingsScene 注入，确保 App 写入与 Settings 删除走同一个 actor 实例（防丢更新）。因此 `SettingsScene.init` 与 `AppDelegate.showSettings` 调用点都要加一个参数。

- [ ] **Step 1：SettingsScene.swift 改动**

1. `enum SidebarItem`（~L129）加 `case history`。
2. `label`（~L141）加 `case .history: return "历史"`。
3. `iconName`（~L156）加 `case .history: return "clock"`。
4. `sidebarView` 某 `Section`（~L54-82）加一行 `SidebarRow(item: .history)`（建议放"更多/通用"组末尾）。
5. `SettingsScene.init`（~L28-34）形参表加 `conversationStore: ConversationStore`，存为 `private let conversationStore`（与现有 `skillRegistry` 等注入参并列；`import Capabilities` 若缺则补，按 sorted_imports 排序）。
6. `detailView` switch（~L94-120）加 `case .history: HistoryPage(store: conversationStore)`。

- [ ] **Step 2：AppDelegate.swift 调用点**

在 `showSettings`（~L410-413）构造 `SettingsScene(...)` 处追加实参 `conversationStore: container.conversationStore`（`container.conversationStore` 由 Task 10 装配）。

- [ ] **Step 3：构建确认**

Run: `swift build --package-path SliceAIKit` + `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
Expected: 全部成功。

- [ ] **Step 4：commit**

```bash
git add SliceAIKit/Sources/SettingsUI/SettingsScene.swift SliceAIApp/AppDelegate.swift
git commit -m "feat(settings): register History tab and inject shared conversation store"
```

---

# Phase 4：收口 gate + 文档

## Task 14：全量 gate + 真实 App smoke + 文档同步

- [ ] **Step 1：全量自动化 gate**

```bash
swift build --package-path SliceAIKit
swift test --package-path SliceAIKit --parallel --enable-code-coverage
swiftlint lint --strict
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
git diff --check
```
Expected: 测试全绿、lint 0 违规、build SUCCEEDED。

- [ ] **Step 2：真实 App smoke（手测，记录到 Task-detail）**

1. prompt 工具划词 → 出结果 → 底部输入框追问 → 同面板出现"你：…"+新答案（多轮 transcript）。
2. agent 工具（如 web-search-summarize / english-tutor）→ 追问时仍能 `sliceai_load_skill` / 调 MCP（看 ResultPanel tool-call 行）。
3. 连续追问 > 10 轮 → 出现"会话较长…"提示；早期轮次不再影响（仍能正常回答）。
4. 打开 Settings → 历史 → 列表含刚才会话 → 查看完整多轮 → 删除单条 / 清空生效。**防复活**：在结果面板仍开着（会话活动）时，于 Settings 删除该会话（或清空全部），回面板再追问一轮 → 被删会话**不**在 `conversations.json` / 历史列表复活。
5. 既有读取链回归：不追问时单轮行为与之前一致；pin/drag/resize 正常。**非窗口模式（bubble/structured）的「重新生成」按钮仍在且工作如常。**
6. **窗口/续聊 re-trigger 语义**：(a) window 模式 header **不再显示「重新生成」**按钮（已隐藏）；(b) 续聊轮流式中途失败 → 出 Retry → 点击只重试**当前追问轮**（同上下文、不重跑首轮、不覆盖会话），且面板不残留失败轮的 partial 文本；(c) **瞬态会话模型**（round-14，用户拍板）：钉住一个 window 会话后——
  • 触发 bubble/replace/file/silent 工具且**成功**（不开/不 reset 面板）→ 被钉会话**存活**：续聊栏仍在且可用、不出现「重新生成」。
  • 触发会**接管面板**的工具（structured 结果，或某工具**失败**经 showExecutionFailure 开失败面板）→ 被钉会话的面板内 UI（续聊栏/regenerate）**随 reset 结束**——这是瞬态模型的**预期**，不计失败；该会话仍可在 Settings→历史 看到完整多轮。
  注：已知限制②（consumer.handle 把任意执行的 tool-call/finish 事件写到共享面板 transient 内容）属预存在、本切片不修（见 Task 10 Step 4 末尾"已知限制"），不计入本项。
7. 隐私核对：`audit.jsonl` 不含会话明文；`conversations.json` 存在于 App Support 且与 config/keychain 分离；Console 无会话内容打印。

- [ ] **Step 3：文档同步**

- `README.md`：功能清单 + 变更记录加"续聊 + 历史"。
- `AGENTS.md` / `CLAUDE.md`：执行流补"续聊经 ExecutionSeed.followUp"；模块清单 SettingsUI 补 History 页、Capabilities 补 ConversationStore；测试策略补新增测试。
- `docs/v2-refactor-master-todolist.md`：§5.0 v1.0 剩余任务 V1-1~V1-3 勾选；§9 追加 snapshot。
- `docs/Task_history.md` + `docs/Task-detail/2026-05-30-v1-conversation-followup-and-history.md`：实施总结 + smoke 结果。
- `docs/Module/Orchestration.md` / `SettingsUI.md` / `SliceCore.md` / `Capabilities.md`：补对应设计。
- 确认**未改 `config.schema.json`**（本切片不动 Configuration schema v4）。

- [ ] **Step 4：commit + 收口**

```bash
git add -A
git commit -m "docs: record conversation follow-up + history implementation and smoke"
```
然后按 §执行交接：本分支 `codex/v1-scope-conversation-followup` push、开 PR 到 main、CI 绿后由用户决定 merge。

---

## Self-Review（plan 对照 spec 自检）

- **Spec 覆盖**：续聊承载面（Task 7-9）、能力继承 agent skill+MCP（Task 6）、prompt 多轮（Task 5）、10 轮窗口 + 友好提示（Task 3 + Task 7/10）、会话内锁定首轮 resolved provider/model + 列表展示（spec §7/§4.1，Task 10 Step 0 + (f)/(d) + Task 12）、History 只读列表/查看/删除（Task 11-13）、删除权含活动会话防复活（Task 4 store tombstone/clear-watermark，round-11）、明文本地 + audit 仍脱敏 + 独立存储（Task 4 + D5/D8）、ExecutionEngine 唯一入口不旁路（D1，executor 内分支）、SliceCore 零 UI（会话类型/reducer 均 Foundation-only）、不 bump schema（D4）。✅ 均有对应 task。
- **占位符扫描**：无 TBD/TODO；每个实现步骤含真实代码。少数"按现有签名适配"处（appendSkillMetadata / SectionCard / SettingsPageShell）已显式标注以现有源码签名为准——这是对既有私有 helper 的引用约束，非占位。
- **类型一致性**：`FollowUpContext`(priorMessages,userText)、`ConversationRecord`(id,toolId,toolName,providerId,model,createdAt,updatedAt,messages)、`ConversationSummary`(id,toolName,title,turnCount,updatedAt,providerId,model)、`ConversationSession`(contextWindowTurns/lockedProviderId/lockedModel/`recordAssistantTurn(…providerId:model:at:)`/recordFollowUpTurn/makeFollowUp/toRecord)、`ConversationStore`(upsert/recentSummaries/record/delete/clear)、`ConversationCoordinator`(`startConversation(…firstUserText:now:)`/`finishTurn(…isFollowUp:providerId:model:now:)`/makeFollowUp/lockedProviderId/lockedModel/endConversation)、`InvocationReport`(+resolvedProviderId/resolvedModel)、`HistoryViewModel`(summaries/selectedRecord/reload/loadDetail/delete/clearAll)、`ResultViewModel`(beginFollowUpTurn/retryFollowUpTurn/contextNotice/canFollowUp/allowsRegenerate/onSubmitFollowUp)、`ResultPanel`(continueConversation/retryFollowUpTurn/setFollowUpHandler/setAllowsRegenerate) 在各 task 间签名一致。
- **已知未定项（实施时确认，非占位）**：(a) `AgentPromptBuilder` 的 `appendContextBag`/`appendSkillMetadata` 现有签名（Task 6 已标注按现有签名适配，续聊只调 skillMetadata 不调 contextBag）。(b) 已解决（codex round 1）：assistant 全文改为 `AppDelegate` per-invocation `currentAssistantText` 累积器（Task 10），不读 panel 文本。(c) 已解决（codex round 1 + round 4）：provider/model 不再传 nil——由 `InvocationReport.resolvedProviderId/resolvedModel`（Task 10 Step 0）在首轮 `.finished` 经 `finishTurn` 锁定进 `ConversationSession`（lock-once），续聊用 `lockingProvider` 把 `ProviderSelection` 覆写为 `.fixed(锁定值)`（会话内锁定，spec §7），History 列表展示 provider·model（Task 12）；不依赖不存在的 `tool.effectiveProviderId/Model`。(d) 已解决（codex round 1）：`ConversationStore` 作为 AppContainer 共享单例经 SettingsScene 注入（Task 13），不在 HistoryViewModel 留生产默认实例。

## Execution Handoff

Plan 已保存到 `docs/superpowers/plans/2026-05-30-v1-conversation-followup-and-history.md`。两种执行方式：

1. **Subagent-Driven（推荐）** — 每个 task 派新 subagent 实现，task 间两段式 review，快速迭代。
2. **Inline Execution** — 在本会话用 executing-plans 批量执行，带 checkpoint。
