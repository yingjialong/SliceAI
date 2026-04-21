import AppKit
import SliceCore

/// AppearanceMode 的 UI 侧扩展
///
/// 将展示名称与 NSAppearance 映射集中在 DesignSystem，避免 SliceCore 携带 UI 依赖。
/// SliceCore 中的 AppearanceMode 是纯数据模型，此扩展仅用于 UI 层渲染。
public extension AppearanceMode {

    /// 用户可见的中文名称，用于设置界面 Picker 展示
    var displayName: String {
        switch self {
        case .auto:  return "跟随系统"
        case .light: return "浅色"
        case .dark:  return "深色"
        }
    }

    /// 对应的显式 NSAppearance
    ///
    /// - `.auto` 返回 `nil`，让 NSWindow.appearance = nil 跟随系统；
    /// - `.light` 返回 `.aqua`；
    /// - `.dark` 返回 `.darkAqua`。
    var nsAppearance: NSAppearance? {
        switch self {
        case .light: return NSAppearance(named: .aqua)
        case .dark:  return NSAppearance(named: .darkAqua)
        case .auto:  return nil
        }
    }
}
