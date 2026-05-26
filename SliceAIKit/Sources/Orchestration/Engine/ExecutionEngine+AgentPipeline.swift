import Foundation
import SliceCore

/// Agent 输出累积状态，避免事件转发 helper 参数膨胀。
private struct AgentOutputAccumulator {
    var finalText = ""
    var outputCharacters = 0
}

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
        let outputContext = makeOutputContext(tool: tool, context: context)
        let stream = await agentExecutor.run(
            tool: tool, agent: agent, resolved: resolved, provider: provider
        )
        do {
            try await output.begin(context: outputContext)
        } catch {
            await finishFailure(
                error: .execution(.unknown("OutputDispatcher failed")),
                effective: context.effective,
                context: context
            )
            return nil
        }
        return await consumeAgentStream(
            stream,
            tool: tool,
            context: context,
            outputContext: outputContext
        )
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
        context: FlowContext,
        outputContext: OutputInvocationContext
    ) async -> UsageStats? {
        var accumulator = AgentOutputAccumulator()
        do {
            for try await event in stream {
                if Task.isCancelled { return nil }
                guard await forwardAgentEvent(
                    event,
                    tool: tool,
                    context: context,
                    outputContext: outputContext,
                    accumulator: &accumulator
                )
                else { return nil }
            }
            context.finalText = accumulator.finalText
            try await output.finish(finalText: accumulator.finalText, context: outputContext)
        } catch is CancellationError {
            return nil
        } catch {
            await output.fail(
                error: .execution(.unknown("AgentExecutor stream failed")),
                context: outputContext
            )
            await finishFailure(
                error: .execution(.unknown("AgentExecutor stream failed")),
                effective: context.effective,
                context: context
            )
            return nil
        }
        return UsageStats(inputTokens: 0, outputTokens: max(0, accumulator.outputCharacters / 4))
    }

    /// 转发一个 AgentExecutor 事件。
    private func forwardAgentEvent(
        _ event: ExecutionEvent,
        tool: Tool,
        context: FlowContext,
        outputContext: OutputInvocationContext,
        accumulator: inout AgentOutputAccumulator
    ) async -> Bool {
        switch event {
        case .llmChunk(let chunk):
            guard await forwardLLMChunk(
                chunk,
                tool: tool,
                context: context,
                outputContext: outputContext
            ) else { return false }
            accumulator.finalText += chunk
            accumulator.outputCharacters += chunk.count
            return true
        case .failed(let error):
            await output.fail(error: error, context: outputContext)
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
        context: FlowContext,
        outputContext: OutputInvocationContext
    ) async -> Bool {
        if case .terminated = context.continuation.yield(.llmChunk(delta: chunk)) { return false }
        do {
            _ = try await output.handle(
                chunk: chunk,
                context: outputContext
            )
            return !Task.isCancelled
        } catch {
            await output.fail(
                error: .execution(.unknown("OutputDispatcher failed")),
                context: outputContext
            )
            await finishFailure(
                error: .execution(.unknown("OutputDispatcher failed")),
                effective: context.effective,
                context: context
            )
            return false
        }
    }
}
