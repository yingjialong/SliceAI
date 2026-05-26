import Foundation
import SliceCore

/// Skill 注册表协议：提供 snapshot 查询和 SKILL.md 按需加载。
public protocol SkillRegistryProtocol: Sendable {
    /// 返回当前 registry 快照。
    func snapshot() async throws -> SkillRegistrySnapshot

    /// 按 canonical skill id 查找可加载的 active skill。
    /// - Parameter id: skill 稳定 id，MVP 中等于 canonicalName。
    /// - Returns: enabled skill；未注册、禁用或被 shadow 时返回 nil。
    func findSkill(id: String) async throws -> Skill?

    /// 加载完整 SKILL.md 指令正文。
    /// - Parameter id: skill 稳定 id，MVP 中等于 canonicalName。
    /// - Returns: 指令 payload；不可加载时抛出配置错误。
    func loadSkillInstructions(id: String) async throws -> SkillInstructionPayload

    /// 加载 skill 内已索引 supporting file 的 UTF-8 内容。
    /// - Parameters:
    ///   - id: skill 稳定 id，MVP 中等于 canonicalName。
    ///   - relativePath: 相对 skill 根目录的资源路径。
    /// - Returns: supporting file payload；不可加载时抛出配置错误。
    func loadSkillResource(id: String, relativePath: String) async throws -> SkillResourcePayload
}

/// Registry 当前快照，供 Settings 和运行时读取。
public struct SkillRegistrySnapshot: Sendable, Codable, Equatable {
    public let sources: [SkillSource]
    public let skills: [Skill]
    public let diagnostics: [SkillRegistryDiagnostic]
    public let generatedAt: Date

    /// 构造 SkillRegistrySnapshot。
    public init(
        sources: [SkillSource],
        skills: [Skill],
        diagnostics: [SkillRegistryDiagnostic],
        generatedAt: Date
    ) {
        self.sources = sources
        self.skills = skills
        self.diagnostics = diagnostics
        self.generatedAt = generatedAt
    }
}

/// 按需加载 SKILL.md 后返回给 AgentExecutor 的正文 payload。
public struct SkillInstructionPayload: Sendable, Codable, Equatable {
    public let id: String
    public let canonicalName: String
    public let skillFile: URL
    public let frontmatterSummary: SkillManifest
    public let instructions: String

    /// 构造 SkillInstructionPayload。
    public init(
        id: String,
        canonicalName: String,
        skillFile: URL,
        frontmatterSummary: SkillManifest,
        instructions: String
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.skillFile = skillFile
        self.frontmatterSummary = frontmatterSummary
        self.instructions = instructions
    }
}

/// 按需加载 supporting file 后返回给 AgentExecutor 的只读资源 payload。
public struct SkillResourcePayload: Sendable, Codable, Equatable {
    public let id: String
    public let canonicalName: String
    public let relativePath: String
    public let fileURL: URL
    public let mimeType: String
    public let content: String

    /// 构造 SkillResourcePayload。
    public init(
        id: String,
        canonicalName: String,
        relativePath: String,
        fileURL: URL,
        mimeType: String,
        content: String
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.relativePath = relativePath
        self.fileURL = fileURL
        self.mimeType = mimeType
        self.content = content
    }
}

/// Registry 诊断，message 面向 UI 展示，底层错误仅进入脱敏日志。
public struct SkillRegistryDiagnostic: Sendable, Codable, Equatable {
    public let code: SkillRegistryDiagnosticCode
    public let sourceId: String?
    public let path: String?
    public let message: String

    /// 构造 SkillRegistryDiagnostic。
    public init(
        code: SkillRegistryDiagnosticCode,
        sourceId: String?,
        path: String?,
        message: String
    ) {
        self.code = code
        self.sourceId = sourceId
        self.path = path
        self.message = message
    }
}

/// MVP registry 诊断码。
public enum SkillRegistryDiagnosticCode: String, Sendable, Codable, Equatable {
    case sourceUnreadable
    case parseError
    case missingDescription
    case tooLarge
    case duplicateName
    case symlinkEscape
}
