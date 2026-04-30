import Foundation
import SliceCore

/// 主流程跨 step 共享的可变上下文。
///
/// 设计要点：
/// - **class（不是 struct）**：actor-isolated 主流程内沿用引用语义；helper 修改 `effective` /
///   `flags` 后无需把 `inout` 参数显式回写。本类型只在 `ExecutionEngine` 自身 actor 隔离
///   边界内使用，所有读写都在主流程 task 串行进行——没有竞态、不需要 Sendable；
/// - **为什么不直接展开成函数参数**：避免 swiftlint function_parameter_count 触发，且让
///   step helper 接口收敛到 `(tool: ..., context:)` 二参数模式。
final class FlowContext {
    /// 本次 invocation 的 ID（与 `.started` / `.finished` / audit / cost 路由一致）
    let invocationId: UUID
    /// 触发的 Tool id；audit / report 透传
    let toolId: String
    /// `tool.permissions` 静态声明集合（去重后的 Set）
    let declared: Set<Permission>
    /// 主流程启动时刻；finishSuccess / finishFailure 写 InvocationReport.startedAt 时使用
    let startedAt: Date
    /// 事件流 continuation；helper 通过 `context.continuation.yield(...)` 派发事件
    let continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    /// PermissionGraph 计算后的 effective union（Step 2 写入，后续 step 只读）
    var effective: Set<Permission>
    /// 关键事件标记，main flow / sideEffects 增量写入
    var flags: Set<InvocationFlag>

    /// 构造 FlowContext —— effective / flags 初始为空，由各 step 写入
    /// - Parameters:
    ///   - invocationId: 本次 invocation 唯一标识
    ///   - toolId: Tool.id 透传
    ///   - declared: 静态 declared 权限集合
    ///   - startedAt: 主流程启动时刻
    ///   - continuation: 事件流 continuation（actor 隔离内传递）
    init(
        invocationId: UUID,
        toolId: String,
        declared: Set<Permission>,
        startedAt: Date,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) {
        self.invocationId = invocationId
        self.toolId = toolId
        self.declared = declared
        self.startedAt = startedAt
        self.continuation = continuation
        self.effective = []
        self.flags = []
    }
}

extension ExecutionEngine {

    // MARK: - Step helpers

    /// Step 2：聚合 effective permissions；undeclared 非空直接终止。
    ///
    /// 返回 nil 表示已 finishFailure 或被取消。每条 catch + happy 分支都先查 `Task.isCancelled`
    /// 静默退出，防止 cancel 后仍走 finishFailure 写"取消但记 .failed" 歧义 audit。
    func runPermissionGraph(
        tool: Tool,
        context: FlowContext
    ) async -> EffectivePermissions? {
        let effective: EffectivePermissions
        do {
            effective = try await permissionGraph.compute(tool: tool)
        } catch is CancellationError {
            return nil
        } catch SliceError.toolPermission(.unknownProvider(let id)) {
            if Task.isCancelled { return nil }
            await finishFailure(
                error: .configuration(.invalidTool(id: id, reason: "context provider not registered")),
                effective: [], context: context
            )
            return nil
        } catch {
            if Task.isCancelled { return nil }
            // 其他 SliceError / 非 SliceError 一律包装为 validationFailed —— 不打日志（无自由日志）
            await finishFailure(
                error: .configuration(.validationFailed("PermissionGraph error")),
                effective: [], context: context
            )
            return nil
        }
        if Task.isCancelled { return nil }

        // D-24 闭环：effective.union ⊆ declared；漏报直接终止
        if !effective.undeclared.isEmpty {
            await finishFailure(
                error: .toolPermission(.undeclared(missing: effective.undeclared)),
                effective: effective.union, context: context
            )
            return nil
        }
        return effective
    }

