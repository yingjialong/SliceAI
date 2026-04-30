import Foundation
import SliceCore

/// 一次 `ExecutionEngine.execute(...)` 的完整审计快照——成功 / 失败 / 被拒都产出。
///
/// 由 `ExecutionEngine` 在 Step 9 写入 `AuditLog`；同时作为 `.finished(report:)` 事件
/// 的 payload 暴露给调用方。
///
/// **D-24 闭环字段**：`declaredPermissions` 与 `effectivePermissions` 的 diff
/// 用于审计实际访问与声明的偏差；即便 ⊆ 校验通过，diff 仍然记录。
public struct InvocationReport: Sendable, Equatable, Codable {
    /// 与 `.started(invocationId:)` 一致
    public let invocationId: UUID

    /// 触发的 Tool 标识（不存原 manifest，避免敏感字段进 AuditLog）
    public let toolId: String

    /// Tool.permissions 静态声明
    public let declaredPermissions: Set<Permission>

    /// 实际触发（PermissionGraph.compute 聚合后的并集）
    public let effectivePermissions: Set<Permission>

    /// effective - declared；非空时表示有"未声明的实际访问"，会触发 .permissionUndeclared flag
    public var undeclaredPermissions: Set<Permission> {
        effectivePermissions.subtracting(declaredPermissions)
    }

    /// 关键事件标记：unauthorized access / dry-run / partial-failure / ...
    public let flags: Set<InvocationFlag>

    // MARK: - Timing & cost

    /// 主流程启动时刻（ExecutionEngine.execute 入口写入）
    public let startedAt: Date
    /// 主流程终止时刻（finishSuccess / finishFailure 写入）
    public let finishedAt: Date
    /// 整次 invocation 累计 token（input + output；M2 估算 / Phase 1 真实 LLM usage）
    public let totalTokens: Int
    /// 整次 invocation 估算成本（USD，Decimal 保精度）
    public let estimatedCostUSD: Decimal

    /// 执行结果（success / failed(errorKind:) / dryRunCompleted 三态）
    public let outcome: InvocationOutcome

    /// 构造 InvocationReport
    /// - Parameters:
    ///   - invocationId: 与 `.started` 事件一致的唯一标识
    ///   - toolId: Tool 的 id，不携带敏感信息
    ///   - declaredPermissions: Tool 静态声明的权限集合
    ///   - effectivePermissions: 运行时实际触发的权限集合
    ///   - flags: 关键事件标记集合
    ///   - startedAt: 执行开始时间
    ///   - finishedAt: 执行结束时间
    ///   - totalTokens: 消耗 token 总数
    ///   - estimatedCostUSD: 估算 USD 成本
    ///   - outcome: 最终执行结果三态
    public init(
        invocationId: UUID,
        toolId: String,
        declaredPermissions: Set<Permission>,
        effectivePermissions: Set<Permission>,
        flags: Set<InvocationFlag>,
        startedAt: Date,
        finishedAt: Date,
        totalTokens: Int,
        estimatedCostUSD: Decimal,
        outcome: InvocationOutcome
    ) {
        self.invocationId = invocationId
        self.toolId = toolId
        self.declaredPermissions = declaredPermissions
        self.effectivePermissions = effectivePermissions
        self.flags = flags
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.totalTokens = totalTokens
        self.estimatedCostUSD = estimatedCostUSD
        self.outcome = outcome
    }
}

/// 关键事件标记；使用 rawValue String 便于 JSON 持久化与 AuditLog 查询
public enum InvocationFlag: String, Sendable, Codable, Hashable, Equatable {
    /// dry-run 模式执行（不产生真实副作用）
    case dryRun
    /// 实际触发了 Tool 未声明的权限
    case permissionUndeclared
    /// 部分步骤失败但整体流程未中止
    case partialFailure
    /// 检测到沙箱路径违规
    case sandboxViolation
}

/// InvocationReport 的 outcome 字段类型；区分成功 / 失败 / dry-run 完成三种终态。
///
/// `failed` case 携带 `errorKind: ErrorKind`——SliceError 各顶层类的简化映射，
/// 让 AuditLog 按错误类型聚合查询。**不**直接携带 SliceError 因为 SliceError 关联值
/// 多含敏感字符串、Codable / 脱敏复杂度高，errorKind 抽象层兼顾审计与隐私。
public enum InvocationOutcome: Sendable, Codable, Equatable {
    /// 执行成功完成
    case success
    /// 执行失败，携带错误大类
    case failed(errorKind: ErrorKind)
    /// dry-run 模式完成（未产生真实副作用）
    case dryRunCompleted

    /// 错误大类（与 SliceError 顶层 case 对齐）
    public enum ErrorKind: String, Sendable, Codable, Equatable {
        /// 选区捕获失败
        case selection
        /// LLM provider 调用失败
        case provider
        /// 配置加载 / 校验失败
        case configuration
        /// 系统权限错误（accessibilityDenied / inputMonitoringDenied）
        case permission
        /// v2 上下文采集错误（SliceError.context(ContextError)）
        case context
        /// v2 工具权限决策错误（SliceError.toolPermission(ToolPermissionError)）
        case toolPermission
        /// 执行链顶层错误（SliceError.execution(ExecutionError)）
        case execution
    }
}

extension InvocationOutcome.ErrorKind {
    /// 把 SliceError 顶层 case 映射到 InvocationOutcome.ErrorKind
    ///
    /// 使用 exhaustive switch（无 default）——SliceError 新增顶层 case 时编译器强制更新此映射。
    public static func from(_ error: SliceError) -> InvocationOutcome.ErrorKind {
        switch error {
        case .selection:      return .selection
        case .provider:       return .provider
        case .configuration:  return .configuration
        case .permission:     return .permission
        case .context:        return .context
        case .toolPermission: return .toolPermission
        case .execution:      return .execution
        }
    }
}

#if DEBUG
extension InvocationReport {
    /// 单测 / Playground 用——固定 stub 值，避免测试代码重复构造 InvocationReport
    public static func stub(
        invocationId: UUID = UUID(),
        toolId: String = "test.tool",
        declared: Set<Permission> = [],
        effective: Set<Permission> = [],
        flags: Set<InvocationFlag> = [],
        outcome: InvocationOutcome = .success
    ) -> InvocationReport {
        InvocationReport(
            invocationId: invocationId,
            toolId: toolId,
            declaredPermissions: declared,
            effectivePermissions: effective,
            flags: flags,
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 1),
            totalTokens: 0,
            estimatedCostUSD: 0,
            outcome: outcome
        )
    }
}
#endif
