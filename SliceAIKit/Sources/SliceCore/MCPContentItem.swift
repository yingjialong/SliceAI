import Foundation

/// MCP tool result 中的 content item，使用 MCP type discriminator wire shape。
public enum MCPContentItem: Sendable, Equatable, Codable {
    case text(String)
    case image(data: String, mimeType: String)
    case resourceLink(uri: String, name: String?, mimeType: String?)
    case embeddedResource(uri: String, text: String?, blob: String?, mimeType: String?)

    private enum CodingKeys: String, CodingKey {
        case type
        case text
        case data
        case uri
        case name
        case blob
        case mimeType
        case resource
    }

    private enum ItemType: String, Codable {
        case text
        case image
        case resourceLink = "resource_link"
        case embeddedResource = "resource"
    }

    private struct EmbeddedResourceRepr: Codable, Equatable {
        let uri: String
        let text: String?
        let blob: String?
        let mimeType: String?
    }

    /// 从 MCP content item JSON 解码，未知 type 直接拒绝。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(ItemType.self, forKey: .type)
        switch type {
        case .text:
            self = .text(try container.decode(String.self, forKey: .text))
        case .image:
            self = .image(
                data: try container.decode(String.self, forKey: .data),
                mimeType: try container.decode(String.self, forKey: .mimeType)
            )
        case .resourceLink:
            // public case 中 name 保持 optional，是为了遵守 SliceCore Task 1 计划里的宽松值类型形状；
            // 但 MCP 2025-06-18 wire schema 要求 resource_link.name 必填，因此解码 wire 时必须强制存在。
            self = .resourceLink(
                uri: try container.decode(String.self, forKey: .uri),
                name: try container.decode(String.self, forKey: .name),
                mimeType: try container.decodeIfPresent(String.self, forKey: .mimeType)
            )
        case .embeddedResource:
            let resource = try container.decode(EmbeddedResourceRepr.self, forKey: .resource)
            try Self.validateEmbeddedResourceUnion(
                text: resource.text,
                blob: resource.blob,
                codingPath: container.codingPath + [CodingKeys.resource]
            )
            self = .embeddedResource(
                uri: resource.uri,
                text: resource.text,
                blob: resource.blob,
                mimeType: resource.mimeType
            )
        }
    }

    /// 编码为 MCP content item JSON，nil 可选字段按 Foundation 默认语义省略。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(ItemType.text, forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let data, let mimeType):
            try container.encode(ItemType.image, forKey: .type)
            try container.encode(data, forKey: .data)
            try container.encode(mimeType, forKey: .mimeType)
        case .resourceLink(let uri, let name, let mimeType):
            try container.encode(ItemType.resourceLink, forKey: .type)
            guard let name else {
                let context = EncodingError.Context(
                    codingPath: container.codingPath + [CodingKeys.name],
                    debugDescription: "MCP resource_link requires name on the wire"
                )
                throw EncodingError.invalidValue(self, context)
            }
            try container.encode(uri, forKey: .uri)
            // public optional 仅保留值类型宽松性；wire encoding 必须输出 required name。
            try container.encode(name, forKey: .name)
            try container.encodeIfPresent(mimeType, forKey: .mimeType)
        case .embeddedResource(let uri, let text, let blob, let mimeType):
            try container.encode(ItemType.embeddedResource, forKey: .type)
            try Self.validateEmbeddedResourceUnionForEncoding(
                text: text,
                blob: blob,
                value: self,
                codingPath: container.codingPath + [CodingKeys.resource]
            )
            let resource = EmbeddedResourceRepr(
                uri: uri,
                text: text,
                blob: blob,
                mimeType: mimeType
            )
            try container.encode(resource, forKey: .resource)
        }
    }

    /// 校验 embedded resource 的 MCP union：text/blob 必须恰好出现一个。
    private static func validateEmbeddedResourceUnion(
        text: String?,
        blob: String?,
        codingPath: [any CodingKey]
    ) throws {
        guard (text == nil) != (blob == nil) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: codingPath,
                debugDescription: "MCP embedded resource requires exactly one of text or blob"
            ))
        }
    }

    /// 编码前校验 embedded resource 的 MCP union，避免输出非法 wire JSON。
    private static func validateEmbeddedResourceUnionForEncoding(
        text: String?,
        blob: String?,
        value: MCPContentItem,
        codingPath: [any CodingKey]
    ) throws {
        guard (text == nil) != (blob == nil) else {
            let context = EncodingError.Context(
                codingPath: codingPath,
                debugDescription: "MCP embedded resource requires exactly one of text or blob"
            )
            throw EncodingError.invalidValue(value, context)
        }
    }
}

/// MCP tool call 结果；同时承载 content 与可选结构化 JSON 结果。
public struct MCPCallResult: Sendable, Equatable, Codable {
    public let content: [MCPContentItem]
    public let structuredContent: MCPJSONValue?
    public let isError: Bool
    public let meta: MCPJSONValue.Object?

    private enum CodingKeys: String, CodingKey {
        case content
        case structuredContent
        case isError
        case meta = "_meta"
    }

    /// 构造 MCPCallResult。
    public init(
        content: [MCPContentItem],
        structuredContent: MCPJSONValue?,
        isError: Bool,
        meta: MCPJSONValue.Object?
    ) {
        self.content = content
        self.structuredContent = structuredContent
        self.isError = isError
        self.meta = meta
    }
}
