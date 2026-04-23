import Foundation

/// 上下文键：在 Tool.contexts 声明处 + ContextBag 存取处共用的强类型标识
///
/// 使用 `RawRepresentable(String)` 而非 String 别名，是为了让"键"与普通字符串在类型层面区分——
/// API 调用者必须显式构造 `ContextKey(rawValue:)` 才能把它当键用，避免把业务字符串误当 key。
///
/// 命名约定（非语言强制）：使用点分路径，例：`selection`、`app.url`、`file.read.result`、`mcp.result`。
public struct ContextKey: Hashable, Codable, Sendable, RawRepresentable {
    public let rawValue: String

    /// 构造 ContextKey
    /// - Parameter rawValue: 键名字符串，调用方负责保证唯一性
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

/// ContextRequest 的失败容忍策略
///
/// - `.required`：采集失败 → `ExecutionEngine` 中止流程，返回 `.failed(.selection(...))`
/// - `.optional`：采集失败 → 记入 `ResolvedExecutionContext.failures`，执行继续，Prompt 可读不到这个 context
public enum Requiredness: String, Codable, Sendable, CaseIterable {
    case required
    case optional
}
