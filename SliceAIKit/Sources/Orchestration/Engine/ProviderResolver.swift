import Foundation
import SliceCore

/// 把 `ProviderSelection`（fixed / capability / cascade）解析到具体 `Provider`。
///
/// M2 只实现 `.fixed`：按 providerId 在 `Configuration.providers` 里查找，命中则返回 Provider，
/// 命中失败抛 `ProviderResolutionError.notFound`。`.capability` / `.cascade` 形态在 M2 范围抛
/// `.notImplemented(.capabilityRouting)` / `.notImplemented(.cascadeRouting)`，由 Phase 1 / Phase 5 实现。
///
/// `selection.modelId` 在 M2 阶段**不**被本协议消费——返回的 `Provider` 始终是配置里的原始定义，
/// 调用方（PromptExecutor / 未来 AgentExecutor）按 `selection.modelId ?? provider.defaultModel` 决定
/// 实际使用的模型；具体语义见 Task 11 PromptExecutor。Phase 1 如需返回带 selected-model 的复合结果，
/// 再扩展协议（如返回 `(Provider, model: String)` 元组或新增 `ResolvedProvider` 类型）。
///
/// **协议命名**：带 `Protocol` 后缀，与 §C-10.1 audit 表 `any ProviderResolverProtocol` 对齐。
public protocol ProviderResolverProtocol: Sendable {

    /// 解析一次 selection 到 Provider。
    /// - Parameter selection: `ProviderSelection` 任一形态
    /// - Returns: 命中的 Provider
    /// - Throws: `ProviderResolutionError.notFound(providerId:)` / `.notImplemented(...)`
    func resolve(_ selection: ProviderSelection) async throws -> Provider
}

/// 默认实现：通过注入的闭包按需获取最新 `Configuration`，避免持有 ConfigurationStore（便于测试注入）。
///
/// `actor` 提供 Sendable 隔离边界，让 `DefaultProviderResolver` 可以从任意并发上下文安全调用；
/// 当前实现没有内部 mutable state，actor 隔离主要起 forward-compatibility 作用——
/// M3 装配 ConfigurationStore 后如需添加配置缓存（mutable state），actor 可直接扩展，
/// 调用方不需重构。`configurationProvider` 闭包在每次 `resolve` 时调用一次，
/// 让配置热更新（M3 接 ConfigurationStore observer 时）能被立即反映。
public actor DefaultProviderResolver: ProviderResolverProtocol {

    // MARK: - Properties

    /// 按需获取最新 Configuration 的闭包；测试用 `{ stubConfig }`，生产用 `{ await store.current() }`
    private let configurationProvider: @Sendable () async throws -> Configuration

    // MARK: - Init

    /// 构造默认 resolver
    /// - Parameter configurationProvider: 按需获取最新 Configuration 的闭包；测试用 `{ stubConfig }`，
    ///   生产用 `{ await store.current() }`（M3 装配）
    public init(configurationProvider: @Sendable @escaping () async throws -> Configuration) {
        self.configurationProvider = configurationProvider
    }

    // MARK: - ProviderResolverProtocol

    /// 解析 ProviderSelection 到具体 Provider
    ///
    /// M2 范围：`.fixed` 完整实现；`.capability` / `.cascade` 抛 notImplemented
    public func resolve(_ selection: ProviderSelection) async throws -> Provider {
        switch selection {
        case .fixed(let providerId, _):
            // M2 仅消费 providerId；modelId 由调用方在 PromptExecutor 处理（见上方 protocol 文档）
            let config = try await configurationProvider()
            guard let provider = config.providers.first(where: { $0.id == providerId }) else {
                throw ProviderResolutionError.notFound(providerId: providerId)
            }
            return provider

        case .capability:
            // Phase 1 实现：按 capability requires/prefer 路由
            throw ProviderResolutionError.notImplemented(.capabilityRouting)

        case .cascade:
            // Phase 5 实现：按 CascadeRule 降级路由
            throw ProviderResolutionError.notImplemented(.cascadeRouting)
        }
    }
}
