import XCTest
@testable import Capabilities

/// `MCPClientProtocol` 契约 + `MockMCPClient` 行为测试。
///
/// 覆盖矩阵（与 plan §2003 对齐）：
/// 1. tools-happy        —— 注入 [d: [ref1, ref2]] → tools(for: d) 返回完整数组
/// 2. tools-empty        —— 空 registry → tools(for: 任意 d) 返回 []
/// 3. call-happy         —— responses[ref] 命中 → 返回该 MCPCallResult
/// 4. call-notFound      —— ref 不在 responses → throw .toolNotFound(ref:)
/// 5. callResult-codable —— Codable round-trip（meta nil / 非 nil 两种）
/// 6. error-equatable    —— MCPClientError 三 case 的 == / ≠ 自检
/// 7. call-count         —— 多次 call 后 callCount 累加（含失败次数）
final class MCPClientProtocolTests: XCTestCase {

    // MARK: - Fixtures

    /// 测试常用 descriptor / ref 常量；放静态属性避免每个测试重复构造。
    private let serverA = MCPDescriptor(id: "stdio://server-a")
    private let serverB = MCPDescriptor(id: "stdio://server-b")

    private let refEcho = MCPToolRef(server: "stdio://server-a", name: "echo")
    private let refSum = MCPToolRef(server: "stdio://server-a", name: "sum")
    private let refUnknown = MCPToolRef(server: "stdio://server-a", name: "ghost")

    // MARK: - 1. tools happy

    /// 注入 [serverA: [refEcho, refSum]] → tools(for: serverA) 应原样返回（顺序保留）
    func test_tools_happyPath_returnsInjectedToolsInOrder() async throws {
        // 给定：server-a 上注册 echo + sum 两个工具
        let client = MockMCPClient(
            tools: [serverA: [refEcho, refSum]]
        )

        // 当：查询 server-a 的工具
        let result = try await client.tools(for: serverA)

        // 则：返回与注入完全一致（含顺序）
        XCTAssertEqual(result, [refEcho, refSum])
    }

    // MARK: - 2. tools empty

    /// 空 registry → 任意 descriptor 都应返回 []，而不是 throw
    /// （契约：找不到 server 是合法状态，由上层 ExecutionEngine 决定如何处理）
    func test_tools_emptyRegistry_returnsEmptyArray() async throws {
        let client = MockMCPClient()

        let result = try await client.tools(for: serverA)

        XCTAssertEqual(result, [])
    }

    /// 注入 server-a 但查 server-b → 仍返回 [] 而不是 throw
    /// （字典 miss 等价于 empty registry，行为统一）
    func test_tools_unknownDescriptor_returnsEmptyArray() async throws {
        let client = MockMCPClient(
            tools: [serverA: [refEcho]]
        )

        let result = try await client.tools(for: serverB)

        XCTAssertEqual(result, [])
    }

    // MARK: - 3. call happy

    /// responses[refEcho] 命中 → call 返回该 MCPCallResult；args 字典内容不影响匹配（Mock 不验 args）
    func test_call_happyPath_returnsInjectedResponse() async throws {
        let expected = MCPCallResult(
            content: ["echo: hi"],
            isError: false,
            meta: ["latency_ms": "12"]
        )
        let client = MockMCPClient(responses: [refEcho: expected])

        // 当：用任意 args 调 echo（Mock 故意忽略 args）
        let result = try await client.call(ref: refEcho, args: ["text": "hi"])

        XCTAssertEqual(result, expected)
    }

    // MARK: - 4. call notFound

    /// responses 不含目标 ref → throw .toolNotFound，且关联值原样回传
    func test_call_unknownRef_throwsToolNotFound() async throws {
        let client = MockMCPClient(responses: [refEcho: .init(content: ["x"], isError: false)])

        do {
            _ = try await client.call(ref: refUnknown, args: [:])
            XCTFail("expected throw .toolNotFound, got success")
        } catch let MCPClientError.toolNotFound(ref) {
            // 关联值必须原样回传，让上层日志能定位是哪个 ref miss
            XCTAssertEqual(ref, refUnknown)
        } catch {
            XCTFail("expected MCPClientError.toolNotFound, got \(error)")
        }
    }

    // MARK: - 5. MCPCallResult Codable round-trip

