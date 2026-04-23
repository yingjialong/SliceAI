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

    func test_contextValue_imageEquality_byDataAndFormat() {
        let d1 = Data([0x89, 0x50, 0x4E, 0x47])    // PNG magic
        let d2 = Data([0x89, 0x50, 0x4E, 0x47])
        let different = Data([0xFF, 0xD8, 0xFF])   // JPEG magic
        XCTAssertEqual(ContextValue.image(d1, format: "png"), ContextValue.image(d2, format: "png"))
        XCTAssertNotEqual(ContextValue.image(d1, format: "png"), ContextValue.image(different, format: "png"))
        XCTAssertNotEqual(ContextValue.image(d1, format: "png"), ContextValue.image(d1, format: "jpeg"))
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

    func test_contextValue_errorEquality_byAssociatedSliceError() {
        let same1 = ContextValue.error(.configuration(.fileNotFound))
        let same2 = ContextValue.error(.configuration(.fileNotFound))
        XCTAssertEqual(same1, same2)

        // 不同 SliceError case 必须不相等（依赖 SliceError: Equatable 自动合成）
        let other = ContextValue.error(.configuration(.invalidJSON(".")))
        XCTAssertNotEqual(same1, other)
    }

    func test_subscript_returnsNilForMissingKey() {
        let bag = ContextBag(values: [ContextKey(rawValue: "a"): .text("x")])
        XCTAssertNotNil(bag[ContextKey(rawValue: "a")])
        XCTAssertNil(bag[ContextKey(rawValue: "missing")])
    }

    func test_contextValue_crossCaseInequality() {
        // 不同 case 即便关联值看起来相近也必须不相等——锁死 Swift Equatable 合成对 case 分量的正确判定
        let textX = ContextValue.text("x")
        let jsonEmpty = ContextValue.json(Data())
        let fileTmp = ContextValue.file(URL(fileURLWithPath: "/tmp/x"), mimeType: "text/plain")
        let imageEmpty = ContextValue.image(Data(), format: "png")
        let errCase = ContextValue.error(.configuration(.fileNotFound))

        XCTAssertNotEqual(textX, jsonEmpty)
        XCTAssertNotEqual(textX, fileTmp)
        XCTAssertNotEqual(textX, imageEmpty)
        XCTAssertNotEqual(textX, errCase)
        XCTAssertNotEqual(jsonEmpty, fileTmp)
        XCTAssertNotEqual(jsonEmpty, imageEmpty)
        XCTAssertNotEqual(jsonEmpty, errCase)
        XCTAssertNotEqual(fileTmp, imageEmpty)
        XCTAssertNotEqual(fileTmp, errCase)
        XCTAssertNotEqual(imageEmpty, errCase)
    }
}
