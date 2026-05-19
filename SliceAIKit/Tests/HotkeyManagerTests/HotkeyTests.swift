import SliceCore
import XCTest
@testable import HotkeyManager

final class HotkeyTests: XCTestCase {

    func test_parseOptionSpace() throws {
        let hk = try Hotkey.parse("option+space")
        XCTAssertEqual(hk.keyCode, 49)    // space keycode
        XCTAssertEqual(hk.modifiers, .option)
    }

    func test_parseCmdShiftSpace() throws {
        let hk = try Hotkey.parse("cmd+shift+space")
        XCTAssertEqual(hk.keyCode, 49)
        XCTAssertTrue(hk.modifiers.contains(.command))
        XCTAssertTrue(hk.modifiers.contains(.shift))
    }

    func test_parseCaseInsensitive() throws {
        let hk = try Hotkey.parse("CMD+Space")
        XCTAssertTrue(hk.modifiers.contains(.command))
    }

    func test_parseInvalid_throws() {
        XCTAssertThrowsError(try Hotkey.parse("cmd+nothing"))
        XCTAssertThrowsError(try Hotkey.parse(""))
    }

    func test_descriptionRoundTrip() throws {
        let hk = try Hotkey.parse("option+space")
        XCTAssertEqual(hk.description, "option+space")
    }

    func test_hotkeyConflict_detectsCommandPaletteConflict() {
        let issues = HotkeyBindingValidator.issues(
            commandPalette: "option+space",
            tools: ["translate": "OPT+SPACE"]
        )

        XCTAssertEqual(issues, [
            .commandPaletteConflict(toolID: "translate", normalizedHotkey: "option+space")
        ])
    }

    func test_hotkeyConflict_detectsToolToToolConflict() {
        let issues = HotkeyBindingValidator.issues(
            commandPalette: "option+space",
            tools: [
                "summarize": "cmd+shift+s",
                "translate": "CMD+SHIFT+S"
            ]
        )

        XCTAssertEqual(issues, [
            .toolConflict(firstToolID: "summarize", secondToolID: "translate", normalizedHotkey: "cmd+shift+s")
        ])
    }

    func test_effectiveToolHotkeys_mergesLegacyFallbackForAllTools() {
        var cfg = DefaultConfiguration.initial()
        var translate = DefaultConfiguration.translate
        translate.hotkey = "cmd+1"
        var summarize = DefaultConfiguration.summarize
        summarize.hotkey = "cmd+2"
        cfg.tools = [translate, summarize]
        cfg.hotkeys.tools = ["translate": "cmd+3"]

        let toolHotkeys = HotkeyBindingValidator.effectiveToolHotkeys(
            bindings: cfg.hotkeys,
            tools: cfg.tools
        )

        XCTAssertEqual(toolHotkeys, [
            "summarize": "cmd+2",
            "translate": "cmd+3"
        ])
    }

    func test_appDelegateHotkeyRouting_usesToolID() throws {
        var cfg = DefaultConfiguration.initial()
        cfg.hotkeys.tools = [
            "summarize": "cmd+shift+s",
            "missing": "cmd+shift+m"
        ]

        let registrations = ToolHotkeyRegistration.validRegistrations(in: cfg)

        XCTAssertEqual(registrations.map(\.toolID), ["summarize"])
        XCTAssertEqual(registrations.map(\.hotkey.description), ["cmd+shift+s"])
    }

    func test_appDelegateHotkeyRouting_rejectsLegacyToolHotkeyConflict() throws {
        var cfg = DefaultConfiguration.initial()
        var translate = DefaultConfiguration.translate
        translate.hotkey = "cmd+shift+s"
        var summarize = DefaultConfiguration.summarize
        summarize.hotkey = "CMD+SHIFT+S"
        cfg.tools = [translate, summarize]
        cfg.hotkeys.tools = [:]

        let registrations = ToolHotkeyRegistration.validRegistrations(in: cfg)

        XCTAssertEqual(registrations, [])
    }
}
