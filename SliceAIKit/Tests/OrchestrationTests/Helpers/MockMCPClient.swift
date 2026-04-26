import Capabilities
import Foundation

/// Task 3 Mock — conforms to the empty `MCPClientProtocol` stub.
///
/// Task 13 will add `call(server:tool:args:) async throws -> MCPCallResult` conformance
/// once the protocol gains that method.
final class MockMCPClient: MCPClientProtocol {}
