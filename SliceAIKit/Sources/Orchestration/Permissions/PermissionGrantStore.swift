import Foundation
import SliceCore

/// In-memory `PermissionGrant` 存储（actor 隔离）
///
/// **M2 范围**：仅 in-memory session-scoped 实现；persistent grant 写入磁盘 / Settings
/// UI 管理面板留到 Phase 1+。当前实现不区分 `GrantScope`——所有 record 进同一字典，
/// 进程退出即丢；`PermissionBroker` 的"per-tier 是否允许缓存"逻辑由 broker 自身判断
/// （network-write / exec 永不缓存 = broker 不写入 grant store；readonly-network /
/// local-write 首次确认后写入；readonly-local 不需 grant 直接 .approved）。
///
/// **Key 设计：`(Permission, Provenance)` 复合 key**——同一 permission 在不同 provenance
/// 来源下不应共享 grant（如 firstParty 给过 `.fileWrite` 不能让 unknown 来源的 `.fileWrite`
/// 直接 .approved；后者 D-25 仍需"每次确认"）。Key 命中等同于：**同一 permission + 同一
/// provenance** 来源已存在 record。
///
/// **why actor**：`record` / `has` 都需要互斥访问内部字典；actor 是 Swift 6 严格并发下
/// 最自然的隔离形式，与 ContextCollector / CostAccounting 风格一致。
public actor PermissionGrantStore {

    // MARK: - 内部存储 key

    /// `(permission, provenance)` 复合 key；Hashable + Sendable
    ///
    /// **why provenance 字段是 String 而非 Provenance**：SliceCore 的 `Provenance` 仅声明
    /// `Codable + Sendable + Equatable`，**不是 Hashable**——而 SliceCore 在 Task 6 是
    /// zero-touch（不允许修改）。这里把 provenance 折叠成 case 标签字符串作为 key 的
    /// hash 维度，保留 case 区分度（firstParty / communitySigned / selfManaged / unknown）；
    /// case 关联值（publisher / signedAt / importedFrom 等）当前不参与 key 计算——
    /// 同一 case 下不同关联值视为同一 provenance 来源（Phase 1 若需要细分再升级）。
    private struct GrantKey: Hashable, Sendable {
        let permission: Permission
        let provenanceTag: String
    }

    // MARK: - Stored

    /// In-memory 字典；key 命中即视为有效 grant
    private var grants: [GrantKey: PermissionGrant] = [:]

    /// 把 SliceCore `Provenance` 折叠为可 hash 的 case 标签
    /// - Parameter provenance: 来源 enum
    /// - Returns: 形如 "firstParty" / "communitySigned" 的字符串
    private static func tag(for provenance: Provenance) -> String {
        switch provenance {
        case .firstParty:        return "firstParty"
        case .communitySigned:   return "communitySigned"
        case .selfManaged:       return "selfManaged"
        case .unknown:           return "unknown"
        }
    }

    // MARK: - Init

    /// 构造空 grant store（M2 不接受任何初始 grants）
    public init() {}

    // MARK: - Public API

    /// 查询某条 (permission, provenance) 是否已存在 grant
    /// - Parameters:
    ///   - permission: 待查询的 permission
    ///   - provenance: 工具来源
    /// - Returns: true 命中（broker 可视为 .approved）；false 未命中（broker 走下限决策）
    public func has(permission: Permission, provenance: Provenance) -> Bool {
        // 中文调试日志：记录命中查询；测试场景方便观察 broker 是否短路命中
        let key = GrantKey(permission: permission, provenanceTag: Self.tag(for: provenance))
        let hit = grants[key] != nil
        // print 在 broker 层关闭以遵循"无自由日志"规范；此处保留隐式注释提示——M3 接 audit 后再统一
        return hit
    }

    /// 写入一条 grant（broker 在用户确认后调用）
    /// - Parameters:
    ///   - permission: 被授予的 permission
    ///   - provenance: 工具来源
    ///   - scope: 授权时长（M2 不持久化，但记入 PermissionGrant 字段为 Phase 1 留 hook）
    /// - Throws: M2 范围 in-memory 实现不抛错；声明 `throws` 是为 Phase 1 加磁盘持久化时不破坏 ABI
    public func record(permission: Permission, provenance: Provenance, scope: GrantScope) throws {
        // 中文调试日志意图：记录新 grant；M2 阶段以 silent 写入为主
        let key = GrantKey(permission: permission, provenanceTag: Self.tag(for: provenance))
        let grant = PermissionGrant(
            permission: permission,
            grantedAt: Date(),
            grantedBy: .userConsent,
            scope: scope
        )
        grants[key] = grant
    }

    // MARK: - Test helpers（@testable 内部可见）

    /// 当前 grant 数量；仅供测试断言（PermissionBrokerTests / PermissionGrantStoreTests）
    internal var count: Int { grants.count }
}
