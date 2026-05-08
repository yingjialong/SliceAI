import Capabilities
import Foundation
import SliceCore

typealias AgentEventContinuation = AsyncThrowingStream<ExecutionEvent, any Error>.Continuation

/// 单个 tool call 处理过程中的共享上下文。
struct AgentToolCallContext: Sendable {
    let uiId: UUID
    let call: ChatToolCall
    let continuation: AgentEventContinuation
}

extension AgentExecutor {

    /// 执行当前 assistant turn 的所有 tool calls。
    func processToolCalls(
        _ calls: [ChatToolCall],
        catalog: AgentToolCatalog,
        tool: Tool,
        continuation: AgentEventContinuation
    ) async -> [ChatMessage] {
        var messages: [ChatMessage] = []
        for call in calls {
            let message = await processOneToolCall(
                call,
                catalog: catalog,
                tool: tool,
                continuation: continuation
            )
            messages.append(message)
        }
        return messages
    }

    /// 执行一个 tool call，并生成回填给模型的 tool message。
    func processOneToolCall(
        _ call: ChatToolCall,
        catalog: AgentToolCatalog,
        tool: Tool,
        continuation: AgentEventContinuation
    ) async -> ChatMessage {
        let context = AgentToolCallContext(uiId: UUID(), call: call, continuation: continuation)
        let ref = catalog.ref(forToolName: call.name)
        continuation.yield(.toolCallProposed(
            id: context.uiId,
            ref: ref,
            argsDescription: describeArguments(call)
        ))
        guard catalog.isAllowed(ref) else { return denyToolCall(context) }
        guard let args = call.arguments else {
            return failToolCall(context, summary: "invalid tool arguments", content: "invalid tool arguments")
        }
        return await callAllowedTool(context, ref: ref, args: args, tool: tool)
    }

    /// allowlist 拒绝分支。
    func denyToolCall(_ context: AgentToolCallContext) -> ChatMessage {
        context.continuation.yield(.toolCallDenied(
            id: context.uiId,
            reason: "Tool not allowed: <redacted>"
        ))
        return ChatMessage(
            role: .tool,
            content: "Tool not allowed in this Agent allowlist",
            toolCallID: context.call.id,
            toolCalls: nil
        )
    }

    /// 已允许 tool 的权限 gate + MCP call 分支。
    func callAllowedTool(
        _ context: AgentToolCallContext,
        ref: MCPToolRef,
        args: MCPJSONValue.Object,
        tool: Tool
    ) async -> ChatMessage {
        let gate = await gateMCP(ref: ref, tool: tool)
        switch gate {
        case .approved:
            context.continuation.yield(.toolCallApproved(id: context.uiId))
            return await executeMCP(context, ref: ref, args: args)
        case .denied(_, let reason):
            let redacted = Redaction.scrub(reason)
            context.continuation.yield(.toolCallDenied(id: context.uiId, reason: redacted))
            return toolMessage(call: context.call, content: "Permission denied: \(redacted)")
        case .requiresUserConsent, .wouldRequireConsent:
            let summary = "permission broker returned unresolved consent"
            return failToolCall(context, summary: summary, content: summary)
        }
    }

    /// 对一个 MCP permission 做 one-time gate。
    func gateMCP(ref: MCPToolRef, tool: Tool) async -> GateOutcome {
        await permissionBroker.gate(
            effective: [.mcp(server: ref.server, tools: [ref.tool])],
            provenance: tool.provenance,
            scope: .oneTime,
            isDryRun: false
        )
    }

    /// 执行 MCP call 并映射成功/错误事件。
    func executeMCP(
        _ context: AgentToolCallContext,
        ref: MCPToolRef,
        args: MCPJSONValue.Object
    ) async -> ChatMessage {
        do {
            let result = try await callMCPWithTimeout(ref: ref, args: args)
            return handleMCPResult(result, context: context)
        } catch is AgentToolCallTimeout {
            return failToolCall(
                context,
                summary: "MCP tool call timed out",
                content: "MCP tool call timed out"
            )
        } catch {
            let summary = summarize(error: error)
            return failToolCall(context, summary: summary, content: summary)
        }
    }

    /// 映射 MCP result 到事件和 tool message。
    func handleMCPResult(
        _ result: MCPCallResult,
        context: AgentToolCallContext
    ) -> ChatMessage {
        let summary = summarize(result: result)
        if result.isError {
            return failToolCall(
                context,
                summary: summary,
                content: "Tool execution error: \(summary)"
            )
        }
        context.continuation.yield(.toolCallResult(id: context.uiId, summary: summary))
        return toolMessage(call: context.call, content: summary)
    }

    /// 统一 tool-call 错误事件与 tool message。
    func failToolCall(
        _ context: AgentToolCallContext,
        summary: String,
        content: String
    ) -> ChatMessage {
        context.continuation.yield(.toolCallError(id: context.uiId, summary: Redaction.scrub(summary)))
        return toolMessage(call: context.call, content: Redaction.scrub(content))
    }

    /// 构造 role=.tool 消息。
    func toolMessage(call: ChatToolCall, content: String) -> ChatMessage {
        ChatMessage(role: .tool, content: content, toolCallID: call.id, toolCalls: nil)
    }

    /// 带超时执行 MCP call。
    func callMCPWithTimeout(
        ref: MCPToolRef,
        args: MCPJSONValue.Object
    ) async throws -> MCPCallResult {
        let client = mcpClient
        let timeout = toolCallTimeoutNanoseconds
        return try await withThrowingTaskGroup(of: MCPCallResult.self) { group in
            group.addTask { try await client.call(ref: ref, args: args) }
            group.addTask {
                try await Task.sleep(nanoseconds: timeout)
                throw AgentToolCallTimeout()
            }
            guard let result = try await group.next() else {
                throw AgentToolCallTimeout()
            }
            group.cancelAll()
            return result
        }
    }

    /// 生成 tool call 参数摘要。
    func describeArguments(_ call: ChatToolCall) -> String {
        if let args = call.arguments {
            return MCPJSONValue.object(args).redactedSummary(maxCharacters: Redaction.maxLength)
        }
        return Redaction.scrub(call.argumentsRaw)
    }
}

/// Tool call timeout 哨兵错误。
struct AgentToolCallTimeout: Error, Sendable {}

extension AgentExecutor {

    /// 将 MCP result 转成脱敏摘要。
    func summarize(result: MCPCallResult) -> String {
        if let structured = result.structuredContent {
            return Redaction.scrub(structured.redactedSummary(maxCharacters: Redaction.maxLength))
        }
        let text = result.content.map(summarize(content:)).joined(separator: "\n")
        return text.isEmpty ? "Tool completed" : Redaction.scrub(text)
    }

    /// 将 MCP content item 转成短摘要。
    func summarize(content: MCPContentItem) -> String {
        switch content {
        case .text(let text):
            return text
        case .image(_, let mimeType):
            return "<image \(mimeType)>"
        case .resourceLink(let uri, let name, let mimeType):
            return "<resource \(name ?? uri) \(mimeType ?? "")>"
        case .embeddedResource(let uri, let text, let blob, let mimeType):
            return text ?? "<resource \(uri) \(mimeType ?? "") \(blob == nil ? "" : "blob")>"
        }
    }

    /// 将错误转成脱敏摘要。
    func summarize(error: any Error) -> String {
        if let sliceError = error as? SliceError {
            return sliceError.developerContext
        }
        if let mcpError = error as? MCPClientError {
            return mcpError.developerContext
        }
        return "tool call failed"
    }
}
