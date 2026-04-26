import Foundation
import SliceCore

/// 审计日志条目，对应 spec §3.9.5 + §3.9.7。
///
/// 三种 case 与 ExecutionEngine 主流程（Task 4 集成）写入点 1:1 对应：
/// - `.invocationCompleted(InvocationReport)`：每次 `execute(...)` 终止时主写入
///   （区分由 `report.outcome`：`.success` / `.failed(errorKind:)` / `.dryRunCompleted`）
/// - `.sideEffectTriggered(invocationId:sideEffect:executedAt:)`：每个**实际执行**的
///   副作用单独写一条；dry-run 时 `ExecutionEngine` yield `.sideEffectSkippedDryRun`
///   事件给 UI，但**不**写 audit
/// - `.logCleared(at:)`：`AuditLog.clear()` 调用时作为新文件第一条写入，让
///   "审计日志被清空"这个动作本身留下不可篡改的痕迹（spec §3.9.7）
///
/// **手写 Codable 模板**：单键 discriminator（与 SliceCore 的 `ToolKind` / `Permission` /
/// `Provenance` 同款），避免 Swift 合成的 `_0` 字段名泄漏到 JSON 外表面。
public enum AuditEntry: Sendable, Equatable, Codable {
    /// 一次 invocation 完整终止（成功 / 失败 / dry-run 完成均产出）
    case invocationCompleted(InvocationReport)

    /// 单个实际执行的副作用（dry-run 不写）
    case sideEffectTriggered(invocationId: UUID, sideEffect: SideEffect, executedAt: Date)

    /// `clear()` 后写入的"清空动作"标记
    case logCleared(at: Date)

    // MARK: - 手写 Codable

    /// 三个 case 各自对应一个 JSON top-level key
    private enum CodingKeys: String, CodingKey {
        case invocationCompleted, sideEffectTriggered, logCleared
    }

    /// 多关联值的 `.sideEffectTriggered` 用嵌套 Repr struct 中转，避免 `_0` / `_1` 字段名外泄
    private struct SideEffectTriggeredRepr: Codable, Equatable {
        let invocationId: UUID
        let sideEffect: SideEffect
        let executedAt: Date
    }

    /// `.logCleared(at:)` 单 named 关联值同样走 Repr 中转，保持 JSON 字段为 `at` 而非 `_0`
    private struct LogClearedRepr: Codable, Equatable {
        let at: Date
    }

    /// 解码：必须恰好出现 1 个已知 case key，否则报 `dataCorrupted`，避免静默退化
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // 严格 canonical：必须恰好 1 个 key；多键 / 空对象一律拒绝
        guard container.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: container.codingPath,
                debugDescription: "AuditEntry requires exactly one key, got \(container.allKeys.count)"
            ))
        }
        if let report = try container.decodeIfPresent(InvocationReport.self, forKey: .invocationCompleted) {
            self = .invocationCompleted(report)
            return
        }
        if let repr = try container.decodeIfPresent(SideEffectTriggeredRepr.self, forKey: .sideEffectTriggered) {
            self = .sideEffectTriggered(
                invocationId: repr.invocationId,
                sideEffect: repr.sideEffect,
                executedAt: repr.executedAt
            )
            return
        }
        if let repr = try container.decodeIfPresent(LogClearedRepr.self, forKey: .logCleared) {
            self = .logCleared(at: repr.at)
            return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: container.codingPath,
            debugDescription: "AuditEntry encountered unknown case key"
        ))
    }

    /// 编码：单 case → 单 key 输出，配合 decoder 的 allKeys.count == 1 校验形成对称约束
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .invocationCompleted(let report):
            try container.encode(report, forKey: .invocationCompleted)
        case .sideEffectTriggered(let invocationId, let sideEffect, let executedAt):
            try container.encode(
                SideEffectTriggeredRepr(
                    invocationId: invocationId,
                    sideEffect: sideEffect,
                    executedAt: executedAt
                ),
                forKey: .sideEffectTriggered
            )
        case .logCleared(let at):
            try container.encode(LogClearedRepr(at: at), forKey: .logCleared)
        }
    }
}

/// 审计日志写入接口；`ExecutionEngine` 的 Step 9 通过 `any AuditLogProtocol` 调用，
/// 测试可注入 in-memory mock，生产用 `JSONLAuditLog`（actor + JSON Lines 落盘）。
///
/// 实现方需保证：
/// 1. `append` 必须在落盘前对 entry 中所有 String payload 调用 `Redaction.scrub`，
///    避免依赖生产者主动脱敏导致漏报；
/// 2. `clear` 清空底层存储后，第一条记录必须是 `.logCleared(at:)`，让"清空"动作
///    本身留下审计痕迹（spec §3.9.7）；
/// 3. `read(limit:)` 返回顺序必须等于 `append` 顺序（FIFO），让 UI 能稳定回放历史。
public protocol AuditLogProtocol: Sendable {
    /// 追加一条审计条目
    /// - Parameter entry: 待写入的 `AuditEntry`；实现方负责脱敏后落盘
    func append(_ entry: AuditEntry) async throws

    /// 清空底层存储，并写入一条 `.logCleared(at:)` 作为新文件的第一条记录
    func clear() async throws

    /// 读取最近 N 条审计条目（按写入时序，前 N 条）
    /// - Parameter limit: 最多返回的条数；超过实际数量时返回全部
    /// - Returns: 按 `append` 顺序排列的 `AuditEntry` 数组
    func read(limit: Int) async throws -> [AuditEntry]
}
