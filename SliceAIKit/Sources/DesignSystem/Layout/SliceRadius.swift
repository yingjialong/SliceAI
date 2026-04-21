import Foundation

/// 圆角 token 枚举（对应 spec §3.4）
///
/// 全局只有 6 档，UI 代码必须从此枚举取值；不允许出现 8 / 10 / 12 等散落数字。
public enum SliceRadius {
    /// 4pt — kbd / chip 小标签
    public static let tight: CGFloat    = 4
    /// 5pt — 图标按钮 / pill 按钮
    public static let button: CGFloat   = 5
    /// 6pt — 输入框 / 选择器 / 代码块
    public static let control: CGFloat  = 6
    /// 8pt — 面板 / 卡片 / 工具栏外框
    public static let card: CGFloat     = 8
    /// 10pt — 命令面板 / 设置窗口
    public static let sheet: CGFloat    = 10
    /// 22pt — Onboarding Hero 图标
    public static let hero: CGFloat     = 22
}
