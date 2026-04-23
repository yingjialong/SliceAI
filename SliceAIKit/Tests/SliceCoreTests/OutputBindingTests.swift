import XCTest
@testable import SliceCore

final class OutputBindingTests: XCTestCase {

    // MARK: - PresentationMode

    func test_presentationMode_allCases_stable() {
        XCTAssertEqual(Set(PresentationMode.allCases), [.window, .bubble, .replace, .file, .silent, .structured])
    }

    func test_presentationMode_codable() throws {
        for mode in PresentationMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(PresentationMode.self, from: data)
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

    func test_sideEffect_goldenJSON_tts_nestedWithOptional() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let se = SideEffect.tts(voice: nil)
        let json = try XCTUnwrap(String(data: try enc.encode(se), encoding: .utf8))
        // nil voice → TTSRepr { voice: nil } → JSON `{"tts":{}}` 或 `{"tts":{"voice":null}}`（取决于 JSONEncoder）
        XCTAssertTrue(json.hasPrefix(#"{"tts":{"#), "got: \(json)")
        XCTAssertFalse(json.contains("\"_0\""))
    }
}
