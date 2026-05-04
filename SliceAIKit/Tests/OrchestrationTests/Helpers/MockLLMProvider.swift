import Foundation
import os
import SliceCore

/// 测试用 LLMProvider：按 init 传入的 ChatChunk 数组依次 yield，可选末尾抛错
///
/// 同时记录 `stream(request:)` 收到的 ChatRequest，供测试断言 prompt 渲染 / model /
/// temperature / maxTokens 等字段是否被正确透传。
///
/// **并发实现**：用 `final class` + `OSAllocatedUnfairLock<State>` 串行化捕获字段
/// 的读写。Swift 6 `StrictConcurrency=complete` 不允许 `NSLock.lock/unlock` 在 async 上下文
/// 调用；`OSAllocatedUnfairLock` 的 `withLock { ... }` 是 async-safe 的官方推荐方案
/// （Apple Foundation Locking docs / WWDC22 213）。
final class MockLLMProvider: LLMProvider, @unchecked Sendable {

    /// 受锁保护的内部捕获状态
    private struct State {
        var capturedRequest: ChatRequest?
    }

    /// 待 yield 的 chunks（顺序透传）
    private let chunks: [ChatChunk]
    /// 流末尾要抛出的错误；nil 表示正常 finish
    private let trailingError: (any Error)?
    /// 流是否在第一个 yield 之前同步抛错（模拟 LLMProvider.stream 抛错路径）
    private let throwBeforeStream: (any Error)?
    /// async-safe 锁，包裹捕获状态；测试在 await 完成后通过 `capturedRequest` 读取
    private let state = OSAllocatedUnfairLock<State>(initialState: .init())

    /// 测试可读：最后一次 stream 收到的 ChatRequest（首次调用前为 nil）
    var capturedRequest: ChatRequest? {
        state.withLock { $0.capturedRequest }
    }

    /// 构造 MockLLMProvider
    /// - Parameters:
    ///   - chunks: 流式 yield 的 ChatChunk 序列（按顺序）
    ///   - trailingError: 所有 chunk yield 完后抛出的错误，nil 则正常 finish
    ///   - throwBeforeStream: 在 stream 创建前同步抛出的错误（绕过 yield 路径）
    init(
        chunks: [ChatChunk] = [],
        trailingError: (any Error)? = nil,
        throwBeforeStream: (any Error)? = nil
    ) {
        self.chunks = chunks
        self.trailingError = trailingError
        self.throwBeforeStream = throwBeforeStream
    }

    /// LLMProvider 协议方法
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        // 记录请求供测试断言；withLock 闭包同步、async-safe
        state.withLock { $0.capturedRequest = request }

        // 同步抛错路径（模拟工厂创建后立即失败）
        if let err = throwBeforeStream { throw err }

        // 复制到本地 let，避免 closure 跨 Sendable 边界捕获 self 可变状态
        let chunksLocal = chunks
        let errorLocal = trailingError
        return AsyncThrowingStream { continuation in
            Task {
                for chunk in chunksLocal {
                    continuation.yield(chunk)
                }
                if let err = errorLocal {
                    continuation.finish(throwing: err)
                } else {
                    continuation.finish()
                }
            }
        }
    }
}

/// 测试用 LLMProviderFactory：返回固定 MockLLMProvider 实例 + 捕获 (provider, apiKey)
///
/// `LLMProviderFactory.make` 是同步 throws 方法，不能用 actor 实现（actor 强制 async）；
/// 用 `final class` + `OSAllocatedUnfairLock<State>` 同步串行化捕获状态。
final class MockLLMProviderFactory: LLMProviderFactory, @unchecked Sendable {

    /// 受锁保护的内部捕获状态
    private struct State {
        var capturedProvider: Provider?
        var capturedAPIKey: String?
    }

    /// 工厂返回的固定 LLMProvider 实例
    private let provider: any LLMProvider
    /// `make` 抛错配置（非 nil 时立即抛，绕过 provider 返回）
    private let makeError: (any Error)?
    /// 锁保护捕获状态
    private let state = OSAllocatedUnfairLock<State>(initialState: .init())

    /// 测试可读：最后一次 make 收到的 Provider
    var capturedProvider: Provider? {
        state.withLock { $0.capturedProvider }
    }

    /// 测试可读：最后一次 make 收到的 apiKey
    var capturedAPIKey: String? {
        state.withLock { $0.capturedAPIKey }
    }

    /// 构造 MockLLMProviderFactory
    /// - Parameters:
    ///   - provider: make 返回的 LLMProvider 实例
    ///   - makeError: 非 nil 时直接 throw，模拟工厂创建失败
    init(provider: any LLMProvider, makeError: (any Error)? = nil) {
        self.provider = provider
        self.makeError = makeError
    }

    /// LLMProviderFactory 协议方法
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        state.withLock { state in
            state.capturedProvider = provider
            state.capturedAPIKey = apiKey
        }

        if let err = makeError { throw err }
        return self.provider
    }
}
