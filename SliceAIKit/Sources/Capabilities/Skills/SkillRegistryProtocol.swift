import Foundation

/// Skill 注册表协议：抽象 Phase 2 的真实 fs scan，让 ExecutionEngine 在 M2 阶段就能注入 Mock 跑通主流程。
///
/// 设计要点（KISS）：
/// - 只暴露两个查询：按 ID 查单个、列出全部。Phase 2 真实 registry 落地时再加 fs scan / hot reload /
///   manifest 校验等能力。
/// - protocol + 类型集中在同一文件，作为对外契约的单点入口。
public protocol SkillRegistryProtocol: Sendable {
    /// 按 skill id 查找单个 skill；不存在返回 nil（区别于 throw——"找不到"是合法状态）。
    /// - Parameter id: skill 的稳定 ID。
    /// - Returns: 对应的 `Skill`；未注册返回 `nil`。
    /// - Throws: 仅在 Phase 2 真实 registry 的 fs scan 失败时使用；M2 Mock 不抛错。
    func findSkill(id: String) async throws -> Skill?

    /// 列出全部已注册的 skill。
    /// - Returns: 当前注册的 `Skill` 数组（顺序由实现决定；Mock 保持注入顺序）。
    /// - Throws: 仅在 Phase 2 真实 registry 的 fs scan 失败时使用；M2 Mock 不抛错。
    func allSkills() async throws -> [Skill]
}

// MARK: - Skill

/// Skill 描述（最小 KISS 版本）。
///
/// 字段语义：
/// - `id`: 全局稳定 ID（如 `"skill.echo"` / `"skill.summary"`），跨 session / 升级保持不变；
/// - `name`: 用户可读名（中文/英文，多语言由上层 i18n 决定，M2 直接用 manifest 里的字段）；
/// - `manifestPath`: skill manifest 文件绝对路径。Phase 2 fs scan 时由 registry 填入；M2 Mock
///   场景下测试可以塞 `"/tmp/mock"` 之类的占位串——`Skill` 类型不校验路径合法性，那是 Phase 2
///   真实 registry 的责任。
///
/// `Identifiable` 是为了让未来 SwiftUI `List` / `ForEach` 能直接渲染——`id` 字段已满足约束，
/// 不需要额外引入 UUID。
public struct Skill: Sendable, Equatable, Hashable, Codable, Identifiable {
    /// skill 的稳定 ID。
    public let id: String

    /// 用户可读名。
    public let name: String

    /// skill manifest 文件绝对路径（Phase 2 fs scan 时填入）。
    public let manifestPath: String

    /// 构造一个 skill 描述。
    /// - Parameters:
    ///   - id: 稳定 ID。
    ///   - name: 用户可读名。
    ///   - manifestPath: manifest 文件绝对路径。
    public init(id: String, name: String, manifestPath: String) {
        self.id = id
        self.name = name
        self.manifestPath = manifestPath
    }
}
