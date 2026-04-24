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

    // MARK: - current() 抛错语义（P1 修复：禁止吞错回退默认，防止覆盖丢失）

    /// 覆盖"v2 JSON 损坏时 current() 必须 throw invalidJSON"
    ///
    /// 修复前：current() 用 `try? await load()` 吞错 → 回退 DefaultV2Configuration.initial() →
    /// 下次 update() 把默认值写回原路径 → 用户原有 providers / tools 永久丢失。
    /// 修复后：load() 的 throw 原样向外传播，调用方（M3 AppContainer）必须显式处理。
    func test_current_throwsOnCorruptedV2JSON() async throws {
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        try Data("{ not valid json".utf8).write(to: v2URL, options: .atomic)

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: nil)
        do {
            _ = try await store.current()
            XCTFail("current() 必须在 v2 JSON 损坏时 throw")
        } catch SliceError.configuration(.invalidJSON) {
            // expected
        } catch {
            XCTFail("expected .configuration(.invalidJSON), got \(error)")
        }
    }

    /// schemaVersion 高于当前应用时 current() 必须 throw，避免用默认配置覆盖未来版本
    func test_current_throwsOnSchemaTooNew() async throws {
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        // 基于 DefaultV2Configuration 合成合法 JSON，仅改 schemaVersion = 999
        let template = DefaultV2Configuration.initial()
        let future = V2Configuration(
            schemaVersion: 999,
            providers: template.providers,
            tools: template.tools,
            hotkeys: template.hotkeys,
            triggers: template.triggers,
            telemetry: template.telemetry,
            appBlocklist: template.appBlocklist,
            appearance: template.appearance
        )
        let data = try JSONEncoder().encode(future)
        try data.write(to: v2URL, options: .atomic)

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: nil)
        do {
            _ = try await store.current()
            XCTFail("current() 必须 throw schemaVersionTooNew")
        } catch SliceError.configuration(.schemaVersionTooNew(let v)) {
            XCTAssertEqual(v, 999)
        } catch {
            XCTFail("expected .configuration(.schemaVersionTooNew), got \(error)")
        }
    }

    /// v2 不存在但 v1 文件损坏时，current() 必须 throw，避免无声丢失 v1 数据
    func test_current_throwsOnCorruptedLegacyJSON() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        try Data("bad".utf8).write(to: v1URL, options: .atomic)

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        do {
            _ = try await store.current()
            XCTFail("current() 必须在 v1 JSON 损坏时 throw")
        } catch SliceError.configuration(.invalidJSON) {
            // expected
        } catch {
            XCTFail("expected .configuration(.invalidJSON), got \(error)")
        }
    }

    /// 两个路径都不存在是合法情况（首次启动）：必须返回默认配置，不抛错
    func test_current_fallsBackWhenBothMissing() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.current()

        XCTAssertEqual(cfg.schemaVersion, V2Configuration.currentSchemaVersion)
        XCTAssertEqual(cfg.tools.count, 4)  // DefaultV2Configuration 4 个内置工具
    }

    // MARK: - 写入边界 validation（第八轮 P2-1/P2-2 修复）
    //
    // save() 必须"先 validate，再 write"——validate throw 时磁盘不得被写入。
    // 测试策略：构造一个包含非法 Provider / Tool 的 V2Configuration，断言
    // save() throw .validationFailed 且 config-v2.json 不存在。

    /// 包含 openAICompatible + nil baseURL 的 Provider 时 save() 必须拒绝写入
    func test_save_rejectsConfigWithInvalidProvider() async throws {
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: nil)

        // 故意构造非法 Provider：kind=openAICompatible 却把 baseURL 传 nil
        let badProvider = V2Provider(
            id: "bad",
            kind: .openAICompatible,
            name: "Bad",
            baseURL: nil,
            apiKeyRef: "keychain:bad",
            defaultModel: "gpt-5",
            capabilities: []
        )
        let template = DefaultV2Configuration.initial()
        let cfg = V2Configuration(
            schemaVersion: template.schemaVersion,
            providers: [badProvider],  // 注入非法 Provider
            tools: [], hotkeys: template.hotkeys,
            triggers: template.triggers, telemetry: template.telemetry,
            appBlocklist: template.appBlocklist, appearance: template.appearance
        )

        do {
            try await store.save(cfg)
            XCTFail("save() 必须在 provider validate 失败时 throw")
        } catch SliceError.configuration(.validationFailed(let msg)) {
            XCTAssertTrue(msg.contains("bad"), "msg missing provider id; got: \(msg)")
        } catch {
            XCTFail("expected .validationFailed, got \(error)")
        }

        // 关键不变量：validate 抛错时磁盘文件必须不存在（fail-before-write）
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: v2URL.path),
            "config-v2.json must not be created when validation fails"
        )
    }

    /// 包含 displayMode/outputBinding 不一致的 Tool 时 save() 必须拒绝写入
    func test_save_rejectsConfigWithInvalidTool() async throws {
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: nil)

        // 故意构造非法 Tool：displayMode=window 但 outputBinding.primary=replace
        let badTool = V2Tool(
            id: "bad-tool",
            name: "Bad",
            icon: "!",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: nil, userPrompt: "u", contexts: [],
                provider: .fixed(providerId: "p", modelId: nil),
                temperature: nil, maxTokens: nil, variables: [:]
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: OutputBinding(primary: .replace, sideEffects: []),
            permissions: [], provenance: .firstParty,
            budget: nil, hotkey: nil, labelStyle: .icon, tags: []
        )
        let template = DefaultV2Configuration.initial()
        let cfg = V2Configuration(
            schemaVersion: template.schemaVersion,
            providers: [], tools: [badTool],  // 注入非法 Tool
            hotkeys: template.hotkeys,
            triggers: template.triggers, telemetry: template.telemetry,
            appBlocklist: template.appBlocklist, appearance: template.appearance
        )

        do {
            try await store.save(cfg)
            XCTFail("save() 必须在 tool validate 失败时 throw")
        } catch SliceError.configuration(.validationFailed(let msg)) {
            XCTAssertTrue(msg.contains("bad-tool"), "msg missing tool id; got: \(msg)")
        } catch {
            XCTFail("expected .validationFailed, got \(error)")
        }

        // 关键不变量：validate 抛错时磁盘文件必须不存在
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: v2URL.path),
            "config-v2.json must not be created when validation fails"
        )
    }

    // MARK: - Helper

    private func fixtureData(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try Data(contentsOf: url)
    }
}
