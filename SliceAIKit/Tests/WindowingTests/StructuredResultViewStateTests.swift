import XCTest
@testable import Windowing

/// structured 结果解析与 bubble 展示状态测试。
final class StructuredResultViewStateTests: XCTestCase {

    /// JSON object 解析应覆盖字符串、数字、布尔、数组、对象和 null。
    func test_parseStructuredObject_supportsStringNumberBoolArrayAndObject() throws {
        let fields = try StructuredResultParser.parseObject(from: """
        {
          "name": "Maya",
          "score": 9.5,
          "passed": true,
          "tags": ["grammar", "tone"],
          "details": {
            "level": "B2"
          },
          "missing": null
        }
        """)

        XCTAssertEqual(fields, [
            StructuredField(key: "details", value: .object([
                StructuredField(key: "level", value: .string("B2"))
            ])),
            StructuredField(key: "missing", value: .null),
            StructuredField(key: "name", value: .string("Maya")),
            StructuredField(key: "passed", value: .bool(true)),
            StructuredField(key: "score", value: .number(9.5)),
            StructuredField(key: "tags", value: .array([
                .string("grammar"),
                .string("tone")
            ]))
        ])
    }

    /// 非法 JSON 应返回受控解析错误，不能崩溃或展示原始异常。
    func test_parseStructuredObject_returnsFailureForInvalidJSON() throws {
        XCTAssertThrowsError(try StructuredResultParser.parseObject(from: "{not json")) { error in
            XCTAssertEqual(error as? StructuredResultParseError, .invalidJSON)
        }
    }

    /// bubble 完成后应按固定延迟自动进入隐藏状态。
    func test_bubbleState_autoDismissesAfterFinishDelay() async throws {
        var state = BubblePresentationState()
        let startedAt = Date(timeIntervalSince1970: 1_800_000_000)

        state.show(text: "Done", now: startedAt)
        XCTAssertTrue(state.isVisible)
        XCTAssertEqual(state.text, "Done")
        XCTAssertNil(state.dismissAt)

        state.finish(now: startedAt, autoDismissDelay: 1.2)
        XCTAssertEqual(state.dismissAt, startedAt.addingTimeInterval(1.2))

        state.update(now: startedAt.addingTimeInterval(1.1))
        XCTAssertTrue(state.isVisible)

        state.update(now: startedAt.addingTimeInterval(1.2))
        XCTAssertFalse(state.isVisible)
    }
}
