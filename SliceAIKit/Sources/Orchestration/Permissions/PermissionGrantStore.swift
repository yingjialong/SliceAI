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
    /// zero-touch（不允许修改）。这里把 provenance 折叠为含**稳定来源身份**的字符串作为
    /// hash 维度——同一 case 下**不同**来源（不同 publisher / 不同导入 URL / 不同 ack 时间）
    /// 视为**不同**信任边界，绝不共享 grant；防止"给 publisher A 授权后 publisher B 自动放行"
    /// 这类 cross-source 授权泄漏。
    private struct GrantKey: Hashable, Sendable {
        let permission: Permission
        let provenanceTag: String
    }

    // MARK: - Stored

    /// In-memory 字典；key 命中即视为有效 grant
    private var grants: [GrantKey: PermissionGrant] = [:]

    /// 把 SliceCore `Provenance` 折叠为含稳定来源身份的字符串 key
    ///
    /// **隔离规则**：
    /// - `.firstParty` 全 App 共享同一信任根 → 仅 case tag
    /// - `.communitySigned(publisher:_)` 不同 publisher 是独立信任根 → 含 publisher（不含 signedAt
    ///   —— publisher 是 Phase 4+ 签名校验背书的稳定身份；同 publisher 重新签名仍命中 grant）
    /// - `.selfManaged(userAcknowledgedAt:)` 每次 ack 视为独立 trust event → 含 timestamp
    /// - `.unknown(importedFrom:importedAt:)` **每次导入事件都是独立信任** → URL + importedAt 都纳入
    ///   key。**rationale**：unknown URL 不具备内容不可变性 / 签名身份（同一 URL 在 T1 / T2 的
    ///   两次导入可能指向不同内容），按 URL 共享 grant 会让 mutable URL 的新内容绕过 consent。
    ///   M2 选择"per-import-event 隔离"语义；Phase 1+ 若 MCPDescriptor 接入 digest/signature 再升级。
    /// - Parameter provenance: 来源 enum
    /// - Returns: 形如 "firstParty" / "communitySigned:Acme" / "unknown:https://x.test:1234567890" 的字符串
    private static func tag(for provenance: Provenance) -> String {
        switch provenance {
        case .firstParty:
            return "firstParty"
        case .communitySigned(let publisher, _):
            return "communitySigned:\(publisher)"
        case .selfManaged(let userAcknowledgedAt):
            return "selfManaged:\(userAcknowledgedAt.timeIntervalSince1970)"
        case .unknown(let importedFrom, let importedAt):
            // URL + importedAt 联合作 key —— per-import-event 隔离：同 URL 二次导入不命中旧 grant
            // 防止 mutable URL（同 URL 不同时刻指向不同内容）通过缓存绕过 consent
            let urlPart = importedFrom?.absoluteString ?? "<no-url>"
            return "unknown:\(urlPart):\(importedAt.timeIntervalSince1970)"
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
