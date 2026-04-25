import XCTest
@testable import SliceCore

final class V2ConfigurationTests: XCTestCase {

    func test_v2Configuration_currentSchemaVersion_is2() {
        XCTAssertEqual(V2Configuration.currentSchemaVersion, 2)
    }

    func test_defaultV2Configuration_usesSchemaVersion2() {
        let cfg = DefaultV2Configuration.initial()
        XCTAssertEqual(cfg.schemaVersion, 2)
    }

    func test_defaultV2Configuration_hasFourPromptTools_firstPartyProvenance() {
        let cfg = DefaultV2Configuration.initial()
        XCTAssertEqual(cfg.tools.count, 4)
        for tool in cfg.tools {
            XCTAssertEqual(tool.provenance, .firstParty)
            guard case .prompt = tool.kind else {
                XCTFail("tool \(tool.id) is not .prompt kind"); continue
            }
        }
    }

    func test_defaultV2Configuration_providerIsOpenAICompatible() {
        let cfg = DefaultV2Configuration.initial()
        XCTAssertEqual(cfg.providers.count, 1)
        XCTAssertEqual(cfg.providers[0].kind, .openAICompatible)
    }

    func test_v2Configuration_roundtrip() throws {
        let cfg = DefaultV2Configuration.initial()
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(V2Configuration.self, from: data)
        XCTAssertEqual(cfg, decoded)
    }

    // 关键不变量：v1 Configuration 的 currentSchemaVersion 保持为 1
    func test_v1Configuration_currentSchemaVersion_unchanged() {
        XCTAssertEqual(Configuration.currentSchemaVersion, 1)
    }
}
