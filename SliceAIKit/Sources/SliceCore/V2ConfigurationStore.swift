import Foundation
import OSLog

private let v2ConfigLog = Logger(subsystem: "com.sliceai.core", category: "V2ConfigurationStore")

/// v2 配置的读写 actor（独立于现有 `FileConfigurationStore`）
///
/// 持有 `V2Configuration` 类型；与 v1 store 完全隔离：
/// - 不继承、不包装 `FileConfigurationStore`
/// - 不共享 Configuration Codable
/// - 仅被 M3 的 AppContainer 启用；M1 的真实 app 启动路径不经过此 store
///
/// 规则（对齐 spec §3.7）：
/// 1. v2 文件存在 → 直接 decode V2Configuration
/// 2. v2 不存在但 v1 存在 → 读 v1 原文 → `ConfigMigratorV1ToV2.migrate(_:)` → 写 v2 → 返回 v2；**不改 v1**
/// 3. 两者都不存在 → 返回 `DefaultV2Configuration.initial()`
/// 4. `save()` 始终写 v2 路径；v1 永不被写
public actor V2ConfigurationStore {

    private let fileURL: URL
    private let legacyFileURL: URL?
    private var cached: V2Configuration?

    /// 构造 V2ConfigurationStore
    /// - Parameters:
    ///   - fileURL: v2 目标 JSON 路径（`config-v2.json`）
    ///   - legacyFileURL: v1 旧文件路径；nil 表示不做 v1 迁移
    public init(fileURL: URL, legacyFileURL: URL?) {
        self.fileURL = fileURL
        self.legacyFileURL = legacyFileURL
    }

    /// 获取当前 v2 配置：优先缓存 → v2 文件 → migrator → 默认配置
    public func current() async -> V2Configuration {
        if let cached { return cached }
        if let loaded = try? await load() {
            cached = loaded
            v2ConfigLog.debug("current() loaded v2 config")
            return loaded
        }
        let fallback = DefaultV2Configuration.initial()
        cached = fallback
        v2ConfigLog.debug("current() falling back to DefaultV2Configuration.initial()")
        return fallback
    }

    /// 更新并持久化到 v2 路径
    public func update(_ configuration: V2Configuration) async throws {
        try await save(configuration)
        cached = configuration
    }

    /// 加载配置（按 §3.7 规则）
    public func load() async throws -> V2Configuration {
        if FileManager.default.fileExists(atPath: fileURL.path) {
            return try loadV2Direct()
        }
        if let legacyFileURL, FileManager.default.fileExists(atPath: legacyFileURL.path) {
            v2ConfigLog.info("v2 missing, migrating from v1 at \(legacyFileURL.path, privacy: .public)")
            let v2 = try migrateFromLegacy(at: legacyFileURL)
            try writeV2(v2)
            return v2
        }
        v2ConfigLog.debug("load() neither v2 nor v1 exists, returning DefaultV2Configuration.initial()")
        return DefaultV2Configuration.initial()
    }

    /// 写 v2；永不碰 v1
    public func save(_ configuration: V2Configuration) async throws {
        try writeV2(configuration)
    }

    // MARK: - Path helpers

    /// v2 默认路径 `~/Library/Application Support/SliceAI/config-v2.json`
    public static func standardV2FileURL() -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("config-v2.json")
    }

    /// v1 旧路径（只供参考；v1 store 自己的 standardFileURL() 才是 AppContainer 读到的）
    public static func legacyV1FileURL() -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("config.json")
    }

    // MARK: - Private

    /// 直接读 v2 文件
    private func loadV2Direct() throws -> V2Configuration {
        let data: Data
        do {
            data = try Data(contentsOf: fileURL)
        } catch {
            v2ConfigLog.error("v2 read failed: \(error.localizedDescription, privacy: .public)")
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }

        let cfg: V2Configuration
        do {
            cfg = try JSONDecoder().decode(V2Configuration.self, from: data)
        } catch {
            v2ConfigLog.error("v2 decode failed: \(error.localizedDescription, privacy: .public)")
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }

        if cfg.schemaVersion > V2Configuration.currentSchemaVersion {
            throw SliceError.configuration(.schemaVersionTooNew(cfg.schemaVersion))
        }
        return cfg
    }

    /// 读 v1 原文 → LegacyConfigV1 → V2Configuration
    private func migrateFromLegacy(at legacyURL: URL) throws -> V2Configuration {
        let data: Data
        do {
            data = try Data(contentsOf: legacyURL)
        } catch {
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }
        let v1: LegacyConfigV1
        do {
            v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        } catch {
            throw SliceError.configuration(.invalidJSON(error.localizedDescription))
        }
        return ConfigMigratorV1ToV2.migrate(v1)
    }

    /// 原子写 v2 文件
    private func writeV2(_ configuration: V2Configuration) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configuration)
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        v2ConfigLog.debug("writeV2: wrote \(data.count, privacy: .public) bytes")
    }
}
