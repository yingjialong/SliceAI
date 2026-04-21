import AppKit
import Observation
import SliceCore
import SwiftUI

/// 主题管理器（Swift Observation 驱动）
///
/// 职责：
/// - 持有当前 `AppearanceMode`（auto / light / dark）
/// - 解析出 SwiftUI 层的 `ColorScheme` 与 AppKit 层的 `NSAppearance`
/// - 通过 `onModeChange` 回调通知外部（通常为 ConfigurationStore）持久化
///
/// 线程模型：`@MainActor` 限定。由 AppContainer 构造后注入到根视图的 environment。
/// 使用方式：
/// ```swift
/// // AppContainer 构造
/// let themeManager = ThemeManager(initialMode: config.appearance)
/// themeManager.onModeChange = { configStore.updateAppearance($0) }
///
/// // 根视图注入
/// ContentView().environment(themeManager)
///
/// // 消费
/// @Environment(ThemeManager.self) private var theme
/// ```
@MainActor
@Observable
public final class ThemeManager {

    /// 当前主题模式（写入时触发 @Observable 重绘，并通知外部回调）
    public var mode: AppearanceMode {
        didSet {
            // 仅在值真正变化时触发回调，避免冗余通知
            guard oldValue != mode else { return }
            onModeChange?(mode)
        }
    }

    /// 当 mode 改变时的回调（通常让 ConfigurationStore 持久化）
    /// 约束为 `@MainActor` 确保回调在主线程执行
    public var onModeChange: (@MainActor (AppearanceMode) -> Void)?

    /// 构造 ThemeManager
    /// - Parameter initialMode: 初始模式，通常从 Configuration.appearance 加载，默认 `.auto`
    public init(initialMode: AppearanceMode = .auto) {
        self.mode = initialMode
    }

    /// 显式切换模式；等价于直接赋值 `mode = newMode`，但语义更清晰
    /// - Parameter newMode: 新主题模式
    public func setMode(_ newMode: AppearanceMode) {
        self.mode = newMode
    }

    /// 解析出 SwiftUI `ColorScheme`。
    ///
    /// `.auto` 时返回 `.light`（作为占位默认值），实际渲染由
    /// `.preferredColorScheme(nil)` 跟随系统决定；
    /// 上层使用时只有在非 `.auto` 模式下才传入此值覆盖系统外观。
    public var resolvedColorScheme: ColorScheme {
        switch mode {
        case .light: return .light
        case .dark:  return .dark
        case .auto:  return .light
        }
    }

    /// 对应的 NSAppearance（用于绑定 NSWindow.appearance）。
    ///
    /// 委托给 `AppearanceMode` 在 DesignSystem 中的 UI 扩展计算，
    /// 统一映射逻辑，避免重复实现。
    public var nsAppearance: NSAppearance? { mode.nsAppearance }

    /// 将当前主题应用到指定 NSWindow。
    ///
    /// `.auto` 时清空 `appearance`，让 window 跟随系统；
    /// 其他模式时显式设置对应的 `NSAppearance`。
    /// - Parameter window: 目标 NSWindow
    public func apply(to window: NSWindow) {
        window.appearance = nsAppearance
    }
}
