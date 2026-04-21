import AppKit
import SwiftUI

public extension View {
    /// 应用毛玻璃背景
    ///
    /// 内部使用 `VisualEffectView` 封装 `NSVisualEffectView`，比 SwiftUI 原生
    /// `.regularMaterial` 提供更精细的材质控制（hudWindow / sidebar / popover / windowBackground）。
    ///
    /// 使用示例：
    /// ```swift
    /// RoundedRectangle(cornerRadius: 12)
    ///     .glassBackground(.hud, cornerRadius: 12)
    /// ```
    ///
    /// - Parameters:
    ///   - material: 语义材质（hud / sidebar / popover / window）
    ///   - cornerRadius: 圆角，默认 0（大多数场景由外层 clip 决定圆角）
    /// - Returns: 背景叠加毛玻璃效果的 View
    func glassBackground(_ material: SliceMaterial, cornerRadius: CGFloat = 0) -> some View {
        background(
            // 将 VisualEffectView 裁切为圆角矩形，防止毛玻璃超出边界
            VisualEffectView(material: material.nsMaterial)
                .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        )
    }
}