    /// Step 2.5：PermissionBroker 对整体 effective set 做 gate 决策。
    ///
    /// 返回 false 表示已 finishFailure / 决策失败终止 / 被取消；返回 true 主流程继续。
    /// `.wouldRequireConsent` 在 dry-run 路径下 yield 占位事件后继续主流程。
    /// gate await 后查 `Task.isCancelled`，防止取消后仍写 .failed audit / yield 多余事件。
    func runPermissionGate(
        tool: Tool,
        effective: EffectivePermissions,
        isDryRun: Bool,
        context: FlowContext
    ) async -> Bool {
        let outcome = await permissionBroker.gate(
            effective: effective.union,
            provenance: tool.provenance,
            scope: .session,
            isDryRun: isDryRun
        )
        if Task.isCancelled { return false }
        switch outcome {
        case .approved:
            return true
        case .denied(let permission, let reason):
            await finishFailure(
                error: .toolPermission(.denied(permission: permission, reason: reason)),
                effective: effective.union, context: context
            )
            return false
        case .requiresUserConsent(let permission, _):
            // 非 dry-run 路径上 broker 返回 requiresUserConsent —— M2 没接 UI，直接当未授予
            await finishFailure(
                error: .toolPermission(.notGranted(permission: permission)),
                effective: effective.union, context: context
            )
            return false
        case .wouldRequireConsent(let permission, let uxHint):
            // dry-run 路径上 broker 返回 wouldRequireConsent —— yield 占位事件后**继续**主流程
            context.continuation.yield(.permissionWouldBeRequested(permission: permission, uxHint: uxHint))
            return true
        }
    }

    /// Step 3：ContextCollector 平铺并发解析 ContextRequest。
    ///
    /// 返回 nil 表示 required ContextRequest 失败已 finishFailure；调用方应 return。
    func runContextCollection(
        tool: Tool,
        seed: ExecutionSeed,
        context: FlowContext
    ) async -> ResolvedExecutionContext? {
        let contextRequests = extractContextRequests(from: tool)
        do {
            return try await contextCollector.resolve(seed: seed, requests: contextRequests)
        } catch is CancellationError {
            // 取消静默退出：onTermination 已 finish 外层 continuation；本路径不写 audit、
            // 不再 yield。CancellationError 由 ContextCollector.runOne 透传上来，触发场景：
            // 用户在 ContextCollector 解析途中关闭 panel → cancel cascade → provider.resolve
            // 内部 Task.sleep / Task.checkCancellation 抛出 → group throw → 这里捕获。
            return nil
        } catch SliceError.context(.requiredFailed(let key, let underlying)) {
            // required 失败语义已经成形，原样转为 InvocationReport.outcome.failed(.context)
            await finishFailure(
                error: .context(.requiredFailed(key: key, underlying: underlying)),
                effective: context.effective, context: context
            )
            return nil
        } catch {
            // 兜底分支：其他 SliceError（providerNotFound / timeout）+ 非 SliceError；
            // 包装为 .context(.requiredFailed) + key=<unknown>，让上层 audit 也走 .context 类目
            await finishFailure(
                error: .context(.requiredFailed(
                    key: ContextKey(rawValue: "<unknown>"),
                    underlying: .configuration(.validationFailed("ContextCollector error"))
                )),
                effective: context.effective, context: context
            )
            return nil
        }
    }

    /// Step 4：ProviderResolver 解析 ProviderSelection 为具体 Provider。
    ///
    /// 返回 nil 表示 provider 未找到 / 解析失败已 finishFailure；调用方应 return。
    func runProviderResolution(
        tool: Tool,
        context: FlowContext
    ) async -> Provider? {
        let selection: ProviderSelection
        switch tool.kind {
        case .prompt(let p):
            selection = p.provider
        case .agent(let a):
            selection = a.provider
        case .pipeline:
            // pipeline 没有顶层 provider；M2 不会执行到这里（前面已 yield .notImplemented 后 return），
            // 此处用 stub providerId 让 resolver 抛 .notFound 而不会 force unwrap
            selection = .fixed(providerId: "<pipeline-default>", modelId: nil)
        }

        do {
            return try await providerResolver.resolve(selection)
        } catch is CancellationError {
            // 真实 ProviderResolver（Phase 1 接 Keychain / 远端 model 列表）做 IO 时
            // 收到 cancel cascade 抛 CancellationError —— 与 F5.1 ContextCollector 同口径，
            // 不能落入 catch-all 走 finishFailure 写 .failed(.configuration) audit
            return nil
        } catch ProviderResolutionError.notFound(let providerId) {
            if Task.isCancelled { return nil }
            // 注：plan 原样代码用 `id` 误绑（不存在的局部变量），这里以绑定的 providerId 为准
            await finishFailure(
                error: .configuration(.referencedProviderMissing(providerId)),
                effective: context.effective, context: context
            )
            return nil
        } catch {
            if Task.isCancelled { return nil }
            await finishFailure(
                error: .configuration(.validationFailed("ProviderResolver error")),
                effective: context.effective, context: context
            )
            return nil
        }
    }

