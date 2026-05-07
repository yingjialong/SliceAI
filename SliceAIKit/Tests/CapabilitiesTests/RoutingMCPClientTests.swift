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

    /// M4 前远程 descriptor 必须 fail-fast，不能静默 fallback 到 stdio 或 mock remote。
    func test_routingClient_rejectsUnsupportedRemoteTransportBeforeM4() async throws {
        let streamable = remoteDescriptor(id: "remote-http", transport: .streamableHTTP)
        let sse = remoteDescriptor(id: "remote-sse", transport: .sse)
        let websocket = remoteDescriptor(id: "remote-ws", transport: .websocket)
        let routing = RoutingMCPClient(
            descriptors: { [streamable, sse, websocket] },
            stdio: MockMCPClient()
        )

        try await assertUnsupportedTools(routing, descriptor: streamable, transport: .streamableHTTP)
        try await assertUnsupportedCall(routing, ref: MCPToolRef(server: sse.id, tool: "echo"), transport: .sse)
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
