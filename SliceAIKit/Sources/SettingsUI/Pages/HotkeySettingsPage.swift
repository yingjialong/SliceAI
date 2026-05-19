// SliceAIKit/Sources/SettingsUI/Pages/HotkeySettingsPage.swift
//
// 快捷键设置页：绑定命令面板全局热键，用户 onSubmit 后立即持久化。
import DesignSystem
import HotkeyManager
import SliceCore
import SwiftUI

// MARK: - HotkeySettingsPage

/// 快捷键设置页
///
/// 当前版本仅提供命令面板热键的单行配置，
/// 使用 `HotkeyEditorView` 内嵌于 `SectionCard` + `SettingsRow` 布局。
///
/// 持久化策略：用户修改并按回车（TextField.onSubmit）后立即调用
/// `viewModel.saveHotkeys()` 写回磁盘；无全局保存按钮。
///
/// 未来可在此页追加工具快捷键（⌘1–⌘9）。
public struct HotkeySettingsPage: View {

    /// 设置视图模型，用于读写 configuration.hotkeys
    @ObservedObject private var viewModel: SettingsViewModel

    /// 构造快捷键设置页
    /// - Parameter viewModel: 宿主注入的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(title: "快捷键", subtitle: "绑定命令面板的全局快捷键。") {
            // 命令面板热键配置卡片
            SectionCard("命令面板") {
                SettingsRow("唤起快捷键") {
                    // HotkeyEditorView 双向绑定 configuration.hotkeys.toggleCommandPalette；
                    // 用户 TextField onSubmit 后，viewModel 内存态已更新，随即写回磁盘
                    HotkeyEditorView(
                        binding: $viewModel.configuration.hotkeys.toggleCommandPalette,
                        onCommit: {
                            // onSubmit 立即持久化热键配置
                            Task {
                                await viewModel.saveHotkeys()
                            }
                        }
                    )
                }
                if let message = commandPaletteValidationMessage {
                    Text(message)
                        .font(SliceFont.caption)
                        .foregroundColor(.red)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            // 备注卡片：提示未来规划
            SectionCard {
                Text("工具快捷键可在 Tools 中每个工具的基础信息里设置。")
                    .font(SliceFont.callout)
                    .foregroundColor(SliceColor.textTertiary)
                    .padding(.vertical, SliceSpacing.base)
            }
        }
    }

    /// 命令面板热键的跨工具校验提示
    private var commandPaletteValidationMessage: String? {
        let toolHotkeys = HotkeyBindingValidator.effectiveToolHotkeys(
            bindings: viewModel.configuration.hotkeys,
            tools: viewModel.configuration.tools
        )
        let issues = HotkeyBindingValidator.issues(
            commandPalette: viewModel.configuration.hotkeys.toggleCommandPalette,
            tools: toolHotkeys
        )
        guard let issue = issues.first(where: isCommandPaletteIssue) else { return nil }
        switch issue {
        case .invalidCommandPalette:
            return "命令面板快捷键无效"
        case .commandPaletteConflict(let toolID, let hotkey):
            return "与工具 \(toolID) 的快捷键 \(hotkey) 冲突"
        case .invalidTool, .toolConflict:
            return nil
        }
    }

    /// 判断校验问题是否需要显示在命令面板热键行下方
    /// - Parameter issue: HotkeyManager 返回的纯校验问题
    /// - Returns: `true` 表示问题与命令面板热键直接相关
    private func isCommandPaletteIssue(_ issue: HotkeyBindingIssue) -> Bool {
        switch issue {
        case .invalidCommandPalette, .commandPaletteConflict:
            return true
        case .invalidTool, .toolConflict:
            return false
        }
    }
}

// MARK: - SettingsRow

/// 设置行：左标签 / 右控件的两列布局
///
/// 底部附 0.5pt 分隔线（向卡片内扩展，视觉上与卡片边框对齐）。
/// 使用泛型 `Control` 支持任意控件类型，由 `@ViewBuilder` 注入。
///
/// 用法示例：
/// ```swift
/// SettingsRow("最小触发字符数") {
///     Stepper("\(value)", value: $value, in: 1...50)
/// }
/// ```
public struct SettingsRow<Control: View>: View {

    /// 行左侧标签文本
    let label: String

    /// 行右侧控件
    @ViewBuilder let control: () -> Control

    /// 构造设置行
    /// - Parameters:
    ///   - label: 左侧标签文本
    ///   - control: 右侧控件，通过 @ViewBuilder 注入
    public init(_ label: String, @ViewBuilder control: @escaping () -> Control) {
        self.label = label
        self.control = control
    }

    public var body: some View {
        HStack(spacing: SliceSpacing.lg) {
            // 左侧标签：subheadline 字号，主文本色；固定最小宽度避免被
            // 右侧 TextField(plain) 这类 greedy 控件挤掉，保证 label 始终可见
            Text(label)
                .font(SliceFont.subheadline)
                .foregroundColor(SliceColor.textPrimary)
                .frame(minWidth: 110, alignment: .leading)

            Spacer(minLength: 0)

            // 右侧控件：layoutPriority 高于 label，控件优先拿剩余空间
            control()
                .layoutPriority(1)
        }
        .padding(.vertical, SliceSpacing.base)
        // 底部 0.5pt 分隔线，向卡片内水平延伸
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SliceColor.divider)
                .frame(height: 0.5)
                .padding(.horizontal, -SliceSpacing.xl)
        }
    }
}
