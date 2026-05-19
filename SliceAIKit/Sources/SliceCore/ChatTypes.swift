import Foundation

/// 角色，对应 OpenAI Chat Completions 的 role 字段
public enum Role: String, Sendable, Codable {
    case system, user, assistant, tool
}

/// 单条消息
public struct ChatMessage: Sendable, Codable, Equatable {
    public let role: Role
    public let content: String?
    public let reasoningContent: String?
    public let toolCallID: String?
    public let toolCalls: [ChatToolCall]?

    /// 构造聊天消息
    /// - Parameters:
    ///   - role: 消息角色（system/user/assistant）
    ///   - content: 消息文本内容
    public init(role: Role, content: String) {
        self.role = role
        self.content = content
        self.reasoningContent = nil
        self.toolCallID = nil
        self.toolCalls = nil
    }

    /// 构造完整聊天消息，支持 assistant tool_calls 与 tool result 消息。
    /// - Parameters:
    ///   - role: 消息角色。
    ///   - content: 消息文本内容；tool-call assistant 消息可为 nil。
    ///   - toolCallID: OpenAI-compatible tool result 的 provider tool_call_id。
    ///   - toolCalls: assistant 消息携带的工具调用列表。
    public init(
        role: Role,
        content: String?,
        toolCallID: String?,
        toolCalls: [ChatToolCall]?,
        reasoningContent: String? = nil
    ) {
        self.role = role
        self.content = content
        self.reasoningContent = reasoningContent
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }

    private enum CodingKeys: String, CodingKey {
        case role, content
        case reasoningContent = "reasoning_content"
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }
}

/// OpenAI-compatible function tool 定义。
public struct ChatTool: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: MCPJSONValue.Object

    /// 构造 tool calling 使用的 function tool。
    /// - Parameters:
    ///   - name: 模型可调用的工具名。
    ///   - description: 工具说明。
    ///   - inputSchema: MCP tools/list 暴露的 JSON Schema。
    public init(name: String, description: String, inputSchema: MCPJSONValue.Object) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
    }

    /// 编码为 OpenAI-compatible `tools[]` 的 function 形状。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode("function", forKey: .type)
        try container.encode(FunctionPayload(
            name: name,
            description: description,
            parameters: inputSchema
        ), forKey: .function)
    }

    /// 从 OpenAI-compatible function tool 形状解码。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(String.self, forKey: .type)
        guard type == "function" else {
            throw DecodingError.dataCorruptedError(
                forKey: .type,
                in: container,
                debugDescription: "ChatTool only supports function tools"
            )
        }
        let function = try container.decode(FunctionPayload.self, forKey: .function)
        self.name = function.name
        self.description = function.description
        self.inputSchema = function.parameters
    }

    private enum CodingKeys: String, CodingKey {
        case type, function
    }

    private struct FunctionPayload: Sendable, Codable, Equatable {
        let name: String
        let description: String
        let parameters: MCPJSONValue.Object
    }
}

/// Tool calling 的工具选择策略。
public enum ChatToolChoice: String, Sendable, Codable, Equatable {
    case auto, none, required
}

/// 带 tools/tool_choice 的聊天请求。
public struct ChatToolRequest: Sendable, Codable, Equatable {
    public let model: String
    public let messages: [ChatMessage]
    public let tools: [ChatTool]
    public let toolChoice: ChatToolChoice?
    public let temperature: Double?
    public let maxTokens: Int?

    /// 构造 tool calling 请求。
    /// - Parameters:
    ///   - model: 模型标识。
    ///   - messages: 对话消息。
    ///   - tools: 模型可调用的工具列表。
    ///   - toolChoice: 工具选择策略；nil 时沿用服务端默认。
    ///   - temperature: 采样温度；nil 时沿用服务端默认。
    ///   - maxTokens: 最大输出 token；nil 时沿用服务端默认。
    public init(
        model: String,
        messages: [ChatMessage],
        tools: [ChatTool],
        toolChoice: ChatToolChoice? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.messages = messages
        self.tools = tools
        self.toolChoice = toolChoice
        self.temperature = temperature
        self.maxTokens = maxTokens
    }

