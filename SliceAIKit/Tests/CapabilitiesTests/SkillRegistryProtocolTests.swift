import XCTest
@testable import Capabilities

/// `SkillRegistryProtocol` 契约 + `MockSkillRegistry` 行为测试。
///
/// 覆盖矩阵（与 plan §2003 对齐）：
/// 1. empty-registry        —— 空 registry → findSkill(...) = nil；allSkills() = []
/// 2. populated-find-happy  —— 注入 [s1, s2] → findSkill(id: s1.id) 返回 s1
/// 3. populated-find-miss   —— 注入 [s1] → findSkill(id: "ghost") = nil
/// 4. allSkills-order       —— allSkills() 保留注入顺序
/// 5. skill-codable         —— Skill Codable round-trip
final class SkillRegistryProtocolTests: XCTestCase {

    // MARK: - Fixtures

    private let skillEcho = Skill(
        id: "skill.echo",
        name: "Echo",
        manifestPath: "/tmp/sliceai-mock/echo.yml"
    )
    private let skillSummary = Skill(
        id: "skill.summary",
        name: "Summarize",
        manifestPath: "/tmp/sliceai-mock/summary.yml"
    )

    // MARK: - 1. empty registry

    /// 空 registry → findSkill(任意 id) 必须返回 nil；allSkills() 必须返回空数组
    /// （契约：空 registry 是合法状态，绝不能 throw）
    func test_emptyRegistry_findReturnsNil_allReturnsEmpty() async throws {
        let registry = MockSkillRegistry()

        let found = try await registry.findSkill(id: "skill.anything")
        let all = try await registry.allSkills()

        XCTAssertNil(found)
        XCTAssertEqual(all, [])
    }

    // MARK: - 2. populated find happy

    /// 注入 [echo, summary] → 按 id 能查到对应 skill
    func test_findSkill_happyPath_returnsMatchingSkill() async throws {
        let registry = MockSkillRegistry(skills: [skillEcho, skillSummary])

        let found = try await registry.findSkill(id: "skill.summary")

        XCTAssertEqual(found, skillSummary)
    }

    // MARK: - 3. populated find miss

    /// 注入 [echo] → 查不存在的 id 应返回 nil（不 throw）
    func test_findSkill_miss_returnsNil() async throws {
        let registry = MockSkillRegistry(skills: [skillEcho])

        let found = try await registry.findSkill(id: "skill.ghost")

        XCTAssertNil(found)
    }

    // MARK: - 4. allSkills order

    /// allSkills() 返回顺序应与注入顺序一致（契约：方便 UI 按"管理员注册顺序"渲染）
    func test_allSkills_preservesInjectionOrder() async throws {
        let registry = MockSkillRegistry(skills: [skillEcho, skillSummary])

        let all = try await registry.allSkills()

        XCTAssertEqual(all, [skillEcho, skillSummary], "allSkills 必须保留注入顺序")
        // 反向注入再验一次，避免上面一条用例只是巧合通过
        let reversed = MockSkillRegistry(skills: [skillSummary, skillEcho])
        let reversedAll = try await reversed.allSkills()
        XCTAssertEqual(reversedAll, [skillSummary, skillEcho])
    }

    // MARK: - 5. Skill Codable round-trip

    /// Skill 全部 3 字段必须能 encode → decode 等价
    /// （Codable 是给 Phase 2 fs scan 把 manifest 序列化到磁盘的前置能力）
    func test_skill_codable_roundTrips() throws {
        let original = Skill(
            id: "skill.translate",
            name: "Translate",
            manifestPath: "/Users/test/Library/Application Support/SliceAI/skills/translate.yml"
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Skill.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertEqual(decoded.id, "skill.translate")
        XCTAssertEqual(decoded.name, "Translate")
        XCTAssertEqual(decoded.manifestPath, original.manifestPath)
    }
}
