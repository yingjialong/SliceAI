import XCTest
import SliceCore
@testable import Capabilities

/// `SkillRegistryProtocol` 契约 + `MockSkillRegistry` 行为测试。
final class SkillRegistryProtocolTests: XCTestCase {

    /// 空 registry 的 snapshot 必须是合法空状态。
    func test_emptyRegistrySnapshotHasNoSkillsOrDiagnostics() async throws {
        let registry = MockSkillRegistry()

        let snapshot = try await registry.snapshot()
        let found = try await registry.findSkill(id: "missing")

        XCTAssertTrue(snapshot.sources.isEmpty)
        XCTAssertTrue(snapshot.skills.isEmpty)
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
        XCTAssertNil(found)
    }

    /// Mock 只返回 enabled skill；其他状态不应被 AgentExecutor 加载。
    func test_findSkillReturnsOnlyEnabledSkill() async throws {
        let enabled = makeSkill(name: "writing", state: .enabled)
        let disabled = makeSkill(name: "summary", state: .disabled)
        let registry = MockSkillRegistry(skills: [enabled, disabled])

        let foundEnabled = try await registry.findSkill(id: "writing")
        let foundDisabled = try await registry.findSkill(id: "summary")

        XCTAssertEqual(foundEnabled, enabled)
        XCTAssertNil(foundDisabled)
    }

    /// loadSkillInstructions 返回注入 payload，缺失 payload 时必须抛错。
    func test_loadSkillInstructionsReturnsInjectedPayloadAndThrowsForMissing() async throws {
        let skill = makeSkill(name: "writing", state: .enabled)
        let payload = makePayload(for: skill, instructions: "Write clearly.")
        let registry = MockSkillRegistry(skills: [skill], instructions: ["writing": payload])
        let loaded = try await registry.loadSkillInstructions(id: "writing")

        XCTAssertEqual(loaded, payload)
        do {
            _ = try await registry.loadSkillInstructions(id: "missing")
            XCTFail("expected missing payload to throw")
        } catch {
            // Expected.
        }
    }

    /// Snapshot 与 payload 必须能 Codable round-trip，供 UI 状态和测试 fixture 复用。
    func test_snapshotAndInstructionPayloadRoundTrip() throws {
        let skill = makeSkill(name: "writing", state: .enabled)
        let diagnostic = SkillRegistryDiagnostic(
            code: .missingDescription,
            sourceId: "source",
            path: "/tmp/writing/SKILL.md",
            message: "缺少 description。"
        )
        let snapshot = SkillRegistrySnapshot(
            sources: [SkillSource(id: "source", displayName: "Source", rootPath: "/tmp", isEnabled: true, order: 0)],
            skills: [skill],
            diagnostics: [diagnostic],
            generatedAt: Date(timeIntervalSinceReferenceDate: 123)
        )
        let payload = makePayload(for: skill, instructions: "Follow writing rules.")

        let decodedSnapshot = try JSONDecoder().decode(
            SkillRegistrySnapshot.self,
            from: JSONEncoder().encode(snapshot)
        )
        let decodedPayload = try JSONDecoder().decode(
            SkillInstructionPayload.self,
            from: JSONEncoder().encode(payload)
        )

        XCTAssertEqual(decodedSnapshot, snapshot)
        XCTAssertEqual(decodedPayload, payload)
    }
}

private func makeSkill(name: String, state: SkillRegistryState) -> Skill {
    let directory = URL(fileURLWithPath: "/tmp/\(name)", isDirectory: true)
    return Skill(
        id: name,
        canonicalName: name,
        path: directory,
        skillFile: directory.appendingPathComponent("SKILL.md"),
        manifest: SkillManifest(name: name, description: "\(name) description"),
        resources: [],
        provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSinceReferenceDate: 0)),
        source: SkillSourceRef(sourceId: "source", rootPath: "/tmp"),
        state: state
    )
}

private func makePayload(for skill: Skill, instructions: String) -> SkillInstructionPayload {
    SkillInstructionPayload(
        id: skill.id,
        canonicalName: skill.canonicalName,
        skillFile: skill.skillFile,
        frontmatterSummary: skill.manifest,
        instructions: instructions
    )
}
