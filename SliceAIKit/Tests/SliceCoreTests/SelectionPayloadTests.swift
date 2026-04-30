import XCTest
@testable import SliceCore

final class SelectionPayloadTests: XCTestCase {
    func test_equatableByAllFields() {
        // 两个 payload 所有字段相等时应当 ==
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let a = SelectionPayload(
            text: "hi", appBundleID: "com.apple.Safari", appName: "Safari",
            url: URL(string: "https://example.com"), screenPoint: CGPoint(x: 10, y: 20),
            source: .accessibility, timestamp: date
        )
        let b = SelectionPayload(
            text: "hi", appBundleID: "com.apple.Safari", appName: "Safari",
            url: URL(string: "https://example.com"), screenPoint: CGPoint(x: 10, y: 20),
            source: .accessibility, timestamp: date
        )
        XCTAssertEqual(a, b)
    }

    func test_sourceRawValuesStable() {
        // rawValue 是 Codable 持久化基础，必须稳定
        XCTAssertEqual(SelectionPayload.Source.accessibility.rawValue, "accessibility")
        XCTAssertEqual(SelectionPayload.Source.clipboardFallback.rawValue, "clipboardFallback")
    }

    /// 验证 SelectionPayload 能完整映射成 ExecutionSeed。
    func test_toExecutionSeed_mapsFields() {
        let timestamp = Date(timeIntervalSince1970: 1_000_000)
        let payload = SelectionPayload(
            text: "hello world",
            appBundleID: "com.apple.Safari",
            appName: "Safari",
            url: URL(string: "https://example.com"),
            screenPoint: CGPoint(x: 100, y: 200),
            source: .accessibility,
            timestamp: timestamp
        )

        let seed = payload.toExecutionSeed(triggerSource: .floatingToolbar)

        XCTAssertEqual(seed.selection.text, "hello world")
        XCTAssertEqual(seed.selection.source, .accessibility)
        XCTAssertEqual(seed.selection.length, 11)
        XCTAssertNil(seed.selection.language)
        XCTAssertNil(seed.selection.contentType)

        XCTAssertEqual(seed.frontApp.bundleId, "com.apple.Safari")
        XCTAssertEqual(seed.frontApp.name, "Safari")
        XCTAssertEqual(seed.frontApp.url?.absoluteString, "https://example.com")
        XCTAssertNil(seed.frontApp.windowTitle)

        XCTAssertEqual(seed.screenAnchor, CGPoint(x: 100, y: 200))
        XCTAssertEqual(seed.timestamp, timestamp)
        XCTAssertEqual(seed.triggerSource, .floatingToolbar)
        XCTAssertFalse(seed.isDryRun)
    }

    /// 验证 clipboard fallback 来源映射到 v2 SelectionSource。
    func test_toSelectionSource_clipboardFallback() {
        let source: SelectionPayload.Source = .clipboardFallback

        XCTAssertEqual(source.toSelectionSource(), .clipboardFallback)
    }
}
