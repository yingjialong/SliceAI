import Capabilities
import SliceCore
import XCTest
@testable import Orchestration

/// Phase 2 Skill Registry 真实文件系统 E2E 兼容性验证。
///
/// 覆盖链路：
/// 临时本地 skill root -> `SkillDirectoryScanner` -> `LocalSkillRegistry` ->
/// Agent Tool skills 绑定 -> provider-visible `sliceai_load_skill` pseudo-tool ->
/// AgentExecutor 渐进式加载完整 `SKILL.md`。
final class AgentExecutorSkillE2ETests: XCTestCase {

    /// 验证 3 个 Claude / Codex 风格本地 skill 能贯通 registry 与 AgentExecutor。
    func test_realLocalClaudeAndCodexStyleSkillsLoadThroughAgentExecutor() async throws {
        let root = try makeTempRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        try writeRealisticSkillFixtures(at: root)
        let settings = SkillSettings(
            sources: [
                SkillSource(
                    id: "project-skills",
                    displayName: "Project Skills",
                    rootPath: root.path,
                    isEnabled: true,
                    order: 0
                )
            ],
            overrides: ["claude-research": .on]
        )
        let registry = LocalSkillRegistry(settingsProvider: { settings })

        let snapshot = try await registry.snapshot()
        let enabledSkills = snapshot.skills.filter {
            $0.state == .enabled && $0.source.sourceId == "project-skills"
        }

        XCTAssertEqual(Set(enabledSkills.map(\.canonicalName)), [
            "prose-polisher",
            "claude-research",
            "codex-review",
        ])
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
        XCTAssertEqual(
            skill(named: "prose-polisher", in: enabledSkills).manifest.allowedTools,
            ["Read", "Grep", "Glob"]
        )
        XCTAssertTrue(skill(named: "claude-research", in: enabledSkills).manifest.disableModelInvocation)
        XCTAssertEqual(skill(named: "claude-research", in: enabledSkills).state, .enabled)
        XCTAssertEqual(skill(named: "codex-review", in: enabledSkills).manifest.userInvocable, true)

        let mcpClient = MockMCPClient()
        let llm = MockToolCallingLLMProvider(turns: [
            toolCallTurn(id: "load-prose", name: "prose-polisher"),
            resourceToolCallTurn(
                id: "load-style",
                name: "prose-polisher",
                path: "references/style.md"
            ),
            toolCallTurn(id: "load-claude", name: "claude-research"),
            finalAnswerTurn("Skills loaded")
        ])
        let executor = AgentExecutor(
            providerResolver: MockProviderResolver(),
            mcpClient: mcpClient,
            permissionBroker: MockPermissionBroker(),
            keychain: MockKeychain(["openai-stub": "fake-key"]),
            llmProviderFactory: MockLLMProviderFactory(provider: llm),
            mcpDescriptors: { [] },
            toolCallTimeoutNanoseconds: 1_000_000_000,
            skillRegistry: registry
        )
        let agent = makeAgent(
            skills: enabledSkills
                .sorted { $0.canonicalName < $1.canonicalName }
                .map { SkillReference(id: $0.id, pinVersion: nil) }
        )

        let events = await collectEvents(from: await executor.run(
            tool: makeTool(agent: agent),
            agent: agent,
            resolved: makeResolvedContext(),
            provider: MockProvider.openAIStub()
        ))

        let initialRequest = try XCTUnwrap(llm.capturedToolRequests.first)
        XCTAssertTrue(initialRequest.tools.contains { $0.name == AgentBuiltInTool.loadSkillName })
        let initialPrompt = initialRequest.messages.compactMap(\.content).joined(separator: "\n")
        XCTAssertTrue(initialPrompt.contains("Available SliceAI skills for this tool:"))
        XCTAssertTrue(initialPrompt.contains("name: prose-polisher"))
        XCTAssertTrue(initialPrompt.contains("name: claude-research"))
        XCTAssertTrue(initialPrompt.contains("name: codex-review"))
        XCTAssertTrue(initialPrompt.contains("references/style.md"))
        XCTAssertTrue(initialPrompt.contains("assets/template.md"))
        XCTAssertFalse(initialPrompt.contains("scripts/check.sh"))

        XCTAssertTrue(events.contains { event in
            if case .toolCallProposed(_, AgentBuiltInTool.loadSkillRef, _) = event { return true }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .toolCallProposed(_, AgentBuiltInTool.loadSkillResourceRef, _) = event { return true }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .toolCallResult(_, let summary) = event { return summary.contains("prose-polisher") }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .toolCallResult(_, let summary) = event { return summary.contains("claude-research") }
            return false
        })
        XCTAssertTrue(events.contains { event in
            if case .llmChunk(let delta) = event { return delta == "Skills loaded" }
            return false
        })

        let followUpMessages = llm.capturedToolRequests
            .dropFirst()
            .flatMap(\.messages)
            .compactMap(\.content)
            .joined(separator: "\n")
        XCTAssertTrue(followUpMessages.contains("Loaded SliceAI skill: prose-polisher"))
        XCTAssertTrue(followUpMessages.contains("Loaded SliceAI skill: claude-research"))
        XCTAssertTrue(followUpMessages.contains("Use crisp before/after rewrite bullets."))
        XCTAssertTrue(followUpMessages.contains("Collect evidence before summarizing."))
        XCTAssertTrue(followUpMessages.contains("REFERENCE_SENTINEL_SHOULD_LOAD"))
        XCTAssertFalse(followUpMessages.contains("SCRIPT_SENTINEL_SHOULD_NOT_LOAD"))

        let mcpCallCount = await mcpClient.callCount
        XCTAssertEqual(mcpCallCount, 0)
    }

