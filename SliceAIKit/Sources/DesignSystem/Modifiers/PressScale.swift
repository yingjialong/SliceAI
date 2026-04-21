import SwiftUI

/// 按下时缩小到指定比例的 ButtonStyle（物理按压感）
///
/// 通过 `ButtonStyle` 协议拿到 `configuration.isPressed`，避免自行管理手势状态，
/// 与 SwiftUI 的 Button 按压系统完全同步。
///
/// 使用方式一（推荐，直接套 ButtonStyle）：
/// ```swift
/// Button("确认") { ... }
///     .buttonStyle(PressScaleButtonStyle())
/// ```
///
/// 使用方式二（通过便利扩展）：
/// ```swift
/// Button("确认") { ... }
///     .pressScale()
/// ```
public struct PressScaleButtonStyle: ButtonStyle {
    // MARK: 属性

    /// 按下时的缩放比例，默认 0.94（缩小到 94%）
    public let scale: CGFloat

    // MARK: 初始化

    /// 创建按压缩放 ButtonStyle
    /// - Parameter scale: 按下时的缩放比例（0.94 表示缩小到 94%）
    public init(scale: CGFloat = 0.94) {
        self.scale = scale
    }

    // MARK: Body

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            // 按下时缩放到 scale，松开恢复 1.0
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            // SliceAnimation.press (80ms easeOut) 保证按压动画快速响应
            .animation(SliceAnimation.press, value: configuration.isPressed)
    }
}

public extension View {
    /// 附加按压缩放的 Button style
    ///
    /// 注意：此扩展通过 `.buttonStyle()` 修改 Button 行为，只对直接子 Button 有效；
    /// 嵌套 Button 需各自独立调用。
    ///
    /// - Parameter scale: 按下时的缩放比例，默认 0.94
    func pressScale(_ scale: CGFloat = 0.94) -> some View {
        buttonStyle(PressScaleButtonStyle(scale: scale))
    }
}
