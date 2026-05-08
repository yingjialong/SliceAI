import Capabilities
import Foundation
import OSLog
import SliceCore

/// Agent Tool 的 ReAct 执行器。
///
/// 执行模型：
/// 1. 构造初始 prompt 和 MCP tool schema；
/// 2. 调用 `LLMProvider.streamToolChat(request:)`；
/// 3. 聚合 provider streaming tool call delta；
/// 4. 按顺序校验 allowlist、权限 gate、调用 MCP；
/// 5. 把每个结果作为 `role: .tool` 消息回填给模型进入下一轮。
public actor AgentExecutor {

    /// 调试日志；只写固定字段，敏感内容进入事件前已脱敏。
    private let logger = Logger(subsystem: "com.sliceai.orchestration", category: "AgentExecutor")
    /// ProviderSelection 解析器；保留在执行器边界，便于后续 capability/cascade agent routing。
    let providerResolver: any ProviderResolverProtocol
    /// MCP client，执行真实 tools/list 与 tools/call。
    let mcpClient: any MCPClientProtocol
    /// 权限 broker；每个 MCP call 走 one-time gate。
    let permissionBroker: any PermissionBrokerProtocol
    /// Keychain 访问器，用于读取 provider API key。
    let keychain: any KeychainAccessing
    /// LLM provider 工厂。
    let llmProviderFactory: any LLMProviderFactory
    /// MCP descriptor snapshot provider。
    let mcpDescriptors: @Sendable () async throws -> [MCPDescriptor]
    /// 单个 MCP tool call 超时。
    let toolCallTimeoutNanoseconds: UInt64

    /// 构造 AgentExecutor。
    /// - Parameters:
    ///   - providerResolver: ProviderSelection 解析器。
    ///   - mcpClient: MCP client。
    ///   - permissionBroker: 权限 broker。
    ///   - keychain: Keychain 访问器。
    ///   - llmProviderFactory: LLM provider 工厂。
    ///   - mcpDescriptors: MCP descriptor snapshot provider。
    ///   - toolCallTimeoutNanoseconds: 单个 MCP tool call 超时。
    public init(
        providerResolver: any ProviderResolverProtocol,
        mcpClient: any MCPClientProtocol,
        permissionBroker: any PermissionBrokerProtocol,
        keychain: any KeychainAccessing,
        llmProviderFactory: any LLMProviderFactory,
        mcpDescriptors: @escaping @Sendable () async throws -> [MCPDescriptor],
        toolCallTimeoutNanoseconds: UInt64 = 30 * 1_000_000_000
    ) {
        self.providerResolver = providerResolver
        self.mcpClient = mcpClient
        self.permissionBroker = permissionBroker
        self.keychain = keychain
        self.llmProviderFactory = llmProviderFactory
        self.mcpDescriptors = mcpDescriptors
        self.toolCallTimeoutNanoseconds = toolCallTimeoutNanoseconds
    }

    /// 执行一次 AgentTool ReAct loop。
    /// - Parameters:
    ///   - tool: 顶层 Tool；用于 provenance、tool id 和权限事件上下文。
    ///   - agent: Tool.kind 中的 AgentTool payload。
    ///   - resolved: 已解析上下文。
    ///   - provider: ProviderResolver 已解析出的 provider。
    /// - Returns: ExecutionEvent stream；错误统一 yield `.failed` 后正常 finish。
    public func run(
        tool: Tool,
        agent: AgentTool,
        resolved: ResolvedExecutionContext,
        provider: Provider
    ) -> AsyncThrowingStream<ExecutionEvent, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                await self.runSafely(
                    tool: tool,
                    agent: agent,
                    resolved: resolved,
                    provider: provider,
                    continuation: continuation
                )
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 包装主流程，将错误转为 `.failed` 事件。
    private func runSafely(
        tool: Tool,
        agent: AgentTool,
        resolved: ResolvedExecutionContext,
        provider: Provider,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async {
        do {
            try await runInternal(
                tool: tool,
                agent: agent,
                resolved: resolved,
                provider: provider,
                continuation: continuation
            )
            continuation.finish()
        } catch is CancellationError {
            continuation.finish()
        } catch let error as SliceError {
            continuation.yield(.failed(error))
            continuation.finish()
        } catch {
            continuation.yield(.failed(.execution(.unknown("AgentExecutor failed"))))
            continuation.finish()
        }
    }

    /// AgentExecutor 主流程。
    private func runInternal(
        tool: Tool,
        agent: AgentTool,
        resolved: ResolvedExecutionContext,
        provider: Provider,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async throws {
        _ = providerResolver
        try validateSupportedStopCondition(agent.stopCondition, toolId: tool.id)
        let llm = try await makeLLMProvider(provider: provider)
        let catalog = try await makeToolCatalog(tool: tool, agent: agent)
        var messages = AgentPromptBuilder.buildInitialMessages(agent: agent, resolved: resolved)
        let model = resolveModel(selection: agent.provider, fallback: provider.defaultModel)
        let maxSteps = max(1, agent.maxSteps)

        for step in 0..<maxSteps {
            logger.debug("agent step \(step, privacy: .public) started")
            let turn = try await runLLMTurn(
                llm: llm,
                model: model,
                messages: messages,
                catalog: catalog,
                continuation: continuation
            )
            guard !turn.toolCalls.isEmpty else { return }
            messages.append(ChatMessage(
                role: .assistant,
                content: turn.assistantText.isEmpty ? nil : turn.assistantText,
                toolCallID: nil,
                toolCalls: turn.toolCalls
            ))
            let toolMessages = await processToolCalls(
                turn.toolCalls,
                catalog: catalog,
                tool: tool,
                continuation: continuation
            )
            messages.append(contentsOf: toolMessages)
        }
    }

    /// 校验当前 AgentExecutor 支持的 stop condition。
    ///
    /// `.maxStepsReached` 语义要求即使模型没有继续发起 tool call 也要跑满 step，
    /// 这需要额外的 follow-up prompt 设计。Task 11 先 fail-closed，避免配置静默失效。
    private func validateSupportedStopCondition(_ stopCondition: StopCondition, toolId: String) throws {
        switch stopCondition {
        case .finalAnswerProvided, .noToolCall:
            return
        case .maxStepsReached:
            throw SliceError.configuration(.invalidTool(
                id: toolId,
                reason: "Agent stopCondition maxStepsReached is not supported yet"
            ))
        }
    }

    /// 创建 LLMProvider，复用 PromptExecutor 的 provider/keychain 语义。
    private func makeLLMProvider(provider: Provider) async throws -> any LLMProvider {
        try llmProviderFactory.validate(provider: provider)
        guard let account = provider.keychainAccount else {
            throw SliceError.provider(.unauthorized)
        }
        try Task.checkCancellation()
        guard let apiKey = try await keychain.readAPIKey(providerId: account),
              !apiKey.isEmpty else {
            throw SliceError.provider(.unauthorized)
        }
        try Task.checkCancellation()
        return try llmProviderFactory.make(for: provider, apiKey: apiKey)
    }

    /// 跑一轮 LLM tool chat stream。
    private func runLLMTurn(
        llm: any LLMProvider,
        model: String,
        messages: [ChatMessage],
        catalog: AgentToolCatalog,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async throws -> AgentTurn {
        let request = ChatToolRequest(
            model: model,
            messages: messages,
            tools: catalog.chatTools,
            toolChoice: .auto
        )
        let stream = try await llm.streamToolChat(request: request)
        var assembler = AgentToolCallAssembler()
        var assistantText = ""
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .textDelta(let delta):
                assistantText += delta
                continuation.yield(.llmChunk(delta: delta))
            case .toolCallDelta(let delta):
                assembler.apply(delta)
            case .finished:
                break
            }
        }
        return AgentTurn(assistantText: assistantText, toolCalls: try assembler.assemble())
    }

    /// 解析工具级 model override。
    private nonisolated func resolveModel(selection: ProviderSelection, fallback: String) -> String {
        if case .fixed(_, let modelId) = selection, let modelId {
            return modelId
        }
        return fallback
    }
}
