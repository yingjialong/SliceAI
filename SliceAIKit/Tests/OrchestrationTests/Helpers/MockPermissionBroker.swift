import Foundation
import SliceCore
@testable import Orchestration

/// Task 6 Mock — 实现 `PermissionBrokerProtocol.gate` 接口，默认全部放行
///
/// **设计语义**：
/// - 默认行为 = 所有调用返回 `.approved`，让 Task 4 ExecutionEngine 集成测试可以走完
///   "permission gate 始终通过"的 happy path 而不需要构造真实 grant store / UI 决策
/// - 可选行为 = 通过 `outcomeOverride` 让测试场景注入特定 outcome（如 `.denied` 模拟拒绝、
///   `.requiresUserConsent` 模拟需弹 UI），覆盖各失败分支
/// - 可选行为 = 通过 `outcomeFunction` 让测试基于入参（effective set / 调用序号）按规则返回，
///   覆盖 partial-failure 这种"first sideEffect approved + second denied"的场景
/// - 可选行为 = 通过 `gateCalls` 计数器让测试断言 broker 被调用的次数与参数
///
/// **why actor**：内部含 mutable state（gateCalls / outcomeOverride 注入接口），
/// 与生产 `PermissionBroker` 一致用 actor 隔离，避免 `@unchecked Sendable` 锁逃逸。
final actor MockPermissionBroker: PermissionBrokerProtocol {

    // MARK: - 注入点

    /// 可选 outcome 覆盖：非 nil 时无视输入直接返回该值；nil 走 `.approved` 默认分支
    private var outcomeOverride: GateOutcome?

    /// 可选 outcome 函数：基于 (调用序号, 入参) 决定 outcome，优先级高于 `outcomeOverride`。
    /// 用于"按调用顺序返回不同 outcome"的场景（如 partial-failure 测试的多 sideEffect gate）。
    /// callIndex 从 0 起算。
    private var outcomeFunction:
        (@Sendable (Int, Set<Permission>, Provenance, GrantScope, Bool) -> GateOutcome)?

    /// 调用记录：每次 `gate` 入参快照（test 侧可断言"broker 被调几次 / 入参是什么"）
    private(set) var gateCalls: [GateInvocation] = []

    // MARK: - Init

    /// 构造 Mock；默认返回 `.approved`（happy path）
    /// - Parameters:
    ///   - outcomeOverride: 固定返回值；默认 nil = .approved
    ///   - outcomeFunction: 函数式 outcome 决策；优先级高于 `outcomeOverride`
    init(
        outcomeOverride: GateOutcome? = nil,
        outcomeFunction:
            (@Sendable (Int, Set<Permission>, Provenance, GrantScope, Bool) -> GateOutcome)? = nil
    ) {
        self.outcomeOverride = outcomeOverride
        self.outcomeFunction = outcomeFunction
    }

    // MARK: - PermissionBrokerProtocol

    /// gate 实现：记录调用 + 按"function > override > .approved"优先级返回
    func gate(
        effective: Set<Permission>,
        provenance: Provenance,
        scope: GrantScope,
        isDryRun: Bool
    ) async -> GateOutcome {
        let callIndex = gateCalls.count
        gateCalls.append(GateInvocation(
            effective: effective,
            provenance: provenance,
            scope: scope,
            isDryRun: isDryRun
        ))
        if let function = outcomeFunction {
            return function(callIndex, effective, provenance, scope, isDryRun)
        }
        return outcomeOverride ?? .approved
    }

    // MARK: - 测试辅助

    /// 在测试中切换 override（如某个 step 后改返回 .denied）
    /// - Parameter outcome: 新的固定返回值
    func setOutcome(_ outcome: GateOutcome?) {
        outcomeOverride = outcome
    }

    /// 在测试中切换函数式 outcome 决策
    func setOutcomeFunction(
        _ function: @escaping @Sendable (Int, Set<Permission>, Provenance, GrantScope, Bool) -> GateOutcome
    ) {
        outcomeFunction = function
    }

    /// 单次调用快照
    struct GateInvocation: Sendable, Equatable {
        let effective: Set<Permission>
        let provenance: Provenance
        let scope: GrantScope
        let isDryRun: Bool
    }
}
