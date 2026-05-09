import Foundation
import SliceCore

/// MCP client facade：按 descriptor transport 路由到具体 transport client。
public actor RoutingMCPClient: MCPClientProtocol {
    private let descriptors: @Sendable () async throws -> [MCPDescriptor]
    private let stdio: any MCPClientProtocol
    private let streamableHTTP: (any MCPClientProtocol)?

    /// 构造 routing MCP client；当前阶段启用 stdio 与 Streamable HTTP，deprecated SSE 继续拒绝。
    public init(
        descriptors: @escaping @Sendable () async throws -> [MCPDescriptor],
        stdio: any MCPClientProtocol,
        streamableHTTP: (any MCPClientProtocol)? = nil
    ) {
        self.descriptors = descriptors
        self.stdio = stdio
        self.streamableHTTP = streamableHTTP
    }

    /// 查询工具列表；按 descriptor transport 委托给具体 client。
    public func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolDescriptor] {
        switch descriptor.transport {
        case .stdio:
            return try await stdio.tools(for: descriptor)
        case .streamableHTTP:
            guard let streamableHTTP else {
                throw MCPClientError.unsupportedTransport(.streamableHTTP)
            }
            return try await streamableHTTP.tools(for: descriptor)
        case .sse:
            throw MCPClientError.unsupportedTransport(.sse)
        case .websocket:
            throw MCPClientError.unsupportedTransport(.websocket)
        }
    }

    /// 按 ref.server 解析 descriptor，再把 tool call 委托给对应 transport client。
    public func call(ref: MCPToolRef, args: MCPJSONValue.Object) async throws -> MCPCallResult {
        let descriptor = try await descriptor(for: ref)
        switch descriptor.transport {
        case .stdio:
            return try await stdio.call(ref: ref, args: args)
        case .streamableHTTP:
            guard let streamableHTTP else {
                throw MCPClientError.unsupportedTransport(.streamableHTTP)
            }
            return try await streamableHTTP.call(ref: ref, args: args)
        case .sse:
            throw MCPClientError.unsupportedTransport(.sse)
        case .websocket:
            throw MCPClientError.unsupportedTransport(.websocket)
        }
    }

    /// 从 descriptors provider 中解析 ref.server 对应的 descriptor。
    private func descriptor(for ref: MCPToolRef) async throws -> MCPDescriptor {
        let availableDescriptors = try await descriptors()
        guard let descriptor = availableDescriptors.first(where: { $0.id == ref.server }) else {
            throw MCPClientError.toolNotFound(ref: ref)
        }
        return descriptor
    }
}
