import Foundation
import OSLog
import SliceCore

/// 基于 MCP Streamable HTTP transport 的 JSON-RPC client。
public final actor StreamableHTTPMCPClient: MCPClientProtocol {
    private let descriptors: @Sendable () async throws -> [MCPDescriptor]
    private let session: URLSession
    private let requestTimeoutNanoseconds: UInt64
    private let logger = Logger(subsystem: "SliceAIKit", category: "StreamableHTTPMCPClient")
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()
    private var sessions: [String: StreamableHTTPSession] = [:]
    private var sessionStartTasks: [String: Task<Void, any Error>] = [:]

    /// 构造 Streamable HTTP MCP client；HTTP session 会在首次调用对应 server 时 lazy initialize。
    public init(
        descriptors: @escaping @Sendable () async throws -> [MCPDescriptor],
        session: URLSession = .shared,
        requestTimeoutNanoseconds: UInt64 = 30 * 1_000_000_000
    ) {
        self.descriptors = descriptors
        self.session = session
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    /// 查询 Streamable HTTP MCP server 暴露的工具列表。
    public func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolDescriptor] {
        let state = try await sessionState(for: descriptor)
        return try await listToolsIfNeeded(state: state)
    }

    /// 调用 MCP tool；`isError == true` 的工具执行错误作为正常结果返回。
    public func call(ref: MCPToolRef, args: MCPJSONValue.Object) async throws -> MCPCallResult {
        let descriptor = try await descriptor(forServerID: ref.server)
        let state = try await sessionState(for: descriptor)
        let tools = try await listToolsIfNeeded(state: state)
        guard tools.contains(where: { $0.ref == ref }) else {
            throw MCPClientError.toolNotFound(ref: ref)
        }
        let params: MCPJSONValue = .object([
            "name": .string(ref.tool),
            "arguments": .object(args)
        ])
        let result: MCPCallResult = try await sendRequest(
            method: "tools/call",
            params: params,
            state: state
        )
        logger.debug("MCP streamable HTTP tools/call completed server=\(descriptor.id, privacy: .private)")
        return result
    }
}

private extension StreamableHTTPMCPClient {
    /// 按 server id 从 descriptors provider 解析 descriptor。
    func descriptor(forServerID serverID: String) async throws -> MCPDescriptor {
        let availableDescriptors = try await descriptors()
        guard let descriptor = availableDescriptors.first(where: { $0.id == serverID }) else {
            throw MCPClientError.toolNotFound(ref: MCPToolRef(server: serverID, tool: "<unknown>"))
        }
        return descriptor
    }

    /// 获取并初始化单个 server 的 HTTP 会话状态。
    func sessionState(for descriptor: MCPDescriptor) async throws -> StreamableHTTPSession {
        guard descriptor.transport == .streamableHTTP else {
            throw MCPClientError.unsupportedTransport(descriptor.transport)
        }
        let endpoint = try validatedEndpoint(for: descriptor)
        if let startTask = sessionStartTasks[descriptor.id] {
            try await startTask.value
            if let existing = sessions[descriptor.id], existing.endpoint == endpoint {
                return existing
            }
        }
        if let existing = sessions[descriptor.id], existing.endpoint == endpoint {
            return existing
        }
        let startTask = Task { [weak self] in
            guard let self else {
                throw MCPClientError.transportFailed(reason: "streamable HTTP client deallocated during start")
            }
            try await self.startAndRegisterSession(for: descriptor, endpoint: endpoint)
        }
        sessionStartTasks[descriptor.id] = startTask
        try await startTask.value
        guard let state = sessions[descriptor.id], state.endpoint == endpoint else {
            throw MCPClientError.transportFailed(reason: "streamable HTTP session unavailable after start")
        }
        return state
    }

    /// 初始化并登记单个 HTTP session；通过 sessionStartTasks 做 per-server single-flight。
    func startAndRegisterSession(for descriptor: MCPDescriptor, endpoint: URL) async throws {
        defer {
            sessionStartTasks[descriptor.id] = nil
        }
        let state = StreamableHTTPSession(descriptor: descriptor, endpoint: endpoint)
        try await initialize(state: state)
        sessions[descriptor.id] = state
    }

    /// 校验 descriptor URL，拒绝缺失 URL 与非本机明文 HTTP。
    func validatedEndpoint(for descriptor: MCPDescriptor) throws -> URL {
        guard let url = descriptor.url else {
            throw MCPClientError.transportFailed(reason: "streamable HTTP descriptor missing URL")
        }
        guard let scheme = url.scheme?.lowercased() else {
            throw MCPClientError.transportFailed(reason: "streamable HTTP URL missing scheme")
        }
        guard let host = url.host, !host.isEmpty else {
            throw MCPClientError.transportFailed(reason: "streamable HTTP URL missing host")
        }
        if scheme == "https" {
            return url
        }
        if scheme == "http", isLocalHTTPHost(host) {
            return url
        }
        throw MCPClientError.transportFailed(reason: "streamable HTTP URL must use HTTPS or local HTTP")
    }

