import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// `.bubble` 与 `.structured` DisplayMode 的 OutputDispatcher 路由测试。
final class BubbleStructuredDisplayModeTests: XCTestCase {

    /// bubble 不应在 chunk 阶段写 window，应在 finish 阶段展示完整 final text。
    func test_bubble_callsBubbleSinkOnlyAtFinish() async throws {
        let window = SpyWindowSinkForBubbleStructured()
        let bubble = SpyBubbleOutputSink()
        let dispatcher = OutputDispatcher(windowSink: window, bubbleSink: bubble)
        let context = OutputInvocationContext(
            invocationId: UUID(),
            toolId: "bubble.tool",
            toolName: "Bubble Tool",
            mode: .bubble,
            screenAnchor: CGPoint(x: 20, y: 30)
        )

        _ = try await dispatcher.handle(chunk: "partial", context: context)
        let windowCallsBeforeFinish = await window.snapshot()
        let bubbleCallsBeforeFinish = await bubble.snapshot()
        XCTAssertTrue(windowCallsBeforeFinish.isEmpty)
        XCTAssertTrue(bubbleCallsBeforeFinish.isEmpty)

        try await dispatcher.finish(finalText: "complete text", context: context)

        let windowCallsAfterFinish = await window.snapshot()
        let bubbleCallsAfterFinish = await bubble.snapshot()
        XCTAssertTrue(windowCallsAfterFinish.isEmpty)
        XCTAssertEqual(bubbleCallsAfterFinish, [
            SpyBubbleOutputSink.Call(finalText: "complete text", context: context)
        ])
    }

    /// structured 不应在 chunk 阶段写 window，应在 finish 阶段展示完整 final text。
    func test_structured_callsStructuredSinkOnlyAtFinish() async throws {
        let window = SpyWindowSinkForBubbleStructured()
        let structured = SpyStructuredOutputSink()
        let dispatcher = OutputDispatcher(windowSink: window, structuredSink: structured)
        let context = OutputInvocationContext(
            invocationId: UUID(),
            toolId: "structured.tool",
            toolName: "Structured Tool",
            mode: .structured,
            screenAnchor: CGPoint(x: 40, y: 50)
        )

        _ = try await dispatcher.handle(chunk: "{\"score\":", context: context)
        let windowCallsBeforeFinish = await window.snapshot()
        let structuredCallsBeforeFinish = await structured.snapshot()
        XCTAssertTrue(windowCallsBeforeFinish.isEmpty)
        XCTAssertTrue(structuredCallsBeforeFinish.isEmpty)

        try await dispatcher.finish(finalText: "{\"score\":9}", context: context)

        let windowCallsAfterFinish = await window.snapshot()
        let structuredCallsAfterFinish = await structured.snapshot()
        XCTAssertTrue(windowCallsAfterFinish.isEmpty)
        XCTAssertEqual(structuredCallsAfterFinish, [
            SpyStructuredOutputSink.Call(finalText: "{\"score\":9}", context: context)
        ])
    }

    /// bubble 缺少 sink 时必须抛配置错误，避免静默丢输出。
    func test_bubble_withoutSinkThrowsConfigurationError() async throws {
        let dispatcher = OutputDispatcher(windowSink: SpyWindowSinkForBubbleStructured())
        let context = OutputInvocationContext(
            invocationId: UUID(),
            toolId: "bubble.tool",
            toolName: "Bubble Tool",
            mode: .bubble,
            screenAnchor: .zero
        )

        do {
            try await dispatcher.finish(finalText: "complete text", context: context)
            XCTFail("bubble mode without sink must throw")
        } catch SliceError.configuration(.validationFailed(let message)) {
            XCTAssertTrue(message.contains("DisplayMode.bubble"))
        } catch {
            XCTFail("expected configuration validation error, got \(error)")
        }
    }
}

/// 测试用 window sink。
private actor SpyWindowSinkForBubbleStructured: WindowSinkProtocol {
    private(set) var calls: [(chunk: String, invocationId: UUID)] = []

    /// 记录 window append 调用。
    func append(chunk: String, invocationId: UUID) async throws {
        calls.append((chunk: chunk, invocationId: invocationId))
    }

    /// 返回当前调用快照。
    func snapshot() -> [(chunk: String, invocationId: UUID)] {
        calls
    }
}

/// 测试用 bubble sink。
private actor SpyBubbleOutputSink: BubbleOutputSink {
    struct Call: Sendable, Equatable {
        let finalText: String
        let context: OutputInvocationContext
    }

    private(set) var calls: [Call] = []

    /// 记录 bubble 展示请求。
    func showBubble(finalText: String, context: OutputInvocationContext) async throws {
        calls.append(Call(finalText: finalText, context: context))
    }

    /// 返回当前调用快照。
    func snapshot() -> [Call] {
        calls
    }
}

/// 测试用 structured sink。
private actor SpyStructuredOutputSink: StructuredOutputSink {
    struct Call: Sendable, Equatable {
        let finalText: String
        let context: OutputInvocationContext
    }

    private(set) var calls: [Call] = []

    /// 记录 structured 展示请求。
    func showStructured(finalText: String, context: OutputInvocationContext) async throws {
        calls.append(Call(finalText: finalText, context: context))
    }

    /// 返回当前调用快照。
    func snapshot() -> [Call] {
        calls
    }
}
