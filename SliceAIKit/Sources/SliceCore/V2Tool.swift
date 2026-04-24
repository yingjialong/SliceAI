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

    // MARK: - Codable（手写 init/encode；除了保持字段 round-trip，额外校验 displayMode / outputBinding.primary 一致性）
    //
    // P2b 修复：V2Tool 既有 displayMode（non-optional）又有 outputBinding.primary（同 enum，可 nil）。
    // 自动合成 Codable 会让 JSON 里声明 displayMode="window" + outputBinding.primary="replace" 的
    // Tool 通过解码，未来 ExecutionEngine 只能读其中一个，另一个默默被忽略 → 单一事实源违反。
    // 这里显式手写 Codable 加一致性校验；encode 也同步手写保证两端对称（字段名、顺序和自动合成保持一致）。

    private enum CodingKeys: String, CodingKey {
        case id, name, icon, description, kind, visibleWhen, displayMode, outputBinding,
             permissions, provenance, budget, hotkey, labelStyle, tags
    }

    /// 手写解码器，负责字段读入 + displayMode/outputBinding.primary 一致性校验
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decode(String.self, forKey: .name)
        self.icon = try c.decode(String.self, forKey: .icon)
        self.description = try c.decodeIfPresent(String.self, forKey: .description)
        self.kind = try c.decode(ToolKind.self, forKey: .kind)
        self.visibleWhen = try c.decodeIfPresent(ToolMatcher.self, forKey: .visibleWhen)
        self.displayMode = try c.decode(PresentationMode.self, forKey: .displayMode)
        self.outputBinding = try c.decodeIfPresent(OutputBinding.self, forKey: .outputBinding)
        self.permissions = try c.decode([Permission].self, forKey: .permissions)
        self.provenance = try c.decode(Provenance.self, forKey: .provenance)
        self.budget = try c.decodeIfPresent(ToolBudget.self, forKey: .budget)
        self.hotkey = try c.decodeIfPresent(String.self, forKey: .hotkey)
        self.labelStyle = try c.decode(ToolLabelStyle.self, forKey: .labelStyle)
        self.tags = try c.decode([String].self, forKey: .tags)

        // 单一事实源：outputBinding 存在时，其 primary 必须与 displayMode 一致
        if let ob = self.outputBinding, ob.primary != self.displayMode {
            let primary = ob.primary.rawValue
            let display = self.displayMode.rawValue
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription:
                    "V2Tool.outputBinding.primary (\(primary)) must equal displayMode (\(display))"
            ))
        }
    }

    /// 手写编码器；输出字段名与自动合成保持一致（单元测试里的 golden JSON 已锁定 shape）
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(self.id, forKey: .id)
        try c.encode(self.name, forKey: .name)
        try c.encode(self.icon, forKey: .icon)
        try c.encodeIfPresent(self.description, forKey: .description)
        try c.encode(self.kind, forKey: .kind)
        try c.encodeIfPresent(self.visibleWhen, forKey: .visibleWhen)
        try c.encode(self.displayMode, forKey: .displayMode)
        try c.encodeIfPresent(self.outputBinding, forKey: .outputBinding)
        try c.encode(self.permissions, forKey: .permissions)
        try c.encode(self.provenance, forKey: .provenance)
        try c.encodeIfPresent(self.budget, forKey: .budget)
        try c.encodeIfPresent(self.hotkey, forKey: .hotkey)
        try c.encode(self.labelStyle, forKey: .labelStyle)
        try c.encode(self.tags, forKey: .tags)
    }
}
