import XCTest
@testable import SliceCore

final class ProviderSelectionTests: XCTestCase {

    func test_fixed_preservesProviderAndModel() {
        let sel = ProviderSelection.fixed(providerId: "openai-official", modelId: "gpt-5")
        if case .fixed(let p, let m) = sel {
            XCTAssertEqual(p, "openai-official")
            XCTAssertEqual(m, "gpt-5")
        } else {
            XCTFail("expected .fixed")
        }
    }

    func test_fixed_nilModel_allowed() {
        let sel = ProviderSelection.fixed(providerId: "p", modelId: nil)
        if case .fixed(_, let m) = sel {
            XCTAssertNil(m)
        } else {
            XCTFail()
        }
    }

    func test_capability_preservesRequiresAndPrefer() {
        let sel = ProviderSelection.capability(
            requires: [.toolCalling, .vision],
            prefer: ["claude", "gpt"]
        )
        if case .capability(let r, let p) = sel {
            XCTAssertEqual(r, [.toolCalling, .vision])
            XCTAssertEqual(p, ["claude", "gpt"])
        } else {
            XCTFail()
        }
    }

    func test_cascade_carriesRules() {
        let rule = CascadeRule(
            when: .selectionLengthGreaterThan(8000),
            providerId: "claude",
            modelId: "haiku"
        )
        let sel = ProviderSelection.cascade(rules: [rule])
        if case .cascade(let rs) = sel {
            XCTAssertEqual(rs.count, 1)
        } else {
            XCTFail()
        }
    }

    func test_providerCapability_rawValues_stable() {
        XCTAssertEqual(ProviderCapability.promptCaching.rawValue, "promptCaching")
        XCTAssertEqual(ProviderCapability.toolCalling.rawValue, "toolCalling")
        XCTAssertEqual(ProviderCapability.vision.rawValue, "vision")
        XCTAssertEqual(ProviderCapability.extendedThinking.rawValue, "extendedThinking")
        XCTAssertEqual(ProviderCapability.grounding.rawValue, "grounding")
        XCTAssertEqual(ProviderCapability.jsonSchemaOutput.rawValue, "jsonSchemaOutput")
        XCTAssertEqual(ProviderCapability.longContext.rawValue, "longContext")
    }

    func test_codable_roundtrip_fixed() throws {
        let sel = ProviderSelection.fixed(providerId: "openai", modelId: "gpt-5")
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(ProviderSelection.self, from: data)
        XCTAssertEqual(sel, decoded)
    }

    func test_codable_roundtrip_capability() throws {
        let sel = ProviderSelection.capability(requires: [.toolCalling], prefer: ["anthropic"])
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(ProviderSelection.self, from: data)
        XCTAssertEqual(sel, decoded)
    }

    func test_codable_roundtrip_cascade() throws {
        let rule = CascadeRule(when: .isCode, providerId: "claude", modelId: "sonnet")
        let sel = ProviderSelection.cascade(rules: [rule])
        let data = try JSONEncoder().encode(sel)
        let decoded = try JSONDecoder().decode(ProviderSelection.self, from: data)
        XCTAssertEqual(sel, decoded)
    }

    // MARK: - Golden JSON shape（模板 D）

