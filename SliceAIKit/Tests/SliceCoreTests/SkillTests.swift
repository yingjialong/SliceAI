import XCTest
@testable import SliceCore

final class SkillTests: XCTestCase {

    func test_skillSettings_defaultsRoundTrip() throws {
        let settings = SkillSettings(
            sources: [
                SkillSource(
                    id: "source-home",
                    displayName: "Home Skills",
                    rootPath: "/Users/test/.agents/skills",
                    isEnabled: true,
                    order: 0
                )
            ],
            overrides: ["writing": .off]
        )

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(SkillSettings.self, from: data)

        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.overrides["writing"], .off)
    }

    func test_skillManifest_minimalCodableFields() throws {
        let manifest = SkillManifest(
            name: "writing",
            description: "Use when editing long-form text.",
            disableModelInvocation: false,
            allowedTools: ["Bash", "Read"],
            userInvocable: true,
            rawFrontmatter: "name: writing",
            instructionsCharacterCount: 120
        )

        let data = try JSONEncoder().encode(manifest)
        let decoded = try JSONDecoder().decode(SkillManifest.self, from: data)

        XCTAssertEqual(decoded, manifest)
    }

    func test_skillManifest_decodesMissingPhase2FieldsWithDefaults() throws {
        let json = Data(#"""
        {
          "name": "legacy",
          "description": "Legacy manifest."
        }
        """#.utf8)

        let decoded = try JSONDecoder().decode(SkillManifest.self, from: json)

        XCTAssertEqual(decoded.name, "legacy")
        XCTAssertEqual(decoded.description, "Legacy manifest.")
        XCTAssertFalse(decoded.disableModelInvocation)
        XCTAssertEqual(decoded.allowedTools, [])
        XCTAssertNil(decoded.userInvocable)
        XCTAssertEqual(decoded.rawFrontmatter, "")
        XCTAssertEqual(decoded.instructionsCharacterCount, 0)
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

    func test_skill_carriesSourceStateAndRoundtrips() throws {
        let root = URL(fileURLWithPath: "/tmp/english-tutor")
        let skill = Skill(
            id: "english-tutor",
            canonicalName: "english-tutor",
            path: root,
            skillFile: root.appendingPathComponent("SKILL.md"),
            manifest: SkillManifest(name: "English Tutor", description: "Grammar"),
            resources: [SkillResource(relativePath: "assets/chart.png", mimeType: "image/png")],
            provenance: .firstParty,
            source: SkillSourceRef(sourceId: "source-home", rootPath: "/tmp"),
            state: .enabled
        )
        XCTAssertEqual(skill.provenance, .firstParty)
        XCTAssertEqual(skill.source.sourceId, "source-home")
        XCTAssertEqual(skill.state, .enabled)

        let data = try JSONEncoder().encode(skill)
        let decoded = try JSONDecoder().decode(Skill.self, from: data)
        XCTAssertEqual(skill, decoded)
        XCTAssertEqual(decoded.provenance, .firstParty)
        XCTAssertEqual(decoded.resources.count, 1)
    }

    // MARK: - Golden JSON shape（锁定 struct 线上形状；防止字段重命名静默破坏 config 兼容）

    func test_skillManifest_goldenJSON_fieldOrder() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let manifest = SkillManifest(
            name: "writing",
            description: "Grammar",
            disableModelInvocation: true,
            allowedTools: ["Read"],
            userInvocable: false,
            rawFrontmatter: "name: writing",
            instructionsCharacterCount: 10
        )
        let json = try XCTUnwrap(String(data: try enc.encode(manifest), encoding: .utf8))
        XCTAssertEqual(
            json,
            #"{"allowedTools":["Read"],"description":"Grammar","disableModelInvocation":true,"instructionsCharacterCount":10,"name":"writing","rawFrontmatter":"name: writing","userInvocable":false}"#
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