    /// 编码为 OpenAI-compatible chat/completions 请求。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        if !tools.isEmpty {
            try container.encode(tools, forKey: .tools)
            try container.encodeIfPresent(toolChoice, forKey: .toolChoice)
        }
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
    }

    /// 从 JSON 解码 tool chat 请求，缺省 tools 时按无工具请求处理。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let decodedTools = try container.decodeIfPresent([ChatTool].self, forKey: .tools) ?? []
        self.model = try container.decode(String.self, forKey: .model)
        self.messages = try container.decode([ChatMessage].self, forKey: .messages)
        self.tools = decodedTools
        self.toolChoice = decodedTools.isEmpty
            ? nil
            : try container.decodeIfPresent(ChatToolChoice.self, forKey: .toolChoice)
        self.temperature = try container.decodeIfPresent(Double.self, forKey: .temperature)
        self.maxTokens = try container.decodeIfPresent(Int.self, forKey: .maxTokens)
    }

    private enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature
        case toolChoice = "tool_choice"
        case maxTokens = "max_tokens"
    }
}

/// 模型完成的一次工具调用。
public struct ChatToolCall: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let argumentsRaw: String
    public let arguments: MCPJSONValue.Object?

    /// 构造完整工具调用。
    /// - Parameters:
    ///   - id: provider 返回的 tool_call_id。
    ///   - name: function tool 名称。
    ///   - argumentsRaw: provider 输出的原始 arguments JSON 字符串。
    ///   - arguments: 解析后的 JSON object；nil 表示 malformed 或非 object。
    public init(
        id: String,
        name: String,
        argumentsRaw: String,
        arguments: MCPJSONValue.Object? = nil
    ) {
        self.id = id
        self.name = name
        self.argumentsRaw = argumentsRaw
        self.arguments = arguments ?? Self.parseArgumentsObject(argumentsRaw)
    }

    /// 编码为 OpenAI-compatible assistant `tool_calls[]` 形状。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode("function", forKey: .type)
        try container.encode(FunctionPayload(name: name, arguments: argumentsRaw), forKey: .function)
    }

    /// 从 OpenAI-compatible assistant `tool_calls[]` 形状解码。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(String.self, forKey: .id)
        let function = try container.decode(FunctionPayload.self, forKey: .function)
        self.name = function.name
        self.argumentsRaw = function.arguments
        self.arguments = Self.parseArgumentsObject(function.arguments)
    }

    private enum CodingKeys: String, CodingKey {
        case id, type, function
    }

    private struct FunctionPayload: Sendable, Codable, Equatable {
        let name: String
        let arguments: String
    }

    /// 将 raw arguments 尝试解析为 JSON object。
    /// - Parameter raw: 模型输出的 arguments 原始字符串。
    /// - Returns: 解析成功的 object；失败或非 object 时返回 nil。
    private static func parseArgumentsObject(_ raw: String) -> MCPJSONValue.Object? {
        guard let data = raw.data(using: .utf8),
              let value = try? JSONDecoder().decode(MCPJSONValue.self, from: data),
              case .object(let object) = value else {
            return nil
        }
        return object
    }
}

/// 流式工具调用增量。
public struct ChatToolCallDelta: Sendable, Equatable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let argumentsDelta: String

    /// 构造工具调用增量。
    /// - Parameters:
    ///   - index: OpenAI delta.tool_calls 的稳定索引。
    ///   - id: provider tool_call_id；通常只在首片出现。
    ///   - name: function tool 名；通常只在首片出现。
    ///   - argumentsDelta: 本片 arguments 字符串增量。
    public init(index: Int, id: String?, name: String?, argumentsDelta: String) {
        self.index = index
        self.id = id
        self.name = name
        self.argumentsDelta = argumentsDelta
    }
}

/// Tool calling 流式事件。
public enum ChatStreamEvent: Sendable, Equatable {
    case reasoningDelta(String)
    case textDelta(String)
    case toolCallDelta(ChatToolCallDelta)
    case finished(FinishReason)
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
