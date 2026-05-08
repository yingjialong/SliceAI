import Foundation
import SliceCore

/// `ProviderResolverProtocol.resolve(_:)` 失败时抛出的错误
///
/// 与 SliceError 解耦：ProviderResolver 是 Orchestration 内部实现，错误由 ExecutionEngine.execute
/// 在 Step 4 catch 后转换为 `SliceError.configuration(.referencedProviderMissing(...))`（notFound 路径）
/// 或 `SliceError.configuration(.validationFailed(...))`（未实现 / 无能力匹配路径）后再走 finishFailure。
/// 这样 ProviderResolutionError 的 case 可以独立演进，不污染 SliceCore 的 SliceError 命名空间。
public enum ProviderResolutionError: Error, Sendable, Equatable {

    /// `.fixed` 形态找不到对应 Provider id；与 `SliceError.configuration(.referencedProviderMissing)`
    /// 语义平行——ExecutionEngine 在 Step 4 catch 后 wrap 为后者
    case notFound(providerId: String)

    /// 当前仍未实现的 ProviderSelection 形态；`.cascade` 由 Phase 5 填实。
    case notImplemented(NotImplementedReason)

    /// `.capability` 路由找不到满足全部 required capabilities 的 Provider。
    case noProviderMatchingCapabilities(requires: Set<ProviderCapability>)

    /// 未实现路径的具体原因（按 ProviderSelection 形态分类）
    public enum NotImplementedReason: String, Sendable, Equatable {
        /// 历史保留：旧版本 `.capability(requires:prefer:)` 未实现时使用。
        case capabilityRouting
        /// `.cascade(rules:)` 形态需要按规则降级路由——Phase 5 实现
        case cascadeRouting
    }
}
