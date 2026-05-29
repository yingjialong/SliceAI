import XCTest
import SliceCore
@testable import Orchestration

/// PlaygroundOutputDispatcher 不得触发生产 UI 或系统副作用。
final class PlaygroundOutputDispatcherTests: XCTestCase {

    /// window 模式应收集流式 chunk 与最终文本，供 Playground 右侧预览使用。
    func test_windowMode_collectsChunksAndFinalText() async throws {
        let dispatcher = PlaygroundOutputDispatcher()
        let context = makeContext(mode: .window)

        try await dispatcher.begin(context: context)
        _ = try await dispatcher.handle(chunk: "hello", context: context)
        _ = try await dispatcher.handle(chunk: " world", context: context)
        try await dispatcher.finish(finalText: "hello world", context: context)

        let snapshot = await dispatcher.snapshot(for: context.invocationId)
        XCTAssertEqual(snapshot?.chunks, ["hello", " world"])
        XCTAssertEqual(snapshot?.finalText, "hello world")
        XCTAssertEqual(snapshot?.mode, .window)
    }

    /// final-only 与 silent 模式在 Playground 中只记录预览，
    /// 不应在 finish 阶段抛出生产副作用错误。
    func test_fileReplaceBubbleStructuredAndSilent_doNotThrowAtFinish() async throws {
        for mode in [DisplayMode.file, .replace, .bubble, .structured, .silent] {
            let dispatcher = PlaygroundOutputDispatcher()
            let context = makeContext(mode: mode)
            try await dispatcher.begin(context: context)
            _ = try await dispatcher.handle(chunk: "preview", context: context)
            try await dispatcher.finish(finalText: "preview", context: context)
            let snapshot = await dispatcher.snapshot(for: context.invocationId)
            XCTAssertEqual(snapshot?.finalText, "preview")
        }
    }

    /// 失败时只记录用户可读错误，避免泄漏 provider 或执行细节。
    func test_fail_recordsRedactedErrorState() async {
        let dispatcher = PlaygroundOutputDispatcher()
        let context = makeContext(mode: .window)

        await dispatcher.fail(error: .provider(.unauthorized), context: context)

        let snapshot = await dispatcher.snapshot(for: context.invocationId)
        XCTAssertEqual(snapshot?.failureMessage, SliceError.provider(.unauthorized).userMessage)
    }

    /// 构造最小输出上下文。
    private func makeContext(mode: DisplayMode) -> OutputInvocationContext {
        OutputInvocationContext(
            invocationId: UUID(),
            toolId: "tool",
            toolName: "Tool",
            mode: mode,
            screenAnchor: .zero,
            outputBinding: nil
        )
    }
}
