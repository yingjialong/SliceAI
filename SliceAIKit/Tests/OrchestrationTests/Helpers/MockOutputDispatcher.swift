import Foundation
@testable import Orchestration

/// Task 3 Mock — conforms to the empty `OutputDispatcherProtocol` stub.
///
/// Task 10 will add `handle(chunk:mode:invocationId:) -> DispatchOutcome` conformance
/// once the protocol gains that method.
final class MockOutputDispatcher: OutputDispatcherProtocol {}
