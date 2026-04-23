import XCTest
@testable import SliceCore

final class V2ConfigurationStoreTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() async throws {
        try await super.setUp()
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("sliceai-v2test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: tempDir)
        try await super.tearDown()
    }

    // MARK: - Path selection

    func test_standardV2FileURL_endsWith_config_v2_json() {
        let url = V2ConfigurationStore.standardV2FileURL()
        XCTAssertEqual(url.lastPathComponent, "config-v2.json")
        XCTAssertTrue(url.path.contains("/SliceAI/"))
    }

    func test_legacyV1FileURL_endsWith_config_json() {
        let url = V2ConfigurationStore.legacyV1FileURL()
        XCTAssertEqual(url.lastPathComponent, "config.json")
    }

    // MARK: - Migration on first launch

    func test_load_withV1Only_migratesToV2AndLeavesV1Intact() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        // 准备 v1 文件
        let v1Data = try fixtureData("config-v1-minimal")
        try v1Data.write(to: v1URL, options: .atomic)

        // 构造 v2 store 读 v2 路径；应触发自动迁移
        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.load()

        XCTAssertEqual(cfg.schemaVersion, 2)
        XCTAssertEqual(cfg.tools.count, 1)

        // v2 文件已被写入
        XCTAssertTrue(FileManager.default.fileExists(atPath: v2URL.path))
        // v1 文件原样保留（bytes 不变）
        let preservedV1 = try Data(contentsOf: v1URL)
        XCTAssertEqual(preservedV1, v1Data)
    }

    func test_load_withV2Existing_readsV2_ignoresV1() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        // 准备 v2 文件（用 DefaultV2Configuration 做样本，改一个可辨识字段）
        var v2Template = DefaultV2Configuration.initial()
        v2Template = V2Configuration(
            schemaVersion: v2Template.schemaVersion,
            providers: [], tools: [],
            hotkeys: HotkeyBindings(toggleCommandPalette: "option+z"),
            triggers: v2Template.triggers,
            telemetry: v2Template.telemetry,
            appBlocklist: v2Template.appBlocklist,
            appearance: v2Template.appearance
        )
        let v2Data = try JSONEncoder().encode(v2Template)
        try v2Data.write(to: v2URL, options: .atomic)

        // 同时准备一个 v1 文件——应被忽略
        let v1Data = try fixtureData("config-v1-minimal")
        try v1Data.write(to: v1URL, options: .atomic)

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.load()

        XCTAssertEqual(cfg.hotkeys.toggleCommandPalette, "option+z")
        XCTAssertEqual(cfg.tools.count, 0)
    }

    func test_load_withNeither_returnsDefaultV2() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.load()

        XCTAssertEqual(cfg.schemaVersion, 2)
        XCTAssertEqual(cfg.tools.count, 4)  // 4 个内置工具（DefaultV2Configuration）
    }

    // MARK: - Write behaviour

    func test_save_writesOnlyToV2Path_neverTouchesV1() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        let v1Data = try fixtureData("config-v1-minimal")
        try v1Data.write(to: v1URL, options: .atomic)

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = DefaultV2Configuration.initial()
        try await store.save(cfg)

        XCTAssertTrue(FileManager.default.fileExists(atPath: v2URL.path))
        let preservedV1 = try Data(contentsOf: v1URL)
        XCTAssertEqual(preservedV1, v1Data)
    }

    // 关键不变量：v1 FileConfigurationStore 与 V2ConfigurationStore 完全隔离；
    // v1 store 的 currentSchemaVersion 仍是 1
    func test_v1Store_unchanged_stillWritesSchemaVersion1() async throws {
        let v1URL = tempDir.appendingPathComponent("config-v1-test.json")
        let v1Store = FileConfigurationStore(fileURL: v1URL)  // 现有 v1 API
        try await v1Store.save(DefaultConfiguration.initial())

        let data = try Data(contentsOf: v1URL)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains("\"schemaVersion\" : 1"), "v1 store must write schemaVersion=1; got: \(json)")
    }

    // MARK: - Helper

    private func fixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
