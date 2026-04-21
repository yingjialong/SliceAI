import XCTest
@testable import DesignSystem

/// DesignSystem 基础烟雾测试，保证 target 装配正确
final class DesignSystemTests: XCTestCase {
    /// 验证模块常量可访问，target 正确链接
    func test_version_isAccessible() {
        XCTAssertFalse(DesignSystem.version.isEmpty)
    }
}