    /// 判断明文 HTTP host 是否限定在本机。
    func isLocalHTTPHost(_ host: String?) -> Bool {
        guard let host = host?.lowercased() else {
            return false
        }
        return host == "localhost" || host == "127.0.0.1" || host == "::1"
    }

    /// 完成 MCP initialize 握手，并发送 notifications/initialized。
    func initialize(state: StreamableHTTPSession) async throws {
        let params: MCPJSONValue = .object([
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object(["tools": .object([:])]),
            "clientInfo": .object([
                "name": .string("SliceAI"),
                "version": .string("0.3.0")
            ])
        ])
        let result: MCPInitializeResult = try await sendRequest(method: "initialize", params: params, state: state)
        state.protocolVersion = result.protocolVersion
        try await sendNotification(method: "notifications/initialized", params: nil, state: state)
        logger.debug("MCP streamable HTTP initialized server=\(state.descriptor.id, privacy: .private)")
    }

    /// 确保当前 server 已执行 tools/list，并返回缓存后的 canonical tool descriptors。
    func listToolsIfNeeded(state: StreamableHTTPSession) async throws -> [MCPToolDescriptor] {
        if let cachedToolDescriptors = state.cachedToolDescriptors {
            return cachedToolDescriptors
        }
        let result: MCPToolsListResult = try await sendRequest(
            method: "tools/list",
            params: nil,
            state: state
        )
        let toolDescriptors = result.tools.map { $0.descriptor(serverID: state.descriptor.id) }
        state.cachedToolDescriptors = toolDescriptors
        logger.debug("MCP streamable HTTP tools/list completed server=\(state.descriptor.id, privacy: .private)")
        return toolDescriptors
    }

    /// 发送有 id 的 JSON-RPC request，并解码 JSON 或 SSE response。
    func sendRequest<Response: Decodable & Sendable>(
        method: String,
        params: MCPJSONValue?,
        state: StreamableHTTPSession
    ) async throws -> Response {
        let id = state.nextID
        state.nextID += 1
        let request = MCPJSONRPCRequest(id: id, method: method, params: params)
        let envelope: MCPJSONRPCResponse<Response> = try await sendEnvelope(
            request,
            expectedID: id,
            state: state
        )
        guard envelope.id == id else {
            throw MCPClientError.decodingFailed(reason: "JSON-RPC id mismatch")
        }
        return try envelope.resultOrThrow()
    }

    /// 发送无 id 的 JSON-RPC notification。
    func sendNotification(
        method: String,
        params: MCPJSONValue?,
        state: StreamableHTTPSession
    ) async throws {
        let request = MCPJSONRPCRequest(id: nil, method: method, params: params)
        let urlRequest = try makeURLRequest(for: request, state: state)
        let (_, response) = try await perform(urlRequest)
        try validateNotificationResponse(response)
    }

    /// 发送 HTTP request 并按 response content-type 解出 JSON-RPC envelope。
    func sendEnvelope<Response: Decodable & Sendable>(
        _ request: MCPJSONRPCRequest,
        expectedID: Int,
        state: StreamableHTTPSession
    ) async throws -> MCPJSONRPCResponse<Response> {
        let urlRequest = try makeURLRequest(for: request, state: state)
        let (data, response) = try await perform(urlRequest)
        let httpResponse = try validateMessageResponse(response)
        captureSessionID(from: httpResponse, state: state)
        let contentType = httpResponse.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
        if contentType.contains("application/json") {
            return try decodeResponse(Response.self, from: data)
        }
        if contentType.contains("text/event-stream") {
            return try decodeSSE(Response.self, from: data, expectedID: expectedID)
        }
        throw MCPClientError.decodingFailed(reason: "unsupported streamable HTTP content type")
    }

    /// 创建符合 MCP Streamable HTTP 规范的 POST request。
    func makeURLRequest(for request: MCPJSONRPCRequest, state: StreamableHTTPSession) throws -> URLRequest {
        do {
            var urlRequest = URLRequest(url: state.endpoint)
            urlRequest.httpMethod = "POST"
            urlRequest.timeoutInterval = TimeInterval(requestTimeoutNanoseconds) / 1_000_000_000
            urlRequest.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
            urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
            if let protocolVersion = state.protocolVersion {
                urlRequest.setValue(protocolVersion, forHTTPHeaderField: "MCP-Protocol-Version")
            }
            if let sessionID = state.sessionID {
                urlRequest.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
            }
            urlRequest.httpBody = try encoder.encode(request)
            return urlRequest
        } catch {
            throw MCPClientError.transportFailed(reason: "failed to encode streamable HTTP request: \(error)")
        }
    }

