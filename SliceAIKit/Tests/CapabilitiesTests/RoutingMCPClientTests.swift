import Foundation
import SliceCore
import XCTest
@testable import Capabilities

/// RoutingMCPClient 的 transport 边界测试。
final class RoutingMCPClientTests: XCTestCase {

    /// stdio descriptor 应委托给注入的 stdio client，不让上层执行器直接 switch transport。
    func test_routingClient_routesStdioDescriptorToStdioClient() async throws {
        let descriptor = stdioDescriptor()
        let ref = MCPToolRef(server: descriptor.id, tool: "echo")
        let tool = MCPToolDescriptor(
            ref: ref,
            title: "echo",
            description: nil,
            inputSchema: ["type": .string("object")]
        )
        let response = MCPCallResult(content: [.text("ok")], structuredContent: nil, isError: false, meta: nil)
        let stdio = MockMCPClient(tools: [descriptor: [tool]], responses: [ref: response])
        let routing = RoutingMCPClient(descriptors: { [descriptor] }, stdio: stdio)

        let tools = try await routing.tools(for: descriptor)
        let callResult = try await routing.call(ref: ref, args: ["query": .string("hi")])
        let lastToolsDescriptor = await stdio.lastToolsDescriptor
        let lastArguments = await stdio.lastArguments

        XCTAssertEqual(tools, [tool])
        XCTAssertEqual(callResult, response)
        XCTAssertEqual(lastToolsDescriptor, descriptor)
        XCTAssertEqual(lastArguments, ["query": .string("hi")])
    }

    /// streamable HTTP descriptor 应委托给注入的 HTTP client，不让上层执行器直接 switch transport。
    func test_routingClient_routesStreamableHTTPDescriptorToHTTPClient() async throws {
        let streamable = remoteDescriptor(id: "remote-http", transport: .streamableHTTP)
        let ref = MCPToolRef(server: streamable.id, tool: "echo")
        let tool = MCPToolDescriptor(
            ref: ref,
            title: "echo",
            description: nil,
            inputSchema: ["type": .string("object")]
        )
        let response = MCPCallResult(content: [.text("remote ok")], structuredContent: nil, isError: false, meta: nil)
        let http = MockMCPClient(tools: [streamable: [tool]], responses: [ref: response])
        let routing = RoutingMCPClient(
            descriptors: { [streamable] },
            stdio: MockMCPClient(),
            streamableHTTP: http
        )

        let tools = try await routing.tools(for: streamable)
        let callResult = try await routing.call(ref: ref, args: ["query": .string("hi")])
        let lastToolsDescriptor = await http.lastToolsDescriptor
        let lastArguments = await http.lastArguments

        XCTAssertEqual(tools, [tool])
        XCTAssertEqual(callResult, response)
        XCTAssertEqual(lastToolsDescriptor, streamable)
        XCTAssertEqual(lastArguments, ["query": .string("hi")])
    }

    /// deprecated SSE descriptor 必须继续 fail-fast，不能静默 fallback 到 Streamable HTTP。
    func test_routingClient_rejectsDeprecatedSSEDescriptor() async throws {
        let sse = remoteDescriptor(id: "remote-sse", transport: .sse)
        let routing = RoutingMCPClient(
            descriptors: { [sse] },
            stdio: MockMCPClient(),
            streamableHTTP: MockMCPClient()
        )

        try await assertUnsupportedTools(routing, descriptor: sse, transport: .sse)
        try await assertUnsupportedCall(routing, ref: MCPToolRef(server: sse.id, tool: "echo"), transport: .sse)
    }

    /// websocket 仍不在当前 milestone 支持范围内。
    func test_routingClient_rejectsUnsupportedWebSocketTransport() async throws {
        let websocket = remoteDescriptor(id: "remote-ws", transport: .websocket)
        let routing = RoutingMCPClient(
            descriptors: { [websocket] },
            stdio: MockMCPClient(),
            streamableHTTP: MockMCPClient()
        )

        try await assertUnsupportedTools(routing, descriptor: websocket, transport: .websocket)
    }

    /// 断言 tools(for:) 抛 unsupported transport。
    private func assertUnsupportedTools(
        _ routing: RoutingMCPClient,
        descriptor: MCPDescriptor,
        transport: MCPTransport
    ) async throws {
        do {
            _ = try await routing.tools(for: descriptor)
            XCTFail("expected unsupported transport")
        } catch let error as MCPClientError {
            XCTAssertEqual(error, .unsupportedTransport(transport))
        } catch {
            XCTFail("expected MCPClientError, got \(error)")
        }
    }

    /// 断言 call(ref:args:) 抛 unsupported transport。
    private func assertUnsupportedCall(
        _ routing: RoutingMCPClient,
        ref: MCPToolRef,
        transport: MCPTransport
    ) async throws {
        do {
            _ = try await routing.call(ref: ref, args: [:])
            XCTFail("expected unsupported transport")
        } catch let error as MCPClientError {
            XCTAssertEqual(error, .unsupportedTransport(transport))
        } catch {
            XCTFail("expected MCPClientError, got \(error)")
        }
    }

    /// 构造 stdio descriptor fixture。
    private func stdioDescriptor() -> MCPDescriptor {
        MCPDescriptor(
            id: "local",
            transport: .stdio,
            command: "/bin/echo",
            args: nil,
            url: nil,
            env: nil,
            capabilities: [.tools(["echo"])],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))
        )
    }

    /// 构造远程 descriptor fixture。
    private func remoteDescriptor(id: String, transport: MCPTransport) -> MCPDescriptor {
        MCPDescriptor(
            id: id,
            transport: transport,
            command: nil,
            args: nil,
            url: URL(string: "https://mcp.example.com/\(id)")!,
            env: nil,
            capabilities: [.tools(["echo"])],
            provenance: .firstParty
        )
    }
}
