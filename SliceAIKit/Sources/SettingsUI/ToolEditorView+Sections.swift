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

    /// 当前工具是否为 Phase 1 设置页支持编辑的 agent 类型。
    var isAgentTool: Bool {
        if case .agent = tool.kind {
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

            SettingsRow("快捷键") {
                VStack(alignment: .trailing, spacing: SliceSpacing.xs) {
                    HotkeyEditorView(
                        binding: toolHotkeyBinding,
                        onCommit: onHotkeyCommit
                    )
                    if let message = toolHotkeyValidationMessage {
                        Text(message)
                            .font(SliceFont.caption)
                            .foregroundColor(.red)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .frame(maxWidth: 280)
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

            Text("window / bubble / replace / structured 已生效；file / silent 需后续高级输出配置")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Agent 提示词分组：System / Initial User Prompt。
    var agentPromptCard: some View {
        SectionCard("Agent 提示词") {
            PromptTextEditor(
                label: "System Prompt",
                placeholder: "描述 Agent 的角色、边界和工具使用规则...",
                required: false,
                text: agentSystemPromptBinding,
                minHeight: 88
            )
            .padding(.vertical, SliceSpacing.base)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(SliceColor.divider)
                    .frame(height: 0.5)
                    .padding(.horizontal, -SliceSpacing.xl)
            }

            PromptTextEditor(
                label: "Initial User Prompt",
                placeholder: "输入 Agent 的初始任务，可用 {{selection}} 等变量...",
                required: true,
                text: agentInitialUserPromptBinding,
                minHeight: 120
            )
            .padding(.vertical, SliceSpacing.base)

            Text("可用变量：{{selection}}  {{app}}  {{url}}")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, SliceSpacing.xs)
        }
    }

    /// Agent Provider 与 ReAct 轮数分组。
    var agentProviderCard: some View {
        SectionCard("Agent Provider") {
            SettingsRow("Provider") {
                if providers.isEmpty {
                    Text("请先添加 Provider")
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textTertiary)
                } else {
                    Picker("", selection: agentProviderIdBinding) {
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
                    text: agentModelIdBinding
                )
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .foregroundColor(SliceColor.textPrimary)
                .font(SliceFont.body)
            }

            SettingsRow("LLM 轮数") {
                Stepper(value: agentMaxStepsBinding, in: 1...20) {
                    Text("\(agentMaxStepsBinding.wrappedValue)")
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textPrimary)
                        .frame(width: 32, alignment: .trailing)
                }
                .frame(width: 120)
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
        }
    }

    /// Agent Skills 绑定分组。
    var agentSkillsCard: some View {
        SectionCard("Agent Skills") {
            if availableSkills.isEmpty {
                Text("暂无可用 Skills")
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SliceSpacing.sm)
            } else {
                if selectedAgentSkillIDs.isEmpty {
                    Text("未绑定 Skill")
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, SliceSpacing.sm)
                }

                ForEach(selectedAgentSkillIDs.indices, id: \.self) { index in
                    agentSkillRow(index: index)
                }
            }

            HStack(spacing: SliceSpacing.sm) {
                IconButton(
                    systemName: "plus",
                    help: "添加 Skill",
                    action: addAgentSkillBinding
                )
                .disabled(!canAddAgentSkillBinding)

                Text("已绑定 \(selectedAgentSkillIDs.count)/5")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)

                Spacer(minLength: 0)
            }
            .padding(.top, SliceSpacing.xs)
        }
    }

    /// 单条 Agent skill 绑定行。
    /// - Parameter index: skill binding 下标。
    /// - Returns: 绑定行视图。
    @ViewBuilder
    func agentSkillRow(index: Int) -> some View {
        let selectedID = selectedAgentSkillIDs[index]
        VStack(alignment: .leading, spacing: SliceSpacing.xs) {
            SettingsRow("Skill \(index + 1)") {
                HStack(spacing: SliceSpacing.sm) {
                    Picker("", selection: agentSkillSelectionBinding(forRow: index)) {
                        ForEach(selectableAgentSkillIDs(forRow: index), id: \.self) { skillID in
                            Text(availableSkill(id: skillID)?.canonicalName ?? skillID).tag(skillID)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .frame(minWidth: 180, maxWidth: 260)

                    IconButton(
                        systemName: "minus",
                        help: "删除 Skill",
                        action: { removeAgentSkill(at: index) }
                    )
                }
            }

            if let description = availableSkill(id: selectedID)?.manifest.description,
               !description.isEmpty {
                Text(description)
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, SliceSpacing.xs)
            }
        }
    }

    /// Agent MCP allowlist 分组。
    var agentMCPAllowlistCard: some View {
        SectionCard("MCP Allowlist") {
            PromptTextEditor(
                label: "允许调用的 MCP Tools",
                placeholder: "brave-search.brave_web_search\nfilesystem.read_file",
                required: false,
                text: agentMCPAllowlistTextBinding,
                minHeight: 96
            )
            .padding(.vertical, SliceSpacing.base)

            Text("每行一个 server.tool；保存后会同步工具的 MCP 权限声明。")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, SliceSpacing.xs)
        }
    }

    /// Agent MCP 调用策略分组。
    var agentToolCallPolicyCard: some View {
        SectionCard("MCP 调用策略") {
            SettingsRow("总 MCP 上限") {
                Stepper(value: agentMaxTotalToolCallsBinding, in: 0...100) {
                    Text(policyLimitLabel(agentMaxTotalToolCallsBinding.wrappedValue))
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textPrimary)
                        .frame(width: 56, alignment: .trailing)
                }
                .frame(width: 150)
            }

            SettingsRow("单轮 MCP 上限") {
                Stepper(value: agentMaxCallsPerTurnBinding, in: 0...20) {
                    Text(policyLimitLabel(agentMaxCallsPerTurnBinding.wrappedValue))
                        .font(SliceFont.body)
                        .foregroundColor(SliceColor.textPrimary)
                        .frame(width: 56, alignment: .trailing)
                }
                .frame(width: 150)
            }

            SettingsRow("跳过重复参数") {
                Toggle("", isOn: agentSkipDuplicateToolCallsBinding)
                    .labelsHidden()
            }

            SettingsRow("限流后停止") {
                Toggle("", isOn: agentStopOnRateLimitBinding)
                    .labelsHidden()
            }
        }
    }

    /// 调用策略上限在 UI 中的展示文本。
    /// - Parameter value: 绑定中的数值；0 表示自动。
    /// - Returns: 展示文案。
    private func policyLimitLabel(_ value: Int) -> String {
        value <= 0 ? "自动" : "\(value)"
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
            Text("基础信息仍可编辑；Pipeline 的专用编辑器将在后续阶段接入。")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
