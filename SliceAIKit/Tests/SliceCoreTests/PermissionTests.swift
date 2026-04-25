import XCTest
@testable import SliceCore

final class PermissionTests: XCTestCase {

    // MARK: - Permission equality & hashable

    func test_permission_equality_byAssociatedValues() {
        XCTAssertEqual(Permission.fileRead(path: "~/Docs"), Permission.fileRead(path: "~/Docs"))
        XCTAssertNotEqual(Permission.fileRead(path: "~/Docs"), Permission.fileRead(path: "~/Desktop"))
        XCTAssertNotEqual(Permission.fileRead(path: "~/Docs"), Permission.fileWrite(path: "~/Docs"))
    }

    func test_permission_usableInSet() {
        let set: Set<Permission> = [
            .clipboard,
            .fileRead(path: "a"),
            .fileRead(path: "a"),   // 去重
            .fileRead(path: "b")
        ]
        XCTAssertEqual(set.count, 3)
    }

    // MARK: - Permission Codable

    func test_permission_codable_fileRead() throws {
        let original = Permission.fileRead(path: "~/Documents/**/*.md")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Permission.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_permission_codable_mcp_withAllTools() throws {
        let original = Permission.mcp(server: "postgres", tools: ["query", "schema"])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Permission.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_permission_codable_mcp_nilTools() throws {
        // tools=nil 语义上 = 允许该 server 全部 tool，必须能 round-trip
        let original = Permission.mcp(server: "fs", tools: nil)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Permission.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_permission_codable_roundTrip_allCases() throws {
        // 遍历 11 个 case（mcp 同时覆盖 nil / 非 nil tools）
        let fixtures: [Permission] = [
            .network(host: "api.openai.com"),
            .fileRead(path: "~/Docs/**/*.md"),
            .fileWrite(path: "/tmp/out.txt"),
            .clipboard,
            .clipboardHistory,
            .shellExec(commands: ["ls", "pwd"]),
            .mcp(server: "fs", tools: ["read", "write"]),
            .mcp(server: "fs", tools: nil),
            .screen,
            .systemAudio,
            .memoryAccess(scope: "tool.translate"),
            .appIntents(bundleId: "com.apple.shortcuts")
        ]
        for original in fixtures {
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(Permission.self, from: data)
            XCTAssertEqual(original, decoded, "Round-trip failed for \(original)")
        }
    }

    // MARK: - Provenance

    func test_provenance_firstParty_codable() throws {
        let original = Provenance.firstParty
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_provenance_selfManaged_preservesDate() throws {
        let t = Date(timeIntervalSince1970: 1_700_000_000)
        let original = Provenance.selfManaged(userAcknowledgedAt: t)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_provenance_unknown_preservesURL() throws {
        let url = URL(string: "https://example.com/pack.slicepack")
        let original = Provenance.unknown(importedFrom: url, importedAt: Date(timeIntervalSince1970: 1))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_provenance_communitySigned_preservesPublisher() throws {
        let original = Provenance.communitySigned(publisher: "anthropic-labs", signedAt: Date(timeIntervalSince1970: 2))
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Provenance.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    // MARK: - PermissionGrant

    func test_permissionGrant_codable() throws {
        let grant = PermissionGrant(
            permission: .network(host: "api.openai.com"),
            grantedAt: Date(timeIntervalSince1970: 100),
            grantedBy: .userConsent,
            scope: .session
        )
        let data = try JSONEncoder().encode(grant)
        let decoded = try JSONDecoder().decode(PermissionGrant.self, from: data)
        XCTAssertEqual(grant, decoded)
    }

    func test_grantScope_allCases() {
        XCTAssertEqual(Set(GrantScope.allCases), [.oneTime, .session, .persistent])
    }

    func test_grantSource_allCases() {
        XCTAssertEqual(Set(GrantSource.allCases), [.userConsent, .toolInstall, .developer])
    }

    // MARK: - Golden JSON shape（锁定 canonical schema；模板 D，禁 Swift 合成的 `_0`）

    func test_permission_goldenJSON_fileRead_usesSingleKeyWithStringValue() throws {
        let data = try sortedJSONEncoder().encode(Permission.fileRead(path: "~/Docs"))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, #"{"fileRead":"~\/Docs"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_permission_goldenJSON_clipboard_usesEmptyObjectMarker() throws {
        let data = try sortedJSONEncoder().encode(Permission.clipboard)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, #"{"clipboard":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_permission_goldenJSON_mcp_usesNestedStruct() throws {
        let data = try sortedJSONEncoder().encode(Permission.mcp(server: "postgres", tools: ["query"]))
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"mcp":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""server":"postgres""#))
        XCTAssertTrue(json.contains(#""tools":["query"]"#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_provenance_goldenJSON_firstParty_isEmptyObjectMarker() throws {
        let data = try sortedJSONEncoder().encode(Provenance.firstParty)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertEqual(json, #"{"firstParty":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_provenance_goldenJSON_communitySigned_nestedStruct() throws {
        let signed = Provenance.communitySigned(publisher: "anthropic-labs", signedAt: Date(timeIntervalSince1970: 100))
        let data = try sortedJSONEncoder().encode(signed)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"communitySigned":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""publisher":"anthropic-labs""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    // MARK: - Decoder negative tests（canonical schema 严格单键 + 未知键拒绝）

    func test_permission_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Permission.self, from: data))
    }

    func test_permission_decode_unknownKey_throws() {
        let data = Data(#"{"unknownKey":"x"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Permission.self, from: data))
    }

    func test_permission_decode_twoKeys_throws() {
        let data = Data(#"{"fileRead":"a","fileWrite":"b"}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Permission.self, from: data))
    }

    func test_provenance_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Provenance.self, from: data))
    }

    func test_provenance_decode_twoKeys_throws() {
        let data = Data(#"{"firstParty":{},"selfManaged":{"userAcknowledgedAt":0}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Provenance.self, from: data))
    }

    private func sortedJSONEncoder() -> JSONEncoder {
        let enc = JSONEncoder()
        enc.outputFormatting = [.sortedKeys]
        return enc
    }
}
