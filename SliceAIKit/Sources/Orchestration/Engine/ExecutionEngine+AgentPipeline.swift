import Foundation
import SliceCore

extension ExecutionEngine {

    /// Step 6/7：跑 AgentExecutor stream，转发工具生命周期事件，并把 `.llmChunk` 走同一 OutputDispatcher。
    ///
    /// AgentExecutor 不直接接触 ResultPanel；所有 chunk 仍经由 ExecutionEngine → OutputDispatcher
    /// 的单写入路径，避免 prompt/agent 两套 UI 写入契约分叉。
    func runAgentStream(
        tool: Tool,
        agent: AgentTool,
        resolved: ResolvedExecutionContext,
        provider: Provider,
        context: FlowContext
    ) async -> UsageStats? {
        guard let agentExecutor else { return nil }
        let stream = await agentExecutor.run(
            tool: tool, agent: agent, resolved: resolved, provider: provider
        )
        return await consumeAgentStream(stream, tool: tool, context: context)
    }

    /// 消费 AgentExecutor 事件流并估算输出 token。
    /// - Parameters:
    ///   - stream: AgentExecutor 事件流。
    ///   - tool: 当前 Tool。
    ///   - context: 当前 flow context。
    /// - Returns: usage 估算；nil 表示已取消或已失败收口。
    private func consumeAgentStream(
        _ stream: AsyncThrowingStream<ExecutionEvent, any Error>,
        tool: Tool,
        context: FlowContext
    ) async -> UsageStats? {
        var outputCharacters = 0
        do {
            for try await event in stream {
                if Task.isCancelled { return nil }
                guard await forwardAgentEvent(event, tool: tool, context: context, outputCharacters: &outputCharacters)
                else { return nil }
            }
        } catch is CancellationError {
            return nil
        } catch {
            await finishFailure(
                error: .execution(.unknown("AgentExecutor stream failed")),
                effective: context.effective,
                context: context
            )
            return nil
        }
        return UsageStats(inputTokens: 0, outputTokens: max(0, outputCharacters / 4))
    }

    /// 转发一个 AgentExecutor 事件。
    private func forwardAgentEvent(
        _ event: ExecutionEvent,
        tool: Tool,
        context: FlowContext,
        outputCharacters: inout Int
    ) async -> Bool {
        switch event {
        case .llmChunk(let chunk):
            guard await forwardLLMChunk(chunk, tool: tool, context: context) else { return false }
            outputCharacters += chunk.count
            return true
        case .failed(let error):
            await finishFailure(error: error, effective: context.effective, context: context)
            return false
        default:
            if case .terminated = context.continuation.yield(event) { return false }
            return true
        }
    }

    /// 转发一个 LLM chunk 到外层事件流和 OutputDispatcher。
    /// - Parameters:
    ///   - chunk: LLM 文本增量。
    ///   - tool: 当前执行的 Tool。
    ///   - context: 当前 flow context。
    /// - Returns: false 表示 consumer 已终止或输出派发失败已收口。
    private func forwardLLMChunk(
        _ chunk: String,
        tool: Tool,
        context: FlowContext
    ) async -> Bool {
        if case .terminated = context.continuation.yield(.llmChunk(delta: chunk)) { return false }
        do {
            _ = try await output.handle(
                chunk: chunk,
                mode: tool.displayMode,
                invocationId: context.invocationId
            )
            return !Task.isCancelled
        } catch {
            await finishFailure(
                error: .execution(.unknown("OutputDispatcher failed")),
                effective: context.effective,
                context: context
            )
            return false
        }
    }
}
