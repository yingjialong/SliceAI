import SwiftUI

/// 阴影预设（对应 spec §3.5）
///
/// 使用方式：
/// ```swift
/// someView
///     .shadow(SliceShadow.panel)
///     .shadow(SliceShadow.panelContact)
/// ```
/// 调用两次 `.shadow(...)` 叠加主阴影 + 接触阴影。
public struct SliceShadowStyle: Sendable {
    /// 阴影色
    public let color: Color
    /// 模糊半径
    public let radius: CGFloat
    /// 水平偏移
    public let x: CGFloat
    /// 垂直偏移
    public let y: CGFloat
}

public enum SliceShadow {
    /// 按钮按压态 / 微阴影
    public static let subtle        = SliceShadowStyle(color: .black.opacity(0.08), radius: 2, x: 0, y: 1)
    /// 结果面板主阴影
    public static let panel         = SliceShadowStyle(color: .black.opacity(0.22), radius: 24, x: 0, y: 20)
    /// 结果面板接触阴影
    public static let panelContact  = SliceShadowStyle(color: .black.opacity(0.10), radius: 4, x: 0, y: 2)
    /// 悬浮工具栏主阴影
    public static let hud           = SliceShadowStyle(color: .black.opacity(0.18), radius: 24, x: 0, y: 8)
    /// 悬浮工具栏接触阴影
    public static let hudContact    = SliceShadowStyle(color: .black.opacity(0.08), radius: 2, x: 0, y: 2)
}

/// 便利的 View 扩展，让阴影应用语法更紧凑
public extension View {
    /// 应用预设阴影样式
    func shadow(_ style: SliceShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}
