import XCTest
@testable import SliceCore

/// AppearanceMode 纯数据模型测试（rawValue / Codable / CaseIterable）
///
/// UI 语义（displayName / nsAppearance）的测试在 DesignSystemTests/AppearanceModeUITests.swift
final class AppearanceModeTests: XCTestCase {

    /// rawValue 与字符串映射验证
    func test_rawValue_mapping() {
        XCTAssertEqual(AppearanceMode.auto.rawValue, "auto")
        XCTAssertEqual(AppearanceMode.light.rawValue, "light")
        XCTAssertEqual(AppearanceMode.dark.rawValue, "dark")
    }

    /// Codable 编码为 JSON string
    func test_codable_encodeAsString() throws {
        let data = try JSONEncoder().encode(AppearanceMode.dark)
        let json = String(data: data, encoding: .utf8)
        XCTAssertEqual(json, "\"dark\"")
    }

    /// Codable 解码 JSON string
    func test_codable_decodeFromString() throws {
        let data = Data("\"light\"".utf8)
        let mode = try JSONDecoder().decode(AppearanceMode.self, from: data)
        XCTAssertEqual(mode, .light)
    }

    /// allCases 完整性：确保三个值都存在
    func test_allCases_completeness() {
        XCTAssertEqual(Set(AppearanceMode.allCases), Set([.auto, .light, .dark]))
    }
}
