import Foundation

/// Tool 的三种执行形态；数据模型的封闭集合（新形态通过 Pipeline 组合，不加第四态）
///
/// **手写 Codable（模板 A）**：产出 `{"prompt":{...}}` / `{"agent":{...}}` / `{"pipeline":{...}}`
/// —— 不使用 Swift 合成的 `_0` 形式。所有三态 case 的 associated value 已经是 struct，
/// 所以直接 encode payload 即可（无需嵌套 Repr）。含 Task 3/8/10/11/13 同款硬化
/// （allKeys.count == 1 guard + cleaner 未知键 throw）。
public enum ToolKind: Sendable, Equatable, Codable {
    /// 单次 LLM 调用（v1 默认形态）
    case prompt(PromptTool)
    /// LLM + MCP + skill 的 ReAct loop
    case agent(AgentTool)
    /// 多 step 编排；每个 step 可再调 tool / prompt / mcp / transform
    case pipeline(PipelineTool)

    private enum CodingKeys: String, CodingKey { case prompt, agent, pipeline }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "ToolKind requires exactly one key, got \(c.allKeys.count)"
            ))
        }
        if let p = try c.decodeIfPresent(PromptTool.self, forKey: .prompt) {
            self = .prompt(p); return
        }
        if let a = try c.decodeIfPresent(AgentTool.self, forKey: .agent) {
            self = .agent(a); return
        }
        if let p = try c.decodeIfPresent(PipelineTool.self, forKey: .pipeline) {
            self = .pipeline(p); return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: c.codingPath,
            debugDescription: "ToolKind encountered unknown case key"
        ))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .prompt(let p):   try c.encode(p, forKey: .prompt)
        case .agent(let a):    try c.encode(a, forKey: .agent)
        case .pipeline(let p): try c.encode(p, forKey: .pipeline)
        }
    }
}

/// 单次 LLM 调用配置
public struct PromptTool: Sendable, Codable, Equatable {
    public var systemPrompt: String?
    public var userPrompt: String
    public var contexts: [ContextRequest]
    public var provider: ProviderSelection
    public var temperature: Double?
    public var maxTokens: Int?
    public var variables: [String: String]

    /// 构造 PromptTool
    public init(
        systemPrompt: String?,
        userPrompt: String,
        contexts: [ContextRequest],
        provider: ProviderSelection,
        temperature: Double?,
        maxTokens: Int?,
        variables: [String: String]
    ) {
        self.systemPrompt = systemPrompt
        self.userPrompt = userPrompt
        self.contexts = contexts
        self.provider = provider
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.variables = variables
    }
}

/// Agentic 循环配置
public struct AgentTool: Sendable, Codable, Equatable {
    public var systemPrompt: String?
    public var initialUserPrompt: String
    public var contexts: [ContextRequest]
    public var provider: ProviderSelection
    public var skill: SkillReference?
    public var mcpAllowlist: [MCPToolRef]
    public var builtinCapabilities: [BuiltinCapability]
    public var maxSteps: Int
    public var stopCondition: StopCondition

    /// 构造 AgentTool
    public init(
        systemPrompt: String?,
        initialUserPrompt: String,
        contexts: [ContextRequest],
        provider: ProviderSelection,
        skill: SkillReference?,
        mcpAllowlist: [MCPToolRef],
        builtinCapabilities: [BuiltinCapability],
        maxSteps: Int,
        stopCondition: StopCondition
    ) {
        self.systemPrompt = systemPrompt
        self.initialUserPrompt = initialUserPrompt
        self.contexts = contexts
        self.provider = provider
        self.skill = skill
        self.mcpAllowlist = mcpAllowlist
        self.builtinCapabilities = builtinCapabilities
        self.maxSteps = maxSteps
        self.stopCondition = stopCondition
    }
}

/// Pipeline 工作流配置
public struct PipelineTool: Sendable, Codable, Equatable {
    public var steps: [PipelineStep]
    public var onStepFail: StepFailurePolicy

    /// 构造 PipelineTool
    public init(steps: [PipelineStep], onStepFail: StepFailurePolicy) {
        self.steps = steps
        self.onStepFail = onStepFail
    }
}

/// Pipeline 单个 step
///
/// **手写 Codable（模板 A + B，含 Task 3/8/10/11/13 同款硬化）**：多 associated value 的 case 用嵌套 Repr struct 做中转。
public enum PipelineStep: Sendable, Equatable, Codable {
    case tool(toolRef: String, input: String)
    case prompt(inline: PromptTool, input: String)
    case mcp(ref: MCPToolRef, args: [String: String])
    case transform(TransformOp)
    case branch(condition: ConditionExpr, onTrue: String, onFalse: String)

