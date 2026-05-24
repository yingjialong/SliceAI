import XCTest
import SliceCore
@testable import Capabilities

final class SkillMarkdownParserTests: XCTestCase {
    /// 验证完整 frontmatter 可解析为 Phase 2 manifest。
    func test_parseValidSkillMarkdown() throws {
        let text = """
        ---
        name: writing
        description: Use when editing long-form text.
        disable-model-invocation: false
        allowed-tools:
          - Read
          - Bash
        user-invocable: true
        ---

        Follow these writing rules.
        """

        let result = try SkillMarkdownParser().parse(text, directoryName: "fallback")

        XCTAssertEqual(result.manifest.name, "writing")
        XCTAssertEqual(result.manifest.description, "Use when editing long-form text.")
        XCTAssertFalse(result.manifest.disableModelInvocation)
        XCTAssertEqual(result.manifest.allowedTools, ["Read", "Bash"])
        XCTAssertEqual(result.manifest.userInvocable, true)
        XCTAssertEqual(
            result.instructions.trimmingCharacters(in: .whitespacesAndNewlines),
            "Follow these writing rules."
        )
    }

    /// 验证缺少 name 时使用目录名作为稳定 fallback。
    func test_parseFallsBackToDirectoryNameWhenNameMissing() throws {
        let text = """
        ---
        description: Useful for summaries.
        ---
        Summarize carefully.
        """

        let result = try SkillMarkdownParser().parse(text, directoryName: "summary")

        XCTAssertEqual(result.manifest.name, "summary")
        XCTAssertEqual(result.manifest.description, "Useful for summaries.")
    }

    /// 验证布尔字段不是 true / false 时 fail-fast，避免静默启用错误配置。
    func test_parseRejectsInvalidBoolean() {
        let text = """
        ---
        name: bad
        description: Bad bool.
        disable-model-invocation: maybe
        ---
        Body
        """

        XCTAssertThrowsError(try SkillMarkdownParser().parse(text, directoryName: "bad"))
    }

    /// 验证 frontmatter 起始符存在但缺少结束符时 fail-fast，避免误当作正文加载。
    func test_parseRejectsMissingClosingFrontmatter() {
        let text = """
        ---
        name: bad
        description: Missing closing marker.
        Body
        """

        XCTAssertThrowsError(try SkillMarkdownParser().parse(text, directoryName: "bad")) { error in
            XCTAssertEqual(error as? SkillMarkdownParserError, .missingClosingFrontmatter)
        }
    }

    /// 验证 description 缺失不会中断扫描，而是返回可展示 warning。
    func test_parseMissingDescriptionReturnsWarning() throws {
        let text = """
        ---
        name: no-description
        ---
        Body
        """

        let result = try SkillMarkdownParser().parse(text, directoryName: "fallback")

        XCTAssertEqual(result.manifest.description, "")
        XCTAssertTrue(result.warnings.contains(.missingDescription))
    }

    /// 验证单行 allowed-tools 兼容为一个工具名，保持最小 YAML 子集。
    func test_parseScalarAllowedToolsAsSingleTool() throws {
        let text = """
        ---
        name: shell
        description: Shell helper.
        allowed-tools: Bash
        ---
        Body
        """

        let result = try SkillMarkdownParser().parse(text, directoryName: "shell")

        XCTAssertEqual(result.manifest.allowedTools, ["Bash"])
    }
}
