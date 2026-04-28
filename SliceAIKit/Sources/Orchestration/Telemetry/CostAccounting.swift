import Foundation
import SliceCore
import SQLite3

/// SQLITE_TRANSIENT —— 让 sqlite3_bind_text 复制传入的 C 字符串，避免悬挂指针。
///
/// `sqlite3_destructor_type` 是 C 函数指针类型；常量 `SQLITE_TRANSIENT` 在 sqlite3.h
/// 定义为 `((sqlite3_destructor_type)-1)`，但 Swift bridging 把宏丢了，需要手动 unsafeBitCast。
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 成本核算 actor —— 持久化每次 invocation 的成本记录到 sqlite（spec §4.4.2 / §4.5.2）。
///
/// 设计要点：
/// - actor 隔离 sqlite 句柄（`OpaquePointer` 不 `Sendable`，必须串行访问）；
/// - schema 在 init 时自动建表（`CREATE TABLE IF NOT EXISTS`），无单独迁移流程；
/// - `usd` 列存储为 `TEXT`（`record.usd.description` 的 decimal string），避免 `REAL`
///   IEEE 754 浮点对金额的精度损失；读取时用 `Decimal(string:)` 还原；
/// - `recorded_at` 列存储为 `INTEGER`（毫秒级 epoch），给未来精度留余地；
///   注意 `Date` 内部是亚毫秒精度，写入会做"四舍五入到毫秒"截断，
///   因此 round-trip 出的 `recordedAt` 与原值在亚毫秒位上可能不同（业务影响可忽略）；
/// - 所有 sqlite 错误统一抛 `SliceError.configuration(.validationFailed(...))`，
///   M2 不为 sqlite 单独建 error case（M3 / Phase 1 再细化）。
///
/// M2 仅提供：写入 + 按 toolId 查询 + 按时间窗口聚合。Cost Panel 的可视化在 Phase 3。
public actor CostAccounting {
    /// 持有的 sqlite 句柄；actor 隔离保证业务期间串行访问，deinit 在最后引用消失后单线程触发。
    ///
    /// `nonisolated(unsafe)` 是必需的：Swift 6 严格并发禁止 nonisolated deinit 访问非 Sendable
    /// 属性，但 sqlite 句柄不 `Sendable`。这里手动声明运行时不变量：
    /// (a) 业务方法运行在 actor 上下文，串行访问 db；
    /// (b) deinit 由 ARC 在最后一个 actor 引用消失后调用，此时不会再有并发访问；
    /// 因此 `nonisolated(unsafe)` 是安全的。
    private nonisolated(unsafe) let db: OpaquePointer

    /// 启动时打开 / 创建数据库文件并建 schema。
    ///
    /// - Parameter dbURL: sqlite 数据库文件路径（建议位于 `~/Library/Application Support/SliceAI/`）。
    /// - Throws: `SliceError.configuration(.validationFailed(...))` —— sqlite open 或 schema 创建失败时。
    public init(dbURL: URL) throws {
        // 打开 / 创建数据库；FULLMUTEX 让 sqlite 自身串行化，actor 之外的并发访问也安全
        var dbHandle: OpaquePointer?
        let path = dbURL.path
        let openResult = sqlite3_open_v2(
            path,
            &dbHandle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard openResult == SQLITE_OK, let handle = dbHandle else {
            // sqlite3_close 即使 dbHandle 为 nil 也安全（no-op）；防止资源泄漏
            sqlite3_close(dbHandle)
            throw SliceError.configuration(
                .validationFailed("sqlite open failed (code=\(openResult)) at \(path)")
            )
        }
        self.db = handle
        // 建 schema；失败时 init 抛错，handle 必须先关
        do {
            try Self.createSchema(db: handle)
        } catch {
            sqlite3_close(handle)
            throw error
        }
    }

    /// 释放 sqlite 句柄；actor deinit 在最后一个引用消失后被调用。
    deinit {
        sqlite3_close(db)
    }

    // MARK: - Public API

    /// 写入一条 cost record。
    ///
    /// - Parameter record: 要持久化的成本记录
    /// - Throws: `SliceError.configuration(.validationFailed(...))` ——
    ///   sqlite prepare / bind / step 失败（含主键冲突 SQLITE_CONSTRAINT）。
    /// - Note: M2 决策：`invocation_id` 主键冲突时直接抛错，**不**做 ON CONFLICT REPLACE；
    ///   重复写入是上层 bug，应在测试中暴露。
    public func record(_ record: CostRecord) throws {
        let sql = """
        INSERT INTO cost_records
            (invocation_id, tool_id, provider_id, model, input_tokens, output_tokens, usd, recorded_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """
        var stmt: OpaquePointer?
        let prepResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }  // finalize 即使 stmt nil 也安全
        guard prepResult == SQLITE_OK else {
            throw SliceError.configuration(
                .validationFailed("sqlite prepare INSERT failed (code=\(prepResult))")
            )
        }
        // 绑定 8 个字段（顺序与 SQL 占位符严格一致）
        sqlite3_bind_text(stmt, 1, record.invocationId.uuidString, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 2, record.toolId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 3, record.providerId, -1, SQLITE_TRANSIENT)
        sqlite3_bind_text(stmt, 4, record.model, -1, SQLITE_TRANSIENT)
        sqlite3_bind_int64(stmt, 5, Int64(record.inputTokens))
        sqlite3_bind_int64(stmt, 6, Int64(record.outputTokens))
        // Decimal -> 字符串保留完整精度，读取时再用 Decimal(string:) 还原
        sqlite3_bind_text(stmt, 7, record.usd.description, -1, SQLITE_TRANSIENT)
        // 毫秒级 epoch；TimeInterval 是 Double 秒，× 1000 后取整为 Int64 毫秒
        let millis = Int64((record.recordedAt.timeIntervalSince1970 * 1000.0).rounded())
        sqlite3_bind_int64(stmt, 8, millis)

        let stepResult = sqlite3_step(stmt)
        guard stepResult == SQLITE_DONE else {
            // SQLITE_CONSTRAINT (19) 主要在 invocation_id 重复时触发
            throw SliceError.configuration(
                .validationFailed("sqlite step INSERT failed (code=\(stepResult))")
            )
        }
    }

    /// 按 toolId 查询所有 cost records，按 `recorded_at` 升序返回。
    ///
    /// - Parameter toolId: 要过滤的 toolId
    /// - Returns: 匹配 toolId 的记录数组（按时间升序，可能为空）
    /// - Throws: `SliceError.configuration(.validationFailed(...))` —— sqlite prepare/step 失败。
    public func findByToolId(_ toolId: String) throws -> [CostRecord] {
        let sql = """
        SELECT invocation_id, tool_id, provider_id, model, input_tokens, output_tokens, usd, recorded_at
        FROM cost_records
        WHERE tool_id = ?
        ORDER BY recorded_at ASC
        """
        var stmt: OpaquePointer?
        let prepResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard prepResult == SQLITE_OK else {
            throw SliceError.configuration(
                .validationFailed("sqlite prepare SELECT failed (code=\(prepResult))")
            )
        }
        sqlite3_bind_text(stmt, 1, toolId, -1, SQLITE_TRANSIENT)

        var results: [CostRecord] = []
        // step 直到 SQLITE_DONE；SQLITE_ROW 时读取本行所有列
        while true {
            let stepResult = sqlite3_step(stmt)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw SliceError.configuration(
                    .validationFailed("sqlite step SELECT failed (code=\(stepResult))")
                )
            }
            // 解码每列；text 列要 cString -> String，int64 列直接读
            guard let record = Self.decodeRow(stmt: stmt) else {
                throw SliceError.configuration(
                    .validationFailed("sqlite decode row failed (toolId=\(toolId))")
                )
            }
            results.append(record)
        }
        return results
    }

    /// 累加 `since` 之后所有 cost records 的 usd（Decimal 精确求和）。
    ///
    /// - Parameter since: 起始时间（含 = 起点的记录会被计入）
    /// - Returns: 区间内 usd 总和；空集返回 `Decimal.zero`
    /// - Throws: `SliceError.configuration(.validationFailed(...))` —— sqlite prepare/step 失败。
    public func totalUSD(since: Date) throws -> Decimal {
        let sql = "SELECT usd FROM cost_records WHERE recorded_at >= ?"
        var stmt: OpaquePointer?
        let prepResult = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        defer { sqlite3_finalize(stmt) }
        guard prepResult == SQLITE_OK else {
            throw SliceError.configuration(
                .validationFailed("sqlite prepare SUM failed (code=\(prepResult))")
            )
        }
        let sinceMillis = Int64((since.timeIntervalSince1970 * 1000.0).rounded())
        sqlite3_bind_int64(stmt, 1, sinceMillis)

        // 在 Swift 侧累加 Decimal —— sqlite SUM 走 REAL，会损失精度
        var total = Decimal.zero
        while true {
            let stepResult = sqlite3_step(stmt)
            if stepResult == SQLITE_DONE { break }
            guard stepResult == SQLITE_ROW else {
                throw SliceError.configuration(
                    .validationFailed("sqlite step SUM failed (code=\(stepResult))")
                )
            }
            // 列 0 是 usd（TEXT）；防御性 nil-check：理论上 NOT NULL 列不会为 nil
            guard
                let usdCStr = sqlite3_column_text(stmt, 0),
                let usd = Decimal(string: String(cString: usdCStr))
            else {
                throw SliceError.configuration(
                    .validationFailed("sqlite SUM decode usd failed")
                )
            }
            total += usd
        }
        return total
    }

    // MARK: - Private helpers

    /// 建表 SQL —— `IF NOT EXISTS` 让重复 init 同一文件幂等。
    private static func createSchema(db: OpaquePointer) throws {
        let sql = """
        CREATE TABLE IF NOT EXISTS cost_records (
            invocation_id TEXT PRIMARY KEY,
            tool_id       TEXT,
            provider_id   TEXT,
            model         TEXT,
            input_tokens  INTEGER,
            output_tokens INTEGER,
            usd           TEXT NOT NULL,
            recorded_at   INTEGER
        )
        """
        var errMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errMsg)
        // sqlite3_free 释放 sqlite 自己 alloc 的 errMsg；nil 时跳过
        defer { if let e = errMsg { sqlite3_free(e) } }
        guard result == SQLITE_OK else {
            throw SliceError.configuration(
                .validationFailed("sqlite schema create failed (code=\(result))")
            )
        }
    }

    /// 把当前 stmt 行解码为 `CostRecord`；任一列读取失败返回 nil。
    ///
    /// 列顺序与 `findByToolId` SQL SELECT 列表严格一致：
    /// 0=invocation_id, 1=tool_id, 2=provider_id, 3=model,
    /// 4=input_tokens, 5=output_tokens, 6=usd, 7=recorded_at
    private static func decodeRow(stmt: OpaquePointer?) -> CostRecord? {
        // text 列 sqlite3_column_text 返回 const unsigned char*；nil 表示 NULL（理论不会发生）
        guard
            let invocCStr = sqlite3_column_text(stmt, 0),
            let toolCStr = sqlite3_column_text(stmt, 1),
            let providerCStr = sqlite3_column_text(stmt, 2),
            let modelCStr = sqlite3_column_text(stmt, 3),
            let usdCStr = sqlite3_column_text(stmt, 6)
        else { return nil }
        guard let invocationId = UUID(uuidString: String(cString: invocCStr)) else {
            return nil
        }
        guard let usd = Decimal(string: String(cString: usdCStr)) else {
            return nil
        }
        let inputTokens = Int(sqlite3_column_int64(stmt, 4))
        let outputTokens = Int(sqlite3_column_int64(stmt, 5))
        let millis = sqlite3_column_int64(stmt, 7)
        let recordedAt = Date(timeIntervalSince1970: TimeInterval(millis) / 1000.0)
        return CostRecord(
            invocationId: invocationId,
            toolId: String(cString: toolCStr),
            providerId: String(cString: providerCStr),
            model: String(cString: modelCStr),
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            usd: usd,
            recordedAt: recordedAt
        )
    }
}
