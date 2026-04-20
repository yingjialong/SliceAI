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

        // 用正则匹配 {{identifier}}。identifier 只允许字母数字 / 下划线 / 连字符
        // 空白、换行都会使占位符保留原样
        let pattern = #"\{\{([A-Za-z][A-Za-z0-9_\-]*)\}\}"#
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
