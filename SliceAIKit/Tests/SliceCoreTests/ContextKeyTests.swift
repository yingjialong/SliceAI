import XCTest
@testable import SliceCore

final class ContextKeyTests: XCTestCase {

    func test_rawValue_preservesString() {
        let key = ContextKey(rawValue: "file.read.result")
        XCTAssertEqual(key.rawValue, "file.read.result")
    }

    func test_equality_byRawValue() {
        XCTAssertEqual(ContextKey(rawValue: "a"), ContextKey(rawValue: "a"))
        XCTAssertNotEqual(ContextKey(rawValue: "a"), ContextKey(rawValue: "b"))
    }

    func test_hashable_usableAsDictionaryKey() {
        var map: [ContextKey: Int] = [:]
        map[ContextKey(rawValue: "x")] = 1
        map[ContextKey(rawValue: "y")] = 2
        XCTAssertEqual(map[ContextKey(rawValue: "x")], 1)
        XCTAssertEqual(map.count, 2)
    }

    func test_codable_roundtrip() throws {
        let original = ContextKey(rawValue: "vocab")
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(ContextKey.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func test_requiredness_allCases() {
        XCTAssertEqual(Requiredness.allCases.count, 2)
        XCTAssertTrue(Requiredness.allCases.contains(.required))
        XCTAssertTrue(Requiredness.allCases.contains(.optional))
    }

    func test_requiredness_codable() throws {
        let req = Requiredness.required
        let data = try JSONEncoder().encode(req)
        XCTAssertEqual(String(data: data, encoding: .utf8), "\"required\"")
    }
}
