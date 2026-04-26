import Foundation

/// **Task 3 STUB** — full implementation in Task 10 (M2.6 OutputDispatcher).
///
/// Empty body so `ExecutionEngine` can use `any OutputDispatcherProtocol` in its init.
/// Task 10 will add
/// `func handle(chunk: String, mode: PresentationMode, invocationId: UUID) async throws -> DispatchOutcome`.
public protocol OutputDispatcherProtocol: Sendable {}
