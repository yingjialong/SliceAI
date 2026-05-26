import Foundation
import SliceCore
@testable import Orchestration

/// 测试用 output lifecycle 事件类型。
enum MockOutputLifecycleKind: Sendable, Equatable {
    case begin
    case chunk
    case finish
    case fail
}

/// 测试用 output lifecycle 调用记录。
struct MockOutputLifecycleCall: Sendable, Equatable {
    let kind: MockOutputLifecycleKind
    let chunk: String?
    let finalText: String?
    let context: OutputInvocationContext
}

/// In-memory `OutputDispatcherProtocol` mock for unit tests.
///
/// 设计要点：
/// - **actor**：与生产 `OutputDispatcher` 同款隔离，`ExecutionEngine` 注入
///   `any OutputDispatcherProtocol` 的代码路径在测试 / 生产保持一致；
/// - **默认 `.delivered`**：测试方便；可通过 `outcomeOverride` 闭包按 `DisplayMode`
///   注入特定 outcome（如想验证 ExecutionEngine 在 `.notImplemented` 路径上的行为）；
/// - **完整调用栈**：保存每次 `(chunk, mode, invocationId)` 三元组，断言时可读出顺序与计数；
/// - **`@Sendable` 闭包**：`outcomeOverride` 跨 actor 边界存储，需要 Sendable 标注，
///   否则 Swift 6 严格并发会报"non-sendable closure stored in actor field"
final actor MockOutputDispatcher: OutputDispatcherProtocol {

    /// `handle(...)` 累计被调次数；与 `calls.count` 始终保持一致
    private(set) var handleCallCount: Int = 0

    /// 每次调用的 `(chunk, mode, invocationId)` 三元组，顺序保留
    private(set) var calls: [(chunk: String, mode: DisplayMode, invocationId: UUID)] = []

    /// lifecycle API 调用记录，供新 DisplayMode / final text 测试断言。
    private(set) var lifecycleCalls: [MockOutputLifecycleCall] = []

    /// 注入特定模式应返回的 `DispatchOutcome`；nil 时默认 `.delivered`
    /// `@Sendable` 是 actor field 存储跨边界闭包的硬性要求
    private var outcomeOverride: (@Sendable (DisplayMode) -> DispatchOutcome)?

    /// 构造 mock；可选注入 `outcomeOverride` 控制返回值
    init(outcomeOverride: (@Sendable (DisplayMode) -> DispatchOutcome)? = nil) {
        self.outcomeOverride = outcomeOverride
    }

    /// 记录调用，按 `outcomeOverride`（若有）或默认 `.delivered` 返回
    func handle(
        chunk: String,
        mode: DisplayMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome {
        handleCallCount += 1
        calls.append((chunk: chunk, mode: mode, invocationId: invocationId))
        if let override = outcomeOverride {
            return override(mode)
        }
        return .delivered
    }

    /// 记录 lifecycle begin。
    func begin(context: OutputInvocationContext) async throws {
        lifecycleCalls.append(MockOutputLifecycleCall(
            kind: .begin,
            chunk: nil,
            finalText: nil,
            context: context
        ))
    }

    /// 记录 lifecycle chunk，并复用旧 handle 记录。
    func handle(
        chunk: String,
        context: OutputInvocationContext
    ) async throws -> DispatchOutcome {
        lifecycleCalls.append(MockOutputLifecycleCall(
            kind: .chunk,
            chunk: chunk,
            finalText: nil,
            context: context
        ))
        return try await handle(
            chunk: chunk,
            mode: context.mode,
            invocationId: context.invocationId
        )
    }

    /// 记录 lifecycle finish。
    func finish(finalText: String, context: OutputInvocationContext) async throws {
        lifecycleCalls.append(MockOutputLifecycleCall(
            kind: .finish,
            chunk: nil,
            finalText: finalText,
            context: context
        ))
    }

    /// 记录 lifecycle fail。
    func fail(error: SliceError, context: OutputInvocationContext) async {
        lifecycleCalls.append(MockOutputLifecycleCall(
            kind: .fail,
            chunk: nil,
            finalText: nil,
            context: context
        ))
    }

    /// 测试用：在 mock 构造之后再注入 / 替换 `outcomeOverride`
    func setOutcomeOverride(_ override: @escaping @Sendable (DisplayMode) -> DispatchOutcome) {
        self.outcomeOverride = override
    }

    /// 测试用：清空累计调用记录
    func reset() {
        handleCallCount = 0
        calls.removeAll()
        lifecycleCalls.removeAll()
    }
}
