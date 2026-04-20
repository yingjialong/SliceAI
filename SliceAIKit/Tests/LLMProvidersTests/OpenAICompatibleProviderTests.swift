import XCTest
@testable import LLMProviders
@testable import SliceCore

/// OpenAICompatibleProvider 的集成测试
/// 通过 MockURLProtocol 拦截 URLSession 请求，覆盖 happy path 与常见错误分支
final class OpenAICompatibleProviderTests: XCTestCase {

    /// 每个用例结束后清空类级 handler，避免测试间互相污染
    override func tearDown() {
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    /// Happy path：SSE 正常返回两个 delta + finish + [DONE]，应拼出完整文本
    func test_stream_happyPath_returnsConcatenatedChunks() async throws {
        let sse = """
        data: {"choices":[{"delta":{"content":"Hello"}}]}

        data: {"choices":[{"delta":{"content":" World"}}]}

        data: {"choices":[{"delta":{},"finish_reason":"stop"}]}

        data: [DONE]


        """.data(using: .utf8)!

        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!,
                                       statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
            return (resp, sse)
        }

        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-test",
            session: URLSession.mocked()
        )

        let req = ChatRequest(
            model: "gpt-5",
            messages: [ChatMessage(role: .user, content: "hi")]
        )
        var collected = ""
        for try await chunk in try await provider.stream(request: req) {
            collected += chunk.delta
        }
        XCTAssertEqual(collected, "Hello World")
    }

    /// 401：Provider 必须映射成 SliceError.provider(.unauthorized)
    func test_stream_unauthorized401_throws() async throws {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 401,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data("unauthorized".utf8))
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "bad", session: URLSession.mocked()
        )
        let req = ChatRequest(model: "x", messages: [])

        do {
            let s = try await provider.stream(request: req)
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.unauthorized) {
            // OK
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// 5xx：应映射成 SliceError.provider(.serverError(code)) 并透传 code
    func test_stream_serverError500_throws() async throws {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 500,
                                       httpVersion: nil, headerFields: nil)!
            return (resp, Data())
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "k", session: URLSession.mocked()
        )
        do {
            let s = try await provider.stream(request: ChatRequest(model: "x", messages: []))
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.serverError(let code)) {
            XCTAssertEqual(code, 500)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// 429：Retry-After 头应解析为 TimeInterval 并携带到错误里
    func test_stream_rateLimited429_includesRetryAfter() async throws {
        MockURLProtocol.requestHandler = { req in
            let resp = HTTPURLResponse(url: req.url!, statusCode: 429, httpVersion: nil,
                                       headerFields: ["Retry-After": "12"])!
            return (resp, Data())
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "k", session: URLSession.mocked()
        )
        do {
            let s = try await provider.stream(request: ChatRequest(model: "x", messages: []))
            for try await _ in s {}
            XCTFail("expected throw")
        } catch SliceError.provider(.rateLimited(let after)) {
            XCTAssertEqual(after, 12)
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }

    /// Authorization header 必须以 Bearer <apiKey> 的形式发送
    func test_stream_sendsAuthorizationHeader() async throws {
        final class Capture: @unchecked Sendable { var auth: String? }
        let cap = Capture()
        MockURLProtocol.requestHandler = { req in
            cap.auth = req.value(forHTTPHeaderField: "Authorization")
            let resp = HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil,
                                       headerFields: ["Content-Type": "text/event-stream"])!
            return (resp, Data("data: [DONE]\n\n".utf8))
        }
        let provider = OpenAICompatibleProvider(
            baseURL: URL(string: "https://api.example.com/v1")!,
            apiKey: "sk-123", session: URLSession.mocked()
        )
        for try await _ in try await provider.stream(request: ChatRequest(model: "x", messages: [])) {}
        XCTAssertEqual(cap.auth, "Bearer sk-123")
    }
}
