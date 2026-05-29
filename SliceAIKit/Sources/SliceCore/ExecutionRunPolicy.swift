import Foundation

/// 一次执行的来源；用于区分生产触发和 Settings Playground 试跑。
public enum ExecutionRunSource: String, Sendable, Codable, Equatable {
    /// 浮条、命令面板、工具热键等真实生产触发。
    case production
    /// Settings 中的 Prompt Playground 试跑。
    case playground
}

/// SideEffect 执行模式。
public enum SideEffectRunMode: String, Sendable, Codable, Equatable {
    /// 真实执行剪贴板、文件、通知、TTS 等副作用。
    case real
    /// 只产出 dry-run 事件，不执行真实副作用。
    case dryRun
}

/// Agent MCP tool call 执行模式。
public enum MCPToolCallRunMode: String, Sendable, Codable, Equatable {
    /// 禁止真实 MCP tool call，模型提出调用时返回受控拒绝。
    case disabled
    /// 允许真实 MCP tool call，但必须经过 allowlist 与 PermissionBroker。
    case realWithPermissionBroker
}

/// 输出路由模式。
public enum OutputRoutingMode: String, Sendable, Codable, Equatable {
    /// 使用生产 ResultPanel / BubblePanel / Replace / File 等输出依赖。
    case production
    /// 输出只进入 Settings Playground 预览依赖。
    case playgroundPreview
}

/// 一次执行的运行策略。
///
/// `ExecutionSeed.isDryRun` 继续表示“副作用 dry-run / dry-run outcome”，
/// 本类型补充 source、MCP 与输出路由语义，避免 Playground 复用含混布尔值。
public struct ExecutionRunPolicy: Sendable, Codable, Equatable {
    /// 本次执行的来源。
    public let source: ExecutionRunSource
    /// SideEffect 执行模式。
    public let sideEffects: SideEffectRunMode
    /// Agent MCP tool call 执行模式。
    public let mcpToolCalls: MCPToolCallRunMode
    /// 输出路由模式。
    public let outputRouting: OutputRoutingMode

    /// 构造运行策略。
    public init(
        source: ExecutionRunSource,
        sideEffects: SideEffectRunMode,
        mcpToolCalls: MCPToolCallRunMode,
        outputRouting: OutputRoutingMode
    ) {
        self.source = source
        self.sideEffects = sideEffects
        self.mcpToolCalls = mcpToolCalls
        self.outputRouting = outputRouting
    }

    /// 生产触发默认策略。
    public static func production(isDryRun: Bool) -> ExecutionRunPolicy {
        ExecutionRunPolicy(
            source: .production,
            sideEffects: isDryRun ? .dryRun : .real,
            mcpToolCalls: .realWithPermissionBroker,
            outputRouting: .production
        )
    }

    /// Playground 试跑默认策略。
    public static func playground(allowMCPToolCalls: Bool) -> ExecutionRunPolicy {
        ExecutionRunPolicy(
            source: .playground,
            sideEffects: .dryRun,
            mcpToolCalls: allowMCPToolCalls ? .realWithPermissionBroker : .disabled,
            outputRouting: .playgroundPreview
        )
    }
}
