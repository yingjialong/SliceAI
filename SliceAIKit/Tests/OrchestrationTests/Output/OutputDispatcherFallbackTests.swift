import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// D-30b：未完成的展示模式 fallback 到 windowSink，已实现模式不能落窗。
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

    /// 验证旧 API 下 file 模式不再 fallback 到 windowSink。
    func test_handle_file_doesNotWriteWindowSink() async throws {
        try await assertDoesNotWriteWindow(mode: .file)
    }

    /// 验证旧 API 下 silent 模式不再 fallback 到 windowSink。
    func test_handle_silent_doesNotWriteWindowSink() async throws {
        try await assertDoesNotWriteWindow(mode: .silent)
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

    /// 参数化验证未实现的展示模式会 fallback 到 windowSink。
    private func assertFallsBack(mode: DisplayMode) async throws {
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

    /// 参数化验证已实现但非 window 的模式不会写 windowSink。
    private func assertDoesNotWriteWindow(mode: DisplayMode) async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)

        let outcome = try await dispatcher.handle(
            chunk: "x",
            mode: mode,
            invocationId: UUID()
        )

        XCTAssertEqual(outcome, .delivered)
        let calls = await spy.calls
        XCTAssertTrue(calls.isEmpty)
    }

    /// silent 模式不应再写 window sink。
    func test_lifecycle_silent_doesNotWriteWindowSink() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let context = OutputInvocationContext(
            invocationId: UUID(),
            toolId: "silent.tool",
            toolName: "Silent Tool",
            mode: .silent,
            screenAnchor: .zero
        )

        _ = try await dispatcher.handle(chunk: "hidden", context: context)
        try await dispatcher.finish(finalText: "hidden", context: context)

        let calls = await spy.calls
        XCTAssertTrue(calls.isEmpty)
    }

    /// file 模式应在 finish 时把 final text 写入 appendToFile 目标。
    func test_lifecycle_file_writesFinalTextAtFinish() async throws {
        let fileAppender = SpyFinalTextFileAppender()
        let dispatcher = OutputDispatcher(windowSink: SpyWindowSink(), fileAppender: fileAppender)
        let context = OutputInvocationContext(
            invocationId: UUID(),
            toolId: "file.tool",
            toolName: "File Tool",
            mode: .file,
            screenAnchor: .zero,
            outputBinding: OutputBinding(
                primary: .file,
                sideEffects: [.appendToFile(path: "/tmp/result.md", header: "## Result")]
            )
        )

        _ = try await dispatcher.handle(chunk: "streamed", context: context)
        try await dispatcher.finish(finalText: "final text", context: context)

        let calls = await fileAppender.calls
        XCTAssertEqual(calls, [
            SpyFinalTextFileAppender.Call(path: "/tmp/result.md", header: "## Result", finalText: "final text")
        ])
    }

    /// file 模式缺少 appendToFile 目标时必须失败，不能 fallback 到 window。
    func test_lifecycle_fileWithoutAppendDestinationThrows() async throws {
        let dispatcher = OutputDispatcher(windowSink: SpyWindowSink())
        let context = OutputInvocationContext(
            invocationId: UUID(),
            toolId: "file.tool",
            toolName: "File Tool",
            mode: .file,
            screenAnchor: .zero,
            outputBinding: OutputBinding(primary: .file, sideEffects: [])
        )

        do {
            try await dispatcher.finish(finalText: "final text", context: context)
            XCTFail("file mode without appendToFile destination must throw")
        } catch SliceError.configuration(.validationFailed(let message)) {
            XCTAssertTrue(message.contains("appendToFile"))
        } catch {
            XCTFail("expected validationFailed, got \(error)")
        }
    }
}

/// 测试用 final text 文件写入器。
private actor SpyFinalTextFileAppender: FinalTextFileAppending {
    struct Call: Sendable, Equatable {
        let path: String
        let header: String?
        let finalText: String
    }

    private(set) var calls: [Call] = []

    /// 记录文件追加请求。
    func append(finalText: String, to path: String, header: String?) async throws {
        calls.append(Call(path: path, header: header, finalText: finalText))
    }
}
