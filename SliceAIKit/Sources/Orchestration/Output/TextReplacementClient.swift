import Foundation

/// 文本替换结果。
public enum TextReplacementResult: Sendable, Equatable {
    /// 已通过 AX 等直接替换前台 App 选区。
    case replaced
    /// 无法直接替换，已把结果写入剪贴板并提示用户手动粘贴。
    case fallbackCopied(reason: String)
    /// 替换与 fallback 均失败。
    case failed(reason: String)
}

/// 前台 App 文本替换边界。
public protocol TextReplacementClient: Sendable {
    /// 用完整 final text 替换当前选区。
    /// - Parameter text: LLM 完整最终输出；不得传 streaming chunk。
    /// - Returns: 替换结果；调用方根据结果决定是否失败。
    func replaceSelection(with text: String) async -> TextReplacementResult
}