    func test_providerSelection_goldenJSON_fixed_nestedStruct() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let sel = ProviderSelection.fixed(providerId: "openai", modelId: "gpt-5")
        let json = try XCTUnwrap(String(data: try enc.encode(sel), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"fixed":{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""providerId":"openai""#))
        XCTAssertTrue(json.contains(#""modelId":"gpt-5""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_providerSelection_goldenJSON_capability_requiresArraySorted() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        // 手写 Codable 把 requires Set 按 rawValue 排序后写 Array
        let sel = ProviderSelection.capability(
            requires: [.vision, .toolCalling, .promptCaching],  // 乱序输入
            prefer: ["claude"]
        )
        let json = try XCTUnwrap(String(data: try enc.encode(sel), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"capability":{"#), "got: \(json)")
        // 排序后：promptCaching < toolCalling < vision（按字母序）
        XCTAssertTrue(json.contains(#""requires":["promptCaching","toolCalling","vision"]"#), "requires 未按 rawValue 字母序排列，got: \(json)")
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_providerSelection_goldenJSON_cascade_arrayOfRules() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let sel = ProviderSelection.cascade(rules: [
            CascadeRule(when: .isCode, providerId: "claude", modelId: "sonnet"),
            CascadeRule(when: .selectionLengthGreaterThan(8000), providerId: "anthropic-fast", modelId: nil)
        ])
        let json = try XCTUnwrap(String(data: try enc.encode(sel), encoding: .utf8))
        XCTAssertTrue(json.hasPrefix(#"{"cascade":[{"#), "got: \(json)")
        XCTAssertTrue(json.contains(#""when":{"isCode":{}}"#), "missing .isCode CascadeRule, got: \(json)")
        XCTAssertTrue(json.contains(#""when":{"selectionLengthGreaterThan":8000}"#), "missing .selectionLengthGreaterThan CascadeRule, got: \(json)")
        XCTAssertTrue(json.contains(#""providerId":"claude""#))
        XCTAssertTrue(json.contains(#""providerId":"anthropic-fast""#))
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_providerSelection_goldenJSON_capability_emptyRequires_emptyPrefer() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        // 允许的 edge case：tool 声明无特定能力需求（任何 provider 都接受）
        let sel = ProviderSelection.capability(requires: [], prefer: [])
        let json = try XCTUnwrap(String(data: try enc.encode(sel), encoding: .utf8))
        XCTAssertEqual(json, #"{"capability":{"prefer":[],"requires":[]}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_providerSelection_goldenJSON_cascade_emptyRules() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        // 允许的 edge case：无级联规则（实际上等价于没有匹配路径）
        let sel = ProviderSelection.cascade(rules: [])
        let json = try XCTUnwrap(String(data: try enc.encode(sel), encoding: .utf8))
        XCTAssertEqual(json, #"{"cascade":[]}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_conditionExpr_goldenJSON_always_emptyObject() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(ConditionExpr.always), encoding: .utf8))
        XCTAssertEqual(json, #"{"always":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_conditionExpr_goldenJSON_selectionLength_directInt() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(ConditionExpr.selectionLengthGreaterThan(8000)), encoding: .utf8))
        XCTAssertEqual(json, #"{"selectionLengthGreaterThan":8000}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_conditionExpr_goldenJSON_isCode_emptyObject() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(ConditionExpr.isCode), encoding: .utf8))
        XCTAssertEqual(json, #"{"isCode":{}}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_conditionExpr_goldenJSON_languageEquals_directString() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(ConditionExpr.languageEquals("zh-CN")), encoding: .utf8))
        XCTAssertEqual(json, #"{"languageEquals":"zh-CN"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    func test_conditionExpr_goldenJSON_appBundleIdEquals_directString() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let json = try XCTUnwrap(String(data: try enc.encode(ConditionExpr.appBundleIdEquals("com.apple.Safari")), encoding: .utf8))
        XCTAssertEqual(json, #"{"appBundleIdEquals":"com.apple.Safari"}"#)
        XCTAssertFalse(json.contains("\"_0\""))
    }

    // MARK: - CascadeRule golden JSON（auto-synth struct；锁 key 名与 nil modelId 行为）

    func test_cascadeRule_goldenJSON_withModelId() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let rule = CascadeRule(when: .isCode, providerId: "claude", modelId: "sonnet")
        let json = try XCTUnwrap(String(data: try enc.encode(rule), encoding: .utf8))
        XCTAssertEqual(json, #"{"modelId":"sonnet","providerId":"claude","when":{"isCode":{}}}"#)
    }

    func test_cascadeRule_goldenJSON_nilModelId_omitsKey() throws {
        let enc = JSONEncoder(); enc.outputFormatting = [.sortedKeys]
        let rule = CascadeRule(when: .always, providerId: "openai", modelId: nil)
        let json = try XCTUnwrap(String(data: try enc.encode(rule), encoding: .utf8))
        // Foundation 默认 encoder 对 nil 可选值的行为：key 省略（-> 无 "modelId" 键）
        XCTAssertEqual(json, #"{"providerId":"openai","when":{"always":{}}}"#)
        XCTAssertFalse(json.contains("\"modelId\""), "nil modelId 应省略 key，got: \(json)")
    }

    // MARK: - Decoder negative tests（canonical 单键 + 未知键拒绝；Task 3/8/10 同款纪律）

    func test_providerSelection_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProviderSelection.self, from: data))
    }

    func test_providerSelection_decode_unknownKey_throws() {
        let data = Data(#"{"bogus":{}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProviderSelection.self, from: data))
    }

    func test_providerSelection_decode_twoKeys_throws() {
        let data = Data(#"{"fixed":{"providerId":"a","modelId":null},"cascade":[]}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ProviderSelection.self, from: data))
    }

    func test_conditionExpr_decode_emptyObject_throws() {
        let data = Data("{}".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ConditionExpr.self, from: data))
    }

    func test_conditionExpr_decode_unknownKey_throws() {
        let data = Data(#"{"bogus":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ConditionExpr.self, from: data))
    }

    func test_conditionExpr_decode_twoKeys_throws() {
        let data = Data(#"{"always":{},"isCode":{}}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(ConditionExpr.self, from: data))
    }
}
