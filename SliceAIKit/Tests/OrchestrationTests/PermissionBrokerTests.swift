import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// Task 6: `PermissionBroker` 默认实现的 §3.9.1 / §3.9.2 全表覆盖测试
///
/// **核心断言矩阵**（plan line 1715-1719 + spec §3.9.1 表）：
/// - 5 tier × 4 provenance = 20 cell 全部独立用例（不抽样）
/// - readonly-local 子集（4 cell）：firstParty / signed / selfManaged → .approved；unknown → .requiresUserConsent
/// - readonly-network / local-write 子集（8 cell）：所有 4 provenance → .requiresUserConsent（首次确认）
/// - network-write / exec 子集（8 cell）：所有 4 provenance → .requiresUserConsent（每次确认，不缓存）
///
/// **dry-run 子矩阵**（额外 cell）：
/// - dry-run + network-write/exec → .wouldRequireConsent（占位事件）
/// - dry-run + readonly-network/local-write → .requiresUserConsent（与非 dry-run 相同；spec §3.9.2 不豁免下限）
///
/// **grant cache 子矩阵**：
/// - 已有 readonly-network grant → .approved（首次确认后缓存命中）
/// - 已有 local-write grant → .approved（同上）
/// - 已有 network-write grant → 仍 .requiresUserConsent（每次确认下限，不可缓存；D-22）
/// - 已有 exec grant → 仍 .requiresUserConsent（同上）
final class PermissionBrokerTests: XCTestCase {

    // MARK: - Fixture：4 种 provenance + 5 tier 的代表 permission

