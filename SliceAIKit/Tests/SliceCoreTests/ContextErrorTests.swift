import XCTest
@testable import SliceCore

/// Task 5: `ContextError` 与 `SliceError.context` 的语义 / 脱敏 / 等价性单测
///
/// 测试矩阵：
/// 1. `ContextError.userMessage` 三个 case 各 1 测试（文案精确匹配）
/// 2. `SliceError.context(_:).userMessage` 委托到内部 `ContextError.userMessage`
/// 3. `SliceError.context(_:).developerContext` 三个 case 都返回 `<redacted>`
///    （key.rawValue / provider id / underlying error 都不能流入日志）
/// 4. `ContextError` Equatable：相同关联值 == ；不同 != ；
///    `requiredFailed.underlying` 经 `SliceError → ContextError → SliceError` 递归仍能比较
final class ContextErrorTests: XCTestCase {

    // MARK: - userMessage（ContextError 自身）

    /// requiredFailed.userMessage 把 ContextKey.rawValue 拼进中文文案
    func test_userMessage_requiredFailed_includesKey() {
        let key = ContextKey(rawValue: "vocab.markdown")
        let underlying = SliceError.selection(.axEmpty)
        let err = ContextError.requiredFailed(key: key, underlying: underlying)
        XCTAssertEqual(err.userMessage, "必填上下文 \"vocab.markdown\" 采集失败。")
    }

    /// providerNotFound.userMessage 把 provider id 拼进中文文案
    func test_userMessage_providerNotFound_includesId() {
        let err = ContextError.providerNotFound(id: "file.read")
        XCTAssertEqual(err.userMessage, "未注册的上下文提供方 \"file.read\"。")
    }

    /// timeout.userMessage 把 ContextKey.rawValue 拼进中文文案
    func test_userMessage_timeout_includesKey() {
        let key = ContextKey(rawValue: "mcp.result")
        let err = ContextError.timeout(key: key)
        XCTAssertEqual(err.userMessage, "上下文 \"mcp.result\" 采集超时。")
    }

    // MARK: - SliceError.context 委托与脱敏

    /// SliceError.context(...).userMessage 直接委托给 ContextError.userMessage
    func test_sliceError_context_userMessage_delegatesToInner() {
        let key = ContextKey(rawValue: "selection.related")
        let inner = ContextError.requiredFailed(key: key, underlying: .selection(.axEmpty))
        let outer = SliceError.context(inner)
        XCTAssertEqual(outer.userMessage, inner.userMessage)
    }

    /// developerContext 必须脱敏 requiredFailed 的 key + underlying（避免泄漏路径 / 配置）
    func test_developerContext_requiredFailed_redactsAll() {
        let key = ContextKey(rawValue: "/Users/secret/file.md")
        let underlying = SliceError.provider(.invalidResponse("API returned 500: secret payload"))
        let outer = SliceError.context(.requiredFailed(key: key, underlying: underlying))
        XCTAssertEqual(outer.developerContext, "context.requiredFailed(<redacted>)")
    }

    /// developerContext 必须脱敏 providerNotFound 的 id（防止 MCP server 名 / 用户工具名泄漏）
    func test_developerContext_providerNotFound_redactsId() {
        let outer = SliceError.context(.providerNotFound(id: "mcp.private.server.alpha"))
        XCTAssertEqual(outer.developerContext, "context.providerNotFound(<redacted>)")
    }

    /// developerContext 必须脱敏 timeout 的 key（防止用户路径 / 文件名通过 key 泄漏）
    func test_developerContext_timeout_redactsKey() {
        let outer = SliceError.context(.timeout(key: ContextKey(rawValue: "/Users/me/secret.json")))
        XCTAssertEqual(outer.developerContext, "context.timeout(<redacted>)")
    }

    // MARK: - Equatable（含 SliceError → ContextError → SliceError 递归）

    /// 相同 case + 相同关联值 ==
    func test_equatable_sameRequiredFailed_equal() {
        let key = ContextKey(rawValue: "k1")
        let lhs = ContextError.requiredFailed(key: key, underlying: .selection(.axEmpty))
        let rhs = ContextError.requiredFailed(key: key, underlying: .selection(.axEmpty))
        XCTAssertEqual(lhs, rhs)
    }

    /// 同 case 但 underlying 不同 → !=（验证 indirect enum 的递归相等性正确传递）
    func test_equatable_differentUnderlying_notEqual() {
        let key = ContextKey(rawValue: "k1")
        let lhs = ContextError.requiredFailed(key: key, underlying: .selection(.axEmpty))
        let rhs = ContextError.requiredFailed(key: key, underlying: .selection(.axUnavailable))
        XCTAssertNotEqual(lhs, rhs)
    }

    /// 不同 case → !=（providerNotFound vs timeout）
    func test_equatable_differentCases_notEqual() {
        let lhs = ContextError.providerNotFound(id: "x")
        let rhs = ContextError.timeout(key: ContextKey(rawValue: "x"))
        XCTAssertNotEqual(lhs, rhs)
    }

    /// SliceError.context 嵌套的等价性（递归层 SliceError → ContextError → SliceError 仍稳）
    func test_equatable_sliceError_context_recursiveEquality() {
        let key = ContextKey(rawValue: "deep")
        let inner1 = ContextError.requiredFailed(key: key, underlying: .selection(.axEmpty))
        let inner2 = ContextError.requiredFailed(key: key, underlying: .selection(.axEmpty))
        XCTAssertEqual(SliceError.context(inner1), SliceError.context(inner2))

        // 同一 ContextError 但被两层 .context 嵌套（再走一次 SliceError → ContextError → SliceError）
        let nested1 = SliceError.context(.requiredFailed(
            key: key,
            underlying: .context(.providerNotFound(id: "abc"))
        ))
        let nested2 = SliceError.context(.requiredFailed(
            key: key,
            underlying: .context(.providerNotFound(id: "abc"))
        ))
        XCTAssertEqual(nested1, nested2)
    }
}
