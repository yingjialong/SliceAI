import Foundation
import SliceCore

/// 生产环境使用的 LLMProviderFactory 实现
public struct OpenAIProviderFactory: LLMProviderFactory {
    public init() {}

    /// 根据 Provider 创建 OpenAI 兼容 Provider。
    ///
    /// 当前生产实现只支持 `.openAICompatible`。错误消息固定脱敏，避免把用户自定义
    /// provider id、endpoint 或其它配置细节写入上层错误链路。
    public func validate(provider: Provider) throws {
        guard provider.kind == .openAICompatible else {
            throw SliceError.configuration(.validationFailed(
                "OpenAIProviderFactory only supports kind=openAICompatible"
            ))
        }
        guard provider.baseURL != nil else {
            throw SliceError.configuration(.validationFailed(
                "OpenAIProviderFactory requires non-nil baseURL"
            ))
        }
    }

    /// 根据 Provider 创建 OpenAI 兼容 Provider。
    ///
    /// make 入口也保留 validate，保护直接调用工厂的路径。
    public func make(for provider: Provider, apiKey: String) throws -> any LLMProvider {
        try validate(provider: provider)
        guard let baseURL = provider.baseURL else {
            throw SliceError.configuration(.validationFailed(
                "OpenAIProviderFactory requires non-nil baseURL"
            ))
        }
        return OpenAICompatibleProvider(baseURL: baseURL, apiKey: apiKey)
    }
}
