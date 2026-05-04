import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// F3.2 单一写入所有者契约。
final class SingleWriterContractTests: XCTestCase {

    /// 测试用 sink，记录 dispatcher 写入次数与顺序。
    actor SpyWindowSink: WindowSinkProtocol {
        var appendCalls: [(chunk: String, invocationId: UUID)] = []

        /// 记录一次 append 调用。
        func append(chunk: String, invocationId: UUID) async throws {
            appendCalls.append((chunk, invocationId))
        }
    }

    /// 验证 OutputDispatcher 对每个 chunk 只向 sink 写入一次。
    func test_outputDispatcher_chunkAppendOnce_perChunk() async throws {
        let sink = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()

        for chunk in ["a", "b", "c", "d", "e"] {
            _ = try await dispatcher.handle(
                chunk: chunk,
                mode: .window,
                invocationId: invocationId
            )
        }

        let calls = await sink.appendCalls
        XCTAssertEqual(calls.count, 5)
        XCTAssertEqual(calls.map(\.chunk), ["a", "b", "c", "d", "e"])
    }
}
