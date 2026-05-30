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
- `SliceAIApp/AppDelegate+Execution.swift` — 续聊回调接入 coordinator。
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
            frontApp: AppSnapshot(name: "Safari", bundleIdentifier: nil, url: nil, windowTitle: nil),
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

    /// summary 取首条 user 文本作为标题、统计轮数
    func test_summary_derivesTitleAndTurnCount() {
        let r = record(id: "c1", turns: 3)
        let s = r.summary
        XCTAssertEqual(s.id, "c1")
        XCTAssertEqual(s.toolName, "翻译")
        XCTAssertEqual(s.turnCount, 3)
        XCTAssertEqual(s.title, "q0")
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
        let title = (firstUser?.isEmpty == false) ? firstUser! : "(空会话)"
        // 一轮 = 一对 user+assistant；按 assistant 条数计更稳（避免末轮无答时多计）
        let turns = messages.filter { $0.role == .assistant }.count
        return ConversationSummary(id: id, toolName: toolName, title: String(title.prefix(80)),
                                   turnCount: turns, updatedAt: updatedAt, model: model)
    }
}

/// History 列表行用的轻量摘要。
public struct ConversationSummary: Sendable, Equatable, Identifiable {
    public let id: String
    public let toolName: String
    public let title: String
    public let turnCount: Int
    public let updatedAt: Date
    public let model: String?

