import Capabilities
import Foundation
import SliceCore

/// 执行引擎主 actor。Task 3 仅落地：actor 声明 + 10-dep init 装配 + execute 入口签名 +
/// AsyncThrowingStream 三事件占位。
///
/// 真正的 Step 1-10 主流程（PermissionGraph 校验 / ContextCollector / ProviderResolver /
/// PromptExecutor / LLM stream / OutputDispatcher / sideEffects / CostAccounting /
/// AuditLog / finished）在 **Task 4** 中替换 `runMainFlow` 占位实现。
///
/// 本 Task 完成时，调用 `execute(tool:seed:)` 立即 yield `.started` →
/// `.notImplemented(reason:)` → `.finished(report:)` 三件事并 finish stream，
/// 让单测能验证 init + 流框架。
///
/// **10 个依赖参数与 §C-10.1 audit 表 1:1 对应**
public actor ExecutionEngine {

    // MARK: - Stored dependencies（§C-10.1 audit 表中的 10 个依赖）

    /// Task 5 扩展后负责并发采集 ContextRequest 的集合器
    private let contextCollector: ContextCollector
    /// Task 6 扩展后负责 permission gate 决策的代理（protocol 形态，便于测试注入）
    private let permissionBroker: any PermissionBrokerProtocol
    /// Task 7 扩展后负责聚合 effectivePermissions 的图结构
    private let permissionGraph: PermissionGraph
    /// Task 2 完成的 ProviderSelection → V2Provider 解析器
    private let providerResolver: any ProviderResolverProtocol
    /// Task 11 扩展后负责渲染 prompt + 调用 LLM stream 的执行器
    private let promptExecutor: PromptExecutor
    /// Task 13 扩展后负责 MCP tool call 的客户端（protocol 形态）
    private let mcpClient: any MCPClientProtocol
    /// Task 13 扩展后负责 Skill 解析的注册表（protocol 形态）
    private let skillRegistry: any SkillRegistryProtocol
    /// Task 8 扩展后负责 token cost 记账的 actor
    private let costAccounting: CostAccounting
    /// Task 9 扩展后负责追加结构化审计条目的日志（protocol 形态）
    private let auditLog: any AuditLogProtocol
    /// Task 10 扩展后负责把结果分发到 UI / file / clipboard 的派发器（protocol 形态）
    private let output: any OutputDispatcherProtocol

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
    /// Task 3 占位：仅 yield .started → .notImplemented → .finished(stub) 三件事；
    /// Task 4 替换为真实 Step 1-10 主流程。
    ///
    /// - Parameters:
    ///   - tool: 要执行的 V2Tool
    ///   - seed: 本次调用的执行种子（选区 / 前台 App / 锚点等）
    /// - Returns: AsyncThrowingStream 事件序列；Task 3 阶段固定产出 3 个事件后结束
    /// `nonisolated`：本方法不直接读写 actor 状态，仅创建 Task 并把工作委托给
    /// actor-isolated `runMainFlow`。标记 nonisolated 允许调用方无需 await 即可拿到 stream。
    public nonisolated func execute(
        tool: V2Tool,
        seed: ExecutionSeed
    ) -> AsyncThrowingStream<ExecutionEvent, any Error> {
        // continuation 是 Sendable，可跨 actor 边界安全传递
        AsyncThrowingStream { continuation in
            // [weak self] 避免 engine 生命周期被 stream retain 延长
            Task { [weak self] in
                guard let self else {
                    continuation.finish(throwing: CancellationError())
                    return
                }
                await self.runMainFlow(tool: tool, seed: seed, continuation: continuation)
            }
        }
    }

    // MARK: - Actor-isolated 主流程（Task 3 占位 / Task 4 真实实现）

    /// Task 3 占位：直接 yield 三事件框架；Task 4 替换为完整 Step 1-10 主流程。
    ///
    /// - Parameters:
    ///   - tool: 要执行的 V2Tool
    ///   - seed: 执行种子
    ///   - continuation: AsyncThrowingStream 续体，负责事件输出和流结束
    private func runMainFlow(
        tool: V2Tool,
        seed: ExecutionSeed,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) async {
        let invocationId = UUID()

        // Step 1 占位：标记主流程已启动
        continuation.yield(.started(invocationId: invocationId))

        // Task 3 placeholder：真实 Step 2-9 由 Task 4 替换
        continuation.yield(.notImplemented(reason: "Task 3 placeholder; Task 4 will wire Step 1-10 main flow"))

        // Task 3 stub finished report，使用 InvocationReport 显式构造（#if DEBUG stub() 仅测试可用）
        let stubReport = InvocationReport(
            invocationId: invocationId,
            toolId: tool.id,
            declaredPermissions: Set(tool.permissions),
            effectivePermissions: [],
            flags: [],
            startedAt: Date(),
            finishedAt: Date(),
            totalTokens: 0,
            estimatedCostUSD: 0,
            outcome: .success
        )
        continuation.yield(.finished(report: stubReport))
        continuation.finish()
    }
}
