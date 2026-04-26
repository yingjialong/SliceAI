import Foundation
import SliceCore
@testable import Orchestration

/// `ProviderResolverProtocol` 的可控 mock，供 ExecutionEngineTests 注入"按需返回 / 按需抛错"行为。
///
/// 设计要点：
/// - **actor**：内部含 mutable state（resolveCalls 计数 + override 闭包），与生产
///   `DefaultProviderResolver` 一致用 actor 隔离，避免 `@unchecked Sendable` 锁逃逸；
/// - **默认行为 = 返回 `MockProvider.openAIStub()`**：让 ExecutionEngineTests 的 happy path
///   不需要每条用例都注入 provider；
/// - **`outcomeOverride` 闭包**：测试可以按 selection 决定返回 V2Provider 或抛
///   `ProviderResolutionError`，覆盖 `referencedProviderMissing` / `notImplemented` 路径；
/// - **`@Sendable` 闭包**：跨 actor 边界存储，Swift 6 严格并发要求 Sendable 标注。
final actor MockProviderResolver: ProviderResolverProtocol {

    // MARK: - 注入点

    /// `resolve(_:)` 累计被调次数；测试可断言"resolver 被调几次"
    private(set) var resolveCalls: Int = 0

    /// 每次调用的 selection 入参快照（顺序保留），便于断言 ExecutionEngine 透传是否正确
    private(set) var capturedSelections: [ProviderSelection] = []

    /// 注入 selection → 解析结果 / 错误的闭包；nil 时走默认 stub provider
    private var outcomeOverride: (@Sendable (ProviderSelection) -> Result<V2Provider, ProviderResolutionError>)?

    /// 默认返回的 V2Provider stub —— `outcomeOverride` 为 nil 时使用
    private let defaultProvider: V2Provider

    // MARK: - Init

    /// 构造 MockProviderResolver
    ///
    /// - Parameters:
    ///   - defaultProvider: 默认返回的 V2Provider；未传则用 `MockProvider.openAIStub()`
    ///   - outcomeOverride: 按 selection 决定返回 / 抛错的闭包；nil 走默认路径
    init(
        defaultProvider: V2Provider = MockProvider.openAIStub(),
        outcomeOverride: (@Sendable (ProviderSelection) -> Result<V2Provider, ProviderResolutionError>)? = nil
    ) {
        self.defaultProvider = defaultProvider
        self.outcomeOverride = outcomeOverride
    }

    // MARK: - ProviderResolverProtocol

    /// 解析 selection；按 override / 默认 provider 返回，记录调用现场便于测试断言
    func resolve(_ selection: ProviderSelection) async throws -> V2Provider {
        resolveCalls += 1
        capturedSelections.append(selection)
        if let override = outcomeOverride {
            switch override(selection) {
            case .success(let provider):
                return provider
            case .failure(let error):
                throw error
            }
        }
        return defaultProvider
    }

    // MARK: - 测试辅助

    /// 在测试中替换 outcomeOverride（如某条用例临时切换返回 .notFound）
    func setOutcomeOverride(
        _ override: @escaping @Sendable (ProviderSelection) -> Result<V2Provider, ProviderResolutionError>
    ) {
        self.outcomeOverride = override
    }
}
