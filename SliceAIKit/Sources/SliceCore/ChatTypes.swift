import Foundation

/// 角色，对应 OpenAI Chat Completions 的 role 字段
public enum Role: String, Sendable, Codable {
    case system, user, assistant
}

/// 单条消息
public struct ChatMessage: Sendable, Codable, Equatable {
    public let role: Role
    public let content: String

    /// 构造聊天消息
    /// - Parameters:
    ///   - role: 消息角色（system/user/assistant）
    ///   - content: 消息文本内容
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
    }
}

/// 聊天请求
/// nil 的 temperature / maxTokens 会被序列化省略，保持服务端默认
public struct ChatRequest: Sendable, Codable, Equatable {
    public let model: String
    public let messages: [ChatMessage]
    public let temperature: Double?
    public let maxTokens: Int?

    /// 构造聊天请求
    /// - Parameters:
    ///   - model: 模型标识，例如 "gpt-5"
    ///   - messages: 历史消息数组
    ///   - temperature: 采样温度，nil 时沿用服务端默认
    ///   - maxTokens: 生成最大 token 数，nil 时沿用服务端默认
    public init(model: String, messages: [ChatMessage],
                temperature: Double? = nil, maxTokens: Int? = nil) {
        self.model = model
        self.messages = messages
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case maxTokens = "max_tokens"
    }
}

/// 完成原因
public enum FinishReason: String, Sendable, Codable {
    case stop, length, contentFilter = "content_filter", toolCalls = "tool_calls"
}

/// 流式 chunk（delta 为增量文本，finishReason 仅在最后一个 chunk 非 nil）
/// 不声明 Codable：仅由 SSE 解码器生产，不会作为整体通过网络发送
public struct ChatChunk: Sendable, Equatable {
    public let delta: String
    public let finishReason: FinishReason?

    /// 构造流式响应块
    /// - Parameters:
    ///   - delta: 本次增量文本
    ///   - finishReason: 仅最后一个 chunk 非 nil，其他 chunk 保持 nil
    public init(delta: String, finishReason: FinishReason? = nil) {
        self.delta = delta
        self.finishReason = finishReason
    }
}
