import Foundation
import SliceCore

// MARK: - ExecutionEngine 终态 helpers

extension ExecutionEngine {

    /// 构造 InvocationReport —— 把"declared / effective / flags / 时间 / token / cost / outcome"汇总为最终快照。
    func makeReport(
        context: FlowContext,
        finishedAt: Date,
        tokens: Int,
        costUSD: Decimal,
        outcome: InvocationOutcome
    ) -> InvocationReport {
        InvocationReport(
            invocationId: context.invocationId,
            toolId: context.toolId,
            declaredPermissions: context.declared,
            effectivePermissions: context.effective,
            flags: context.flags,
            startedAt: context.startedAt, finishedAt: finishedAt,
            totalTokens: tokens,
            estimatedCostUSD: costUSD,
            outcome: outcome
        )
    }

    /// 失败终态：写一条 `.invocationCompleted(report.failed(...))` audit + yield `.failed(error)` + finish。
    ///
    /// 不读 `context.effective`：失败发生时 effective 可能尚未算出（Step 2 早期失败），
    /// 所以单独以参数注入 effective 集合，让调用方明确传入"当前已知的 effective"。
    /// `try?` 吞 audit 错误：失败路径已经在 yield .failed 通知调用方，audit 写失败属于二次故障，不应叠加。
    func finishFailure(
        error: SliceError,
        effective: Set<Permission>,
        context: FlowContext
    ) async {
        if context.runPolicy.source == .playground {
            context.flags.insert(.playground)
        }
        let report = InvocationReport(
            invocationId: context.invocationId,
            toolId: context.toolId,
            declaredPermissions: context.declared,
            effectivePermissions: effective,
            flags: context.flags,
            startedAt: context.startedAt, finishedAt: Date(),
            totalTokens: 0,
            estimatedCostUSD: 0,
            outcome: .failed(errorKind: InvocationOutcome.ErrorKind.from(error))
        )
        try? await auditLog.append(.invocationCompleted(report))
        context.continuation.yield(.failed(error))
        context.continuation.finish()
    }

    /// 成功终态：写 audit + yield `.finished(report)` + finish。
    func finishSuccess(
        report: InvocationReport,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async {
        try? await auditLog.append(.invocationCompleted(report))
        continuation.yield(.finished(report: report))
        continuation.finish()
    }

    /// `.agent` / `.pipeline` 在 M2 阶段未实现 —— yield `.notImplemented` 后走 success 终态（stub 报告）。
    ///
    /// 选择 success 而非 failure，是因为本路径**没有真正执行任何动作**（既没采集 / 也没调 LLM），
    /// audit 上记一条 `.success` stub 让调用方能看出"M2 范围内已挑战 .agent / .pipeline kind"。
    func finishNotImplementedKind(context: FlowContext) async {
        context.continuation.yield(.notImplemented(
            reason: "ToolKind not supported in M2 (Phase 1+ for .agent / Phase 5+ for .pipeline)"
        ))
        let stub = makeReport(
            context: context,
            finishedAt: Date(),
            tokens: 0,
            costUSD: 0,
            outcome: .success
        )
        await finishSuccess(report: stub, continuation: context.continuation)
    }
}
