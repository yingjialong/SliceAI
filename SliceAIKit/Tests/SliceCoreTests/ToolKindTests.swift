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

    func test_pipelineStep_goldenJSON_tool_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let step = PipelineStep.tool(toolRef: "summarize", input: "{{selection}}")
        let json = try XCTUnwrap(String(data: try enc.encode(step), encoding: .utf8))
        XCTAssertEqual(json, #"{"tool":{"input":"{{selection}}","toolRef":"summarize"}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_pipelineStep_goldenJSON_prompt_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let inline = PromptTool(
            systemPrompt: nil, userPrompt: "u",
            contexts: [],
            provider: .fixed(providerId: "p", modelId: nil),
            temperature: nil, maxTokens: nil, variables: [:]
        )
        let step = PipelineStep.prompt(inline: inline, input: "i")
        let json = try XCTUnwrap(String(data: try enc.encode(step), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"prompt":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""input":"i""#))
        XCTAssertTrue(json.contains(#""inline":{"#))
        XCTAssertTrue(json.contains(#""userPrompt":"u""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_pipelineStep_goldenJSON_transform_directTransformOp() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let step = PipelineStep.transform(.jq(".items[]"))
        let json = try XCTUnwrap(String(data: try enc.encode(step), encoding: .utf8))
        // transform case 直接嵌入 TransformOp，没有 Repr 包装
        XCTAssertEqual(json, #"{"transform":{"jq":".items[]"}}"#)
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

    func test_transformOp_goldenJSON_jsonPath_directString() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(TransformOp.jsonPath("$.items[*].name")), encoding: .utf8))
        XCTAssertEqual(json, #"{"jsonPath":"$.items[*].name"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_promptTool_goldenJSON_fullShape_variablesEmptyDict() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        // 锁定 PromptTool auto-synth 线上形状，尤其：
        // - nil 可选（systemPrompt / temperature / maxTokens）→ key 省略
        // - 空字典 variables → `"variables":{}`（非省略、非 null）
        let pt = PromptTool(
            systemPrompt: nil,
            userPrompt: "Polish: {{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai", modelId: nil),
            temperature: nil,
            maxTokens: nil,
            variables: [:]
        )
        let json = try XCTUnwrap(String(data: try enc.encode(pt), encoding: .utf8))
        XCTAssertTrue(json.contains(#""userPrompt":"Polish: {{selection}}""#))
        XCTAssertTrue(json.contains(#""contexts":[]"#))
        XCTAssertTrue(json.contains(#""provider":{"fixed":{"providerId":"openai"}}"#))
        // 空字典：必须存在、以 `{}` 形式出现
        XCTAssertTrue(json.contains(#""variables":{}"#))
        // nil 可选：key 必须省略（Foundation 默认行为）
        XCTAssertFalse(json.contains("\"systemPrompt\""))
        XCTAssertFalse(json.contains("\"temperature\""))
        XCTAssertFalse(json.contains("\"maxTokens\""))
    }

    // MARK: - Decoder negative tests（canonical 单键 + 未知键拒绝；Task 3/8/10/11/13 同款纪律）

    // ToolKind

    func test_toolKind_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ToolKind.self, from: data))
    }

    func test_toolKind_decode_unknownKey_throws() {
        let data = Data(#"{"bogus":{}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ToolKind.self, from: data))
    }

    func test_toolKind_decode_twoKeys_throws() {
        // 两个合法 kind key 同时出现 → 单键 guard 必须拒绝
        let data = Data(#"{"prompt":{"userPrompt":"u","contexts":[],"provider":{"fixed":{"providerId":"p"}},"variables":{}},"agent":{"initialUserPrompt":"x","contexts":[],"provider":{"fixed":{"providerId":"p"}},"mcpAllowlist":[],"builtinCapabilities":[],"maxSteps":1,"stopCondition":"finalAnswerProvided"}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ToolKind.self, from: data))
    }

    // PipelineStep

    func test_pipelineStep_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PipelineStep.self, from: data))
    }

    func test_pipelineStep_decode_unknownKey_throws() {
        let data = Data(#"{"bogus":{}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PipelineStep.self, from: data))
    }

    func test_pipelineStep_decode_twoKeys_throws() {
        let data = Data(#"{"tool":{"toolRef":"a","input":"x"},"transform":{"jq":"."}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(PipelineStep.self, from: data))
    }

    // TransformOp

    func test_transformOp_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(TransformOp.self, from: data))
    }

    func test_transformOp_decode_unknownKey_throws() {
        let data = Data(#"{"bogus":"x"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(TransformOp.self, from: data))
    }

    func test_transformOp_decode_twoKeys_throws() {
        let data = Data(#"{"jq":".","jsonPath":"$.a"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(TransformOp.self, from: data))
    }
}
