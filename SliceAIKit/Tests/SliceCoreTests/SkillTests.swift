import XCTest
@testable import SliceCore

final class SkillTests: XCTestCase {

    func test_skillManifest_codable() throws {
        let m = SkillManifest(
            name: "English Tutor",
            description: "Grammar + rewrite",
            version: "1.0.0",
            triggers: ["selection.language == en"],
            requiredCapabilities: [.toolCalling, .vision]
        )
        let data = try JSONEncoder().encode(m)
        let decoded = try JSONDecoder().decode(SkillManifest.self, from: data)
        XCTAssertEqual(m, decoded)
    }

    func test_skillReference_codable() throws {
        let r = SkillReference(id: "english-tutor@1.0.0", pinVersion: "1.0.0")
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(SkillReference.self, from: data)
        XCTAssertEqual(r, decoded)
    }

    func test_skillReference_nilPin() throws {
        let r = SkillReference(id: "english-tutor@1.0.0", pinVersion: nil)
        let data = try JSONEncoder().encode(r)
        let decoded = try JSONDecoder().decode(SkillReference.self, from: data)
        XCTAssertEqual(r, decoded)
    }

    func test_skill_carriesProvenance() {
        let url = URL(fileURLWithPath: "/tmp/english-tutor")
        let s = Skill(
            id: "english-tutor@1.0.0",
            path: url,
            manifest: SkillManifest(name: "t", description: "d", version: "1.0.0", triggers: [], requiredCapabilities: []),
            resources: [],
            provenance: .firstParty
        )
        XCTAssertEqual(s.provenance, .firstParty)
    }
}
