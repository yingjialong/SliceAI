import XCTest
import SliceCore
@testable import Capabilities

/// 公开 Skill 仓库兼容性 smoke；默认跳过，脚本设置 manifest env 后才联网验证快照。
final class PublicSkillRepositorySmokeTests: XCTestCase {
    /// 验证 manifest 中固定仓库快照的公开 skills 可被 LocalSkillRegistry 扫描、启用并加载。
    func test_publicSkillRepositoriesFromManifest() async throws {
        let manifest = try loadManifest()
        let settings = SkillSettings(
            sources: manifest.repositories.enumerated().map { index, repository in
                SkillSource(
                    id: repository.id,
                    displayName: repository.id,
                    rootPath: repository.rootPath,
                    isEnabled: true,
                    order: index
                )
            },
            overrides: [:]
        )
        let registry = LocalSkillRegistry(settingsProvider: { settings })
        let snapshot = try await registry.snapshot()

        XCTAssertTrue(snapshot.diagnostics.isEmpty, "unexpected diagnostics: \(snapshot.diagnostics)")

        for repository in manifest.repositories {
            for expectedName in repository.expectedNames {
                let skill = try XCTUnwrap(
                    snapshot.skills.first {
                        $0.canonicalName == expectedName && $0.source.sourceId == repository.id
                    },
                    "missing public skill \(expectedName) from \(repository.id)"
                )
                XCTAssertEqual(skill.state, .enabled)
                XCTAssertTrue(
                    isPath(skill.skillFile, inside: URL(fileURLWithPath: repository.rootPath, isDirectory: true)),
                    "skill file escapes repository root: \(skill.skillFile.path)"
                )

                let payload = try await registry.loadSkillInstructions(id: skill.id)
                XCTAssertFalse(
                    payload.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                    "empty instructions for \(expectedName)"
                )
            }
        }
    }

    /// 从 `SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST` 读取 smoke manifest；缺失时跳过。
    private func loadManifest() throws -> PublicSkillSmokeManifest {
        let environment = ProcessInfo.processInfo.environment
        guard let manifestPath = environment["SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST"],
              !manifestPath.isEmpty else {
            throw XCTSkip("Set SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST via scripts/phase2-public-skill-smoke.sh")
        }
        let data = try Data(contentsOf: URL(fileURLWithPath: manifestPath))
        return try JSONDecoder().decode(PublicSkillSmokeManifest.self, from: data)
    }
}

/// Smoke manifest 根对象。
private struct PublicSkillSmokeManifest: Decodable {
    let repositories: [PublicSkillSmokeRepository]
}

/// 单个公开仓库快照描述。
private struct PublicSkillSmokeRepository: Decodable {
    let id: String
    let url: String
    let commit: String
    let rootPath: String
    let expectedNames: [String]
}

/// 使用 pathComponents 判断文件是否位于 root 内，避免 `/tmp/root2` 被误判。
private func isPath(_ child: URL, inside root: URL) -> Bool {
    let childComponents = child.standardizedFileURL.pathComponents
    let rootComponents = root.standardizedFileURL.pathComponents
    guard childComponents.count >= rootComponents.count else {
        return false
    }
    return Array(childComponents.prefix(rootComponents.count)) == rootComponents
}
