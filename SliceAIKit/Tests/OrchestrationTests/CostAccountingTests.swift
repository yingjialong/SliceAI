import Foundation
import SliceCore
import XCTest
@testable import Orchestration

/// Task 8: `CostAccounting` actor + sqlite 持久化的行为测试。
///
/// 覆盖矩阵：
/// 1. init 建表成功
/// 2. record 后 findByToolId 返回该记录
/// 3. 同 toolId 多条 → 返回全部、按 recorded_at 升序
/// 4. 多 toolId → findByToolId 仅返回匹配子集
/// 5. totalUSD(since:) 仅累加区间内记录、Decimal 精确加和
/// 6. totalUSD(since: future) → Decimal.zero
/// 7. Decimal 精度（小数位 > 9）写入后 find 等于原值
/// 8. 重复 invocationId 第二次写入抛 SliceError.configuration(.validationFailed)
final class CostAccountingTests: XCTestCase {

    // MARK: - Fixture

    /// 测试期间使用的临时数据库 URL；tearDown 删除文件。
    private var dbURL: URL!
    /// 被测 actor；setUp 建立、tearDown 释放（actor deinit 会 close db）。
    private var sut: CostAccounting!

    /// 每个测试用独立 .db 文件，避免共享磁盘状态。
    override func setUp() async throws {
        dbURL = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("sliceai-cost-test-\(UUID().uuidString).db")
        sut = try CostAccounting(dbURL: dbURL)
    }

    /// 先释放 actor 让其 deinit 关闭 sqlite 句柄，再清理磁盘文件。
    ///
    /// 注意：Swift actor 的 deinit 时序由 ARC 决定，把 sut 设 nil 即可触发引用计数归零；
    /// removeItem 在 sqlite 已关闭后执行更稳妥。
    override func tearDown() async throws {
        sut = nil
        try? FileManager.default.removeItem(at: dbURL)
        dbURL = nil
    }

    /// 构造一条 CostRecord，所有字段都可单独覆盖以便针对性测试。
    ///
    /// 默认 `recordedAt` 已对齐到毫秒整数，避免与 sqlite 列 ms 精度不匹配导致的
    /// 假 round-trip 失败（参见 CostAccounting 文档「ms 精度」说明）。
    private func makeRecord(
        invocationId: UUID = UUID(),
        toolId: String = "test.tool",
        providerId: String = "test-provider",
        model: String = "gpt-4o",
        inputTokens: Int = 100,
        outputTokens: Int = 50,
        usd: Decimal = Decimal(string: "0.0015")!,  // swiftlint:disable:this force_unwrapping
        recordedAt: Date? = nil
    ) -> CostRecord {
        // 默认时间在调用点取 now 并对齐到 ms 整数；显式传入的 recordedAt 由调用方负责对齐
        let date = recordedAt ?? Self.alignToMilliseconds(Date())
        return CostRecord(
            invocationId: invocationId,
            toolId: toolId,
            providerId: providerId,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            usd: usd,
            recordedAt: date
        )
    }

    /// 把 Date 截断到毫秒整数，与 CostAccounting 写入时的 ms 精度对齐
    private static func alignToMilliseconds(_ date: Date) -> Date {
        let millis = (date.timeIntervalSince1970 * 1000.0).rounded()
        return Date(timeIntervalSince1970: millis / 1000.0)
    }

    // MARK: - 1. init 建表成功

    /// init 在新文件上不抛错且 db 文件被创建
    func test_init_createsSchemaAndFile() async {
        // setUp 已经构造 sut；只需断言 db 文件存在
        XCTAssertTrue(FileManager.default.fileExists(atPath: dbURL.path),
                      "init 应该在指定路径创建 sqlite 文件")
        // findByToolId 在空 db 上应返回 []
        await XCTAssertNoThrowAsync {
            let results = try await self.sut.findByToolId("nonexistent")
            XCTAssertEqual(results, [], "空 db 上 findByToolId 应返回空数组")
        }
    }

    // MARK: - 2. record 后 findByToolId 返回该记录

    /// 写一条 + findByToolId 返回完全等价的记录（所有字段 round-trip 正确）
    func test_record_thenFindByToolId_returnsSameRecord() async throws {
        let original = makeRecord(toolId: "translate")
        try await sut.record(original)

        let results = try await sut.findByToolId("translate")
        XCTAssertEqual(results.count, 1, "应返回 1 条记录")
        XCTAssertEqual(results[0], original, "find 出来的记录应与原记录字段全等")
    }

    // MARK: - 3. 同 toolId 多条 → 全部返回 + 按时间升序

    /// 写 3 条同 toolId 不同 recordedAt → find 按时间升序返回全部 3 条
    func test_record_multipleSameToolId_returnsAllOrderedByTimeAsc() async throws {
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)  // 2023-11
        // 故意乱序写入，验证查询时按 recorded_at 排序而非插入顺序
        let middle = makeRecord(toolId: "summarize", recordedAt: baseTime.addingTimeInterval(60))
        let earliest = makeRecord(toolId: "summarize", recordedAt: baseTime)
        let latest = makeRecord(toolId: "summarize", recordedAt: baseTime.addingTimeInterval(120))

        try await sut.record(middle)
        try await sut.record(earliest)
        try await sut.record(latest)

