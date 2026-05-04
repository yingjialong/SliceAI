import XCTest
@testable import SliceCore

final class OutputBindingTests: XCTestCase {

    // MARK: - DisplayMode

    func test_displayMode_allCases_stable() {
        XCTAssertEqual(Set(DisplayMode.allCases), [.window, .bubble, .replace, .file, .silent, .structured])
    }

    func test_displayMode_codable() throws {
        for mode in DisplayMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(DisplayMode.self, from: data)
            XCTAssertEqual(mode, decoded)
        }
    }

    // MARK: - SideEffect inferredPermissions (D-24)

    func test_appendToFile_inferredPermissions_fileWrite() {
        let se = SideEffect.appendToFile(path: "~/notes.md", header: nil)
        XCTAssertEqual(se.inferredPermissions, [.fileWrite(path: "~/notes.md")])
    }

    func test_copyToClipboard_inferredPermissions_clipboard() {
        XCTAssertEqual(SideEffect.copyToClipboard.inferredPermissions, [.clipboard])
    }

    func test_notify_inferredPermissions_empty() {
        // 本地通知不视为 permission
        XCTAssertTrue(SideEffect.notify(title: "t", body: "b").inferredPermissions.isEmpty)
    }

    func test_runAppIntent_inferredPermissions_appIntents() {
        let se = SideEffect.runAppIntent(bundleId: "com.culturedcode.ThingsMac", intent: "Add", params: [:])
        XCTAssertEqual(se.inferredPermissions, [.appIntents(bundleId: "com.culturedcode.ThingsMac")])
    }

    func test_callMCP_inferredPermissions_mcpWithTool() {
        let ref = MCPToolRef(server: "postgres", tool: "query")
        let se = SideEffect.callMCP(ref: ref, params: [:])
        XCTAssertEqual(se.inferredPermissions, [.mcp(server: "postgres", tools: ["query"])])
    }

    func test_writeMemory_inferredPermissions_memoryAccess() {
        let se = SideEffect.writeMemory(tool: "grammar-tutor", entry: "ok")
        XCTAssertEqual(se.inferredPermissions, [.memoryAccess(scope: "grammar-tutor")])
    }

    func test_tts_inferredPermissions_systemAudio() {
        XCTAssertEqual(SideEffect.tts(voice: nil).inferredPermissions, [.systemAudio])
    }

    func test_inferredPermissions_aggregatedAcrossSideEffects() {
        // PermissionGraph.compute() 会对 OutputBinding.sideEffects 做 flatMap(\.inferredPermissions)；
        // 这里锁死聚合顺序 = 数组顺序（每个 side effect 独立贡献），
        // 同一 Permission 出现多次允许（去重交给 PermissionGraph）
        let binding = OutputBinding(
            primary: .window,
            sideEffects: [
                .copyToClipboard,
                .tts(voice: nil),
                .writeMemory(tool: "translate", entry: "saved")
            ]
        )
        let aggregated = binding.sideEffects.flatMap(\.inferredPermissions)
        XCTAssertEqual(aggregated, [
            .clipboard,
            .systemAudio,
            .memoryAccess(scope: "translate")
        ])
    }

    // MARK: - OutputBinding Codable

    func test_outputBinding_codable_roundtrip() throws {
        let ref = MCPToolRef(server: "slack", tool: "send")
        let binding = OutputBinding(
            primary: .window,
            sideEffects: [.copyToClipboard, .callMCP(ref: ref, params: ["channel": "#general"])]
        )
        let data = try JSONEncoder().encode(binding)
        let decoded = try JSONDecoder().decode(OutputBinding.self, from: data)
        XCTAssertEqual(binding, decoded)
    }

    // MARK: - Decoder negative tests（canonical 单键 + 未知键拒绝；Task 3/8 同款纪律）

    func test_sideEffect_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SideEffect.self, from: data))
    }

    func test_sideEffect_decode_unknownKey_throws() {
        let data = Data(#"{"bogus":{}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SideEffect.self, from: data))
    }

    func test_sideEffect_decode_twoKeys_throws() {
        let data = Data(#"{"copyToClipboard":{},"tts":{"voice":null}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(SideEffect.self, from: data))
    }

    // MARK: - Golden JSON shape（模板 D；禁 `_0`）

    func test_sideEffect_goldenJSON_copyToClipboard_emptyObject() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(SideEffect.copyToClipboard), encoding: .utf8))
        XCTAssertEqual(json, #"{"copyToClipboard":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_appendToFile_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.appendToFile(path: "~/notes.md", header: "## 2026-04-23")
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"appendToFile":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""path":"~\/notes.md""#))
        XCTAssertTrue(json.contains(###""header":"## 2026-04-23""###))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_callMCP_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.callMCP(ref: MCPToolRef(server: "anki", tool: "createNote"), params: [:])
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"callMCP":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""server":"anki""#))
        XCTAssertTrue(json.contains(#""tool":"createNote""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_tts_nilVoice_omitsKeyOrNull() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.tts(voice: nil)
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        // Foundation 默认 encoder 对 nil 可选值的行为：key 省略（-> `{"tts":{}}`）
        // 若未来 Foundation 行为改为 `{"voice":null}`，这里会失败，提示显式选择 strategy。
        XCTAssertEqual(json, #"{"tts":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_tts_nonNilVoice_pinsShape() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.tts(voice: "Alex")
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        XCTAssertEqual(json, #"{"tts":{"voice":"Alex"}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_notify_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.notify(title: "Hi", body: "Done")
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        XCTAssertEqual(json, #"{"notify":{"body":"Done","title":"Hi"}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_runAppIntent_emptyParams() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.runAppIntent(bundleId: "com.apple.Shortcuts", intent: "Run", params: [:])
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        XCTAssertEqual(json, #"{"runAppIntent":{"bundleId":"com.apple.Shortcuts","intent":"Run","params":{}}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_sideEffect_goldenJSON_writeMemory_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.writeMemory(tool: "grammar-tutor", entry: "saved")
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        XCTAssertEqual(json, #"{"writeMemory":{"entry":"saved","tool":"grammar-tutor"}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    // MARK: - MCPToolRef golden JSON

    // MCPToolRef 出现在 SideEffect.callMCP(ref:) 和 Task 14 AgentTool.mcpAllowlist 两处；
    // 锁住 2-字段 auto-synthesized wire shape，防止 key rename 影响配置 / migration。
    func test_mcpToolRef_goldenJSON_canonicalWireShape() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let ref = MCPToolRef(server: "anki", tool: "createNote")
        let json = try XCTUnwrap(String(data: try enc.encode(ref), encoding: .utf8))
        XCTAssertEqual(json, #"{"server":"anki","tool":"createNote"}"#)
    }
}
