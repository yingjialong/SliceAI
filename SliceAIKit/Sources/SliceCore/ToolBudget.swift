import Foundation

/// Per-tool 成本上限；`CostAccounting`（Phase 0 M2）按此约束
public struct ToolBudget: Sendable, Codable, Equatable {
    /// 每日 USD 上限；nil 表示不限
    public let dailyUSD: Double?
    /// 单次调用 USD 上限；nil 表示不限
    public let perCallUSD: Double?

    /// 构造 ToolBudget
    public init(dailyUSD: Double?, perCallUSD: Double?) {
        self.dailyUSD = dailyUSD
        self.perCallUSD = perCallUSD
    }
}