        let results = try await sut.findByToolId("summarize")
        XCTAssertEqual(results.count, 3, "应返回 3 条")
        XCTAssertEqual(results[0].invocationId, earliest.invocationId, "第一条应是最早的")
        XCTAssertEqual(results[1].invocationId, middle.invocationId, "第二条应是中间的")
        XCTAssertEqual(results[2].invocationId, latest.invocationId, "第三条应是最晚的")
    }

    // MARK: - 4. 多 toolId → findByToolId 仅返回匹配子集

    /// 写 3 条不同 toolId，findByToolId("a") 仅返回 toolId=a 的记录
    func test_record_differentToolIds_findReturnsCorrectSubset() async throws {
        let a1 = makeRecord(toolId: "tool.a")
        let a2 = makeRecord(toolId: "tool.a")
        let b1 = makeRecord(toolId: "tool.b")
        try await sut.record(a1)
        try await sut.record(a2)
        try await sut.record(b1)

        let aResults = try await sut.findByToolId("tool.a")
        XCTAssertEqual(aResults.count, 2, "tool.a 应返回 2 条")
        XCTAssertTrue(aResults.allSatisfy { $0.toolId == "tool.a" })

        let bResults = try await sut.findByToolId("tool.b")
        XCTAssertEqual(bResults.count, 1, "tool.b 应返回 1 条")
        XCTAssertEqual(bResults[0].invocationId, b1.invocationId)

        let cResults = try await sut.findByToolId("tool.c")
        XCTAssertEqual(cResults, [], "未注册的 toolId 应返回空数组")
    }

    // MARK: - 5. totalUSD(since:) 区间累加

    /// 写 3 条不同时间 + 不同 usd，totalUSD(since:) 仅累加 since 之后的两条
    func test_totalUSD_sinceDate_aggregatesOnlyMatchingRecords() async throws {
        let baseTime = Date(timeIntervalSince1970: 1_700_000_000)
        // 以下三条 usd 加和需精确 —— 用 string 构造 Decimal 避免 Double 误差
        // swiftlint:disable force_unwrapping
        let oldRec = makeRecord(usd: Decimal(string: "0.01")!, recordedAt: baseTime)
        let mid = makeRecord(usd: Decimal(string: "0.02")!, recordedAt: baseTime.addingTimeInterval(60))
        let new = makeRecord(usd: Decimal(string: "0.03")!, recordedAt: baseTime.addingTimeInterval(120))
        // swiftlint:enable force_unwrapping

        try await sut.record(oldRec)
        try await sut.record(mid)
        try await sut.record(new)

        // since = baseTime + 30s → 仅命中 mid 和 new，sum = 0.05
        let total = try await sut.totalUSD(since: baseTime.addingTimeInterval(30))
        XCTAssertEqual(total, Decimal(string: "0.05"), "应仅累加 since 之后的两条")

        // since = baseTime - 1 → 命中全部 3 条，sum = 0.06
        let totalAll = try await sut.totalUSD(since: baseTime.addingTimeInterval(-1))
        XCTAssertEqual(totalAll, Decimal(string: "0.06"), "since 早于全部记录应累加全部")
    }

    // MARK: - 6. totalUSD(since: future) → Decimal.zero

    /// since 在未来 → 没有记录命中 → 返回 Decimal.zero
    func test_totalUSD_sinceDateInFuture_returnsZero() async throws {
        try await sut.record(makeRecord())  // 用默认 recordedAt = now

        let future = Date().addingTimeInterval(3600)  // 1 小时后
        let total = try await sut.totalUSD(since: future)
        XCTAssertEqual(total, Decimal.zero, "未来时间 since 应返回 0")
    }

    // MARK: - 7. Decimal 精度（小数位 > 9）round-trip 准确

    /// 写入 usd = 0.000123456789（IEEE 754 double 无法精确表示） → find 后等于原值
    func test_record_decimalHighPrecision_preservedRoundTrip() async throws {
        // swiftlint:disable:next force_unwrapping
        let preciseUSD = Decimal(string: "0.0001234567890123")!
        let original = makeRecord(usd: preciseUSD)
        try await sut.record(original)

        let results = try await sut.findByToolId(original.toolId)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].usd, preciseUSD,
                       "TEXT 列应完整保留 Decimal 精度（不走 REAL 损失）")
        // 多走一步：description 完全相同，证明 round-trip 没损失任何数字
        XCTAssertEqual(results[0].usd.description, preciseUSD.description)
    }

    // MARK: - 8. 重复 invocationId 第二次写入抛错

    /// 同 invocationId 写两次 → 第二次抛 SliceError.configuration(.validationFailed)
    func test_record_duplicateInvocationId_throws() async throws {
        let id = UUID()
        let first = makeRecord(invocationId: id)
        let second = makeRecord(invocationId: id, toolId: "different.tool")

        try await sut.record(first)

        do {
            try await sut.record(second)
            XCTFail("第二次 record 同 invocationId 应抛错")
        } catch let SliceError.configuration(.validationFailed(msg)) {
            // 期望命中 SQLITE_CONSTRAINT 路径；msg 包含 "step INSERT failed"
            XCTAssertTrue(msg.contains("step INSERT failed"),
                          "错误消息应来自 step 路径，实际：\(msg)")
        } catch {
            XCTFail("应抛 SliceError.configuration(.validationFailed)，实际：\(error)")
        }

        // 第一条仍然在
        let results = try await sut.findByToolId(first.toolId)
        XCTAssertEqual(results.count, 1, "第一条不应被覆盖")
        XCTAssertEqual(results[0], first)
    }
}

// MARK: - Test helpers

/// async 版 XCTAssertNoThrow —— XCTest 内置的 XCTAssertNoThrow 不接受 async closure
private func XCTAssertNoThrowAsync(
    _ block: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await block()
    } catch {
        XCTFail("Unexpected error: \(error)", file: file, line: line)
    }
}
