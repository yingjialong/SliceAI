import Foundation

/// LLM 调用的抽象协议，所有供应商（OpenAI 兼容 / 未来的 Anthropic / Gemini）必须实现
public protocol LLMProvider: Sendable {
    /// 流式调用。失败时 AsyncStream 会 throw SliceError.provider
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error>

    /// 带 tool calling 的流式调用。默认实现 fail-fast，具体 provider 按能力覆盖。
    func streamToolChat(request: ChatToolRequest) async throws -> AsyncThrowingStream<ChatStreamEvent, any Error>
}

public extension LLMProvider {
    /// 默认 tool calling 实现：未覆盖的 provider 明确报错，避免静默走 prompt-only API。
    /// - Parameter request: 未使用；保留签名便于 conformer 覆盖。
    /// - Returns: 不返回；总是抛出 unsupported 错误。
    func streamToolChat(request: ChatToolRequest) async throws -> AsyncThrowingStream<ChatStreamEvent, any Error> {
        throw SliceError.provider(.invalidResponse("tool calling stream is unsupported"))
    }
}

/// 工厂：根据 Provider 配置创建对应的 LLMProvider
public protocol LLMProviderFactory: Sendable {
    /// 在读取 Keychain / 创建 LLMProvider 前验证 provider 是否被当前工厂支持。
    ///
    /// 该方法必须只检查 provider 自身的结构与协议族，不读取 API Key、不访问网络。
    /// 这样调用方可以在缺少 Keychain 条目前先返回准确的配置错误。
    /// - Parameter provider: v2 Provider 配置。
    func validate(provider: Provider) throws

    /// 创建可执行的 LLMProvider。
    /// - Parameters:
    ///   - provider: v2 Provider 配置。
    ///   - apiKey: 已从 Keychain 读取出的 API Key。
    /// - Returns: 可流式执行 ChatRequest 的 Provider 实例。
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider
}

public extension LLMProviderFactory {
    /// 默认 preflight：通用测试工厂或多协议工厂可以选择不做额外限制。
    ///
    /// 生产工厂应覆盖本方法，确保 unsupported provider kind 在 Keychain 读取前被准确拒绝。
    func validate(provider: Provider) throws {}
}
