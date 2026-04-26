import Foundation
import SliceCore

/// `ExecutionEngine.execute(...)` 流式产出的事件。
///
/// 每条事件都是不可变值类型；调用方按 `AsyncThrowingStream<ExecutionEvent, Error>`
/// 顺序消费。事件字段尽量 `Sendable` + 简单 struct，便于跨 actor 流转。
///
/// 注意：`promptRendered` 的 `preview` **必须**经过 `Redaction.scrub` 后再传入；
/// `toolCallProposed` / `toolCallResult` 中的字典也必须脱敏。脱敏责任在事件**生产者**
/// （PromptExecutor / AgentExecutor），事件本身不再做二次过滤。
public enum ExecutionEvent: Sendable {
    /// 主流程已启动；invocationId 用于关联 AuditLog / CostAccounting / 后续事件
    case started(invocationId: UUID)

    /// ContextCollector 解析出某个 ContextRequest 的结果（仅成功路径产出，
    /// 失败的请求统一在 `failed` 或最终 report.flags 里体现）
    case contextResolved(key: ContextKey, valueDescription: String)

    /// 渲染好的 prompt 预览（已截断 + 脱敏）；用于 Playground / DryRun
    case promptRendered(preview: String)

    /// LLM provider 流式输出片段
    case llmChunk(delta: String)

    /// Agent loop 提议调用 MCP tool（M2 仅声明，AgentExecutor 由 Phase 1 实现）
    case toolCallProposed(ref: MCPToolRef, argsDescription: String)

    /// PermissionBroker 同意 tool call
    case toolCallApproved(id: UUID)

    /// MCP tool 返回（脱敏后的简短摘要，避免污染日志）
    case toolCallResult(id: UUID, summary: String)

    /// Pipeline 进度（M2 仅声明，PipelineExecutor 由 Phase 5 实现）
    case stepCompleted(step: Int, total: Int)

    /// OutputBinding.sideEffects 的副作用已触发（含 inferredPermissions 已 gate 通过）
    case sideEffectTriggered(SideEffect)

    /// 主流程成功结束
    case finished(report: InvocationReport)

    /// 主流程失败（任何 step 错误统一收敛到此 case）
    case failed(SliceError)

    /// M2 范围 placeholder：还未实现的 PresentationMode / ToolKind 分支返回此事件
    case notImplemented(reason: String)

    /// dry-run 路径下 PermissionBroker.gate 返回 `.wouldRequireConsent` 时 yield；
    /// caller 收到此事件后跳过实际执行但**继续主流程**；用于 Playground UI 显示
    /// "如果实际执行会需要 X 权限"。**严禁** 与 `.approved` 混淆。
    case permissionWouldBeRequested(permission: Permission, uxHint: String)

    /// Step 7 dry-run 时替代 `.sideEffectTriggered` 的事件，
    /// 标记该 sideEffect 仅 gate 通过但**未实际执行**；不写 AuditLog
    /// （AuditLog 仅在真正执行时写）。
    case sideEffectSkippedDryRun(SideEffect)
}
