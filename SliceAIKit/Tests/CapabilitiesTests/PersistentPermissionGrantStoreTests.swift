import Capabilities
import Foundation
import SliceCore
import XCTest

/// Task 8: `PersistentPermissionGrantStore` 磁盘持久化测试
final class PersistentPermissionGrantStoreTests: XCTestCase {

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
        } catch PermissionGrantStoreError.nonCacheablePermission(let rejected) {
            XCTAssertEqual(rejected, permission)
        }

        let hit = await store.has(permission: permission, provenance: .firstParty)
        XCTAssertFalse(hit)
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
}
