import Foundation

/// v2 工具定义（独立新类型；现有 `Tool` 保持 v1 形状不变）
///
/// `V2Tool` 是 canonical v2 数据模型：三态 kind（prompt/agent/pipeline）+ provenance +
/// permissions + outputBinding + visibleWhen + budget + hotkey + tags。
///
/// **不**与 v1 `Tool` 共享 Codable：v1 JSON 由旧 `Tool` 读写、v2 JSON 由 `V2Tool` 读写；
/// migrator 是唯一的 v1 → v2 转换路径。
///
/// **没有** v1 兼容 accessor（systemPrompt / userPrompt / providerId / modelId / temperature / variables）——
/// ToolEditorView / ToolExecutor 继续消费现有 `Tool` 类型；访问 V2Tool 字段必须通过 `kind` 的
/// pattern matching 或专用 kind-aware 编辑器（M3+ 引入）。
///
/// M3 的 rename pass 会：
/// 1. 删除现有 `Tool.swift`
/// 2. 把本文件重命名为 `Tool.swift`、类型改名为 `Tool`
/// 3. 同步改 ToolExecutor / ToolEditorView / DefaultConfiguration 等所有引用
public struct V2Tool: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var name: String
    public var icon: String
    public var description: String?
    public var kind: ToolKind
    public var visibleWhen: ToolMatcher?
    public var displayMode: PresentationMode
    public var outputBinding: OutputBinding?
    public var permissions: [Permission]
    public var provenance: Provenance
    public var budget: ToolBudget?
    public var hotkey: String?
    public var labelStyle: ToolLabelStyle
    public var tags: [String]

    /// v2 主初始化器
    public init(
        id: String,
        name: String,
        icon: String,
        description: String?,
        kind: ToolKind,
        visibleWhen: ToolMatcher?,
        displayMode: PresentationMode,
        outputBinding: OutputBinding?,
        permissions: [Permission],
        provenance: Provenance,
        budget: ToolBudget?,
        hotkey: String?,
        labelStyle: ToolLabelStyle,
        tags: [String]
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.kind = kind
        self.visibleWhen = visibleWhen
        self.displayMode = displayMode
        self.outputBinding = outputBinding
        self.permissions = permissions
        self.provenance = provenance
        self.budget = budget
        self.hotkey = hotkey
        self.labelStyle = labelStyle
        self.tags = tags
    }

    // Codable 自动合成；Task 14 的 ToolKind 提供手写 Codable 保证 `{"kind":{"prompt":{...}}}` 稳定 shape（无 _0）
}
