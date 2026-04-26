import XCTest
import SliceCore
@testable import Orchestration

/// InvocationReport 单元测试
///
/// 覆盖：
/// 1. undeclaredPermissions 在 effective ⊆ declared 时返回空集
/// 2. undeclaredPermissions 在 effective 超出 declared 时返回差集
/// 3. InvocationFlag rawValue codable 正向往返
final class InvocationReportTests: XCTestCase {

    func test_undeclaredPermissions_returnsEmptySetWhenEffectiveIsSubsetOfDeclared() {
        // effective 权限集合 ⊆ declared 时，undeclaredPermissions 应为空
        let declared: Set<Permission> = [.fileRead(path: "~/Documents/**")]
        let effective: Set<Permission> = [.fileRead(path: "~/Documents/**")]
        let report = InvocationReport.stub(declared: declared, effective: effective)
        XCTAssertTrue(report.undeclaredPermissions.isEmpty)
    }

    func test_undeclaredPermissions_returnsDifferenceWhenEffectiveExceedsDeclared() {
        // effective 包含 declared 未声明的权限时，应返回差集
        let declared: Set<Permission> = [.fileRead(path: "~/Documents/**")]
        let effective: Set<Permission> = [
            .fileRead(path: "~/Documents/**"),
            .fileWrite(path: "~/Library/Application Support/SliceAI/**")
        ]
        let report = InvocationReport.stub(declared: declared, effective: effective)
        XCTAssertEqual(
            report.undeclaredPermissions,
            [.fileWrite(path: "~/Library/Application Support/SliceAI/**")]
        )
    }

    func test_invocationFlag_codable_roundtrips() throws {
        // 验证 InvocationFlag rawValue 能正确编码为 JSON 字符串并解码回来
        let flag = InvocationFlag.permissionUndeclared
        let data = try JSONEncoder().encode(flag)
        let decoded = try JSONDecoder().decode(InvocationFlag.self, from: data)
        XCTAssertEqual(decoded, flag)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"permissionUndeclared\"")
    }
}
