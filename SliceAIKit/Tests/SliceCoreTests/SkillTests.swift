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

    func test_skill_carriesProvenance_andRoundtrips() throws {
        let url = URL(fileURLWithPath: "/tmp/english-tutor")
        let s = Skill(
            id: "english-tutor@1.0.0",
            path: url,
            manifest: SkillManifest(name: "t", description: "d", version: "1.0.0", triggers: [], requiredCapabilities: []),
            resources: [SkillResource(relativePath: "assets/chart.png", mimeType: "image/png")],
            provenance: .firstParty
        )
        XCTAssertEqual(s.provenance, .firstParty)

        // round-trip：包含 resources 非空 + provenance 已填
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(Skill.self, from: data)
        XCTAssertEqual(s, decoded)
        XCTAssertEqual(decoded.provenance, .firstParty)
        XCTAssertEqual(decoded.resources.count, 1)
    }

    // MARK: - Golden JSON shape（锁定 struct 线上形状；防止 M3 rename / 字段重命名静默破坏 config 兼容）

    func test_skillManifest_goldenJSON_fieldOrder() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let m = SkillManifest(
            name: "English Tutor",
            description: "Grammar",
            version: "1.0.0",
            triggers: ["en"],
            requiredCapabilities: [.toolCalling]
        )
        let json = try XCTUnwrap(String(data: try enc.encode(m), encoding: .utf8))
        // sortedKeys：description < name < requiredCapabilities < triggers < version（字母序）
        XCTAssertEqual(
            json,
            #"{"description":"Grammar","name":"English Tutor","requiredCapabilities":["toolCalling"],"triggers":["en"],"version":"1.0.0"}"#
        )
    }

    func test_skillReference_goldenJSON_nilPinOmitsKey() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let r = SkillReference(id: "english@1.0.0", pinVersion: nil)
        let json = try XCTUnwrap(String(data: try enc.encode(r), encoding: .utf8))
        // Foundation 默认 encoder 对 nil 可选值的行为：key 省略
        XCTAssertEqual(json, #"{"id":"english@1.0.0"}"#)
        XCTAssertFalse(json.contains("\"pinVersion\""))
    }
}
