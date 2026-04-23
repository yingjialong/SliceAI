import XCTest
@testable import SliceCore

final class ConfigMigratorV1ToV2Tests: XCTestCase {

    private func loadFixture(_ name: String) throws -> Data {
        let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")
        guard let url else {
            XCTFail("fixture \(name).json not found")
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }

    // MARK: - Minimal v1

    func test_migrate_minimal_preservesProviderId() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.schemaVersion, 2)
        XCTAssertEqual(v2.providers.count, 1)
        XCTAssertEqual(v2.providers[0].id, "openai-official")
        XCTAssertEqual(v2.providers[0].kind, .openAICompatible)
        XCTAssertEqual(v2.providers[0].capabilities, [])
    }

    func test_migrate_minimal_toolToPromptKind() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.tools.count, 1)
        let tool = v2.tools[0]
        XCTAssertEqual(tool.id, "translate")
        XCTAssertEqual(tool.provenance, .firstParty)

        guard case .prompt(let pt) = tool.kind else {
            XCTFail("expected .prompt kind"); return
        }
        XCTAssertEqual(pt.systemPrompt, "You are a translator.")
        XCTAssertEqual(pt.userPrompt, "Translate to {{language}}:\n\n{{selection}}")
        XCTAssertEqual(pt.temperature, 0.3)
        XCTAssertEqual(pt.variables["language"], "Simplified Chinese")
        XCTAssertEqual(pt.provider, .fixed(providerId: "openai-official", modelId: nil))
    }

    func test_migrate_minimal_preservesHotkeys_andTriggers_defaults() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.hotkeys.toggleCommandPalette, "option+space")
        XCTAssertEqual(v2.triggers.floatingToolbarEnabled, true)
        XCTAssertEqual(v2.triggers.commandPaletteEnabled, true)
        XCTAssertEqual(v2.triggers.minimumSelectionLength, 1)
        XCTAssertEqual(v2.triggers.triggerDelayMs, 150)
        // v1 fixture 未提供这些字段 → 用 DefaultConfiguration 默认
        XCTAssertEqual(v2.triggers.floatingToolbarMaxTools, 6)
        XCTAssertEqual(v2.triggers.floatingToolbarSize, .compact)
        XCTAssertEqual(v2.triggers.floatingToolbarAutoDismissSeconds, 5)
    }

    func test_migrate_minimal_appearanceDefaultsAuto() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.appearance, .auto)
    }

    // MARK: - Full v1

    func test_migrate_full_preservesAllFields() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.schemaVersion, 2)
        XCTAssertEqual(v2.appearance, .dark)
        XCTAssertEqual(v2.providers.count, 2)
        XCTAssertEqual(v2.tools.count, 2)
        XCTAssertEqual(v2.triggers.triggerDelayMs, 200)
        XCTAssertEqual(v2.triggers.floatingToolbarMaxTools, 8)
        XCTAssertEqual(v2.triggers.floatingToolbarSize, .regular)
        XCTAssertEqual(v2.triggers.floatingToolbarAutoDismissSeconds, 0)
        XCTAssertTrue(v2.telemetry.enabled)
        XCTAssertEqual(v2.appBlocklist.count, 2)
        XCTAssertEqual(v2.hotkeys.toggleCommandPalette, "option+shift+space")
    }

    func test_migrate_full_preservesLabelStyle() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.tools[0].labelStyle, .iconAndName)
        XCTAssertEqual(v2.tools[1].labelStyle, .icon)
    }

    func test_migrate_full_nullFieldsPreserved() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)

        guard case .prompt(let polishPT) = v2.tools[1].kind else { XCTFail(); return }
        XCTAssertNil(polishPT.systemPrompt)
        XCTAssertNil(polishPT.temperature)
        XCTAssertEqual(polishPT.provider, .fixed(providerId: "deepseek", modelId: "deepseek-reasoner"))
    }

    func test_migrate_allTools_provenanceIsFirstParty() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)
        for tool in v2.tools {
            XCTAssertEqual(tool.provenance, .firstParty)
        }
    }

    func test_migrate_unknownPresentationModeFallsBackToWindow() throws {
        // 手工构造一个 v1 结构含非标 displayMode
        let badJSON = #"""
        {
          "schemaVersion": 1, "providers": [], "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {"floatingToolbarEnabled": true, "commandPaletteEnabled": true, "minimumSelectionLength": 1, "triggerDelayMs": 150},
          "telemetry": {"enabled": false}, "appBlocklist": [],
          "tools": [{
            "id": "t", "name": "n", "icon": "i",
            "systemPrompt": null, "userPrompt": "u",
            "providerId": "p", "modelId": null, "temperature": null,
            "displayMode": "nonexistent", "variables": {}
          }]
        }
        """#.data(using: .utf8)!
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: badJSON)
        let v2 = ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.tools[0].displayMode, .window)
    }
}
