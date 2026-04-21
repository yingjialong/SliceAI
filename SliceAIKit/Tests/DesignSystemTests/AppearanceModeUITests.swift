import XCTest
import AppKit
import SliceCore
@testable import DesignSystem

/// AppearanceMode UI 扩展测试
///
/// 验证 DesignSystem 层的 displayName（中文展示名）和 nsAppearance（NSAppearance 映射）。
/// AppearanceMode 纯数据模型测试（rawValue / Codable）在 SliceCoreTests/AppearanceModeTests.swift
final class AppearanceModeUITests: XCTestCase {

    /// displayName 返回正确的中文名称
    func test_displayName_localized() {
        XCTAssertEqual(AppearanceMode.auto.displayName,  "跟随系统")
        XCTAssertEqual(AppearanceMode.light.displayName, "浅色")
        XCTAssertEqual(AppearanceMode.dark.displayName,  "深色")
    }

    /// nsAppearance 映射：light → .aqua，dark → .darkAqua，auto → nil
    func test_nsAppearance_mapping() {
        XCTAssertEqual(AppearanceMode.light.nsAppearance?.name, .aqua)
        XCTAssertEqual(AppearanceMode.dark.nsAppearance?.name,  .darkAqua)
        XCTAssertNil(AppearanceMode.auto.nsAppearance)
    }
}
