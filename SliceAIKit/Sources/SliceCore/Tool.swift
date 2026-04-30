import Foundation

/// v2 工具定义，对应 `config-v2.json` 中的 tool 节点。
///
/// `Tool` 是 canonical v2 数据模型：三态 kind（prompt/agent/pipeline）+ provenance +
/// permissions + outputBinding + visibleWhen + budget + hotkey + tags。
///
/// **不**与旧配置 JSON 共享 Codable：旧 JSON 由 `LegacyConfigV1` 读取，v2 JSON 由 `Tool` 读写；
/// migrator 是唯一的旧配置 → v2 转换路径。
///
/// **没有**旧扁平 accessor（systemPrompt / userPrompt / providerId / modelId / temperature / variables）——
/// 访问 Tool 字段必须通过 `kind` 的 pattern matching 或 kind-aware 编辑器。
///
public struct Tool: Identifiable, Sendable, Codable, Equatable {
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

    /// 校验 Tool 的类型不变量
    ///
    /// **与 decoder 校验的关系**：decoder 对 JSON 输入做同样检查（`init(from:)`），但
    /// public `init(id:...)` 非 throws、允许代码侧临时构造非法对象（测试 fixture /
    /// 默认值 / migrator 输出）。`validate()` 是写入边界的守护——
    /// `ConfigurationStore.save()` 在落盘前对所有 tool 调用一次。
    ///
    /// 当前校验项（与 decoder 对齐）：
    /// 1. `outputBinding != nil && outputBinding.primary != displayMode` → throw
    ///    （单一事实源：同时存在两个可能冲突的字段时，ExecutionEngine 只会读其中一个）
    ///
    /// - Throws: `SliceError.configuration(.validationFailed(msg))`，msg 包含 tool id、两个字段名与冲突的值
    public func validate() throws {
        // outputBinding 存在时 primary 必须与 displayMode 一致
        if let ob = outputBinding, ob.primary != displayMode {
            throw SliceError.configuration(.validationFailed(
                "Tool '\(id)': outputBinding.primary (\(ob.primary.rawValue)) "
                + "must equal displayMode (\(displayMode.rawValue))"
            ))
        }
    }

    // MARK: - Codable（手写 init/encode；除了保持字段 round-trip，额外校验 displayMode / outputBinding.primary 一致性）
    //
    // P2b 修复：Tool 既有 displayMode（non-optional）又有 outputBinding.primary（同 enum，可 nil）。
    // 自动合成 Codable 会让 JSON 里声明 displayMode="window" + outputBinding.primary="replace" 的
    // Tool 通过解码，未来 ExecutionEngine 只能读其中一个，另一个默默被忽略 → 单一事实源违反。
    // 这里显式手写 Codable 加一致性校验；encode 也同步手写保证两端对称。
    //
    // **JSON shape contract**：只锁定**字段名**与自动合成一致（`test_tool_goldenJSON_promptKind_usesKindDiscriminator`
    // 已覆盖关键 key 名），**不**把 CodingKeys 声明顺序作为 API 契约——JSON 里 key 的实际顺序由
    // `JSONEncoder.outputFormatting`（当前配置含 `.sortedKeys`）决定，与 CodingKeys 枚举顺序无关。

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
                    "Tool.outputBinding.primary (\(primary)) must equal displayMode (\(display))"
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
