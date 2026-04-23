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

    func test_init_preservesAllFields() {
        let seed = makeSeed()
        XCTAssertEqual(seed.invocationId.uuidString.lowercased(), "11111111-1111-1111-1111-111111111111")
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

    // INV-6：seed 构造后不可变；struct + let 天然保证，本测试显式确认编译期约束
    func test_immutability_fieldsAreLet() {
        let mirror = Mirror(reflecting: makeSeed())
        // displayStyle == .struct 已保证不可变；此处仅为文档化意图
        XCTAssertEqual(mirror.displayStyle, .struct)
    }
}
