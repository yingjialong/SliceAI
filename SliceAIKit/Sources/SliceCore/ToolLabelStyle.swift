import Foundation

/// 浮条（FloatingToolbar）上单个工具的显示样式。
///
/// UI 层在渲染工具按钮时读取此字段决定绘制图标、名称或二者组合。
/// 仅影响浮条外观，不影响命令面板（命令面板本就是图标 + 名称列表）或执行逻辑。
public enum ToolLabelStyle: String, Sendable, Codable, CaseIterable {
    /// 只显示图标（emoji / SF Symbol）——MVP 默认风格，最紧凑
    case icon
    /// 只显示工具名称的短缩写（最多 4 个中文字或首个英文单词）
    case name
    /// 图标 + 短缩写并排显示
    case iconAndName
}
