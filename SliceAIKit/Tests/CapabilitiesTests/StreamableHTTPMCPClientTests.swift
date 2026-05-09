import Foundation
import SliceCore
import XCTest
@testable import Capabilities

/// Streamable HTTP MCP client 行为测试。
final class StreamableHTTPMCPClientTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        HTTPMCPURLProtocol.reset()
    }

    /// initialize 请求必须使用 POST、JSON body，并声明 application/json + text/event-stream。
    func test_streamableHTTP_initializePostsJSONRPCWithAcceptHeader() async throws {
        let descriptor = streamableDescriptor(id: "http-init")
        let recorder = HTTPMCPRequestRecorder(responses: [
            jsonResponse(for: descriptor.url!, body: initializeBody(), headers: ["Mcp-Session-Id": "session-1"]),
            acceptedResponse(for: descriptor.url!),
            jsonResponse(for: descriptor.url!, body: toolsListBody(id: 2))
        ])
        HTTPMCPURLProtocol.install(recorder: recorder)
        let client = StreamableHTTPMCPClient(descriptors: { [descriptor] }, session: URLSession.mcpMocked())

        _ = try await client.tools(for: descriptor)
        let first = try XCTUnwrap(recorder.requests.first)
        let body = try requestBodyObject(first)

        XCTAssertEqual(first.httpMethod, "POST")
        XCTAssertEqual(first.url, descriptor.url)
        XCTAssertEqual(first.value(forHTTPHeaderField: "Accept"), "application/json, text/event-stream")
        XCTAssertTrue(first.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("application/json") == true)
        XCTAssertNil(first.value(forHTTPHeaderField: "Mcp-Session-Id"))
        XCTAssertNil(first.value(forHTTPHeaderField: "MCP-Protocol-Version"))
        XCTAssertEqual(body["method"] as? String, "initialize")
    }

    /// initialize 返回 session id 后，后续 initialized notification / tools/list 都必须携带 session 与协议版本。
    func test_streamableHTTP_usesSessionIDOnSubsequentRequests() async throws {
        let descriptor = streamableDescriptor(id: "http-session")
        let recorder = HTTPMCPRequestRecorder(responses: [
            jsonResponse(for: descriptor.url!, body: initializeBody(), headers: ["Mcp-Session-Id": "session-2"]),
            acceptedResponse(for: descriptor.url!),
            jsonResponse(for: descriptor.url!, body: toolsListBody(id: 2))
        ])
        HTTPMCPURLProtocol.install(recorder: recorder)
        let client = StreamableHTTPMCPClient(descriptors: { [descriptor] }, session: URLSession.mcpMocked())

        _ = try await client.tools(for: descriptor)
        XCTAssertGreaterThanOrEqual(recorder.requests.count, 3)
        let initialized = recorder.requests[1]
        let toolsList = recorder.requests[2]

        XCTAssertEqual(initialized.value(forHTTPHeaderField: "Mcp-Session-Id"), "session-2")
        XCTAssertEqual(initialized.value(forHTTPHeaderField: "MCP-Protocol-Version"), "2025-06-18")
        XCTAssertEqual(toolsList.value(forHTTPHeaderField: "Mcp-Session-Id"), "session-2")
        XCTAssertEqual(toolsList.value(forHTTPHeaderField: "MCP-Protocol-Version"), "2025-06-18")
    }

    /// tools/call 必须接受 application/json JSON-RPC response，并解码为 MCPCallResult。
    func test_streamableHTTP_toolsCallAcceptsApplicationJSONResponse() async throws {
        let descriptor = streamableDescriptor(id: "http-json")
        let ref = MCPToolRef(server: descriptor.id, tool: "search")
        let recorder = HTTPMCPRequestRecorder(responses: [
            jsonResponse(for: descriptor.url!, body: initializeBody(), headers: ["Mcp-Session-Id": "session-3"]),
            acceptedResponse(for: descriptor.url!),
            jsonResponse(for: descriptor.url!, body: toolsListBody(id: 2)),
            jsonResponse(for: descriptor.url!, body: toolCallBody(id: 3, text: "json ok"))
        ])
        HTTPMCPURLProtocol.install(recorder: recorder)
        let client = StreamableHTTPMCPClient(descriptors: { [descriptor] }, session: URLSession.mcpMocked())

        let args: MCPJSONValue.Object = ["query": .string("SliceAI")]
        let result = try await client.call(ref: ref, args: args)
        let callRequest = try XCTUnwrap(recorder.requests.last)
        let callBody = try requestBodyObject(callRequest)

        XCTAssertEqual(result, MCPCallResult(content: [.text("json ok")], structuredContent: nil, isError: false, meta: nil))
        XCTAssertEqual(callBody["method"] as? String, "tools/call")
        XCTAssertEqual(callRequest.value(forHTTPHeaderField: "Mcp-Session-Id"), "session-3")
    }

    /// tools/call 必须接受 text/event-stream response，并从 SSE data 中取出匹配 id 的 JSON-RPC response。
    func test_streamableHTTP_toolsCallAcceptsTextEventStreamResponse() async throws {
        let descriptor = streamableDescriptor(id: "http-sse")
        let ref = MCPToolRef(server: descriptor.id, tool: "search")
        let recorder = HTTPMCPRequestRecorder(responses: [
            jsonResponse(for: descriptor.url!, body: initializeBody(), headers: ["Mcp-Session-Id": "session-4"]),
            acceptedResponse(for: descriptor.url!),
            jsonResponse(for: descriptor.url!, body: toolsListBody(id: 2)),
            sseResponse(for: descriptor.url!, body: toolCallBody(id: 3, text: "sse ok"))
        ])
        HTTPMCPURLProtocol.install(recorder: recorder)
        let client = StreamableHTTPMCPClient(descriptors: { [descriptor] }, session: URLSession.mcpMocked())

        let args: MCPJSONValue.Object = ["query": .string("SliceAI")]
        let result = try await client.call(ref: ref, args: args)

        XCTAssertEqual(result, MCPCallResult(content: [.text("sse ok")], structuredContent: nil, isError: false, meta: nil))
    }

    /// Streamable HTTP descriptor 必须显式配置 URL。
    func test_streamableHTTP_rejectsMissingURL() async throws {
        let descriptor = MCPDescriptor(
            id: "missing-url",
            transport: .streamableHTTP,
            command: nil,
            args: nil,
            url: nil,
            env: nil,
            capabilities: [.tools(["search"])],
            provenance: .firstParty
        )
        let client = StreamableHTTPMCPClient(descriptors: { [descriptor] }, session: URLSession.mcpMocked())

        do {
            _ = try await client.tools(for: descriptor)
            XCTFail("expected transportFailed for missing URL")
        } catch MCPClientError.transportFailed {
            // 预期错误：reason 会被 developerContext 脱敏，测试不依赖具体文案。
        } catch {
            XCTFail("expected MCPClientError.transportFailed, got \(error)")
        }
    }

    /// 非 localhost 的明文 HTTP URL 必须拒绝，降低本地网络被静默调用的风险。
    func test_streamableHTTP_rejectsNonLocalPlainHTTPURL() async throws {
        let descriptor = streamableDescriptor(id: "plain-http", url: URL(string: "http://192.168.1.10/mcp")!)
        let client = StreamableHTTPMCPClient(descriptors: { [descriptor] }, session: URLSession.mcpMocked())

        do {
            _ = try await client.tools(for: descriptor)
            XCTFail("expected transportFailed for non-local plain HTTP")
        } catch MCPClientError.transportFailed {
            // 预期错误：reason 会被 developerContext 脱敏，测试不依赖具体文案。
        } catch {
            XCTFail("expected MCPClientError.transportFailed, got \(error)")
        }
    }

    /// 构造 streamable HTTP descriptor fixture。
    private func streamableDescriptor(
        id: String,
        url: URL = URL(string: "https://mcp.example.com/mcp")!
    ) -> MCPDescriptor {
        MCPDescriptor(
            id: id,
            transport: .streamableHTTP,
            command: nil,
            args: nil,
            url: url,
            env: nil,
            capabilities: [.tools(["search"])],
            provenance: .firstParty
        )
    }

    /// 构造 initialize JSON-RPC response body。
    private func initializeBody(id: Int = 1) -> String {
        """
        {"jsonrpc":"2.0","id":\(id),"result":{"protocolVersion":"2025-06-18","capabilities":{},"serverInfo":{"name":"test","version":"1.0.0"}}}
        """
    }

    /// 构造 tools/list JSON-RPC response body。
    private func toolsListBody(id: Int) -> String {
        """
        {"jsonrpc":"2.0","id":\(id),"result":{"tools":[{"name":"search","title":"Search","description":"Search tool","inputSchema":{"type":"object"}}]}}
        """
    }

    /// 构造 tools/call JSON-RPC response body。
    private func toolCallBody(id: Int, text: String) -> String {
        """
        {"jsonrpc":"2.0","id":\(id),"result":{"content":[{"type":"text","text":"\(text)"}],"isError":false}}
        """
    }

    /// 构造 application/json HTTP response fixture。
    private func jsonResponse(
        for url: URL,
        body: String,
        headers: [String: String] = [:]
    ) -> HTTPMCPStubResponse {
        var headerFields = ["Content-Type": "application/json"]
        for (key, value) in headers {
            headerFields[key] = value
        }
        return HTTPMCPStubResponse(
            response: HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headerFields)!,
            data: Data(body.utf8)
        )
    }

    /// 构造 notification accepted HTTP response fixture。
    private func acceptedResponse(for url: URL) -> HTTPMCPStubResponse {
        HTTPMCPStubResponse(
            response: HTTPURLResponse(url: url, statusCode: 202, httpVersion: nil, headerFields: [:])!,
            data: Data()
        )
    }

    /// 构造 text/event-stream HTTP response fixture。
    private func sseResponse(for url: URL, body: String) -> HTTPMCPStubResponse {
        let event = "event: message\ndata: \(body)\n\n"
        return HTTPMCPStubResponse(
            response: HTTPURLResponse(
                url: url,
                statusCode: 200,
                httpVersion: nil,
                headerFields: ["Content-Type": "text/event-stream"]
            )!,
            data: Data(event.utf8)
        )
    }

    /// 从 URLProtocol 捕获的 request 中读取 JSON body。
    private func requestBodyObject(_ request: URLRequest) throws -> [String: Any] {
        let data: Data
        if let httpBody = request.httpBody {
            data = httpBody
        } else {
            data = try Data(reading: request.httpBodyStream)
        }
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }
}

