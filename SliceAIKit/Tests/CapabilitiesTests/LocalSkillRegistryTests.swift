import XCTest
import SliceCore
@testable import Capabilities

final class LocalSkillRegistryTests: XCTestCase {

    /// 默认 registry 应包含首方 English Tutor skill，供内置 English Tutor Agent Tool 绑定。
    func test_snapshotIncludesBundledEnglishTutorByDefault() async throws {
        let registry = LocalSkillRegistry(settingsProvider: { .empty })

        let snapshot = try await registry.snapshot()
        let skill = try XCTUnwrap(snapshot.skills.first { $0.id == "english-tutor" })

        XCTAssertEqual(skill.canonicalName, "english-tutor")
        XCTAssertEqual(skill.provenance, .firstParty)
        XCTAssertEqual(skill.state, .enabled)
    }

    /// 内置 English Tutor skill 必须能通过 registry 按需加载完整说明。
    func test_loadSkillInstructionsReturnsBundledEnglishTutor() async throws {
        let registry = LocalSkillRegistry(settingsProvider: { .empty })

        let payload = try await registry.loadSkillInstructions(id: "english-tutor")

        XCTAssertEqual(payload.canonicalName, "english-tutor")
        XCTAssertTrue(payload.instructions.contains("Return a JSON object"))
        XCTAssertTrue(payload.instructions.contains("ttsText"))
    }

