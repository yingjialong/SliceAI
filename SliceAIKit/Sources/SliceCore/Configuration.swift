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
    public var skillSettings: SkillSettings

    /// 当前 v2 schema 版本
    public static let currentSchemaVersion = 3

    /// 构造 Configuration
    public init(
        schemaVersion: Int = Configuration.currentSchemaVersion,
        providers: [Provider],
        tools: [Tool],
        hotkeys: HotkeyBindings,
        triggers: TriggerSettings,
        telemetry: TelemetrySettings,
        appBlocklist: [String],
        appearance: AppearanceMode = .auto,
        skillSettings: SkillSettings = .empty
    ) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.tools = tools
        self.hotkeys = hotkeys
        self.triggers = triggers
        self.telemetry = telemetry
        self.appBlocklist = appBlocklist
        self.appearance = appearance
        self.skillSettings = skillSettings
    }

    private enum CodingKeys: String, CodingKey {
        case schemaVersion, providers, tools, hotkeys, triggers, telemetry, appBlocklist, appearance, skillSettings
    }

    /// 兼容旧版 config-v2：缺少 skillSettings 时使用空设置。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try c.decode(Int.self, forKey: .schemaVersion)
        providers = try c.decode([Provider].self, forKey: .providers)
        tools = try c.decode([Tool].self, forKey: .tools)
        hotkeys = try c.decode(HotkeyBindings.self, forKey: .hotkeys)
        triggers = try c.decode(TriggerSettings.self, forKey: .triggers)
        telemetry = try c.decode(TelemetrySettings.self, forKey: .telemetry)
        appBlocklist = try c.decode([String].self, forKey: .appBlocklist)
        appearance = try c.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .auto
        skillSettings = try c.decodeIfPresent(SkillSettings.self, forKey: .skillSettings) ?? .empty
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(schemaVersion, forKey: .schemaVersion)
        try c.encode(providers, forKey: .providers)
        try c.encode(tools, forKey: .tools)
        try c.encode(hotkeys, forKey: .hotkeys)
        try c.encode(triggers, forKey: .triggers)
        try c.encode(telemetry, forKey: .telemetry)
        try c.encode(appBlocklist, forKey: .appBlocklist)
        try c.encode(appearance, forKey: .appearance)
        try c.encode(skillSettings, forKey: .skillSettings)
    }
}
