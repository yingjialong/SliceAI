import Foundation

/// **Task 3 STUB** — full implementation in Task 6 (M2.3 PermissionBrokerProtocol + 默认实现).
///
/// Empty body so `ExecutionEngine` can use `any PermissionBrokerProtocol` in its init.
/// Task 6 will add `func gate(permission:provenance:isDryRun:) async throws -> GateOutcome`
/// and the full 4-state `GateOutcome` type.
public protocol PermissionBrokerProtocol: Sendable {}
