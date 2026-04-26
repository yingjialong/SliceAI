import Foundation

/// v2 上下文采集失败语义；`SliceError.context` 关联值
///
/// 在 v2 编排链路中，`ContextCollector.resolve(seed:requests:)` 处理 Tool 声明的所有
/// `ContextRequest` 并把成功值并入 `ResolvedExecutionContext.contexts`、把可选失败放进
/// `failures`。required 失败 / provider 注册缺失 / 单 request 超时这三类"无法继续"的错误
/// 通过本 enum 表达，再被 `SliceError.context(_:)` 顶层包装，统一进入应用错误模型。
///
/// **`indirect`**（plan Round 5 R5-P1.1）：`requiredFailed.underlying` 的类型是 `SliceError`，
/// 而 `SliceError.context` 又关联 `ContextError`，构成 `SliceError → ContextError → SliceError`
/// 的直接递归。Swift 编译器要求递归的关联值必须用 `indirect` 间接存储，否则报
/// "recursive enum '...' is not marked 'indirect'"。
public indirect enum ContextError: Error, Sendable, Equatable {
    /// `Requiredness.required` 的请求采集失败，underlying 是被包装的具体 SliceError
    /// （可能是其他 ContextError、provider 包装错误，或非 SliceError 被 collector 包装后的形态）
    case requiredFailed(key: ContextKey, underlying: SliceError)
    /// `ContextRequest.provider` 在 `ContextProviderRegistry` 中找不到对应实例
    case providerNotFound(id: String)
    /// 单个 request 在默认 timeout 内未完成
    case timeout(key: ContextKey)

    /// 面向最终用户的友好错误文案
    public var userMessage: String {
        switch self {
        case .requiredFailed(let key, _):
            return "必填上下文 \"\(key.rawValue)\" 采集失败。"
        case .providerNotFound(let id):
            return "未注册的上下文提供方 \"\(id)\"。"
        case .timeout(let key):
            return "上下文 \"\(key.rawValue)\" 采集超时。"
        }
    }
}
