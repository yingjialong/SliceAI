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

/// 一轮 tool call 处理结果。
struct AgentToolCallProcessingResult: Sendable {
    let messages: [ChatMessage]
}

/// 单轮 assistant tool-call 处理需要的稳定上下文。
struct AgentToolTurnProcessingContext: Sendable {
    let catalog: AgentToolCatalog
    let tool: Tool
    let continuation: AgentEventContinuation
}

/// 单次 Agent 运行内的 MCP 调用状态。
struct AgentToolCallRunState: Sendable {
    var policy: AgentToolCallPolicy
    private(set) var totalExecuted = 0
    private(set) var currentTurnExecuted = 0
    private var perToolExecuted: [MCPToolRef: Int] = [:]
    private var seenFingerprints: Set<String> = []
    private(set) var rateLimitActive = false

    /// 构造单次 Agent 运行的 MCP 调用状态。
    /// - Parameter policy: 已合并默认值后的工具调用策略。
    init(policy: AgentToolCallPolicy) {
        self.policy = policy
    }

    /// 开始处理一个 assistant tool-call turn。
    mutating func beginTurn() {
        currentTurnExecuted = 0
    }

    /// 判断当前 tool call 是否应跳过。
    /// - Parameters:
    ///   - ref: MCP tool 引用。
    ///   - args: MCP tool 参数。
    /// - Returns: 跳过原因；nil 表示允许执行。
    func skipReason(ref: MCPToolRef, args: MCPJSONValue.Object) -> AgentToolCallSkipReason? {
        if policy.stopOnRateLimit && rateLimitActive {
            return .rateLimitActive
        }
        if let maxTotalCalls = policy.maxTotalCalls,
           totalExecuted >= max(0, maxTotalCalls) {
            return .totalLimit
        }
        if let maxCallsPerTurn = policy.maxCallsPerTurn,
           currentTurnExecuted >= max(0, maxCallsPerTurn) {
            return .turnLimit
        }
        if let limit = policy.limit(for: ref),
           (perToolExecuted[ref] ?? 0) >= max(0, limit) {
            return .perToolLimit
        }
        if policy.duplicateArgumentStrategy == .skipExactArguments,
           seenFingerprints.contains(Self.fingerprint(ref: ref, args: args)) {
            return .duplicate
        }
        return nil
    }

    /// 记录一次真实执行的 MCP 调用。
    /// - Parameters:
    ///   - ref: MCP tool 引用。
    ///   - args: MCP tool 参数。
    mutating func recordExecution(ref: MCPToolRef, args: MCPJSONValue.Object) {
        totalExecuted += 1
        currentTurnExecuted += 1
        perToolExecuted[ref, default: 0] += 1
        seenFingerprints.insert(Self.fingerprint(ref: ref, args: args))
    }

    /// 记录 MCP 返回内容，用于识别 rate limit。
    /// - Parameter content: 已脱敏的 tool message 内容。
    mutating func recordToolMessageContent(_ content: String?) {
        guard policy.stopOnRateLimit, let content else { return }
        if Self.containsRateLimitSignal(content) {
            rateLimitActive = true
        }
    }

    /// 是否应该停止后续 LLM tool turn，转入最终答案请求。
    var shouldStopRequestingTools: Bool {
        if policy.stopOnRateLimit && rateLimitActive {
            return true
        }
        if let maxTotalCalls = policy.maxTotalCalls {
            return totalExecuted >= max(0, maxTotalCalls)
        }
        return false
    }

    /// 构造去重指纹。
    /// - Parameters:
    ///   - ref: MCP tool 引用。
    ///   - args: MCP tool 参数。
    /// - Returns: 稳定的去重 key。
    private static func fingerprint(ref: MCPToolRef, args: MCPJSONValue.Object) -> String {
        "\(ref.server).\(ref.tool):\(MCPJSONValue.object(args).redactedSummary(maxCharacters: Int.max))"
    }

    /// 判断文本是否包含常见限流信号。
    /// - Parameter content: MCP 结果或错误摘要。
    /// - Returns: 命中 rate limit / 429 信号时返回 true。
    private static func containsRateLimitSignal(_ content: String) -> Bool {
        let normalized = content.lowercased()
        return normalized.contains("rate limit")
            || normalized.contains("rate-limit")
            || normalized.contains("rate_limited")
            || normalized.contains("429")
    }
}

/// MCP 调用跳过原因。
enum AgentToolCallSkipReason: Sendable {
    case totalLimit
    case turnLimit
    case perToolLimit
    case duplicate
    case rateLimitActive

