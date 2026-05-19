// SliceAIKit/Sources/SettingsUI/ToolEditorView+Bindings.swift
import HotkeyManager
import SliceCore
import SwiftUI

// MARK: - V2 PromptTool Bindings

extension ToolEditorView {

    /// System Prompt 的 V2 PromptTool 绑定，空字符串回写为 nil。
    var systemPromptBinding: Binding<String> {
        Binding(
            get: {
                if case .prompt(let promptTool) = tool.kind {
                    return promptTool.systemPrompt ?? ""
                }
                return ""
            },
            set: { newValue in
                if case .prompt(var promptTool) = tool.kind {
                    // 清空输入等价于删除可选字段，避免持久化空字符串污染配置。
                    promptTool.systemPrompt = newValue.isEmpty ? nil : newValue
                    tool.kind = .prompt(promptTool)
                }
            }
        )
    }

    /// User Prompt 的 V2 PromptTool 绑定。
    var userPromptBinding: Binding<String> {
        Binding(
            get: {
                if case .prompt(let promptTool) = tool.kind {
                    return promptTool.userPrompt
                }
                return ""
            },
            set: { newValue in
                if case .prompt(var promptTool) = tool.kind {
                    promptTool.userPrompt = newValue
                    tool.kind = .prompt(promptTool)
                }
            }
        )
    }

    /// Provider id 的 V2 PromptTool 绑定，切换 Provider 时清空模型覆写。
    var providerIdBinding: Binding<String> {
        Binding(
            get: {
                if case .prompt(let promptTool) = tool.kind,
                   case .fixed(let providerId, _) = promptTool.provider {
                    return providerId
                }
                return ""
            },
            set: { newProviderId in
                if case .prompt(var promptTool) = tool.kind {
                    // 旧 modelId 可能只适用于旧 Provider，切换 Provider 时必须回落到新 Provider 默认模型。
                    promptTool.provider = .fixed(providerId: newProviderId, modelId: nil)
                    tool.kind = .prompt(promptTool)
                    print("[ToolEditorView] provider changed for tool '\(tool.id)'")
                }
            }
        )
    }

    /// 模型覆写的 V2 PromptTool 绑定，空字符串回写为 nil。
    var modelIdBinding: Binding<String> {
        Binding(
            get: {
                if case .prompt(let promptTool) = tool.kind,
                   case .fixed(_, let modelId) = promptTool.provider {
                    return modelId ?? ""
                }
                return ""
            },
            set: { newModelText in
                if case .prompt(var promptTool) = tool.kind,
                   case .fixed(let providerId, _) = promptTool.provider {
                    promptTool.provider = .fixed(
                        providerId: providerId,
                        modelId: newModelText.isEmpty ? nil : newModelText
                    )
                    tool.kind = .prompt(promptTool)
                }
            }
        )
    }

    /// Temperature 的 V2 PromptTool 绑定；nil 时按 UI 旧默认值 0.3 展示。
    var temperatureBinding: Binding<Double> {
        Binding(
            get: {
                if case .prompt(let promptTool) = tool.kind {
                    return promptTool.temperature ?? 0.3
                }
                return 0.3
            },
            set: { newValue in
                if case .prompt(var promptTool) = tool.kind {
                    promptTool.temperature = newValue
                    tool.kind = .prompt(promptTool)
                }
            }
        )
    }

    /// 当前 PromptTool 的 variables 快照；非 prompt 工具在 v0.2 UI 中显示为空。
    var variablesAccessor: [String: String] {
        if case .prompt(let promptTool) = tool.kind {
            return promptTool.variables
        }
        return [:]
    }

    /// 设置指定变量值。
    /// - Parameters:
    ///   - value: 新变量值。
    ///   - key: 变量名。
    func setVariableValue(_ value: String, for key: String) {
        if case .prompt(var promptTool) = tool.kind {
            promptTool.variables[key] = value
            tool.kind = .prompt(promptTool)
        }
    }

    /// 删除指定变量。
    /// - Parameter key: 变量名。
    func removeVariable(forKey key: String) {
        if case .prompt(var promptTool) = tool.kind {
            promptTool.variables.removeValue(forKey: key)
            tool.kind = .prompt(promptTool)
            print("[ToolEditorView] removeVariable: key=\(key) tool=\(tool.id)")
        }
    }

    /// 添加指定变量，重复 key 会直接忽略。
    /// - Parameter key: 变量名。
    func addPromptVariable(forKey key: String) {
        if case .prompt(var promptTool) = tool.kind {
            guard promptTool.variables[key] == nil else { return }
            promptTool.variables[key] = ""
            tool.kind = .prompt(promptTool)
            print("[ToolEditorView] addVariable: key=\(key) tool=\(tool.id)")
        }
    }

    // MARK: - V2 AgentTool Bindings

