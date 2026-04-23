import XCTest
@testable import SliceCore

final class V2ToolTests: XCTestCase {

    // MARK: - v2 主路径：V2Tool 的三态 kind

    func test_v2tool_init_promptKind() {
        let tool = V2Tool(
            id: "translate",
            name: "Translate",
            icon: "🌐",
            description: "Translate",
            kind: .prompt(PromptTool(
                systemPrompt: "sys", userPrompt: "u",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
                temperature: 0.3, maxTokens: nil, variables: ["language": "zh"]
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
        if case .prompt(let p) = tool.kind {
            XCTAssertEqual(p.userPrompt, "u")
        } else {
            XCTFail("expected .prompt kind")
        }
        XCTAssertEqual(tool.provenance, .firstParty)
    }

    // MARK: - 三态 kind 分别构造与 round-trip

    func test_v2tool_init_agentKind() {
        let tool = V2Tool(
            id: "grammar-tutor", name: "Grammar Tutor", icon: "📝", description: nil,
            kind: .agent(AgentTool(
                systemPrompt: "agentSys", initialUserPrompt: "{{selection}}",
                contexts: [],
                provider: .capability(requires: [.toolCalling], prefer: ["claude"]),
                skill: nil, mcpAllowlist: [], builtinCapabilities: [],
                maxSteps: 6, stopCondition: .finalAnswerProvided
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        if case .agent(let a) = tool.kind {
            XCTAssertEqual(a.maxSteps, 6)
        } else {
            XCTFail("expected .agent")
        }
    }

    func test_v2tool_codable_roundtrip_promptKind() throws {
        let tool = V2Tool(
            id: "t", name: "n", icon: "i", description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: nil, userPrompt: "u", contexts: [],
                provider: .fixed(providerId: "p", modelId: nil),
                temperature: 0.3, maxTokens: nil, variables: [:]
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        let data = try JSONEncoder().encode(tool)
        let decoded = try JSONDecoder().decode(V2Tool.self, from: data)
        XCTAssertEqual(tool, decoded)
    }

    func test_v2tool_codable_roundtrip_agentKind_preservesKind() throws {
        let original = V2Tool(
            id: "t", name: "n", icon: "i", description: nil,
            kind: .agent(AgentTool(
                systemPrompt: nil, initialUserPrompt: "x",
                contexts: [],
                provider: .fixed(providerId: "p", modelId: nil),
                skill: nil, mcpAllowlist: [], builtinCapabilities: [],
                maxSteps: 3, stopCondition: .finalAnswerProvided
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(V2Tool.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_v2tool_codable_roundtrip_pipelineKind_preservesKind() throws {
        let original = V2Tool(
            id: "t", name: "n", icon: "i", description: nil,
            kind: .pipeline(PipelineTool(
                steps: [
                    .prompt(inline: PromptTool(
                        systemPrompt: nil, userPrompt: "u", contexts: [],
                        provider: .fixed(providerId: "p", modelId: nil),
                        temperature: nil, maxTokens: nil, variables: [:]
                    ), input: "{{selection}}"),
                    .mcp(ref: MCPToolRef(server: "s", tool: "x"), args: [:])
                ],
                onStepFail: .abort
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(V2Tool.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - Golden JSON shape（锁定 canonical schema，避免 Swift 自动合成 _0 等实现细节泄漏）

    func test_v2tool_goldenJSON_promptKind_usesKindDiscriminator() throws {
        let tool = V2Tool(
            id: "t", name: "n", icon: "🌐", description: "d",
            kind: .prompt(PromptTool(
                systemPrompt: nil, userPrompt: "u", contexts: [],
                provider: .fixed(providerId: "p", modelId: nil),
                temperature: nil, maxTokens: nil, variables: [:]
            )),
            visibleWhen: nil, displayMode: .window, outputBinding: nil,
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        let data = try enc.encode(tool)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))

        // 锁定 canonical shape：kind 的 discriminator + payload 结构可人工可读
        XCTAssertTrue(json.contains("\"kind\":{\"prompt\":{"), "kind should use named case discriminator, got: \(json)")
        // 不允许 Swift 合成的 "_0" 泄漏
        XCTAssertFalse(json.contains("\"_0\""), "canonical JSON must not contain synthesized _0; got: \(json)")
        // Provenance 也是 discriminator 形式
        XCTAssertTrue(json.contains("\"provenance\":\"firstParty\"") || json.contains("\"provenance\":{\"firstParty\""), "provenance unexpected shape")
        // 锁定顶层字段名（防止静默 rename）
        XCTAssertTrue(json.contains("\"id\":\"t\""), "id field missing/renamed, got: \(json)")
        XCTAssertTrue(json.contains("\"displayMode\":\"window\""), "displayMode field missing/renamed, got: \(json)")
        XCTAssertTrue(json.contains("\"labelStyle\":\"icon\""), "labelStyle field missing/renamed, got: \(json)")
    }

    // MARK: - Decoder negative tests（V2Tool auto-synth 必要字段缺失应拒绝）

    func test_v2tool_decode_missingKind_throws() {
        // 缺少必要字段 kind → auto-synth decoder 必须抛错
        let json = #"""
        {"id":"t","name":"n","icon":"i","displayMode":"window","permissions":[],"provenance":{"firstParty":{}},"labelStyle":"icon","tags":[]}
        """#
        let data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(V2Tool.self, from: data))
    }

    func test_v2tool_decode_missingProvenance_throws() {
        // 缺少 provenance（v2 canonical 强制字段）→ 必须抛错
        let json = #"""
        {"id":"t","name":"n","icon":"i","kind":{"prompt":{"userPrompt":"u","contexts":[],"provider":{"fixed":{"providerId":"p"}},"variables":{}}},"displayMode":"window","permissions":[],"labelStyle":"icon","tags":[]}
        """#
        let data = Data(json.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(V2Tool.self, from: data))
    }
}
