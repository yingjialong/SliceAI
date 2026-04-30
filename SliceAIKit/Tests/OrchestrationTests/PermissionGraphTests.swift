import SliceCore
import XCTest
@testable import Orchestration

/// Task 7：`PermissionGraph.compute(tool:)` 的 D-24 静态闭环全场景覆盖
///
/// 测试矩阵（plan line 1748-1757，9 + 边界）：
/// 1. prompt + contexts 含 file.read，permissions 缺 .fileRead → undeclared 非空
/// 2. prompt + sideEffects 含 appendToFile，permissions 缺 .fileWrite → undeclared 非空
/// 3. agent + mcpAllowlist 含 ["fs.read"]，permissions 缺 .mcp(...) → undeclared 非空
/// 4. agent + builtinCapabilities 含 .shell（推 shellExec），permissions 缺 → undeclared 非空
/// 5. pipeline + step .mcp 但 permissions 缺 .mcp(...) → undeclared 非空
/// 6. pipeline + step .prompt with contexts 引用 file.read 但 permissions 缺 .fileRead → undeclared 非空
/// 7. registry 缺 provider id → throw .toolPermission(.unknownProvider)
/// 8. 全部声明覆盖（prompt / agent / pipeline 各跑一次）→ undeclared 空
/// 9. empty tool（无 contexts/sideEffects/mcp/builtin）→ effective.union 空集
final class PermissionGraphTests: XCTestCase {

    // MARK: - Test fixtures (mock providers)

    /// 把 args["path"] 推成 .fileRead(path:) 的 Mock provider，覆盖 D-24 静态闭环典型场景
    private final class MockFileReadProvider: ContextProvider, @unchecked Sendable {
        let name: String

        init(name: String = "file.read") {
            self.name = name
        }

        static func inferredPermissions(for args: [String: String]) -> [Permission] {
            // 模拟 spec §3.3.3 file.read provider：args["path"] 被推成 .fileRead(path:)
            if let path = args["path"] {
                return [.fileRead(path: path)]
            }
            return []
        }

        func resolve(
            request: ContextRequest,
            seed: SelectionSnapshot,
            app: AppSnapshot
        ) async throws -> ContextValue {
            // PermissionGraph 不调 resolve；保留以兼容 ContextProvider 协议
            .text("")
        }
    }

    /// 用于第 8 cell：把 args["host"] 推成 .network(host:) 的 Mock provider
    private final class MockNetworkProvider: ContextProvider, @unchecked Sendable {
        let name: String

        init(name: String = "network.fetch") {
            self.name = name
        }

        static func inferredPermissions(for args: [String: String]) -> [Permission] {
            if let host = args["host"] {
                return [.network(host: host)]
            }
            return []
        }

        func resolve(
            request: ContextRequest,
            seed: SelectionSnapshot,
            app: AppSnapshot
        ) async throws -> ContextValue {
            .text("")
        }
    }

    // MARK: - Helpers

    /// 构造空 Tool；调用方用 with* 风格手动改 kind / permissions / outputBinding
    private func makeTool(
        id: String = "test.tool",
        kind: ToolKind,
        permissions: [Permission] = [],
        outputBinding: OutputBinding? = nil,
        provenance: Provenance = .firstParty
    ) -> Tool {
        Tool(
            id: id,
            name: "Test",
            icon: "T",
            description: nil,
            kind: kind,
            visibleWhen: nil,
            displayMode: outputBinding?.primary ?? .window,
            outputBinding: outputBinding,
            permissions: permissions,
            provenance: provenance,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造空 PromptTool 骨架，便于在每个 cell 里只覆盖关心字段
    private func makePromptTool(contexts: [ContextRequest] = []) -> PromptTool {
        PromptTool(
            systemPrompt: nil,
            userPrompt: "u",
            contexts: contexts,
            provider: .fixed(providerId: "p", modelId: nil),
            temperature: nil,
            maxTokens: nil,
            variables: [:]
        )
    }

    /// 构造空 AgentTool 骨架
    private func makeAgentTool(
        contexts: [ContextRequest] = [],
        mcpAllowlist: [MCPToolRef] = [],
        builtinCapabilities: [BuiltinCapability] = []
    ) -> AgentTool {
        AgentTool(
            systemPrompt: nil,
            initialUserPrompt: "u",
            contexts: contexts,
            provider: .fixed(providerId: "p", modelId: nil),
            skill: nil,
            mcpAllowlist: mcpAllowlist,
            builtinCapabilities: builtinCapabilities,
            maxSteps: 5,
            stopCondition: .finalAnswerProvided
        )
    }

    /// 构造典型 file.read ContextRequest（args["path"] 触发 fileRead 推导）
    private func makeFileReadRequest(
        key: String = "doc.text",
        path: String = "~/note.md",
        provider: String = "file.read"
    ) -> ContextRequest {
        ContextRequest(
            key: ContextKey(rawValue: key),
            provider: provider,
            args: ["path": path],
            cachePolicy: .none,
            requiredness: .required
        )
    }

    /// 构造默认 registry：含 file.read + network.fetch 两个 provider
    private func makeDefaultRegistry() -> ContextProviderRegistry {
        ContextProviderRegistry(providers: [
            "file.read": MockFileReadProvider(),
            "network.fetch": MockNetworkProvider()
        ])
    }

    // MARK: - Cell 1: prompt + contexts file.read，缺 .fileRead → undeclared

    func test_compute_promptKind_contextsRequireFileRead_undeclaredWhenMissing() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .prompt(makePromptTool(contexts: [
                makeFileReadRequest(path: "~/Documents/vocab.md")
            ])),
            permissions: [] // 故意不声明 .fileRead
        )

        let effective = try await graph.compute(tool: tool)

        // fromContexts 应含 .fileRead("~/Documents/vocab.md")
        XCTAssertEqual(effective.fromContexts, [.fileRead(path: "~/Documents/vocab.md")])
        // declared 为空，所以 undeclared = union
        XCTAssertEqual(effective.undeclared, [.fileRead(path: "~/Documents/vocab.md")])
        XCTAssertFalse(effective.undeclared.isEmpty, "声明缺失应触发 undeclared 非空")
    }

