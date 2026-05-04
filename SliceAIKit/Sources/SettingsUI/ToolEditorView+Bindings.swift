// SliceAIKit/Sources/SettingsUI/ToolEditorView+Bindings.swift
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
}
