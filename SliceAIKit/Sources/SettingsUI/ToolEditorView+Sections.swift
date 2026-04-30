// SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift
import DesignSystem
import SliceCore
import SwiftUI

// MARK: - Tool Editor Sections

extension ToolEditorView {

    /// 当前工具是否为 v0.2 设置页支持编辑的 prompt 类型。
    var isPromptTool: Bool {
        if case .prompt = tool.kind {
            return true
        }
        return false
    }

    /// 基础信息分组：名称 / 图标 / 描述。
    var basicsCard: some View {
        SectionCard("基础信息") {
            SettingsRow("名称") {
                TextField("工具名称", text: $tool.name)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
            }

            SettingsRow("图标") {
                TextField("SF Symbol 或 emoji", text: $tool.icon)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.trailing)
                    .foregroundColor(SliceColor.textPrimary)
                    .font(SliceFont.body)
            }

            SettingsRow("描述") {
                TextField(
                    "可选描述",
                    text: Binding(
                        get: { tool.description ?? "" },
                        set: { tool.description = $0.isEmpty ? nil : $0 }
                    )
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundColor(SliceColor.textPrimary)
                .font(SliceFont.body)
            }

            SettingsRow("浮条显示") {
                Picker("", selection: $tool.labelStyle) {
                    ForEach(ToolLabelStyle.allCases, id: \.self) { style in
                        Text(style.displayLabel).tag(style)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 240)
            }
        }
    }

    /// 提示词分组：System / User Prompt。
    var promptCard: some View {
        SectionCard("提示词") {
            PromptTextEditor(
                label: "System Prompt",
                placeholder: "可选 System Prompt...",
                required: false,
                text: systemPromptBinding,
                minHeight: 72
            )
            .padding(.vertical, SliceSpacing.base)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SliceColor.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, -SliceSpacing.xl)
            }

            PromptTextEditor(
                label: "User Prompt",
                placeholder: "输入 User Prompt，可用 {{selection}} 等变量...",
                required: true,
                text: userPromptBinding,
                minHeight: 120
            )
            .padding(.vertical, SliceSpacing.base)

            Text("可用变量：{{selection}}  {{app}}  {{url}}  {{language}}")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, SliceSpacing.xs)
        }
    }

    /// Provider 分组：关联 Provider / 模型覆写 / 采样温度。
    var providerCard: some View {
        SectionCard("Provider") {
            SettingsRow("Provider") {
                if providers.isEmpty {
                    Text("请先添加 Provider")
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textTertiary)
                } else {
                    Picker("", selection: providerIdBinding) {
                        ForEach(providers) { provider in
                            Text(provider.name).tag(provider.id)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                }
            }

            SettingsRow("模型覆写") {
                TextField(
                    "留空使用 Provider 默认模型",
                    text: modelIdBinding
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundColor(SliceColor.textPrimary)
                .font(SliceFont.body)
            }

            SettingsRow("Temperature") {
                HStack(spacing: SliceSpacing.sm) {
                    Slider(
                        value: temperatureBinding,
                        in: 0...2
                    )
                    .frame(width: 120)

                    Text(String(format: "%.2f", temperatureBinding.wrappedValue))
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                        .frame(width: 40, alignment: .trailing)
                }
            }

            SettingsRow("展示模式") {
                Picker("", selection: $tool.displayMode) {
                    ForEach(Self.editableDisplayModes, id: \.self) { mode in
                        Text(mode.displayLabel).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
            }

            Text("v0.2 暂时全部以窗口模式展示，Phase 2 起 bubble / replace 等模式生效")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// 非 prompt 工具的只读提示，避免用户在 no-op editor 中误以为修改会保存。
    var unsupportedKindCard: some View {
        SectionCard("工具类型") {
            HStack {
                Text("当前工具类型暂不支持在 v0.2 设置页编辑。")
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textSecondary)
                Spacer(minLength: 0)
            }
            Text("基础信息仍可编辑；Agent / Pipeline 的专用编辑器将在后续阶段接入。")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
