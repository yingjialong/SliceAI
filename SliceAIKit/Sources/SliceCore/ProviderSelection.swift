import Foundation

/// Provider 选择策略；Tool 的 `kind.*.provider` 字段
///
/// 从 v1 的 `providerId: String` 升级：三种模式中 `.fixed` 与 v1 行为等价；
/// `.capability` 让工具声明"我需要什么能力"，运行时按 `Configuration.providers` 匹配；
/// `.cascade` 实现"长文用 Haiku，代码用 Sonnet"之类的条件路由。
public enum ProviderSelection: Sendable, Equatable, Codable {
    case fixed(providerId: String, modelId: String?)
    case capability(requires: Set<ProviderCapability>, prefer: [String])
    case cascade(rules: [CascadeRule])

    // MARK: - 手写 Codable（模板 A + B；Set<ProviderCapability> 先转 Array 排序以稳定 JSON）

    private enum CodingKeys: String, CodingKey { case fixed, capability, cascade }
    private struct FixedRepr: Codable, Equatable { let providerId: String; let modelId: String? }
    private struct CapabilityRepr: Codable, Equatable {
        let requires: [ProviderCapability]  // 编码前会 sort；解码后用 Set 恢复语义
        let prefer: [String]
    }

    /// 解码 ProviderSelection；采用单键 canonical contract，允许未来安全地新增 case
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 单键 canonical contract（Task 3/8/10 同款纪律）
        guard c.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "ProviderSelection requires exactly one key, got \(c.allKeys.count)"
            ))
        }
        // 按 case 顺序尝试匹配：fixed / capability / cascade
        if let r = try c.decodeIfPresent(FixedRepr.self, forKey: .fixed) {
            self = .fixed(providerId: r.providerId, modelId: r.modelId); return
        }
        if let r = try c.decodeIfPresent(CapabilityRepr.self, forKey: .capability) {
            self = .capability(requires: Set(r.requires), prefer: r.prefer); return
        }
        if let rules = try c.decodeIfPresent([CascadeRule].self, forKey: .cascade) {
            self = .cascade(rules: rules); return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: c.codingPath,
            debugDescription: "ProviderSelection encountered unknown case key"
        ))
    }

    /// 编码 ProviderSelection；`.capability` 将 Set 按 rawValue 排序后编码为 Array，保证 JSON 可 diff
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .fixed(let p, let m):
            try c.encode(FixedRepr(providerId: p, modelId: m), forKey: .fixed)
        case .capability(let req, let prefer):
            // Set 编码顺序不稳定 → 转 Array 并按 rawValue 排序，保证 JSON 可 diff
            let sortedReq = req.sorted { $0.rawValue < $1.rawValue }
            try c.encode(CapabilityRepr(requires: sortedReq, prefer: prefer), forKey: .capability)
        case .cascade(let rules):
            try c.encode(rules, forKey: .cascade)
        }
    }
}

/// Provider 能力声明；`Provider.capabilities` 与 `ProviderSelection.capability.requires` 共用
public enum ProviderCapability: String, Sendable, Codable, CaseIterable {
    /// Anthropic / DeepSeek 的 prompt caching
    case promptCaching
    /// Function / tool calling
    case toolCalling
    /// 多模态视觉输入
    case vision
    /// Claude Extended Thinking
    case extendedThinking
    /// Gemini grounding / Google Search
    case grounding
    /// 强 JSON Schema 输出（非 prompt-hinted）
    case jsonSchemaOutput
    /// 长上下文（≥ 200k tokens）
    case longContext
}

/// 级联规则：条件命中则用指定 provider + model
public struct CascadeRule: Sendable, Equatable, Codable {
    /// 命中条件
    public let when: ConditionExpr
    /// 命中时使用的 provider id
    public let providerId: String
    /// 可选 modelId（nil 回落 provider.defaultModel）
    public let modelId: String?

    /// 构造 CascadeRule
    public init(when: ConditionExpr, providerId: String, modelId: String?) {
        self.when = when
        self.providerId = providerId
        self.modelId = modelId
    }
}

/// 简单条件表达式（刻意不做 DSL，枚举有限几种）
///
/// M1 定义枚举；M2+ 的 ProviderResolver 按 case 分派判定逻辑。
public enum ConditionExpr: Sendable, Equatable, Codable {
    case always
    case selectionLengthGreaterThan(Int)
    case isCode
    case languageEquals(String)
    case appBundleIdEquals(String)

    // MARK: - 手写 Codable（模板 A + C；含 Task 3/8/10 统一的单键 guard + 明确未知键 throw）

    private enum CodingKeys: String, CodingKey {
        case always, selectionLengthGreaterThan, isCode, languageEquals, appBundleIdEquals
    }
    private struct EmptyMarker: Codable, Equatable {}

    /// 解码 ConditionExpr；单键 canonical contract
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "ConditionExpr requires exactly one key, got \(c.allKeys.count)"
            ))
        }
        // 按 case 顺序尝试匹配：always / selectionLengthGreaterThan / isCode / languageEquals / appBundleIdEquals
        if c.contains(.always) {
            _ = try c.decode(EmptyMarker.self, forKey: .always); self = .always; return
        }
        if let n = try c.decodeIfPresent(Int.self, forKey: .selectionLengthGreaterThan) {
            self = .selectionLengthGreaterThan(n); return
        }
        if c.contains(.isCode) {
            _ = try c.decode(EmptyMarker.self, forKey: .isCode); self = .isCode; return
        }
        if let s = try c.decodeIfPresent(String.self, forKey: .languageEquals) {
            self = .languageEquals(s); return
        }
        if let s = try c.decodeIfPresent(String.self, forKey: .appBundleIdEquals) {
            self = .appBundleIdEquals(s); return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: c.codingPath,
            debugDescription: "ConditionExpr encountered unknown case key"
        ))
    }

    /// 编码 ConditionExpr；无 payload case 用 EmptyMarker 写成 `{}`
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .always:
            try c.encode(EmptyMarker(), forKey: .always)
        case .selectionLengthGreaterThan(let n):
            try c.encode(n, forKey: .selectionLengthGreaterThan)
        case .isCode:
            try c.encode(EmptyMarker(), forKey: .isCode)
        case .languageEquals(let s):
            try c.encode(s, forKey: .languageEquals)
        case .appBundleIdEquals(let s):
            try c.encode(s, forKey: .appBundleIdEquals)
        }
    }
}
