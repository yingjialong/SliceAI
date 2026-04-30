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
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.schemaVersion, 2)
        XCTAssertEqual(v2.providers.count, 1)
        XCTAssertEqual(v2.providers[0].id, "openai-official")
        XCTAssertEqual(v2.providers[0].kind, .openAICompatible)
        XCTAssertEqual(v2.providers[0].capabilities, [])
    }

    func test_migrate_minimal_toolToPromptKind() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)

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
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)

        XCTAssertEqual(v2.hotkeys.toggleCommandPalette, "option+space")
        XCTAssertEqual(v2.triggers.floatingToolbarEnabled, true)
        XCTAssertEqual(v2.triggers.commandPaletteEnabled, true)
        XCTAssertEqual(v2.triggers.minimumSelectionLength, 1)
        XCTAssertEqual(v2.triggers.triggerDelayMs, 150)
        // v1 fixture 未提供这些字段 → 用 v2 默认值补齐
        XCTAssertEqual(v2.triggers.floatingToolbarMaxTools, 6)
        XCTAssertEqual(v2.triggers.floatingToolbarSize, .compact)
        XCTAssertEqual(v2.triggers.floatingToolbarAutoDismissSeconds, 5)
    }

    func test_migrate_minimal_appearanceDefaultsAuto() throws {
        let data = try loadFixture("config-v1-minimal")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.appearance, .auto)
    }

    // MARK: - Full v1

    func test_migrate_full_preservesAllFields() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)

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
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.tools[0].labelStyle, .iconAndName)
        XCTAssertEqual(v2.tools[1].labelStyle, .icon)
    }

    func test_migrate_full_nullFieldsPreserved() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)

        guard case .prompt(let polishPT) = v2.tools[1].kind else { XCTFail(); return }
        XCTAssertNil(polishPT.systemPrompt)
        XCTAssertNil(polishPT.temperature)
        XCTAssertEqual(polishPT.provider, .fixed(providerId: "deepseek", modelId: "deepseek-reasoner"))
    }

    func test_migrate_allTools_provenanceIsFirstParty() throws {
        let data = try loadFixture("config-v1-full")
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)
        for tool in v2.tools {
            XCTAssertEqual(tool.provenance, .firstParty)
        }
    }

    // MARK: - schemaVersion 校验（第八轮 P2-3 修复）
    //
    // 背景：`LegacyConfigV1` 结构有 `schemaVersion: Int` 字段但历史 migrator 从未校验。
    // 如果用户手改 config.json 把 schemaVersion 改成 2（或更新版本）而其他字段碰巧
    // 能通过 LegacyConfigV1.Decodable，migrator 仍然会盲目把它当 v1 迁移——字段含义错乱，
    // v2 配置被错误生成且覆盖（ConfigurationStore.load 会接着写 v2 文件）。
    // 本组测试锁定"非 v1 schemaVersion → throw，拒绝盲目迁移"的不变量。

    /// schemaVersion 不等于 1 时 migrate() 必须 throw，避免把未来版本/非 v1 文件当 v1 处理
    func test_migrate_throwsForUnknownSchemaVersion() throws {
        // 手工构造：schemaVersion=2 但其他字段仍符合 v1 shape
        // 这里模拟"用户误把 v2 文件存成 config.json"的场景
        let badJSON = #"""
        {
          "schemaVersion": 2,
          "providers": [],
          "tools": [],
          "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {"floatingToolbarEnabled": true, "commandPaletteEnabled": true, "minimumSelectionLength": 1, "triggerDelayMs": 150},
          "telemetry": {"enabled": false},
          "appBlocklist": []
        }
        """#.data(using: .utf8)!
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: badJSON)

        XCTAssertThrowsError(try ConfigMigratorV1ToV2.migrate(v1)) { error in
            guard case SliceError.configuration(.schemaVersionTooNew(let v)) = error else {
                XCTFail("expected .schemaVersionTooNew, got \(error)")
                return
            }
            XCTAssertEqual(v, 2)
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
        let v2 = try ConfigMigratorV1ToV2.migrate(v1)
        XCTAssertEqual(v2.tools[0].displayMode, .window)
    }
}
