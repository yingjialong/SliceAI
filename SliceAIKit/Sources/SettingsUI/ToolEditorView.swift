// SliceAIKit/Sources/SettingsUI/ToolEditorView.swift
import SwiftUI
import SliceCore

/// 单个 Tool 的编辑表单
///
/// 输入通过 `@Binding` 直接指向 `Configuration.tools[i]`，修改即时反映到 VM。
/// Provider 列表只读展示，用于 Picker 选择关联的供应商。
public struct ToolEditorView: View {

    /// 正在编辑的 Tool 的双向绑定
    @Binding public var tool: Tool

    /// 可选的 Provider 列表，作为 Picker 数据源
    public let providers: [Provider]

    /// 构造 Tool 编辑视图
    /// - Parameters:
    ///   - tool: 指向 Configuration 中某个 Tool 的绑定
    ///   - providers: 供 Picker 显示的 Provider 列表
    public init(tool: Binding<Tool>, providers: [Provider]) {
        self._tool = tool
        self.providers = providers
    }

    public var body: some View {
        Form {
            basicsSection
            promptSection
            providerSection
            variablesSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Sections

    /// 基础信息：名称 / 图标 / 描述
    private var basicsSection: some View {
        Section("Basics") {
            TextField("Name", text: $tool.name)
            TextField("Icon", text: $tool.icon)
            TextField(
                "Description",
                text: Binding(
                    get: { tool.description ?? "" },
                    set: { tool.description = $0.isEmpty ? nil : $0 }
                )
            )
        }
    }

    /// 提示词：System / User / 变量提示
    private var promptSection: some View {
        Section("Prompt") {
            TextField(
                "System",
                text: Binding(
                    get: { tool.systemPrompt ?? "" },
                    set: { tool.systemPrompt = $0.isEmpty ? nil : $0 }
                ),
                axis: .vertical
            )
            .lineLimit(2...5)

            TextField("User", text: $tool.userPrompt, axis: .vertical)
                .lineLimit(3...8)

            Text("可用变量: {{selection}} {{app}} {{url}} {{language}}")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// Provider 绑定 / 模型覆写 / 采样温度
    private var providerSection: some View {
        Section("Provider") {
            Picker("Provider", selection: $tool.providerId) {
                ForEach(providers) { provider in
                    Text(provider.name).tag(provider.id)
                }
            }

            TextField(
                "Model override",
                text: Binding(
                    get: { tool.modelId ?? "" },
                    set: { tool.modelId = $0.isEmpty ? nil : $0 }
                )
            )

            HStack {
                Text("Temperature")
                // Slider 不支持 Optional，因此用非空默认值做桥接；0.3 与
                // DefaultConfiguration 保持一致
                Slider(
                    value: Binding(
                        get: { tool.temperature ?? 0.3 },
                        set: { tool.temperature = $0 }
                    ),
                    in: 0...2
                )
                Text(String(format: "%.2f", tool.temperature ?? 0.3))
                    .frame(width: 48, alignment: .trailing)
            }
        }
    }

    /// 自定义变量键值对（按 key 字典序展示，避免 UI 抖动）
    private var variablesSection: some View {
        Section("Variables") {
            ForEach(Array(tool.variables.keys.sorted()), id: \.self) { key in
                TextField(
                    key,
                    text: Binding(
                        get: { tool.variables[key] ?? "" },
                        set: { tool.variables[key] = $0 }
                    )
                )
            }
        }
    }
}
