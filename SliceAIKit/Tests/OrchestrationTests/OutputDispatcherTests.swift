import SliceCore
import XCTest
@testable import Orchestration

/// `OutputDispatcher` 单元测试（Task 10 测试矩阵）。
///
/// 覆盖范围：
/// 1. `.window` 模式 chunk 顺序与计数（Array == 严格 FIFO）
/// 2. 五个非 `.window` 模式在 v0.2 阶段 fallback 到 window sink 并返回 `.delivered`
/// 3. `.window` 调用真的转发到注入的 sink（spy WindowSink 验证 args）
/// 4. 不同 invocationId 在 sink 内严格隔离（不串流）
/// 5. WindowSink 抛错时 `OutputDispatcher.handle(...)` 透传
final class OutputDispatcherTests: XCTestCase {

    // MARK: - Cell 1: .window 顺序与计数

    /// `.window` 模式按调用顺序投递 chunk，sink 内 Array == 应严格匹配
    func test_handle_windowMode_chunksDeliveredInOrder() async throws {
        let sink = InMemoryWindowSink()
        let sut = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()

        // 顺序投递三个 chunk，全部应返回 .delivered
        for chunk in ["a", "b", "c"] {
            let outcome = try await sut.handle(
                chunk: chunk,
                mode: .window,
                invocationId: invocationId
            )
            XCTAssertEqual(outcome, .delivered, "每次 .window handle 都应返回 .delivered")
        }

        // 用 Array == 比较顺序与计数（plan 明确：禁止 Set 比较）
        let received = await sink.receivedChunks(for: invocationId)
        XCTAssertEqual(received, ["a", "b", "c"], "sink 应保留 chunk 原始顺序")
    }

    // MARK: - Cell 2: 五个非 .window 模式 fallback 到 .window sink

    /// `.bubble` 模式应 fallback 到 window sink，并返回 .delivered
    func test_handle_bubbleMode_fallsBackToWindowSink() async throws {
        try await assertFallsBack(mode: .bubble)
    }

    /// `.replace` 模式应 fallback 到 window sink，并返回 .delivered
    func test_handle_replaceMode_fallsBackToWindowSink() async throws {
        try await assertFallsBack(mode: .replace)
    }

    /// `.file` 模式应 fallback 到 window sink，并返回 .delivered
    func test_handle_fileMode_fallsBackToWindowSink() async throws {
        try await assertFallsBack(mode: .file)
    }

    /// `.silent` 模式应 fallback 到 window sink，并返回 .delivered
    func test_handle_silentMode_fallsBackToWindowSink() async throws {
        try await assertFallsBack(mode: .silent)
    }

    /// `.structured` 模式应 fallback 到 window sink，并返回 .delivered
    func test_handle_structuredMode_fallsBackToWindowSink() async throws {
        try await assertFallsBack(mode: .structured)
    }

    /// 防御回归：非 .window 模式在真实 sink 未实现前必须 fallback，避免用户丢输出。
    func test_handle_nonWindowModes_fallbacksToWindowSink() async throws {
        let sink = SpyWindowSink()
        let sut = OutputDispatcher(windowSink: sink)

        // 遍历所有非 .window 模式各调一次
        for mode in DisplayMode.allCases where mode != .window {
            let outcome = try await sut.handle(chunk: "fallback", mode: mode, invocationId: UUID())
            XCTAssertEqual(outcome, .delivered, "\(mode) fallback 成功时应返回 .delivered")
        }

        let calls = await sink.calls
        XCTAssertEqual(calls.count, 5, "五个非 .window 模式都应触达 windowSink，实际调用 \(calls.count) 次")
        XCTAssertTrue(calls.allSatisfy { $0.chunk == "fallback" }, "fallback chunk 应原样透传")
    }

    // MARK: - Cell 3: .window 调用透传到 sink

    /// 验证 dispatcher 真的把 `(chunk, invocationId)` 透传给 sink，没有改写
    func test_handle_windowMode_callsWindowSinkWithCorrectArgs() async throws {
        let sink = SpyWindowSink()
        let sut = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()

        _ = try await sut.handle(chunk: "hello", mode: .window, invocationId: invocationId)

        let calls = await sink.calls
        XCTAssertEqual(calls.count, 1, "sink.append 应被调用 1 次")
        XCTAssertEqual(calls.first?.chunk, "hello", "chunk 应原样透传")
        XCTAssertEqual(calls.first?.invocationId, invocationId, "invocationId 应原样透传")
    }

