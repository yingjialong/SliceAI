import Foundation
import SliceCore

/// OpenAI 兼容协议的 Provider 实现
/// 使用 URLSession.bytes(for:) 流式读取 SSE
public struct OpenAICompatibleProvider: LLMProvider {

    /// 供应商的基础 URL，通常形如 https://api.openai.com/v1
    private let baseURL: URL
    /// 透传到 Authorization: Bearer <apiKey> 的密钥
    private let apiKey: String
    /// 注入的 URLSession，测试可换成 Mock
    private let session: URLSession

    /// 构造 OpenAI 兼容 Provider
    /// - Parameters:
    ///   - baseURL: 服务端基础 URL，例如 https://api.openai.com/v1
    ///   - apiKey: 用于 Bearer 鉴权的 API Key
    ///   - session: URLSession，默认使用 .shared；测试可注入 MockURLProtocol 的会话
    public init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.session = session
    }

    /// 发起流式 chat completion 请求并将 SSE 解码为 ChatChunk 流
    /// - Parameter request: 领域层定义的 ChatRequest（含 model / messages / 参数）
    /// - Returns: AsyncThrowingStream<ChatChunk, any Error>；遇 HTTP 错误会在 await 阶段抛出
    public func stream(
        request: ChatRequest
    ) async throws -> AsyncThrowingStream<ChatChunk, any Error> {
        // 组装 URL：baseURL 通常形如 https://api.openai.com/v1
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var httpReq = URLRequest(url: endpoint)
        httpReq.httpMethod = "POST"
        httpReq.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        httpReq.setValue("application/json", forHTTPHeaderField: "Content-Type")
        httpReq.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        httpReq.timeoutInterval = 30

        // 追加 stream: true，保持其它字段由 ChatRequest 编码产出
        var body = try JSONEncoder().encode(request)
        if var dict = try JSONSerialization.jsonObject(with: body) as? [String: Any] {
            dict["stream"] = true
            body = try JSONSerialization.data(withJSONObject: dict)
        }
        httpReq.httpBody = body

        // 发起请求；bytes 为可异步读取的字节流，response 用于状态码判定
        let (bytes, response) = try await session.bytes(for: httpReq)
        guard let http = response as? HTTPURLResponse else {
            throw SliceError.provider(.invalidResponse("non-http response"))
        }

        // 先做状态码分流，便于在 await 阶段就抛出错误，无需进入流循环
        switch http.statusCode {
        case 200..<300:
            break
        case 401:
            throw SliceError.provider(.unauthorized)
        case 429:
            let retry = http.value(forHTTPHeaderField: "Retry-After").flatMap(TimeInterval.init)
            throw SliceError.provider(.rateLimited(retryAfter: retry))
        case 500..<600:
            throw SliceError.provider(.serverError(http.statusCode))
        default:
            throw SliceError.provider(.invalidResponse("HTTP \(http.statusCode)"))
        }

        // 2xx 成功：把字节流接入 SSE 解码器，逐事件映射成 ChatChunk
        return Self.makeStream(from: bytes)
    }

    /// 将 URLSession.AsyncBytes 封装为 ChatChunk 流
    /// 注：独立成静态方法以隔离非 Sendable 的 bytes 捕获路径
    /// 实现要点：bytes.lines 会吞掉空行，而 SSE 事件边界依赖空行；因此我们按字节累积，
    ///          遇到 "\n" 边界后把整行（含换行）交给 SSEDecoder，空行也能正确触发事件
    private static func makeStream(
        from bytes: URLSession.AsyncBytes
    ) -> AsyncThrowingStream<ChatChunk, any Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                var decoder = SSEDecoder()
                var buffer: [UInt8] = []
                do {
                    for try await byte in bytes {
                        buffer.append(byte)
                        if byte == UInt8(ascii: "\n") {
                            // 以 UTF-8 解码当前缓冲的一整行（含换行），交给 SSEDecoder
                            if let line = String(bytes: buffer, encoding: .utf8) {
                                let events = decoder.feed(line)
                                if emitAndCheckDone(events, continuation: continuation) {
                                    return
                                }
                            }
                            buffer.removeAll(keepingCapacity: true)
                        }
                    }
                    // 流结束：把尾部残留 + 两个换行喂入，保证事件边界被触发
                    var tail = ""
                    if !buffer.isEmpty, let s = String(bytes: buffer, encoding: .utf8) {
                        tail = s
                    }
                    let rest = decoder.feed(tail + "\n\n")
                    _ = emitAndCheckDone(rest, continuation: continuation)
                    continuation.finish()
                } catch {
                    // URLSession 超时映射为领域层 networkTimeout，其余原样抛出
                    if (error as? URLError)?.code == .timedOut {
                        continuation.finish(throwing: SliceError.provider(.networkTimeout))
                    } else {
                        continuation.finish(throwing: error)
                    }
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 把解码得到的 SSE 事件转换成 ChatChunk 并投递给 continuation
    /// - Returns: 是否遇到 [DONE]；true 时调用方应立即退出循环
    private static func emitAndCheckDone(
        _ events: [SSEDecoder.Event],
        continuation: AsyncThrowingStream<ChatChunk, any Error>.Continuation
    ) -> Bool {
        for event in events {
            switch event {
            case .data(let json):
                if let chunk = decodeChunk(json: json) {
                    continuation.yield(chunk)
                }
            case .done:
                continuation.finish()
                return true
            }
        }
        return false
    }

    /// 将一行 SSE data JSON 解码成 ChatChunk；无法识别返回 nil
    /// - Parameter json: SSE data 字段的原始 JSON 字符串
    /// - Returns: 解析成功且有意义的 ChatChunk；否则 nil
    private static func decodeChunk(json: String) -> ChatChunk? {
        guard let data = json.data(using: .utf8) else { return nil }
        guard let parsed = try? JSONDecoder().decode(OpenAIStreamChunk.self, from: data) else {
            return nil
        }
        let delta = parsed.choices.first?.delta.content ?? ""
        let reason = parsed.choices.first?.finishReason.flatMap(FinishReason.init(rawValue:))
        // 空 delta 且无 finishReason 的 chunk 无意义，过滤
        if delta.isEmpty && reason == nil { return nil }
        return ChatChunk(delta: delta, finishReason: reason)
    }
}
