import Foundation

/// MCP tools/list 中单个 tool 的 SliceCore 值类型描述。
public struct MCPToolDescriptor: Sendable, Equatable, Codable {
    public let ref: MCPToolRef
    public let title: String
    public let description: String?
    public let inputSchema: MCPJSONValue.Object

    /// 构造 MCPToolDescriptor。
    public init(
        ref: MCPToolRef,
        title: String,
        description: String?,
        inputSchema: MCPJSONValue.Object
    ) {
        self.ref = ref
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
    }
}
