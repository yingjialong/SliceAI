import XCTest
@testable import SliceCore

final class SelectionSnapshotTests: XCTestCase {

    func test_init_preservesAllFields() {
        let snap = SelectionSnapshot(
            text: "hello",
            source: .accessibility,
            length: 5,
            language: "en",
            contentType: .prose
        )
        XCTAssertEqual(snap.text, "hello")
        XCTAssertEqual(snap.source, .accessibility)
        XCTAssertEqual(snap.length, 5)
        XCTAssertEqual(snap.language, "en")
        XCTAssertEqual(snap.contentType, .prose)
    }

    func test_init_allowsNilOptionals() {
        let snap = SelectionSnapshot(
            text: "x",
            source: .clipboardFallback,
            length: 1,
            language: nil,
            contentType: nil
        )
        XCTAssertNil(snap.language)
        XCTAssertNil(snap.contentType)
    }

    func test_codable_roundtrip_withAllOptionals() throws {
        let snap = SelectionSnapshot(
            text: "let x = 1",
            source: .accessibility,
            length: 9,
            language: nil,
            contentType: .code
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(SelectionSnapshot.self, from: data)
        XCTAssertEqual(snap, decoded)
    }

    func test_codable_roundtrip_withFilledOptionals() throws {
        let snap = SelectionSnapshot(
            text: "https://example.com/page",
            source: .inputBox,
            length: 24,
            language: "zh-CN",
            contentType: .url
        )
        let data = try JSONEncoder().encode(snap)
        let decoded = try JSONDecoder().decode(SelectionSnapshot.self, from: data)
        XCTAssertEqual(snap, decoded)
        XCTAssertEqual(decoded.language, "zh-CN")
        XCTAssertEqual(decoded.contentType, .url)
    }

    func test_selectionContentType_allCases_stable() {
        XCTAssertEqual(Set(SelectionContentType.allCases), [
            .prose, .code, .url, .email, .json, .commitHash, .date, .other
        ])
    }

    func test_selectionOrigin_rawValues() {
        XCTAssertEqual(SelectionOrigin.accessibility.rawValue, "accessibility")
        XCTAssertEqual(SelectionOrigin.clipboardFallback.rawValue, "clipboardFallback")
        XCTAssertEqual(SelectionOrigin.inputBox.rawValue, "inputBox")
    }

    // 显式断言：SelectionSnapshot 与 SelectionPayload 是 **两个不同的类型**
    // （M1 不做 typealias 桥接；SelectionPayload 原封保留）
    func test_selectionSnapshot_isDistinctFromSelectionPayload() {
        // 两者不应互相赋值；若编译成功说明 typealias 误引入
        // 这里只做运行时类型对比，避免编译期断言
        let snap = SelectionSnapshot(text: "x", source: .accessibility, length: 1, language: nil, contentType: nil)
        XCTAssertEqual(String(describing: type(of: snap)), "SelectionSnapshot")
    }
}
