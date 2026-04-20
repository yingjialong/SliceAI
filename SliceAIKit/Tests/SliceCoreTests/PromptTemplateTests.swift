// SliceAIKit/Tests/SliceCoreTests/PromptTemplateTests.swift
import XCTest
@testable import SliceCore

final class PromptTemplateTests: XCTestCase {
    func test_render_replacesSingleVariable() {
        let out = PromptTemplate.render("Hello {{name}}", variables: ["name": "World"])
        XCTAssertEqual(out, "Hello World")
    }

    func test_render_multipleVariables() {
        let out = PromptTemplate.render(
            "{{a}} and {{b}} and {{a}}",
            variables: ["a": "X", "b": "Y"]
        )
        XCTAssertEqual(out, "X and Y and X")
    }

    func test_render_unknownVariableKeptAsIs() {
        // 未定义的变量保留原文，便于用户在 UI 发现错字
        let out = PromptTemplate.render("Hello {{nope}}", variables: [:])
        XCTAssertEqual(out, "Hello {{nope}}")
    }

    func test_render_emptyTemplate() {
        XCTAssertEqual(PromptTemplate.render("", variables: ["a": "b"]), "")
    }

    func test_render_variableWithSpaces() {
        // 变量名内不允许空格，有空格的占位符原样保留
        let out = PromptTemplate.render("{{ has space }}", variables: ["has space": "x"])
        XCTAssertEqual(out, "{{ has space }}")
    }

    func test_render_variableWithSpecialChars() {
        let out = PromptTemplate.render("{{selection}}", variables: ["selection": "$pecial/chars\\"])
        XCTAssertEqual(out, "$pecial/chars\\")
    }
}
