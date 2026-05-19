import Capabilities
import SliceCore
import XCTest
@testable import Orchestration

/// AgentExecutor ReAct loop 测试。
///
/// 覆盖重点：
/// - LLM tool call 只能调用 Agent allowlist 中的 MCP tool；
/// - allowlist / arguments 校验必须先于 PermissionBroker 与 MCPClient；
/// - 每个 provider tool_call_id 都必须回填一条 `role: .tool` 消息，让模型有机会产出最终答案；
/// - MCP 结果进入模型前必须脱敏，避免工具输出中的 token/API key 泄漏进下一轮 prompt。
final class AgentExecutorTests: XCTestCase {

    // MARK: - Fixtures

    /// 默认 MCP ref：`fs.read`。
    private let readRef = MCPToolRef(server: "fs", tool: "read")
    /// 默认 disallowed MCP ref：`fs.write`。
    private let writeRef = MCPToolRef(server: "fs", tool: "write")

    /// 构造测试用 AgentExecutor 和注入依赖。
    /// - Parameters:
    ///   - llm: tool-calling LLM mock。
    ///   - broker: 权限 broker mock。
    ///   - mcpClient: MCP client mock。
    ///   - descriptors: MCP server 描述列表。
    ///   - timeout: 单个 tool call 超时。
    /// - Returns: executor 与关键 mock。
    private func makeExecutor(
        llm: MockToolCallingLLMProvider,
        broker: MockPermissionBroker = MockPermissionBroker(),
        mcpClient: any MCPClientProtocol,
        descriptors: [MCPDescriptor]? = nil,
        timeout: UInt64 = 1_000_000_000
    ) -> AgentExecutor {
        AgentExecutor(
            providerResolver: MockProviderResolver(),
            mcpClient: mcpClient,
            permissionBroker: broker,
            keychain: MockKeychain(["openai-stub": "fake-key"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm),
            mcpDescriptors: { descriptors ?? [Self.fsDescriptor] },
            toolCallTimeoutNanoseconds: timeout
        )
    }

    /// 构造 agent tool。
    /// - Parameters:
    ///   - allowlist: MCP tool allowlist。
    ///   - maxSteps: 最大 ReAct 轮数。
    /// - Returns: AgentTool。
    private func makeAgent(
        allowlist: [MCPToolRef]? = nil,
        maxSteps: Int = 4,
        stopCondition: StopCondition = .finalAnswerProvided,
        toolCallPolicy: AgentToolCallPolicy? = nil
    ) -> AgentTool {
        AgentTool(
            systemPrompt: "You are an agent.",
            initialUserPrompt: "Read {{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai-stub", modelId: nil),
            skill: nil,
            mcpAllowlist: allowlist ?? [readRef],
            builtinCapabilities: [],
            maxSteps: maxSteps,
            stopCondition: stopCondition,
            toolCallPolicy: toolCallPolicy
        )
    }