/// URLProtocol 回放的 HTTP response。
private struct HTTPMCPStubResponse {
    let response: HTTPURLResponse
    let data: Data
}

/// 线程安全记录 URLProtocol 捕获到的 request，并按顺序回放 response。
private final class HTTPMCPRequestRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private let responses: [HTTPMCPStubResponse]
    private var index = 0
    private var capturedRequests: [URLRequest] = []

    /// 构造 request recorder。
    /// - Parameter responses: 按请求顺序回放的响应。
    init(responses: [HTTPMCPStubResponse]) {
        self.responses = responses
    }

    /// 已捕获的 request 快照。
    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return capturedRequests
    }

    /// 记录请求并返回下一组响应。
    /// - Parameter request: URLProtocol 捕获的请求。
    /// - Returns: 按顺序取出的响应；超出范围视为测试配置错误。
    func handle(_ request: URLRequest) throws -> HTTPMCPStubResponse {
        lock.lock()
        defer { lock.unlock() }
        capturedRequests.append(request)
        guard index < responses.count else {
            throw URLError(.badServerResponse)
        }
        let response = responses[index]
        index += 1
        return response
    }
}

/// Streamable HTTP 测试专用 URLProtocol。
private final class HTTPMCPURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var recorder: HTTPMCPRequestRecorder?

    /// 安装 recorder。
    /// - Parameter recorder: 当前测试用 request recorder。
    static func install(recorder: HTTPMCPRequestRecorder) {
        self.recorder = recorder
    }

    /// 清理全局 recorder，避免测试间污染。
    static func reset() {
        recorder = nil
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let recorder = Self.recorder else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let stub = try recorder.handle(request)
            client?.urlProtocol(self, didReceive: stub.response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: stub.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private extension URLSession {
    /// 构造使用 HTTPMCPURLProtocol 的测试 URLSession。
    static func mcpMocked() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [HTTPMCPURLProtocol.self]
        return URLSession(configuration: configuration)
    }
}

private extension Data {
    /// 从 InputStream 读取 Data，兼容 URLSession 把 httpBody 转为 body stream 的情况。
    init(reading stream: InputStream?) throws {
        guard let stream else {
            self = Data()
            return
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 1024
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let count = stream.read(buffer, maxLength: bufferSize)
            if count < 0 {
                throw stream.streamError ?? URLError(.cannotDecodeRawData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        self = data
    }
}