    // MARK: - Cell 2: prompt + sideEffects appendToFile，缺 .fileWrite → undeclared

    func test_compute_promptKind_sideEffectsRequireFileWrite_undeclaredWhenMissing() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .prompt(makePromptTool()),
            permissions: [], // 故意不声明 .fileWrite
            outputBinding: OutputBinding(
                primary: .window,
                sideEffects: [.appendToFile(path: "~/log.md", header: nil)]
            )
        )

        let effective = try await graph.compute(tool: tool)

        XCTAssertEqual(effective.fromSideEffects, [.fileWrite(path: "~/log.md")])
        XCTAssertEqual(effective.undeclared, [.fileWrite(path: "~/log.md")])
    }

    // MARK: - Cell 3: agent + mcpAllowlist，缺 .mcp(...) → undeclared

    func test_compute_agentKind_mcpAllowlist_undeclaredWhenMissing() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .agent(makeAgentTool(
                mcpAllowlist: [MCPToolRef(server: "fs", tool: "read")]
            )),
            permissions: [] // 故意不声明对应 .mcp
        )

        let effective = try await graph.compute(tool: tool)

        XCTAssertEqual(effective.fromMCP, [.mcp(server: "fs", tools: ["read"])])
        XCTAssertEqual(effective.undeclared, [.mcp(server: "fs", tools: ["read"])])
    }

    // MARK: - Cell 4: agent + builtinCapabilities = .shell，缺 .shellExec → undeclared

    func test_compute_agentKind_builtinShell_undeclaredWhenMissing() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .agent(makeAgentTool(
                builtinCapabilities: [.shell]
            )),
            permissions: [] // 故意不声明 .shellExec
        )

        let effective = try await graph.compute(tool: tool)

        // .shell → .shellExec(commands: [])（空 commands = 全开）
        XCTAssertEqual(effective.fromBuiltins, [.shellExec(commands: [])])
        XCTAssertEqual(effective.undeclared, [.shellExec(commands: [])])
    }

    // MARK: - Cell 5: pipeline + step .mcp，缺 .mcp(...) → undeclared

    func test_compute_pipelineKind_mcpStep_undeclaredWhenMissing() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let pipeline = PipelineTool(
            steps: [
                .mcp(ref: MCPToolRef(server: "kb", tool: "search"), args: [:])
            ],
            onStepFail: .abort
        )
        let tool = makeTool(
            kind: .pipeline(pipeline),
            permissions: [] // 故意不声明 .mcp
        )

        let effective = try await graph.compute(tool: tool)

        XCTAssertEqual(effective.fromMCP, [.mcp(server: "kb", tools: ["search"])])
        XCTAssertEqual(effective.undeclared, [.mcp(server: "kb", tools: ["search"])])
    }

    // MARK: - Cell 6: pipeline + step .prompt(inline:) with contexts，缺 .fileRead → undeclared

    func test_compute_pipelineKind_inlinePromptContexts_undeclaredWhenMissing() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let inlinePrompt = makePromptTool(contexts: [
            makeFileReadRequest(path: "~/inline.md")
        ])
        let pipeline = PipelineTool(
            steps: [
                .prompt(inline: inlinePrompt, input: "x")
            ],
            onStepFail: .abort
        )
        let tool = makeTool(
            kind: .pipeline(pipeline),
            permissions: [] // 故意不声明 .fileRead
        )

        let effective = try await graph.compute(tool: tool)

        // pipeline 的 inline.contexts 应被 extractContexts 递归收集
        XCTAssertEqual(effective.fromContexts, [.fileRead(path: "~/inline.md")])
        XCTAssertEqual(effective.undeclared, [.fileRead(path: "~/inline.md")])
    }

    // MARK: - Cell 7: registry 缺 provider id → throw .toolPermission(.unknownProvider)

    func test_compute_unknownProvider_throwsToolPermissionError() async {
        // 空 registry，但 tool 引用了 "nonexistent.foo"
        let graph = PermissionGraph(providerRegistry: ContextProviderRegistry(providers: [:]))
        let tool = makeTool(
            kind: .prompt(makePromptTool(contexts: [
                ContextRequest(
                    key: ContextKey(rawValue: "k"),
                    provider: "nonexistent.foo",
                    args: [:],
                    cachePolicy: .none,
                    requiredness: .required
                )
            ])),
            permissions: []
        )

        do {
            _ = try await graph.compute(tool: tool)
            XCTFail("应抛 .toolPermission(.unknownProvider)")
        } catch let err as SliceError {
            // exhaustive 模式匹配，避免漏判
            guard case .toolPermission(.unknownProvider(let id)) = err else {
                XCTFail("期待 .toolPermission(.unknownProvider)，实际：\(err)")
                return
            }
            XCTAssertEqual(id, "nonexistent.foo")
        } catch {
            XCTFail("应抛 SliceError，实际：\(error)")
        }
    }

    // MARK: - Cell 8: 全部声明覆盖 → undeclared 空集（prompt / agent / pipeline 各 1）

    /// prompt：声明覆盖 contexts + sideEffects
    func test_compute_promptKind_fullyDeclared_undeclaredEmpty() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .prompt(makePromptTool(contexts: [
                makeFileReadRequest(path: "~/x.md")
            ])),
            permissions: [
                .fileRead(path: "~/x.md"),
                .clipboard
            ],
            outputBinding: OutputBinding(
                primary: .window,
                sideEffects: [.copyToClipboard]
            )
        )

        let effective = try await graph.compute(tool: tool)

        XCTAssertEqual(effective.fromContexts, [.fileRead(path: "~/x.md")])
        XCTAssertEqual(effective.fromSideEffects, [.clipboard])
        XCTAssertTrue(effective.undeclared.isEmpty, "应全部声明覆盖，undeclared=\(effective.undeclared)")
    }

    /// agent：声明覆盖 mcpAllowlist + builtinCapabilities
    func test_compute_agentKind_fullyDeclared_undeclaredEmpty() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            id: "agent.tool",
            kind: .agent(makeAgentTool(
                mcpAllowlist: [MCPToolRef(server: "fs", tool: "read")],
                builtinCapabilities: [.tts]
            )),
            permissions: [
                .mcp(server: "fs", tools: ["read"]),
                .systemAudio
            ]
        )

        let effective = try await graph.compute(tool: tool)

        XCTAssertEqual(effective.fromMCP, [.mcp(server: "fs", tools: ["read"])])
        XCTAssertEqual(effective.fromBuiltins, [.systemAudio])
        XCTAssertTrue(effective.undeclared.isEmpty, "应全部声明覆盖，undeclared=\(effective.undeclared)")
    }

    /// pipeline：声明覆盖 inline-prompt-contexts + step.mcp
    func test_compute_pipelineKind_fullyDeclared_undeclaredEmpty() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let inlinePrompt = makePromptTool(contexts: [
            makeFileReadRequest(path: "~/p.md")
        ])
        let pipeline = PipelineTool(
            steps: [
                .prompt(inline: inlinePrompt, input: "x"),
                .mcp(ref: MCPToolRef(server: "kb", tool: "q"), args: [:])
            ],
            onStepFail: .abort
        )
        let tool = makeTool(
            kind: .pipeline(pipeline),
            permissions: [
                .fileRead(path: "~/p.md"),
                .mcp(server: "kb", tools: ["q"])
            ]
        )

        let effective = try await graph.compute(tool: tool)

        XCTAssertTrue(effective.undeclared.isEmpty, "应全部声明覆盖，undeclared=\(effective.undeclared)")
    }

    // MARK: - Cell 9: empty tool → union 空集

    func test_compute_emptyTool_unionEmpty() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .prompt(makePromptTool()), // 无 contexts
            permissions: [] // 无声明
            // 无 outputBinding（即无 sideEffects）
        )

        let effective = try await graph.compute(tool: tool)

        XCTAssertTrue(effective.fromContexts.isEmpty)
        XCTAssertTrue(effective.fromSideEffects.isEmpty)
        XCTAssertTrue(effective.fromMCP.isEmpty)
        XCTAssertTrue(effective.fromBuiltins.isEmpty)
        XCTAssertTrue(effective.union.isEmpty)
        XCTAssertTrue(effective.undeclared.isEmpty)
    }

    // MARK: - 边界：sideEffect.callMCP 同时累积到 fromSideEffects + fromMCP（不双计 ⊆ 校验）

    /// 验证 sideEffect.callMCP 的 ref 同时进入 fromSideEffects（含 .mcp）+ fromMCP（含 .mcp），
    /// 但 union 通过 Set 自然去重——⊆ 校验只看一次
    func test_compute_callMCPSideEffect_aggregatesToBothMCPAndSideEffects_noDoubleCounting() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .prompt(makePromptTool()),
            permissions: [.mcp(server: "rag", tools: ["search"])],
            outputBinding: OutputBinding(
                primary: .window,
                sideEffects: [.callMCP(
                    ref: MCPToolRef(server: "rag", tool: "search"),
                    params: [:]
                )]
            )
        )

        let effective = try await graph.compute(tool: tool)

        // 两个 set 都含同一条 .mcp（来源不同）
        XCTAssertEqual(effective.fromSideEffects, [.mcp(server: "rag", tools: ["search"])])
        XCTAssertEqual(effective.fromMCP, [.mcp(server: "rag", tools: ["search"])])
        // union 通过 Set.union 去重，只剩 1 项
        XCTAssertEqual(effective.union.count, 1)
        // 已声明，undeclared 空
        XCTAssertTrue(effective.undeclared.isEmpty)
    }

    // MARK: - 边界：builtinCapabilities = .memory 用 tool.id 作 scope

    /// 验证 .memory 映射的 .memoryAccess(scope: tool.id)——与 SideEffect.writeMemory(tool:) 同口径
    func test_compute_agentKind_builtinMemory_usesToolIdAsScope() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            id: "translate.zh",
            kind: .agent(makeAgentTool(builtinCapabilities: [.memory])),
            permissions: [.memoryAccess(scope: "translate.zh")]
        )

        let effective = try await graph.compute(tool: tool)
        XCTAssertEqual(effective.fromBuiltins, [.memoryAccess(scope: "translate.zh")])
        XCTAssertTrue(effective.undeclared.isEmpty)
    }

    // MARK: - 边界：filesystem 推 fileRead + fileWrite 双权限

    /// 验证 .filesystem 同时推 fileRead("**") 与 fileWrite("**")
    func test_compute_agentKind_builtinFilesystem_inferreBothReadAndWrite() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .agent(makeAgentTool(builtinCapabilities: [.filesystem])),
            permissions: [] // 故意不声明
        )

        let effective = try await graph.compute(tool: tool)

        XCTAssertTrue(effective.fromBuiltins.contains(.fileRead(path: "**")))
        XCTAssertTrue(effective.fromBuiltins.contains(.fileWrite(path: "**")))
        XCTAssertEqual(effective.fromBuiltins.count, 2)
        XCTAssertEqual(effective.undeclared.count, 2)
    }

    // MARK: - 边界：.empty 静态字段

    func test_effectivePermissions_empty_isAllEmpty() {
        let empty = EffectivePermissions.empty
        XCTAssertTrue(empty.declared.isEmpty)
        XCTAssertTrue(empty.fromContexts.isEmpty)
        XCTAssertTrue(empty.fromSideEffects.isEmpty)
        XCTAssertTrue(empty.fromMCP.isEmpty)
        XCTAssertTrue(empty.fromBuiltins.isEmpty)
        XCTAssertTrue(empty.union.isEmpty)
        XCTAssertTrue(empty.undeclared.isEmpty)
    }

    // MARK: - 边界：declared 非空但 union 空 → undeclared 应空（声明多于实际不算漏报）

    func test_compute_declaredExceedsEffective_undeclaredEmpty() async throws {
        let graph = PermissionGraph(providerRegistry: makeDefaultRegistry())
        let tool = makeTool(
            kind: .prompt(makePromptTool()),
            permissions: [.fileRead(path: "~/extra.md")] // 声明了但实际不用
        )

        let effective = try await graph.compute(tool: tool)
        // declared 非空但 union 空，undeclared = union - declared = 空
        XCTAssertEqual(effective.declared.count, 1)
        XCTAssertTrue(effective.union.isEmpty)
        XCTAssertTrue(effective.undeclared.isEmpty)
    }
}
