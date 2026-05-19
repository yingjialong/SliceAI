import Foundation

/// Agent 工具调用策略。
///
/// `AgentTool.maxSteps` 只表示 LLM ReAct 轮数；MCP 调用次数、同轮调用量、重复调用处理
/// 由本策略独立控制，避免把“思考轮数”和“外部工具配额”混成同一个旋钮。
public struct AgentToolCallPolicy: Sendable, Codable, Equatable {
    /// 单次 Agent 运行最多真实执行多少次 MCP 调用；nil 表示使用执行器默认兜底值。
    public var maxTotalCalls: Int?
    /// 单个 assistant turn 最多真实执行多少次 MCP 调用；nil 表示使用执行器默认兜底值。
    public var maxCallsPerTurn: Int?
    /// 针对特定 MCP tool 的调用上限。
    public var perToolLimits: [AgentToolCallLimit]
    /// 参数完全相同的重复调用如何处理。
    public var duplicateArgumentStrategy: AgentDuplicateToolCallStrategy
    /// MCP 返回 rate limit 后，是否跳过本次运行后续 MCP 调用。
    public var stopOnRateLimit: Bool

    /// 构造 Agent 工具调用策略。
    /// - Parameters:
    ///   - maxTotalCalls: 单次运行总调用上限。
    ///   - maxCallsPerTurn: 单轮调用上限。
    ///   - perToolLimits: 每个 MCP tool 的单独上限。
    ///   - duplicateArgumentStrategy: 重复参数调用处理策略。
    ///   - stopOnRateLimit: 是否在限流后停止继续调用 MCP。
    public init(
        maxTotalCalls: Int? = nil,
        maxCallsPerTurn: Int? = nil,
        perToolLimits: [AgentToolCallLimit] = [],
        duplicateArgumentStrategy: AgentDuplicateToolCallStrategy = .skipExactArguments,
        stopOnRateLimit: Bool = true
    ) {
        self.maxTotalCalls = maxTotalCalls
        self.maxCallsPerTurn = maxCallsPerTurn
        self.perToolLimits = perToolLimits
        self.duplicateArgumentStrategy = duplicateArgumentStrategy
        self.stopOnRateLimit = stopOnRateLimit
    }
}

/// 单个 MCP tool 的调用上限。
public struct AgentToolCallLimit: Sendable, Codable, Equatable {
    /// MCP tool 引用。
    public var ref: MCPToolRef
    /// 单次 Agent 运行允许的最大调用次数。
    public var maxCalls: Int

    /// 构造单工具调用上限。
    /// - Parameters:
    ///   - ref: MCP tool 引用。
    ///   - maxCalls: 单次 Agent 运行允许的最大调用次数。
    public init(ref: MCPToolRef, maxCalls: Int) {
        self.ref = ref
        self.maxCalls = maxCalls
    }
}

/// 参数完全相同的重复 MCP 调用处理策略。
public enum AgentDuplicateToolCallStrategy: String, Sendable, Codable, CaseIterable {
    /// 不去重，完全按模型请求执行。
    case allow
    /// 跳过同一 MCP tool + 完全相同 JSON 参数的重复调用。
    case skipExactArguments
}
