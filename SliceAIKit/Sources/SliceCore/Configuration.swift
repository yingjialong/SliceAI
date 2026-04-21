import Foundation

/// 整个应用的持久化配置，对应 config.json
/// 说明：
///   - `schemaVersion` 为不可变字段（`let`），用于判断迁移策略；
///   - 其他字段均为 `var`，允许运行期编辑并写回磁盘；
///   - 所有子类型（HotkeyBindings / TriggerSettings / TelemetrySettings）与
///     Configuration 强耦合，因此集中放在同一文件中，避免跨文件跳转成本。
public struct Configuration: Sendable, Codable, Equatable {
    /// 当前 JSON schema 版本号（仅能解码到此值，升级时需执行迁移）
    public let schemaVersion: Int
    /// 已配置的 LLM 供应商列表
    public var providers: [Provider]
    /// 已配置的工具（菜单按钮 + prompt 模板）列表
    public var tools: [Tool]
    /// 全局快捷键绑定
    public var hotkeys: HotkeyBindings
    /// 划词/命令面板等触发相关设置
    public var triggers: TriggerSettings
    /// 遥测开关设置
    public var telemetry: TelemetrySettings
    /// 不允许触发划词的应用 bundle id 列表
    public var appBlocklist: [String]
    /// 应用主题模式（跟随系统 / 浅色 / 深色）；旧版 JSON 缺失时默认 `.auto`
    public var appearance: AppearanceMode

    /// JSON 字段名映射，集中管理所有 key，避免拼写错误
    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case providers
        case tools
        case hotkeys
        case triggers
        case telemetry
        case appBlocklist
        case appearance
    }

    /// 构造应用配置聚合
    /// - Parameters:
    ///   - schemaVersion: 当前 schema 版本号，应等于 `Configuration.currentSchemaVersion`
    ///   - providers: LLM 供应商配置列表
    ///   - tools: 工具配置列表
    ///   - hotkeys: 快捷键绑定
    ///   - triggers: 触发行为设置
    ///   - telemetry: 遥测开关
    ///   - appBlocklist: 不允许触发的应用 bundle id 列表
    ///   - appearance: 主题模式，默认 `.auto`（跟随系统）
    public init(schemaVersion: Int, providers: [Provider], tools: [Tool],
                hotkeys: HotkeyBindings, triggers: TriggerSettings,
                telemetry: TelemetrySettings, appBlocklist: [String],
                appearance: AppearanceMode = .auto) {
        self.schemaVersion = schemaVersion
        self.providers = providers
        self.tools = tools
        self.hotkeys = hotkeys
        self.triggers = triggers
        self.telemetry = telemetry
        self.appBlocklist = appBlocklist
        self.appearance = appearance
    }

    /// 自定义解码：`appearance` 使用 `decodeIfPresent` 保证向后兼容
    ///
    /// 旧版 config.json 中不含 appearance 字段，解码时默认回落到 `.auto`，
    /// 避免因缺字段导致 DecodingError。
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 必选字段 — 旧版 JSON 不允许缺失
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        providers = try container.decode([Provider].self, forKey: .providers)
        tools = try container.decode([Tool].self, forKey: .tools)
        hotkeys = try container.decode(HotkeyBindings.self, forKey: .hotkeys)
        triggers = try container.decode(TriggerSettings.self, forKey: .triggers)
        telemetry = try container.decode(TelemetrySettings.self, forKey: .telemetry)
        appBlocklist = try container.decode([String].self, forKey: .appBlocklist)
        // 可选字段 — 旧版 JSON 缺失时回落默认值 .auto
        appearance = try container.decodeIfPresent(AppearanceMode.self, forKey: .appearance) ?? .auto
    }

    /// 当前代码支持的 schema 版本号，写入新配置时使用
    public static let currentSchemaVersion = 1
}

/// 快捷键绑定
public struct HotkeyBindings: Sendable, Codable, Equatable {
    /// 切换命令面板的全局热键（如 "option+space"）
    public var toggleCommandPalette: String

    /// 构造快捷键绑定
    /// - Parameter toggleCommandPalette: 命令面板快捷键的字符串描述
    public init(toggleCommandPalette: String) {
        self.toggleCommandPalette = toggleCommandPalette
    }
}

