import XCTest
@testable import SliceCore

final class ConfigurationTests: XCTestCase {

    func test_configuration_currentSchemaVersion_is2() {
        XCTAssertEqual(Configuration.currentSchemaVersion, 2)
    }

    func test_defaultConfiguration_usesSchemaVersion2() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.schemaVersion, 2)
    }

    func test_defaultConfiguration_hasFiveFirstPartyToolsAndLegacyPromptsRemainPrompt() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.tools.count, 5)

        let legacyPromptToolIds = Set(["translate", "polish", "summarize", "explain"])
        for tool in cfg.tools where legacyPromptToolIds.contains(tool.id) {
            XCTAssertEqual(tool.provenance, .firstParty)
            guard case .prompt = tool.kind else {
                XCTFail("tool \(tool.id) is not .prompt kind"); continue
            }
        }
    }

    /// 默认配置应内置 Web Search Summarize Agent，给 Phase 1 Agent 功能提供可试用入口。
    func test_defaultConfiguration_containsWebSearchSummarizeAgentTool() throws {
        let cfg = DefaultConfiguration.initial()

        let tool = try XCTUnwrap(cfg.tools.first { $0.id == "web-search-summarize" })

        XCTAssertEqual(tool.name, "Web Search Summarize")
        XCTAssertEqual(tool.icon, "magnifyingglass")
        XCTAssertEqual(tool.description, "用 Brave Search MCP 搜索并总结选中内容")
        XCTAssertEqual(tool.provenance, .firstParty)
        XCTAssertEqual(tool.displayMode, .window)
        XCTAssertNil(tool.outputBinding)
        guard case .agent(let agent) = tool.kind else {
            XCTFail("web-search-summarize should be an agent tool")
            return
        }
        XCTAssertEqual(agent.initialUserPrompt, "Search and summarize information related to:\n\n{{selection}}")
        XCTAssertEqual(agent.contexts, [
            ContextRequest(
                key: .init(rawValue: "selection"),
                provider: "selection",
                args: [:],
                cachePolicy: .none,
                requiredness: .required
            )
        ])
        XCTAssertEqual(agent.mcpAllowlist, [
            MCPToolRef(server: "brave-search", tool: "brave_web_search")
        ])
        XCTAssertEqual(agent.maxSteps, 6)
        XCTAssertEqual(agent.stopCondition, .finalAnswerProvided)
    }

    /// Web Search Summarize 必须声明 Brave Search MCP 权限，否则 PermissionGraph 会 fail-closed。
    func test_webSearchSummarize_declaresMCPPermission() throws {
        let cfg = DefaultConfiguration.initial()

        let tool = try XCTUnwrap(cfg.tools.first { $0.id == "web-search-summarize" })

        XCTAssertEqual(tool.permissions, [
            .mcp(server: "brave-search", tools: ["brave_web_search"])
        ])
    }

    /// Web Search Summarize 必须要求 tool-calling provider，避免被普通 prompt-only provider 执行。
    func test_webSearchSummarize_requiresToolCallingProviderCapability() throws {
        let cfg = DefaultConfiguration.initial()
        let tool = try XCTUnwrap(cfg.tools.first { $0.id == "web-search-summarize" })

        guard case .agent(let agent) = tool.kind else {
            XCTFail("web-search-summarize should be an agent tool")
            return
        }
        guard case .capability(let requires, let prefer) = agent.provider else {
            XCTFail("web-search-summarize should use capability provider selection")
            return
        }
        XCTAssertEqual(requires, [.toolCalling])
        XCTAssertEqual(prefer, [])
    }

    func test_defaultConfiguration_providerIsOpenAICompatible() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.providers.count, 1)
        XCTAssertEqual(cfg.providers[0].kind, .openAICompatible)
    }

    /// 默认 OpenAI provider 需声明 toolCalling，确保内置 Agent tool 在全新配置中可路由。
    func test_defaultConfiguration_providerSupportsToolCallingForBuiltInAgentTool() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertTrue(cfg.providers[0].capabilities.contains(.toolCalling))
    }

    func test_configuration_roundtrip() throws {
        let cfg = DefaultConfiguration.initial()
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        XCTAssertEqual(cfg, decoded)
    }

    /// 配置应能集中保存每个工具的全局热键映射，供运行时按 tool id 直接注册。
    func test_configurationStoresPerToolHotkeys() throws {
        var cfg = DefaultConfiguration.initial()
        cfg.hotkeys.tools = [
            "translate": "cmd+shift+1",
            "web-search-summarize": "cmd+shift+w"
        ]

        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)

        XCTAssertEqual(decoded.hotkeys.tools["translate"], "cmd+shift+1")
        XCTAssertEqual(decoded.hotkeys.tools["web-search-summarize"], "cmd+shift+w")
    }

    /// 旧版 config-v2 只包含命令面板热键时，工具热键映射必须默认空字典。
    func test_hotkeyBindingsDecodingDefaultsPerToolHotkeysToEmpty() throws {
        let json = #"{"toggleCommandPalette":"option+space"}"#.data(using: .utf8)!

        let bindings = try JSONDecoder().decode(HotkeyBindings.self, from: json)

        XCTAssertEqual(bindings.toggleCommandPalette, "option+space")
        XCTAssertEqual(bindings.tools, [:])
    }
}
