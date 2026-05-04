import Foundation
import XCTest
@testable import Orchestration

/// F9.2 single-flight invocation 隔离契约，直接测试真实 `InvocationGate`。
///
/// 这里不使用 spy adapter 复制契约，避免测试通过但生产 adapter 没有真正接入 gate 的假阳性。
@MainActor
final class InvocationGateTests: XCTestCase {

    /// overlapping invocations：切换到 B 后，A 的 stale chunk 必须被拒绝。
    func test_overlappingInvocations_dropStale() {
        let gate = InvocationGate()
        let a = UUID()
        let b = UUID()

        gate.setActiveInvocation(a)
        XCTAssertTrue(gate.shouldAccept(invocationId: a))
        XCTAssertFalse(gate.shouldAccept(invocationId: b))

        gate.setActiveInvocation(b)
        XCTAssertFalse(gate.shouldAccept(invocationId: a))
        XCTAssertTrue(gate.shouldAccept(invocationId: b))
    }

    /// clearActiveInvocation(ifCurrent:) 只能清理当前 invocation，不能误清别人。
    func test_clearIfCurrent_guard() {
        let gate = InvocationGate()
        let a = UUID()
        let b = UUID()

        gate.setActiveInvocation(a)
        gate.clearActiveInvocation(ifCurrent: b)
        XCTAssertTrue(gate.shouldAccept(invocationId: a))

        gate.clearActiveInvocation(ifCurrent: a)
        XCTAssertFalse(gate.shouldAccept(invocationId: a))
    }

    /// R2 race regression：A 的 defer 晚到时，不能把已经 active 的 B 清掉。
    func test_staleClearAfterSwitch_doesNotEvictNew() {
        let gate = InvocationGate()
        let a = UUID()
        let b = UUID()

        gate.setActiveInvocation(a)
        gate.setActiveInvocation(b)
        gate.clearActiveInvocation(ifCurrent: a)

        XCTAssertTrue(gate.shouldAccept(invocationId: b))
    }

    /// 用户在首个 chunk 到达前 dismiss 后，后续 chunk 必须全部拒绝。
    func test_dismissBeforeFirstChunk() {
        let gate = InvocationGate()
        let a = UUID()

        gate.setActiveInvocation(a)
        gate.clearActiveInvocation(ifCurrent: a)

        XCTAssertFalse(gate.shouldAccept(invocationId: a))
    }

    /// setActive 后立刻到达的首个 chunk 必须被接受。
    func test_setActiveThenFirstChunk() {
        let gate = InvocationGate()
        let a = UUID()

        gate.setActiveInvocation(a)

        XCTAssertTrue(gate.shouldAccept(invocationId: a))
    }

    /// active invocation 的 gatedAppend 必须调用 sink 一次。
    func test_gatedAppend_active_callsSink() {
        let gate = InvocationGate()
        let a = UUID()
        gate.setActiveInvocation(a)

        var received: [String] = []
        gate.gatedAppend(chunk: "hello", invocationId: a) { received.append($0) }

        XCTAssertEqual(received, ["hello"])
    }

    /// stale invocation 的 gatedAppend 必须静默丢弃，不调用 sink。
    func test_gatedAppend_stale_skipsSink() {
        let gate = InvocationGate()
        let a = UUID()
        let b = UUID()
        gate.setActiveInvocation(b)

        var received: [String] = []
        gate.gatedAppend(chunk: "stale-A", invocationId: a) { received.append($0) }

        XCTAssertTrue(received.isEmpty)
    }

    /// clear 后的 gatedAppend 必须静默丢弃，不调用 sink。
    func test_gatedAppend_afterClear_skipsSink() {
        let gate = InvocationGate()
        let a = UUID()

        gate.setActiveInvocation(a)
        gate.clearActiveInvocation(ifCurrent: a)

        var received: [String] = []
        gate.gatedAppend(chunk: "post-dismiss", invocationId: a) { received.append($0) }

        XCTAssertTrue(received.isEmpty)
    }
}