    /// Agent System Prompt 绑定，空字符串回写为 nil。
    var agentSystemPromptBinding: Binding<String> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind {
                    return agentTool.systemPrompt ?? ""
                }
                return ""
            },
            set: { newValue in
                if case .agent(var agentTool) = tool.kind {
                    agentTool.systemPrompt = newValue.isEmpty ? nil : newValue
                    tool.kind = .agent(agentTool)
                }
            }
        )
    }

    /// Agent 初始用户提示词绑定。
    var agentInitialUserPromptBinding: Binding<String> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind {
                    return agentTool.initialUserPrompt
                }
                return ""
            },
            set: { newValue in
                if case .agent(var agentTool) = tool.kind {
                    agentTool.initialUserPrompt = newValue
                    tool.kind = .agent(agentTool)
                }
            }
        )
    }

    /// Agent Provider id 绑定；切换 Provider 时把 capability/cascade 归一为 fixed，便于用户明确选择。
    var agentProviderIdBinding: Binding<String> {
        Binding(
            get: {
                guard case .agent(let agentTool) = tool.kind else { return "" }
                return selectedProviderId(for: agentTool.provider)
            },
            set: { newProviderId in
                if case .agent(var agentTool) = tool.kind {
                    agentTool.provider = .fixed(providerId: newProviderId, modelId: nil)
                    tool.kind = .agent(agentTool)
                    print("[ToolEditorView] agent provider changed for tool '\(tool.id)'")
                }
            }
        )
    }

    /// Agent 模型覆写绑定；空字符串表示使用 Provider 默认模型。
    var agentModelIdBinding: Binding<String> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind,
                   case .fixed(_, let modelId) = agentTool.provider {
                    return modelId ?? ""
                }
                return ""
            },
            set: { newModelText in
                if case .agent(var agentTool) = tool.kind {
                    let providerId = selectedProviderId(for: agentTool.provider)
                    agentTool.provider = .fixed(
                        providerId: providerId,
                        modelId: newModelText.isEmpty ? nil : newModelText
                    )
                    tool.kind = .agent(agentTool)
                }
            }
        )
    }

    /// Agent ReAct 轮数绑定；只控制 LLM 轮数，不再作为 MCP 总调用预算。
    var agentMaxStepsBinding: Binding<Int> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind {
                    return max(1, agentTool.maxSteps)
                }
                return 1
            },
            set: { newValue in
                if case .agent(var agentTool) = tool.kind {
                    agentTool.maxSteps = max(1, newValue)
                    tool.kind = .agent(agentTool)
                }
            }
        )
    }

    /// Agent MCP allowlist 文本绑定；写入时同步 `tool.permissions` 中的 MCP 权限声明。
    var agentMCPAllowlistTextBinding: Binding<String> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind {
                    return AgentMCPAllowlistTextCodec.render(agentTool.mcpAllowlist)
                }
                return ""
            },
            set: { newValue in
                if case .agent(var agentTool) = tool.kind {
                    let refs = normalizedMCPRefs(AgentMCPAllowlistTextCodec.parse(newValue))
                    agentTool.mcpAllowlist = refs
                    tool.kind = .agent(agentTool)
                    syncMCPPermissions(with: refs)
                    print("[ToolEditorView] agent MCP allowlist updated for tool '\(tool.id)' count=\(refs.count)")
                }
            }
        )
    }

    /// Agent 单次运行 MCP 总调用上限绑定；0 表示使用执行器默认策略。
    var agentMaxTotalToolCallsBinding: Binding<Int> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind {
                    return agentTool.toolCallPolicy?.maxTotalCalls ?? 0
                }
                return 0
            },
            set: { newValue in
                updateAgentToolCallPolicy { policy in
                    policy.maxTotalCalls = newValue <= 0 ? nil : newValue
                }
            }
        )
    }

    /// Agent 单轮 MCP 调用上限绑定；0 表示使用执行器默认策略。
    var agentMaxCallsPerTurnBinding: Binding<Int> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind {
                    return agentTool.toolCallPolicy?.maxCallsPerTurn ?? 0
                }
                return 0
            },
            set: { newValue in
                updateAgentToolCallPolicy { policy in
                    policy.maxCallsPerTurn = newValue <= 0 ? nil : newValue
                }
            }
        )
    }

    /// Agent 是否跳过完全相同参数的重复 MCP 调用。
    var agentSkipDuplicateToolCallsBinding: Binding<Bool> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind {
                    return (agentTool.toolCallPolicy?.duplicateArgumentStrategy ?? .skipExactArguments)
                        == .skipExactArguments
                }
                return true
            },
            set: { enabled in
                updateAgentToolCallPolicy { policy in
                    policy.duplicateArgumentStrategy = enabled ? .skipExactArguments : .allow
                }
            }
        )
    }

    /// Agent 命中 MCP rate limit 后是否停止后续 MCP 调用。
    var agentStopOnRateLimitBinding: Binding<Bool> {
        Binding(
            get: {
                if case .agent(let agentTool) = tool.kind {
                    return agentTool.toolCallPolicy?.stopOnRateLimit ?? true
                }
                return true
            },
            set: { enabled in
                updateAgentToolCallPolicy { policy in
                    policy.stopOnRateLimit = enabled
                }
            }
        )
    }

    /// 更新 Agent tool-call policy，缺省时先创建默认 policy。
    /// - Parameter update: 对 policy 的局部修改。
    private func updateAgentToolCallPolicy(_ update: (inout AgentToolCallPolicy) -> Void) {
        if case .agent(var agentTool) = tool.kind {
            var policy = agentTool.toolCallPolicy ?? AgentToolCallPolicy()
            update(&policy)
            agentTool.toolCallPolicy = policy
            tool.kind = .agent(agentTool)
            print("[ToolEditorView] agent tool-call policy updated for tool '\(tool.id)'")
        }
    }

    /// 根据 ProviderSelection 推导当前 UI 展示的 provider id。
    /// - Parameter selection: Agent 当前 provider 选择策略。
    /// - Returns: 可用于 Picker 的 provider id。
    private func selectedProviderId(for selection: ProviderSelection) -> String {
        switch selection {
        case .fixed(let providerId, _):
            return providerId
        case .capability(_, let prefer):
            return prefer.first
                ?? providers.first { $0.capabilities.contains(.toolCalling) }?.id
                ?? providers.first?.id
                ?? ""
        case .cascade(let rules):
            return rules.first?.providerId ?? providers.first?.id ?? ""
        }
    }

    /// 对 MCP ref 去重并排序，保证配置文件稳定可 diff。
    /// - Parameter refs: 原始 MCP ref 列表。
    /// - Returns: 稳定排序后的 MCP ref 列表。
    private func normalizedMCPRefs(_ refs: [MCPToolRef]) -> [MCPToolRef] {
        Array(Set(refs)).sorted {
            if $0.server == $1.server {
                return $0.tool < $1.tool
            }
            return $0.server < $1.server
        }
    }

    /// 根据 Agent allowlist 同步静态 MCP 权限声明。
    /// - Parameter refs: 当前 Agent 允许调用的 MCP tools。
    private func syncMCPPermissions(with refs: [MCPToolRef]) {
        let nonMCPPermissions = tool.permissions.filter { permission in
            if case .mcp = permission { return false }
            return true
        }
        let grouped = Dictionary(grouping: refs, by: \.server)
        let mcpPermissions = grouped.keys.sorted().map { server in
            Permission.mcp(server: server, tools: grouped[server]?.map(\.tool).sorted())
        }
        tool.permissions = nonMCPPermissions + mcpPermissions
    }

    /// 工具级热键绑定，写入时同步集中映射与 Tool.hotkey 兼容字段
    var toolHotkeyBinding: Binding<String> {
        Binding(
            get: {
                hotkeys.tools[tool.id] ?? tool.hotkey ?? ""
            },
            set: { newValue in
                let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty {
                    hotkeys.tools.removeValue(forKey: tool.id)
                    tool.hotkey = nil
                    print("[ToolEditorView] hotkey cleared for tool '\(tool.id)'")
                } else {
                    hotkeys.tools[tool.id] = trimmed
                    tool.hotkey = trimmed
                    print("[ToolEditorView] hotkey updated for tool '\(tool.id)'")
                }
            }
        )
    }

    /// 当前工具热键的校验提示；nil 表示没有影响当前工具的问题
    var toolHotkeyValidationMessage: String? {
        let issues = HotkeyBindingValidator.issues(
            commandPalette: hotkeys.toggleCommandPalette,
            tools: effectiveToolHotkeyMap
        )
        guard let issue = issues.first(where: { HotkeyBindingValidator.issue($0, involves: tool.id) }) else {
            return nil
        }
        return message(for: issue)
    }

    /// 合并集中映射和 Tool.hotkey 兼容字段，避免手写配置只填旧占位字段时 UI 不提示
    private var effectiveToolHotkeyMap: [String: String] {
        HotkeyBindingValidator.effectiveToolHotkeys(bindings: hotkeys, tools: tools)
    }

    /// 把校验问题转换为设置页展示文案
    /// - Parameter issue: HotkeyManager 返回的纯校验问题
    /// - Returns: 面向用户的中文提示
    private func message(for issue: HotkeyBindingIssue) -> String {
        switch issue {
        case .invalidCommandPalette:
            return "命令面板快捷键无效"
        case .invalidTool:
            return "当前工具快捷键无效"
        case .commandPaletteConflict(_, let hotkey):
            return "与命令面板快捷键 \(hotkey) 冲突"
        case .toolConflict(let first, let second, let hotkey):
            let other = first == tool.id ? second : first
            return "与工具 \(other) 的快捷键 \(hotkey) 冲突"
        }
    }
}
