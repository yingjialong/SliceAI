import CoreGraphics
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
    /// 本次执行的运行策略。
    let runPolicy: ExecutionRunPolicy
    /// 主流程启动时刻；finishSuccess / finishFailure 写 InvocationReport.startedAt 时使用
    let startedAt: Date
    /// 触发时的屏幕锚点，供 output lifecycle sink 定位。
    let screenAnchor: CGPoint
    /// 事件流 continuation；helper 通过 `context.continuation.yield(...)` 派发事件
    let continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    /// PermissionGraph 计算后的 effective union（Step 2 写入，后续 step 只读）
    var effective: Set<Permission>
    /// 当前 invocation 的完整最终输出；Prompt / Agent stream 完成后写入，side effects 读取。
    var finalText: String
    /// 关键事件标记，main flow / sideEffects 增量写入
    var flags: Set<InvocationFlag>

    /// 构造 FlowContext —— effective / flags 初始为空，由各 step 写入
    /// - Parameters:
    ///   - invocationId: 本次 invocation 唯一标识
    ///   - toolId: Tool.id 透传
    ///   - declared: 静态 declared 权限集合
    ///   - runPolicy: 本次执行的运行策略
    ///   - startedAt: 主流程启动时刻
    ///   - continuation: 事件流 continuation（actor 隔离内传递）
    init(
        invocationId: UUID,
        toolId: String,
        declared: Set<Permission>,
        runPolicy: ExecutionRunPolicy,
        startedAt: Date,
        screenAnchor: CGPoint,
        continuation: AsyncThrowingStream<ExecutionEvent, any Error>.Continuation
    ) {
        self.invocationId = invocationId
        self.toolId = toolId
        self.declared = declared
        self.runPolicy = runPolicy
        self.startedAt = startedAt
        self.screenAnchor = screenAnchor
        self.continuation = continuation
        self.effective = []
        self.finalText = ""
        self.flags = []
    }
}