    /// UI 事件摘要。
    var summary: String {
        switch self {
        case .totalLimit, .turnLimit, .perToolLimit:
            return "tool call budget exhausted"
        case .duplicate:
            return "duplicate tool call skipped"
        case .rateLimitActive:
            return "rate limit active; tool call skipped"
        }
    }

    /// 回填给 provider 的 tool message 内容。
    var content: String {
        switch self {
        case .totalLimit:
            return "Tool call skipped: per-run tool call limit reached"
        case .turnLimit:
            return "Tool call skipped: per-turn tool call limit reached"
        case .perToolLimit:
            return "Tool call skipped: per-tool tool call limit reached"
        case .duplicate:
            return "Tool call skipped: duplicate exact arguments"
        case .rateLimitActive:
            return "Tool call skipped: previous MCP call hit a rate limit"
        }
    }
}

private extension AgentToolCallPolicy {
    /// 查询指定 MCP tool 的配置上限。
    /// - Parameter ref: MCP tool 引用。
    /// - Returns: 上限；不存在时返回 nil。
    func limit(for ref: MCPToolRef) -> Int? {
        perToolLimits.first { $0.ref == ref }?.maxCalls
    }
}

extension AgentExecutor {

    /// 生成执行器实际使用的工具调用策略。
    ///
    /// 用户未显式配置时，默认值按 Agent 可见 MCP 工具数量推导：每轮最多每个 allowlist tool
    /// 各调用一次，总量为 `maxSteps * allowlist.count`。这不是某个 MCP 的硬编码限制，
    /// 只是避免模型在同一回合无限并发调用外部服务。
    func effectiveToolCallPolicy(
        agent: AgentTool,
        catalog: AgentToolCatalog,
        maxSteps: Int
    ) -> AgentToolCallPolicy {
        var policy = agent.toolCallPolicy ?? AgentToolCallPolicy()
        let visibleToolCount = max(1, catalog.allowlist.count)
        if policy.maxTotalCalls == nil {
            policy.maxTotalCalls = max(1, maxSteps) * visibleToolCount
        }
        if policy.maxCallsPerTurn == nil {
            policy.maxCallsPerTurn = visibleToolCount
        }
        return policy
    }

    /// 记录 assistant tool-call turn 并执行当前预算允许的工具调用。
    func appendToolTurnResult(
        _ turn: AgentTurn,
        messages: inout [ChatMessage],
        context: AgentToolTurnProcessingContext,
        toolCallState: inout AgentToolCallRunState
    ) async -> Bool {
        messages.append(ChatMessage(
            role: .assistant,
            content: turn.assistantText,
            toolCallID: nil,
            toolCalls: turn.toolCalls,
            reasoningContent: turn.reasoningContent.isEmpty ? nil : turn.reasoningContent
        ))
        let processingResult = await processToolCalls(
            turn.toolCalls,
            catalog: context.catalog,
            tool: context.tool,
            toolCallState: &toolCallState,
            continuation: context.continuation
        )
        messages.append(contentsOf: processingResult.messages)
        return toolCallState.shouldStopRequestingTools
    }

    /// 执行当前 assistant turn 的所有 tool calls。
    func processToolCalls(
        _ calls: [ChatToolCall],
        catalog: AgentToolCatalog,
        tool: Tool,
        toolCallState: inout AgentToolCallRunState,
        continuation: AgentEventContinuation
    ) async -> AgentToolCallProcessingResult {
        var messages: [ChatMessage] = []
        toolCallState.beginTurn()
        for call in calls {
            let message = await processOneToolCall(
                call,
                catalog: catalog,
                tool: tool,
                toolCallState: &toolCallState,
                continuation: continuation
            )
            messages.append(message)
        }
        return AgentToolCallProcessingResult(messages: messages)
    }

    /// 执行一个 tool call，并生成回填给模型的 tool message。
    func processOneToolCall(
        _ call: ChatToolCall,
        catalog: AgentToolCatalog,
        tool: Tool,
        toolCallState: inout AgentToolCallRunState,
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
        if let reason = toolCallState.skipReason(ref: ref, args: args) {
            logger.debug("agent tool call skipped reason=\(reason.summary, privacy: .public)")
            return skipToolCall(context, reason: reason)
        }
        toolCallState.recordExecution(ref: ref, args: args)
        let message = await callAllowedTool(context, ref: ref, args: args, tool: tool)
        toolCallState.recordToolMessageContent(message.content)
        return message
    }

    /// 按策略跳过工具调用时，回填 provider 要求的 tool message，但不再执行 MCP。
    func skipToolCall(
        _ context: AgentToolCallContext,
        reason: AgentToolCallSkipReason
    ) -> ChatMessage {
        failToolCall(
            context,
            summary: reason.summary,
            content: reason.content
        )
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
