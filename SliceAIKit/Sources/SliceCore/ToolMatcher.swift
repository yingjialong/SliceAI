import Foundation

/// Tool 可见性过滤器；UI 在渲染浮条 / 面板前按此过滤
///
/// 所有字段均可 nil（表示"不设约束"）。多字段同时存在时取 AND：
/// 比如 `appAllowlist + languageAllowlist` 要同时满足才显示。
public struct ToolMatcher: Sendable, Codable, Equatable {
    /// 只在这些 bundleId 下显示；nil 表示所有
    public let appAllowlist: [String]?
    /// 排除这些 bundleId；nil 表示无排除
    public let appDenylist: [String]?
    /// 只对这些内容类型显示；nil 表示所有
    public let contentTypes: [SelectionContentType]?
    /// 只对这些语言显示（BCP-47）；nil 表示所有
    public let languageAllowlist: [String]?
    /// 选区最小长度；nil 表示不限
    public let minLength: Int?
    /// 选区最大长度；nil 表示不限
    public let maxLength: Int?
    /// 正则匹配选区；nil 表示不做正则过滤
    public let regex: String?

    /// 构造 ToolMatcher
    public init(
        appAllowlist: [String]?,
        appDenylist: [String]?,
        contentTypes: [SelectionContentType]?,
        languageAllowlist: [String]?,
        minLength: Int?,
        maxLength: Int?,
        regex: String?
    ) {
        self.appAllowlist = appAllowlist
        self.appDenylist = appDenylist
        self.contentTypes = contentTypes
        self.languageAllowlist = languageAllowlist
        self.minLength = minLength
        self.maxLength = maxLength
        self.regex = regex
    }
}
