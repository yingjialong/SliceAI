import Foundation
@testable import Orchestration

/// In-memory `AuditLogProtocol` mock for unit tests.
///
/// 设计要点：
/// - **actor**：与生产 `JSONLAuditLog` 同款隔离，`ExecutionEngine` 注入 `any AuditLogProtocol`
///   的代码路径在测试 / 生产保持一致；
/// - **不做 scrub**：测试调用方需要直接看到原始 entry 才能断言（脱敏行为由 `RedactionTests`
///   + `JSONLAuditLogTests` 端到端覆盖，不应在 mock 这一层重复）；
/// - **clear() 也写 .logCleared**：与生产 `JSONLAuditLog.clear()` 行为对齐，避免测试用
///   mock 后导致行为偏离规范。
final actor MockAuditLog: AuditLogProtocol {

    /// 已 append 的 entry 列表，按写入顺序保存
    private(set) var entries: [AuditEntry] = []

    /// 追加一条 entry；mock 不做脱敏，原样保存
    func append(_ entry: AuditEntry) async throws {
        entries.append(entry)
    }

    /// 清空记录并写入 .logCleared 留痕，行为与生产 JSONLAuditLog.clear() 对齐
    func clear() async throws {
        entries.removeAll()
        entries.append(.logCleared(at: Date()))
    }

    /// 取前 N 条 entry；FIFO 顺序与 append 一致
    func read(limit: Int) async throws -> [AuditEntry] {
        Array(entries.prefix(max(0, limit)))
    }
}