    /// Step 6/7：跑 PromptExecutor stream，yield `.llmChunk` 并把 chunk 投递给 OutputDispatcher。
    ///
    /// 返回 UsageStats 表示流正常结束；返回 nil 表示已 finishFailure 或被取消。
    /// `.notImplemented(reason)` 仅首次 yield。每个 chunk 入口 + `output.handle` await 后查
    /// `Task.isCancelled`：取消后不再 yield .llmChunk / .notImplemented / 调 output.handle，
    /// 防止 ResultPanel dismiss 后 chunk 仍投递到已关闭 panel。
    func runPromptStream(
        tool: Tool,
        promptTool: PromptTool,
        resolved: ResolvedExecutionContext,
        provider: Provider,
        context: FlowContext
    ) async -> UsageStats? {
        var promptUsage: UsageStats = .zero
        var notImplementedYielded = false
        let stream = await promptExecutor.run(
            promptTool: promptTool, resolved: resolved, provider: provider
        )
        do {
            for try await element in stream {
                switch element {
                case .chunk(let chunk):
                    if Task.isCancelled { return nil }
                    // 捕获 yield 结果：consumer 已 drop iterator 时 .terminated；不进 OutputDispatcher
                    let yieldResult = context.continuation.yield(.llmChunk(delta: chunk))
                    if case .terminated = yieldResult { return nil }
                    let dispatchOutcome = try await output.handle(
                        chunk: chunk, mode: tool.displayMode, invocationId: context.invocationId
                    )
                    if Task.isCancelled { return nil }
                    if case .notImplemented(let reason) = dispatchOutcome, !notImplementedYielded {
                        context.continuation.yield(.notImplemented(reason: reason))
                        notImplementedYielded = true
                    }
                case .completed(let stats):
                    promptUsage = stats
                }
            }
        } catch is CancellationError {
            // 静默取消：consumer drop iterator 已触发 onTermination → 外层 continuation 已 drain；
            // 不写 audit、不 yield .failed（避免 audit 出现"用户取消但记 .failed"的歧义）。
            return nil
        } catch let error as SliceError {
            await finishFailure(
                error: error, effective: context.effective, context: context
            )
            return nil
        } catch {
            // 非 SliceError —— 包装为 provider.invalidResponse；payload 不携带任何用户文本
            await finishFailure(
                error: .provider(.invalidResponse("PromptExecutor stream failed (non-SliceError)")),
                effective: context.effective, context: context
            )
            return nil
        }
        return promptUsage
    }

    /// Step 7（续）：逐条 sideEffect gate + 派发；返回 partialFailure 标记。
    ///
    /// `.approved`：dry-run yield `.sideEffectSkippedDryRun`，否则 yield `.sideEffectTriggered` 并写 audit；
    /// `.denied` / `.requiresUserConsent`：partial-failure 标记 true（主流程不中止）；
    /// `.wouldRequireConsent`：dry-run 占位事件 `.sideEffectSkippedDryRun`。
    /// 循环入口 + gate await 后查 `Task.isCancelled`：Phase 1 真实 sideEffect（writeFile /
    /// showNotification / open URL）不可逆，取消后未派发部分静默丢弃。
    func runSideEffects(
        tool: Tool,
        isDryRun: Bool,
        context: FlowContext
    ) async -> Bool {
        var partialFailure = false
        for sideEffect in tool.outputBinding?.sideEffects ?? [] {
            if Task.isCancelled { break }
            let outcome = await permissionBroker.gate(
                effective: Set(sideEffect.inferredPermissions),
                provenance: tool.provenance,
                scope: .session,
                isDryRun: isDryRun
            )
            if Task.isCancelled { break }
            switch outcome {
            case .approved:
                if isDryRun {
                    // dry-run：yield 占位事件，**不**写 audit（按 spec §3.9.7：仅真正执行才入 audit）
                    context.continuation.yield(.sideEffectSkippedDryRun(sideEffect))
                } else {
                    context.continuation.yield(.sideEffectTriggered(sideEffect))
                    // try? 吞错：audit 写失败不应阻塞主流程；M2 用 mock 都不会失败
                    try? await auditLog.append(
                        .sideEffectTriggered(
                            invocationId: context.invocationId,
                            sideEffect: sideEffect,
                            executedAt: Date()
                        )
                    )
                }
            case .denied:
                partialFailure = true
            case .requiresUserConsent:
                partialFailure = true
            case .wouldRequireConsent:
                // dry-run 路径上 broker 用 wouldRequireConsent 替代了 requiresUserConsent
                context.continuation.yield(.sideEffectSkippedDryRun(sideEffect))
            }
        }
        return partialFailure
    }

    // MARK: - Step 8/9 复合 helper

