import Foundation

/// 本次执行的触发通路；`ExecutionSeed.triggerSource` 字段的类型
///
/// 审计日志、Prompt 模板（`{{triggerSource}}`）、UI 可读此字段做差异化行为。
public enum TriggerSource: String, Sendable, Codable, CaseIterable {
    /// 划词后鼠标弹出的浮条
    case floatingToolbar
    /// ⌥Space 命令面板
    case commandPalette
    /// Per-tool hotkey 直接触发（Phase 1+）
    case hotkey
    /// 从 Shortcuts.app 的 AppIntent 调用（Phase 4+）
    case shortcutsApp
    /// URL Scheme `sliceai://run/<tool>`（Phase 4+）
    case urlScheme
    /// macOS Services 菜单（Phase 4+）
    case servicesMenu
}
