import Capabilities
import Foundation

/// Task 3 Mock — conforms to the empty `SkillRegistryProtocol` stub.
///
/// Task 13 will add `resolve(_ ref: SkillReference) async throws -> ResolvedSkill` conformance
/// once the protocol gains that method.
final class MockSkillRegistry: SkillRegistryProtocol {}
