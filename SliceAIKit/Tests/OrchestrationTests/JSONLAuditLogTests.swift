import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// JSONLAuditLog actor 单元测试
///
/// 覆盖矩阵（plan §Task 9 测试矩阵最低要求）：
/// 1. 1000 条 .invocationCompleted 顺序 append + read FIFO 验证
/// 2. AuditEntry 三 case 全 round-trip（含 ISO8601 Date 编解码）
/// 3. Redaction 触发：含 sk- API key 的 toolId 落盘后不应残留原文
/// 4. clear() 清空文件后第一条是 .logCleared(at:) 事件
/// 5. schema 防泄漏 sanity check：InvocationReport 反射断言无 selectionText 字段
final class JSONLAuditLogTests: XCTestCase {

    // MARK: - Lifecycle

    /// 临时 audit jsonl 文件路径；setUp 注册，tearDown 清理
    private var fileURL: URL!  // swiftlint:disable:this implicitly_unwrapped_optional
    /// 被测 actor 实例；setUp 创建，tearDown 释放
    private var sut: JSONLAuditLog!  // swiftlint:disable:this implicitly_unwrapped_optional

    /// 每个 test 前在 NSTemporaryDirectory 下生成唯一 jsonl 文件，避免并行测试串扰
    override func setUp() async throws {
        try await super.setUp()
        fileURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-audit-test-\(UUID().uuidString).jsonl")
        sut = try JSONLAuditLog(fileURL: fileURL)
    }

    /// 释放 actor 引用 + 删除临时文件，避免 CI 长期跑积累垃圾
    override func tearDown() async throws {
        sut = nil
        if let url = fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        fileURL = nil
        try await super.tearDown()
    }

    // MARK: - 1. FIFO 顺序

    /// 1000 条 invocationCompleted 顺序 append → read(limit: 1000) 必须完全等于 append 顺序
    func test_append1000Entries_readReturnsInOrder() async throws {
        // 用递增 toolId 标记每条 entry 的 append 序号
        var expectedToolIds: [String] = []
        for i in 0..<1000 {
            let toolId = "tool.\(i)"
            expectedToolIds.append(toolId)
            try await sut.append(.invocationCompleted(.stub(toolId: toolId)))
        }

        let read = try await sut.read(limit: 1000)
        XCTAssertEqual(read.count, 1000)

        // 抽取 read 出的 toolId 序列与 append 顺序对比
        let readToolIds: [String] = read.compactMap { entry in
            if case .invocationCompleted(let report) = entry { return report.toolId }
            return nil
        }
        XCTAssertEqual(readToolIds, expectedToolIds)
    }

    // MARK: - 2. 三 case round-trip

    /// invocationCompleted(.success) round-trip
    func test_invocationCompleted_success_roundTrips() async throws {
        let original = AuditEntry.invocationCompleted(.stub(toolId: "test.success", outcome: .success))
        try await sut.append(original)
        let read = try await sut.read(limit: 10)
        XCTAssertEqual(read.count, 1)
        XCTAssertEqual(read.first, original)
    }

    /// invocationCompleted(.failed(errorKind:)) round-trip——验证 enum associated value 正确编解码
    func test_invocationCompleted_failed_roundTrips() async throws {
        let original = AuditEntry.invocationCompleted(
            .stub(toolId: "test.failed", outcome: .failed(errorKind: .permission))
        )
        try await sut.append(original)
        let read = try await sut.read(limit: 10)
        XCTAssertEqual(read.first, original)
    }

    /// invocationCompleted(.dryRunCompleted) round-trip
    func test_invocationCompleted_dryRun_roundTrips() async throws {
        let original = AuditEntry.invocationCompleted(
            .stub(toolId: "test.dryRun", outcome: .dryRunCompleted)
        )
        try await sut.append(original)
        let read = try await sut.read(limit: 10)
        XCTAssertEqual(read.first, original)
    }

    /// sideEffectTriggered(.copyToClipboard) round-trip——单 case 无关联值
    func test_sideEffectTriggered_copyToClipboard_roundTrips() async throws {
        let executedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = AuditEntry.sideEffectTriggered(
            invocationId: UUID(),
            sideEffect: .copyToClipboard,
            executedAt: executedAt
        )
        try await sut.append(original)
        let read = try await sut.read(limit: 10)
        XCTAssertEqual(read.first, original)
    }

    /// sideEffectTriggered(.callMCP) round-trip——含 String 关联值（params dict）
    /// params 不含敏感字段，确保普通参数原样保留
    func test_sideEffectTriggered_callMCP_roundTrips() async throws {
        let executedAt = Date(timeIntervalSince1970: 1_700_000_000)
        let original = AuditEntry.sideEffectTriggered(
            invocationId: UUID(),
            sideEffect: .callMCP(
                ref: MCPToolRef(server: "postgres", tool: "query"),
                params: ["sql": "SELECT 1", "timeout": "30"]
            ),
            executedAt: executedAt
        )
        try await sut.append(original)
        let read = try await sut.read(limit: 10)
        XCTAssertEqual(read.first, original)
    }

