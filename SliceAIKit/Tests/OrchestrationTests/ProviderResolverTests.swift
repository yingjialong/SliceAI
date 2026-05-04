import XCTest
import SliceCore
@testable import Orchestration

/// ProviderResolverProtocol / DefaultProviderResolver 单元测试
///
/// 覆盖：
/// 1. `.fixed` 路径：按 providerId 命中正确 Provider
/// 2. `.fixed` 路径：providerId 不存在时抛 `.notFound`
/// 3. `.fixed` 路径：传入 modelId 不影响返回的 Provider（M2 resolver 不消费 modelId）
/// 4. `.capability` 路径：在 M2 范围内抛 `.notImplemented(.capabilityRouting)`
/// 5. `.cascade` 路径：在 M2 范围内抛 `.notImplemented(.cascadeRouting)`
final class ProviderResolverTests: XCTestCase {

    // MARK: - .fixed 路径

    /// `.fixed` 命中：按 providerId 正确返回对应的 Provider
    func test_resolve_fixed_returnsProviderById() async throws {
        // 准备：配置包含 openai-1 + claude-1 两个 provider
        let openai = MockProvider.openAIStub(id: "openai-1")
        let claude = MockProvider.anthropicStub(id: "claude-1")
        let config = MockProvider.configWith([openai, claude])
        let resolver = DefaultProviderResolver { config }

        // 执行：解析 claude-1
        let resolved = try await resolver.resolve(.fixed(providerId: "claude-1", modelId: nil))

        // 断言：返回 claude-1，kind 为 .anthropic
        XCTAssertEqual(resolved.id, "claude-1")
        XCTAssertEqual(resolved.kind, .anthropic)
    }

    /// `.fixed` 未命中：providerId 不存在时抛 `ProviderResolutionError.notFound`
    func test_resolve_fixed_throwsNotFoundWhenIdMissing() async throws {
        // 准备：配置只有 openai-1
        let config = MockProvider.configWith([MockProvider.openAIStub(id: "openai-1")])
        let resolver = DefaultProviderResolver { config }

        // 执行 + 断言：解析不存在的 missing-id，期望抛 notFound 且携带正确 providerId
        do {
            _ = try await resolver.resolve(.fixed(providerId: "missing-id", modelId: nil))
            XCTFail("expected ProviderResolutionError.notFound to be thrown")
        } catch ProviderResolutionError.notFound(let providerId) {
            XCTAssertEqual(providerId, "missing-id")
        }
    }

    /// `.fixed` modelId 幂等性：无论 modelId 是否传入，返回同一 Provider
    ///
    /// M2 resolver 不消费 modelId——modelId fallback 语义在 PromptExecutor（Task 11）处理；
    /// 本测试确保 resolver 对 modelId=nil 与 modelId="gpt-5-mini" 返回完全相同的 Provider。
    func test_resolve_fixed_returnsSameProviderRegardlessOfModelId() async throws {
        // 准备：defaultModel 为 gpt-5 的 openai-1
        let provider = MockProvider.openAIStub(id: "openai-1", defaultModel: "gpt-5")
        let config = MockProvider.configWith([provider])
        let resolver = DefaultProviderResolver { config }

        // 执行：分别用 nil 和显式 modelId 解析
        let resolvedNil = try await resolver.resolve(.fixed(providerId: "openai-1", modelId: nil))
        let resolvedExplicit = try await resolver.resolve(
            .fixed(providerId: "openai-1", modelId: "gpt-5-mini")
        )

        // 断言：两次结果相同；defaultModel 保持 gpt-5（selection 的 modelId 未被 bake 进 Provider）
        XCTAssertEqual(resolvedNil, resolvedExplicit)
        XCTAssertEqual(resolvedNil.defaultModel, "gpt-5")
    }

    // MARK: - .capability / .cascade 路径（M2 范围抛 notImplemented）

    /// `.capability` 路径：M2 范围内抛 `.notImplemented(.capabilityRouting)`
    func test_resolve_capability_throwsNotImplemented_capabilityRouting() async throws {
        // 准备：空配置（capability 路由在 M2 不依赖配置内容）
        let resolver = DefaultProviderResolver { MockProvider.configWith([]) }

        // 执行 + 断言：`.capability` 触发 notImplemented + capabilityRouting 原因
        do {
            _ = try await resolver.resolve(.capability(requires: [.toolCalling], prefer: ["claude"]))
            XCTFail("expected ProviderResolutionError.notImplemented to be thrown")
        } catch ProviderResolutionError.notImplemented(let reason) {
            XCTAssertEqual(reason, .capabilityRouting)
        }
    }

    /// `.cascade` 路径：M2 范围内抛 `.notImplemented(.cascadeRouting)`
    func test_resolve_cascade_throwsNotImplemented_cascadeRouting() async throws {
        // 准备：空配置（cascade 路由在 M2 不依赖配置内容）
        let resolver = DefaultProviderResolver { MockProvider.configWith([]) }

        // 执行 + 断言：`.cascade` 触发 notImplemented + cascadeRouting 原因
        do {
            _ = try await resolver.resolve(.cascade(rules: []))
            XCTFail("expected ProviderResolutionError.notImplemented to be thrown")
        } catch ProviderResolutionError.notImplemented(let reason) {
            XCTAssertEqual(reason, .cascadeRouting)
        }
    }
}
