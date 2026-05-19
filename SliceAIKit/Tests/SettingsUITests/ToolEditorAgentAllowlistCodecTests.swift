import SliceCore
@testable import SettingsUI
import XCTest

/// Agent Tool MCP allowlist 文本编解码测试。
final class ToolEditorAgentAllowlistCodecTests: XCTestCase {

    /// 解析 allowlist 文本时应忽略空行和注释，并保留有效 `server.tool` 行。
    func test_parseMCPAllowlistText_ignoresBlankCommentsAndInvalidLines() {
        let refs = AgentMCPAllowlistTextCodec.parse("""

        # search
          brave-search.brave_web_search
        invalid
        .missing-server
        missing-tool.
        filesystem.read_file
        """)

        XCTAssertEqual(refs, [
            MCPToolRef(server: "brave-search", tool: "brave_web_search"),
            MCPToolRef(server: "filesystem", tool: "read_file")
        ])
    }

    /// 渲染 allowlist 文本时应输出一行一个 `server.tool`，便于用户直接编辑和 diff。
    func test_renderMCPAllowlistText_outputsOneRefPerLine() {
        let text = AgentMCPAllowlistTextCodec.render([
            MCPToolRef(server: "brave-search", tool: "brave_web_search"),
            MCPToolRef(server: "filesystem", tool: "read_file")
        ])

        XCTAssertEqual(text, "brave-search.brave_web_search\nfilesystem.read_file")
    }
}
