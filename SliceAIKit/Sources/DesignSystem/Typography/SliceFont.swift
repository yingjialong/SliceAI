import SwiftUI

/// 语义化字体预设
///
/// 所有字号 / weight / design 均已烘焙，UI 代码只需 `.font(SliceFont.body)` 引用。
/// kerning 通过 `SliceKerning` 独立配合，因为 SwiftUI `.kerning()` 是 View modifier
/// 而非 Font 属性。
public enum SliceFont {
    /// 22pt bold — Onboarding 主标题
    public static let displayLarge    = Font.system(size: 22, weight: .bold)
    /// 17pt bold — 设置页标题
    public static let title           = Font.system(size: 17, weight: .bold)
    /// 15pt semibold — 命令面板搜索框
    public static let headline        = Font.system(size: 15, weight: .semibold)
    /// 13.5pt regular — 正文
    public static let body            = Font.system(size: 13.5, weight: .regular)
    /// 13.5pt semibold — 正文加粗
    public static let bodyEmphasis    = Font.system(size: 13.5, weight: .semibold)
    /// 13pt regular — 设置项 label
    public static let subheadline     = Font.system(size: 13, weight: .regular)
    /// 12.5pt regular — 描述 / 详情
    public static let callout         = Font.system(size: 12.5, weight: .regular)
    /// 11.5pt regular — 辅助文本
    public static let caption         = Font.system(size: 11.5, weight: .regular)
    /// 11pt semibold — 小 section 标题
    public static let captionEmphasis = Font.system(size: 11, weight: .semibold)
    /// 10.5pt semibold — uppercase section label（字距需配 SliceKerning.wide）
    public static let overline        = Font.system(size: 10.5, weight: .semibold)
    /// 10pt regular — 键盘提示
    public static let micro           = Font.system(size: 10, weight: .regular)
    /// 12pt monospaced — 代码 / 详情
    public static let mono            = Font.system(size: 12, design: .monospaced)
    /// 11.5pt monospaced — error 详情
    public static let monoSmall       = Font.system(size: 11.5, design: .monospaced)
}

/// 字距预设（配合 .kerning(_:) 使用）
///
/// SwiftUI `.kerning(_:)` 接收点值（point），按当前字号自动换算。文中 "em" 参考值来自
/// 设计 spec，实际代码用 point 近似（例如 13.5pt × -0.005em ≈ -0.07pt）。
public enum SliceKerning {
    /// 大标题收紧 -0.02em
    public static let tight: CGFloat   = -0.4
    /// 标题收紧 -0.01em
    public static let snug: CGFloat    = -0.2
    /// 正文微收 -0.005em
    public static let normal: CGFloat  = -0.07
    /// uppercase label 外扩 0.08em
    public static let wide: CGFloat    = 0.8
}

/// 行距预设（配合 .lineSpacing(_:) 使用，SwiftUI 不支持 lineHeight 倍数）
public enum SliceLineSpacing {
    /// 正文段落内行距（对应 spec 目标 line-height 1.62 ≈ body 13.5 × 0.62 ≈ 8.37，实测 5.5 视觉最贴）
    public static let body: CGFloat     = 5.5
    /// 代码块行距
    public static let code: CGFloat     = 4
    /// 标题行距
    public static let heading: CGFloat  = 2
}