    /// Step 8 + Step 9 复合：CostAccounting 写记录 → finishSuccess 写 audit + yield .finished。
    ///
    /// 拆 helper 把"计费 + 终态收口"逻辑从 main flow 抽出来，
    /// 让 `runMainFlow` 控制流体落在 swiftlint function_body 40 行以内。
    /// cost record await 后查 `Task.isCancelled` —— 取消后跳过 finishSuccess（不写 audit、
    /// 不 yield .finished）。CostRecord 残留是可接受代价（telemetry 多一条孤记录，
    /// 比 audit 出现"取消但记 .success" 歧义影响小）。
    func recordCostAndFinishSuccess(
        tool: Tool,
        provider: Provider,
        usage: UsageStats,
        isDryRun: Bool,
        context: FlowContext
    ) async {
        let costUSD = estimateCostUSD(usage: usage)
        // CostRecord.model 与 PromptExecutor 实际请求的 model 必须同源——否则 audit 中的"请求模型"
        // 与"记账模型"会漂移；用 resolveSelectedModel 集中解析 ProviderSelection.fixed.modelId
        let model = resolveSelectedModel(tool: tool, fallback: provider.defaultModel)
        // try? 吞错：cost 写失败属于 telemetry，不应阻塞主流程；后续观察期由 sqlite IO 监控暴露
        try? await costAccounting.record(CostRecord(
            invocationId: context.invocationId,
            toolId: tool.id,
            providerId: provider.id,
            model: model,
            inputTokens: usage.inputTokens,
            outputTokens: usage.outputTokens,
            usd: costUSD,
            recordedAt: Date()
        ))
        if Task.isCancelled { return }
        if isDryRun { context.flags.insert(.dryRun) }
        let report = makeReport(
            context: context,
            finishedAt: Date(),
            tokens: usage.inputTokens + usage.outputTokens,
            costUSD: costUSD,
            outcome: isDryRun ? .dryRunCompleted : .success
        )
        await finishSuccess(report: report, continuation: context.continuation)
    }

    // MARK: - 终态 helpers

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

    // MARK: - Pure helpers

    /// 抽取 tool.kind 中所有 ContextRequest（与 PermissionGraph.extractContexts 同口径）。
    ///
    /// pipeline 仅 .prompt(inline:) step 的 inline.contexts 参与；其他 step 类型不嵌套 ContextRequest。
    nonisolated func extractContextRequests(from tool: Tool) -> [ContextRequest] {
        switch tool.kind {
        case .prompt(let p):
            return p.contexts
        case .agent(let a):
            return a.contexts
        case .pipeline(let pipeline):
            var collected: [ContextRequest] = []
            for step in pipeline.steps {
                if case .prompt(let inline, _) = step {
                    collected.append(contentsOf: inline.contexts)
                }
            }
            return collected
        }
    }

    /// 估算单次 invocation 的 USD 成本（M2 简化模型 —— Phase 1 接入真实 provider rate 后下线）。
    ///
    /// `nonisolated`：纯函数无 actor 状态依赖，跳过隔离避免不必要的 hop。
    /// **swiftlint --strict 禁 `!`**：用 `?? .zero` 兜底；字面量 "0.000001" 实际不会解析失败，
    /// 但显式 nil-coalesce 比 force unwrap 更安全（未来字面量笔误也不会 crash）。
    nonisolated func estimateCostUSD(usage: UsageStats) -> Decimal {
        let totalTokens = Decimal(usage.inputTokens + usage.outputTokens)
        // 0.000001 美元/token 是 M2 占位单价（约对应 $1/M tokens）；fallback .zero 让逻辑全程无 crash 路径
        return totalTokens * (Decimal(string: "0.000001") ?? .zero)
    }

    /// 解析工具级 model override：与 PromptExecutor 同口径，让 ChatRequest.model 与 CostRecord.model 同源。
    ///
    /// `nonisolated`：纯函数无 actor 状态依赖。
    /// pipeline 没顶层 provider，一致回 fallback；其他 kind 各自取自己的 provider selection。
    /// 只在 `.fixed(_, modelId:)` 且 modelId 非 nil 时返回 override，否则 fallback。
    nonisolated func resolveSelectedModel(tool: Tool, fallback: String) -> String {
        let selection: ProviderSelection
        switch tool.kind {
        case .prompt(let promptTool): selection = promptTool.provider
        case .agent(let agentTool): selection = agentTool.provider
        case .pipeline: return fallback
        }
        if case .fixed(_, let modelId) = selection, let modelId {
            return modelId
        }
        return fallback
    }
}
