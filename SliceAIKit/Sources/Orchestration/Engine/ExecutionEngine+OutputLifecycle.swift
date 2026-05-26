import Foundation
import SliceCore

extension ExecutionEngine {

    /// 派发 prompt chunk，并维护 final text 与 notImplemented 单次提示状态。
    /// - Parameters:
    ///   - chunk: 当前 LLM 文本增量。
    ///   - outputContext: 当前输出生命周期上下文。
    ///   - context: 当前 flow context。
    ///   - finalText: 调用方累积的最终文本。
    ///   - notImplementedYielded: non-window fallback 提示是否已发送。
    /// - Returns: false 表示 consumer 已终止或调用已取消。
    func dispatchPromptChunk(
        _ chunk: String,
        outputContext: OutputInvocationContext,
        context: FlowContext,
        finalText: inout String,
        notImplementedYielded: inout Bool
    ) async throws -> Bool {
        if Task.isCancelled { return false }
        finalText += chunk
        if case .terminated = context.continuation.yield(.llmChunk(delta: chunk)) { return false }
        let dispatchOutcome = try await output.handle(chunk: chunk, context: outputContext)
        if Task.isCancelled { return false }
        if case .notImplemented(let reason) = dispatchOutcome, !notImplementedYielded {
            context.continuation.yield(.notImplemented(reason: reason))
            notImplementedYielded = true
        }
        return true
    }

    /// prompt stream 失败时同步 output lifecycle 与主流程失败收口。
    /// - Parameters:
    ///   - error: 已脱敏的 SliceError。
    ///   - outputContext: 当前输出生命周期上下文。
    ///   - context: 当前 flow context。
    func failPromptStream(
        error: SliceError,
        outputContext: OutputInvocationContext,
        context: FlowContext
    ) async {
        await output.fail(error: error, context: outputContext)
        await finishFailure(error: error, effective: context.effective, context: context)
    }

    /// 为当前 Tool 构造 output lifecycle 上下文。
    /// - Parameters:
    ///   - tool: 当前执行的 Tool。
    ///   - context: 当前 flow context。
    /// - Returns: sink 可用于路由和定位的输出上下文。
    func makeOutputContext(tool: Tool, context: FlowContext) -> OutputInvocationContext {
        OutputInvocationContext(
            invocationId: context.invocationId,
            toolId: tool.id,
            toolName: tool.name,
            mode: tool.displayMode,
            screenAnchor: context.screenAnchor,
            outputBinding: tool.outputBinding
        )
    }
}
