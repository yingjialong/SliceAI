import XCTest
@testable import SliceCore

final class LegacyConfigV1Tests: XCTestCase {

    func test_decode_minimalV1Config() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "providers": [
            {
              "id": "openai-official",
              "name": "OpenAI",
              "baseURL": "https://api.openai.com/v1",
              "apiKeyRef": "keychain:openai-official",
              "defaultModel": "gpt-5"
            }
          ],
          "tools": [
            {
              "id": "translate", "name": "Translate", "icon": "🌐",
              "systemPrompt": "sys", "userPrompt": "u",
              "providerId": "openai-official", "modelId": null, "temperature": 0.3,
              "displayMode": "window", "variables": {"language": "zh"}
            }
          ],
          "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {
            "floatingToolbarEnabled": true,
            "commandPaletteEnabled": true,
            "minimumSelectionLength": 1,
            "triggerDelayMs": 150
          },
          "telemetry": {"enabled": false},
          "appBlocklist": []
        }
        """#.data(using: .utf8)!

        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: json)
        XCTAssertEqual(v1.schemaVersion, 1)
        XCTAssertEqual(v1.providers.count, 1)
        XCTAssertEqual(v1.tools.count, 1)
        XCTAssertEqual(v1.tools[0].systemPrompt, "sys")
        XCTAssertEqual(v1.tools[0].userPrompt, "u")
        XCTAssertEqual(v1.tools[0].variables["language"], "zh")
    }

    func test_decode_v1WithOptionalFields() throws {
        let json = #"""
        {
          "schemaVersion": 1,
          "providers": [],
          "tools": [],
          "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {
            "floatingToolbarEnabled": true,
            "commandPaletteEnabled": true,
            "minimumSelectionLength": 1,
            "triggerDelayMs": 150,
            "floatingToolbarMaxTools": 8,
            "floatingToolbarSize": "regular",
            "floatingToolbarAutoDismissSeconds": 10
          },
          "telemetry": {"enabled": true},
          "appBlocklist": ["com.example.secrets"],
          "appearance": "dark"
        }
        """#.data(using: .utf8)!

        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: json)
        XCTAssertEqual(v1.triggers.floatingToolbarMaxTools, 8)
        XCTAssertEqual(v1.triggers.floatingToolbarSize, "regular")
        XCTAssertEqual(v1.triggers.floatingToolbarAutoDismissSeconds, 10)
        XCTAssertTrue(v1.telemetry.enabled)
        XCTAssertEqual(v1.appBlocklist, ["com.example.secrets"])
        XCTAssertEqual(v1.appearance, "dark")
    }

    func test_decode_v1WithLabelStyle() throws {
        let json = #"""
        {
          "schemaVersion": 1, "providers": [], "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {"floatingToolbarEnabled": true, "commandPaletteEnabled": true, "minimumSelectionLength": 1, "triggerDelayMs": 150},
          "telemetry": {"enabled": false}, "appBlocklist": [],
          "tools": [{
            "id": "t", "name": "n", "icon": "i",
            "systemPrompt": null, "userPrompt": "u",
            "providerId": "p", "modelId": null, "temperature": null,
            "displayMode": "window", "variables": {}, "labelStyle": "iconAndName"
          }]
        }
        """#.data(using: .utf8)!
        let v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: json)
        XCTAssertEqual(v1.tools[0].labelStyle, "iconAndName")
    }
}
