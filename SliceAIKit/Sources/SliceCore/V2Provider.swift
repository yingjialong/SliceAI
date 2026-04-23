import Foundation

/// v2 LLM 供应商配置（独立新类型；现有 `Provider` 保持 v1 形状不变）
///
/// 相对 v1 `Provider` 的变化：
/// - 新增 `kind: ProviderKind`：声明协议族
/// - 新增 `capabilities: [ProviderCapability]`：声明支持的高级能力（Set 语义 + 稳定顺序；见评审 P2-3）
/// - `baseURL: URL?`：`.anthropic` / `.gemini` 协议族可 nil
///
/// **评审修正（Codex 第六轮 P2-3）**：初版 `capabilities: Set<ProviderCapability>` 在 JSON 序列化中
/// 顺序不稳定（`JSONEncoder.outputFormatting = [.sortedKeys]` 只排字典 key，不排数组元素）。
/// 本版改为 `[ProviderCapability]`：`init` 中自动去重（保留首次出现顺序）并按 rawValue 排序，
/// 保证 round-trip 稳定；Set 语义由 init 保证，调用方读到的数组已有序无重复。
///
/// M3 rename pass：删除 Provider.swift，把本文件重命名为 Provider.swift、类型改名为 Provider。
public struct V2Provider: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var kind: ProviderKind
    public var name: String
    public var baseURL: URL?
    public var apiKeyRef: String
    public var defaultModel: String
    public var capabilities: [ProviderCapability]  // **[…] 而非 Set<…>**（P2-3）

    /// 构造 V2Provider
    /// - Note: `capabilities` 传入 Set 或 Array 都可；内部去重 + 按 rawValue 排序，保证 JSON 稳定
    public init(
        id: String,
        kind: ProviderKind,
        name: String,
        baseURL: URL?,
        apiKeyRef: String,
        defaultModel: String,
        capabilities: some Sequence<ProviderCapability>
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.baseURL = baseURL
        self.apiKeyRef = apiKeyRef
        self.defaultModel = defaultModel
        // 去重 + 按 rawValue 排序，保证 JSON 稳定（评审 P2-3）
        self.capabilities = Array(Set(capabilities)).sorted { $0.rawValue < $1.rawValue }
    }

    /// apiKeyRef 前缀，与 v1 保持一致
    public static let keychainRefPrefix = "keychain:"

    /// 解析 Keychain account；非 `keychain:` 前缀返回 nil
    public var keychainAccount: String? {
        guard apiKeyRef.hasPrefix(Self.keychainRefPrefix) else { return nil }
        return String(apiKeyRef.dropFirst(Self.keychainRefPrefix.count))
    }

    // MARK: - Codable（手写 init；保证解码路径也做 capabilities 去重+排序）
    //
    // 评审修正（Codex 第七轮 P2）：仅在 init(id:…:capabilities:) 里做归一化不够——
    // 用户手改 `config-v2.json`（如 `"capabilities":["toolCalling","promptCaching","toolCalling"]`）
    // 直接走自动合成的 decoder 会保留重复/乱序，违反"JSON 数组顺序稳定 + Set 语义"承诺。
    // 本版手写 `init(from:)` 在解码时跑同样的规范化；`encode(to:)` 走自动合成（因为 init 已保证 self.capabilities 有序无重）。

    private enum CodingKeys: String, CodingKey {
        case id, kind, name, baseURL, apiKeyRef, defaultModel, capabilities
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.kind = try c.decode(ProviderKind.self, forKey: .kind)
        self.name = try c.decode(String.self, forKey: .name)
        self.baseURL = try c.decodeIfPresent(URL.self, forKey: .baseURL)
        self.apiKeyRef = try c.decode(String.self, forKey: .apiKeyRef)
        self.defaultModel = try c.decode(String.self, forKey: .defaultModel)
        // 解码后同样做归一化，保证"外部 JSON 手改后 round-trip 结果稳定"
        let raw = try c.decode([ProviderCapability].self, forKey: .capabilities)
        self.capabilities = Array(Set(raw)).sorted { $0.rawValue < $1.rawValue }
    }
}

/// Provider 协议族
public enum ProviderKind: String, Sendable, Codable, CaseIterable {
    /// OpenAI Chat Completions 兼容（OpenAI / DeepSeek / Moonshot / OpenRouter / 自建中转）
    case openAICompatible
    /// Anthropic Messages API
    case anthropic
    /// Google Gemini API
    case gemini
    /// 本地 Ollama
    case ollama
}