    /// logCleared(at:) round-trip
    func test_logCleared_roundTrips() async throws {
        let at = Date(timeIntervalSince1970: 1_700_000_000)
        let original = AuditEntry.logCleared(at: at)
        try await sut.append(original)
        let read = try await sut.read(limit: 10)
        XCTAssertEqual(read.first, original)
    }

    // MARK: - 3. Redaction 触发

    /// toolId 含 sk- 风格 API key 时，落盘文件不应残留 key 原文
    func test_append_withApiKeyInToolId_scrubbedInFile() async throws {
        let report = InvocationReport.stub(toolId: "tool-with-sk-1234567890abcdefghij")
        try await sut.append(.invocationCompleted(report))

        // 直接读文件原文做断言（绕过 read API 的 decode 路径，验证物理落盘脱敏）
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(content.contains("sk-1234567890abcdefghij"), "落盘文件不应含 API key 原文")
        XCTAssertTrue(content.contains("<redacted>"), "落盘文件应含 <redacted> 标记")
    }

    /// SideEffect.appendToFile 的 path / header 含敏感字段时也应脱敏
    func test_append_sideEffectAppendToFile_pathScrubbed() async throws {
        let entry = AuditEntry.sideEffectTriggered(
            invocationId: UUID(),
            sideEffect: .appendToFile(
                path: "/tmp/sk-1234567890abcdefghij.log",
                header: "Authorization: Bearer my.jwt.token"
            ),
            executedAt: Date()
        )
        try await sut.append(entry)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(content.contains("sk-1234567890abcdefghij"))
        XCTAssertFalse(content.contains("my.jwt.token"))
    }

    /// SideEffect.callMCP 的 params values 含敏感字段时也应脱敏
    func test_append_sideEffectCallMCP_paramsValueScrubbed() async throws {
        let entry = AuditEntry.sideEffectTriggered(
            invocationId: UUID(),
            sideEffect: .callMCP(
                ref: MCPToolRef(server: "github", tool: "createIssue"),
                params: ["token": "Bearer secret.jwt.value", "repo": "foo/bar"]
            ),
            executedAt: Date()
        )
        try await sut.append(entry)
        let content = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertFalse(content.contains("secret.jwt.value"))
        // 非敏感字段应保留
        XCTAssertTrue(content.contains("foo/bar"))
        // server / tool ref 是稳定标识符，不脱敏
        XCTAssertTrue(content.contains("github"))
        XCTAssertTrue(content.contains("createIssue"))
    }

    // MARK: - 4. clear() 留痕

    /// clear() 清空原有 entries → 文件第一条必须是 .logCleared
    func test_clear_writesLogClearedAsFirstEntry() async throws {
        // 先写 3 条普通 entry
        for i in 0..<3 {
            try await sut.append(.invocationCompleted(.stub(toolId: "before.\(i)")))
        }
        let beforeClear = try await sut.read(limit: 10)
        XCTAssertEqual(beforeClear.count, 3)

        // clear 后只剩 1 条 .logCleared
        try await sut.clear()
        let afterClear = try await sut.read(limit: 10)
        XCTAssertEqual(afterClear.count, 1)

        guard case .logCleared = afterClear[0] else {
            XCTFail("clear() 后第一条 entry 必须是 .logCleared，实际：\(afterClear[0])")
            return
        }
    }

    // MARK: - 5. Schema 防泄漏 sanity check

    /// InvocationReport 字段反射断言：禁止任何 selection 原文相关字段名
    ///
    /// 防御深度：未来若有人在 InvocationReport 加 selectionText / originalText 等字段，
    /// 本测试编译期不会报错但会运行期 fail，作为 schema 层面的 last-resort 守卫
    func test_invocationReport_hasNoSelectionTextField_byReflection() {
        let report = InvocationReport.stub(toolId: "test")
        let mirror = Mirror(reflecting: report)
        let labels = mirror.children.compactMap { $0.label }

        // 禁止的字段名清单——任一出现都说明 schema 被污染
        let forbiddenLabels: Set<String> = [
            "selectionText", "selection_text",
            "originalText", "original_text",
            "rawSelection", "raw_selection",
            "selectionContent", "selection_content"
        ]

        for label in labels {
            XCTAssertFalse(
                forbiddenLabels.contains(label),
                "InvocationReport 出现禁止字段 '\(label)'——会让 selection 原文泄漏到 audit jsonl"
            )
        }
    }

    // MARK: - 6. 边界 / 空集

    /// 文件刚创建（空）时 read 返回空数组，不报错
    func test_read_onEmptyFile_returnsEmptyArray() async throws {
        let read = try await sut.read(limit: 100)
        XCTAssertEqual(read.count, 0)
    }

    /// limit = 0 返回空数组（不报错）
    func test_read_withZeroLimit_returnsEmpty() async throws {
        try await sut.append(.invocationCompleted(.stub(toolId: "any")))
        let read = try await sut.read(limit: 0)
        XCTAssertEqual(read.count, 0)
    }

    /// limit > 实际条数时返回所有
    func test_read_withLimitExceedingCount_returnsAll() async throws {
        for i in 0..<5 {
            try await sut.append(.invocationCompleted(.stub(toolId: "t.\(i)")))
        }
        let read = try await sut.read(limit: 100)
        XCTAssertEqual(read.count, 5)
    }
}
