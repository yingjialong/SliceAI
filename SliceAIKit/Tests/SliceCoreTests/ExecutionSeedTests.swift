import XCTest
@testable import SliceCore

final class ExecutionSeedTests: XCTestCase {

    private func makeSeed(dryRun: Bool = false) -> ExecutionSeed {
        ExecutionSeed(
            invocationId: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            selection: SelectionSnapshot(text: "hi", source: .accessibility, length: 2, language: "en", contentType: .prose),
            frontApp: AppSnapshot(bundleId: "com.apple.Safari", name: "Safari", url: nil, windowTitle: nil),
            screenAnchor: .zero,
            timestamp: Date(timeIntervalSince1970: 100),
            triggerSource: .floatingToolbar,
            isDryRun: dryRun
        )
    }

    func test_init_preservesAllFields() throws {
        let seed = makeSeed()
        let expectedId = try XCTUnwrap(UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
        XCTAssertEqual(seed.invocationId, expectedId)
        XCTAssertEqual(seed.selection.text, "hi")
        XCTAssertEqual(seed.frontApp.bundleId, "com.apple.Safari")
        XCTAssertEqual(seed.triggerSource, .floatingToolbar)
        XCTAssertFalse(seed.isDryRun)
    }

    func test_init_dryRunFlagCarriedThrough() {
        let seed = makeSeed(dryRun: true)
        XCTAssertTrue(seed.isDryRun)
    }

    func test_equality_sameFields_isEqual() {
        XCTAssertEqual(makeSeed(), makeSeed())
    }

    func test_equality_differentInvocationId_isNotEqual() {
        let a = makeSeed()
        let b = ExecutionSeed(
            invocationId: UUID(),       // 随机
            selection: a.selection, frontApp: a.frontApp,
            screenAnchor: a.screenAnchor, timestamp: a.timestamp,
            triggerSource: a.triggerSource, isDryRun: a.isDryRun
        )
        XCTAssertNotEqual(a, b)
    }

    func test_codable_roundtrip() throws {
        let seed = makeSeed(dryRun: true)
        let data = try JSONEncoder().encode(seed)
        let decoded = try JSONDecoder().decode(ExecutionSeed.self, from: data)
        XCTAssertEqual(seed, decoded)
    }

    // INV-6 / 值语义：ExecutionSeed 必须是 `struct` 而非 `class`，这样两份 seed
    // 自然独立、跨 actor 边界复制不共享 state。`let` 不变性由编译器静态保证
    // （见源文件 7 个 `public let` 声明），运行时无法观测，此测试只锁定"值类型"选择。
    func test_typeIsStruct_forValueSemantics() {
        let mirror = Mirror(reflecting: makeSeed())
        XCTAssertEqual(mirror.displayStyle, .struct,
                       "ExecutionSeed must remain a value type; reference-type semantics would violate INV-6")
    }
}
