import Foundation

/// MCP 任意 JSON 值；用于 tool 参数、结构化结果和日志摘要。
public enum MCPJSONValue: Sendable, Equatable, Codable {
    public typealias Object = [String: MCPJSONValue]

    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([MCPJSONValue])
    case object(Object)

    /// 从 decoder 读取透明 raw JSON，而不是 Swift enum wrapper。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
            return
        }
        if let value = try? container.decode(Bool.self) {
            self = .bool(value)
            return
        }
        if let value = try? container.decode(Double.self) {
            self = .number(value)
            return
        }
        if let value = try? container.decode(String.self) {
            self = .string(value)
            return
        }
        if let value = try? container.decode([MCPJSONValue].self) {
            self = .array(value)
            return
        }
        if let value = try? container.decode(Object.self) {
            self = .object(value)
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: container.codingPath,
            debugDescription: "MCPJSONValue encountered unsupported JSON value"
        ))
    }

    /// 编码为透明 raw JSON，而不是 Swift enum wrapper。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    /// 只渲染字符串叶子中的 PromptTemplate 变量，占位形状保持不变。
    public func renderingStringLeaves(variables: [String: String]) -> MCPJSONValue {
        switch self {
        case .string(let value):
            return .string(PromptTemplate.render(value, variables: variables))
        case .array(let values):
            return .array(values.map { $0.renderingStringLeaves(variables: variables) })
        case .object(let object):
            return .object(object.mapValues { $0.renderingStringLeaves(variables: variables) })
        case .null, .bool, .number:
            return self
        }
    }

    /// 生成适合日志/错误展示的摘要，并对 secret-like key 做脱敏。
    public func redactedSummary(maxCharacters: Int) -> String {
        guard maxCharacters > 0 else { return "" }

        let redacted = redactingSecretLikeObjectValues()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]

        let data = (try? encoder.encode(redacted)) ?? Data()
        let summary = String(data: data, encoding: .utf8) ?? ""
        guard summary.count > maxCharacters else { return summary }
        return String(summary.prefix(maxCharacters))
    }

    /// 递归脱敏对象中 secret-like key 的值。
    private func redactingSecretLikeObjectValues() -> MCPJSONValue {
        switch self {
        case .array(let values):
            return .array(values.map { $0.redactingSecretLikeObjectValues() })
        case .object(let object):
            var redacted: Object = [:]
            for (key, value) in object {
                if Self.isSecretLikeKey(key) {
                    redacted[key] = .string("<redacted>")
                } else {
                    redacted[key] = value.redactingSecretLikeObjectValues()
                }
            }
            return .object(redacted)
        case .null, .bool, .number, .string:
            return self
        }
    }

    /// 判断对象字段名是否类似 secret，匹配采用大小写不敏感规则。
    private static func isSecretLikeKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("token")
            || normalized.contains("secret")
            || normalized.contains("password")
            || normalized.contains("apikey")
            || normalized.contains("api_key")
            || normalized.contains("authorization")
            || normalized.contains("credential")
    }
}
