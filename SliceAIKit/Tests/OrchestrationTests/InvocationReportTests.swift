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

    func test_errorKind_from_mapsAllSliceErrorCases() {
        // 4 个 M1 SliceError 顶层 case 必须各自映射到对应的 ErrorKind；
        // Task 5/7 扩展 SliceError 时本测试 + ErrorKind.from exhaustive switch
        // 共同构成回归守卫——任何漏接的 case 在编译期或本测试中暴露
        XCTAssertEqual(InvocationOutcome.ErrorKind.from(.selection(.axUnavailable)), .selection)
        XCTAssertEqual(InvocationOutcome.ErrorKind.from(.provider(.unauthorized)), .provider)
        XCTAssertEqual(InvocationOutcome.ErrorKind.from(.configuration(.fileNotFound)), .configuration)
        XCTAssertEqual(InvocationOutcome.ErrorKind.from(.permission(.accessibilityDenied)), .permission)
    }

    /// 验证 SliceError.execution 映射到 InvocationOutcome.ErrorKind.execution。
    func test_errorKindFrom_execution() {
        XCTAssertEqual(
            InvocationOutcome.ErrorKind.from(.execution(.notImplemented("test"))),
            .execution
        )
        XCTAssertEqual(
            InvocationOutcome.ErrorKind.from(.execution(.unknown("test"))),
            .execution
        )
    }

    /// 验证 ErrorKind.execution 的持久化 rawValue 稳定。
    func test_errorKindExecution_rawValue() {
        XCTAssertEqual(InvocationOutcome.ErrorKind.execution.rawValue, "execution")
    }
}