    /// meta 非 nil 的 round-trip：encode → decode 等价
    func test_mcpCallResult_codable_withMeta_roundTrips() throws {
        let original = MCPCallResult(
            content: ["a", "b"],
            isError: true,
            meta: ["k1": "v1", "k2": "v2"]
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPCallResult.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    /// meta 为 nil 的 round-trip：必须能正常 encode / decode（验证 Optional 字段不会在 JSON 里丢失语义）
    func test_mcpCallResult_codable_withoutMeta_roundTrips() throws {
        let original = MCPCallResult(content: ["solo"], isError: false, meta: nil)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MCPCallResult.self, from: data)

        XCTAssertEqual(decoded, original)
        XCTAssertNil(decoded.meta, "decoded.meta 应保持 nil，不应被默认值化为空字典")
    }

    // MARK: - 6. MCPClientError Equatable

    /// 三个 case 的 == / ≠ 自检；Equatable 是给测试断言 + 日志去重用，必须对 case discriminator + 关联值都敏感
    func test_mcpClientError_equatable_perCase() {
        // toolNotFound：ref 不同应 ≠
        XCTAssertEqual(
            MCPClientError.toolNotFound(ref: refEcho),
            MCPClientError.toolNotFound(ref: refEcho)
        )
        XCTAssertNotEqual(
            MCPClientError.toolNotFound(ref: refEcho),
            MCPClientError.toolNotFound(ref: refSum)
        )

        // transportFailed：reason 不同应 ≠
        XCTAssertEqual(
            MCPClientError.transportFailed(reason: "broken pipe"),
            MCPClientError.transportFailed(reason: "broken pipe")
        )
        XCTAssertNotEqual(
            MCPClientError.transportFailed(reason: "broken pipe"),
            MCPClientError.transportFailed(reason: "timeout")
        )

        // decodingFailed：reason 不同应 ≠
        XCTAssertEqual(
            MCPClientError.decodingFailed(reason: "bad json"),
            MCPClientError.decodingFailed(reason: "bad json")
        )
        XCTAssertNotEqual(
            MCPClientError.decodingFailed(reason: "bad json"),
            MCPClientError.decodingFailed(reason: "missing field")
        )

        // 跨 case 必须 ≠（即使 reason 字面量一致，case discriminator 不同）
        XCTAssertNotEqual(
            MCPClientError.transportFailed(reason: "x"),
            MCPClientError.decodingFailed(reason: "x")
        )
    }

    // MARK: - 6.5 MCPClientError.developerContext 脱敏

    /// `.toolNotFound` 的关联 ref 来自调用方代码（不会带敏感数据），developerContext 应原样含 server/name；
    /// `.transportFailed` / `.decodingFailed` 的 reason 可能携带 server 路径 / underlying error 等敏感
    /// 信息，developerContext 一律输出 `<redacted>`，与 `SliceError.developerContext` 同口径。
    func test_mcpClientError_developerContext_redactsStringPayloads() {
        let toolNotFoundCtx = MCPClientError.toolNotFound(ref: refEcho).developerContext
        XCTAssertTrue(
            toolNotFoundCtx.contains("server=stdio://server-a") && toolNotFoundCtx.contains("name=echo"),
            "toolNotFound 应原样保留 ref 字段，便于定位调用方拼写错误，实际 = \(toolNotFoundCtx)"
        )

        let transportCtx = MCPClientError.transportFailed(reason: "broken pipe to /Users/me/.ssh/key").developerContext
        XCTAssertEqual(transportCtx, "transportFailed(<redacted>)", "transportFailed reason 必须脱敏")
        XCTAssertFalse(transportCtx.contains("/Users/me"), "脱敏后不应残留任何路径片段")

        let decodingCtx = MCPClientError.decodingFailed(reason: "bad json: {\"apiKey\":\"sk-secret\"}").developerContext
        XCTAssertEqual(decodingCtx, "decodingFailed(<redacted>)", "decodingFailed reason 必须脱敏")
        XCTAssertFalse(decodingCtx.contains("sk-secret"), "脱敏后不应残留任何 secret")
    }

    // MARK: - 7. callCount

    /// 多次 call 后 callCount 应累加；包括失败的 .toolNotFound 也计数
    /// （契约：callCount 是"caller 发起调用次数"，不是"成功次数"）
    func test_call_callCount_incrementsForBothSuccessAndFailure() async throws {
        let client = MockMCPClient(responses: [refEcho: .init(content: ["ok"], isError: false)])

        // 起始：0
        let countBefore = await client.callCount
        XCTAssertEqual(countBefore, 0)

        // 1 次成功
        _ = try await client.call(ref: refEcho, args: [:])
        // 1 次失败（toolNotFound）
        do {
            _ = try await client.call(ref: refUnknown, args: [:])
        } catch {
            // 期望 throw，不打 XCTFail
        }
        // 又 1 次成功
        _ = try await client.call(ref: refEcho, args: ["k": "v"])

        // 累计应为 3（2 成功 + 1 失败）
        let countAfter = await client.callCount
        XCTAssertEqual(countAfter, 3, "callCount 应累计 3 次（含 1 次失败）")
    }
}
