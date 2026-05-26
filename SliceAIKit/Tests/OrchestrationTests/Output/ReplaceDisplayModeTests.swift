import CoreGraphics
import SliceCore
import XCTest
@testable import Orchestration

/// `.replace` DisplayMode 的输出派发测试。
final class ReplaceDisplayModeTests: XCTestCase {

    /// replace 模式 finish 时应调用文本替换 client，且不写 window sink。
    func test_replace_usesTextReplacementWhenAvailable() async throws {
        let windowSink = SpyWindowSink()
        let replacementClient = RecordingTextReplacementClient(result: .replaced)
        let dispatcher = OutputDispatcher(
            windowSink: windowSink,
            replacementClient: replacementClient
        )
        let context = makeContext()

        _ = try await dispatcher.handle(chunk: "draft", context: context)
        try await dispatcher.finish(finalText: "final answer", context: context)

        let calls = await replacementClient.calls
        XCTAssertEqual(calls, ["final answer"])
        let windowCalls = await windowSink.calls
        XCTAssertTrue(windowCalls.isEmpty)
    }

    /// AX 替换失败后，client 可返回 fallbackCopied，dispatcher 不应再落窗或抛错。
    func test_replace_fallsBackToClipboardAndNotificationWhenAXFails() async throws {
        let windowSink = SpyWindowSink()
        let replacementClient = RecordingTextReplacementClient(
            result: .fallbackCopied(reason: "ax set selected text failed")
        )
        let dispatcher = OutputDispatcher(
            windowSink: windowSink,
            replacementClient: replacementClient
        )
        let context = makeContext()

        _ = try await dispatcher.handle(chunk: "draft", context: context)
        try await dispatcher.finish(finalText: "replacement", context: context)

        let calls = await replacementClient.calls
        XCTAssertEqual(calls, ["replacement"])
        let windowCalls = await windowSink.calls
        XCTAssertTrue(windowCalls.isEmpty)
    }

    /// replace 必须等到 finish 才写入，不能把 streaming chunk 写进前台 App。
    func test_replace_waitsUntilFinishBeforeWriting() async throws {
        let replacementClient = RecordingTextReplacementClient(result: .replaced)
        let dispatcher = OutputDispatcher(
            windowSink: SpyWindowSink(),
            replacementClient: replacementClient
        )
        let context = makeContext()

        _ = try await dispatcher.handle(chunk: "partial", context: context)

        let callsBeforeFinish = await replacementClient.calls
        XCTAssertTrue(callsBeforeFinish.isEmpty)

        try await dispatcher.finish(finalText: "complete", context: context)

        let callsAfterFinish = await replacementClient.calls
        XCTAssertEqual(callsAfterFinish, ["complete"])
    }

    /// replace client 明确失败时，dispatcher 应抛出执行错误。
    func test_replace_failedResultThrows() async throws {
        let replacementClient = RecordingTextReplacementClient(
            result: .failed(reason: "replacement unavailable")
        )
        let dispatcher = OutputDispatcher(
            windowSink: SpyWindowSink(),
            replacementClient: replacementClient
        )

        do {
            try await dispatcher.finish(finalText: "complete", context: makeContext())
            XCTFail("replace failed result must throw")
        } catch SliceError.execution(.unknown(let reason)) {
            XCTAssertTrue(reason.contains("replace"))
        } catch {
            XCTFail("expected execution unknown, got \(error)")
        }
    }

    /// 构造 replace 输出上下文。
    private func makeContext() -> OutputInvocationContext {
        OutputInvocationContext(
            invocationId: UUID(),
            toolId: "replace.tool",
            toolName: "Replace Tool",
            mode: .replace,
            screenAnchor: .zero
        )
    }
}

/// 测试用 window sink。
private actor SpyWindowSink: WindowSinkProtocol {
    private(set) var calls: [(chunk: String, invocationId: UUID)] = []

    /// 记录一次 window sink 追加。
    func append(chunk: String, invocationId: UUID) async throws {
        calls.append((chunk: chunk, invocationId: invocationId))
    }
}

/// 测试用文本替换 client。
private actor RecordingTextReplacementClient: TextReplacementClient {
    private let result: TextReplacementResult
    private(set) var calls: [String] = []

    /// 构造固定返回值的替换 client。
    init(result: TextReplacementResult) {
        self.result = result
    }

    /// 记录 final text 并返回固定结果。
    func replaceSelection(with text: String) async -> TextReplacementResult {
        calls.append(text)
        return result
    }
}
