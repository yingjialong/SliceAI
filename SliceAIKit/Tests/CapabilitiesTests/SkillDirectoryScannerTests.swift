import XCTest
import SliceCore
@testable import Capabilities

final class SkillDirectoryScannerTests: XCTestCase {
    /// 验证 scanner 覆盖根目录、root/*、Claude、Agents、Codex 常见布局。
    func test_scannerFindsRootCollectionAndClaudeCodexLayouts() throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("SKILL.md"), name: "root")
        try writeSkill(root.appendingPathComponent("direct/SKILL.md"), name: "direct")
        try writeSkill(root.appendingPathComponent("skills/nested-skill/SKILL.md"), name: "nested-skill")
        try writeSkill(root.appendingPathComponent(".claude/skills/claude-skill/SKILL.md"), name: "claude-skill")
        try writeSkill(root.appendingPathComponent(".agents/skills/codex-skill/SKILL.md"), name: "codex-skill")
        try writeSkill(root.appendingPathComponent(".codex/skills/local-codex/SKILL.md"), name: "local-codex")

        let source = SkillSource(id: "root", displayName: "Root", rootPath: root.path, isEnabled: true, order: 0)
        let candidates = try SkillDirectoryScanner().candidates(in: source)

        XCTAssertEqual(Set(candidates.map(\.directory.lastPathComponent)), [
            root.lastPathComponent,
            "direct",
            "nested-skill",
            "claude-skill",
            "codex-skill",
            "local-codex",
        ])
    }

    /// 验证 scanner 只扫描一层，避免 root 下深层目录产生不可控 IO。
    func test_scannerDoesNotRecurseDeeply() throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("a/b/c/SKILL.md"), name: "deep")

        let source = SkillSource(id: "root", displayName: "Root", rootPath: root.path, isEnabled: true, order: 0)
        let candidates = try SkillDirectoryScanner().candidates(in: source)

        XCTAssertTrue(candidates.isEmpty)
    }

    /// 验证指向 source root 外部的 symlink skill 会被拒绝。
    func test_scannerRejectsSymlinkEscapingSourceRoot() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        try writeSkill(outside.appendingPathComponent("escape/SKILL.md"), name: "escape")
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: outside.appendingPathComponent("escape")
        )

        let source = SkillSource(id: "root", displayName: "Root", rootPath: root.path, isEnabled: true, order: 0)
        let result = try SkillDirectoryScanner().scan(in: source)

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.rejections.contains { $0.reason == .symlinkEscapesSourceRoot })
    }

    /// 验证 disabled source 不扫描任何路径。
    func test_scannerSkipsDisabledSource() throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("SKILL.md"), name: "root")

        let source = SkillSource(id: "root", displayName: "Root", rootPath: root.path, isEnabled: false, order: 0)
        let result = try SkillDirectoryScanner().scan(in: source)

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.rejections.isEmpty)
    }
}

/// 创建独立临时目录，避免测试之间共享状态。
private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sliceai-skill-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// 写入最小合法 SKILL.md fixture。
private func writeSkill(_ url: URL, name: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try """
    ---
    name: \(name)
    description: \(name) description
    ---
    Instructions for \(name).
    """.write(to: url, atomically: true, encoding: .utf8)
}
