import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// Task 6: `PermissionGrantStore` actor 行为测试
///
/// 覆盖矩阵：
/// 1. empty store has → false
/// 2. record then has → true
/// 3. 同 permission 但不同 provenance（firstParty vs unknown） → has 互不串扰
/// 4. 重复 record 不重复计数（同 key 覆盖）
/// 5. 并发 record 不丢失（actor 隔离验证）
/// 6. 不同 permission 关联值（不同 host）→ has 互不串扰
final class PermissionGrantStoreTests: XCTestCase {

    // MARK: - 1. 空 store

    /// 新建 store has 任意 permission 都返回 false
    func test_emptyStore_hasReturnsFalse() async {
        let store = PermissionGrantStore()
        let permission = Permission.fileRead(path: "~/Documents/test.md")
        let provenance = Provenance.firstParty
        let hit = await store.has(permission: permission, provenance: provenance)
        XCTAssertFalse(hit, "空 store 不应命中任何 grant")
    }

    // MARK: - 2. record then has

    /// record 后立即 has 同一 (permission, provenance) → true
    func test_record_thenHasReturnsTrue() async throws {
        let store = PermissionGrantStore()
        let permission = Permission.fileWrite(path: "~/Library/Application Support/SliceAI/")
        let provenance = Provenance.firstParty

        try await store.record(permission: permission, provenance: provenance, scope: .session)
        let hit = await store.has(permission: permission, provenance: provenance)

        XCTAssertTrue(hit, "record 后立即 has 必命中")
        let count = await store.count
        XCTAssertEqual(count, 1, "单次 record 应只计 1 条")
    }

    // MARK: - 3. 同 permission 不同 provenance

    /// firstParty 给 .fileRead 不应让 unknown 的同 permission 命中（D-25 隔离）
    func test_recordedPermission_differentProvenance_returnsFalse() async throws {
        let store = PermissionGrantStore()
        let permission = Permission.fileRead(path: "~/Documents/test.md")

        try await store.record(permission: permission, provenance: .firstParty, scope: .session)

        let firstPartyHit = await store.has(permission: permission, provenance: .firstParty)
        XCTAssertTrue(firstPartyHit, "firstParty 自身查询应命中")

        let unknownHit = await store.has(
            permission: permission,
            provenance: .unknown(importedFrom: nil, importedAt: Date())
        )
        XCTAssertFalse(unknownHit, "不同 provenance 不应共享 grant（D-25 不可降级 UX）")
    }

    // MARK: - 4. 重复 record 同 key 覆盖

    /// 同 (permission, provenance) 重复 record → 字典 key 唯一，count 仍 = 1
    func test_record_duplicate_overwritesAndKeepsCountOne() async throws {
        let store = PermissionGrantStore()
        let permission = Permission.network(host: "api.openai.com")
        let provenance = Provenance.firstParty

        try await store.record(permission: permission, provenance: provenance, scope: .session)
        try await store.record(permission: permission, provenance: provenance, scope: .persistent)

        let count = await store.count
        XCTAssertEqual(count, 1, "同 key 重复 record 应覆盖而非追加")
    }

    // MARK: - 5. 并发 record（actor 隔离验证）

    /// 100 个并发 record 不同 host → 全部成功命中且 count = 100（actor 串行化保证）
    func test_actorIsolation_concurrentRecords() async throws {
        let store = PermissionGrantStore()
        let count = 100

        // 并发任务组：每个任务 record 不同 host 的 .network permission
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<count {
                group.addTask {
                    let permission = Permission.network(host: "host\(i).example.com")
                    try? await store.record(permission: permission, provenance: .firstParty, scope: .session)
                }
            }
        }

        // 验证最终条目数
        let finalCount = await store.count
        XCTAssertEqual(finalCount, count, "100 并发 record 应全部成功（actor 串行化）")

        // 抽查几条
        for i in [0, 50, 99] {
            let hit = await store.has(
                permission: .network(host: "host\(i).example.com"),
                provenance: .firstParty
            )
            XCTAssertTrue(hit, "host\(i) 应命中")
        }
    }

    // MARK: - 6. 不同 permission 关联值不串扰

    /// 同 case (.fileRead) 但不同关联值（path）应视为不同 key
    func test_differentPermissionAssociatedValues_doNotCollide() async throws {
        let store = PermissionGrantStore()
        let p1 = Permission.fileRead(path: "~/Documents/a.md")
        let p2 = Permission.fileRead(path: "~/Documents/b.md")

        try await store.record(permission: p1, provenance: .firstParty, scope: .session)

        let hitP1 = await store.has(permission: p1, provenance: .firstParty)
        let hitP2 = await store.has(permission: p2, provenance: .firstParty)

        XCTAssertTrue(hitP1, "p1 应命中")
        XCTAssertFalse(hitP2, "p2 关联值不同，不应命中 p1 的 grant")
    }
}
