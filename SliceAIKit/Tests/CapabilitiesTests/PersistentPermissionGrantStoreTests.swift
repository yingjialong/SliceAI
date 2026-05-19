import Capabilities
import Foundation
import SliceCore
import XCTest

/// Task 8: `PersistentPermissionGrantStore` 磁盘持久化测试
final class PersistentPermissionGrantStoreTests: XCTestCase {

    /// 默认文件路径必须落在用户 Application Support 的 SliceAI 目录下
    func test_standardFileURL_usesApplicationSupportSliceAIPath() {
        let fileURL = PersistentPermissionGrantStore.standardFileURL()
        XCTAssertEqual(fileURL.lastPathComponent, "permission-grants.json")
        XCTAssertEqual(fileURL.deletingLastPathComponent().lastPathComponent, "SliceAI")
        XCTAssertEqual(fileURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "Application Support")
    }

    /// persistent grant 可写入 JSON 文件，并被新的 store 实例读回
    func test_persistentGrant_roundTripsToDisk() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let permission = Permission.fileWrite(path: "~/Library/Application Support/SliceAI/persistent.txt")
        let provenance = Provenance.firstParty
        let firstStore = PersistentPermissionGrantStore(fileURL: fileURL)

        try await firstStore.record(permission: permission, provenance: provenance, scope: .persistent)
        let firstHit = await firstStore.has(permission: permission, provenance: provenance)
        XCTAssertTrue(firstHit)

        let secondStore = PersistentPermissionGrantStore(fileURL: fileURL)
        let secondHit = await secondStore.has(permission: permission, provenance: provenance)
        XCTAssertTrue(
            secondHit,
            "persistent grant 应跨 store 实例从磁盘恢复"
        )
    }

    /// persistent store 必须在存储层拒绝 MCP 权限，不能只依赖 broker 过滤
    func test_persistentStore_rejectsMCPPermission() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let store = PersistentPermissionGrantStore(fileURL: fileURL)
        let permission = Permission.mcp(server: "filesystem", tools: ["write"])

        do {
            try await store.record(permission: permission, provenance: .firstParty, scope: .persistent)
            XCTFail("persistent store 必须拒绝 MCP 权限")
        } catch PersistentPermissionGrantStoreError.nonCacheablePermission(let rejected) {
            XCTAssertEqual(rejected, permission)
        }

        let hit = await store.has(permission: permission, provenance: .firstParty)
        XCTAssertFalse(hit)
    }

    /// Brave web search MCP 是当前内置只读搜索工具，允许写入 persistent grant。
    func test_persistentStore_allowsBraveSearchMCPPermission() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let permission = Permission.mcp(server: "brave-search", tools: ["brave_web_search"])
        let firstStore = PersistentPermissionGrantStore(fileURL: fileURL)

        try await firstStore.record(permission: permission, provenance: .firstParty, scope: .persistent)

        let secondStore = PersistentPermissionGrantStore(fileURL: fileURL)
        let hit = await secondStore.has(permission: permission, provenance: .firstParty)
        XCTAssertTrue(hit)
    }

    /// 磁盘里伪造的 session grant 不应被当成 persistent grant 命中
    func test_persistentStore_rejectsStoredSessionGrant() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let permission = Permission.fileWrite(path: "~/Library/Application Support/SliceAI/session-on-disk.txt")
        try Self.writeGrantFile(fileURL: fileURL, permission: permission, scope: .session)

        let store = PersistentPermissionGrantStore(fileURL: fileURL)
        let hit = await store.has(permission: permission, provenance: .firstParty)

        XCTAssertFalse(hit, "磁盘中的 session grant 不应升级成 persistent grant")
    }

    /// schemaVersion 不匹配时必须 fail-closed
    func test_persistentStore_rejectsUnsupportedSchemaVersion() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let permission = Permission.fileWrite(path: "~/Library/Application Support/SliceAI/schema.txt")
        try Self.writeGrantFile(fileURL: fileURL, permission: permission, schemaVersion: 999)

        let store = PersistentPermissionGrantStore(fileURL: fileURL)
        let hit = await store.has(permission: permission, provenance: .firstParty)

        XCTAssertFalse(hit, "未知 schemaVersion 不能被当成有效授权")
    }

    /// grant.permission 与外层 permission 不一致时必须 fail-closed
    func test_persistentStore_rejectsMismatchedGrantPermission() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let permission = Permission.fileWrite(path: "~/Library/Application Support/SliceAI/outer.txt")
        let grantPermission = Permission.fileWrite(path: "~/Library/Application Support/SliceAI/inner.txt")
        try Self.writeGrantFile(fileURL: fileURL, permission: permission, grantPermission: grantPermission)

        let store = PersistentPermissionGrantStore(fileURL: fileURL)
        let hit = await store.has(permission: permission, provenance: .firstParty)

        XCTAssertFalse(hit, "外层 permission 与 grant.permission 不一致时不能命中")
    }

    /// session grant 不能写入 persistent store，避免 Settings-only 持久化边界被绕过
    func test_persistentStore_ignoresSessionScope() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let store = PersistentPermissionGrantStore(fileURL: fileURL)
        let permission = Permission.fileWrite(path: "~/Library/Application Support/SliceAI/session.txt")

        try await store.record(permission: permission, provenance: .firstParty, scope: .session)

        let hit = await store.has(permission: permission, provenance: .firstParty)
        XCTAssertFalse(hit, "persistent store 只保存 .persistent，session scope 不应落盘")
    }

    /// 创建临时 grant 文件路径
    private static func makeTemporaryGrantFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("permission-grants.json")
    }

    /// 写入测试用 grant 文件，模拟磁盘上可能出现的非法记录
    private static func writeGrantFile(
        fileURL: URL,
        permission: Permission,
        grantPermission: Permission? = nil,
        scope: GrantScope = .persistent,
        schemaVersion: Int = PersistentPermissionGrantStore.currentSchemaVersion
    ) throws {
        let fixture = GrantFileFixture(
            schemaVersion: schemaVersion,
            grants: [
                StoredGrantFixture(
                    permission: permission,
                    provenance: .firstParty,
                    provenanceTag: "firstParty",
                    grant: PermissionGrant(
                        permission: grantPermission ?? permission,
                        grantedAt: Date(timeIntervalSinceReferenceDate: 0),
                        grantedBy: .userConsent,
                        scope: scope
                    )
                ),
            ]
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(fixture)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
    }
}

/// 测试专用 grant 文件结构，字段名与 production JSON 保持一致
private struct GrantFileFixture: Encodable {
    let schemaVersion: Int
    let grants: [StoredGrantFixture]
}

/// 测试专用单条 grant 结构
private struct StoredGrantFixture: Encodable {
    let permission: Permission
    let provenance: Provenance
    let provenanceTag: String
    let grant: PermissionGrant
}
