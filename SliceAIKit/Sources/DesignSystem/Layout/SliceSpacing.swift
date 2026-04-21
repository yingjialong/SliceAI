import Foundation

/// 间距 token 枚举（对应 spec §3.3）
///
/// UI 代码禁止使用魔法数字，所有 padding / spacing 均通过此枚举引用。
public enum SliceSpacing {
    /// 2pt — 字距 / 微小间隙
    public static let xs: CGFloat       = 2
    /// 4pt — icon 内边距
    public static let sm: CGFloat       = 4
    /// 6pt — row 内部间隙
    public static let md: CGFloat       = 6
    /// 8pt — 基础间距
    public static let base: CGFloat     = 8
    /// 10pt — padding 常用档
    public static let lg: CGFloat       = 10
    /// 12pt — card 内边距 / row padding
    public static let xl: CGFloat       = 12
    /// 16pt — panel body padding
    public static let xxl: CGFloat      = 16
    /// 20pt — section 间距
    public static let section: CGFloat  = 20
    /// 24pt — group 间距
    public static let group: CGFloat    = 24
    /// 32pt — page padding
    public static let page: CGFloat     = 32
}