    // MARK: - Cell 4: 不同 invocationId 在 sink 内严格隔离

    /// 两个 invocation 交错投递，sink 应分别保留各自序列且不交叉
    func test_handle_differentInvocations_isolatedInSink() async throws {
        let sink = InMemoryWindowSink()
        let sut = OutputDispatcher(windowSink: sink)
        let id1 = UUID()
        let id2 = UUID()

        // 交错投递：id1 → id2 → id1
        _ = try await sut.handle(chunk: "x", mode: .window, invocationId: id1)
        _ = try await sut.handle(chunk: "y", mode: .window, invocationId: id2)
        _ = try await sut.handle(chunk: "z", mode: .window, invocationId: id1)

        let chunks1 = await sink.receivedChunks(for: id1)
        let chunks2 = await sink.receivedChunks(for: id2)
        XCTAssertEqual(chunks1, ["x", "z"], "id1 应只收到 [x, z]，按原顺序")
        XCTAssertEqual(chunks2, ["y"], "id2 应只收到 [y]")
    }

    // MARK: - Cell 5: WindowSink 抛错时 dispatcher 透传

    /// sink 内部抛错时，`OutputDispatcher.handle(...)` 应原样透传 error，不吞错
    func test_handle_windowMode_sinkThrows_propagatesError() async throws {
        let sink = SpyWindowSink()
        await sink.setShouldThrow(true)
        let sut = OutputDispatcher(windowSink: sink)

        do {
            _ = try await sut.handle(chunk: "boom", mode: .window, invocationId: UUID())
            XCTFail("sink 抛错时 dispatcher 应透传，但调用成功返回了")
        } catch let error as SliceError {
            // 期望透传 SpyWindowSink 注入的 .configuration(.validationFailed) 错误
            guard case .configuration(.validationFailed(let msg)) = error else {
                XCTFail("透传的 SliceError 应为 .configuration(.validationFailed)，实际：\(error)")
                return
            }
            XCTAssertTrue(
                msg.contains("spy sink injected error"),
                "msg 应保留 spy 注入的描述：\(msg)"
            )
        } catch {
            XCTFail("应透传 SliceError，实际收到 \(type(of: error)): \(error)")
        }
    }

    // MARK: - Helpers

    /// 参数化辅助：对指定 `mode` 断言 fallback 到 window sink 且返回 `.delivered`
    ///
    /// - Parameter mode: 要测试的非 window `DisplayMode`
    private func assertFallsBack(mode: DisplayMode) async throws {
        let sink = SpyWindowSink()
        let sut = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()
        let outcome = try await sut.handle(chunk: "test", mode: mode, invocationId: invocationId)

        XCTAssertEqual(outcome, .delivered, "\(mode) fallback 成功时应返回 .delivered")
        let calls = await sink.calls
        XCTAssertEqual(calls.count, 1, "\(mode) 应调用 windowSink 一次")
        XCTAssertEqual(calls.first?.chunk, "test", "chunk 应原样透传")
        XCTAssertEqual(calls.first?.invocationId, invocationId, "invocationId 应原样透传")
    }
}

/// 测试用 spy sink；记录调用栈，可注入抛错行为。
///
/// `actor` 隔离与 `InMemoryWindowSink` 一致，避免并发写交错。
private actor SpyWindowSink: WindowSinkProtocol {

    /// 累计的 (chunk, invocationId) 调用栈
    private(set) var calls: [(chunk: String, invocationId: UUID)] = []

    /// 是否在下次 `append(...)` 时抛 SliceError；测试用
    private(set) var shouldThrow: Bool = false

    /// 切换抛错开关
    func setShouldThrow(_ value: Bool) {
        shouldThrow = value
    }

    /// 实现 `WindowSinkProtocol.append`：可选抛错或记录调用
    func append(chunk: String, invocationId: UUID) async throws {
        if shouldThrow {
            // 注入 SliceError 而非自定义 enum，验证 OutputDispatcher 透传不变形
            throw SliceError.configuration(.validationFailed("spy sink injected error"))
        }
        calls.append((chunk: chunk, invocationId: invocationId))
    }
}
