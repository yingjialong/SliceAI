import Foundation

/// 本地 skill 资源；对应 `~/Library/Application Support/SliceAI/skills/<skill-id>/`
///
/// M1 只落数据模型；真正的 `SkillRegistry`（扫描目录、解析 SKILL.md、加载资源）在 Phase 2。
public struct Skill: Identifiable, Sendable, Codable, Equatable {
    /// 如 "english-tutor@1.2.0"
    public let id: String
    /// 本地 skill 目录路径
    public let path: URL
    /// 从 SKILL.md frontmatter 解析出的 manifest
    public var manifest: SkillManifest
    /// 资源文件列表（图片 / CSV / reference MD 等）
    public var resources: [SkillResource]
    /// 信任来源
    ///
    /// `var` 是为了让安装流程在签名校验完成后更新（例如从 `.selfManaged` 升级为 `.communitySigned`）；
    /// 运行时消费方（PermissionBroker / audit log）**不得 mutate**，按只读语义消费。
    /// 本契约由调用方约束；struct 本身无法在类型层面禁止。
    public var provenance: Provenance

    /// 构造 Skill
    public init(id: String, path: URL, manifest: SkillManifest, resources: [SkillResource], provenance: Provenance) {
        self.id = id
        self.path = path
        self.manifest = manifest
        self.resources = resources
        self.provenance = provenance
    }
}

/// SKILL.md frontmatter 解析结果
public struct SkillManifest: Sendable, Codable, Equatable {
    /// 人类可读名称
    public let name: String
    /// 功能简介
    public let description: String
    /// 语义化版本号
    public let version: String
    /// 激活条件（表达式字符串，Phase 2 解析）
    public let triggers: [String]
    /// 需要的 Provider 能力
    ///
    /// **不去重**：M1 保持用户 SKILL.md 声明顺序不变；Phase 2 的 SkillRegistry 在
    /// 装载时按需去重 + 与 Provider.capabilities 做能力匹配。若用户手改 SKILL.md
    /// 写入重复 capability，这里不会静默 dedup，交由 SkillRegistry 报告冲突。
    public let requiredCapabilities: [ProviderCapability]

    /// 构造 SkillManifest
    public init(
        name: String,
        description: String,
        version: String,
        triggers: [String],
        requiredCapabilities: [ProviderCapability]
    ) {
        self.name = name
        self.description = description
        self.version = version
        self.triggers = triggers
        self.requiredCapabilities = requiredCapabilities
    }
}

/// Skill 资源描述
public struct SkillResource: Sendable, Codable, Equatable {
    /// 相对 skill 根的路径
    public let relativePath: String
    /// MIME 类型
    public let mimeType: String

    /// 构造 SkillResource
    public init(relativePath: String, mimeType: String) {
        self.relativePath = relativePath
        self.mimeType = mimeType
    }
}

/// Tool 引用 Skill 的方式
public struct SkillReference: Sendable, Codable, Equatable {
    /// 指向 SkillRegistry 的 id
    public let id: String
    /// 可选锁定版本；nil 时跟随 registry 最新
    public let pinVersion: String?

    /// 构造 SkillReference
    public init(id: String, pinVersion: String?) {
        self.id = id
        self.pinVersion = pinVersion
    }
}