    public init(id: String, toolName: String, title: String, turnCount: Int, updatedAt: Date, model: String?) {
        self.id = id
        self.toolName = toolName
        self.title = title
        self.turnCount = turnCount
        self.updatedAt = updatedAt
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
            id: "c1", toolId: "translate", toolName: "翻译", providerId: "p1", model: "m1",
            firstUserText: "hello", createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// 首轮 finish 后：messages = [user(原文), assistant(答案)]，record 可生成
    func test_recordFirstTurn_buildsUserAssistantPair() {
        var s = makeSession()
        s.recordAssistantTurn(assistantText: "你好", at: Date(timeIntervalSince1970: 1))
        XCTAssertEqual(s.messages.map(\.role), [.user, .assistant])
        XCTAssertEqual(s.messages[0].content, "hello")
        XCTAssertEqual(s.messages[1].content, "你好")
        XCTAssertEqual(s.toRecord().messages.count, 2)
    }

    /// 续聊：makeFollowUp 返回 priorMessages(=当前累积) + userText，未超窗口不裁剪
    func test_makeFollowUp_carriesPriorMessages_noTruncationUnderWindow() {
        var s = makeSession()
        s.recordAssistantTurn(assistantText: "你好", at: Date(timeIntervalSince1970: 1))
        let fu = s.makeFollowUp(userText: "再说一次")
        XCTAssertEqual(fu.context.priorMessages.map(\.role), [.user, .assistant])
        XCTAssertEqual(fu.context.userText, "再说一次")
        XCTAssertFalse(fu.truncated)
    }

    /// 续聊推进：先 makeFollowUp 再 recordFollowUpTurn，messages 增长为 4 条
    func test_recordFollowUpTurn_appendsUserThenAssistant() {
        var s = makeSession()
        s.recordAssistantTurn(assistantText: "你好", at: Date(timeIntervalSince1970: 1))
        _ = s.makeFollowUp(userText: "再说一次")
        s.recordFollowUpTurn(userText: "再说一次", assistantText: "你好你好", at: Date(timeIntervalSince1970: 2))
        XCTAssertEqual(s.messages.map(\.role), [.user, .assistant, .user, .assistant])
        XCTAssertEqual(s.messages.last?.content, "你好你好")
    }

    /// 超过 10 轮：priorMessages 只保留最近 10 对，truncated == true
    func test_makeFollowUp_truncatesToWindow_andFlagsTruncated() {
        var s = makeSession()
        s.recordAssistantTurn(assistantText: "a0", at: Date(timeIntervalSince1970: 1))
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
    public let providerId: String?
    public let model: String?
    public let createdAt: Date
    /// 用户可见消息（user/assistant 交替）。首轮以 firstUserText 作为第一条 user。
    public private(set) var messages: [ChatMessage]
    public private(set) var updatedAt: Date

    public init(id: String, toolId: String, toolName: String, providerId: String?, model: String?,
                firstUserText: String, createdAt: Date) {
        self.id = id
        self.toolId = toolId
        self.toolName = toolName
        self.providerId = providerId
        self.model = model
        self.createdAt = createdAt
        self.updatedAt = createdAt
        self.messages = [ChatMessage(role: .user, content: firstUserText)]
    }

    /// 首轮答案到达后记录 assistant 消息。
    public mutating func recordAssistantTurn(assistantText: String, at now: Date) {
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

    /// 生成落盘 record（保留完整历史，不受窗口影响）。
    public func toRecord() -> ConversationRecord {
        ConversationRecord(id: id, toolId: toolId, toolName: toolName, providerId: providerId, model: model,
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
import XCTest
@testable import Capabilities
import SliceCore

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
    public func upsert(_ record: ConversationRecord) throws {
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

    /// 删除一条。
    public func delete(id: String) throws {
        try update { $0.removeAll { $0.id == id } }
    }

    /// 清空全部。
    public func clear() throws {
        try write(.empty)
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
Expected: PASS（6 tests）。

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

    _ = try await collectPromptElements(executor.run(promptTool: promptTool, resolved: resolved, provider: provider))

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

    _ = try await collectEvents(executor.run(tool: makeTool(agent), agent: agent, resolved: resolved, provider: makeProvider()))

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

- [ ] **Step 3：改 `AgentPromptBuilder.buildInitialMessages` 加分支**

```swift
static func buildInitialMessages(agent: AgentTool, resolved: ResolvedExecutionContext, boundSkills: [BoundSkill]) -> [ChatMessage] {
    var messages: [ChatMessage] = []
    if let sys = agent.systemPrompt, !sys.isEmpty {
        messages.append(ChatMessage(role: .system, content: sys))
    }
    if let followUp = resolved.seed.followUp {
        // 续聊：接历史；本轮 user = 追问原文 + 重挂 skill metadata（context bag 不重复注入）
        messages.append(contentsOf: followUp.priorMessages)
        var userText = followUp.userText
        appendSkillMetadata(&userText, boundSkills: boundSkills)   // 复用既有私有 helper
        messages.append(ChatMessage(role: .user, content: userText))
        return messages
    }
    // 首轮：原逻辑（initialUserPrompt + context bag + skill metadata）
    var userText = agent.initialUserPrompt
    appendContextBag(&userText, resolved: resolved)
    appendSkillMetadata(&userText, boundSkills: boundSkills)
    messages.append(ChatMessage(role: .user, content: userText))
    return messages
}
```

> 注：`appendContextBag` / `appendSkillMetadata` 是该文件现有私有 helper；若签名不同（如返回 String 而非 inout），按现有签名适配，保持"续聊不调 appendContextBag、仍调 appendSkillMetadata"的语义。`BoundSkill` 类型名以现有 `catalog.boundSkills` 元素类型为准。

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
        vm.reset(toolName: "x", model: nil)
        XCTAssertNil(vm.contextNotice)                   // reset 清除
    }
}
```

- [ ] **Step 2：跑测试确认失败**

Run: `swift test --package-path SliceAIKit --filter WindowingTests.ResultViewModelFollowUpTests`
Expected: 编译失败（`beginFollowUpTurn` / `contextNotice` 未定义）。

- [ ] **Step 3：改 `ResultViewModel.swift`**

加 `@Published`：

```swift
    /// 上下文窗口裁剪等非阻塞提示；nil 表示无提示。reset 时清除。
    @Published public var contextNotice: String?
    /// 用户提交追问的回调（App 层接管：带 history 再 execute）。
    public var onSubmitFollowUp: (@MainActor (String) -> Void)?
```

在 `reset(toolName:model:)` body 内补 `contextNotice = nil`。

加方法（不清 `text`）：

```swift
    /// 开始一轮续聊：保留已有 transcript，追加分隔与用户追问块，状态回到等待答案。
    public func beginFollowUpTurn(_ userText: String) {
        text += "\n\n---\n\n**你：** \(userText)\n\n"
        toolCalls = []                 // 新一轮 tool-call 行从空开始
        structuredFields = nil
        streamingState = .thinking
    }
```

- [ ] **Step 4：跑测试确认通过**

Run: `swift test --package-path SliceAIKit --filter WindowingTests.ResultViewModelFollowUpTests`
Expected: PASS（2 tests）。

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

在 `VStack` 底部、`contentArea` 之后插入（仅 finished 态显示，避免流式中输入）：

```swift
            if viewModel.streamingState == .finished {
                Divider()
                FollowUpInputBar(viewModel: viewModel)
            }
```

- [ ] **Step 3：构建确认**

Run: `swift build --package-path SliceAIKit` 然后 `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
Expected: BUILD SUCCEEDED。（NSPanel/SwiftUI 渲染靠手测，见最终 smoke。）

- [ ] **Step 4：commit**

```bash
git add SliceAIKit/Sources/Windowing/ResultContentView.swift
git commit -m "feat(windowing): add follow-up input bar to result panel"
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

    /// 设置/更新续聊提交回调（App 层在 open 后绑定）。
    public func setFollowUpHandler(_ handler: (@MainActor (String) -> Void)?) {
        viewModel.onSubmitFollowUp = handler
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

## Task 10：App 层 `ConversationCoordinator` + 装配 + 落盘 + pbxproj

**Files:**
- Create: `SliceAIApp/ConversationCoordinator.swift`
- Modify: `SliceAIApp/AppContainer+Factories.swift`、`SliceAIApp/AppContainer.swift`、`SliceAIApp/AppDelegate+Execution.swift`、`SliceAI.xcodeproj/project.pbxproj`

> App target 无单测；本任务靠 `xcodebuild` 编译 + 最终真实 App smoke 验收。纯逻辑（窗口/累积）已在 Task 3 单测覆盖。

- [ ] **Step 1：创建 `ConversationCoordinator.swift`**

```swift
import Foundation
import SliceCore
import Capabilities

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
    func startConversation(invocationId: UUID, toolId: String, toolName: String,
                           providerId: String?, model: String?, firstUserText: String, now: Date) {
        session = ConversationSession(id: invocationId.uuidString, toolId: toolId, toolName: toolName,
                                      providerId: providerId, model: model, firstUserText: firstUserText, createdAt: now)
    }

    /// 一轮（首轮或续聊）答案完成：记录 assistant，落盘。
    /// - Parameter isFollowUp: true 表示这轮是续聊（需先记 user 再记 assistant）。
    func finishTurn(userText: String?, assistantText: String, isFollowUp: Bool, now: Date) async {
        guard var s = session else { return }
        if isFollowUp, let userText { s.recordFollowUpTurn(userText: userText, assistantText: assistantText, at: now) }
        else { s.recordAssistantTurn(assistantText: assistantText, at: now) }
        session = s
        do { try await store.upsert(s.toRecord()) }
        catch { /* 落盘失败不阻断 UI；隐私护栏：不打印内容 */ }
    }

    /// 生成续聊 follow-up（供构造新 seed）。
    func makeFollowUp(userText: String) -> (context: FollowUpContext, truncated: Bool)? {
        session?.makeFollowUp(userText: userText)
    }

    /// 结束当前会话（面板 dismiss 时调用）。
    func endConversation() { session = nil }
}
```

- [ ] **Step 2：`AppContainer+Factories.swift` 加工厂**

参照第 41 行 MCPServerStore，在 store 工厂区加：

```swift
    /// 会话历史存储（落盘到 App Support/conversations.json）。
    func makeConversationStore(appSupport: URL) -> ConversationStore {
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

在 `openResultPanel(...)` 绑定回调处，新增 follow-up handler；并在首轮 execute 启动会话、每轮 finish 落盘。要点（按现有 `execute` / `consumeExecutionStream` 结构落位）：

```swift
// 1) execute() 首轮：openResultPanel 后启动会话
container.conversationCoordinator.startConversation(
    invocationId: seed.invocationId, toolId: tool.id, toolName: tool.name,
    providerId: tool.effectiveProviderId, model: tool.effectiveModel,
    firstUserText: payload.selection.text, now: Date()
)
container.resultPanel.setFollowUpHandler { [weak self] text in
    self?.continueConversation(text)
}

// 2) 新增 continueConversation(_:)：用 followUp 造新 seed，复用面板（不 open），再走执行流
@MainActor func continueConversation(_ userText: String) {
    guard let fu = container.conversationCoordinator.makeFollowUp(userText: userText),
          let payload = lastPayload, let tool = lastTool else { return }
    streamTask?.cancel()
    let notice = fu.truncated ? "会话轮数较长，较早内容已不在上下文，可能影响回答质量" : nil
    container.resultPanel.continueConversation(userText: userText, contextNotice: notice)
    var seed = payload.toExecutionSeed(triggerSource: .followUp)
    seed = seed.withFollowUp(fu.context)                 // 见下方 helper
    container.invocationGate.setActiveInvocation(seed.invocationId)
    pendingFollowUpText = userText                        // finish 时落盘用
    startExecutionStream(tool: tool, seed: seed, isFollowUp: true)
}

// 3) consumeExecutionStream / 事件 .finished 收尾：落盘本轮
//    在收到 .finished 时（拿 viewModel.text 末段或维护的 per-turn 答案）调用：
await container.conversationCoordinator.finishTurn(
    userText: isFollowUp ? pendingFollowUpText : nil,
    assistantText: capturedAssistantText, isFollowUp: isFollowUp, now: Date()
)
```

辅助改动：
- 给 `ExecutionSeed` 加便捷 `func withFollowUp(_ ctx: FollowUpContext) -> ExecutionSeed`（在 SliceCore，返回替换 followUp 的副本），或直接在 `toExecutionSeed` 加可选 `followUp` 参。**选其一**：推荐在 SliceCore `ExecutionSeed` 加 `withFollowUp`，避免改 payload API。
- `AppDelegate` 增 `lastPayload` / `lastTool` / `pendingFollowUpText` 私有状态（若已有 last* 缓存复用）。
- `.followUp` 是新的 `TriggerSource` case，需在 `SliceCore/TriggerSource.swift` 加（同步任何 exhaustive switch）。
- 取"本轮 assistant 全文"：prompt 轮可用 `consumeExecutionStream` 累积的 `.llmChunk`（参照现有 finalText 累积），或读 `container.resultPanel` 当前轮文本；保持与现有 finalText 来源一致。
- panel `onDismiss` 回调里追加 `container.conversationCoordinator.endConversation()`。

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
git add SliceAIApp/ConversationCoordinator.swift SliceAIApp/AppContainer+Factories.swift SliceAIApp/AppContainer.swift SliceAIApp/AppDelegate+Execution.swift SliceAIKit/Sources/SliceCore/ExecutionSeed.swift SliceAIKit/Sources/SliceCore/TriggerSource.swift SliceAI.xcodeproj/project.pbxproj SliceAIKit/Tests/SliceCoreTests/FollowUpContextTests.swift
git commit -m "feat(app): wire conversation follow-up loop and persistence"
```

---

# Phase 3：History 页

## Task 11：`HistoryViewModel`（SettingsUI）

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/HistoryViewModel.swift`
- Test: `SliceAIKit/Tests/SettingsUITests/HistoryViewModelTests.swift`

- [ ] **Step 1：写失败测试**（照 `MCPServersViewModelTests`：临时文件 store + 预置 + 断言内存/落盘）

```swift
import XCTest
@testable import SettingsUI
import SliceCore
import Capabilities

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
import Foundation
import SliceCore
import Capabilities

/// History 页 VM：只读列出会话摘要、查看完整会话、删除/清空。
@MainActor
public final class HistoryViewModel: ObservableObject {
    @Published public private(set) var summaries: [ConversationSummary] = []
    @Published public var selectedRecord: ConversationRecord?
    @Published public var errorMessage: String?

    private let store: ConversationStore
    private let pageLimit = 200

    public init(store: ConversationStore = ConversationStore()) {
        self.store = store
    }

    /// 重新加载摘要列表。
    public func reload() async {
        do { summaries = try await store.recentSummaries(limit: pageLimit); errorMessage = nil }
        catch { errorMessage = "历史读取失败" }            // 脱敏：不回显底层错误
    }

    /// 加载某条完整会话用于查看。
    public func loadDetail(id: String) async {
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
import SwiftUI
import SliceCore
import DesignSystem

/// Settings 历史页：只读列出过往会话，可查看完整多轮、删除单条或清空。
public struct HistoryPage: View {
    @StateObject private var viewModel = HistoryViewModel()
    @State private var detailId: String?

    public init() {}

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
            .padding(.top, 8)
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
                Text("\(summary.toolName) · \(summary.turnCount) 轮").font(.caption).foregroundStyle(.secondary)
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
        VStack(alignment: .leading, spacing: 12) {
            HStack { Text("会话详情").font(.headline); Spacer(); Button("关闭", action: onClose) }
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array((viewModel.selectedRecord?.messages ?? []).enumerated()), id: \.offset) { _, msg in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(msg.role == .user ? "你" : "助手").font(.caption).foregroundStyle(.secondary)
                            Text(msg.content ?? "").textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .padding(16).frame(minWidth: 420, minHeight: 360)
        .task { await viewModel.loadDetail(id: id) }
    }
}

/// sheet(item:) 用的可识别包装。
private struct IdentifiedString: Identifiable { let value: String; var id: String { value }; init(_ v: String) { value = v } }
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

## Task 13：`SettingsScene` 注册 History tab

**Files:**
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`（5 处，均在同一文件）

- [ ] **Step 1：5 处改动**

1. `enum SidebarItem`（~L129）加 `case history`。
2. `label`（~L141）加 `case .history: return "历史"`。
3. `iconName`（~L156）加 `case .history: return "clock"`。
4. `sidebarView` 某 `Section`（~L54-82）加一行 `SidebarRow(item: .history)`（建议放"更多/通用"组末尾）。
5. `detailView` switch（~L94-120）加 `case .history: HistoryPage()`。

- [ ] **Step 2：构建确认**

Run: `swift build --package-path SliceAIKit` + `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
Expected: 全部成功。`SettingsScene.init` / `AppDelegate.showSettings` 不需新增参数（HistoryPage 自持默认 store）。

- [ ] **Step 3：commit**

```bash
git add SliceAIKit/Sources/SettingsUI/SettingsScene.swift
git commit -m "feat(settings): register History tab in settings navigation"
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
4. 打开 Settings → 历史 → 列表含刚才会话 → 查看完整多轮 → 删除单条 / 清空生效。
5. 既有读取链回归：不追问时单轮行为与之前一致；pin/drag/resize/regenerate 正常。
6. 隐私核对：`audit.jsonl` 不含会话明文；`conversations.json` 存在于 App Support 且与 config/keychain 分离；Console 无会话内容打印。

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

- **Spec 覆盖**：续聊承载面（Task 7-9）、能力继承 agent skill+MCP（Task 6）、prompt 多轮（Task 5）、10 轮窗口 + 友好提示（Task 3 + Task 7/10）、History 只读列表/查看/删除（Task 11-13）、明文本地 + audit 仍脱敏 + 独立存储（Task 4 + D5/D8）、ExecutionEngine 唯一入口不旁路（D1，executor 内分支）、SliceCore 零 UI（会话类型/reducer 均 Foundation-only）、不 bump schema（D4）。✅ 均有对应 task。
- **占位符扫描**：无 TBD/TODO；每个实现步骤含真实代码。少数"按现有签名适配"处（appendSkillMetadata / SectionCard / SettingsPageShell）已显式标注以现有源码签名为准——这是对既有私有 helper 的引用约束，非占位。
- **类型一致性**：`FollowUpContext`(priorMessages,userText)、`ConversationRecord`(id,toolId,toolName,providerId,model,createdAt,updatedAt,messages)、`ConversationSession`(contextWindowTurns/recordAssistantTurn/recordFollowUpTurn/makeFollowUp/toRecord)、`ConversationStore`(upsert/recentSummaries/record/delete/clear)、`HistoryViewModel`(summaries/selectedRecord/reload/loadDetail/delete/clearAll)、`ResultViewModel`(beginFollowUpTurn/contextNotice/onSubmitFollowUp) 在各 task 间签名一致。
- **已知未定项（实施时确认，非占位）**：(a) `appendContextBag`/`appendSkillMetadata` 现有签名；(b) "本轮 assistant 全文"在 App 层的现成来源（沿用现有 finalText 累积）；(c) `tool.effectiveProviderId/effectiveModel` 实际取值入口名。三者均为对现有代码的对接点，已在对应 step 注明。

## Execution Handoff

Plan 已保存到 `docs/superpowers/plans/2026-05-30-v1-conversation-followup-and-history.md`。两种执行方式：

1. **Subagent-Driven（推荐）** — 每个 task 派新 subagent 实现，task 间两段式 review，快速迭代。
2. **Inline Execution** — 在本会话用 executing-plans 批量执行，带 checkpoint。
