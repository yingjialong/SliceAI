import XCTest
@testable import SliceCore

/// Task 7：`ToolPermissionError` 与 `SliceError.toolPermission` 的语义 / 脱敏 / 等价性单测
///
/// 测试矩阵：
/// 1. `ToolPermissionError.userMessage` 5 个 case 各 1 测试（文案精确匹配 / 含计数）
/// 2. `SliceError.toolPermission(_:).userMessage` 委托给内部 `ToolPermissionError.userMessage`
/// 3. `SliceError.toolPermission(_:).developerContext` 5 个 case：
///    - .undeclared 仅暴露 count（permission 集合本身可能含路径 / server 名 → 不进日志）
///    - .denied / .notGranted / .unknownProvider / .sandboxViolation 全 <redacted>
/// 4. `ConfigurationError.invalidTool` 的 userMessage 含 tool id + reason
/// 5. `SliceError.configuration(.invalidTool(...))` 的 developerContext == "configuration.invalidTool(<redacted>)"
/// 6. `ToolPermissionError` Equatable：相同关联值 == ；不同 != （含集合等价性）
final class ToolPermissionErrorTests: XCTestCase {

    // MARK: - userMessage（ToolPermissionError 自身）

    /// undeclared.userMessage 拼入 missing 集合大小（不暴露具体权限项）
    func test_userMessage_undeclared_includesCount() {
        // 构造含 2 项 missing：fileWrite + mcp，应显示 "2 项"
        let missing: Set<Permission> = [
            .fileWrite(path: "~/Documents/log.md"),
            .mcp(server: "fs", tools: ["read"])
        ]
        let err = ToolPermissionError.undeclared(missing: missing)
        XCTAssertEqual(err.userMessage, "工具尝试访问未声明的权限（2 项）。")
    }

    /// denied.userMessage 把 reason 拼进文案（reason 由 broker 保证安全，不脱敏）
    func test_userMessage_denied_includesReason() {
        let err = ToolPermissionError.denied(
            permission: .fileRead(path: "~/secret.md"),
            reason: "用户在弹窗中选择了拒绝"
        )
        XCTAssertEqual(err.userMessage, "权限被拒绝：用户在弹窗中选择了拒绝")
    }

    /// notGranted.userMessage 是固定文案
    func test_userMessage_notGranted_isFixedCopy() {
        let err = ToolPermissionError.notGranted(permission: .clipboard)
        XCTAssertEqual(err.userMessage, "权限未授予，无法执行该工具。")
    }

    /// unknownProvider.userMessage 把 provider id 拼进文案（spec §3.9.6.5 同款 ContextError）
    func test_userMessage_unknownProvider_includesId() {
        let err = ToolPermissionError.unknownProvider(id: "nonexistent.foo")
        XCTAssertEqual(err.userMessage, "未注册的提供方 \"nonexistent.foo\"。")
    }

    /// sandboxViolation.userMessage 是固定文案（path 不暴露给用户层文案，避免误导）
    func test_userMessage_sandboxViolation_isFixedCopy() {
        let err = ToolPermissionError.sandboxViolation(path: "/etc/passwd")
        XCTAssertEqual(err.userMessage, "路径访问被沙箱拦截。")
    }

    // MARK: - SliceError.toolPermission 委托与脱敏

    /// SliceError.toolPermission(...).userMessage 直接委托给 ToolPermissionError.userMessage
    func test_sliceError_toolPermission_userMessage_delegatesToInner() {
        let inner = ToolPermissionError.unknownProvider(id: "file.read")
        let outer = SliceError.toolPermission(inner)
        XCTAssertEqual(outer.userMessage, inner.userMessage)
    }

    /// developerContext.undeclared 仅暴露 count，不暴露权限明细（path / server 名都可能敏感）
    func test_developerContext_undeclared_exposesCountOnly() {
        let missing: Set<Permission> = [
            .fileWrite(path: "/Users/me/secret.md"),
            .shellExec(commands: ["rm -rf /"]),
            .mcp(server: "private.kb", tools: nil)
        ]
        let outer = SliceError.toolPermission(.undeclared(missing: missing))
        XCTAssertEqual(outer.developerContext, "toolPermission.undeclared(count=3)")
        // 显式确认敏感字符串不会出现在日志输出中
        XCTAssertFalse(outer.developerContext.contains("/Users/me/secret.md"))
        XCTAssertFalse(outer.developerContext.contains("rm -rf"))
        XCTAssertFalse(outer.developerContext.contains("private.kb"))
    }