    private enum CodingKeys: String, CodingKey { case tool, prompt, mcp, transform, branch }
    private struct ToolRepr: Codable, Equatable { let toolRef: String; let input: String }
    private struct PromptRepr: Codable, Equatable { let inline: PromptTool; let input: String }
    private struct MCPRepr: Codable, Equatable { let ref: MCPToolRef; let args: [String: String] }
    private struct BranchRepr: Codable, Equatable {
        let condition: ConditionExpr
        let onTrue: String
        let onFalse: String
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "PipelineStep requires exactly one key, got \(c.allKeys.count)"
            ))
        }
        if let r = try c.decodeIfPresent(ToolRepr.self, forKey: .tool) {
            self = .tool(toolRef: r.toolRef, input: r.input); return
        }
        if let r = try c.decodeIfPresent(PromptRepr.self, forKey: .prompt) {
            self = .prompt(inline: r.inline, input: r.input); return
        }
        if let r = try c.decodeIfPresent(MCPRepr.self, forKey: .mcp) {
            self = .mcp(ref: r.ref, args: r.args); return
        }
        if let op = try c.decodeIfPresent(TransformOp.self, forKey: .transform) {
            self = .transform(op); return
        }
        if let r = try c.decodeIfPresent(BranchRepr.self, forKey: .branch) {
            self = .branch(condition: r.condition, onTrue: r.onTrue, onFalse: r.onFalse); return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: c.codingPath,
            debugDescription: "PipelineStep encountered unknown case key"
        ))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tool(let toolRef, let input):
            try c.encode(ToolRepr(toolRef: toolRef, input: input), forKey: .tool)
        case .prompt(let inline, let input):
            try c.encode(PromptRepr(inline: inline, input: input), forKey: .prompt)
        case .mcp(let ref, let args):
            try c.encode(MCPRepr(ref: ref, args: args), forKey: .mcp)
        case .transform(let op):
            try c.encode(op, forKey: .transform)
        case .branch(let condition, let onTrue, let onFalse):
            try c.encode(BranchRepr(condition: condition, onTrue: onTrue, onFalse: onFalse), forKey: .branch)
        }
    }
}

/// Pipeline 失败策略
public enum StepFailurePolicy: String, Sendable, Codable, CaseIterable {
    /// 任一 step 失败 → Pipeline 直接失败
    case abort
    /// 失败 step 跳过，继续下一 step
    case skip
}

/// Agent 停止条件
public enum StopCondition: String, Sendable, Codable, CaseIterable {
    /// LLM 返回 finalAnswer（finish_reason == stop 且无 tool call）
    case finalAnswerProvided
    /// 达到 maxSteps
    case maxStepsReached
    /// 某一轮 LLM 未发起 tool call（视作 agent 认为已答完）
    case noToolCall
}

/// 内置能力引用；`AgentTool.builtinCapabilities` 使用
public enum BuiltinCapability: String, Sendable, Codable, CaseIterable {
    case filesystem
    case shell
    case vision
    case tts
    case memory
    case screen
}

/// Pipeline `transform` step 的操作类型；M1 只定义少量 case
///
/// **手写 Codable（模板 C + B，含 Task 3/8/10/11/13 同款硬化）**
public enum TransformOp: Sendable, Equatable, Codable {
    case jq(String)
    case regex(pattern: String, replacement: String)
    case jsonPath(String)

    private enum CodingKeys: String, CodingKey { case jq, regex, jsonPath }
    private struct RegexRepr: Codable, Equatable { let pattern: String; let replacement: String }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "TransformOp requires exactly one key, got \(c.allKeys.count)"
            ))
        }
        if let s = try c.decodeIfPresent(String.self, forKey: .jq) { self = .jq(s); return }
        if let r = try c.decodeIfPresent(RegexRepr.self, forKey: .regex) {
            self = .regex(pattern: r.pattern, replacement: r.replacement); return
        }
        if let s = try c.decodeIfPresent(String.self, forKey: .jsonPath) { self = .jsonPath(s); return }
        throw DecodingError.dataCorrupted(.init(
            codingPath: c.codingPath,
            debugDescription: "TransformOp encountered unknown case key"
        ))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .jq(let s):                      try c.encode(s, forKey: .jq)
        case .regex(let p, let r):            try c.encode(RegexRepr(pattern: p, replacement: r), forKey: .regex)
        case .jsonPath(let s):                try c.encode(s, forKey: .jsonPath)
        }
    }
}
