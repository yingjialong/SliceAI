import Foundation
import SliceCore

/// PermissionBroker 弹窗 UX 的文案 hint
///
/// **设计语义**（KISS）：跨边界传递时与 `ExecutionEvent.permissionWouldBeRequested(uxHint:)`
/// 的 String 形态保持一致；M2 阶段不引入额外 struct，避免编/解码与跨模块同步成本。生产路径（M3+）若
/// 需要更结构化的字段（headline / detail / dialogStyle），届时再升级为 struct——届时改动的是 broker 内
/// 的 hint 构造函数与 Playground 消费端，与 schema/json round-trip 无关。
public typealias ConsentUXHint = String

/// 权限确认请求；由 `PermissionBroker` 生成，UI 或测试 presenter 只负责展示并返回决策
public struct PermissionConsentRequest: Sendable, Equatable {
    /// 待确认的权限
    public let permission: Permission
    /// 工具来源；只影响 UX 文案，不降低权限下限
    public let provenance: Provenance
    /// UI 文案 hint
    public let uxHint: ConsentUXHint
    /// 当前运行时允许用户选择的授权范围
    public let allowedScopes: [GrantScope]

    /// 构造权限确认请求
    /// - Parameters:
    ///   - permission: 待确认的权限。
    ///   - provenance: 工具来源。
    ///   - uxHint: UI 文案 hint。
    ///   - allowedScopes: 当前运行时允许选择的授权范围。
    public init(
        permission: Permission,
        provenance: Provenance,
        uxHint: ConsentUXHint,
        allowedScopes: [GrantScope]
    ) {
        self.permission = permission
        self.provenance = provenance
        self.uxHint = uxHint
        self.allowedScopes = allowedScopes
    }
}

/// 权限确认决策
public enum PermissionConsentDecision: Sendable, Equatable {
    /// 用户批准某个授权范围
    case approve(scope: GrantScope)
    /// 用户拒绝，并返回脱敏原因
    case deny(reason: String)
}

/// UI-free 权限确认协议；Orchestration 只依赖该协议，不直接依赖 AppKit 或具体 UI
public protocol PermissionConsentPresenting: Sendable {
    /// 请求用户确认某条权限
    /// - Parameter request: 权限确认请求。
    /// - Returns: 用户决策。
    func requestConsent(_ request: PermissionConsentRequest) async -> PermissionConsentDecision
}

/// PermissionBroker.gate 的决策结果（**4 态**）：三个非 approved 态都带
/// `permission: Permission` 关联值，便于 caller 知道是哪条权限触发的决策。
///
/// **why non-throwing**：用 4 态 enum 表达"通过 / 拒绝 / 需 UI 确认 / dry-run 替代占位"
/// 比抛错更清晰；caller 只 `await` 不需 `try`。新增 case 时务必同步 ExecutionEngine 主流程的
/// exhaustive switch（CI 用 `grep default:` 反向断言保障无 default 兜底）。
///
/// **dry-run 行为不豁免下限**：`isDryRun=true` 时 broker 仍然计算下限；只是把所有
/// 需要运行期确认的下限替换为 `.wouldRequireConsent` 让 Playground 显示"如果实际执行会需要 X 权限"，
/// **严禁** dry-run 静默 `.approved` 或调用 presenter。
public enum GateOutcome: Sendable, Equatable {
    /// 通过：已有 grant 命中（或 tier 不需要确认，如 readonly-local + 非 unknown）
    case approved

    /// 拒绝某条具体 permission
    /// - Parameters:
    ///   - permission: 触发拒绝的具体 permission（caller 可据此显示"X 权限被拒"）
    ///   - reason: 脱敏后的拒绝原因（如 "blacklisted host" / "user previously denied"）
    case denied(permission: Permission, reason: String)

    /// 需要弹 UI 让用户确认某条具体 permission。
    ///
    /// Task 8 后生产 `PermissionBroker` 会通过 presenter 解析 non-dry-run consent，
    /// 该 case 主要保留给测试替身和兼容调用方。
    /// - Parameters:
    ///   - permission: 等待用户确认的 permission
    ///   - uxHint: 弹窗文案 hint（按 §3.9.1 表合并 tier × provenance 后的文案强度）
    case requiresUserConsent(permission: Permission, uxHint: ConsentUXHint)

    /// dry-run 路径下，本应弹确认但被替换为占位事件的 permission；caller 收到后跳过实际副作用、继续主流程
    /// - Parameters:
    ///   - permission: 本应被确认的 permission
    ///   - uxHint: 与 `.requiresUserConsent` 同源的文案 hint（Playground UI 直接展示）
    case wouldRequireConsent(permission: Permission, uxHint: ConsentUXHint)
}

/// 权限决策代理协议（Orchestration `ExecutionEngine` 在 Step 2.5 / Step 7 调用）
///
/// 设计要点：
/// - **non-throwing**：决策结果 4 态收敛到 `GateOutcome`；底层异常（如 grant store 内部错误）由实现内部
///   捕获后转 `.denied(...)` 返回，不向上游抛；签名与 §C-10.1 audit 表一致。
/// - **`Sendable` 约束**：默认实现 `PermissionBroker` 是 actor；`MockPermissionBroker` 是 `final class`
///   也按 protocol 的 `Sendable` 要求标 `@unchecked Sendable` / actor。
/// - **必须实现 short-circuit**：实现侧对 `effective` set 中第一个非 `.approved` 的 permission 即返回，
///   避免逐条弹 UI 让用户疲劳；详见 `PermissionBroker.gate` 注释。
public protocol PermissionBrokerProtocol: Sendable {
    /// 对 `effective` 集合中所有 permission 做 gate 决策
    /// - Parameters:
    ///   - effective: 当前 invocation 的 `EffectivePermissions.union`（context / sideEffect / mcp / builtin / declared 合集）
    ///   - provenance: 工具来源；只能调节 UX hint 文案，**严禁** 影响 lowerBound 决策
    ///   - scope: 调用方建议的 grant 时长；生产 broker 根据权限风险和 store 可用性决定是否接受
    ///     one-time / session / persistent runtime grant。
    ///   - isDryRun: 是否 dry-run；true 时不会调用 presenter，需要 consent 的权限返回 `.wouldRequireConsent`
    /// - Returns: `GateOutcome` 4 态决策结果；non-throwing
    func gate(
        effective: Set<Permission>,
        provenance: Provenance,
        scope: GrantScope,
        isDryRun: Bool
    ) async -> GateOutcome
}
