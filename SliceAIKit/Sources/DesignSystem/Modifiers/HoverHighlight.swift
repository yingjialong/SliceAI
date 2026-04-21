import SwiftUI

/// Hover 时叠加浅填充背景的 modifier
///
/// 用于图标按钮、列表项等希望鼠标悬停时有轻微视觉反馈的场景。
/// 默认使用 `SliceColor.hoverFill`；传入自定义 fill 以实现强调色（如 accent 悬停）。
///
/// 使用示例：
/// ```swift
/// Image(systemName: "gear")
///     .padding(6)
///     .hoverHighlight()
/// ```
public struct HoverHighlight: ViewModifier {
    // MARK: 属性

    /// 悬停时的填充颜色
    let fill: Color
    /// 高亮背景的圆角半径
    let cornerRadius: CGFloat
    /// 当前鼠标是否悬停在视图上
    @State private var isHovered = false

    // MARK: Body

    public func body(content: Content) -> some View {
        content
            .background(
                // 仅在 isHovered 为 true 时显示填充，避免无状态下额外绘制
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(isHovered ? fill : .clear)
            )
            .onHover { hovering in
                // 使用 SliceAnimation.quick (120ms easeOut) 产生流畅的悬停过渡
                withAnimation(SliceAnimation.quick) { isHovered = hovering }
            }
    }
}

public extension View {
    /// 附加 hover 高亮
    ///
    /// - Parameters:
    ///   - fill: 悬停填充色，默认 `SliceColor.hoverFill`
    ///   - cornerRadius: 圆角，默认 `SliceRadius.button`（5pt）
    func hoverHighlight(
        fill: Color = SliceColor.hoverFill,
        cornerRadius: CGFloat = SliceRadius.button
    ) -> some View {
        modifier(HoverHighlight(fill: fill, cornerRadius: cornerRadius))
    }
}
