import XCTest
@testable import Orchestration

/// Redaction 脱敏 helper 单元测试
///
/// 覆盖的关键模式：
/// 1. 普通字符串不变（无敏感模式）
/// 2. OpenAI 风格 sk- 前缀 token 替换
/// 3. Bearer token 替换
/// 4. Authorization header 替换
/// 5. Cookie header 替换
/// 6. 多模式叠加：同一字符串含多种敏感片段全部命中
/// 7. 长度截断：超过 maxLength 字符替换为 "<truncated:N>"
/// 8. 空字符串 short-circuit
/// 9. 大小写无关：bearer / BEARER / Authorization / AUTHORIZATION 都命中
final class RedactionTests: XCTestCase {

    // MARK: - 基础不变 case

    /// 普通 ASCII 文本应保持不变
    func test_scrub_plainText_returnsUnchanged() {
        let input = "hello world this is a normal sentence"
        XCTAssertEqual(Redaction.scrub(input), input)
    }

    /// 空字符串 short-circuit，原样返回
    func test_scrub_emptyString_returnsEmpty() {
        XCTAssertEqual(Redaction.scrub(""), "")
    }

    /// Unicode / 中文文本不应被任何模式误伤
    func test_scrub_unicodeText_returnsUnchanged() {
        let input = "中文 prompt 用户输入 — 不含敏感字段"
        XCTAssertEqual(Redaction.scrub(input), input)
    }

    // MARK: - sk- token

    /// OpenAI 风格 sk- 前缀 + 16+ 字符的 key 应被替换
    func test_scrub_openAIKey_isRedacted() {
        let input = "key=sk-1234567890abcdefghij"
        let result = Redaction.scrub(input)
        XCTAssertFalse(result.contains("sk-1234567890abcdef"))
        XCTAssertTrue(result.contains("<redacted>"))
    }

    /// 短 sk-xxx（< 16 字符）不应被误伤——避免误判合法的 toolId
    func test_scrub_shortSkPrefix_notTouched() {
        // 11 字符 < 16，不命中 sk-[A-Za-z0-9_-]{16,}
        let input = "tool-id=sk-short01"
        let result = Redaction.scrub(input)
        XCTAssertEqual(result, input)
    }

    // MARK: - Bearer token

    /// Bearer 后跟 token 应整段被替换
    func test_scrub_bearerToken_isRedacted() {
        let input = "Authorization header value: Bearer abc123.def456-ghi"
        let result = Redaction.scrub(input)
        XCTAssertFalse(result.contains("abc123.def456-ghi"))
        XCTAssertTrue(result.contains("<redacted>"))
    }

    /// 大小写无关：bearer 小写也命中
    func test_scrub_bearerLowercase_isRedacted() {
        let input = "got bearer xyzTOKENvalue here"
        let result = Redaction.scrub(input)
        XCTAssertFalse(result.contains("xyzTOKENvalue"))
    }

    // MARK: - Authorization header

    /// Authorization: <token> 格式整段替换
    func test_scrub_authorizationHeader_isRedacted() {
        let input = "request: Authorization: Token-XYZ-123 trailing text"
        let result = Redaction.scrub(input)
        XCTAssertFalse(result.contains("Token-XYZ-123"))
        XCTAssertTrue(result.contains("Authorization: <redacted>"))
    }

    // MARK: - Cookie header

    /// Cookie: <value> 格式整段替换
    func test_scrub_cookieHeader_isRedacted() {
        let input = "request headers: Cookie: session=abc123def trailing"
        let result = Redaction.scrub(input)
        XCTAssertFalse(result.contains("session=abc123def"))
        XCTAssertTrue(result.contains("Cookie: <redacted>"))
    }

    /// RFC 6265 多对 cookie（用 `; ` 分隔）必须整段被替换——
    /// 旧 `Cookie:\s*\S+` 在第一个空白处停止，会让第二个 `b=secret2` 漏过脱敏。
    /// 这是审计日志真实泄露面，必须保持回归。
    func test_scrub_cookieHeader_multipleValues_allRedacted() {
        let input = "Cookie: a=secret1; b=secret2; c=secret3"
        let result = Redaction.scrub(input)
        // 任意一个 cookie value 都不应残留
        XCTAssertFalse(result.contains("a=secret1"), "first cookie value leaked: \(result)")
        XCTAssertFalse(result.contains("b=secret2"), "second cookie value leaked: \(result)")
        XCTAssertFalse(result.contains("c=secret3"), "third cookie value leaked: \(result)")
        // 整段头被压成单个 marker
        XCTAssertTrue(result.contains("Cookie: <redacted>"))
    }

    /// Authorization 多 token / 含残留也必须吃到行尾——防止 `Bearer abc def` 这类
    /// 多 token 格式或子规则替换后留下的尾随 token 漏过脱敏。
    func test_scrub_authorizationHeader_multipleTokens_allRedacted() {
        let input = "Authorization: my.jwt.token additional-segment"
        let result = Redaction.scrub(input)
        XCTAssertFalse(result.contains("my.jwt.token"), "first token leaked: \(result)")
        XCTAssertFalse(result.contains("additional-segment"), "second token leaked: \(result)")
        XCTAssertTrue(result.contains("Authorization: <redacted>"))
    }

    // MARK: - 多模式叠加

    /// 同一字符串含 sk- + Bearer + Cookie，三者全部命中
    func test_scrub_multiplePatterns_allRedacted() {
        let input = """
        config: key=sk-1234567890abcdefghij
        Authorization: Bearer my.jwt.token
        Cookie: sessionId=abc123
        """
        let result = Redaction.scrub(input)
        // 每段敏感字段都不应残留
        XCTAssertFalse(result.contains("sk-1234567890abcdef"))
        XCTAssertFalse(result.contains("my.jwt.token"))
        XCTAssertFalse(result.contains("sessionId=abc123"))
        // 至少有一个 <redacted> 被插入
        XCTAssertTrue(result.contains("<redacted>"))
    }

    // MARK: - 长度截断

    /// 超过 maxLength 字符的字符串整段替换为 "<truncated:N>"
    func test_scrub_longString_isTruncated() {
        // 构造 250 字符 ASCII 字符串（>200 maxLength）
        let input = String(repeating: "a", count: 250)
        let result = Redaction.scrub(input)
        XCTAssertEqual(result, "<truncated:250>")
    }

    /// 边界：恰好 maxLength 长度（200）保留原文
    func test_scrub_exactMaxLength_returnsUnchanged() {
        let input = String(repeating: "b", count: Redaction.maxLength)
        let result = Redaction.scrub(input)
        XCTAssertEqual(result, input)
    }

    /// 截断优先级在替换之后：先替换敏感模式，再判定截断长度
    /// 这里构造 "<redacted>" 已替换、合计长度仍 > 200 的场景
    func test_scrub_longStringWithSensitivePatterns_truncatedAfterRedaction() {
        let prefix = String(repeating: "x", count: 220)
        let input = "\(prefix) sk-1234567890abcdefghij"
        let result = Redaction.scrub(input)
        // 替换后总长 > 200，最终返回 "<truncated:N>"，N 是替换后的长度
        XCTAssertTrue(result.hasPrefix("<truncated:"))
        XCTAssertTrue(result.hasSuffix(">"))
        // 不应残留任何 sk- 字面量
        XCTAssertFalse(result.contains("sk-1234567890abcdef"))
    }

    // MARK: - 公开常量回归

    /// `maxLength` 公开常量应保持稳定（200），任何调整需同步审计相关测试
    func test_maxLength_isStableAt200() {
        XCTAssertEqual(Redaction.maxLength, 200)
    }
}
