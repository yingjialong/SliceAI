import Foundation
import SliceCore

/// MCP newline-delimited JSON-RPC request。
public struct MCPJSONRPCRequest: Sendable, Equatable, Encodable {
    public let jsonrpc: String
    public let id: Int?
    public let method: String
    public let params: MCPJSONValue?

    private enum CodingKeys: String, CodingKey {
        case jsonrpc
        case id
        case method
        case params
    }

    /// 构造 JSON-RPC request；`id == nil` 时按 notification 编码。
    public init(id: Int?, method: String, params: MCPJSONValue? = nil) {
        self.jsonrpc = "2.0"
        self.id = id
        self.method = method
        self.params = params
    }

    /// 编码 request，notification 不输出 `id`，无 params 时不输出 `params`。
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(jsonrpc, forKey: .jsonrpc)
        try container.encodeIfPresent(id, forKey: .id)
        try container.encode(method, forKey: .method)
        try container.encodeIfPresent(params, forKey: .params)
    }
}

/// MCP JSON-RPC error object。
public struct MCPJSONRPCError: Sendable, Equatable, Codable {
    public let code: Int
    public let message: String
    public let data: MCPJSONValue?

    /// 构造 JSON-RPC error object。
    public init(code: Int, message: String, data: MCPJSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

/// MCP JSON-RPC response；`result` 与 `error` 只允许消费方二选一处理。
public struct MCPJSONRPCResponse<Result: Decodable & Sendable>: Sendable, Decodable {
    public let jsonrpc: String
    public let id: Int?
    public let result: Result?
    public let error: MCPJSONRPCError?

    /// 返回 result；若 response 携带 JSON-RPC error，则转换为 `MCPClientError.protocolError`。
    public func resultOrThrow() throws -> Result {
        if let error {
            throw MCPClientError.protocolError(code: error.code, message: error.message)
        }
        guard let result else {
            throw MCPClientError.decodingFailed(reason: "JSON-RPC response missing result and error")
        }
        return result
    }
}

/// tools/list result。
public struct MCPToolsListResult: Sendable, Equatable, Decodable {
    public let tools: [MCPToolListItem]

    /// 构造 tools/list result。
    public init(tools: [MCPToolListItem]) {
        self.tools = tools
    }
}

/// tools/list 中单个 MCP tool 的 wire DTO。
public struct MCPToolListItem: Sendable, Equatable, Decodable {
    public let name: String
    public let title: String?
    public let description: String?
    public let inputSchema: MCPJSONValue.Object

    /// 构造 tool list item。
    public init(
        name: String,
        title: String?,
        description: String?,
        inputSchema: MCPJSONValue.Object
    ) {
        self.name = name
        self.title = title
        self.description = description
        self.inputSchema = inputSchema
    }

    /// 转换为 SliceCore canonical tool descriptor。
    public func descriptor(serverID: String) -> MCPToolDescriptor {
        MCPToolDescriptor(
            ref: MCPToolRef(server: serverID, tool: name),
            title: title ?? name,
            description: description,
            inputSchema: inputSchema
        )
    }
}

/// initialize result；M1 只需要确认响应可解码，不消费具体能力字段。
public struct MCPInitializeResult: Sendable, Decodable {
    public let protocolVersion: String
    public let capabilities: MCPJSONValue.Object
    public let serverInfo: MCPJSONValue.Object?

    /// 构造 initialize result。
    public init(
        protocolVersion: String,
        capabilities: MCPJSONValue.Object,
        serverInfo: MCPJSONValue.Object?
    ) {
        self.protocolVersion = protocolVersion
        self.capabilities = capabilities
        self.serverInfo = serverInfo
    }
}