    /// developerContext.denied 完全脱敏（permission + reason 都不进日志）
    func test_developerContext_denied_redactsAll() {
        let outer = SliceError.toolPermission(.denied(
            permission: .fileWrite(path: "/Users/me/leak.txt"),
            reason: "raw reason that may contain pii"
        ))
        XCTAssertEqual(outer.developerContext, "toolPermission.denied(<redacted>)")
        XCTAssertFalse(outer.developerContext.contains("leak.txt"))
        XCTAssertFalse(outer.developerContext.contains("pii"))
    }

    /// developerContext.notGranted 是无关联值的 tag 字符串
    func test_developerContext_notGranted_isFixedTag() {
        let outer = SliceError.toolPermission(.notGranted(permission: .clipboard))
        XCTAssertEqual(outer.developerContext, "toolPermission.notGranted")
    }

    /// developerContext.unknownProvider 完全脱敏（provider id 可能是私有 MCP 名）
    func test_developerContext_unknownProvider_redactsId() {
        let outer = SliceError.toolPermission(.unknownProvider(id: "mcp.private.kb.alpha"))
        XCTAssertEqual(outer.developerContext, "toolPermission.unknownProvider(<redacted>)")
        XCTAssertFalse(outer.developerContext.contains("mcp.private"))
    }

    /// developerContext.sandboxViolation 完全脱敏（path 是用户文件路径）
    func test_developerContext_sandboxViolation_redactsPath() {
        let outer = SliceError.toolPermission(.sandboxViolation(path: "/Users/me/.ssh/id_rsa"))
        XCTAssertEqual(outer.developerContext, "toolPermission.sandboxViolation(<redacted>)")
        XCTAssertFalse(outer.developerContext.contains("id_rsa"))
        XCTAssertFalse(outer.developerContext.contains(".ssh"))
    }

    // MARK: - ConfigurationError.invalidTool

    /// invalidTool.userMessage 拼入 tool id + reason
    func test_configurationError_invalidTool_userMessage_includesIdAndReason() {
        let err = SliceError.configuration(.invalidTool(
            id: "translate.zh",
            reason: "PromptTool 引用了未注册的 ContextProvider \"file.read\""
        ))
        XCTAssertEqual(
            err.userMessage,
            "工具 \"translate.zh\" 配置错误：PromptTool 引用了未注册的 ContextProvider \"file.read\""
        )
    }

    /// invalidTool.developerContext 完全脱敏（id + reason 都可能含敏感信息）
    func test_configuration_invalidTool_developerContext_isRedacted() {
        let err = SliceError.configuration(.invalidTool(
            id: "tool.with.secret",
            reason: "raw reason: api key sk-xxx"
        ))
        XCTAssertEqual(err.developerContext, "configuration.invalidTool(<redacted>)")
        XCTAssertFalse(err.developerContext.contains("sk-xxx"))
        XCTAssertFalse(err.developerContext.contains("tool.with.secret"))
    }

    // MARK: - Equatable

    /// 相同 case + 相同关联值 ==
    func test_equatable_sameUnknownProvider_equal() {
        let lhs = ToolPermissionError.unknownProvider(id: "x")
        let rhs = ToolPermissionError.unknownProvider(id: "x")
        XCTAssertEqual(lhs, rhs)
    }

    /// 同 case 但关联值不同 → !=
    func test_equatable_differentUnknownProvider_notEqual() {
        let lhs = ToolPermissionError.unknownProvider(id: "x")
        let rhs = ToolPermissionError.unknownProvider(id: "y")
        XCTAssertNotEqual(lhs, rhs)
    }

    /// undeclared 集合相等性：Set<Permission> 内含 path / server 等关联值，应按"集合相等"判定
    func test_equatable_undeclared_setEquality() {
        let lhs = ToolPermissionError.undeclared(missing: [.clipboard, .fileRead(path: "a")])
        let rhs = ToolPermissionError.undeclared(missing: [.fileRead(path: "a"), .clipboard])
        XCTAssertEqual(lhs, rhs, "Set 顺序无关，相同元素应相等")

        let diff = ToolPermissionError.undeclared(missing: [.clipboard])
        XCTAssertNotEqual(lhs, diff)
    }

    /// 不同 case → !=
    func test_equatable_differentCases_notEqual() {
        let lhs = ToolPermissionError.notGranted(permission: .clipboard)
        let rhs = ToolPermissionError.sandboxViolation(path: "/tmp")
        XCTAssertNotEqual(lhs, rhs)
    }
}
