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
    let logger = Logger(subsystem: "com.sliceai.orchestration", category: "AgentExecutor")
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
    /// Skill registry，供内置 sliceai.load_skill pseudo-tool 按需加载 SKILL.md。
    let skillRegistry: any SkillRegistryProtocol

    /// 构造 AgentExecutor。
    /// - Parameters:
    ///   - providerResolver: ProviderSelection 解析器。
    ///   - mcpClient: MCP client。
    ///   - permissionBroker: 权限 broker。
    ///   - keychain: Keychain 访问器。
    ///   - llmProviderFactory: LLM provider 工厂。
    ///   - mcpDescriptors: MCP descriptor snapshot provider。
    ///   - toolCallTimeoutNanoseconds: 单个 MCP tool call 超时。
    ///   - skillRegistry: Skill registry，用于解析当前 Agent 绑定 skills。
    public init(
        providerResolver: any ProviderResolverProtocol,
        mcpClient: any MCPClientProtocol,
        permissionBroker: any PermissionBrokerProtocol,
        keychain: any KeychainAccessing,
        llmProviderFactory: any LLMProviderFactory,
        mcpDescriptors: @escaping @Sendable () async throws -> [MCPDescriptor],
        toolCallTimeoutNanoseconds: UInt64 = 30 * 1_000_000_000,
        skillRegistry: any SkillRegistryProtocol = MockSkillRegistry()
    ) {
        self.providerResolver = providerResolver
        self.mcpClient = mcpClient
        self.permissionBroker = permissionBroker
        self.keychain = keychain
        self.llmProviderFactory = llmProviderFactory
        self.mcpDescriptors = mcpDescriptors
        self.toolCallTimeoutNanoseconds = toolCallTimeoutNanoseconds
        self.skillRegistry = skillRegistry
    }

    /// 执行一次 AgentTool ReAct loop。
    /// - Parameters:
    ///   - tool: 顶层 Tool；用于 provenance、tool id 和权限事件上下文。
    ///   - agent: Tool.kind 中的 AgentTool payload。
    ///   - resolved: 已解析上下文。
    ///   - provider: ProviderResolver 已解析出的 provider。
    ///   - runPolicy: 本次执行的运行策略；默认生产语义，Playground 可禁用 MCP tool call。
    /// - Returns: ExecutionEvent stream；错误统一 yield `.failed` 后正常 finish。
    public func run(
        tool: Tool,
        agent: AgentTool,
        resolved: ResolvedExecutionContext,
        provider: Provider,
        runPolicy: ExecutionRunPolicy = .production(isDryRun: false)
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
                    runPolicy: runPolicy,
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
        runPolicy: ExecutionRunPolicy,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async {
        do {
            try await runInternal(
                tool: tool,
                agent: agent,
                resolved: resolved,
                provider: provider,
                runPolicy: runPolicy,
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
        runPolicy: ExecutionRunPolicy,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async throws {
        _ = providerResolver
        try validateSupportedStopCondition(agent.stopCondition, toolId: tool.id)
        let llm = try await makeLLMProvider(provider: provider)
        let catalog = try await makeToolCatalog(tool: tool, agent: agent)
        var messages = makeInitialMessages(agent: agent, resolved: resolved, catalog: catalog)
        let model = resolveModel(selection: agent.provider, fallback: provider.defaultModel)
        let maxSteps = max(1, agent.maxSteps)
        var toolCallState = makeToolCallRunState(agent: agent, catalog: catalog, maxSteps: maxSteps)

        for step in 0..<maxSteps {
            logger.debug("agent step \(step, privacy: .public) started")
            let turn = try await runLLMTurn(
                llm: llm,
                request: makeChatToolRequest(model: model, messages: messages, catalog: catalog, toolChoice: .auto),
                continuation: continuation
            )
            guard !turn.toolCalls.isEmpty else { return }
            let turnContext = AgentToolTurnProcessingContext(
                catalog: catalog,
                tool: tool,
                runPolicy: runPolicy,
                continuation: continuation
            )
            let isBudgetExhausted = await appendToolTurnResult(
                turn,
                messages: &messages,
                context: turnContext,
                toolCallState: &toolCallState
            )
            if isBudgetExhausted {
                logger.debug("agent tool call policy stopped further tool use")
                break
            }
        }

        try await requestFinalAnswer(
            llm: llm,
            model: model,
            messages: messages,
            continuation: continuation
        )
    }

    /// 达到工具调用轮数上限后，禁用工具并要求模型基于已有 tool result 产出最终回答。
    private func requestFinalAnswer(
        llm: any LLMProvider,
        model: String,
        messages: [ChatMessage],
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async throws {
        logger.debug("agent max tool steps reached; requesting final answer with tools disabled")
        let finalTurn = try await runLLMTurn(
            llm: llm,
            request: makeFinalAnswerRequest(model: model, messages: messages),
            continuation: continuation,
            emitTextDeltas: false
        )
        if !finalTurn.toolCalls.isEmpty {
            throw SliceError.provider(.invalidResponse("Agent finalization returned tool calls"))
        }
        if finalTurn.assistantText.isEmpty {
            throw SliceError.provider(.invalidResponse("Agent finalization returned empty response"))
        }
        if containsToolCallMarkup(finalTurn.assistantText) {
            logger.warning("agent finalization returned text tool-call markup")
            throw SliceError.provider(.invalidResponse("Agent finalization returned tool-call markup"))
        }
        continuation.yield(.llmChunk(delta: finalTurn.assistantText))
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
        request: ChatToolRequest,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation,
        emitTextDeltas: Bool = true
    ) async throws -> AgentTurn {
        let stream = try await llm.streamToolChat(request: request)
        var assembler = AgentToolCallAssembler()
        var assistantText = ""
        var reasoningContent = ""
        for try await event in stream {
            try Task.checkCancellation()
            switch event {
            case .reasoningDelta(let delta):
                reasoningContent += delta
            case .textDelta(let delta):
                assistantText += delta
                if emitTextDeltas {
                    continuation.yield(.llmChunk(delta: delta))
                }
            case .toolCallDelta(let delta):
                assembler.apply(delta)
            case .finished:
                break
            }
        }
        return AgentTurn(
            assistantText: assistantText,
            reasoningContent: reasoningContent,
            toolCalls: try assembler.assemble()
        )
    }

}
