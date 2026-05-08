import Foundation
import os
import SliceCore

/// 测试用 tool-calling LLMProvider：按 turn 回放 `ChatStreamEvent`，并捕获每次 `ChatToolRequest`。
///
/// 设计语义：
/// - 每次 `streamToolChat(request:)` 消耗一个 scripted turn；
/// - `capturedToolRequests` 保留完整请求序列，便于断言 tools schema、消息顺序和 tool result 回填；
/// - prompt-only `stream(request:)` 明确抛错，防止 AgentExecutor 误走 Task 10 已禁止的旧 API。
final class MockToolCallingLLMProvider: LLMProvider, @unchecked Sendable {

    /// 受锁保护的内部状态。
    private struct State {
        var capturedToolRequests: [ChatToolRequest] = []
        var toolStreamCallCount = 0
    }

    /// 每轮 LLM 流式事件脚本。
    private let turns: [[ChatStreamEvent]]
    /// 指定轮次在 stream 创建前同步抛错。
    private let throwBeforeTurn: Int?
    /// 同步抛错内容。
    private let throwBeforeError: (any Error)?
    /// async-safe 锁，保护捕获状态。
    private let state = OSAllocatedUnfairLock<State>(initialState: .init())

    /// 测试可读：所有 tool chat 请求快照。
    var capturedToolRequests: [ChatToolRequest] {
        state.withLock { $0.capturedToolRequests }
    }

    /// 测试可读：`streamToolChat` 被调用次数。
    var toolStreamCallCount: Int {
        state.withLock { $0.toolStreamCallCount }
    }

    /// 构造 tool-calling LLM mock。
    /// - Parameters:
    ///   - turns: 每次 tool-chat stream 要回放的事件序列。
    ///   - throwBeforeTurn: 从 0 开始的轮次；命中时在返回 stream 前抛错。
    ///   - throwBeforeError: 命中 `throwBeforeTurn` 时抛出的错误。
    init(
        turns: [[ChatStreamEvent]],
        throwBeforeTurn: Int? = nil,
        throwBeforeError: (any Error)? = nil
    ) {
        self.turns = turns
        self.throwBeforeTurn = throwBeforeTurn
        self.throwBeforeError = throwBeforeError
    }

    /// prompt-only API 在 AgentExecutor 中不应被调用。
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        throw SliceError.provider(.invalidResponse("prompt-only stream must not be used by AgentExecutor"))
    }

    /// 回放下一轮 tool-chat 事件，并记录请求。
    func streamToolChat(
        request: ChatToolRequest
    ) async throws -> AsyncThrowingStream<ChatStreamEvent, any Error> {
        let callIndex = state.withLock { state -> Int in
            let index = state.toolStreamCallCount
            state.toolStreamCallCount += 1
            state.capturedToolRequests.append(request)
            return index
        }

        if throwBeforeTurn == callIndex, let throwBeforeError {
            throw throwBeforeError
        }

        let events = callIndex < turns.count ? turns[callIndex] : [.finished(.stop)]
        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }
}
