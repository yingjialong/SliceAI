import XCTest
import SwiftUI
import AppKit
@testable import DesignSystem

/// ThemeManager 单元测试
@MainActor
final class ThemeManagerTests: XCTestCase {
    /// 初始化后 mode 等于传入值
    func test_init_setsInitialMode() {
        let tm = ThemeManager(initialMode: .dark)
        XCTAssertEqual(tm.mode, .dark)
    }

    /// setMode 切换时 mode 同步更新
    func test_setMode_updatesMode() {
        let tm = ThemeManager(initialMode: .auto)
        tm.setMode(.light)
        XCTAssertEqual(tm.mode, .light)
    }

    /// .light 模式下 resolvedColorScheme 固定为 .light
    func test_resolvedColorScheme_lightMode() {
        let tm = ThemeManager(initialMode: .light)
        XCTAssertEqual(tm.resolvedColorScheme, .light)
    }

    /// .dark 模式下 resolvedColorScheme 固定为 .dark
    func test_resolvedColorScheme_darkMode() {
        let tm = ThemeManager(initialMode: .dark)
        XCTAssertEqual(tm.resolvedColorScheme, .dark)
    }

    /// .light / .dark 对应的 NSAppearance 名称正确
    func test_nsAppearance_forExplicitModes() {
        let light = ThemeManager(initialMode: .light)
        XCTAssertEqual(light.nsAppearance?.name, NSAppearance.Name.aqua)

        let dark = ThemeManager(initialMode: .dark)
        XCTAssertEqual(dark.nsAppearance?.name, NSAppearance.Name.darkAqua)
    }

    /// .auto 模式下 nsAppearance 返回 nil（让 NSWindow 回落到系统）
    func test_nsAppearance_autoReturnsNil() {
        let tm = ThemeManager(initialMode: .auto)
        XCTAssertNil(tm.nsAppearance)
    }

    /// setMode 触发 onModeChange 回调
    func test_setMode_invokesCallback() {
        let tm = ThemeManager(initialMode: .auto)
        var captured: AppearanceMode?
        tm.onModeChange = { captured = $0 }
        tm.setMode(.dark)
        XCTAssertEqual(captured, .dark)
    }
}
