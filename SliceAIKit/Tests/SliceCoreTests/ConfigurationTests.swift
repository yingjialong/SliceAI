import XCTest
@testable import SliceCore

final class ConfigurationTests: XCTestCase {
    func test_configuration_defaultDecoding() throws {
        let json = """
        {
          "schemaVersion": 1,
          "providers": [],
          "tools": [],
          "hotkeys": { "toggleCommandPalette": "option+space" },
          "triggers": {
            "floatingToolbarEnabled": true,
            "commandPaletteEnabled": true,
            "minimumSelectionLength": 1,
            "triggerDelayMs": 150
          },
          "telemetry": { "enabled": false },
          "appBlocklist": []
        }
        """.data(using: .utf8)!
        let cfg = try JSONDecoder().decode(Configuration.self, from: json)
        XCTAssertEqual(cfg.schemaVersion, 1)
        XCTAssertEqual(cfg.hotkeys.toggleCommandPalette, "option+space")
        XCTAssertEqual(cfg.triggers.triggerDelayMs, 150)
        XCTAssertFalse(cfg.telemetry.enabled)
    }
}
