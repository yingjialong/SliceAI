import Foundation

/// **Task 3 STUB** — full implementation in Task 9 (M2.5 AuditLogProtocol + JSONLAuditLog).
///
/// Empty body so `ExecutionEngine` can use `any AuditLogProtocol` in its init.
/// Task 9 will add `func append(_ entry: AuditEntry) async throws`
/// and the `AuditEntry` enum with full redaction support.
public protocol AuditLogProtocol: Sendable {}
