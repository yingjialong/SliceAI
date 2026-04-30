// SliceAIKit/Sources/SettingsUI/ToolEditorView.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 单个 Tool 的编辑表单
///
/// 输入通过 `@Binding` 直接指向 `Configuration.tools[i]`，修改即时反映到 VM。
/// Provider 列表只读展示，用于 Picker 选择关联的供应商。
///
/// 样式采用 DesignSystem：SectionCard 分组 + SettingsRow 行布局，
/// 不使用 Form/Section（FormStyle.grouped 在内联展开场景有额外内边距不适用）。
public struct ToolEditorView: View {

    /// 正在编辑的 Tool 的双向绑定
    @Binding public var tool: Tool

    /// 可选的 Provider 列表，作为 Picker 数据源
    public let providers: [Provider]

    /// "添加变量"对话框是否展示
    @State var showAddVariableAlert = false

    /// 对话框里待输入的变量名
    @State var newVariableKey = ""

    /// v0.2 设置页可编辑的展示模式白名单，避免暴露尚未实现的 file/silent/structured
    static let editableDisplayModes: [SliceCore.DisplayMode] = [.window, .bubble, .replace]

    /// 构造 Tool 编辑视图
    /// - Parameters:
    ///   - tool: 指向 Configuration 中某个 Tool 的绑定
    ///   - providers: 供 Picker 显示的 Provider 列表
    public init(tool: Binding<Tool>, providers: [Provider]) {
        self._tool = tool
        self.providers = providers
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.lg) {
            // 基础信息分组：名称 / 图标 / 描述
            basicsCard

            if isPromptTool {
                // 提示词分组：System / User
                promptCard

                // Provider 分组：关联 Provider / 模型覆写 / 采样温度
                providerCard

                // 自定义变量分组（始终显示——空态也要提供"添加变量"入口）
                variablesCard
            } else {
                unsupportedKindCard
            }
        }
        // 添加变量对话框
        .alert("添加变量", isPresented: $showAddVariableAlert) {
            TextField("变量名（如 language）", text: $newVariableKey)
            Button("添加") { addVariable() }
            Button("取消", role: .cancel) { newVariableKey = "" }
        } message: {
            Text("变量名将作为提示词模板占位符，例如填写 language 后可在 prompt 里用 {{language}} 引用。")
        }
    }
}
