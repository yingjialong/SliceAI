import Foundation
import SliceCore

extension ExecutionEngine {

    /// .prompt ToolKind 的 Step 3-9 流程：ContextCollector → ProviderResolver →
    /// PromptStream → sideEffects → CostAccounting → finishSuccess。
    ///
    /// 拆出本 helper 是为了：(1) 让 .agent / .pipeline 在 ToolKind 分流时立即走
    /// `finishNotImplementedKind` 不浪费 ContextCollector / ProviderResolver 预执行
    /// （否则 .pipeline 会被构造 `<pipeline-default>` provider 抛 fake .notFound 写
    /// .failed audit）；(2) 让 runMainFlow + runPromptKindPipeline 都落在 swiftlint
    /// cyclomatic_complexity 12 / function_body_length 40 限制内同时**保留**
    /// 每个 await 边界的 cancellation check（覆盖 Phase 1 真实 ContextProvider 做 IO 时
    /// 的早退场景）。单独成文件是为了让 ExecutionEngine+Steps.swift 不超 file_length
    /// warning 500（已接近上限）。
    ///
    /// **取消语义**：每个 await 之后立即 `if Task.isCancelled { return }` 短路；
    /// onTermination 已 finish 外层 continuation，本路径**不**写 audit、**不**再 yield。
    func runPromptKindPipeline(
        tool: Tool,
        promptTool: PromptTool,
        seed: ExecutionSeed,
        context: FlowContext
    ) async {
        // Step 3 入口取消短路：进入 ContextCollector 前——Phase 1 真实 fileRead/MCP/clipboard
        // provider 在 resolve 中可能做 IO，必须在调用前显式 check
        if Task.isCancelled { return }

        // Step 3：ContextCollector 平铺并发解析
        guard let resolved = await runContextCollection(
            tool: tool, seed: seed, context: context
        ) else { return }
        // Step 3 出口取消短路：避免 Phase 1 provider IO 完成后仍跑 ProviderResolver
        if Task.isCancelled { return }

        // Step 4：ProviderResolver 解析 ProviderSelection
        guard let provider = await runProviderResolution(tool: tool, context: context) else { return }
        // PromptStream 前最后一道防线：防 Keychain 访问 / LLM 网络请求 / token 计费
        if Task.isCancelled { return }

        // Step 6/7：PromptExecutor 流式调用 + OutputDispatcher 派发
        guard let promptUsage = await runPromptStream(
            tool: tool, promptTool: promptTool, resolved: resolved, provider: provider,
            context: context
        ) else { return }
        // PromptStream 后取消短路：MockLLMProvider 同步 yield 完所有 chunks 时 runPromptStream
        // 不会抛 CancellationError，故必须在 sideEffects/cost/audit 边界显式再检一次。
        if Task.isCancelled { return }

        // Step 7（续）：sideEffects 逐条 gate；partial-failure 写入 flags
        let partialFailure = await runSideEffects(
            tool: tool, isDryRun: seed.isDryRun, context: context
        )
        if partialFailure { context.flags.insert(.partialFailure) }
        // sideEffects 末尾 cancel 防御：runSideEffects 已 break，此处再查防止跑 cost/audit
        if Task.isCancelled { return }

        // Step 8/9：CostAccounting + finishSuccess
        await recordCostAndFinishSuccess(
            tool: tool, provider: provider, usage: promptUsage,
            isDryRun: seed.isDryRun, context: context
        )
    }
}
