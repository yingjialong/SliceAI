import Foundation

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
    /// 悬浮工具栏最多显示多少个位置（含溢出位的"更多"按钮）
    public var floatingToolbarMaxTools: Int
    /// 悬浮工具栏按钮尺寸档位
    public var floatingToolbarSize: ToolbarSize
    /// 悬浮工具栏自动消失倒计时，以秒为单位；`0` 表示永不自动消失
    public var floatingToolbarAutoDismissSeconds: Int

    /// 构造触发行为设置
    /// - Parameters:
    ///   - floatingToolbarEnabled: 是否启用浮动工具栏
    ///   - commandPaletteEnabled: 是否启用命令面板
    ///   - minimumSelectionLength: 最小触发选区长度
    ///   - triggerDelayMs: mouseUp 后的 debounce 毫秒
    ///   - floatingToolbarMaxTools: 悬浮工具栏最多显示多少个工具位，默认 6
    ///   - floatingToolbarSize: 悬浮工具栏尺寸档位，默认 `.compact`
    ///   - floatingToolbarAutoDismissSeconds: 浮条自动消失秒数，默认 5；`0` 表示永不自动消失
    public init(
        floatingToolbarEnabled: Bool,
        commandPaletteEnabled: Bool,
        minimumSelectionLength: Int,
        triggerDelayMs: Int,
        floatingToolbarMaxTools: Int = 6,
        floatingToolbarSize: ToolbarSize = .compact,
        floatingToolbarAutoDismissSeconds: Int = 5
    ) {
        self.floatingToolbarEnabled = floatingToolbarEnabled
        self.commandPaletteEnabled = commandPaletteEnabled
        self.minimumSelectionLength = minimumSelectionLength
        self.triggerDelayMs = triggerDelayMs
        self.floatingToolbarMaxTools = floatingToolbarMaxTools
        self.floatingToolbarSize = floatingToolbarSize
        self.floatingToolbarAutoDismissSeconds = floatingToolbarAutoDismissSeconds
    }

    /// JSON 字段名映射
    private enum CodingKeys: String, CodingKey {
        case floatingToolbarEnabled
        case commandPaletteEnabled
        case minimumSelectionLength
        case triggerDelayMs
        case floatingToolbarMaxTools
        case floatingToolbarSize
        case floatingToolbarAutoDismissSeconds
    }

    /// 自定义解码：新字段使用 decodeIfPresent 保证向后兼容
    ///
    /// 旧版 config.json 不含 floatingToolbarMaxTools / floatingToolbarSize /
    /// floatingToolbarAutoDismissSeconds 时，分别回落到默认值 6 / `.compact` / 5。
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
        floatingToolbarAutoDismissSeconds = try container
            .decodeIfPresent(Int.self, forKey: .floatingToolbarAutoDismissSeconds) ?? 5
    }
}

/// 悬浮工具栏尺寸档位
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
    public init(enabled: Bool) {
        self.enabled = enabled
    }
}
