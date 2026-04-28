import Foundation

/// `SkillRegistryProtocol` 的内存 Mock 实现：构造期注入 skills 数组，运行期按 ID 查表。
///
/// 设计要点（与 `MockMCPClient` 对称）：
/// - **actor**：保证 actor isolation + Sendable 安全，与真实 Phase 2 registry 的隔离模型对齐
///   （fs scan 必须 actor 化，避免并发 reload 撞车）。
/// - **production-side**：跟 `MockMCPClient` 同样放 `Sources/Capabilities/Skills/`，不放
///   `Tests/Helpers`——多个测试 target 共用、Phase 2 后仍可作 sample / dev fixture。
/// - **顺序保留**：内部用数组而非字典存 skills；`allSkills()` 返回注入顺序（测试可断言顺序），
///   `findSkill(id:)` 通过 `first(where:)` 线性查找。M2 测试场景的 skills 数量不会超过个位数，
///   线性查找的 O(n) 完全够用，KISS 优先（Phase 2 真实 registry 数量大时再换 dictionary index）。
public final actor MockSkillRegistry: SkillRegistryProtocol {

    // MARK: - 注入状态

    /// 已注册的 skill 数组；保留注入顺序，`allSkills()` 直接返回。
    private let skills: [Skill]

    // MARK: - 初始化

    /// 构造一个 Mock skill registry。
    /// - Parameter skills: 预注册的 skill 数组；默认空 = 空 registry。
    public init(skills: [Skill] = []) {
        self.skills = skills
    }

    // MARK: - SkillRegistryProtocol

    /// 按 id 线性查找；未命中返回 nil。
    public func findSkill(id: String) async throws -> Skill? {
        // 数量小，线性查找够用；找到第一个匹配即返回
        skills.first { $0.id == id }
    }

    /// 返回全部注册 skill 的拷贝（Swift Array 是 value type，调用方拿到独立副本）。
    public func allSkills() async throws -> [Skill] {
        skills
    }
}
