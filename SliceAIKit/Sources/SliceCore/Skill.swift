import Foundation

/// 本地 skill 资源；对应用户配置 root 下的 Claude / Codex 风格 skill 包。
public struct Skill: Identifiable, Sendable, Codable, Equatable {
    /// 稳定 id；MVP 中等于 canonicalName。
    public let id: String
    /// 用户可见名称；优先来自 SKILL.md frontmatter name，缺省使用目录名。
    public let canonicalName: String
    /// skill 根目录路径。
    public let path: URL
    /// SKILL.md 文件绝对路径。
    public let skillFile: URL
    /// 从 SKILL.md frontmatter 解析出的 manifest。
    public var manifest: SkillManifest
    /// supporting files 索引；MVP 只展示，不读取内容。
    public var resources: [SkillResource]
    /// 信任来源；用户配置的外部 roots 默认为 selfManaged。
    public var provenance: Provenance
    /// 来源 root 摘要，供 UI 展示和冲突诊断。
    public var source: SkillSourceRef
    /// registry 合并后的运行期状态。
    public var state: SkillRegistryState

    /// 构造 Skill。
    public init(
        id: String,
        canonicalName: String,
        path: URL,
        skillFile: URL,
        manifest: SkillManifest,
        resources: [SkillResource],
        provenance: Provenance,
        source: SkillSourceRef,
        state: SkillRegistryState
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.path = path
        self.skillFile = skillFile
        self.manifest = manifest
        self.resources = resources
        self.provenance = provenance
        self.source = source
        self.state = state
    }
}

/// `SKILL.md` frontmatter 的最小兼容解析结果。
public struct SkillManifest: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let disableModelInvocation: Bool
    public let allowedTools: [String]
    public let userInvocable: Bool?
    public let rawFrontmatter: String
    public let instructionsCharacterCount: Int

    /// 构造 SkillManifest。
    public init(
        name: String,
        description: String,
        disableModelInvocation: Bool = false,
        allowedTools: [String] = [],
        userInvocable: Bool? = nil,
        rawFrontmatter: String = "",
        instructionsCharacterCount: Int = 0
    ) {
        self.name = name
        self.description = description
        self.disableModelInvocation = disableModelInvocation
        self.allowedTools = allowedTools
        self.userInvocable = userInvocable
        self.rawFrontmatter = rawFrontmatter
        self.instructionsCharacterCount = instructionsCharacterCount
    }

    private enum CodingKeys: String, CodingKey {
        case name, description, disableModelInvocation, allowedTools, userInvocable, rawFrontmatter,
             instructionsCharacterCount
    }

    /// 兼容旧 manifest fixture：缺少 Phase 2 新字段时使用安全默认值。
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description) ?? ""
        disableModelInvocation = try c.decodeIfPresent(Bool.self, forKey: .disableModelInvocation) ?? false
        allowedTools = try c.decodeIfPresent([String].self, forKey: .allowedTools) ?? []
        userInvocable = try c.decodeIfPresent(Bool.self, forKey: .userInvocable)
        rawFrontmatter = try c.decodeIfPresent(String.self, forKey: .rawFrontmatter) ?? ""
        instructionsCharacterCount = try c.decodeIfPresent(Int.self, forKey: .instructionsCharacterCount) ?? 0
    }

    /// 编码当前 canonical manifest 字段。
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encode(description, forKey: .description)
        try c.encode(disableModelInvocation, forKey: .disableModelInvocation)
        try c.encode(allowedTools, forKey: .allowedTools)
        try c.encodeIfPresent(userInvocable, forKey: .userInvocable)
        try c.encode(rawFrontmatter, forKey: .rawFrontmatter)
        try c.encode(instructionsCharacterCount, forKey: .instructionsCharacterCount)
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

/// Skill 来源 root 的轻量引用。
public struct SkillSourceRef: Sendable, Codable, Equatable {
    public let sourceId: String
    public let rootPath: String

    /// 构造 SkillSourceRef。
    public init(sourceId: String, rootPath: String) {
        self.sourceId = sourceId
        self.rootPath = rootPath
    }
}

/// Registry 合并 source、frontmatter、override 后的可展示状态。
public enum SkillRegistryState: String, Sendable, Codable {
    case enabled
    case disabled
    case defaultDisabled
    case parseError
    case shadowed
    case sourceError
    case tooLarge
}

/// 用户 skill 配置，随 config-v2.json 持久化。
public struct SkillSettings: Sendable, Codable, Equatable {
    public var sources: [SkillSource]
    public var overrides: [String: SkillEnablementOverride]

    /// 空 skill 设置。
    public static let empty = SkillSettings(sources: [], overrides: [:])

    /// 构造 SkillSettings。
    public init(sources: [SkillSource], overrides: [String: SkillEnablementOverride]) {
        self.sources = sources
        self.overrides = overrides
    }
}

/// 用户配置的 skill root。
public struct SkillSource: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var displayName: String
    public var rootPath: String
    public var isEnabled: Bool
    public var order: Int

    /// 构造 SkillSource。
    public init(id: String, displayName: String, rootPath: String, isEnabled: Bool, order: Int) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.isEnabled = isEnabled
        self.order = order
    }
}

/// Skill 启停 override；缺省时遵循 SKILL.md frontmatter。
public enum SkillEnablementOverride: String, Sendable, Codable {
    case on
    case off
}
