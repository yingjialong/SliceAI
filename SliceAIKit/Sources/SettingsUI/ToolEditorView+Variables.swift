// SliceAIKit/Sources/SettingsUI/ToolEditorView+Variables.swift
import DesignSystem
import SwiftUI

// MARK: - Tool Editor Variables

extension ToolEditorView {

    /// 自定义变量分组：始终显示；提供 key-value 列表 + 添加/删除入口。
    var variablesCard: some View {
        SectionCard("自定义变量") {
            HStack {
                Text("变量会注入到提示词里的 {{变量名}} 占位符。")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
                Spacer(minLength: 0)
            }
            .padding(.vertical, SliceSpacing.xs)

            if variablesAccessor.isEmpty {
                HStack {
                    Text("暂无自定义变量")
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textTertiary)
                    Spacer()
                }
                .padding(.vertical, SliceSpacing.sm)
            } else {
                ForEach(Array(variablesAccessor.keys.sorted()), id: \.self) { key in
                    variableRow(key: key)
                }
            }

            HStack {
                Spacer()
                PillButton("添加变量", icon: "plus", style: .secondary) {
                    newVariableKey = ""
                    showAddVariableAlert = true
                }
            }
            .padding(.top, SliceSpacing.xs)
        }
    }

    /// 单行自定义变量编辑：key 标签 + value TextField + 删除按钮。
    /// - Parameter key: 变量名。
    func variableRow(key: String) -> some View {
        HStack(spacing: SliceSpacing.sm) {
            Text(key)
                .font(SliceFont.subheadline)
                .foregroundColor(SliceColor.textPrimary)
                .frame(minWidth: 90, alignment: .leading)
                .lineLimit(1)

            TextField(
                "变量值",
                text: Binding(
                    get: { variablesAccessor[key] ?? "" },
                    set: { setVariableValue($0, for: key) }
                )
            )
            .textFieldStyle(.plain)
            .foregroundColor(SliceColor.textPrimary)
            .font(SliceFont.body)

            Button {
                removeVariable(forKey: key)
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(SliceColor.error)
            }
            .buttonStyle(.plain)
            .help("删除此变量")
        }
        .padding(.vertical, SliceSpacing.xs)
    }

    /// alert 里"添加"按钮的回调：校验 key 并写入 variables。
    ///
    /// 若校验未通过也重置 newVariableKey，避免下次弹框残留脏值。
    func addVariable() {
        defer { newVariableKey = "" }
        let trimmed = newVariableKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, variablesAccessor[trimmed] == nil else { return }
        addPromptVariable(forKey: trimmed)
    }
}
