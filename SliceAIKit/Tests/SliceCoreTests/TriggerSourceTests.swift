import XCTest
@testable import SliceCore

final class TriggerSourceTests: XCTestCase {

    func test_allCases_stable() {
        XCTAssertEqual(Set(TriggerSource.allCases), [
            .floatingToolbar, .commandPalette, .hotkey, .shortcutsApp, .urlScheme, .servicesMenu
        ])
    }

    // 显式锁死每个 case 的 JSON 线上编码（wire format）
    // 防止 `case hotkey` → "hotKey" 这类静默重命名绕过 round-trip 测试
    func test_rawValues_allCasesPinned() {
        XCTAssertEqual(TriggerSource.floatingToolbar.rawValue, "floatingToolbar")
        XCTAssertEqual(TriggerSource.commandPalette.rawValue, "commandPalette")
        XCTAssertEqual(TriggerSource.hotkey.rawValue, "hotkey")
        XCTAssertEqual(TriggerSource.shortcutsApp.rawValue, "shortcutsApp")
        XCTAssertEqual(TriggerSource.urlScheme.rawValue, "urlScheme")
        XCTAssertEqual(TriggerSource.servicesMenu.rawValue, "servicesMenu")
    }

    func test_codable_roundtrip() throws {
        for ts in TriggerSource.allCases {
            let data = try JSONEncoder().encode(ts)
            let decoded = try JSONDecoder().decode(TriggerSource.self, from: data)
            XCTAssertEqual(ts, decoded)
        }
    }
}
