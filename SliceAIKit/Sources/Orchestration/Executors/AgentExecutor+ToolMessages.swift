import Capabilities
import Foundation
import SliceCore

extension AgentExecutor {
    private static let modelToolMessageMaxCharacters = 16 * 1024

    /// 将 MCP result 转成脱敏摘要。
    func summarize(result: MCPCallResult) -> String {
        if let structured = result.structuredContent {
            return Redaction.scrub(structured.redactedSummary(maxCharacters: Redaction.maxLength))
        }
        let text = result.content.map(summarize(content:)).joined(separator: "\n")
        return text.isEmpty ? "Tool completed" : Redaction.scrub(text)
    }

    /// 将 MCP content item 转成短摘要。
    func summarize(content: MCPContentItem) -> String {
        switch content {
        case .text(let text):
            return text
        case .image(_, let mimeType):
            return "<image \(mimeType)>"
        case .resourceLink(let uri, let name, let mimeType):
            return "<resource \(name ?? uri) \(mimeType ?? "")>"
        case .embeddedResource(let uri, let text, let blob, let mimeType):
            return text ?? "<resource \(uri) \(mimeType ?? "") \(blob == nil ? "" : "blob")>"
        }
    }

    /// 将错误转成脱敏摘要。
    func summarize(error: any Error) -> String {
        if let sliceError = error as? SliceError {
            return sliceError.developerContext
        }
        if let mcpError = error as? MCPClientError {
            return mcpError.developerContext
        }
        return "tool call failed"
    }

    /// 将 MCP result 转成回填给模型的工具内容。
    ///
    /// 该路径只做敏感信息脱敏，并保留足够长的前缀内容供模型推理；UI / 日志使用
    /// `summarize(result:)` 的短摘要，避免 ResultPanel 和 audit payload 过大。
    /// - Parameter result: MCP tool call 返回值。
    /// - Returns: 可安全回填给 LLM 的 tool role content。
    func toolMessageContent(result: MCPCallResult) -> String {
        if let structured = result.structuredContent {
            let summary = structured.redactedSummary(
                maxCharacters: Self.modelToolMessageMaxCharacters
            )
            return sanitizeToolMessageContent(summary)
        }
        let text = result.content.map(summarize(content:)).joined(separator: "\n")
        return text.isEmpty ? "Tool completed" : sanitizeToolMessageContent(text)
    }

    /// 清洗回填给模型的工具内容。
    ///
    /// 与 `Redaction.scrub` 不同，本方法不会把长内容整体替换为 `<truncated:N>`；
    /// 它会保留前缀上下文并追加长度提示，使搜索结果、数据库查询等 MCP 输出仍可被模型使用。
    /// - Parameter content: 原始工具内容。
    /// - Returns: 脱敏并按模型消息预算裁剪后的内容。
    func sanitizeToolMessageContent(_ content: String) -> String {
        let redacted = Redaction.scrubSecrets(content)
        guard redacted.count > Self.modelToolMessageMaxCharacters else {
            return redacted
        }
        let prefix = String(redacted.prefix(Self.modelToolMessageMaxCharacters))
        return "\(prefix)\n<truncated:\(redacted.count)>"
    }
}
