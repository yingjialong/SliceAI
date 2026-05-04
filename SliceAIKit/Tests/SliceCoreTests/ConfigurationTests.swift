import XCTest
@testable import SliceCore

final class ConfigurationTests: XCTestCase {

    func test_configuration_currentSchemaVersion_is2() {
        XCTAssertEqual(Configuration.currentSchemaVersion, 2)
    }

    func test_defaultConfiguration_usesSchemaVersion2() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.schemaVersion, 2)
    }

    func test_defaultConfiguration_hasFourPromptTools_firstPartyProvenance() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.tools.count, 4)
        for tool in cfg.tools {
            XCTAssertEqual(tool.provenance, .firstParty)
            guard case .prompt = tool.kind else {
                XCTFail("tool \(tool.id) is not .prompt kind"); continue
            }
        }
    }

    func test_defaultConfiguration_providerIsOpenAICompatible() {
        let cfg = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.providers.count, 1)
        XCTAssertEqual(cfg.providers[0].kind, .openAICompatible)
    }

    func test_configuration_roundtrip() throws {
        let cfg = DefaultConfiguration.initial()
        let data = try JSONEncoder().encode(cfg)
        let decoded = try JSONDecoder().decode(Configuration.self, from: data)
        XCTAssertEqual(cfg, decoded)
    }
}
