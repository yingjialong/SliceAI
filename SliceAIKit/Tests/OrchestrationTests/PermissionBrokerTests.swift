import Capabilities
import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// Task 6: `PermissionBroker` 默认实现的 §3.9.1 / §3.9.2 全表覆盖测试
///
/// **核心断言矩阵**（plan line 1715-1719 + spec §3.9.1 表）：
/// - 5 tier × 4 provenance = 20 cell 全部独立用例（不抽样）
/// - readonly-local 子集（4 cell）：firstParty / signed / selfManaged → .approved；unknown → 调 presenter 后 approved/denied
/// - readonly-network / local-write 子集（8 cell）：所有 4 provenance → 首次 presenter 确认
/// - network-write / exec 子集（8 cell）：所有 4 provenance → 每次 presenter 确认，不缓存
///
/// **dry-run 子矩阵**（额外 cell）：
/// - dry-run + network-write/exec → .wouldRequireConsent（占位事件）
/// - dry-run + readonly-network/local-write → .wouldRequireConsent（不调用 presenter）
///
/// **grant cache 子矩阵**：
/// - 已有 readonly-network grant → .approved（首次确认后缓存命中）
/// - 已有 local-write grant → .approved（同上）
/// - network-write / exec grant 写入由 store 层拒绝，broker 每次走 presenter
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

    /// 构造测试用 broker；默认 presenter 用于矩阵测试，把 consent 下限推进为 approved
    private static func makeBroker(
        store: PermissionGrantStore = .init(),
        persistentStore: PersistentPermissionGrantStore? = nil,
        presenter: any PermissionConsentPresenting = StaticConsentPresenter(decision: .approve(scope: .oneTime))
    ) -> PermissionBroker {
        PermissionBroker(store: store, persistentStore: persistentStore, consentPresenter: presenter)
    }

    // MARK: - readonly-local × 4 provenance（4 cell）

    /// readonly-local + firstParty → .approved（spec §3.9.1 line 939）
    func test_gate_readonlyLocal_firstParty_returnsApproved() async {
        let broker = Self.makeBroker()
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
        let broker = Self.makeBroker()
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
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.selfManaged,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "readonly-local + selfManaged 应静默通过")
    }

    /// readonly-local + unknown → 调用 presenter 并在 approve 后返回 .approved
    /// 注：plan line 1718 简化表述与 spec 表存在出入，按 spec 准确实现
    func test_gate_readonlyLocal_unknown_callsPresenterAndReturnsApproved() async {
        let presenter = RecordingConsentPresenter(decision: .approve(scope: .oneTime))
        let broker = Self.makeBroker(presenter: presenter)
        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "readonly-local + unknown 经 presenter 一次确认后应通过")
        let request = await presenter.lastRequest
        let perm = request?.permission
        let hint = request?.uxHint ?? ""
        XCTAssertEqual(perm, Self.permFileRead)
        XCTAssertTrue(hint.contains("readonly-local"), "uxHint 应含 tier 标签：\(hint)")
        XCTAssertTrue(hint.contains("unknown"), "uxHint 应含 provenance 标签：\(hint)")
        XCTAssertTrue(hint.contains("not verified"), "unknown 来源应使用警告文案：\(hint)")
    }

    // MARK: - local-write × 4 provenance（4 cell；D-25 firstParty 也不可跳过首次确认）

    /// local-write + firstParty → 调用 presenter 并在 approve 后返回 .approved（D-25：首次确认不可跳过）
    func test_gate_localWrite_firstParty_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "local-write + firstParty 经 presenter 一次确认后应通过")
        let hint = PermissionBroker.uxHint(tier: .localWrite, provenance: Self.firstParty)
        let perm = Self.permFileWrite
        XCTAssertEqual(perm, Self.permFileWrite)
        XCTAssertTrue(hint.contains("local-write"), "uxHint 应含 tier：\(hint)")
        XCTAssertTrue(hint.contains("firstParty"), "uxHint 应含 provenance：\(hint)")
        XCTAssertTrue(hint.contains("Authorize"), "firstParty 应使用中性文案：\(hint)")
    }

    /// local-write + communitySigned → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_localWrite_communitySigned_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.communitySigned,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "local-write + communitySigned 经 presenter 一次确认后应通过")
    }

    /// local-write + selfManaged → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_localWrite_selfManaged_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.selfManaged,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "local-write + selfManaged 经 presenter 一次确认后应通过")
    }

    /// local-write + unknown → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_localWrite_unknown_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "local-write + unknown 经 presenter 一次确认后应通过")
        let hint = PermissionBroker.uxHint(tier: .localWrite, provenance: Self.unknown)
        XCTAssertTrue(hint.contains("not verified"), "unknown 来源应使用警告文案：\(hint)")
    }

    // MARK: - network-write × 4 provenance（4 cell；D-22 每次确认，不可缓存）

    /// network-write + firstParty → 调用 presenter 并在 approve 后返回 .approved（D-22：firstParty 也不能静默放行）
    func test_gate_networkWrite_firstParty_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "network-write + firstParty 经 presenter 单次确认后应通过")
        let hint = PermissionBroker.uxHint(tier: .networkWrite, provenance: Self.firstParty)
        let perm = Self.permNetwork
        XCTAssertEqual(perm, Self.permNetwork)
        XCTAssertTrue(hint.contains("network-write"))
    }

    /// network-write + communitySigned → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_networkWrite_communitySigned_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.communitySigned,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "network-write + communitySigned 经 presenter 单次确认后应通过")
    }

    /// network-write + selfManaged → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_networkWrite_selfManaged_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.selfManaged,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "network-write + selfManaged 经 presenter 单次确认后应通过")
    }

    /// network-write + unknown → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_networkWrite_unknown_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "network-write + unknown 经 presenter 单次确认后应通过")
        let hint = PermissionBroker.uxHint(tier: .networkWrite, provenance: Self.unknown)
        XCTAssertTrue(hint.contains("not verified"))
    }

    // MARK: - exec × 4 provenance（4 cell；D-22 每次确认）

    /// exec + firstParty → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_exec_firstParty_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "exec + firstParty 经 presenter 单次确认后应通过")
        let hint = PermissionBroker.uxHint(tier: .exec, provenance: Self.firstParty)
        let perm = Self.permShellExec
        XCTAssertEqual(perm, Self.permShellExec)
        XCTAssertTrue(hint.contains("exec"))
    }

    /// exec + communitySigned → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_exec_communitySigned_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.communitySigned,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "exec + communitySigned 经 presenter 单次确认后应通过")
    }

    /// exec + selfManaged → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_exec_selfManaged_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.selfManaged,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "exec + selfManaged 经 presenter 单次确认后应通过")
    }

    /// exec + unknown → 调用 presenter 并在 approve 后返回 .approved
    func test_gate_exec_unknown_callsPresenterAndReturnsApproved() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "exec + unknown 经 presenter 单次确认后应通过")
        let hint = PermissionBroker.uxHint(tier: .exec, provenance: Self.unknown)
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

    /// dry-run + network-write → .wouldRequireConsent（spec §3.9.2）
    func test_dryRun_networkWriteReturnsWouldRequireConsent() async throws {
        let presenter = RecordingConsentPresenter(decision: .approve(scope: .oneTime))
        let broker = Self.makeBroker(presenter: presenter)
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
        let requestCount = await presenter.requestCount
        XCTAssertEqual(requestCount, 0, "dry-run 不应调用 presenter")
    }

    /// dry-run + exec → .wouldRequireConsent
    func test_gate_dryRun_exec_returnsWouldRequireConsent() async {
        let broker = Self.makeBroker()
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

    /// dry-run + local-write → .wouldRequireConsent，且不调用 presenter
    func test_gate_dryRun_localWrite_returnsWouldRequireConsent() async {
        let broker = Self.makeBroker()
        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: true
        )
        guard case .wouldRequireConsent = outcome else {
            return XCTFail("dry-run + local-write 不应调用 presenter，实际 \(outcome)")
        }
    }

    /// dry-run + readonly-local + firstParty → .approved（与非 dry-run 同；下限本就是静默）
    func test_gate_dryRun_readonlyLocal_firstParty_returnsApproved() async {
        let broker = Self.makeBroker()
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
        let broker = Self.makeBroker(store: store)

        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "first-time-confirm tier 已有 grant 应直接放行")
    }

    /// network-write grant 写入会被 store 拒绝；broker 仍按每次确认路径走 presenter
    func test_gate_networkWrite_storeRejectsGrantAndBrokerUsesPresenter() async throws {
        let store = PermissionGrantStore()
        do {
            try await store.record(permission: Self.permNetwork, provenance: Self.firstParty, scope: .session)
            XCTFail("network-write grant 不应允许写入")
        } catch SessionPermissionGrantStoreError.nonCacheablePermission {
            // 预期路径：不可缓存权限由 store 层拒绝
        }
        let broker = Self.makeBroker(store: store)

        let outcome = await broker.gate(
            effective: [Self.permNetwork],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "network-write 旧 grant 不应命中，但 presenter approve 后应通过")
    }

    /// exec grant 写入会被 store 拒绝；broker 仍按每次确认路径走 presenter
    func test_gate_exec_storeRejectsGrantAndBrokerUsesPresenter() async throws {
        let store = PermissionGrantStore()
        do {
            try await store.record(permission: Self.permShellExec, provenance: Self.firstParty, scope: .session)
            XCTFail("exec grant 不应允许写入")
        } catch SessionPermissionGrantStoreError.nonCacheablePermission {
            // 预期路径：不可缓存权限由 store 层拒绝
        }
        let broker = Self.makeBroker(store: store)

        let outcome = await broker.gate(
            effective: [Self.permShellExec],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "exec 旧 grant 不应命中，但 presenter approve 后应通过")
    }

    /// readonly-local + unknown 已有 grant → 后续 gate .approved（首次确认 → 缓存命中）
    func test_gate_readonlyLocal_unknownWithGrant_returnsApproved() async throws {
        let store = PermissionGrantStore()
        try await store.record(permission: Self.permFileRead, provenance: Self.unknown, scope: .session)
        let broker = Self.makeBroker(store: store)

        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "readonly-local + unknown 首次确认后应可缓存")
    }

    // MARK: - short-circuit 行为

    /// effective set 含多 permission，其中一条需 consent → presenter approve 后整体通过
    func test_gate_multiplePermissions_resolvesConsentAndReturnsApproved() async {
        let broker = Self.makeBroker()
        // .fileRead (readonly-local + firstParty) → .approved
        // .fileWrite (local-write + firstParty)   → presenter approve
        let outcome = await broker.gate(
            effective: [Self.permFileRead, Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        XCTAssertEqual(outcome, .approved, "presenter approve 后整体应放行")
    }

    /// 全 readonly-local + firstParty → .approved
    func test_gate_allReadonlyLocal_returnsApproved() async {
        let broker = Self.makeBroker()
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
        let broker = Self.makeBroker()
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

    // MARK: - Task 8：UI-free consent boundary

    /// readonly-local + unknown 需要 consent；生产 broker 通过 presenter 解析成 approved/denied
    func test_readonlyLocal_unknownRequiresConsent() async throws {
        let presenter = RecordingConsentPresenter(decision: .approve(scope: .oneTime))
        let broker = Self.makeBroker(presenter: presenter)

        let outcome = await broker.gate(
            effective: [Self.permFileRead],
            provenance: Self.unknown,
            scope: .session,
            isDryRun: false
        )

        XCTAssertEqual(outcome, .approved)
        let maybeRequest = await presenter.lastRequest
        let request = try XCTUnwrap(maybeRequest)
        XCTAssertEqual(request.permission, Self.permFileRead)
        XCTAssertEqual(request.provenance, Self.unknown)
        XCTAssertEqual(request.allowedScopes, [.oneTime, .session])
        XCTAssertTrue(request.uxHint.contains("readonly-local"))
    }

    /// 首次 local-write 应调用 consent handler，而不是把 requiresUserConsent 泄漏给生产调用方
    func test_permissionBroker_callsConsentHandlerForFirstTimeLocalWrite() async throws {
        let presenter = RecordingConsentPresenter(decision: .deny(reason: "user cancelled"))
        let broker = Self.makeBroker(presenter: presenter)

        let outcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )

        XCTAssertEqual(outcome, .denied(permission: Self.permFileWrite, reason: "user cancelled"))
        let maybeRequest = await presenter.lastRequest
        let request = try XCTUnwrap(maybeRequest)
        XCTAssertEqual(request.permission, Self.permFileWrite)
        XCTAssertEqual(request.allowedScopes, [.oneTime, .session])
    }

    /// cacheable tier 经用户批准 session 后应写入 PermissionGrantStore，下一次 gate 不再调用 presenter
    func test_permissionBroker_approvalRecordsSessionGrantForCacheableTier() async throws {
        let store = PermissionGrantStore()
        let presenter = RecordingConsentPresenter(decision: .approve(scope: .session))
        let broker = Self.makeBroker(store: store, presenter: presenter)

        let firstOutcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        let secondOutcome = await broker.gate(
            effective: [Self.permFileWrite],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )

        XCTAssertEqual(firstOutcome, .approved)
        XCTAssertEqual(secondOutcome, .approved)
        let grantHit = await store.has(permission: Self.permFileWrite, provenance: Self.firstParty)
        let requestCount = await presenter.requestCount
        XCTAssertTrue(grantHit)
        XCTAssertEqual(requestCount, 1, "第二次应命中 session grant，不再请求 presenter")
    }

    /// MCP 权限必须每次走 presenter，allowedScopes 只能是一锤子授权
    func test_permissionBroker_mcpApprovalIsOneInvocationOnly() async throws {
        let permission = Permission.mcp(server: "filesystem", tools: ["write"])
        let presenter = RecordingConsentPresenter(decision: .approve(scope: .session))
        let broker = Self.makeBroker(presenter: presenter)

        let firstOutcome = await broker.gate(
            effective: [permission],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        let secondOutcome = await broker.gate(
            effective: [permission],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )

        XCTAssertEqual(firstOutcome, .approved)
        XCTAssertEqual(secondOutcome, .approved)
        let requestCount = await presenter.requestCount
        XCTAssertEqual(requestCount, 2, "MCP 权限不能因 presenter 返回 session 而缓存")
        let maybeRequest = await presenter.lastRequest
        let request = try XCTUnwrap(maybeRequest)
        XCTAssertEqual(request.allowedScopes, [.oneTime])
    }

    /// Brave web search MCP 是内置只读搜索工具，允许用户选择会话授权和持久授权。
    func test_permissionBroker_braveSearchAllowsSessionAndPersistentScopes() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let persistentStore = PersistentPermissionGrantStore(fileURL: fileURL)
        let permission = Permission.mcp(server: "brave-search", tools: ["brave_web_search"])
        let presenter = RecordingConsentPresenter(decision: .approve(scope: .oneTime))
        let broker = Self.makeBroker(persistentStore: persistentStore, presenter: presenter)

        let outcome = await broker.gate(
            effective: [permission],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )

        XCTAssertEqual(outcome, .approved)
        let maybeRequest = await presenter.lastRequest
        let request = try XCTUnwrap(maybeRequest)
        XCTAssertEqual(request.allowedScopes, [.oneTime, .session, .persistent])
    }

    /// Brave web search MCP 的 session 授权应在当前 App 会话内复用，避免每次搜索都弹窗。
    func test_permissionBroker_braveSearchSessionGrantIsCached() async throws {
        let permission = Permission.mcp(server: "brave-search", tools: ["brave_web_search"])
        let presenter = RecordingConsentPresenter(decision: .approve(scope: .session))
        let broker = Self.makeBroker(presenter: presenter)

        let firstOutcome = await broker.gate(
            effective: [permission],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )
        let secondOutcome = await broker.gate(
            effective: [permission],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )

        XCTAssertEqual(firstOutcome, .approved)
        XCTAssertEqual(secondOutcome, .approved)
        let requestCount = await presenter.requestCount
        XCTAssertEqual(requestCount, 1, "Brave 搜索会话授权命中后不应重复弹窗")
    }

    /// Brave web search MCP 的持久授权应写入 persistent store，并被新的 broker 实例命中。
    func test_permissionBroker_braveSearchPersistentGrantIsCachedAcrossBrokers() async throws {
        let fileURL = try Self.makeTemporaryGrantFileURL()
        let permission = Permission.mcp(server: "brave-search", tools: ["brave_web_search"])
        let firstPersistentStore = PersistentPermissionGrantStore(fileURL: fileURL)
        let presenter = RecordingConsentPresenter(decision: .approve(scope: .persistent))
        let firstBroker = Self.makeBroker(persistentStore: firstPersistentStore, presenter: presenter)

        let firstOutcome = await firstBroker.gate(
            effective: [permission],
            provenance: Self.firstParty,
            scope: .persistent,
            isDryRun: false
        )
        let secondPersistentStore = PersistentPermissionGrantStore(fileURL: fileURL)
        let secondPresenter = RecordingConsentPresenter(decision: .deny(reason: "should not ask"))
        let secondBroker = Self.makeBroker(persistentStore: secondPersistentStore, presenter: secondPresenter)
        let secondOutcome = await secondBroker.gate(
            effective: [permission],
            provenance: Self.firstParty,
            scope: .session,
            isDryRun: false
        )

        XCTAssertEqual(firstOutcome, .approved)
        XCTAssertEqual(secondOutcome, .approved)
        let firstRequestCount = await presenter.requestCount
        let secondRequestCount = await secondPresenter.requestCount
        XCTAssertEqual(firstRequestCount, 1)
        XCTAssertEqual(secondRequestCount, 0, "持久授权命中后不应再次请求 presenter")
    }

    /// 创建临时 grant 文件路径。
    private static func makeTemporaryGrantFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("permission-grants.json")
    }
}

/// 固定返回 consent 决策的测试 presenter
private struct StaticConsentPresenter: PermissionConsentPresenting {
    let decision: PermissionConsentDecision

    /// 返回初始化时指定的决策
    func requestConsent(_ request: PermissionConsentRequest) async -> PermissionConsentDecision {
        decision
    }
}

/// 记录请求次数和最后一次请求的测试 presenter
private actor RecordingConsentPresenter: PermissionConsentPresenting {
    private let decision: PermissionConsentDecision
    private var requests: [PermissionConsentRequest] = []

    /// 构造记录型 presenter
    init(decision: PermissionConsentDecision) {
        self.decision = decision
    }

    /// 返回最后一次收到的 consent 请求
    var lastRequest: PermissionConsentRequest? {
        requests.last
    }

    /// 返回累计请求次数
    var requestCount: Int {
        requests.count
    }

    /// 记录请求后返回预设决策
    func requestConsent(_ request: PermissionConsentRequest) async -> PermissionConsentDecision {
        requests.append(request)
        return decision
    }
}