    /// 构造包裹 AgentTool 的 Tool。
    /// - Parameter agent: AgentTool。
    /// - Returns: Tool。
    private func makeTool(agent: AgentTool? = nil) -> Tool {
        let actualAgent = agent ?? makeAgent()
        return Tool(
            id: "agent.read",
            name: "Agent Read",
            icon: "A",
            description: nil,
            kind: .agent(actualAgent),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [.mcp(server: "fs", tools: ["read"])],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造已解析上下文。
    /// - Returns: ResolvedExecutionContext。
    private func makeResolvedContext() -> ResolvedExecutionContext {
        let seed = ExecutionSeed(
            invocationId: UUID(),
            selection: SelectionSnapshot(
                text: "/tmp/a.txt",
                source: .accessibility,
                length: 10,
                language: "en",
                contentType: nil
            ),
            frontApp: AppSnapshot(
                bundleId: "com.test",
                name: "TestApp",
                url: URL(string: "https://example.com"),
                windowTitle: "Window"
            ),
            screenAnchor: .zero,
            timestamp: Date(),
            triggerSource: .floatingToolbar,
            isDryRun: false
        )
        return ResolvedExecutionContext(
            seed: seed,
            contexts: ContextBag(values: [ContextKey(rawValue: "ctx.note"): .text("context value")]),
            resolvedAt: Date(),
            failures: [:]
        )
    }

    /// 收集 executor 事件。
    /// - Parameter stream: AgentExecutor 返回的事件流。
    /// - Returns: 所有事件。
    private func collectEvents(
        from stream: AsyncThrowingStream<ExecutionEvent, any Error>
    ) async -> [ExecutionEvent] {
        var events: [ExecutionEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch {
            XCTFail("AgentExecutor stream should yield .failed instead of throwing: \(error)")
        }
        return events
    }

    /// 构造一个完整 tool call turn。
    /// - Parameters:
    ///   - id: provider tool_call_id。
    ///   - name: function tool 名。
    ///   - arguments: raw arguments。
    /// - Returns: LLM stream events。
    private func toolCallTurn(id: String, name: String, arguments: String) -> [ChatStreamEvent] {
        [
            .toolCallDelta(ChatToolCallDelta(
                index: 0,
                id: id,
                name: name,
                argumentsDelta: arguments
            )),
            .finished(.toolCalls)
        ]
    }

    /// 构造两个并行 tool call 的 turn。
    /// - Returns: LLM stream events。
    private func parallelToolCallTurn() -> [ChatStreamEvent] {
        [
            .toolCallDelta(ChatToolCallDelta(
                index: 0,
                id: "call-read",
                name: "read",
                argumentsDelta: "{\"path\":\"/tmp/a.txt\"}"
            )),
            .toolCallDelta(ChatToolCallDelta(
                index: 1,
                id: "call-write",
                name: "write",
                argumentsDelta: "{\"path\":\"/tmp/b.txt\"}"
            )),
            .finished(.toolCalls)
        ]
    }

    /// 构造多个同名 tool call 的 turn，用于验证总 tool call 预算。
    /// - Parameter count: 本轮模型请求的工具调用数量。
    /// - Returns: LLM stream events。
    private func repeatedReadToolCallTurn(count: Int) -> [ChatStreamEvent] {
        let deltas = (0..<count).map { index in
            ChatStreamEvent.toolCallDelta(ChatToolCallDelta(
                index: index,
                id: "call-\(index)",
                name: "read",
                argumentsDelta: "{\"path\":\"/tmp/a-\(index).txt\"}"
            ))
        }
        return deltas + [.finished(.toolCalls)]
    }

    /// 构造多个参数完全相同的同名 tool call，用于验证去重策略。
    /// - Parameter count: 本轮模型请求的重复工具调用数量。
    /// - Returns: LLM stream events。
    private func duplicateReadToolCallTurn(count: Int) -> [ChatStreamEvent] {
        let deltas = (0..<count).map { index in
            ChatStreamEvent.toolCallDelta(ChatToolCallDelta(
                index: index,
                id: "dup-\(index)",
                name: "read",
                argumentsDelta: "{\"path\":\"/tmp/same.txt\"}"
            ))
        }
        return deltas + [.finished(.toolCalls)]
    }

    /// 构造最终答案 turn。
    /// - Parameter text: 模型输出文本。
    /// - Returns: LLM stream events。
    private func finalAnswerTurn(_ text: String = "Done") -> [ChatStreamEvent] {
        [.textDelta(text), .finished(.stop)]
    }

    /// 构造 DeepSeek thinking mode 风格的 tool call turn。
    /// - Returns: 带 reasoning delta、空 content 与 tool call 的 LLM stream events。
    private func reasoningToolCallTurn() -> [ChatStreamEvent] {
        [
            .reasoningDelta("Need search first."),
            .toolCallDelta(ChatToolCallDelta(
                index: 0,
                id: "call-1",
                name: "read",
                argumentsDelta: "{\"path\":\"/tmp/a.txt\"}"
            )),
            .finished(.toolCalls)
        ]
    }

    /// 默认 MCP 成功结果。
    /// - Parameter text: 文本内容。
    /// - Returns: MCPCallResult。
    private func mcpSuccess(_ text: String = "file contents") -> MCPCallResult {
        MCPCallResult(
            content: [.text(text)],
            structuredContent: nil,
            isError: false,
            meta: nil
        )
    }

    /// 默认 MCP client。
    /// - Parameter responses: tool ref 到结果。
    /// - Returns: MockMCPClient。
    private func makeMCPClient(
        responses: [MCPToolRef: MCPCallResult]? = nil
    ) -> MockMCPClient {
        MockMCPClient(
            tools: [Self.fsDescriptor: [Self.readToolDescriptor, Self.writeToolDescriptor]],
            responses: responses ?? [readRef: mcpSuccess()]
        )
    }

    // MARK: - Tests

    /// 成功路径：allowed MCP tool → broker approved → MCP result → 模型最终答案。
    func test_agentExecutor_callsAllowedMCPToolAndReturnsFinalAnswer() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn("Read complete")
        ])
        let broker = MockPermissionBroker()
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, broker: broker, mcpClient: mcp)
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        guard case .toolCallProposed(let id, let ref, let args) = events[0] else {
            XCTFail("event[0] expected proposed, got \(events)"); return
        }
        XCTAssertEqual(ref, readRef)
        XCTAssertTrue(args.contains("path"))
        guard case .toolCallApproved(let approvedId) = events[1] else {
            XCTFail("event[1] expected approved, got \(events)"); return
        }
        XCTAssertEqual(approvedId, id)
        guard case .toolCallResult(let resultId, let summary) = events[2] else {
            XCTFail("event[2] expected result, got \(events)"); return
        }
        XCTAssertEqual(resultId, id)
        XCTAssertTrue(summary.contains("file contents"))
        guard case .llmChunk(let delta) = events[3] else {
            XCTFail("event[3] expected final llm chunk, got \(events)"); return
        }
        XCTAssertEqual(delta, "Read complete")
        let mcpCallCount = await mcp.callCount
        let brokerCallCount = await broker.gateCalls.count
        XCTAssertEqual(mcpCallCount, 1)
        XCTAssertEqual(brokerCallCount, 1)
    }

    /// 多 server 暴露同名非 allowlist 工具时，不应阻断实际 allowlist 内的不同工具。
    func test_agentExecutor_allowsMultiServerCatalogWhenOnlyNonAllowlistedNamesOverlap() async throws {
        let queryRef = MCPToolRef(server: "db", tool: "query")
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-query", name: "query", arguments: "{\"sql\":\"select 1\"}"),
            finalAnswerTurn("Query complete")
        ])
        let dbDescriptor = Self.dbDescriptor
        let mcp = MockMCPClient(
            tools: [
                Self.fsDescriptor: [Self.readToolDescriptor, Self.writeToolDescriptor],
                dbDescriptor: [Self.dbReadToolDescriptor, Self.queryToolDescriptor]
            ],
            responses: [queryRef: mcpSuccess("rows")]
        )
        let executor = makeExecutor(
            llm: llm,
            mcpClient: mcp,
            descriptors: [Self.fsDescriptor, dbDescriptor]
        )
        let agent = makeAgent(allowlist: [readRef, queryRef])

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertFalse(events.contains { event in
            if case .failed = event { return true }
            return false
        })
        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(mcpCallCount, 1)
        XCTAssertEqual(llm.capturedToolRequests.first?.tools.map(\.name).sorted(), ["query", "read"])
    }

    /// allowlist 外 tool 必须在 broker/MCP 之前被拒绝。
    func test_agentExecutor_rejectsToolNotInAllowlistBeforeBroker() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "write", arguments: "{\"path\":\"/tmp/b.txt\"}"),
            finalAnswerTurn("Cannot write")
        ])
        let broker = MockPermissionBroker()
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, broker: broker, mcpClient: mcp)
        let agent = makeAgent(allowlist: [readRef])

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let brokerCallCount = await broker.gateCalls.count
        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(brokerCallCount, 0)
        XCTAssertEqual(mcpCallCount, 0)
        guard case .toolCallProposed(let proposedId, let ref, _) = events[0] else {
            XCTFail("event[0] expected proposed, got \(events)"); return
        }
        XCTAssertEqual(ref.server, "<redacted>")
        XCTAssertEqual(ref.tool, writeRef.tool)
        guard case .toolCallDenied(let deniedId, let reason) = events[1] else {
            XCTFail("event[1] expected denied, got \(events)"); return
        }
        XCTAssertEqual(deniedId, proposedId)
        XCTAssertTrue(reason.contains("not allowed"))
    }

    /// allowlist 外 tool 应回填 tool message，而不是直接中止 loop。
    func test_agentExecutor_outOfAllowlistToolCallReturnsToolMessageWithoutBroker() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-write", name: "write", arguments: "{\"path\":\"/tmp/b.txt\"}"),
            finalAnswerTurn("I used an allowed explanation")
        ])
        let broker = MockPermissionBroker()
        let executor = makeExecutor(llm: llm, broker: broker, mcpClient: makeMCPClient())
        let agent = makeAgent(allowlist: [readRef])

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let brokerCallCount = await broker.gateCalls.count
        XCTAssertEqual(brokerCallCount, 0)
        XCTAssertEqual(llm.capturedToolRequests.count, 2)
        let secondMessages = llm.capturedToolRequests[1].messages
        XCTAssertTrue(secondMessages.contains { message in
            message.role == .tool
                && message.toolCallID == "call-write"
                && message.content == "Tool not allowed in this Agent allowlist"
        })
    }

    /// broker 拒绝后应回填 tool result，让模型输出最终答案。
    func test_agentExecutor_denialIsReturnedAsToolResultAndModelFinalizes() async throws {
        let permission = Permission.mcp(server: "fs", tools: ["read"])
        let broker = MockPermissionBroker(
            outcomeOverride: .denied(permission: permission, reason: "blocked Bearer secret-token")
        )
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn("Permission denied")
        ])
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, broker: broker, mcpClient: mcp)
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(mcpCallCount, 0)
        guard case .toolCallDenied(_, let reason) = events[1] else {
            XCTFail("event[1] expected denied, got \(events)"); return
        }
        XCTAssertFalse(reason.contains("secret-token"))
        XCTAssertTrue(reason.contains("<redacted>"))
        XCTAssertTrue(llm.capturedToolRequests[1].messages.contains { message in
            message.role == .tool && message.content?.contains("<redacted>") == true
        })
    }

    /// MCPClient 抛错应产出 toolCallError，并继续让模型 finalize。
    func test_agentExecutor_mcpErrorYieldsToolCallErrorAndModelFinalizes() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn("Tool failed")
        ])
        let mcp = MockMCPClient(tools: [Self.fsDescriptor: [Self.readToolDescriptor]], responses: [:])
        let executor = makeExecutor(llm: llm, mcpClient: mcp)
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(mcpCallCount, 1)
        XCTAssertTrue(events.contains { event in
            if case .toolCallError(_, let summary) = event {
                return summary.contains("<redacted>")
            }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .llmChunk(let delta) = event, delta == "Tool failed" { return true }
            return false
        })
    }

    /// MCP result `isError=true` 应映射为 toolCallError。
    func test_agentExecutor_mcpResultIsErrorYieldsToolCallErrorEvent() async throws {
        let errorResult = MCPCallResult(
            content: [.text("backend error sk-1234567890123456")],
            structuredContent: nil,
            isError: true,
            meta: nil
        )
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn("Tool returned error")
        ])
        let executor = makeExecutor(
            llm: llm,
            mcpClient: makeMCPClient(responses: [readRef: errorResult])
        )
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertTrue(events.contains { event in
            if case .toolCallError(_, let summary) = event {
                return summary.contains("<redacted>")
            }
            return false
        })
    }

    /// 非 JSON object arguments 应在 broker/MCP 之前变成 toolCallError。
    func test_agentExecutor_invalidToolArgumentsAreSurfacedAsToolCallError() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "not-json"),
            finalAnswerTurn("Arguments invalid")
        ])
        let broker = MockPermissionBroker()
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, broker: broker, mcpClient: mcp)
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let brokerCallCount = await broker.gateCalls.count
        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(brokerCallCount, 0)
        XCTAssertEqual(mcpCallCount, 0)
        XCTAssertTrue(events.contains { event in
            if case .toolCallError(_, let summary) = event, summary == "invalid tool arguments" { return true }
            return false
        })
    }

    /// 同一 assistant turn 的多个 tool call 按顺序处理，允许成功/拒绝混合。
    func test_agentExecutor_handlesParallelToolCallsWithMixedDenialAndSuccess() async throws {
        let broker = MockPermissionBroker(outcomeFunction: { callIndex, _, _, _, _ in
            callIndex == 0
                ? .approved
                : .denied(permission: .mcp(server: "fs", tools: ["write"]), reason: "write denied")
        })
        let llm = MockToolCallingLLMProvider(turns: [
            parallelToolCallTurn(),
            finalAnswerTurn("Mixed done")
        ])
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, broker: broker, mcpClient: mcp)
        let agent = makeAgent(allowlist: [readRef, writeRef])

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(mcpCallCount, 1)
        XCTAssertTrue(events.contains { event in
            if case .toolCallResult = event { return true }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .toolCallDenied = event { return true }
            return false
        })
    }

    /// 达到 maxSteps 后应禁用工具并请求一次最终答案，避免工具调用完成后静默无结果。
    func test_agentExecutor_finalizesWithToolsDisabledAfterMaxSteps() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn("Final summary")
        ])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent(maxSteps: 1)

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertEqual(llm.toolStreamCallCount, 2)
        guard llm.capturedToolRequests.indices.contains(1) else {
            XCTFail("expected final answer request after maxSteps")
            return
        }
        XCTAssertTrue(llm.capturedToolRequests[1].tools.isEmpty)
        XCTAssertNil(llm.capturedToolRequests[1].toolChoice)
        XCTAssertTrue(events.contains { event in
            if case .llmChunk(let delta) = event, delta == "Final summary" { return true }
            return false
        })
    }

    /// 达到 maxSteps 后的最终回合不应再向 provider 暴露 tools schema。
    func test_agentExecutor_finalizationRequestOmitsToolsAfterMaxSteps() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn("Final summary")
        ])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent(maxSteps: 1)

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        guard llm.capturedToolRequests.indices.contains(1) else {
            XCTFail("expected final answer request after maxSteps")
            return
        }
        let finalRequest = llm.capturedToolRequests[1]
        XCTAssertTrue(finalRequest.tools.isEmpty)
        XCTAssertNil(finalRequest.toolChoice)
        XCTAssertEqual(finalRequest.messages.last?.role, .user)
        XCTAssertTrue(finalRequest.messages.last?.content?.contains("No more tool calls are available") == true)
    }

    /// 最终回合若返回 DSML 工具调用文本，不应把内部协议标记写入 UI。
    func test_agentExecutor_rejectsFinalizationToolMarkupWithoutStreamingIt() async throws {
        let dsml = """
        <|DSML|tool_calls>
        <|DSML|invoke name="brave_web_search">
        <|DSML|parameter name="query" string="true">Claude Code</|DSML|parameter>
        </|DSML|invoke>
        </|DSML|tool_calls>
        """
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn(dsml)
        ])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent(maxSteps: 1)

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertFalse(events.contains { event in
            if case .llmChunk(let delta) = event {
                return delta.contains("DSML") || delta.contains("tool_calls")
            }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .failed(.provider(.invalidResponse(let reason))) = event {
                return reason.contains("tool-call markup")
            }
            return false
        })
    }

    /// maxSteps 只限制 ReAct 轮数；单轮 tool call 数量由独立 policy 控制。
    func test_agentExecutor_maxStepsDoesNotCapToolCallsWhenPolicyAllows() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            repeatedReadToolCallTurn(count: 3),
            finalAnswerTurn("Enough context")
        ])
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, mcpClient: mcp)
        let policy = AgentToolCallPolicy(
            maxTotalCalls: 3,
            maxCallsPerTurn: 3,
            perToolLimits: [],
            duplicateArgumentStrategy: .allow,
            stopOnRateLimit: true
        )
        let agent = makeAgent(maxSteps: 1, toolCallPolicy: policy)

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(mcpCallCount, 3)
        XCTAssertEqual(llm.toolStreamCallCount, 2)

        let finalMessages = llm.capturedToolRequests[1].messages
        let toolMessages = finalMessages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 3)
    }

    /// 单次运行的 MCP tool call 总数由 AgentToolCallPolicy 约束，避免一轮多工具调用打爆外部限流。
    func test_agentExecutor_policyCapsTotalToolCallsPerRun() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            repeatedReadToolCallTurn(count: 3),
            finalAnswerTurn("Enough context")
        ])
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, mcpClient: mcp)
        let policy = AgentToolCallPolicy(
            maxTotalCalls: 2,
            maxCallsPerTurn: 3,
            perToolLimits: [],
            duplicateArgumentStrategy: .allow,
            stopOnRateLimit: true
        )
        let agent = makeAgent(maxSteps: 4, toolCallPolicy: policy)

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(mcpCallCount, 2)
        XCTAssertEqual(llm.toolStreamCallCount, 2)

        let finalMessages = llm.capturedToolRequests[1].messages
        let toolMessages = finalMessages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 3)
        XCTAssertTrue(toolMessages.contains { message in
            message.content?.contains("per-run tool call limit reached") == true
        })
        XCTAssertTrue(events.contains { event in
            if case .toolCallError(_, let summary) = event {
                return summary.contains("tool call budget exhausted")
            }
            return false
        })
    }

    /// 去重策略为 skipExactArguments 时，同一轮完全相同的 MCP 调用只执行一次。
    func test_agentExecutor_policySkipsDuplicateExactArguments() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            duplicateReadToolCallTurn(count: 2),
            finalAnswerTurn("Deduped")
        ])
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, mcpClient: mcp)
        let policy = AgentToolCallPolicy(
            maxTotalCalls: 2,
            maxCallsPerTurn: 2,
            perToolLimits: [],
            duplicateArgumentStrategy: .skipExactArguments,
            stopOnRateLimit: true
        )
        let agent = makeAgent(toolCallPolicy: policy)

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(mcpCallCount, 1)
        let toolMessages = llm.capturedToolRequests[1].messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 2)
        XCTAssertTrue(events.contains { event in
            if case .toolCallError(_, let summary) = event {
                return summary.contains("duplicate tool call skipped")
            }
            return false
        })
    }

    /// stopOnRateLimit 开启时，命中限流后同轮后续 MCP 调用应跳过，避免继续放大限流。
    func test_agentExecutor_policyStopsFurtherCallsAfterRateLimit() async throws {
        let longRateLimitBody = String(repeating: "diagnostic payload ", count: 20)
            + "Error: Rate limit exceeded"
        let rateLimited = MCPCallResult(
            content: [.text(longRateLimitBody)],
            structuredContent: nil,
            isError: true,
            meta: nil
        )
        let llm = MockToolCallingLLMProvider(turns: [
            repeatedReadToolCallTurn(count: 2),
            finalAnswerTurn("Rate limit handled")
        ])
        let mcp = makeMCPClient(responses: [readRef: rateLimited])
        let executor = makeExecutor(llm: llm, mcpClient: mcp)
        let policy = AgentToolCallPolicy(
            maxTotalCalls: 2,
            maxCallsPerTurn: 2,
            perToolLimits: [],
            duplicateArgumentStrategy: .allow,
            stopOnRateLimit: true
        )
        let agent = makeAgent(toolCallPolicy: policy)

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let mcpCallCount = await mcp.callCount
        XCTAssertEqual(mcpCallCount, 1)
        XCTAssertTrue(events.contains { event in
            if case .toolCallError(_, let summary) = event {
                return summary.contains("rate limit")
            }
            return false
        })
    }

    /// 达到 maxSteps 后不应继续允许模型再次调用工具。
    func test_agentExecutor_stopsAtMaxSteps() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn("should-not-run")
        ])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent(maxSteps: 1)

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertEqual(llm.toolStreamCallCount, 2)
        guard llm.capturedToolRequests.indices.contains(1) else {
            XCTFail("expected final answer request after maxSteps")
            return
        }
        XCTAssertTrue(llm.capturedToolRequests[1].tools.isEmpty)
        XCTAssertNil(llm.capturedToolRequests[1].toolChoice)
    }

    /// 当前执行器不支持“必须跑满 maxSteps”的 stopCondition，必须 fail-closed，避免配置静默失效。
    func test_agentExecutor_rejectsUnsupportedMaxStepsStopConditionBeforeLLMCall() async throws {
        let llm = MockToolCallingLLMProvider(turns: [finalAnswerTurn("should-not-run")])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent(stopCondition: .maxStepsReached)

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertEqual(llm.toolStreamCallCount, 0)
        guard case .failed(.configuration(.invalidTool(let id, let reason))) = events.first else {
            XCTFail("expected failed event, got \(events)")
            return
        }
        XCTAssertEqual(id, "agent.read")
        XCTAssertTrue(reason.contains("maxStepsReached"))
    }

    /// 单个 MCP 调用超时应转为 toolCallError，并继续下一轮模型 final answer。
    func test_agentExecutor_timesOutSingleToolCall() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn("Timeout handled")
        ])
        let executor = makeExecutor(
            llm: llm,
            mcpClient: HangingMCPClient(tools: [Self.fsDescriptor: [Self.readToolDescriptor]]),
            timeout: 10_000_000
        )
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertTrue(events.contains { event in
            if case .toolCallError(_, let summary) = event {
                return summary.contains("timed out")
            }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .llmChunk(let delta) = event, delta == "Timeout handled" { return true }
            return false
        })
    }

    /// MCP result 进入下一轮模型消息前必须脱敏。
    func test_agentExecutor_redactsMCPResultBeforeModelMessage() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn()
        ])
        let executor = makeExecutor(
            llm: llm,
            mcpClient: makeMCPClient(responses: [readRef: mcpSuccess("secret sk-1234567890123456")])
        )
        let agent = makeAgent()

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let toolMessages = llm.capturedToolRequests[1].messages.filter { $0.role == .tool }
        XCTAssertEqual(toolMessages.count, 1)
        XCTAssertFalse(toolMessages[0].content?.contains("sk-1234567890123456") == true)
        XCTAssertTrue(toolMessages[0].content?.contains("<redacted>") == true)
    }

    /// 长 MCP 结果进入下一轮模型消息时应保留实际内容，只做敏感信息脱敏，不能变成 `<truncated:N>`。
    func test_agentExecutor_preservesLongMCPResultContentInModelToolMessage() async throws {
        let longSearchResult = (1...35)
            .map { index in "Search result \(index): SliceAI MCP context result body." }
            .joined(separator: "\n")
            + "\nsecret sk-1234567890123456"
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn()
        ])
        let executor = makeExecutor(
            llm: llm,
            mcpClient: makeMCPClient(responses: [readRef: mcpSuccess(longSearchResult)])
        )
        let agent = makeAgent()

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let toolMessages = llm.capturedToolRequests[1].messages.filter { $0.role == .tool }
        let toolContent = try XCTUnwrap(toolMessages.first?.content)
        XCTAssertFalse(toolContent.contains("<truncated:"))
        XCTAssertTrue(toolContent.contains("Search result 35"))
        XCTAssertFalse(toolContent.contains("sk-1234567890123456"))
        XCTAssertTrue(toolContent.contains("<redacted>"))
    }

    /// MCP inputSchema 必须原样传给 LLM tools。
    func test_agentExecutor_passesMCPInputSchemaToLLM() async throws {
        let llm = MockToolCallingLLMProvider(turns: [finalAnswerTurn()])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent()

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertEqual(llm.capturedToolRequests.first?.tools.first?.inputSchema, Self.readToolDescriptor.inputSchema)
    }

    /// AgentExecutor 应按 server id 解析 MCPDescriptor 并调用 `tools(for:)`。
    func test_agentExecutor_resolvesMCPDescriptorFromServerID() async throws {
        let llm = MockToolCallingLLMProvider(turns: [finalAnswerTurn()])
        let mcp = makeMCPClient()
        let executor = makeExecutor(llm: llm, mcpClient: mcp)
        let agent = makeAgent()

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let lastToolsDescriptor = await mcp.lastToolsDescriptor
        XCTAssertEqual(lastToolsDescriptor, Self.fsDescriptor)
    }

    /// allowlist 引用的 server 不存在时，应在第一次 LLM 调用前失败。
    func test_agentExecutor_missingDescriptorFailsBeforeLLMCall() async throws {
        let llm = MockToolCallingLLMProvider(turns: [finalAnswerTurn()])
        let executor = makeExecutor(
            llm: llm,
            mcpClient: makeMCPClient(),
            descriptors: []
        )
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertEqual(llm.toolStreamCallCount, 0)
        guard case .failed(.configuration(.invalidTool(let id, _))) = events.first else {
            XCTFail("expected configuration invalidTool failure, got \(events)"); return
        }
        XCTAssertEqual(id, "agent.read")
    }

    /// 重复 MCPDescriptor id 必须走可恢复失败，不能触发 `Dictionary(uniqueKeysWithValues:)` trap。
    func test_agentExecutor_duplicateDescriptorIDsFailBeforeLLMCall() async throws {
        let llm = MockToolCallingLLMProvider(turns: [finalAnswerTurn()])
        let executor = makeExecutor(
            llm: llm,
            mcpClient: makeMCPClient(),
            descriptors: [Self.fsDescriptor, Self.duplicateFSDescriptor]
        )
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        XCTAssertEqual(llm.toolStreamCallCount, 0)
        guard case .failed(.configuration(.validationFailed(let reason))) = events.first else {
            XCTFail("expected validationFailed, got \(events)")
            return
        }
        XCTAssertTrue(reason.contains("Duplicate MCP server id"))
    }

    /// 下一轮请求必须先包含 assistant tool_calls message，再包含 tool result message。
    func test_agentExecutor_appendsAssistantToolCallMessageBeforeToolResult() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "call-1", name: "read", arguments: "{\"path\":\"/tmp/a.txt\"}"),
            finalAnswerTurn()
        ])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent()

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let messages = llm.capturedToolRequests[1].messages
        guard let assistantIndex = messages.firstIndex(where: { $0.role == .assistant && $0.toolCalls != nil }),
              let toolIndex = messages.firstIndex(where: { $0.role == .tool }) else {
            XCTFail("expected assistant tool_calls and tool message, got \(messages)"); return
        }
        XCTAssertLessThan(assistantIndex, toolIndex)
        XCTAssertEqual(messages[toolIndex].toolCallID, "call-1")
    }

    /// DeepSeek V4 thinking mode 要求后续请求回传 assistant.reasoning_content。
    func test_agentExecutor_preservesReasoningContentForToolCallFollowUp() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            reasoningToolCallTurn(),
            finalAnswerTurn()
        ])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent()

        _ = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let messages = llm.capturedToolRequests[1].messages
        let assistant = try XCTUnwrap(messages.first { $0.role == .assistant && $0.toolCalls != nil })
        XCTAssertEqual(assistant.reasoningContent, "Need search first.")
        XCTAssertEqual(assistant.content, "")
    }

    /// 模型文本 delta 必须作为 `.llmChunk` 透出。
    func test_agentExecutor_streamsModelTextDeltasAsLLMChunkEvents() async throws {
        let llm = MockToolCallingLLMProvider(turns: [
            [.textDelta("Hello"), .textDelta(" world"), .finished(.stop)]
        ])
        let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
        let agent = makeAgent()

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let chunks = events.compactMap { event -> String? in
            if case .llmChunk(let delta) = event { return delta }
            return nil
        }
        XCTAssertEqual(chunks, ["Hello", " world"])
    }

    // MARK: - Shared descriptors

    /// 测试用 `fs` MCP server descriptor。
    private static let fsDescriptor = MCPDescriptor(
        id: "fs",
        transport: .stdio,
        command: "mock-fs",
        args: nil,
        url: nil,
        env: nil,
        capabilities: [.tools(["read", "write"])],
        provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 0))
    )

    /// 与 `fsDescriptor` 重复 id 的 descriptor，用于验证 fail-closed 去重。
    private static let duplicateFSDescriptor = MCPDescriptor(
        id: "fs",
        transport: .stdio,
        command: "mock-fs-duplicate",
        args: nil,
        url: nil,
        env: nil,
        capabilities: [.tools(["read"])],
        provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 0))
    )

    /// `fs.read` MCP tool descriptor。
    private static let readToolDescriptor = MCPToolDescriptor(
        ref: MCPToolRef(server: "fs", tool: "read"),
        title: "Read File",
        description: "Read a file",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")])
            ])
        ]
    )

    /// `fs.write` MCP tool descriptor。
    private static let writeToolDescriptor = MCPToolDescriptor(
        ref: MCPToolRef(server: "fs", tool: "write"),
        title: "Write File",
        description: "Write a file",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "path": .object(["type": .string("string")])
            ])
        ]
    )

    /// 测试用 `db` MCP server descriptor。
    private static let dbDescriptor = MCPDescriptor(
        id: "db",
        transport: .stdio,
        command: "mock-db",
        args: nil,
        url: nil,
        env: nil,
        capabilities: [.tools(["read", "query"])],
        provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 0))
    )

    /// `db.read` MCP tool descriptor，用于构造非 allowlist 同名冲突。
    private static let dbReadToolDescriptor = MCPToolDescriptor(
        ref: MCPToolRef(server: "db", tool: "read"),
        title: "DB Read",
        description: "Read database metadata",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "table": .object(["type": .string("string")])
            ])
        ]
    )

    /// `db.query` MCP tool descriptor。
    private static let queryToolDescriptor = MCPToolDescriptor(
        ref: MCPToolRef(server: "db", tool: "query"),
        title: "Query Database",
        description: "Run a read-only query",
        inputSchema: [
            "type": .string("object"),
            "properties": .object([
                "sql": .object(["type": .string("string")])
            ])
        ]
    )
}

// MARK: - Test helper MCP client

/// 永不返回 `call` 的 MCP client，用于验证 AgentExecutor 单次 tool call timeout。
private final actor HangingMCPClient: MCPClientProtocol {
    private let toolsByDescriptor: [MCPDescriptor: [MCPToolDescriptor]]

    /// 构造 HangingMCPClient。
    /// - Parameter tools: server descriptor 到 tool descriptor 的映射。
    init(tools: [MCPDescriptor: [MCPToolDescriptor]]) {
        self.toolsByDescriptor = tools
    }

    /// 返回预置 tools。
    func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolDescriptor] {
        toolsByDescriptor[descriptor] ?? []
    }

    /// 模拟长时间阻塞的 tool call；收到取消后透传 CancellationError。
    func call(ref: MCPToolRef, args: MCPJSONValue.Object) async throws -> MCPCallResult {
        try await Task.sleep(nanoseconds: 60_000_000_000)
        return MCPCallResult(content: [], structuredContent: nil, isError: false, meta: nil)
    }
}
