import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// D-30b：5 个 non-window mode 都 fallback 到 windowSink。
final class OutputDispatcherFallbackTests: XCTestCase {

    /// 测试用 window sink，记录 OutputDispatcher 实际投递的 chunk。
    actor SpyWindowSink: WindowSinkProtocol {
        var calls: [(chunk: String, invocationId: UUID)] = []

        /// 记录一次 windowSink.append 调用。
        func append(chunk: String, invocationId: UUID) async throws {
            calls.append((chunk, invocationId))
        }
    }

    /// 验证 bubble 模式 fallback 到 windowSink。
    func test_handle_bubble_fallsBack() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let invocationId = UUID()

        let outcome = try await dispatcher.handle(
            chunk: "hello",
            mode: .bubble,
            invocationId: invocationId
        )

        XCTAssertEqual(outcome, .delivered)
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].chunk, "hello")
        XCTAssertEqual(calls[0].invocationId, invocationId)
    }

    /// 验证 replace 模式 fallback 到 windowSink。
    func test_handle_replace_fallsBack() async throws {
        try await assertFallsBack(mode: .replace)
    }

    /// 验证 file 模式 fallback 到 windowSink。
    func test_handle_file_fallsBack() async throws {
        try await assertFallsBack(mode: .file)
    }

    /// 验证 silent 模式 fallback 到 windowSink。
    func test_handle_silent_fallsBack() async throws {
        try await assertFallsBack(mode: .silent)
    }

    /// 验证 structured 模式 fallback 到 windowSink。
    func test_handle_structured_fallsBack() async throws {
        try await assertFallsBack(mode: .structured)
    }

    /// 验证 window 模式维持直通行为。
    func test_handle_window_unchanged() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let invocationId = UUID()

        // window 模式不走 fallback，但仍应每个 chunk 投递一次。
        for _ in 0..<5 {
            let outcome = try await dispatcher.handle(
                chunk: "x",
                mode: .window,
                invocationId: invocationId
            )
            XCTAssertEqual(outcome, .delivered)
        }

        let calls = await spy.calls
        XCTAssertEqual(calls.count, 5)
    }

    /// 参数化验证 non-window mode 会 fallback 到 windowSink。
    private func assertFallsBack(mode: PresentationMode) async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)

        let outcome = try await dispatcher.handle(
            chunk: "x",
            mode: mode,
            invocationId: UUID()
        )

        XCTAssertEqual(outcome, .delivered)
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].chunk, "x")
    }
}