    /// 执行 URLSession 请求，并把 transport error 收敛到 MCPClientError。
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch {
            throw MCPClientError.transportFailed(reason: "streamable HTTP request failed: \(error)")
        }
    }

    /// 校验 JSON-RPC message response 的 HTTP 状态。
    func validateMessageResponse(_ response: URLResponse) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw MCPClientError.transportFailed(reason: "streamable HTTP response is not HTTP")
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw MCPClientError.transportFailed(reason: "streamable HTTP status code is not 2xx")
        }
        return httpResponse
    }

    /// 校验 notification response 的 HTTP 状态，并按规范接受 202/204。
    func validateNotificationResponse(_ response: URLResponse) throws {
        let httpResponse = try validateMessageResponse(response)
        guard httpResponse.statusCode == 202 || httpResponse.statusCode == 204 || httpResponse.statusCode == 200 else {
            throw MCPClientError.transportFailed(reason: "streamable HTTP notification was not accepted")
        }
    }

    /// 从 HTTP response header 记录 MCP session id。
    func captureSessionID(from response: HTTPURLResponse, state: StreamableHTTPSession) {
        guard let sessionID = response.value(forHTTPHeaderField: "Mcp-Session-Id"), !sessionID.isEmpty else {
            return
        }
        state.sessionID = sessionID
    }

    /// 解码 application/json JSON-RPC response。
    func decodeResponse<Response: Decodable & Sendable>(
        _ type: Response.Type,
        from data: Data
    ) throws -> MCPJSONRPCResponse<Response> {
        do {
            return try decoder.decode(MCPJSONRPCResponse<Response>.self, from: data)
        } catch {
            throw MCPClientError.decodingFailed(reason: "failed to decode JSON-RPC response: \(error)")
        }
    }

    /// 解码 text/event-stream response，返回匹配 request id 的 JSON-RPC response。
    func decodeSSE<Response: Decodable & Sendable>(
        _ type: Response.Type,
        from data: Data,
        expectedID: Int
    ) throws -> MCPJSONRPCResponse<Response> {
        guard let text = String(data: data, encoding: .utf8) else {
            throw MCPClientError.decodingFailed(reason: "SSE response is not valid UTF-8")
        }
        let events = normalizedSSEEvents(from: text)
        for event in events {
            guard let payload = dataPayload(fromSSEEvent: event) else {
                continue
            }
            let payloadData = Data(payload.utf8)
            let envelope = try? decoder.decode(StreamableHTTPJSONRPCIDEnvelope.self, from: payloadData)
            guard envelope?.id == expectedID else {
                continue
            }
            return try decodeResponse(Response.self, from: payloadData)
        }
        throw MCPClientError.decodingFailed(reason: "SSE response missing matching JSON-RPC response")
    }

    /// 将 SSE 文本按空行拆成 event blocks，兼容 CRLF。
    func normalizedSSEEvents(from text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
    }

    /// 从单个 SSE event 中提取所有 data 行并按 SSE 规则用换行拼接。
    func dataPayload(fromSSEEvent event: String) -> String? {
        let payloadLines = event
            .split(separator: "\n", omittingEmptySubsequences: false)
            .compactMap { line -> String? in
                guard line.hasPrefix("data:") else { return nil }
                var payload = line.dropFirst("data:".count)
                if payload.first == " " {
                    payload.removeFirst()
                }
                return String(payload)
            }
        guard !payloadLines.isEmpty else {
            return nil
        }
        return payloadLines.joined(separator: "\n")
    }
}

/// actor 内部持有的 Streamable HTTP 会话状态。
private final class StreamableHTTPSession {
    let descriptor: MCPDescriptor
    let endpoint: URL
    var nextID = 1
    var sessionID: String?
    var protocolVersion: String?
    var cachedToolDescriptors: [MCPToolDescriptor]?

    /// 构造 Streamable HTTP 会话状态。
    init(descriptor: MCPDescriptor, endpoint: URL) {
        self.descriptor = descriptor
        self.endpoint = endpoint
    }
}

/// 只解 JSON-RPC response id 的轻量 envelope。
private struct StreamableHTTPJSONRPCIDEnvelope: Decodable {
    let id: Int?
}