    /// 4 种 provenance 实例（关联值用固定测试值）
    private static let firstParty: Provenance = .firstParty
    private static let communitySigned: Provenance = .communitySigned(
        publisher: "test-publisher",
        signedAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    private static let selfManaged: Provenance = .selfManaged(
        userAcknowledgedAt: Date(timeIntervalSinceReferenceDate: 0)
    )
    // swiftlint:disable:next force_unwrapping — 硬编码测试用 URL，启动时强制解包安全
    private static let unknown: Provenance = .unknown(
        importedFrom: URL(string: "https://example.com/tool.json")!,
        importedAt: Date(timeIntervalSinceReferenceDate: 0)
    )

    /// 5 tier 的代表 permission（保守归类后；见 PermissionBroker.inferTier 注释）
    /// readonly-local: .fileRead
    /// readonly-network: 当前 SliceCore 没有 case 直接命中此 tier；M2 跳过此 tier 的真实测试，
    ///   仅通过 PermissionBroker.inferTier 间接覆盖（M3+ 加 .network(method:) 后再补全 cell）
    /// local-write: .fileWrite
    /// network-write: .network
    /// exec: .shellExec
    private static let permFileRead = Permission.fileRead(path: "~/Documents/test.md")
    private static let permFileWrite = Permission.fileWrite(path: "~/Library/Application Support/SliceAI/")
    private static let permNetwork = Permission.network(host: "api.openai.com")
    private static let permShellExec = Permission.shellExec(commands: ["git status"])

    // MARK: - readonly-local × 4 provenance（4 cell）

    /// readonly-local + firstParty → .approved（spec §3.9.1 line 939）
    func test_gate_readonlyLocal_firstParty_returnsApproved() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "readonly-local + firstParty 应静默通过")
    }

    /// readonly-local + communitySigned → .approved
    func test_gate_readonlyLocal_communitySigned_returnsApproved() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.communitySigned,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "readonly-local + communitySigned 应静默通过")
    }

    /// readonly-local + selfManaged → .approved
    func test_gate_readonlyLocal_selfManaged_returnsApproved() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.selfManaged,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "readonly-local + selfManaged 应静默通过")
    }

    /// readonly-local + unknown → .requiresUserConsent（spec §3.9.1 line 939：unknown 也需首次确认）
    /// 注：plan line 1718 简化表述与 spec 表存在出入，按 spec 准确实现
    func test_gate_readonlyLocal_unknown_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent(let perm, let hint) = outcome else {
            return XCTFail("readonly-local + unknown 应返回 .requiresUserConsent，实际 \(outcome)")
        }
        XCTAssertEqual(perm, Self.permFileRead)
        XCTAssertTrue(hint.contains("readonly-local"), "uxHint 应含 tier 标签：\(hint)")
        XCTAssertTrue(hint.contains("unknown"), "uxHint 应含 provenance 标签：\(hint)")
        XCTAssertTrue(hint.contains("not verified"), "unknown 来源应使用警告文案：\(hint)")
    }

    // MARK: - local-write × 4 provenance（4 cell；D-25 firstParty 也不可跳过首次确认）

    /// local-write + firstParty → .requiresUserConsent（D-25：首次确认不可跳过）
    func test_gate_localWrite_firstParty_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent(let perm, let hint) = outcome else {
            return XCTFail("local-write + firstParty 应需首次确认，实际 \(outcome)")
        }
        XCTAssertEqual(perm, Self.permFileWrite)
        XCTAssertTrue(hint.contains("local-write"), "uxHint 应含 tier：\(hint)")
        XCTAssertTrue(hint.contains("firstParty"), "uxHint 应含 provenance：\(hint)")
        XCTAssertTrue(hint.contains("Authorize"), "firstParty 应使用中性文案：\(hint)")
    }

    /// local-write + communitySigned → .requiresUserConsent
    func test_gate_localWrite_communitySigned_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.communitySigned,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("local-write + communitySigned 应需首次确认，实际 \(outcome)")
        }
    }

    /// local-write + selfManaged → .requiresUserConsent
    func test_gate_localWrite_selfManaged_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.selfManaged,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("local-write + selfManaged 应需首次确认，实际 \(outcome)")
        }
    }

    /// local-write + unknown → .requiresUserConsent（每次确认；M2 仍单次返回，UX 差异由 hint 表达）
    func test_gate_localWrite_unknown_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent(_, let hint) = outcome else {
            return XCTFail("local-write + unknown 应需确认，实际 \(outcome)")
        }
        XCTAssertTrue(hint.contains("not verified"), "unknown 来源应使用警告文案：\(hint)")
    }

    // MARK: - network-write × 4 provenance（4 cell；D-22 每次确认，不可缓存）

    /// network-write + firstParty → .requiresUserConsent（D-22：firstParty 也不能放行）
    func test_gate_networkWrite_firstParty_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent(let perm, let hint) = outcome else {
            return XCTFail("network-write + firstParty 应需每次确认，实际 \(outcome)")
        }
        XCTAssertEqual(perm, Self.permNetwork)
        XCTAssertTrue(hint.contains("network-write"))
    }

    /// network-write + communitySigned → .requiresUserConsent
    func test_gate_networkWrite_communitySigned_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.communitySigned,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("network-write + communitySigned 应需每次确认，实际 \(outcome)")
        }
    }

    /// network-write + selfManaged → .requiresUserConsent
    func test_gate_networkWrite_selfManaged_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.selfManaged,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("network-write + selfManaged 应需每次确认，实际 \(outcome)")
        }
    }

    /// network-write + unknown → .requiresUserConsent
    func test_gate_networkWrite_unknown_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent(_, let hint) = outcome else {
            return XCTFail("network-write + unknown 应需确认，实际 \(outcome)")
        }
        XCTAssertTrue(hint.contains("not verified"))
    }

    // MARK: - exec × 4 provenance（4 cell；D-22 每次确认）

    /// exec + firstParty → .requiresUserConsent
    func test_gate_exec_firstParty_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent(let perm, let hint) = outcome else {
            return XCTFail("exec + firstParty 应需每次确认，实际 \(outcome)")
        }
        XCTAssertEqual(perm, Self.permShellExec)
        XCTAssertTrue(hint.contains("exec"))
    }

    /// exec + communitySigned → .requiresUserConsent
    func test_gate_exec_communitySigned_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.communitySigned,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("exec + communitySigned 应需每次确认，实际 \(outcome)")
        }
    }

    /// exec + selfManaged → .requiresUserConsent
    func test_gate_exec_selfManaged_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.selfManaged,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("exec + selfManaged 应需每次确认，实际 \(outcome)")
        }
    }

    /// exec + unknown → .requiresUserConsent
    func test_gate_exec_unknown_returnsRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent(_, let hint) = outcome else {
            return XCTFail("exec + unknown 应需确认，实际 \(outcome)")
        }
        XCTAssertTrue(hint.contains("not verified"))
    }

    // MARK: - readonly-network × 4 provenance（4 cell；D-25 首次确认）
    //
    // 当前 SliceCore Permission case 不区分 GET/POST，所有 .network 都被 inferTier 归为 networkWrite，
    // readonly-network tier 在生产路径下"暂无 Permission 命中"。这里通过 .uxHint 静态方法直接验证 tier
    // 的文案差异，作为 readonly-network 行的占位覆盖；M3+ Permission 加 method 区分后再换为真实 broker.gate
    // 调用。

    /// readonly-network + firstParty → uxHint 携带 readonly-network 标签 + 中性文案
    func test_uxHint_readonlyNetwork_firstParty_usesNeutralCopy() {
        let hint = PermissionBroker.uxHint(tier: .readonlyNetwork, provenance: Self.firstParty)
        XCTAssertTrue(hint.contains("readonly-network"))
        XCTAssertTrue(hint.contains("firstParty"))
        XCTAssertTrue(hint.contains("Authorize"))
    }

    /// readonly-network + communitySigned → 中性文案
    func test_uxHint_readonlyNetwork_communitySigned_usesNeutralCopy() {
        let hint = PermissionBroker.uxHint(tier: .readonlyNetwork, provenance: Self.communitySigned)
        XCTAssertTrue(hint.contains("communitySigned"))
        XCTAssertTrue(hint.contains("Authorize"))
    }

    /// readonly-network + selfManaged → 中性文案
    func test_uxHint_readonlyNetwork_selfManaged_usesNeutralCopy() {
        let hint = PermissionBroker.uxHint(tier: .readonlyNetwork, provenance: Self.selfManaged)
        XCTAssertTrue(hint.contains("selfManaged"))
        XCTAssertTrue(hint.contains("Authorize"))
    }

    /// readonly-network + unknown → 警告文案
    func test_uxHint_readonlyNetwork_unknown_usesWarningCopy() {
        let hint = PermissionBroker.uxHint(tier: .readonlyNetwork, provenance: Self.unknown)
        XCTAssertTrue(hint.contains("unknown"))
        XCTAssertTrue(hint.contains("not verified"))
    }

    // MARK: - dry-run 子矩阵

    /// dry-run + network-write → .wouldRequireConsent（spec §3.9.2 + Round 1 P1-1 修订）
    func test_gate_dryRun_networkWrite_returnsWouldRequireConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: true
        )
        guard case .wouldRequireConsent(let perm, let hint) = outcome else {
            return XCTFail("dry-run + network-write 应返回 .wouldRequireConsent，实际 \(outcome)")
        }
        XCTAssertEqual(perm, Self.permNetwork)
        XCTAssertTrue(hint.contains("network-write"))
    }

    /// dry-run + exec → .wouldRequireConsent
    func test_gate_dryRun_exec_returnsWouldRequireConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: true
        )
        guard case .wouldRequireConsent(let perm, _) = outcome else {
            return XCTFail("dry-run + exec 应返回 .wouldRequireConsent，实际 \(outcome)")
        }
        XCTAssertEqual(perm, Self.permShellExec)
    }

    /// dry-run + local-write → 与非 dry-run 相同的 .requiresUserConsent（不豁免下限）
    func test_gate_dryRun_localWrite_stillRequiresConsent() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: true
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("dry-run + local-write 仍走 requiresUserConsent，实际 \(outcome)")
        }
    }

    /// dry-run + readonly-local + firstParty → .approved（与非 dry-run 同；下限本就是静默）
    func test_gate_dryRun_readonlyLocal_firstParty_returnsApproved() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: true
        )
        XCTAssertEqual(outcome, .approved, "dry-run 不豁免下限，但 readonly-local 下限本就是静默")
    }

    // MARK: - grant cache 子矩阵（first-time-confirm tier 命中后 .approved）

    /// 已有 local-write grant → 后续 gate 直接 .approved
    func test_gate_localWrite_withExistingGrant_returnsApproved() async throws {
        let store = PermissionGrantStore()
        try await store.record(permission: Self.permFileWrite, provenance: Self.firstParty, scope: .session)
        let broker = PermissionBroker(store: store)

        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "first-time-confirm tier 已有 grant 应直接放行")
    }

    /// 已有 network-write grant → 仍 .requiresUserConsent（D-22 不可缓存）
    func test_gate_networkWrite_withExistingGrant_stillRequiresConsent() async throws {
        let store = PermissionGrantStore()
        try await store.record(permission: Self.permNetwork, provenance: Self.firstParty, scope: .session)
        let broker = PermissionBroker(store: store)

        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("network-write 不可缓存 grant，实际 \(outcome)")
        }
    }

    /// 已有 exec grant → 仍 .requiresUserConsent（D-22 不可缓存）
    func test_gate_exec_withExistingGrant_stillRequiresConsent() async throws {
        let store = PermissionGrantStore()
        try await store.record(permission: Self.permShellExec, provenance: Self.firstParty, scope: .session)
        let broker = PermissionBroker(store: store)

        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent = outcome else {
            return XCTFail("exec 不可缓存 grant，实际 \(outcome)")
        }
    }

    /// readonly-local + unknown 已有 grant → 后续 gate .approved（首次确认 → 缓存命中）
    func test_gate_readonlyLocal_unknownWithGrant_returnsApproved() async throws {
        let store = PermissionGrantStore()
        try await store.record(permission: Self.permFileRead, provenance: Self.unknown, scope: .session)
        let broker = PermissionBroker(store: store)

        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "readonly-local + unknown 首次确认后应可缓存")
    }

    // MARK: - short-circuit 行为

    /// effective set 含多 permission，其中一条需 consent → 整体短路返回该条
    func test_gate_multiplePermissions_shortCircuitsOnFirstNonApproved() async {
        let broker = PermissionBroker()
        // .fileRead (readonly-local + firstParty) → .approved
        // .fileWrite (local-write + firstParty)   → .requiresUserConsent
        // 期望 broker 短路返回 fileWrite 的 outcome
        let outcome = await broker.gate(
            effective: [Self.permFileRead, Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        guard case .requiresUserConsent(let perm, _) = outcome else {
            return XCTFail("应短路返回首个非 approved，实际 \(outcome)")
        }
        XCTAssertEqual(perm, Self.permFileWrite, "返回的 permission 应是 fileWrite（按 canonicalKey 排序后第一条非 approved）")
    }

    /// 全 readonly-local + firstParty → .approved
    func test_gate_allReadonlyLocal_returnsApproved() async {
        let broker = PermissionBroker()
        let permissions: Set<Permission> = [
            .fileRead(path: "~/Documents/a.md"),
            .fileRead(path: "~/Documents/b.md"),
            .clipboardHistory,
            .screen,
            .memoryAccess(scope: "tool.x")
        ]
        let outcome = await broker.gate(
            effective: permissions,
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "全 readonly-local + firstParty 应整体放行")
    }

    /// 空 effective set → .approved（无 permission 即无下限触发）
    func test_gate_emptyEffective_returnsApproved() async {
        let broker = PermissionBroker()
        let outcome = await broker.gate(
            effective: [],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "空 effective 集合应直接通过")
    }

    // MARK: - inferTier 映射断言（M2 保守归类的回归保护）

    /// 验证 11 case Permission → 5 tier 的最终映射
    func test_inferTier_mapsAllPermissionCases() {
        // readonly-local
        XCTAssertEqual(PermissionBroker.inferTier(.fileRead(path: "x")), .readonlyLocal)
        XCTAssertEqual(PermissionBroker.inferTier(.clipboardHistory), .readonlyLocal)
        XCTAssertEqual(PermissionBroker.inferTier(.memoryAccess(scope: "x")), .readonlyLocal)
        XCTAssertEqual(PermissionBroker.inferTier(.screen), .readonlyLocal)
        // local-write
        XCTAssertEqual(PermissionBroker.inferTier(.fileWrite(path: "x")), .localWrite)
        XCTAssertEqual(PermissionBroker.inferTier(.clipboard), .localWrite)
        XCTAssertEqual(PermissionBroker.inferTier(.systemAudio), .localWrite)
        // network-write
        XCTAssertEqual(PermissionBroker.inferTier(.network(host: "x")), .networkWrite)
        XCTAssertEqual(PermissionBroker.inferTier(.mcp(server: "x", tools: nil)), .networkWrite)
        // exec
        XCTAssertEqual(PermissionBroker.inferTier(.shellExec(commands: ["x"])), .exec)
        XCTAssertEqual(PermissionBroker.inferTier(.appIntents(bundleId: "x")), .exec)
    }

    /// 验证 cacheable 映射
    func test_cacheable_blocksEachTimeTiers() {
        XCTAssertTrue(PermissionBroker.cacheable(tier: .readonlyLocal))
        XCTAssertTrue(PermissionBroker.cacheable(tier: .readonlyNetwork))
        XCTAssertTrue(PermissionBroker.cacheable(tier: .localWrite))
        XCTAssertFalse(PermissionBroker.cacheable(tier: .networkWrite), "network-write 永不缓存")
        XCTAssertFalse(PermissionBroker.cacheable(tier: .exec), "exec 永不缓存")
    }
}
