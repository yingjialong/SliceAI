import CoreGraphics
import Foundation

/// 二阶段执行上下文：由 `ContextCollector.resolve(seed:requests:)` 产出
///
/// 不可变（INV-6）；执行引擎真正消费的对象。相比 `ExecutionSeed` 增加：
/// - `contexts`：所有成功采集的 ContextValue
/// - `failures`：`requiredness == .optional` 的请求失败记录（required 失败则流程早已终止）
/// - `resolvedAt`：解析完成时间，便于延迟分析
///
/// 透传访问器仅为调用便利；底层数据源 = `seed.*`。
public struct ResolvedExecutionContext: Sendable, Equatable {
    /// 原始 seed（不可变）
    public let seed: ExecutionSeed
    /// 采集到的上下文值
    public let contexts: ContextBag
    /// 解析完成时间
    ///
    /// **调用方契约**：应 ≥ `seed.timestamp`。ResolvedExecutionContext 不强制校验，
    /// 因为 ContextCollector 构造本类型时已经保证时间单调。本字段 `- seed.timestamp`
    /// = ContextCollector 耗时，可用于审计 / 延迟分析。
    public let resolvedAt: Date
    /// optional 请求的失败记录；required 请求失败时流程直接中止、不会进入这里
    public let failures: [ContextKey: SliceError]

    /// 构造 ResolvedExecutionContext
    /// - Parameters:
    ///   - seed: 来源 seed
    ///   - contexts: 成功采集的键值
    ///   - resolvedAt: 解析完成时间
    ///   - failures: optional 请求的失败记录
    public init(seed: ExecutionSeed, contexts: ContextBag, resolvedAt: Date, failures: [ContextKey: SliceError]) {
        self.seed = seed
        self.contexts = contexts
        self.resolvedAt = resolvedAt
        self.failures = failures
    }

    // MARK: - Transparent accessors

    /// 透传 `seed.invocationId`
    public var invocationId: UUID { seed.invocationId }
    /// 透传 `seed.selection`
    public var selection: SelectionSnapshot { seed.selection }
    /// 透传 `seed.frontApp`
    public var frontApp: AppSnapshot { seed.frontApp }
    /// 透传 `seed.isDryRun`
    public var isDryRun: Bool { seed.isDryRun }
    /// 透传 `seed.screenAnchor`
    public var screenAnchor: CGPoint { seed.screenAnchor }
    /// 透传 `seed.timestamp`（触发时间；对比 `resolvedAt` 可算 collector 耗时）
    public var triggerTimestamp: Date { seed.timestamp }
    /// 透传 `seed.triggerSource`
    public var triggerSource: TriggerSource { seed.triggerSource }
}
