import XCTest
@testable import SliceCore

final class ConfigurationStoreTests: XCTestCase {

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
        let url = ConfigurationStore.standardV2FileURL()
        XCTAssertEqual(url.lastPathComponent, "config-v2.json")
        XCTAssertTrue(url.path.contains("/SliceAI/"))
    }

    func test_legacyV1FileURL_endsWith_config_json() {
        let url = ConfigurationStore.legacyV1FileURL()
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
        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
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

        // 准备 v2 文件（用 DefaultConfiguration 做样本，改一个可辨识字段）
        var v2Template = DefaultConfiguration.initial()
        v2Template = Configuration(
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

        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.load()

        XCTAssertEqual(cfg.hotkeys.toggleCommandPalette, "option+z")
        XCTAssertEqual(cfg.tools.count, 0)
    }

    func test_load_withNeither_returnsDefaultV2() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.load()

        XCTAssertEqual(cfg.schemaVersion, 2)
        XCTAssertEqual(cfg.tools.count, 4)  // 4 个内置工具（DefaultConfiguration）
    }

    /// 两个配置文件都不存在时，load/current 必须返回默认 v2 并只创建 config-v2.json
    func test_load_withNeither_writesDefaultToV2Path() async throws {
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        let legacyURL = tempDir.appendingPathComponent("config.json")
        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: legacyURL)

        // 前置条件：全新安装场景下 v1/v2 配置文件都不存在。
        XCTAssertFalse(FileManager.default.fileExists(atPath: v2URL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))

        let cfg = try await store.current()

        let expected = DefaultConfiguration.initial()
        XCTAssertEqual(cfg.providers.map(\.id), expected.providers.map(\.id))
        XCTAssertEqual(cfg.tools.map(\.id), expected.tools.map(\.id))

        XCTAssertTrue(FileManager.default.fileExists(atPath: v2URL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))

        // 校验写出的 v2 文件内容可解码，且与本次返回值一致。
        let writtenData = try Data(contentsOf: v2URL)
        let writtenCfg = try JSONDecoder().decode(Configuration.self, from: writtenData)
        XCTAssertEqual(writtenCfg, cfg)
    }

    // MARK: - Write behaviour

    func test_save_writesOnlyToV2Path_neverTouchesV1() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        let v1Data = try fixtureData("config-v1-minimal")
        try v1Data.write(to: v1URL, options: .atomic)

        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = DefaultConfiguration.initial()
        try await store.save(cfg)

        XCTAssertTrue(FileManager.default.fileExists(atPath: v2URL.path))
        let preservedV1 = try Data(contentsOf: v1URL)
        XCTAssertEqual(preservedV1, v1Data)
    }

    /// 关键不变量：ConfigurationStore.save 只写 v2 路径，不创建 legacy v1 文件。
    func test_save_doesNotCreateLegacyFileWhenLegacyMissing() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)

        try await store.save(DefaultConfiguration.initial())

        XCTAssertTrue(FileManager.default.fileExists(atPath: v2URL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: v1URL.path))
    }

    // MARK: - current() 抛错语义（P1 修复：禁止吞错回退默认，防止覆盖丢失）

    /// 覆盖"v2 JSON 损坏时 current() 必须 throw invalidJSON"
    ///
    /// 修复前：current() 用 `try? await load()` 吞错 → 回退 DefaultConfiguration.initial() →
    /// 下次 update() 把默认值写回原路径 → 用户原有 providers / tools 永久丢失。
    /// 修复后：load() 的 throw 原样向外传播，调用方（M3 AppContainer）必须显式处理。
    func test_current_throwsOnCorruptedV2JSON() async throws {
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        try Data("{ not valid json".utf8).write(to: v2URL, options: .atomic)

        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: nil)
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
        // 基于 DefaultConfiguration 合成合法 JSON，仅改 schemaVersion = 999
        let template = DefaultConfiguration.initial()
        let future = Configuration(
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

        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: nil)
        do {
            _ = try await store.current()
            XCTFail("current() 必须 throw schemaVersionTooNew")
        } catch SliceError.configuration(.schemaVersionTooNew(let v)) {
            XCTAssertEqual(v, 999)
        } catch {
            XCTFail("expected .configuration(.schemaVersionTooNew), got \(error)")
        }
    }

    /// v1 文件 schemaVersion 不等于 1 时 current() 必须 throw（第八轮 P2-3 修复）
    ///
    /// 场景：用户误把 config-v2.json 内容写进 config.json（或未来 v3 降级），LegacyConfigV1
    /// 的可选/兼容字段让 decode 能通过，但语义已变。此时 migrator 必须拒绝迁移，而不是盲目
    /// 把错值映射为 v2 写盘（会彻底破坏用户数据）。
    func test_load_throwsWhenLegacyHasUnknownSchemaVersion() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")

        // schemaVersion=2 但 shape 仍符合 v1（其他字段 decode 通过）
        let weirdV1JSON = #"""
        {
          "schemaVersion": 2,
          "providers": [],
          "tools": [],
          "hotkeys": {"toggleCommandPalette": "option+space"},
          "triggers": {"floatingToolbarEnabled": true, "commandPaletteEnabled": true, "minimumSelectionLength": 1, "triggerDelayMs": 150},
          "telemetry": {"enabled": false},
          "appBlocklist": []
        }
        """#
        try Data(weirdV1JSON.utf8).write(to: v1URL, options: .atomic)

        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        do {
            _ = try await store.current()
            XCTFail("current() 必须在 v1 schemaVersion 未知时 throw")
        } catch SliceError.configuration(.schemaVersionTooNew(let v)) {
            XCTAssertEqual(v, 2)
        } catch {
            XCTFail("expected .schemaVersionTooNew, got \(error)")
        }

        // 关键不变量：migrator 抛错 → v2 文件不应被创建
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: v2URL.path),
            "config-v2.json must not be created when migration is rejected"
        )
    }

    /// v2 不存在但 v1 文件损坏时，current() 必须 throw，避免无声丢失 v1 数据
    func test_current_throwsOnCorruptedLegacyJSON() async throws {
        let v1URL = tempDir.appendingPathComponent("config.json")
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        try Data("bad".utf8).write(to: v1URL, options: .atomic)

        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
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

        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: v1URL)
        let cfg = try await store.current()

        XCTAssertEqual(cfg.schemaVersion, Configuration.currentSchemaVersion)
        XCTAssertEqual(cfg.tools.count, 4)  // DefaultConfiguration 4 个内置工具
    }

    // MARK: - 写入边界 validation（第八轮 P2-1/P2-2 修复）
    //
    // save() 必须"先 validate，再 write"——validate throw 时磁盘不得被写入。
    // 测试策略：构造一个包含非法 Provider / Tool 的 Configuration，断言
    // save() throw .validationFailed 且 config-v2.json 不存在。

    /// 包含 openAICompatible + nil baseURL 的 Provider 时 save() 必须拒绝写入
    func test_save_rejectsConfigWithInvalidProvider() async throws {
        let v2URL = tempDir.appendingPathComponent("config-v2.json")
        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: nil)

        // 故意构造非法 Provider：kind=openAICompatible 却把 baseURL 传 nil
        let badProvider = Provider(
            id: "bad",
            kind: .openAICompatible,
            name: "Bad",
            baseURL: nil,
            apiKeyRef: "keychain:bad",
            defaultModel: "gpt-5",
            capabilities: []
        )
        let template = DefaultConfiguration.initial()
        let cfg = Configuration(
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
        let store = ConfigurationStore(fileURL: v2URL, legacyFileURL: nil)

        // 故意构造非法 Tool：displayMode=window 但 outputBinding.primary=replace
        let badTool = Tool(
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
        let template = DefaultConfiguration.initial()
        let cfg = Configuration(
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