/// 触发行为设置
public struct TriggerSettings: Sendable, Codable, Equatable {
    /// 是否启用划词后的浮动工具栏
    public var floatingToolbarEnabled: Bool
    /// 是否启用命令面板
    public var commandPaletteEnabled: Bool
    /// 小于此长度的选区不触发浮条
    public var minimumSelectionLength: Int
    /// mouseUp 后做 debounce 的毫秒数
    public var triggerDelayMs: Int
    /// 悬浮工具栏最多显示多少个位置（含溢出位的"更多"按钮）；超出此数会被折叠进"更多"菜单
    ///
    /// 取值下限 2 上限 20；旧版 config.json 缺失此字段时默认 6（满足常见工具数且不挤占屏幕）
    public var floatingToolbarMaxTools: Int
    /// 悬浮工具栏按钮尺寸档位：`.compact` 22pt、`.regular` 30pt
    ///
    /// 默认 `.compact`——更精致不占地；旧版 config.json 缺失此字段时也回落到 `.compact`
    public var floatingToolbarSize: ToolbarSize

    /// 构造触发行为设置
    /// - Parameters:
    ///   - floatingToolbarEnabled: 是否启用浮动工具栏
    ///   - commandPaletteEnabled: 是否启用命令面板
    ///   - minimumSelectionLength: 最小触发选区长度
    ///   - triggerDelayMs: mouseUp 后的 debounce 毫秒
    ///   - floatingToolbarMaxTools: 悬浮工具栏最多显示多少个工具位（含更多按钮），默认 6
    ///   - floatingToolbarSize: 悬浮工具栏尺寸档位，默认 .compact（22pt 按钮）
    public init(floatingToolbarEnabled: Bool, commandPaletteEnabled: Bool,
                minimumSelectionLength: Int, triggerDelayMs: Int,
                floatingToolbarMaxTools: Int = 6,
                floatingToolbarSize: ToolbarSize = .compact) {
        self.floatingToolbarEnabled = floatingToolbarEnabled
        self.commandPaletteEnabled = commandPaletteEnabled
        self.minimumSelectionLength = minimumSelectionLength
        self.triggerDelayMs = triggerDelayMs
        self.floatingToolbarMaxTools = floatingToolbarMaxTools
        self.floatingToolbarSize = floatingToolbarSize
    }

    /// JSON 字段名映射
    private enum CodingKeys: String, CodingKey {
        case floatingToolbarEnabled
        case commandPaletteEnabled
        case minimumSelectionLength
        case triggerDelayMs
        case floatingToolbarMaxTools
        case floatingToolbarSize
    }

    /// 自定义解码：新字段使用 decodeIfPresent 保证向后兼容
    ///
    /// 旧版 config.json 不含 floatingToolbarMaxTools / floatingToolbarSize 时，
    /// 分别回落到默认值 6 与 `.compact`，避免因缺字段抛 DecodingError
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        floatingToolbarEnabled = try container.decode(Bool.self, forKey: .floatingToolbarEnabled)
        commandPaletteEnabled = try container.decode(Bool.self, forKey: .commandPaletteEnabled)
        minimumSelectionLength = try container.decode(Int.self, forKey: .minimumSelectionLength)
        triggerDelayMs = try container.decode(Int.self, forKey: .triggerDelayMs)
        floatingToolbarMaxTools = try container
            .decodeIfPresent(Int.self, forKey: .floatingToolbarMaxTools) ?? 6
        floatingToolbarSize = try container
            .decodeIfPresent(ToolbarSize.self, forKey: .floatingToolbarSize) ?? .compact
    }
}

/// 悬浮工具栏尺寸档位
///
/// 对应 IconButton 的两档 size，放在 SliceCore 以便 Configuration 序列化；
/// UI 层（Windowing）消费时映射到实际像素值。
public enum ToolbarSize: String, Codable, CaseIterable, Sendable {
    /// 紧凑：22pt 按钮 + 3pt padding，适合精致小巧的 HUD 观感
    case compact
    /// 标准：30pt 按钮 + 4pt padding，按钮更大容易点击
    case regular
}

/// 遥测设置，MVP v0.1 只有开关
public struct TelemetrySettings: Sendable, Codable, Equatable {
    /// 是否启用匿名遥测
    public var enabled: Bool

    /// 构造遥测设置
    /// - Parameter enabled: 是否启用遥测
    public init(enabled: Bool) { self.enabled = enabled }
}
