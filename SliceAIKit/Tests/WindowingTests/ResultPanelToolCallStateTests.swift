import XCTest
@testable import Windowing

/// ResultPanel 工具调用生命周期状态测试。
final class ResultPanelToolCallStateTests: XCTestCase {

    /// proposed → approved → result 应保持同一行并更新状态与结果摘要。
    func test_toolCallState_transitionsProposedApprovedResult() throws {
        let id = UUID()
        var store = ResultToolCallStateStore()

        store.proposed(id: id, title: "fs.read", detail: "{\"path\":\"/tmp/a.txt\"}")
        store.approved(id: id)
        store.result(id: id, summary: "file contents")

        XCTAssertEqual(store.calls, [
            ResultToolCallState(id: id, title: "fs.read", detail: "file contents", status: .result)
        ])
    }

    /// denied 应记录拒绝原因，并保持原始 tool 标题。
    func test_toolCallState_recordsDenied() throws {
        let id = UUID()
        var store = ResultToolCallStateStore()

        store.proposed(id: id, title: "fs.write", detail: "{\"path\":\"/tmp/b.txt\"}")
        store.denied(id: id, reason: "Tool not allowed")

        XCTAssertEqual(store.calls, [
            ResultToolCallState(id: id, title: "fs.write", detail: "Tool not allowed", status: .denied)
        ])
    }

    /// error 应记录错误摘要，并保持同一生命周期行。
    func test_toolCallState_recordsError() throws {
        let id = UUID()
        var store = ResultToolCallStateStore()

        store.proposed(id: id, title: "web.search", detail: "{\"q\":\"SliceAI\"}")
        store.error(id: id, summary: "MCP tool call timed out")

        XCTAssertEqual(store.calls, [
            ResultToolCallState(id: id, title: "web.search", detail: "MCP tool call timed out", status: .error)
        ])
    }

    /// 同一 id 再次 proposed 应更新原行，避免 UI 出现重复 lifecycle row。
    func test_toolCallState_duplicateProposedUpdatesExistingRow() throws {
        let id = UUID()
        var store = ResultToolCallStateStore()

        store.proposed(id: id, title: "fs.read", detail: "old args")
        store.proposed(id: id, title: "fs.read", detail: "new args")

        XCTAssertEqual(store.calls, [
            ResultToolCallState(id: id, title: "fs.read", detail: "new args", status: .proposed)
        ])
    }

    /// reset 应清空所有 tool-call 行，避免下一次 open 看到旧 Agent 状态。
    func test_toolCallState_resetClearsRows() throws {
        var store = ResultToolCallStateStore()
        store.proposed(id: UUID(), title: "fs.read", detail: "{}")

        store.reset()

        XCTAssertTrue(store.calls.isEmpty)
    }
}
