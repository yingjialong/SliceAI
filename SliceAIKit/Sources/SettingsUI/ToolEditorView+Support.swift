// SliceAIKit/Sources/SettingsUI/ToolEditorView+Support.swift
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - PromptTextEditor

/// 带 placeholder 和圆角边框的多行 prompt 编辑器。
///
/// macOS 下原生 `TextField(axis: .vertical)` 按 Return 会提交而非换行，写 prompt
/// 体验差；改用 `TextEditor`（底层 NSTextView）即可。TextEditor 没有原生 placeholder
/// 所以这里用 ZStack overlay 一层灰字模拟，text 为空时显示。
struct PromptTextEditor: View {

    /// 标题（显示在编辑器上方）
    let label: String

    /// placeholder 文本
    let placeholder: String

    /// 是否显示"必填"红字标记
    let required: Bool

    /// 内容双向绑定
    @Binding var text: String

    /// 编辑器最小高度
    let minHeight: CGFloat

    /// 渲染多行 prompt 编辑器。
    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.xs) {
            HStack {
                Text(label)
                    .font(SliceFont.subheadline)
                    .foregroundColor(SliceColor.textPrimary)
                Spacer()
                if required {
                    Text("必填")
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.error)
                }
            }

            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder)
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textTertiary)
                        .padding(.horizontal, SliceSpacing.sm + 4)
                        .padding(.vertical, SliceSpacing.sm + 4)
                        .allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .textEditorStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textPrimary)
                    .frame(minHeight: minHeight)
                    .padding(SliceSpacing.sm)
            }
            .background(
                RoundedRectangle(cornerRadius: SliceRadius.control)
                    .fill(SliceColor.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: SliceRadius.control)
                            .stroke(SliceColor.border, lineWidth: 0.5)
                    )
            )
        }
    }
}

// MARK: - Display Labels

extension SliceCore.PresentationMode {
    /// 用于 Picker 展示的中文标签。
    var displayLabel: String {
        switch self {
        case .window:     return "浮窗"
        case .bubble:     return "气泡（v0.2）"
        case .replace:    return "替换（v0.2）"
        case .file:       return "file"
        case .silent:     return "silent"
        case .structured: return "structured"
        }
    }
}

extension ToolLabelStyle {
    /// 用于 Picker 展示的中文标签。
    var displayLabel: String {
        switch self {
        case .icon:        return "图标"
        case .name:        return "名称"
        case .iconAndName: return "图标+名称"
        }
    }
}
