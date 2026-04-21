import SwiftUI

/// 语义化色板，统一从 DesignSystem 的 Assets.xcassets 加载
///
/// 所有 Color 走 Xcode Asset Catalog 的 "Any / Dark" 变体机制，SwiftUI 自动
/// 根据当前 `colorScheme` 切换。禁止在业务代码中硬编码 `Color(red:green:blue:)`，
/// 应一律通过 `SliceColor.xxx` 访问以便主题切换生效。
///
/// 使用示例：
/// ```swift
/// Text("Hello")
///     .foregroundColor(SliceColor.textPrimary)
///     .background(SliceColor.surface)
/// ```
public enum SliceColor {
    // MARK: 背景层

    /// 窗口底色（最底层）
    public static let background = Color("background", bundle: .module)
    /// 卡片 / 面板底色
    public static let surface = Color("surface", bundle: .module)
    /// 悬浮层 / HUD 底色（带透明度，通常叠加毛玻璃）
    public static let surfaceElevated = Color("surfaceElevated", bundle: .module)

    // MARK: 分隔与边框

    /// 0.5pt 细分隔线
    public static let divider = Color("divider", bundle: .module)
    /// 外框描边
    public static let border = Color("border", bundle: .module)

    // MARK: 文本层级

    /// 主文本
    public static let textPrimary = Color("textPrimary", bundle: .module)
    /// 次文本
    public static let textSecondary = Color("textSecondary", bundle: .module)
    /// 辅助 / 三级文本
    public static let textTertiary = Color("textTertiary", bundle: .module)
    /// 禁用文本
    public static let textDisabled = Color("textDisabled", bundle: .module)

    // MARK: 品牌强调

    /// 主强调色（紫）
    public static let accent = Color("accent", bundle: .module)
    /// 浅填充（hover / chip 底 / selected row 底）
    public static let accentFillLight = Color("accentFillLight", bundle: .module)
    /// 深填充（active / pressed / icon 底）
    public static let accentFillStrong = Color("accentFillStrong", bundle: .module)
    /// 紫色文字（link / active tab / 选中态 label）
    public static let accentText = Color("accentText", bundle: .module)

    // MARK: 状态色

    /// 错误
    public static let error = Color("error", bundle: .module)
    /// 错误填充（error block 底）
    public static let errorFill = Color("errorFill", bundle: .module)
    /// 错误边框
    public static let errorBorder = Color("errorBorder", bundle: .module)
    /// 成功
    public static let success = Color("success", bundle: .module)
    /// 警告
    public static let warning = Color("warning", bundle: .module)
    /// 警告填充
    public static let warningFill = Color("warningFill", bundle: .module)

    // MARK: 交互反馈

    /// 通用 hover 浅色
    public static let hoverFill = Color("hoverFill", bundle: .module)
    /// 通用按压深色
    public static let pressedFill = Color("pressedFill", bundle: .module)
}

#if DEBUG
#Preview("SliceColor palette · Light") {
    ColorGridPreview().preferredColorScheme(.light)
}

#Preview("SliceColor palette · Dark") {
    ColorGridPreview().preferredColorScheme(.dark)
}

private struct ColorGridPreview: View {
    var body: some View {
        ScrollView {
            LazyVGrid(columns: [.init(.adaptive(minimum: 140))], spacing: 8) {
                swatch("accent", SliceColor.accent)
                swatch("accentText", SliceColor.accentText)
                swatch("accentFillLight", SliceColor.accentFillLight)
                swatch("accentFillStrong", SliceColor.accentFillStrong)
                swatch("surface", SliceColor.surface)
                swatch("surfaceElevated", SliceColor.surfaceElevated)
                swatch("background", SliceColor.background)
                swatch("textPrimary", SliceColor.textPrimary)
                swatch("textSecondary", SliceColor.textSecondary)
                swatch("textTertiary", SliceColor.textTertiary)
                swatch("divider", SliceColor.divider)
                swatch("border", SliceColor.border)
                swatch("error", SliceColor.error)
                swatch("errorFill", SliceColor.errorFill)
                swatch("success", SliceColor.success)
                swatch("warning", SliceColor.warning)
                swatch("hoverFill", SliceColor.hoverFill)
                swatch("pressedFill", SliceColor.pressedFill)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
    }

    private func swatch(_ name: String, _ color: Color) -> some View {
        VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6).fill(color).frame(height: 40)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(SliceColor.border))
            Text(name).font(.caption).foregroundColor(SliceColor.textSecondary)
        }
    }
}
#endif