    /// 配置 source 后，snapshot 应返回 enabled skill。
    func test_snapshotReturnsEnabledSkillFromConfiguredSource() async throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("writing/SKILL.md"), name: "writing", description: "Write clearly.")
        let settings = SkillSettings(sources: [source(root)], overrides: [:])
        let registry = LocalSkillRegistry(settingsProvider: { settings })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.map(\.canonicalName), ["english-tutor", "writing"])
        XCTAssertEqual(snapshot.skills.first { $0.id == "writing" }?.state, .enabled)
    }

    /// 同名 skill 按 source order 保留第一个 enabled，后续 enabled 标记为 shadowed。
    func test_duplicateNamesShadowLowerPrioritySource() async throws {
        let first = try makeTempRoot()
        let second = try makeTempRoot()
        try writeSkill(first.appendingPathComponent("writing/SKILL.md"), name: "writing", description: "First.")
        try writeSkill(second.appendingPathComponent("writing/SKILL.md"), name: "writing", description: "Second.")
        let settings = SkillSettings(
            sources: [source(first, id: "first", order: 0), source(second, id: "second", order: 1)],
            overrides: [:]
        )
        let registry = LocalSkillRegistry(settingsProvider: { settings })

        let snapshot = try await registry.snapshot()

        let writingSkills = snapshot.skills.filter { $0.canonicalName == "writing" }
        XCTAssertEqual(writingSkills.filter { $0.state == .enabled }.count, 1)
        XCTAssertEqual(writingSkills.filter { $0.state == .shadowed }.count, 1)
        XCTAssertTrue(snapshot.diagnostics.contains { $0.code == .duplicateName })
    }

    /// loadSkillInstructions 只返回 SKILL.md body，不读取 supporting files。
    func test_loadSkillInstructionsReturnsBody() async throws {
        let root = try makeTempRoot()
        try writeSkill(
            root.appendingPathComponent("writing/SKILL.md"),
            name: "writing",
            description: "Write.",
            body: "Use active voice."
        )
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let payload = try await registry.loadSkillInstructions(id: "writing")

        XCTAssertEqual(payload.canonicalName, "writing")
        XCTAssertTrue(payload.instructions.contains("Use active voice."))
    }

    /// snapshot 应索引可读 supporting files，并跳过 scripts、二进制 assets 和越界 symlink。
    func test_snapshotIndexesReadableSupportingFilesAndSkipsUnsafeResources() async throws {
        let root = try makeTempRoot()
        let skillDir = root.appendingPathComponent("writing", isDirectory: true)
        try writeSkill(skillDir.appendingPathComponent("SKILL.md"), name: "writing", description: "Write.")
        try writeText("Style guide", to: skillDir.appendingPathComponent("references/style.md"))
        try writeText("Template", to: skillDir.appendingPathComponent("assets/template.md"))
        try writeText("#!/bin/sh\necho unsafe", to: skillDir.appendingPathComponent("scripts/check.sh"))
        try Data([0x89, 0x50, 0x4E, 0x47]).write(to: skillDir.appendingPathComponent("assets/logo.png"))
        let outside = root.appendingPathComponent("outside.md")
        try "Outside".write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: skillDir.appendingPathComponent("references/outside.md"),
            withDestinationURL: outside
        )
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let snapshot = try await registry.snapshot()
        let resources = try XCTUnwrap(snapshot.skills.first { $0.id == "writing" }?.resources)

        XCTAssertEqual(resources.map(\.relativePath).sorted(), [
            "assets/template.md",
            "references/style.md"
        ])
        XCTAssertEqual(resources.first { $0.relativePath == "references/style.md" }?.mimeType, "text/markdown")
    }

    /// loadSkillResource 应只读取已索引的 UTF-8 supporting file。
    func test_loadSkillResourceReturnsIndexedUtf8Content() async throws {
        let root = try makeTempRoot()
        let skillDir = root.appendingPathComponent("writing", isDirectory: true)
        try writeSkill(skillDir.appendingPathComponent("SKILL.md"), name: "writing", description: "Write.")
        try writeText("Use active voice.", to: skillDir.appendingPathComponent("references/style.md"))
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let payload = try await registry.loadSkillResource(id: "writing", relativePath: "references/style.md")

        XCTAssertEqual(payload.canonicalName, "writing")
        XCTAssertEqual(payload.relativePath, "references/style.md")
        XCTAssertEqual(payload.mimeType, "text/markdown")
        XCTAssertEqual(payload.content, "Use active voice.")
    }

    /// scripts 与路径穿越必须被拒绝，避免 supporting files 只读能力扩大到任意文件读取。
    func test_loadSkillResourceRejectsScriptsAndTraversal() async throws {
        let root = try makeTempRoot()
        let skillDir = root.appendingPathComponent("writing", isDirectory: true)
        try writeSkill(skillDir.appendingPathComponent("SKILL.md"), name: "writing", description: "Write.")
        try writeText("#!/bin/sh\necho unsafe", to: skillDir.appendingPathComponent("scripts/check.sh"))
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        try await assertThrows {
            _ = try await registry.loadSkillResource(id: "writing", relativePath: "scripts/check.sh")
        }
        try await assertThrows {
            _ = try await registry.loadSkillResource(id: "writing", relativePath: "../outside.md")
        }
    }

    /// 缺失 description 时默认禁用并产生诊断，除非用户显式 override on。
    func test_missingDescriptionIsDefaultDisabledAndDiagnosed() async throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("writing/SKILL.md"), name: "writing", description: nil)
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.first { $0.id == "writing" }?.state, .defaultDisabled)
        XCTAssertTrue(snapshot.diagnostics.contains { $0.code == .missingDescription })
    }

    /// 超过大小上限的 SKILL.md 可展示为 tooLarge，但不可加载。
    func test_oversizeSkillFileIsTooLargeAndNotLoadable() async throws {
        let root = try makeTempRoot()
        try writeOversizeSkill(root.appendingPathComponent("huge/SKILL.md"))
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.first { $0.id == "huge" }?.state, .tooLarge)
        do {
            _ = try await registry.loadSkillInstructions(id: "huge")
            XCTFail("expected oversize skill to be unloadable")
        } catch {
            // Expected.
        }
    }

    /// 用户显式开启缺少 description 的 skill 时，应允许加载。
    func test_overrideOnEnablesMissingDescriptionSkill() async throws {
        let root = try makeTempRoot()
        try writeSkill(
            root.appendingPathComponent("writing/SKILL.md"),
            name: "writing",
            description: nil,
            body: "Write."
        )
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: ["writing": .on])
        })

        let snapshot = try await registry.snapshot()
        let payload = try await registry.loadSkillInstructions(id: "writing")

        XCTAssertEqual(snapshot.skills.first { $0.id == "writing" }?.state, .enabled)
        XCTAssertEqual(payload.canonicalName, "writing")
    }

    /// 缺少 frontmatter 结束符属于 parse error，不能被 override 开启后加载。
    func test_missingClosingFrontmatterIsParseErrorAndNotLoadable() async throws {
        let root = try makeTempRoot()
        let skillFile = root.appendingPathComponent("broken/SKILL.md")
        try FileManager.default.createDirectory(at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try """
        ---
        name: broken
        description: Broken.
        Body
        """.write(to: skillFile, atomically: true, encoding: .utf8)
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: ["broken": .on])
        })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.first { $0.id == "broken" }?.state, .parseError)
        XCTAssertTrue(snapshot.diagnostics.contains { $0.code == .parseError })
        do {
            _ = try await registry.loadSkillInstructions(id: "broken")
            XCTFail("expected parse error skill to be unloadable")
        } catch {
            // Expected.
        }
    }

    /// source root 不存在时必须产生可见诊断，避免 UI 把路径错误误判为空目录。
    func test_missingSourceRootProducesSourceUnreadableDiagnostic() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("sliceai-missing-source-\(UUID().uuidString)", isDirectory: true)
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.map(\.id), ["english-tutor"])
        XCTAssertTrue(snapshot.diagnostics.contains { $0.code == .sourceUnreadable })
    }
}

private func source(_ root: URL, id: String = "root", order: Int = 0) -> SkillSource {
    SkillSource(id: id, displayName: id, rootPath: root.path, isEnabled: true, order: order)
}

private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sliceai-registry-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeSkill(
    _ url: URL,
    name: String,
    description: String?,
    body: String = "Instructions for skill."
) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    var frontmatter = "---\nname: \(name)\n"
    if let description {
        frontmatter += "description: \(description)\n"
    }
    frontmatter += "---\n"
    try (frontmatter + body).write(to: url, atomically: true, encoding: .utf8)
}

private func writeOversizeSkill(_ url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let body = String(repeating: "x", count: SkillMarkdownParser.maxSkillBytes + 1)
    try """
    ---
    name: huge
    description: Huge skill.
    ---
    \(body)
    """.write(to: url, atomically: true, encoding: .utf8)
}

private func writeText(_ text: String, to url: URL) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try text.write(to: url, atomically: true, encoding: .utf8)
}

private func assertThrows(_ operation: () async throws -> Void) async throws {
    do {
        try await operation()
        XCTFail("expected operation to throw")
    } catch {
        // Expected.
    }
}
