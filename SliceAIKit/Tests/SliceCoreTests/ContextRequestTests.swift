import XCTest
@testable import SliceCore

final class ContextRequestTests: XCTestCase {

    func test_init_preservesFields() {
        let req = ContextRequest(
            key: ContextKey(rawValue: "vocab"),
            provider: "file.read",
            args: ["path": "~/vocab.md"],
            cachePolicy: .session,
            requiredness: .optional
        )
        XCTAssertEqual(req.key.rawValue, "vocab")
        XCTAssertEqual(req.provider, "file.read")
        XCTAssertEqual(req.args["path"], "~/vocab.md")
        XCTAssertEqual(req.cachePolicy, .session)
        XCTAssertEqual(req.requiredness, .optional)
    }

    func test_codable_roundtrip() throws {
        let req = ContextRequest(
            key: ContextKey(rawValue: "x"),
            provider: "mcp.call",
            args: ["server": "postgres", "tool": "query"],
            cachePolicy: .ttl(300),
            requiredness: .required
        )
        let data = try JSONEncoder().encode(req)
        let decoded = try JSONDecoder().decode(ContextRequest.self, from: data)
        XCTAssertEqual(req, decoded)
    }

    func test_cachePolicy_ttl_codable() throws {
        let policy = CachePolicy.ttl(60)
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(CachePolicy.self, from: data)
        XCTAssertEqual(policy, decoded)
    }

    func test_cachePolicy_none_codable() throws {
        let data = try JSONEncoder().encode(CachePolicy.none)
        let decoded = try JSONDecoder().decode(CachePolicy.self, from: data)
        XCTAssertEqual(decoded, CachePolicy.none)
    }

    // MARK: - Golden JSON shape（模板 D；禁 `_0`）

    func test_cachePolicy_goldenJSON_none_usesEmptyObjectMarker() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(CachePolicy.none), encoding: .utf8))
        XCTAssertEqual(json, #"{"none":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_cachePolicy_goldenJSON_ttl_usesDirectNumber() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(CachePolicy.ttl(60)), encoding: .utf8))
        XCTAssertEqual(json, #"{"ttl":60}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    // D-24：ContextProvider.inferredPermissions 是 static 协议方法；
    // 测试通过一个具体 stub 验证协议契约
    func test_contextProvider_conformance_exposesInferredPermissions() {
        struct FileReadProviderStub: ContextProvider {
            let name = "file.read"
            static func inferredPermissions(for args: [String: String]) -> [Permission] {
                guard let path = args["path"] else { return [] }
                return [.fileRead(path: path)]
            }
            func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue {
                .text("stub")
            }
        }
        let perms = FileReadProviderStub.inferredPermissions(for: ["path": "~/Docs/x.md"])
        XCTAssertEqual(perms, [.fileRead(path: "~/Docs/x.md")])
    }

    func test_contextProvider_emptyArgs_returnsNoPermissions() {
        struct FileReadProviderStub: ContextProvider {
            let name = "file.read"
            static func inferredPermissions(for args: [String: String]) -> [Permission] {
                guard let path = args["path"] else { return [] }
                return [.fileRead(path: path)]
            }
            func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue {
                .text("stub")
            }
        }
        XCTAssertTrue(FileReadProviderStub.inferredPermissions(for: [:]).isEmpty)
    }
}
