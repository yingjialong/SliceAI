import Foundation

/// v2 应用配置聚合（独立新类型；现有 `Configuration` 保持 v1 形状，`currentSchemaVersion = 1`）
///
/// 由 `ConfigMigratorV1ToV2.migrate(_:)` 产出、由 `V2ConfigurationStore` 读写。
/// 真实 app 启动路径在 M1 阶段**不消费**此类型（它们仍用 v1 `Configuration`）。
///
/// M3 的 rename pass 会把本文件改名为 `Configuration.swift` 并删除旧 v1 `Configuration`。
public struct V2Configuration: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public var providers: [V2Provider]
    public var tools: [V2Tool]
    public var hotkeys: HotkeyBindings
    public var triggers: TriggerSettings
    public var telemetry: TelemetrySettings
    public var appBlocklist: [String]
    public var appearance: AppearanceMode

    /// 当前 v2 schema 版本
    public static let currentSchemaVersion = 2

    /// 构造 V2Configuration
    public init(
        schemaVersion: Int = V2Configuration.currentSchemaVersion,
        providers: [V2Provider],
        tools: [V2Tool],
        hotkeys: HotkeyBindings,
        triggers: TriggerSettings,
        telemetry: TelemetrySettings,
        appBlocklist: [String],
        appearance: AppearanceMode = .auto
    ) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.tools = tools
        self.hotkeys = hotkeys
        self.triggers = triggers
        self.telemetry = telemetry
        self.appBlocklist = appBlocklist
        self.appearance = appearance
    }
}
