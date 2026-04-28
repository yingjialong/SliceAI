import Foundation

/// `PathSandbox` 路径校验失败时抛出的错误枚举（参见 spec §3.9.3）。
///
/// 设计要点：
/// - 与 `SliceError` 风格保持一致：每个 case 都有中文 `userMessage`，便于上层 UI 直接展示；
/// - 不写入 `SliceCore/SliceError.swift`（zero-touch SliceCore 白名单只允许
///   `SliceError` / `ContextError` / `ToolPermissionError` 三个文件），独立放在 Capabilities/SecurityKit；
/// - 关联值仅携带"已规范化路径"或"原始输入"，**不**携带任意第三方字符串 payload，
///   不存在密钥泄露风险，可以原样进入日志/审计。
public enum PathSandboxError: Error, Sendable, Equatable {
    /// 解析后的路径不在（默认 + 用户附加）允许名单内，或被硬禁止前缀拒绝。
    /// - Parameters:
    ///   - rawPath: 调用方传入的原始字符串（未做任何展开）；
    ///   - normalized: 经过 `resolvingSymlinksInPath()` + `standardizedFileURL` 规范化后的绝对路径。
    case escapesAllowlist(rawPath: String, normalized: String)

    /// `.write` 角色访问只读路径。
    /// 仅 `~/Library/Application Support/SliceAI/**` 与用户附加 allowlist 允许写入；
    /// 其他默认白名单（`~/Documents` / `~/Desktop` / `~/Downloads`）只允许 `.read`。
    /// - Parameter normalized: 经过规范化后的绝对路径。
    case writeNotPermittedForReadOnlyPath(normalized: String)

    /// 路径输入本身非法（空串 / 不可表示为合法 URL）。
    /// - Parameter rawPath: 调用方传入的原始字符串。
    case invalidInput(rawPath: String)

    /// 中文友好文案，由上层 UI 直接展示给用户。
    ///
    /// 不暴露完整路径到 UI（路径可能含用户名等隐私信息），日志/审计自行从关联值取上下文。
    public var userMessage: String {
        // 文案统一原则：不展示完整路径，避免在错误弹窗中泄露隐私目录结构
        switch self {
        case .escapesAllowlist:
            return "该路径不在允许的目录范围内，请在「设置 → 权限 → 文件访问」中显式添加后再试。"
        case .writeNotPermittedForReadOnlyPath:
            return "目标位置不允许写入。仅 SliceAI 应用支持目录与你显式添加的目录可被写入。"
        case .invalidInput:
            return "路径不合法，请检查输入是否为空或包含非法字符。"
        }
    }
}
