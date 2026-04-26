import Foundation
@testable import Orchestration

/// Task 3 Mock — conforms to the empty `AuditLogProtocol` stub.
///
/// Task 9 will add `append(_ entry: AuditEntry) async throws` conformance
/// once the protocol gains that method.
final class MockAuditLog: AuditLogProtocol {}
