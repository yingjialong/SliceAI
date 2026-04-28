import Foundation

/// 审计日志脱敏 helper（spec §3.9.5）。
///
/// 设计目标：
/// 1. **统一脱敏入口**——`AuditLogProtocol.append(_:)` 实现内部对所有 String payload
///    主动调用，避免依赖生产者；
/// 2. **可枚举的敏感模式**——只识别明确危险的固定模式（API key、Bearer token、
///    Authorization / Cookie header），不做"看起来像 secret"的启发式判定，避免误伤
///    用户工具的合法 toolId / 参数；
/// 3. **防 jsonl 单行溢出**——超过 `maxLength` 字符的字段直接替换为
///    `<truncated:N>`，N 是原长度；既限制单条 audit entry 体积，也降低 Console 噪音。
///
/// **不在脱敏范围内**：
/// - `Permission` 关联值里的路径 / host / bundleId：这些是稳定标识符，且 audit 需要
///   保留以支持事后审计；路径合法性由 `PathSandbox`（Task 12）独立把关；
/// - `InvocationReport` 的 `flags` / `outcome` 等枚举值：rawValue 是固定字符串，无 PII。
public enum Redaction {

    /// 单字段最大保留长度；超过即直接替换为 "<truncated:N>"（N = 原长度）
    public static let maxLength = 200

    // MARK: - 模式定义（lazy 初始化避免每次调用重新编译）

    /// 已编译的正则 + 替换模板对；first-success-then-continue 顺序生效
    ///
    /// `try?` + 防御性 fallback：模式都是硬编码 literal，理论上永远 valid；
    /// 与 PromptTemplate.swift 同款做法，避免 force_try / force_unwrapping 触发 lint
    ///
    /// **顺序很关键**：先用"具体 token 模式"（Bearer / sk-）替换敏感子串，
    /// 再用"行级 header 模式"（Authorization / Cookie）吃掉残留的 `<redacted>` 标记
    /// 与字段名（如 "Authorization: <redacted>"）。
    ///
    /// **header 兜底必须 match 到行尾**：Cookie / Authorization 里常见多段 `key=value;
    /// key2=value2`（RFC 6265 cookie pair 用 `; ` 分隔），`\S+` 只吃第一个空白前的 token，
    /// 第二段 `key2=value2` 会原样留在 audit jsonl 中——真实泄露风险。改用 `[^\r\n]+`
    /// 一直吃到行末（NSRegularExpression `.` 默认不跨行；这里更显式），覆盖：
    /// - `Cookie: a=secret; b=secret2` → `Cookie: <redacted>`（不再漏 b=secret2）
    /// - `Authorization: my.jwt.token next-stuff` → `Authorization: <redacted>`
    /// - `Authorization: <redacted>`（已被 Bearer 子规则替换过）→ 仍幂等收敛
    private static let patterns: [(NSRegularExpression, String)] = {
        // 候选 patterns：(pattern, replacement)
        let raw: [(String, String)] = [
            // 1. Bearer <token>（含 dot/dash/equals/underscore，覆盖 JWT / opaque token）
            (#"Bearer\s+[A-Za-z0-9_\-\.=]+"#, "<redacted>"),
            // 2. OpenAI 风格 sk-xxxx（16+ 字符，含 dash / underscore）
            ("sk-[A-Za-z0-9_-]{16,}", "<redacted>"),
            // 3. Authorization header（吃到行尾，覆盖多 token / 子模式残留）
            ("Authorization:\\s*[^\\r\\n]+", "Authorization: <redacted>"),
            // 4. Cookie header（吃到行尾，覆盖 RFC 6265 多对 key=value 用 `; ` 分隔）
            ("Cookie:\\s*[^\\r\\n]+", "Cookie: <redacted>")
        ]
        var compiled: [(NSRegularExpression, String)] = []
        for (pat, rep) in raw {
            // .caseInsensitive 让 "bearer" / "BEARER" / "Authorization" / "AUTHORIZATION" 一并命中
            if let regex = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) {
                compiled.append((regex, rep))
            }
        }
        return compiled
    }()

    // MARK: - Public API

    /// 脱敏字符串：先替换敏感模式，再做长度截断
    ///
    /// - Parameter input: 原始字符串（来自 audit entry 的 String payload）
    /// - Returns: 脱敏后的字符串；可能比原文短（截断）也可能稍长（替换为更长 marker）
    public static func scrub(_ input: String) -> String {
        // 空字符串 short-circuit：避免无谓的 NSRegularExpression 调用
        guard !input.isEmpty else { return input }

        var result = input

        // 顺序应用所有已编译 pattern；任何一条命中都直接替换
        for (regex, replacement) in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }

        // 长度截断：用原长度做 N，便于审计回看时知道"原本多长"
        if result.count > maxLength {
            return "<truncated:\(result.count)>"
        }
        return result
    }
}
