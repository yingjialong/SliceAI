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

    func test_cachePolicy_session_codable() throws {
        let data = try JSONEncoder().encode(CachePolicy.session)
        let decoded = try JSONDecoder().decode(CachePolicy.self, from: data)
        XCTAssertEqual(decoded, CachePolicy.session)
    }

    // MARK: - Decoder negative tests (strict single-key wire format)

    func test_cachePolicy_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CachePolicy.self, from: data))
    }

    func test_cachePolicy_decode_unknownKey_throws() {
        let data = Data(#"{"forever":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CachePolicy.self, from: data))
    }

    func test_cachePolicy_decode_twoKeys_throws() {
        let data = Data(#"{"none":{},"ttl":60}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(CachePolicy.self, from: data))
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

    func test_cachePolicy_goldenJSON_session_usesEmptyObjectMarker() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(CachePolicy.session), encoding: .utf8))
        XCTAssertEqual(json, #"{"session":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    // 锁住 ContextRequest 的 canonical 线上形状：
    // - ContextKey (RawRepresentable<String> + Codable) 被合成为 bare string "vocab"，而非 {"rawValue":"vocab"}
    // - CachePolicy 保持单键形状；Requiredness raw value 是 lowercase
    func test_contextRequest_goldenJSON_wireShape() throws {
        let req = ContextRequest(
            key: ContextKey(rawValue: "vocab"),
            provider: "file.read",
            args: ["path": "~/vocab.md"],
            cachePolicy: .ttl(60),
            requiredness: .optional
        )
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(req), encoding: .utf8))

        XCTAssertTrue(json.contains(#""key":"vocab""#),
                      "ContextKey should encode as bare string, got: \(json)")
        XCTAssertFalse(json.contains(#""rawValue""#),
                       "ContextKey wrapper leak: \(json)")
        XCTAssertTrue(json.contains(#""provider":"file.read""#))
        XCTAssertTrue(json.contains(#""cachePolicy":{"ttl":60}"#))
        XCTAssertTrue(json.contains(#""requiredness":"optional""#))
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

    // M2 的 ContextCollector 会持有 `any ContextProvider` 列表，
    // 通过 `type(of: provider).inferredPermissions(for:)` 聚合权限。
    // 这里显式跑一遍 existential 路径，防止 Swift 对 protocol static requirement
    // 的调用规则变化导致 M2 编译失败
    func test_contextProvider_staticMethod_callableViaExistential() {
        struct NetworkProviderStub: ContextProvider {
            let name = "net.fetch"
            static func inferredPermissions(for args: [String: String]) -> [Permission] {
                guard let host = args["host"] else { return [] }
                return [.network(host: host)]
            }
            func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue {
                .text("stub")
            }
        }

        let erased: any ContextProvider = NetworkProviderStub()
        let perms = type(of: erased).inferredPermissions(for: ["host": "api.openai.com"])
        XCTAssertEqual(perms, [.network(host: "api.openai.com")])
    }
}
