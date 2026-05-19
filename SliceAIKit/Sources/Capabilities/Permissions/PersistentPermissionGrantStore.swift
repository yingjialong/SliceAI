import Foundation
import OSLog
import SliceCore

private let persistentGrantStoreLog = Logger(
    subsystem: "com.sliceai.capabilities",
    category: "PersistentPermissionGrantStore"
)

/// Persistent permission grant 存储错误
public enum PersistentPermissionGrantStoreError: Error, Sendable, Equatable {
    /// 尝试持久化必须逐次确认的权限
    case nonCacheablePermission(Permission)
    /// 磁盘文件 schemaVersion 与当前实现不兼容
    case unsupportedSchemaVersion(Int)
    /// 磁盘中的 grant 记录不满足持久授权约束
    case invalidStoredGrant(Permission)
}

/// 磁盘持久化的 permission grant store。
///
/// 默认路径：`~/Library/Application Support/SliceAI/permission-grants.json`。
/// 该 store 只保存 `.persistent` grant；`.session` 由 Orchestration 的 in-memory store 负责，
/// `.oneTime` 不进入任何缓存；MCP 仅允许精确白名单内置只读工具持久化。
public actor PersistentPermissionGrantStore {

    /// 当前文件 schema 版本。
    public static let currentSchemaVersion = 1

    private let fileURL: URL

    /// 构造 persistent grant store。
    /// - Parameter fileURL: 可选自定义文件路径；nil 时使用标准 Application Support 路径。
    public init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.standardFileURL()
    }

    /// 查询某条 `(permission, provenance)` 是否已有 persistent grant。
    /// - Parameters:
    ///   - permission: 待查询权限。
    ///   - provenance: 工具来源。
    /// - Returns: true 表示命中 persistent grant。
    public func has(permission: Permission, provenance: Provenance) -> Bool {
        guard Self.isCacheable(permission) else {
            return false
        }
        do {
            let configuration = try loadSync()
            let tag = Self.tag(for: provenance)
            return configuration.grants.contains { entry in
                entry.permission == permission && entry.provenanceTag == tag
            }
        } catch {
            persistentGrantStoreLog.error("failed to load permission grants")
            return false
        }
    }

    /// 记录 persistent grant。
    /// - Parameters:
    ///   - permission: 被授予的权限。
    ///   - provenance: 工具来源。
    ///   - scope: 授权范围；只有 `.persistent` 会写盘。
    /// - Throws: 不可缓存权限或文件读写错误。
    public func record(permission: Permission, provenance: Provenance, scope: GrantScope) throws {
        guard Self.isCacheable(permission) else {
            throw PersistentPermissionGrantStoreError.nonCacheablePermission(permission)
        }
        guard scope == .persistent else {
            persistentGrantStoreLog.debug("skip non-persistent grant scope=\(scope.rawValue, privacy: .public)")
            return
        }

        var configuration = try loadSync()
        let tag = Self.tag(for: provenance)
        let entry = StoredPermissionGrant(
            permission: permission,
            provenance: provenance,
            provenanceTag: tag,
            grant: PermissionGrant(
                permission: permission,
                grantedAt: Date(),
                grantedBy: .userConsent,
                scope: .persistent
            )
        )

        // 同一 permission + provenance 覆盖旧 grant，避免 JSON 文件无限追加重复项。
        configuration.grants.removeAll { existing in
            existing.permission == permission && existing.provenanceTag == tag
        }
        configuration.grants.append(entry)
        configuration.grants.sort { lhs, rhs in
            lhs.sortKey < rhs.sortKey
        }
        try saveSync(configuration)
    }

    /// 标准 `permission-grants.json` 路径。
    /// - Returns: `~/Library/Application Support/SliceAI/permission-grants.json`。
    public static func standardFileURL() -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("permission-grants.json")
    }

    /// 同步读取配置；actor 内部调用，不跨 await。
    /// - Returns: grant 配置。
    /// - Throws: JSON 读取或解码错误。
    private func loadSync() throws -> PermissionGrantConfiguration {
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return PermissionGrantConfiguration(schemaVersion: Self.currentSchemaVersion, grants: [])
        }

        let data = try Data(contentsOf: fileURL)
        let configuration = try JSONDecoder().decode(PermissionGrantConfiguration.self, from: data)
        try Self.validate(configuration)
        persistentGrantStoreLog.debug(
            "loaded permission grants count=\(configuration.grants.count, privacy: .public)"
        )
        return configuration
    }

    /// 同步保存配置；actor 内部调用，不跨 await。
    /// - Parameter configuration: 待保存配置。
    /// - Throws: JSON 编码或文件写入错误。
    private func saveSync(_ configuration: PermissionGrantConfiguration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)

        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        let grantCount = configuration.grants.count
        persistentGrantStoreLog.debug(
            "saved permission grants bytes=\(data.count, privacy: .public) count=\(grantCount, privacy: .public)"
        )
    }

    /// 判断权限是否允许缓存。
    /// - Parameter permission: 待判断权限。
    /// - Returns: true 表示可缓存；false 表示必须逐次确认。
    private static func isCacheable(_ permission: Permission) -> Bool {
        permission.supportsRuntimeGrantCache
    }

    /// 校验磁盘 grant 文件是否满足当前持久授权约束。
    /// - Parameter configuration: 已解码的 grant 配置。
    /// - Throws: schema 不兼容或存在非法 grant 记录。
    private static func validate(_ configuration: PermissionGrantConfiguration) throws {
        guard configuration.schemaVersion == currentSchemaVersion else {
            throw PersistentPermissionGrantStoreError.unsupportedSchemaVersion(configuration.schemaVersion)
        }

        for entry in configuration.grants {
            guard isCacheable(entry.permission) else {
                throw PersistentPermissionGrantStoreError.nonCacheablePermission(entry.permission)
            }
            guard entry.grant.scope == .persistent,
                  entry.grant.permission == entry.permission,
                  entry.provenanceTag == tag(for: entry.provenance) else {
                throw PersistentPermissionGrantStoreError.invalidStoredGrant(entry.permission)
            }
        }
    }

    /// 把 provenance 折叠为稳定查询 key。
    /// - Parameter provenance: 工具来源。
    /// - Returns: 稳定字符串 tag。
    private static func tag(for provenance: Provenance) -> String {
        switch provenance {
        case .firstParty:
            return "firstParty"
        case .communitySigned(let publisher, _):
            return "communitySigned:\(publisher)"
        case .selfManaged(let userAcknowledgedAt):
            return "selfManaged:\(userAcknowledgedAt.timeIntervalSince1970)"
        case .unknown(let importedFrom, let importedAt):
            let urlPart = importedFrom?.absoluteString ?? "<no-url>"
            return "unknown:\(urlPart):\(importedAt.timeIntervalSince1970)"
        }
    }
}

/// permission grants 文件结构
private struct PermissionGrantConfiguration: Codable, Sendable, Equatable {
    /// schema version
    var schemaVersion: Int
    /// 已持久化 grants
    var grants: [StoredPermissionGrant]
}

/// 单条持久化 grant 记录
private struct StoredPermissionGrant: Codable, Sendable, Equatable {
    /// 被授权权限
    let permission: Permission
    /// 来源原始值，保留给后续 Settings UI 展示
    let provenance: Provenance
    /// 来源稳定查询 key
    let provenanceTag: String
    /// grant 元数据
    let grant: PermissionGrant

    /// 稳定排序 key，保证 JSON 输出可预测
    var sortKey: String {
        "\(provenanceTag)|\(String(describing: permission))"
    }
}
