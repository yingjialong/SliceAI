import Capabilities
import Foundation
import SliceCore

/// v2 编排主入口：把一次"触发种子 + Tool"驱动到 LLM 调用 + 副作用 + 审计落盘。
///
/// **流程概览（spec §3.4 Step 1-10）**：
/// 1. `.started` 事件 + 记录 `startedAt`
/// 2. PermissionGraph 静态聚合 effective permissions；undeclared 非空直接终止
/// 3. PermissionBroker.gate 整体 effective 集合（4 态决策）
/// 4. ContextCollector 平铺并发解析 ContextRequest
/// 5. ProviderResolver 解析 ProviderSelection 到具体 Provider
/// 6. 按 tool.kind 分派；M2 仅 `.prompt` 走 PromptExecutor，其余 yield `.notImplemented`
/// 7. PromptExecutor 流：转发 chunk + OutputDispatcher 投递；末尾收 `.completed(UsageStats)`
/// 8. outputBinding.sideEffects：每条独立 gate；dry-run skip / partial-failure 标记
/// 9. CostAccounting 写一条 CostRecord（usd 估算）
/// 10. finishSuccess/finishFailure：构造 InvocationReport 写 AuditLog + yield `.finished`/`.failed`
///
/// **依赖装配（§C-10.1 audit 表）**：10 个依赖按 actor / protocol 区分；UI 模式下由
/// `AppContainer` 一次性 wire，测试用对应 Helpers/Mock 注入。
///
/// **设计要点**：
/// - 主流程拆成多个 actor-isolated step helper（见 `ExecutionEngine+Steps.swift`），
///   每个 helper 接受同一个 `FlowContext` 上下文打包，避免参数爆炸；
/// - 错误处理统一收口到 `finishFailure`，调用方只需 match `.failed` / `.finished` 两种终态；
/// - `nonisolated func execute(...)` 让调用方拿到 stream 时无需 await，符合 Task 3 已发布契约；
///   真正的并发隔离由内部 `runMainFlow` 这个 actor-isolated 方法承担。
public actor ExecutionEngine {

    // MARK: - Stored dependencies（§C-10.1 audit 表中的 10 个依赖）

    /// 并发上下文采集器（actor）
    let contextCollector: ContextCollector
    /// 权限决策代理（protocol）
    let permissionBroker: any PermissionBrokerProtocol
    /// 有效权限聚合图（actor）
    let permissionGraph: PermissionGraph
    /// ProviderSelection 解析器（protocol）
    let providerResolver: any ProviderResolverProtocol
    /// Prompt 渲染 + LLM 流调用器（actor）
    let promptExecutor: PromptExecutor
    /// MCP tool call 客户端（protocol，Task 13 落地）
    let mcpClient: any MCPClientProtocol
    /// Skill 注册表（protocol，Task 13 落地）
    let skillRegistry: any SkillRegistryProtocol
    /// Token cost 记账器（actor）
    let costAccounting: CostAccounting
    /// 审计日志追加器（protocol）
    let auditLog: any AuditLogProtocol
    /// 结果派发器（protocol）
    let output: any OutputDispatcherProtocol

    // MARK: - Init

    /// 构造执行引擎；10 个依赖按 §C-10.1 audit 表的 isolation 类型分别为 actor / protocol 形态。
    ///
    /// - Parameters:
    ///   - contextCollector: 并发上下文采集器（actor）
    ///   - permissionBroker: 权限决策代理（protocol）
    ///   - permissionGraph: 有效权限聚合图（actor）
    ///   - providerResolver: ProviderSelection 解析器（protocol）
    ///   - promptExecutor: Prompt 渲染 + LLM 流调用器（actor）
    ///   - mcpClient: MCP tool call 客户端（protocol）
    ///   - skillRegistry: Skill 注册表（protocol）
    ///   - costAccounting: Token cost 记账器（actor）
    ///   - auditLog: 审计日志追加器（protocol）
    ///   - output: 结果派发器（protocol）
    public init(
        contextCollector: ContextCollector,
        permissionBroker: any PermissionBrokerProtocol,
        permissionGraph: PermissionGraph,
        providerResolver: any ProviderResolverProtocol,
        promptExecutor: PromptExecutor,
        mcpClient: any MCPClientProtocol,
        skillRegistry: any SkillRegistryProtocol,
        costAccounting: CostAccounting,
        auditLog: any AuditLogProtocol,
        output: any OutputDispatcherProtocol
    ) {
        self.contextCollector = contextCollector
        self.permissionBroker = permissionBroker
        self.permissionGraph = permissionGraph
        self.providerResolver = providerResolver
        self.promptExecutor = promptExecutor
        self.mcpClient = mcpClient
        self.skillRegistry = skillRegistry
        self.costAccounting = costAccounting
        self.auditLog = auditLog
        self.output = output
    }

    // MARK: - Public API

    /// 入口：同步返回 stream，主流程在 actor-isolated `runMainFlow` 中执行。
    ///
    /// `nonisolated`：本方法不直接读写 actor 状态，仅创建 Task 并把工作委托给
    /// actor-isolated `runMainFlow`。标记 nonisolated 允许调用方无需 await 即可拿到 stream
    /// （与 Task 3 发布的契约一致，避免 caller 改签名）。
    ///
    /// **取消语义**：保存内部 Task handle 并通过 `continuation.onTermination` 在
    /// stream consumer drop iterator（如 ResultPanel dismiss / 上层 Task cancel）时
    /// 主动 `task.cancel()`。流程拆成 `runMainFlow`（Step 1-2.5 + ToolKind 分流）+
    /// `runPromptKindPipeline`（Step 3-9 .prompt 路径），分别在每个 await 边界显式检查
    /// `Task.isCancelled`——覆盖"早退 / Step 3 ContextCollector 前后 / Step 4
    /// ProviderResolution 之后 / PromptStream 之前 / PromptStream 之后"共 5 道防线，
    /// 让 Phase 1 真实 ContextProvider（fileRead/MCP/clipboard）做 IO 时也能被早退打断。
    /// 拆 helper 是为了让两个函数都落在 swiftlint cyclomatic_complexity 12 / function_body 40
    /// 限制内同时不牺牲 cancellation 响应粒度。保证 v0.1 既有"用户关闭面板即停"语义在 V2
    /// 链路上端到端一致。
    ///
    /// - Parameters:
    ///   - tool: 要执行的 Tool
    ///   - seed: 本次调用的执行种子（选区 / 前台 App / 锚点等）
    /// - Returns: AsyncThrowingStream 事件序列；按 spec §3.4 顺序产出 Step 1-10 各事件
    public nonisolated func execute(
        tool: Tool,
        seed: ExecutionSeed
    ) -> AsyncThrowingStream<ExecutionEvent, any Error> {
        // continuation 是 Sendable，可跨 actor 边界安全传递
        AsyncThrowingStream { continuation in
            // [weak self] 避免 engine 生命周期被 stream retain 延长
            let task = Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                await self.runMainFlow(tool: tool, seed: seed, continuation: continuation)
            }
            // consumer drop iterator → onTermination → task.cancel() → runMainFlow / runPromptStream
            // 在边界 `Task.isCancelled` 检查处短路；@Sendable closure 仅捕获 task（Sendable）。
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Actor-isolated 主流程

    /// 主流程入口：依次执行 Step 1-10，各阶段失败统一收口到 `finishFailure`。
    ///
    /// 把每个阶段的 happy / failure 路径拆成独立 helper（见 `ExecutionEngine+Steps.swift`），
    /// 让本方法控制流极简（仅顺序串接）；所有跨 step 共享的上下文（invocationId / toolId /
    /// declared / startedAt / continuation）打包成 `FlowContext` 引用类型，避免参数爆炸。
    func runMainFlow(
        tool: Tool,
        seed: ExecutionSeed,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async {
        // Step 1：派发 .started + 记录开始时间，用于 InvocationReport.startedAt
        // 复用 seed.invocationId（spec/数据模型注释明确"贯穿日志的追踪 id；
        // 同一次划词/快捷键触发只生成一次"），让触发层日志、.started、.finished、
        // OutputDispatcher、CostRecord、AuditLog 共用同一个 id；M3 接 UI 后做事故追踪、
        // 取消路由、窗口路由都按 seed id 索引。
        let context = FlowContext(
            invocationId: seed.invocationId,
            toolId: tool.id,
            declared: Set(tool.permissions),
            startedAt: Date(),
            continuation: continuation
        )
        continuation.yield(.started(invocationId: context.invocationId))
        // 取消短路 #1：consumer 收到 .started 后立即关闭面板 → onTermination → task.cancel()
        // → 此处 isCancelled=true。onTermination 已 finish continuation；本路径**不**写 audit、
        // **不**再 yield .failed（避免 audit 出现"用户取消但记 .failed"的歧义），直接 return。
        if Task.isCancelled { return }

        // Step 2：PermissionGraph 静态聚合 + undeclared 校验
        guard let effective = await runPermissionGraph(tool: tool, context: context) else { return }
        context.effective = effective.union

        // Step 2.5：PermissionBroker 整体 gate（dry-run 仍走 lowerBound 计算）
        guard await runPermissionGate(
            tool: tool, effective: effective, isDryRun: seed.isDryRun, context: context
        ) else { return }

        // Step 5/6 提前分流：先按 tool.kind 选路，避免 .agent / .pipeline 浪费 ContextCollector +
        // ProviderResolver 的预执行（spec M2 范围内 .agent/.pipeline 应是 stub —— 不应让真实
        // ContextProvider 做 IO，也不该走 ProviderResolver 抛 fake .notFound 写 .failed audit）。
        let promptTool: PromptTool
        switch tool.kind {
        case .prompt(let p):
            promptTool = p
        case .agent, .pipeline:
            // M2 不实现 .agent / .pipeline；yield .notImplemented + finishSuccess（stub 报告）
            await finishNotImplementedKind(context: context)
            return
        }

        // .prompt 路径：Step 3-9 拆到独立 helper，让 cancellation 防线覆盖每道 await
        // 同时让 runMainFlow / runPromptKindPipeline 各自 ≤ swiftlint cyclomatic 12 + body 40。
        await runPromptKindPipeline(
            tool: tool, promptTool: promptTool, seed: seed, context: context
        )
    }
}