    /// 构造只绑定 skills、不开放 MCP 的 AgentTool。
    /// - Parameter skills: Agent Tool 绑定的 skill 引用。
    /// - Returns: 用于 E2E 的 AgentTool。
    private func makeAgent(skills: [SkillReference]) -> AgentTool {
        AgentTool(
            systemPrompt: "You are a SliceAI skill validation agent.",
            initialUserPrompt: "Use bound skills for {{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai-stub", modelId: nil),
            skills: skills,
            mcpAllowlist: [],
            builtinCapabilities: [],
            maxSteps: 4,
            stopCondition: .finalAnswerProvided,
            toolCallPolicy: nil
        )
    }

    /// 构造包裹 AgentTool 的顶层 Tool。
    /// - Parameter agent: AgentTool 配置。
    /// - Returns: 用于 AgentExecutor 的 Tool。
    private func makeTool(agent: AgentTool) -> Tool {
        Tool(
            id: "phase2.skill.e2e",
            name: "Skill E2E",
            icon: "S",
            description: nil,
            kind: .agent(agent),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造固定的执行上下文。
    /// - Returns: AgentExecutor 所需的 resolved context。
    private func makeResolvedContext() -> ResolvedExecutionContext {
        let seed = ExecutionSeed(
            invocationId: UUID(),
            selection: SelectionSnapshot(
                text: "The draft needs clearer research and review.",
                source: .accessibility,
                length: 43,
                language: "en",
                contentType: .prose
            ),
            frontApp: AppSnapshot(
                bundleId: "com.sliceai.tests",
                name: "SliceAI Tests",
                url: nil,
                windowTitle: "Skill E2E"
            ),
            screenAnchor: .zero,
            timestamp: Date(),
            triggerSource: .commandPalette,
            isDryRun: false
        )
        return ResolvedExecutionContext(
            seed: seed,
            contexts: ContextBag(values: [:]),
            resolvedAt: Date(),
            failures: [:]
        )
    }

    /// 收集 AgentExecutor 事件，测试中不期望 stream throw。
    /// - Parameter stream: AgentExecutor 返回的事件流。
    /// - Returns: 全部事件。
    private func collectEvents(
        from stream: AsyncThrowingStream<ExecutionEvent, any Error>
    ) async -> [ExecutionEvent] {
        var events: [ExecutionEvent] = []
        do {
            for try await event in stream {
                events.append(event)
            }
        } catch {
            XCTFail("AgentExecutor stream should not throw: \(error)")
        }
        return events
    }

    /// 构造一次 `sliceai_load_skill` tool-call turn。
    /// - Parameters:
    ///   - id: provider tool call id。
    ///   - name: skill canonical name。
    /// - Returns: provider stream events。
    private func toolCallTurn(id: String, name: String) -> [ChatStreamEvent] {
        [
            .toolCallDelta(ChatToolCallDelta(
                index: 0,
                id: id,
                name: AgentBuiltInTool.loadSkillName,
                argumentsDelta: "{\"name\":\"\(name)\"}"
            )),
            .finished(.toolCalls)
        ]
    }

    /// 构造一次 `sliceai_load_skill_resource` tool-call turn。
    /// - Parameters:
    ///   - id: provider tool call id。
    ///   - name: skill canonical name。
    ///   - path: supporting file 相对路径。
    /// - Returns: provider stream events。
    private func resourceToolCallTurn(id: String, name: String, path: String) -> [ChatStreamEvent] {
        [
            .toolCallDelta(ChatToolCallDelta(
                index: 0,
                id: id,
                name: AgentBuiltInTool.loadSkillResourceName,
                argumentsDelta: "{\"name\":\"\(name)\",\"path\":\"\(path)\"}"
            )),
            .finished(.toolCalls)
        ]
    }

    /// 构造最终答案 turn。
    /// - Parameter text: 最终答案文本。
    /// - Returns: provider stream events。
    private func finalAnswerTurn(_ text: String) -> [ChatStreamEvent] {
        [.textDelta(text), .finished(.stop)]
    }

    /// 从 skills 中按名称取出 skill。
    /// - Parameters:
    ///   - name: canonical name。
    ///   - skills: registry 返回的 skills。
    /// - Returns: 匹配的 Skill；缺失时让测试失败。
    private func skill(named name: String, in skills: [Skill]) -> Skill {
        guard let skill = skills.first(where: { $0.canonicalName == name }) else {
            XCTFail("missing skill \(name)")
            return skills[0]
        }
        return skill
    }

    /// 创建独立临时目录。
    /// - Returns: 新建的临时 root。
    private func makeTempRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("sliceai-skill-e2e-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// 写入 3 个真实 Claude / Codex 风格 skill fixture。
    /// - Parameter root: skill source root。
    private func writeRealisticSkillFixtures(at root: URL) throws {
        try writeSkill(
            root.appendingPathComponent("skills/prose-polisher/SKILL.md"),
            frontmatter: """
            name: prose-polisher
            description: Use when rewriting prose for clarity, tone, and concise before/after suggestions.
            allowed-tools:
              - Read
              - Grep
              - Glob
            user-invocable: true
            """,
            body: """
            # Prose Polisher

            Use crisp before/after rewrite bullets.
            Do not invent facts.
            """
        )
        try writeText(
            "REFERENCE_SENTINEL_SHOULD_LOAD",
            to: root.appendingPathComponent("skills/prose-polisher/references/style.md")
        )
        try writeText(
            "Template asset.",
            to: root.appendingPathComponent("skills/prose-polisher/assets/template.md")
        )
        try writeText(
            "SCRIPT_SENTINEL_SHOULD_NOT_LOAD",
            to: root.appendingPathComponent("skills/prose-polisher/scripts/check.sh")
        )
        try writeText(
            """
            interface:
              display_name: "Prose Polisher"
            policy:
              allow_implicit_invocation: true
            """,
            to: root.appendingPathComponent("skills/prose-polisher/agents/openai.yaml")
        )

        try writeSkill(
            root.appendingPathComponent(".claude/skills/claude-research/SKILL.md"),
            frontmatter: """
            name: claude-research
            description: Use when evaluating claims and collecting evidence before summarizing.
            disable-model-invocation: true
            allowed-tools: Read, Grep, Glob
            user-invocable: false
            """,
            body: """
            # Claude Research

            Collect evidence before summarizing.
            Separate direct evidence from inference.
            """
        )
        try writeText(
            "REFERENCE_SENTINEL_SHOULD_NOT_LOAD",
            to: root.appendingPathComponent(".claude/skills/claude-research/references/checklist.md")
        )

        try writeSkill(
            root.appendingPathComponent(".agents/skills/codex-review/SKILL.md"),
            frontmatter: """
            name: codex-review
            description: Use when reviewing code changes for correctness, regressions, and missing tests.
            allowed-tools:
              - Read
            user-invocable: true
            """,
            body: """
            # Codex Review

            Start with concrete findings.
            Include file and line references when available.
            """
        )
        try writeText(
            """
            interface:
              display_name: "Codex Review"
            """,
            to: root.appendingPathComponent(".agents/skills/codex-review/agents/openai.yaml")
        )
    }

    /// 写入一个 `SKILL.md` 文件。
    /// - Parameters:
    ///   - url: `SKILL.md` 目标路径。
    ///   - frontmatter: YAML frontmatter 内容，不含 `---` 分隔符。
    ///   - body: markdown 指令正文。
    private func writeSkill(_ url: URL, frontmatter: String, body: String) throws {
        try writeText(
            """
            ---
            \(frontmatter)
            ---
            \(body)
            """,
            to: url
        )
    }

    /// 写入文本文件并自动创建父目录。
    /// - Parameters:
    ///   - text: 文件内容。
    ///   - url: 目标路径。
    private func writeText(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
