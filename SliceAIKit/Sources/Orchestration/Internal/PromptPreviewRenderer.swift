import Foundation
import SliceCore

/// 渲染可展示的 Prompt 预览文本。
///
/// 预览只用于 Playground / dry-run UI，不参与真实 LLM 请求；所有内容在返回前统一经过
/// `Redaction.scrub`，由该 helper 负责敏感模式脱敏与长度截断。
enum PromptPreviewRenderer {
    /// 将 chat messages 渲染为紧凑的多行预览。
    /// - Parameter messages: 即将发送给 LLM 的消息列表。
    /// - Returns: 已脱敏、已截断的预览文本。
    static func render(messages: [ChatMessage]) -> String {
        let raw = messages.map { message in
            "\(message.role.rawValue): \(message.content ?? "")"
        }
        .joined(separator: "\n")
        return Redaction.scrub(raw)
    }
}
