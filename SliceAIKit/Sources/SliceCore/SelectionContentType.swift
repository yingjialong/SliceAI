import Foundation

/// 选中文字的内容类型启发式识别结果
///
/// Phase 0 M1 只定义枚举；真正的识别逻辑由 `SelectionCapture` 模块在 Phase 1+ 填充
/// （基于简单 heuristic：正则识别 URL / email / hash / 日期；代码围栏识别；兜底 .prose / .other）。
///
/// 工具可以通过 `ToolMatcher.contentTypes` 声明 "只对某些内容类型显示"，
/// 也可以在 Prompt 模板里读 `{{selection.contentType}}` 做条件分支。
public enum SelectionContentType: String, Codable, Sendable, CaseIterable {
    case prose
    case code
    case url
    case email
    case json
    case commitHash
    case date
    case other
}

/// 选中文字的来源渠道；从旧 `SelectionPayload.Source` 提升到独立类型便于复用
///
/// **命名说明**：`SelectionSource` 是 spec canonical 的来源枚举。
/// 它与 `SelectionCapture` 模块的 `SelectionReader` 读取器接口语义正交；
/// `SelectionReader` 继续由 AXSelectionSource / ClipboardSelectionSource 实现。
public enum SelectionSource: String, Codable, Sendable, CaseIterable {
    /// 通过 AX API 直接读取
    case accessibility
    /// 通过模拟 Cmd+C + 剪贴板备份恢复获取
    case clipboardFallback
    /// ⌥Space 命令面板中用户直接打字输入（无选区）
    case inputBox
}
