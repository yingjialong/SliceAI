import Foundation
import SliceCore

/// 一次执行的权限静态聚合（spec §3.9.6.5）
///
/// 由 `PermissionGraph.compute(tool:)` 在执行前一次性算出：
/// - `declared` 取自 `tool.permissions`
/// - `fromContexts` / `fromSideEffects` / `fromMCP` / `fromBuiltins` 分别按来源汇总，
///   `union` 合并所有来源、`undeclared = union - declared` 即"漏报"集合
///
/// **D-24 不变量**：`undeclared.isEmpty == true` 才允许进入主流程；非空时
/// `ExecutionEngine` 必须抛 `SliceError.toolPermission(.undeclared(missing:))` 终止。
///
/// **不变性**：4 个 from* set 仅在构造时一次写入，外部不可修改——使聚合结果可被
/// `InvocationReport` 与 `AuditLog` 直接复用，避免漂移。
public struct EffectivePermissions: Sendable, Equatable {
    /// `tool.permissions` 静态声明集合（去重后的 Set）
    public let declared: Set<Permission>
    /// 来自 `tool.contexts` 中各 ContextProvider 的 `inferredPermissions(for:)` 聚合
    public let fromContexts: Set<Permission>
    /// 来自 `outputBinding.sideEffects` 中各 SideEffect 的 `inferredPermissions` 聚合
    public let fromSideEffects: Set<Permission>
    /// 来自 `agent.mcpAllowlist` / pipeline.mcp / sideEffect.callMCP 的 .mcp 权限聚合
    public let fromMCP: Set<Permission>
    /// 来自 `agent.builtinCapabilities` 的内置能力到 Permission 的映射聚合
    public let fromBuiltins: Set<Permission>

    /// 全部来源的并集（D-24 ⊆ 校验的左侧集合）
    public var union: Set<Permission> {
        fromContexts.union(fromSideEffects).union(fromMCP).union(fromBuiltins)
    }

    /// effective - declared；非空表示 D-24 闭环漏报
    public var undeclared: Set<Permission> { union.subtracting(declared) }

    /// 主初始化器
    /// - Parameters:
    ///   - declared: `tool.permissions` 转 Set 后的声明集合
    ///   - fromContexts: ContextProvider 推导的权限集合
    ///   - fromSideEffects: SideEffect 推导的权限集合
    ///   - fromMCP: MCP 引用聚合的权限集合
    ///   - fromBuiltins: AgentTool.builtinCapabilities 映射后的权限集合
    public init(
        declared: Set<Permission>,
        fromContexts: Set<Permission>,
        fromSideEffects: Set<Permission>,
        fromMCP: Set<Permission>,
        fromBuiltins: Set<Permission>
    ) {
        self.declared = declared
        self.fromContexts = fromContexts
        self.fromSideEffects = fromSideEffects
        self.fromMCP = fromMCP
        self.fromBuiltins = fromBuiltins
    }
}

// MARK: - .empty 静态字段（R8 B-1 修订）

extension EffectivePermissions {
    /// 全空聚合，便于 `ExecutionEngine` 构造空 V2Tool 测试 fixture / 默认占位
    public static let empty = EffectivePermissions(
        declared: [],
        fromContexts: [],
        fromSideEffects: [],
        fromMCP: [],
        fromBuiltins: []
    )
}
