import Foundation

/// MCP client 诊断日志 sink；默认禁用，测试或调试时可注入异步 collector。
public struct MCPDiagnosticLog: Sendable {
    private let handler: @Sendable (String) async -> Void

    /// 禁用诊断日志的默认实例。
    public static let disabled = MCPDiagnosticLog { _ in }

    /// 构造诊断日志 sink。
    public init(_ handler: @escaping @Sendable (String) async -> Void) {
        self.handler = handler
    }

    /// 记录一条诊断消息；入口统一做脱敏，避免调用方遗漏。
    public func record(_ message: String) async {
        await handler(Self.redact(message))
    }

    /// 脱敏 bearer、OpenAI `sk-`、Authorization、Cookie 等敏感片段。
    public static func redact(_ input: String) -> String {
        guard !input.isEmpty else { return input }
        var result = input
        for (regex, replacement) in patterns {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: replacement
            )
        }
        return result
    }

    /// 已编译脱敏正则；与 Orchestration.Redaction 保持同类模式，但避免 Capabilities 反向依赖 Orchestration。
    private static let patterns: [(NSRegularExpression, String)] = {
        let rawPatterns: [(String, String)] = [
            (#"Bearer\s+[A-Za-z0-9_\-\.=]+"#, "<redacted>"),
            ("sk-[A-Za-z0-9_-]{16,}", "<redacted>"),
            ("Authorization:\\s*[^\\r\\n]+", "Authorization: <redacted>"),
            ("Cookie:\\s*[^\\r\\n]+", "Cookie: <redacted>")
        ]
        var compiled: [(NSRegularExpression, String)] = []
        for (pattern, replacement) in rawPatterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
                compiled.append((regex, replacement))
            }
        }
        return compiled
    }()
}
