import XCTest
import SliceCore
@testable import Orchestration

/// ExecutionEvent 单元测试
///
/// 覆盖：
/// 1. `.started` case 正确携带 invocationId
/// 2. 所有 12 个主要 case 均可构造（含 SliceCore 类型关联值）
final class ExecutionEventTests: XCTestCase {

    func test_executionEvent_started_carriesInvocationId() {
        // 验证 .started case 能正确提取 invocationId
        let id = UUID()
        let event = ExecutionEvent.started(invocationId: id)
        guard case .started(let extracted) = event else {
            XCTFail("expected .started case")
            return
        }
        XCTAssertEqual(extracted, id)
    }

    func test_executionEvent_allCases_canBeBuilt() {
        // 构造 12 个主要 case（不含 .permissionWouldBeRequested / .sideEffectSkippedDryRun）
        // 验证所有 case 能正常实例化，无编译错误，无运行时崩溃
        let cases: [ExecutionEvent] = [
            .started(invocationId: UUID()),
            .contextResolved(key: ContextKey(rawValue: "selection"), valueDescription: "<82 chars>"),
            .promptRendered(preview: "Translate the following text to English: …"),
            .llmChunk(delta: "Hello"),
            .toolCallProposed(
                ref: MCPToolRef(server: "fs", tool: "read"),
                argsDescription: "{\"path\":\"~/Documents/foo.md\"}"
            ),
            .toolCallApproved(id: UUID()),
            .toolCallResult(id: UUID(), summary: "<file contents 1234 bytes>"),
            .stepCompleted(step: 1, total: 3),
            .sideEffectTriggered(.copyToClipboard),
            .finished(report: .stub()),
            .failed(.configuration(.validationFailed("test"))),
            .notImplemented(reason: "DisplayMode.bubble not in M2 scope")
        ]
        // .permissionWouldBeRequested 与 .sideEffectSkippedDryRun 是 dry-run 专属事件，
        // 由 ExecutionEngine Step 2.5 / Step 7 在 dry-run 路径下 yield；
        // 主流程 smoke test 不单独构造，由 Task 4 ExecutionEngineTests 的 dry-run 路径覆盖
        XCTAssertEqual(cases.count, 12)
    }
}
