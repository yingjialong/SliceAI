import Foundation
@testable import Orchestration

/// Task 3 Mock — conforms to the empty `PermissionBrokerProtocol` stub.
///
/// Task 6 will add `gate(permission:provenance:isDryRun:) -> GateOutcome` conformance
/// once the protocol gains that method.
final class MockPermissionBroker: PermissionBrokerProtocol {}
