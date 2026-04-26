import Foundation
import SliceCore

/// JSON Lines 格式的审计日志 actor 实现（spec §3.9.5 + §3.9.7）。
///
/// 设计要点：
/// - **Append-only jsonl**：每条 entry 独立一行 JSON + 换行（`\n`），便于 grep / tail；
/// - **统一脱敏**：`append(_:)` 入口对所有 String payload 调 `Redaction.scrub`，
///   不依赖生产者主动调用，避免漏报；
/// - **clear() 留痕**：清空文件后第一条写入 `.logCleared(at:)`，让"清空"动作本身留痕；
/// - **actor 隔离**：sqlite / 文件句柄等"非 Sendable 状态"由 actor 串行化访问，
///   避免并发写入交错；
/// - **selection 原文永不入 jsonl**：`InvocationReport` schema 层就不带 `selectionText`
///   字段，audit 层物理上接触不到原文（防御深度，配合 `JSONLAuditLogTests` 反射回归守卫）。
public actor JSONLAuditLog: AuditLogProtocol {

    /// jsonl 文件落盘位置；建议 `~/Library/Application Support/SliceAI/audit.jsonl`
    private let fileURL: URL

    /// 共享的 JSON encoder；ISO8601 日期编码确保跨语言可读
    private let encoder: JSONEncoder

    /// 共享的 JSON decoder；与 encoder 对称
    private let decoder: JSONDecoder

    // MARK: - Init

    /// 打开 / 创建 audit 文件，并预创建父目录。
    ///
    /// - Parameter fileURL: 目标 audit jsonl 文件路径
    /// - Throws: 父目录创建 / 空文件占位失败时抛 `SliceError.configuration(.validationFailed(...))`
    public init(fileURL: URL) throws {
        self.fileURL = fileURL

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        // .withoutEscapingSlashes：默认 JSONEncoder 会把 "/" 编为 "\/"，
        // 让 jsonl grep / 文件路径 / URL 字段在 Console 上难读；
        // audit 是给开发者读的，禁用 slash 转义更友好
        enc.outputFormatting = [.withoutEscapingSlashes]
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec

        // 父目录可能不存在（首次启动）；createDirectory(withIntermediateDirectories: true)
        // 已存在时也是 no-op，不会报错
        let parentDir = fileURL.deletingLastPathComponent()
        do {
            try FileManager.default.createDirectory(
                at: parentDir,
                withIntermediateDirectories: true
            )
        } catch {
            throw SliceError.configuration(
                .validationFailed("audit log parent dir creation failed at \(parentDir.path)")
            )
        }

        // 文件不存在则创建空文件，让 append 路径无需 special-case "file missing"
        if !FileManager.default.fileExists(atPath: fileURL.path) {
            do {
                try Data().write(to: fileURL)
            } catch {
                throw SliceError.configuration(
                    .validationFailed("audit log file create failed at \(fileURL.path)")
                )
            }
        }
    }

    // MARK: - AuditLogProtocol

    /// 追加一条审计 entry：先脱敏，再 JSON 编码 + 换行 + 写入文件末尾。
    ///
    /// - Parameter entry: 待写入的 `AuditEntry`；内部统一调 `scrubEntry(_:)` 脱敏后落盘
    /// - Throws: JSON 编码失败 / 文件 I/O 失败时抛 `SliceError.configuration(.validationFailed(...))`
    public func append(_ entry: AuditEntry) async throws {
        // 1. 统一脱敏：避免依赖生产者主动调用 Redaction
        let scrubbed = scrubEntry(entry)

        // 2. JSON 编码
        let data: Data
        do {
            data = try encoder.encode(scrubbed)
        } catch {
            throw SliceError.configuration(
                .validationFailed("audit log JSON encode failed")
            )
        }

        // 3. 拼装"jsonl 单行"——data + 换行
        var lineData = data
        lineData.append(0x0A)  // '\n'

        // 4. 文件末尾追加；actor 隔离保证多次 append 串行执行
        do {
            let handle = try FileHandle(forWritingTo: fileURL)
            // defer close 避免句柄泄漏，即使 write 抛错也能清理
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: lineData)
        } catch {
            throw SliceError.configuration(
                .validationFailed("audit log file write failed")
            )
        }
    }

    /// 清空底层 jsonl 文件，并立即写入一条 `.logCleared(at:)` 作为新文件第一条记录。
    ///
    /// - Throws: 文件清空 / 后续 append 失败时抛 `SliceError.configuration(.validationFailed(...))`
    public func clear() async throws {
        // 1. 物理清空——直接覆盖为空 Data；比 truncate 跨平台更稳
        do {
            try Data().write(to: fileURL)
        } catch {
            throw SliceError.configuration(
                .validationFailed("audit log file clear failed at \(fileURL.path)")
            )
        }

        // 2. 写入 .logCleared 留痕；actor 自递归调用 append——actor 隔离保证排队串行执行
        try await append(.logCleared(at: Date()))
    }

    /// 读取最近 N 条 audit entry，按写入顺序返回。
    ///
    /// - Parameter limit: 最多返回的条数；超过实际数量时返回全部
    /// - Returns: 按 append 顺序排列的 `AuditEntry` 数组（空文件返回空数组）
    /// - Throws: JSON 解码失败时抛 `SliceError.configuration(.validationFailed(...))`
    public func read(limit: Int) async throws -> [AuditEntry] {
        // 文件不存在 / 读不到时退回空数组——audit read 不应因"还没写过"报错
        guard let content = try? String(contentsOf: fileURL, encoding: .utf8) else {
            return []
        }

        // 按 \n 切分；omittingEmptySubsequences 跳过末尾空行（最后一条 entry 后总有 \n）
        let lines = content.split(
            separator: "\n",
            omittingEmptySubsequences: true
        )

        // limit 为 0 / 负数视作"取 0 条"，prefix 自然处理
        let limited = lines.prefix(max(0, limit))

        var entries: [AuditEntry] = []
        entries.reserveCapacity(limited.count)
        for line in limited {
            do {
                let entry = try decoder.decode(AuditEntry.self, from: Data(line.utf8))
                entries.append(entry)
            } catch {
                throw SliceError.configuration(
                    .validationFailed("audit log JSON decode failed")
                )
            }
        }
        return entries
    }

    // MARK: - 私有：脱敏（按 case 模式遍历）

    /// 按 entry case 模式匹配，对所有可能含 PII 的 String payload 调 `Redaction.scrub`。
    ///
    /// **覆盖范围**：
    /// - `.invocationCompleted`：`toolId`（用户自定义工具可能误带 secret）
    /// - `.sideEffectTriggered`：`SideEffect` 关联值的所有 String 字段（path / params 等）
    /// - `.logCleared`：无 String payload，原样返回
    ///
    /// **不在范围**：
    /// - `Permission` 关联值字段（path / host / bundleId）：是稳定标识符，audit 需要保留
    /// - `flags` / `outcome` 等 enum：rawValue 是固定字符串，无 PII
    ///
    /// - Parameter entry: 原始 `AuditEntry`
    /// - Returns: 脱敏后的 `AuditEntry`，结构与原始一致，仅 String payload 被 scrub
    private func scrubEntry(_ entry: AuditEntry) -> AuditEntry {
        switch entry {
        case .invocationCompleted(let report):
            // InvocationReport 结构层只暴露 toolId 这一个 String 字段（其他都是 enum / Set / Date / 数值）
            // 重新构造 report，仅 scrub toolId；其他字段原样保留
            let scrubbedReport = InvocationReport(
                invocationId: report.invocationId,
                toolId: Redaction.scrub(report.toolId),
                declaredPermissions: report.declaredPermissions,
                effectivePermissions: report.effectivePermissions,
                flags: report.flags,
                startedAt: report.startedAt,
                finishedAt: report.finishedAt,
                totalTokens: report.totalTokens,
                estimatedCostUSD: report.estimatedCostUSD,
                outcome: report.outcome
            )
            return .invocationCompleted(scrubbedReport)

        case .sideEffectTriggered(let invocationId, let sideEffect, let executedAt):
            return .sideEffectTriggered(
                invocationId: invocationId,
                sideEffect: scrubSideEffect(sideEffect),
                executedAt: executedAt
            )

        case .logCleared:
            // 仅含 Date，无 String payload
            return entry
        }
    }

    /// 对 `SideEffect` 各 case 的关联 String 字段做脱敏；不改变 case 类型本身。
    private func scrubSideEffect(_ sideEffect: SideEffect) -> SideEffect {
        switch sideEffect {
        case .appendToFile(let path, let header):
            // path / header 都是用户提供的字符串，可能误带 secret
            return .appendToFile(
                path: Redaction.scrub(path),
                header: header.map(Redaction.scrub)
            )

        case .copyToClipboard:
            // 无 String payload
            return .copyToClipboard

        case .notify(let title, let body):
            // notify title / body 由 tool author 决定，可能引用变量值
            return .notify(
                title: Redaction.scrub(title),
                body: Redaction.scrub(body)
            )

        case .runAppIntent(let bundleId, let intent, let params):
            // bundleId 是稳定标识符（com.foo.bar 风格），不脱敏；intent 同理
            // params values 是用户传给外部 App 的实际数据，可能含 secret
            let scrubbedParams = params.mapValues(Redaction.scrub)
            return .runAppIntent(bundleId: bundleId, intent: intent, params: scrubbedParams)

        case .callMCP(let ref, let params):
            // ref.server / ref.tool 是稳定标识符，保留
            // params values 同 runAppIntent，必脱敏
            let scrubbedParams = params.mapValues(Redaction.scrub)
            return .callMCP(ref: ref, params: scrubbedParams)

        case .writeMemory(let tool, let entry):
            // tool 是 toolId（与 .invocationCompleted 同口径处理）
            // entry 是用户/工具写入 memory 的实际内容，必脱敏
            return .writeMemory(
                tool: Redaction.scrub(tool),
                entry: Redaction.scrub(entry)
            )

        case .tts(let voice):
            // voice 是预设 voice id（如 "com.apple.voice.compact.zh-CN.Tingting"），保留
            return .tts(voice: voice)
        }
    }
}
