// SliceAIApp/ResultPanelWindowSinkAdapter.swift
import Foundation
import Orchestration
import Windowing

/// `WindowSinkProtocol` 的 SliceAIApp 层适配实现：把 `OutputDispatcher` 的 chunk
/// 路由到既有 `ResultPanel` 单实例，single-flight 状态统一委托给 `InvocationGate`。
///
/// 该类型放在 SliceAIApp composition root 层，避免让 Windowing 直接依赖 Orchestration。
@MainActor
public final class ResultPanelWindowSinkAdapter: WindowSinkProtocol {

    /// 注入的结果面板单实例。
    private let panel: ResultPanel

    /// single-flight 状态持有者，必须与 AppDelegate 执行链共用同一个实例。
    private let gate: InvocationGate

    /// 构造结果面板 sink adapter。
    ///
    /// - Parameters:
    ///   - panel: AppContainer 注入的结果面板单实例。
    ///   - gate: AppContainer 注入的 InvocationGate；用于隔离不同 invocation 的 stream chunk。
    public init(panel: ResultPanel, gate: InvocationGate) {
        self.panel = panel
        self.gate = gate
    }

    /// 把 chunk 委托给 `InvocationGate` 判断后追加到结果面板。
    ///
    /// adapter 自身不做 `shouldAccept` 分支判断，避免复制 single-flight 逻辑；过期 chunk
    /// 是否丢弃完全由 `InvocationGate.gatedAppend(chunk:invocationId:sink:)` 决定。
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段。
    ///   - invocationId: chunk 所属 invocation ID。
    public func append(chunk: String, invocationId: UUID) async throws {
        gate.gatedAppend(chunk: chunk, invocationId: invocationId) { [weak panel] c in
            // 不打印 chunk 内容，避免在调试日志中泄露用户选中文本或模型输出。
            panel?.append(c)
        }
    }
}
