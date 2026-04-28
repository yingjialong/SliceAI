import Foundation

/// 单次 invocation 的成本记录（spec §4.4.2 / §4.5.2）。
///
/// 由 `PromptExecutor`（Task 11）在 stream 结束时构造，并由 `ExecutionEngine`（Task 4）
/// 调用 `CostAccounting.record(_:)` 持久化。M2 范围内 `inputTokens` / `outputTokens` 由
/// `PromptExecutor` 估算（粗粒度近似）；`usd` 由调用方按 `inputTokens × providerRate.input
/// + outputTokens × providerRate.output` 计算后传入。
///
/// 设计决策：
/// - `usd` 用 `Decimal` 而非 `Double` —— 金额计算必须避免 IEEE 754 浮点误差；
///   存储到 sqlite 时也以 `TEXT` 而非 `REAL` 持久化（见 `CostAccounting`）。
/// - 类型 `Sendable` 以便跨 actor 边界传递；`Codable` 留作 future hook（M2 不依赖 JSON 稳定 round-trip）。
public struct CostRecord: Sendable, Equatable, Codable {
    /// 关联到 `ExecutionEvent.started/finished` 的 invocationId
    public let invocationId: UUID
    /// 触发本次 invocation 的 toolId
    public let toolId: String
    /// 实际命中的 providerId（`ProviderResolver` 解析后）
    public let providerId: String
    /// 实际使用的 model（"gpt-4o" 等）
    public let model: String
    /// 估算输入 token 数（M2 由 PromptExecutor 粗略估算）
    public let inputTokens: Int
    /// 估算输出 token 数
    public let outputTokens: Int
    /// 估算成本（美元），= inputTokens × rate.input + outputTokens × rate.output
    public let usd: Decimal
    /// invocation 结束时间戳
    public let recordedAt: Date

    /// Designated initializer
    /// - Parameters:
    ///   - invocationId: 关联到 ExecutionEvent.started/finished 的 invocationId
    ///   - toolId: 触发本次 invocation 的 toolId
    ///   - providerId: 实际命中的 providerId
    ///   - model: 实际使用的 model
    ///   - inputTokens: 估算输入 token 数
    ///   - outputTokens: 估算输出 token 数
    ///   - usd: 估算成本（美元，Decimal）
    ///   - recordedAt: invocation 结束时间戳
    public init(
        invocationId: UUID,
        toolId: String,
        providerId: String,
        model: String,
        inputTokens: Int,
        outputTokens: Int,
        usd: Decimal,
        recordedAt: Date
    ) {
        self.invocationId = invocationId
        self.toolId = toolId
        self.providerId = providerId
        self.model = model
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.usd = usd
        self.recordedAt = recordedAt
    }
}
