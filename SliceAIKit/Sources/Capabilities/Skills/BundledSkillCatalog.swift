import Foundation
import SliceCore

/// 内置首方 skill 目录。
enum BundledSkillCatalog {

    /// 内置 English Tutor skill。
    static let englishTutor = BundledSkillDefinition(
        id: "english-tutor",
        canonicalName: "english-tutor",
        directoryName: "english-tutor",
        markdown: """
        ---
        name: english-tutor
        description: Diagnose English grammar, rewrite naturally, and provide short practice prompts.
        ---
        Return a JSON object with exactly these top-level keys:
        - correctedText: a natural corrected version of the selected text.
        - issues: an array of short issue descriptions.
        - explanation: concise tutoring feedback.
        - practice: one or two short practice prompts.
        - ttsText: one short sentence that should be spoken aloud.

        Prefer concrete corrections over broad lectures. Keep the tone direct, patient, and brief.
        """
    )

    /// 所有内置首方 skill。
    static var all: [BundledSkillDefinition] {
        [englishTutor]
    }
}

/// 单个内置 skill 的定义。
struct BundledSkillDefinition: Sendable {
    let id: String
    let canonicalName: String
    let directoryName: String
    let markdown: String

    /// 内置 skill 根路径占位；不会用于真实文件读取。
    var rootURL: URL {
        URL(fileURLWithPath: "/__sliceai_builtin__/skills/\(directoryName)", isDirectory: true)
    }

    /// 内置 SKILL.md 路径占位；用于 UI 和 payload 标识，不做磁盘读取。
    var skillFileURL: URL {
        rootURL.appendingPathComponent("SKILL.md", isDirectory: false)
    }

    /// 解析内置 SKILL.md。
    /// - Parameter parser: 与本地 skill 共用的 markdown parser。
    /// - Returns: 解析后的 manifest 与 instructions。
    func parse(using parser: SkillMarkdownParser) throws -> SkillMarkdownParseResult {
        try parser.parse(markdown, directoryName: directoryName)
    }

    /// 构造 registry snapshot 中的 Skill。
    /// - Parameter parser: 与本地 skill 共用的 markdown parser。
    /// - Returns: enabled first-party skill。
    func makeSkill(using parser: SkillMarkdownParser) throws -> Skill {
        let result = try parse(using: parser)
        return Skill(
            id: id,
            canonicalName: canonicalName,
            path: rootURL,
            skillFile: skillFileURL,
            manifest: result.manifest,
            resources: [],
            provenance: .firstParty,
            source: SkillSourceRef(sourceId: "sliceai-bundled", rootPath: rootURL.deletingLastPathComponent().path),
            state: .enabled
        )
    }

    /// 构造按需加载 payload。
    /// - Parameter parser: 与本地 skill 共用的 markdown parser。
    /// - Returns: AgentExecutor 可回填给模型的 skill instructions。
    func makeInstructionPayload(using parser: SkillMarkdownParser) throws -> SkillInstructionPayload {
        let result = try parse(using: parser)
        return SkillInstructionPayload(
            id: id,
            canonicalName: canonicalName,
            skillFile: skillFileURL,
            frontmatterSummary: result.manifest,
            instructions: result.instructions
        )
    }
}
