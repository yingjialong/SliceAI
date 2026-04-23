import XCTest
@testable import SliceCore

final class ToolKindTests: XCTestCase {

    // MARK: - PromptTool

    func test_promptTool_codable_roundtrip() throws {
        let pt = PromptTool(
            systemPrompt: "You are an editor.",
            userPrompt: "Polish: {{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai", modelId: "gpt-5"),
            temperature: 0.4,
            maxTokens: 1000,
            variables: ["tone": "formal"]
        )
        let data = try JSONEncoder().encode(pt)
        let decoded = try JSONDecoder().decode(PromptTool.self, from: data)
        XCTAssertEqual(pt, decoded)
    }

    // MARK: - AgentTool

    func test_agentTool_codable_roundtrip() throws {
        let at = AgentTool(
            systemPrompt: "agent sys",
            initialUserPrompt: "{{selection}}",
            contexts: [],
            provider: .capability(requires: [.toolCalling], prefer: ["claude"]),
            skill: SkillReference(id: "english-tutor@1", pinVersion: nil),
            mcpAllowlist: [MCPToolRef(server: "anki", tool: "createNote")],
            builtinCapabilities: [.tts],
            maxSteps: 6,
            stopCondition: .finalAnswerProvided
        )
        let data = try JSONEncoder().encode(at)
        let decoded = try JSONDecoder().decode(AgentTool.self, from: data)
        XCTAssertEqual(at, decoded)
    }

    // MARK: - PipelineTool

    func test_pipelineTool_codable_roundtrip() throws {
        let pt = PipelineTool(
            steps: [
                .prompt(inline: PromptTool(
                    systemPrompt: nil, userPrompt: "Extract words: {{selection}}",
                    contexts: [],
                    provider: .fixed(providerId: "openai", modelId: nil),
                    temperature: nil, maxTokens: nil, variables: [:]
                ), input: "{{selection}}"),
                .mcp(ref: MCPToolRef(server: "anki", tool: "createNote"), args: ["deck": "English"])
            ],
            onStepFail: .abort
        )
        let data = try JSONEncoder().encode(pt)
        let decoded = try JSONDecoder().decode(PipelineTool.self, from: data)
        XCTAssertEqual(pt, decoded)
    }

    // MARK: - ToolKind dispatch

    func test_toolKind_prompt_codable() throws {
        let kind = ToolKind.prompt(PromptTool(
            systemPrompt: nil, userPrompt: "t",
            contexts: [], provider: .fixed(providerId: "p", modelId: nil),
            temperature: nil, maxTokens: nil, variables: [:]
        ))
        let data = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(ToolKind.self, from: data)
        XCTAssertEqual(kind, decoded)
    }

    func test_toolKind_agent_codable() throws {
        let kind = ToolKind.agent(AgentTool(
            systemPrompt: nil, initialUserPrompt: "t",
            contexts: [], provider: .fixed(providerId: "p", modelId: nil),
            skill: nil, mcpAllowlist: [], builtinCapabilities: [],
            maxSteps: 3, stopCondition: .finalAnswerProvided
        ))
        let data = try JSONEncoder().encode(kind)
        let decoded = try JSONDecoder().decode(ToolKind.self, from: data)
        XCTAssertEqual(kind, decoded)
    }

    // MARK: - StopCondition

    func test_stopCondition_allCases() {
        XCTAssertEqual(Set(StopCondition.allCases), [.finalAnswerProvided, .maxStepsReached, .noToolCall])
    }

    // MARK: - ToolMatcher

    func test_toolMatcher_codable_allFieldsNil() throws {
        let m = ToolMatcher(appAllowlist: nil, appDenylist: nil, contentTypes: nil, languageAllowlist: nil, minLength: nil, maxLength: nil, regex: nil)
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(ToolMatcher.self, from: data)
        XCTAssertEqual(m, decoded)
    }

    func test_toolMatcher_codable_fullFields() throws {
        let m = ToolMatcher(
            appAllowlist: ["com.apple.Safari"],
            appDenylist: nil,
            contentTypes: [.prose, .code],
            languageAllowlist: ["en"],
            minLength: 5,
            maxLength: 5000,
            regex: "^[A-Za-z]+$"
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(ToolMatcher.self, from: data)
        XCTAssertEqual(m, decoded)
    }

    // MARK: - ToolBudget

    func test_toolBudget_codable() throws {
        let b = ToolBudget(dailyUSD: 0.5, perCallUSD: 0.02)
        let data = try JSONEncoder().encode(b)
        let decoded = try JSONDecoder().decode(ToolBudget.self, from: data)
        XCTAssertEqual(b, decoded)
    }

    // MARK: - Golden JSON shape（模板 D；ToolKind / PipelineStep / TransformOp）

    func test_toolKind_goldenJSON_prompt_usesSingleKeyDiscriminator() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let kind = ToolKind.prompt(PromptTool(
            systemPrompt: nil, userPrompt: "u", contexts: [],
            provider: .fixed(providerId: "p", modelId: nil),
            temperature: nil, maxTokens: nil, variables: [:]
        ))
        let json = try XCTUnwrap(String(data: try enc.encode(kind), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"prompt":{"#), "got: \(json)")
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_toolKind_goldenJSON_agent_usesSingleKeyDiscriminator() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let kind = ToolKind.agent(AgentTool(
            systemPrompt: nil, initialUserPrompt: "x",
            contexts: [], provider: .fixed(providerId: "p", modelId: nil),
            skill: nil, mcpAllowlist: [], builtinCapabilities: [],
            maxSteps: 3, stopCondition: .finalAnswerProvided
        ))
        let json = try XCTUnwrap(String(data: try enc.encode(kind), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"agent":{"#), "got: \(json)")
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_pipelineStep_goldenJSON_mcp_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let step = PipelineStep.mcp(ref: MCPToolRef(server: "anki", tool: "createNote"), args: ["deck": "English"])
        let json = try XCTUnwrap(String(data: try enc.encode(step), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"mcp":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""server":"anki""#))
        XCTAssertTrue(json.contains(#""tool":"createNote""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_pipelineStep_goldenJSON_branch_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let step = PipelineStep.branch(condition: .isCode, onTrue: "a", onFalse: "b")
        let json = try XCTUnwrap(String(data: try enc.encode(step), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"branch":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""condition":{"isCode":{}}"#))
        XCTAssertTrue(json.contains(#""onFalse":"b""#))
        XCTAssertTrue(json.contains(#""onTrue":"a""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_transformOp_goldenJSON_jq_directString() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(TransformOp.jq(".items[]")), encoding: .utf8))
        XCTAssertEqual(json, #"{"jq":".items[]"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_transformOp_goldenJSON_regex_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(TransformOp.regex(pattern: "a", replacement: "b")), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"regex":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""pattern":"a""#))
        XCTAssertTrue(json.contains(#""replacement":"b""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }
}
