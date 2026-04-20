import Foundation

/// 测试专用的 URLProtocol 拦截器
/// 用法：测试内给 `requestHandler` 赋值，发起请求时 URLSession 会命中此协议并回放指定响应
/// 注意：`requestHandler` 使用类级存储，tearDown 时务必置 nil，避免测试间污染
final class MockURLProtocol: URLProtocol, @unchecked Sendable {
    /// 用类级字典存 request handler，测试设置后复位
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    /// 声明本协议可处理所有请求；实际拦截由 URLSession 的 configuration.protocolClasses 决定
    override class func canInit(with request: URLRequest) -> Bool { true }

    /// URLProtocol 要求返回规范化后的请求；无需改写，原样返回
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    /// 开始加载：执行 requestHandler，把响应/数据/结束事件依次回放给 client
    override func startLoading() {
        guard let handler = Self.requestHandler else {
            // 未设置 handler 视为异常，模拟坏响应
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    /// 取消加载：MVP 内无需特殊清理，保持空实现
    override func stopLoading() {}
}

extension URLSession {
    /// 构造使用 MockURLProtocol 的短生命周期 URLSession，供测试调用
    static func mocked() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        return URLSession(configuration: config)
    }
}
