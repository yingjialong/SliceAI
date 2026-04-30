import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// F8.3 ordering + F9.2 single-flight 的 fake stream 契约测试。
@MainActor
final class ExecutionStreamOrderingTests: XCTestCase {

    /// 测试用 chunk 收集器，模拟 ResultPanel.append 的最终接收端。
    @MainActor
    final class ChunkCollector {
        var chunks: [String] = []

        /// 追加一个 chunk。
        func append(_ chunk: String) {
            chunks.append(chunk)
        }
    }

    /// 使用真实 InvocationGate.gatedAppend 的测试 sink。
    @MainActor
    final class GateBackedSpySink: WindowSinkProtocol {
        private let gate: InvocationGate
        private let collector: ChunkCollector

        /// 构造带 gate 的 spy sink。
        init(gate: InvocationGate, collector: ChunkCollector) {
            self.gate = gate
            self.collector = collector
        }

        /// 通过 InvocationGate 决定 chunk 是否进入 collector。
        func append(chunk: String, invocationId: UUID) async throws {
            gate.gatedAppend(chunk: chunk, invocationId: invocationId) { [collector] acceptedChunk in
                collector.append(acceptedChunk)
            }
        }
    }

    /// 验证先 setActive 再发首 chunk 时，首 chunk 不丢。
    func test_setActiveBeforeFirstChunk_acceptsFirst() async throws {
        let gate = InvocationGate()
        let collector = ChunkCollector()
        let sink = GateBackedSpySink(gate: gate, collector: collector)
        let dispatcher = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()

        gate.setActiveInvocation(invocationId)
        _ = try await dispatcher.handle(
            chunk: "FIRST",
            mode: .window,
            invocationId: invocationId
        )

        XCTAssertEqual(collector.chunks, ["FIRST"])
    }

    /// 验证 setActive 之前到达的 chunk 会被 gate 丢弃。
    func test_firstChunkBeforeSetActive_isDropped() async throws {
        let gate = InvocationGate()
        let collector = ChunkCollector()
        let sink = GateBackedSpySink(gate: gate, collector: collector)
        let dispatcher = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()

        _ = try await dispatcher.handle(
            chunk: "LOST",
            mode: .window,
            invocationId: invocationId
        )
        gate.setActiveInvocation(invocationId)

        XCTAssertTrue(collector.chunks.isEmpty)
    }

    /// 验证旧 invocation 的 clear 晚到不会清空新 invocation。
    func test_staleClearAfterSwitch_doesNotEvictNew() async throws {
        let gate = InvocationGate()
        let collector = ChunkCollector()
        let sink = GateBackedSpySink(gate: gate, collector: collector)
        let dispatcher = OutputDispatcher(windowSink: sink)
        let firstInvocation = UUID()
        let secondInvocation = UUID()

        gate.setActiveInvocation(firstInvocation)
        gate.setActiveInvocation(secondInvocation)
        gate.clearActiveInvocation(ifCurrent: firstInvocation)

        _ = try await dispatcher.handle(
            chunk: "B-OK",
            mode: .window,
            invocationId: secondInvocation
        )

        XCTAssertEqual(collector.chunks, ["B-OK"])
    }

    /// 验证切换到新 invocation 后，旧 invocation 的 stale event 会被拒绝。
    func test_staleEventAfterReopen_isDropped() async throws {
        let gate = InvocationGate()
        let collector = ChunkCollector()
        let sink = GateBackedSpySink(gate: gate, collector: collector)
        let dispatcher = OutputDispatcher(windowSink: sink)
        let firstInvocation = UUID()
        let secondInvocation = UUID()

        gate.setActiveInvocation(firstInvocation)
        _ = try await dispatcher.handle(
            chunk: "A-CHUNK",
            mode: .window,
            invocationId: firstInvocation
        )

        gate.setActiveInvocation(secondInvocation)
        _ = try await dispatcher.handle(
            chunk: "STALE-A-FINISH-CHUNK",
            mode: .window,
            invocationId: firstInvocation
        )
        let staleAcceptedByGate = gate.shouldAccept(invocationId: firstInvocation)
        XCTAssertFalse(staleAcceptedByGate)

        _ = try await dispatcher.handle(
            chunk: "B-CHUNK",
            mode: .window,
            invocationId: secondInvocation
        )

        XCTAssertEqual(collector.chunks, ["A-CHUNK", "B-CHUNK"])
    }
}
