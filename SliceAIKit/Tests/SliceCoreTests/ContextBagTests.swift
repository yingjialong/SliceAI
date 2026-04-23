import XCTest
@testable import SliceCore

final class ContextBagTests: XCTestCase {

    func test_empty_bagHasNoValues() {
        let bag = ContextBag(values: [:])
        XCTAssertNil(bag[ContextKey(rawValue: "anything")])
    }

    func test_subscript_returnsInsertedValue() {
        let key = ContextKey(rawValue: "vocab")
        let bag = ContextBag(values: [key: .text("hello")])
        if case .text(let s) = bag[key] {
            XCTAssertEqual(s, "hello")
        } else {
            XCTFail("expected .text")
        }
    }

    func test_contextValue_textEquality() {
        XCTAssertEqual(ContextValue.text("a"), ContextValue.text("a"))
        XCTAssertNotEqual(ContextValue.text("a"), ContextValue.text("b"))
    }

    func test_contextValue_jsonEquality() {
        let d1 = try! JSONSerialization.data(withJSONObject: ["x": 1])
        let d2 = try! JSONSerialization.data(withJSONObject: ["x": 1])
        XCTAssertEqual(ContextValue.json(d1), ContextValue.json(d2))
    }

    func test_contextValue_fileEquality_byURLAndMime() {
        let u = URL(fileURLWithPath: "/tmp/a.md")
        XCTAssertEqual(ContextValue.file(u, mimeType: "text/markdown"), ContextValue.file(u, mimeType: "text/markdown"))
        XCTAssertNotEqual(ContextValue.file(u, mimeType: "text/markdown"), ContextValue.file(u, mimeType: "text/plain"))
    }

    func test_contextValue_errorCase_carriesSliceError() {
        let err = SliceError.configuration(.fileNotFound)
        let val = ContextValue.error(err)
        if case .error(let e) = val {
            XCTAssertEqual(e.userMessage, err.userMessage)
        } else {
            XCTFail("expected .error")
        }
    }

    func test_containsKey_returnsFalseForMissing() {
        let bag = ContextBag(values: [ContextKey(rawValue: "a"): .text("x")])
        XCTAssertNotNil(bag[ContextKey(rawValue: "a")])
        XCTAssertNil(bag[ContextKey(rawValue: "missing")])
    }
}
