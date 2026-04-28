import Foundation
import SliceCore

/// In-memory `WindowSinkProtocol` 实现。
///
/// **用途**：
/// - **M2 测试期**：`OutputDispatcher` 注入此实现，单测可读取 `receivedChunks(for:)` 验证投递
/// - **生产路径**：M3 由 `ResultPanel` adapter 替换；本 actor 不参与生产链路
///
/// **行为约束**：
/// - 按 `invocationId` 分组保留所有 chunk，**顺序严格保留**（FIFO；用 Array 而非 Set）
/// - 不做任何脱敏 / 过滤 / 合并：调用方收到的就是原文
/// - actor 隔离避免并发写交错；多个 invocation 并发投递互不干扰
public actor InMemoryWindowSink: WindowSinkProtocol {

    /// invocationId → 该 invocation 收到的 chunk 序列（顺序保留）
    private var chunksByInvocation: [UUID: [String]] = [:]

    /// 构造空 sink；测试 / 调试期间常配合 `reset()` 在 setUp / tearDown 复用
    public init() {}

    /// 追加 chunk 到指定 invocation 的序列尾部。
    ///
    /// 注意：本实现不抛错；签名 throws 仅为满足 `WindowSinkProtocol` 协议（生产 sink 可能 IO 失败）
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段
    ///   - invocationId: 与 `OutputDispatcher.handle(...)` 透传一致的 invocation ID
    public func append(chunk: String, invocationId: UUID) async throws {
        chunksByInvocation[invocationId, default: []].append(chunk)
    }

    /// 读取某 invocation 收到的全部 chunks（顺序保留）。
    ///
    /// - Parameter invocationId: 目标 invocation ID
    /// - Returns: 该 invocation 收到的 chunk 数组；从未投递过则返回 `[]`
    public func receivedChunks(for invocationId: UUID) -> [String] {
        chunksByInvocation[invocationId] ?? []
    }

    /// 测试用：清空所有 invocation 的 chunk 数据。
    public func reset() {
        chunksByInvocation.removeAll()
    }
}
