import Foundation

/// 应用主题模式：跟随系统 / 强制亮色 / 强制暗色
///
/// 纯数据模型，放在 SliceCore 便于 Configuration 序列化。UI 语义（displayName 中文 /
/// nsAppearance）放在 DesignSystem 的扩展中，避免 SliceCore 带 UI 依赖。
///
/// - 默认值 `.auto` 保证首次启动零配置仍符合用户预期（跟随系统）。
/// - 实现 `Codable` 以便 Configuration 直接 JSON 序列化为字符串枚举。
/// - 实现 `CaseIterable` 便于 UI 枚举所有选项。
public enum AppearanceMode: String, Codable, CaseIterable, Sendable {
    /// 跟随系统外观
    case auto
    /// 强制浅色模式
    case light
    /// 强制深色模式
    case dark
}
