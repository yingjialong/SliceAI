import Foundation

/// v2 应用配置聚合，对应 `config-v2.json` 的顶层 schema。
///
/// 由 `ConfigMigratorV1ToV2.migrate(_:)` 产出、由 `ConfigurationStore` 读写。
public struct Configuration: Sendable, Codable, Equatable {
    public let schemaVersion: Int
    public var providers: [Provider]
    public var tools: [Tool]
    public var hotkeys: HotkeyBindings
    public var triggers: TriggerSettings
    public var telemetry: TelemetrySettings
    public var appBlocklist: [String]
    public var appearance: AppearanceMode

    /// 当前 v2 schema 版本
    public static let currentSchemaVersion = 2

    /// 构造 Configuration
    public init(
        schemaVersion: Int = Configuration.currentSchemaVersion,
        providers: [Provider],
        tools: [Tool],
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
