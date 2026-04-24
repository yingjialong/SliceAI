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
    ///
    /// **抛错语义（P1 修复）**：v2 JSON 损坏 / schemaVersion 高于支持 / v1 迁移失败时
    /// 原样向外抛出 `SliceError.configuration(...)`，由上层（M3 AppContainer）决定是否
    /// 告警用户 + 中止启动。严禁回退 DefaultV2Configuration.initial() 覆盖损坏文件——否则
    /// 下次 update() 会把默认值写回原路径，用户原有 providers / tools 永久丢失。
    ///
    /// "两个文件都不存在"不是错误：`load()` 会直接返回默认配置。
    ///
    /// **错误不缓存**：throw 时 `cached` 保持 nil，下次调用会重新从磁盘 load——这样用户
    /// 修好 `config-v2.json` 后下一次 `current()` 即可自动恢复，无需重启 app。
    public func current() async throws -> V2Configuration {
        if let cached { return cached }
        let loaded = try await load()
        cached = loaded
        v2ConfigLog.debug("current() loaded v2 config")
        return loaded
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
            v2ConfigLog.info("v2 missing, migrating from v1 at \(legacyFileURL.path, privacy: .private)")
            let v2 = try migrateFromLegacy(at: legacyFileURL)
            try writeV2(v2)
            return v2
        }
        v2ConfigLog.debug("load() neither v2 nor v1 exists, returning DefaultV2Configuration.initial()")
        return DefaultV2Configuration.initial()
    }

    /// 写 v2；永不碰 v1
    ///
    /// **写入边界（第八轮 P2-1/P2-2 修复）**：落盘前逐个 validate providers / tools。
    /// 首个违规直接 throw `SliceError.configuration(.validationFailed)`，磁盘文件不会被写入/覆盖。
    /// `update()` 是 `try await save(...); cached = configuration`，因此 validate 失败时
    /// 缓存也不会被更新——天然符合"非法对象不入磁盘、不入内存"的不变量。
    public func save(_ configuration: V2Configuration) async throws {
        try validate(configuration)
        try writeV2(configuration)
    }

    /// 在落盘前逐个 validate providers / tools；首个违规立即抛出
    ///
    /// 目的是让 V2Provider / V2Tool 的写入边界在 save() 路径上集中执行。
    /// decoder 已校验的是 JSON 输入（用户手改 config-v2.json），而此处校验的是
    /// 代码构造的对象（测试 / 默认值 / migrator 输出 / UI 未来的 ToolEditor）。
    private func validate(_ cfg: V2Configuration) throws {
        for p in cfg.providers {
            try p.validate()
        }
        for t in cfg.tools {
            try t.validate()
        }
    }

    // MARK: - Path helpers

    /// v2 默认路径 `~/Library/Application Support/SliceAI/config-v2.json`
    public static func standardV2FileURL() -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        return appSupport.appendingPathComponent("config-v2.json")
    }

    /// v1 旧路径，**仅供参考 / 测试 / M3 迁移使用**
    ///
    /// **DO NOT** wire this into AppContainer as the real v1 read path.
    /// AppContainer 应该继续使用 `FileConfigurationStore.standardFileURL()`；
    /// 本方法的存在只是让 V2ConfigurationStore 测试能构造 legacyFileURL 参数。
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
            v2ConfigLog.error("v2 read failed: \(error.localizedDescription, privacy: .private)")
            throw SliceError.configuration(.invalidJSON("<redacted>"))
        }

        let cfg: V2Configuration
        do {
            cfg = try JSONDecoder().decode(V2Configuration.self, from: data)
        } catch {
            v2ConfigLog.error("v2 decode failed: \(error.localizedDescription, privacy: .private)")
            throw SliceError.configuration(.invalidJSON("<redacted>"))
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
            throw SliceError.configuration(.invalidJSON("<redacted>"))
        }
        let v1: LegacyConfigV1
        do {
            v1 = try JSONDecoder().decode(LegacyConfigV1.self, from: data)
        } catch {
            throw SliceError.configuration(.invalidJSON("<redacted>"))
        }
        // migrate() 现在 throws（第八轮 P2-3 修复）：v1.schemaVersion ≠ 1 时原样抛出
        // .schemaVersionTooNew，阻止 current()/load() 把未知版本的配置写成 v2
        return try ConfigMigratorV1ToV2.migrate(v1)
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
