import Foundation

/// v2 工具权限决策失败语义；`SliceError.toolPermission` 关联值
///
/// 与 `SliceCore.PermissionError`（系统权限：accessibility / inputMonitoring）独立——
/// 后者是 macOS 系统权限错误命名空间，本类型是 v2 工具运行时权限决策错误。
///
/// 五个 case 的语义边界：
/// - `.undeclared(missing:)`：`PermissionGraph.compute(tool:)` 静态闭环检测出
///   `effective.union - declared` 非空（D-24 漏报）。携带集合让上层 UI 列出缺失项。
/// - `.denied(permission:reason:)`：`PermissionBroker` 显式拒绝（含 reason 文案给用户看）。
/// - `.notGranted(permission:)`：用户在确认弹窗里点了拒绝，单条权限粒度的反馈。
/// - `.unknownProvider(id:)`：`PermissionGraph` 在 `ContextProviderRegistry` 中查不到
///   `ContextRequest.provider`，无法静态推导该 request 的权限——属于配置错误。
/// - `.sandboxViolation(path:)`：`PathSandbox`（Task 12）或 `OutputDispatcher`（Task 10）
///   实际执行 IO 时检出路径越界。
public enum ToolPermissionError: Error, Sendable, Equatable {
    /// Tool 实际触发的权限不在 `tool.permissions` 静态声明集合内
    case undeclared(missing: Set<Permission>)
    /// PermissionBroker 决策为拒绝（reason 给用户看，不脱敏，调用方自己保证不泄漏敏感信息）
    case denied(permission: Permission, reason: String)
    /// 用户在确认弹窗里拒绝授予指定权限
    case notGranted(permission: Permission)
    /// `ContextRequest.provider` 在 `ContextProviderRegistry` 中找不到对应实例
    case unknownProvider(id: String)
    /// 路径访问越过 `PathSandbox` 允许范围
    case sandboxViolation(path: String)

    /// 面向最终用户的友好错误文案
    public var userMessage: String {
        switch self {
        case .undeclared(let missing):
            return "工具尝试访问未声明的权限（\(missing.count) 项）。"
        case .denied(_, let reason):
            return "权限被拒绝：\(reason)"
        case .notGranted:
            return "权限未授予，无法执行该工具。"
        case .unknownProvider(let id):
            return "未注册的提供方 \"\(id)\"。"
        case .sandboxViolation:
            return "路径访问被沙箱拦截。"
        }
    }
}
