// SliceAIKit/Sources/SliceCore/PromptTemplate.swift
import Foundation

/// 轻量 {{variable}} 模板渲染器
/// 不支持循环 / 条件 / filter；保留语义极简以降低贡献门槛
public enum PromptTemplate {

    /// 渲染模板：将 {{name}} 替换为 variables[name]，未定义变量保留原样
    /// - Parameters:
    ///   - template: 含占位符的模板字符串
    ///   - variables: 变量表，key 为 {{}} 内的标识符
    /// - Returns: 渲染后的字符串
    public static func render(_ template: String, variables: [String: String]) -> String {
        guard !template.isEmpty else { return template }

        // 用正则匹配 {{identifier}}。identifier 仅禁止空白与 `{` / `}`，
        // 以覆盖配置层对 key 没有字符集限制的事实（支持 Unicode、点号、连字符等）
        // 空白、换行仍会让占位符保留原样，避免 "{{ a b }}" 这类意外匹配
        let pattern = #"\{\{([^\s{}]+)\}\}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return template }

        let ns = template as NSString
        var result = ""
        var cursor = 0
        let fullRange = NSRange(location: 0, length: ns.length)

        regex.enumerateMatches(in: template, range: fullRange) { match, _, _ in
            guard let match else { return }
            let wholeRange = match.range
            let nameRange = match.range(at: 1)
            // 追加命中前的原文
            if wholeRange.location > cursor {
                result += ns.substring(with: NSRange(location: cursor,
                                                     length: wholeRange.location - cursor))
            }
            let name = ns.substring(with: nameRange)
            if let value = variables[name] {
                result += value
            } else {
                // 未知变量保留原占位符
                result += ns.substring(with: wholeRange)
            }
            cursor = wholeRange.location + wholeRange.length
        }
        if cursor < ns.length {
            result += ns.substring(with: NSRange(location: cursor, length: ns.length - cursor))
        }
        return result
    }
}
