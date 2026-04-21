import Foundation

/// 应用主题模式：跟随系统 / 强制亮色 / 强制暗色
///
/// 持久化到 Configuration.appearance 字段（JSON 中为 string enum）。
/// 默认值 `.auto` 保证首次启动零配置仍符合用户预期（跟随系统）。
public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    /// 跟随系统
    case auto
    /// 强制亮色
    case light
    /// 强制暗色
    case dark

    /// 用户可见的中文名称
    public var displayName: String {
        switch self {
        case .auto:  return "跟随系统"
        case .light: return "浅色"
        case .dark:  return "深色"
        }
    }
}
