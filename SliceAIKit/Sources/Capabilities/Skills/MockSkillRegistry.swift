import Foundation
import SliceCore

/// `SkillRegistryProtocol` 的内存 Mock 实现，供测试和预览注入。
public final actor MockSkillRegistry: SkillRegistryProtocol {

    /// 已注册的 skill 数组；保留注入顺序，方便 UI 与测试断言。
    private let skills: [Skill]

    /// 可被 `loadSkillInstructions` 返回的正文 payload。
    private let instructions: [String: SkillInstructionPayload]
    /// 可被 `loadSkillResource` 返回的 supporting file payload。
    private let resources: [String: SkillResourcePayload]

    /// 构造一个 Mock skill registry。
    /// - Parameters:
    ///   - skills: 预注册的 skill 数组；默认空 = 空 registry。
    ///   - instructions: 按 skill id 注入的正文 payload。
    ///   - resources: 按 `skillId:relativePath` 注入的 supporting file payload。
    public init(
        skills: [Skill] = [],
        instructions: [String: SkillInstructionPayload] = [:],
        resources: [String: SkillResourcePayload] = [:]
    ) {
        self.skills = skills
        self.instructions = instructions
        self.resources = resources
    }

    /// 返回当前 mock snapshot。
    public func snapshot() async throws -> SkillRegistrySnapshot {
        SkillRegistrySnapshot(sources: [], skills: skills, diagnostics: [], generatedAt: Date())
    }

    /// 按 id 查找 enabled skill；禁用、shadow、错误状态都不可加载。
    public func findSkill(id: String) async throws -> Skill? {
        skills.first { $0.id == id && $0.state == .enabled }
    }

    /// 返回注入的 skill 指令正文；未注入时抛出配置错误。
    public func loadSkillInstructions(id: String) async throws -> SkillInstructionPayload {
        if let payload = instructions[id] {
            return payload
        }
        throw SliceError.configuration(.validationFailed("Skill not loadable: <redacted>"))
    }

    /// 返回注入的 supporting file；未注入时抛出配置错误。
    public func loadSkillResource(id: String, relativePath: String) async throws -> SkillResourcePayload {
        if let payload = resources["\(id):\(relativePath)"] {
            return payload
        }
        throw SliceError.configuration(.validationFailed("Skill resource not loadable: <redacted>"))
    }
}
