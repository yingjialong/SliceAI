// SliceAIKit/Sources/SettingsUI/ToolEditorView.swift
import DesignSystem
import SliceCore
import SwiftUI

/// 单个 Tool 的编辑表单。
///
/// v2 中该 binding 可以指向 `ToolEditorDraftSession` 的本地草稿；
/// 只有外层页面执行 Save 时，草稿才会写回 `Configuration.tools`。
/// Provider 列表只读展示，用于 Picker 选择关联的供应商。
///
/// 样式采用 DesignSystem：SectionCard 分组 + SettingsRow 行布局，
/// 不使用 Form/Section（FormStyle.grouped 在内联展开场景有额外内边距不适用）。
public struct ToolEditorView: View {

    /// 正在编辑的 Tool 的双向绑定；v2 可来自本地草稿。
    @Binding public var tool: Tool

    /// 可选的 Provider 列表，作为 Picker 数据源
    public let providers: [Provider]

    /// 当前配置中的完整工具列表，用于跨工具热键冲突校验
    public let tools: [Tool]

    /// 全局热键配置绑定，工具热键通过 `hotkeys.tools[tool.id]` 集中保存
    @Binding public var hotkeys: HotkeyBindings

    /// 当前 registry 中可绑定到 Agent Tool 的 enabled skills
    public let availableSkills: [SliceCore.Skill]

    /// 工具热键录制完成后的回调，用于立即持久化并触发 App 重新注册热键
    let onHotkeyCommit: (() -> Void)?

    /// "添加变量"对话框是否展示
    @State var showAddVariableAlert = false

    /// 对话框里待输入的变量名
    @State var newVariableKey = ""

    /// 设置页可编辑的展示模式白名单；
    /// file/silent 依赖 side effect 配置，暂不在基础编辑器暴露。
    static let editableDisplayModes: [SliceCore.DisplayMode] = [.window, .bubble, .replace, .structured]

    /// 构造 Tool 编辑视图
    /// - Parameters:
    ///   - tool: 当前编辑 Tool 的绑定；v2 中可指向本地草稿而非生产配置
    ///   - providers: 供 Picker 显示的 Provider 列表
    ///   - tools: 当前配置中的完整工具列表
    ///   - hotkeys: 指向 Configuration.hotkeys 的绑定
    ///   - onHotkeyCommit: 工具热键录制完成后的回调
    public init(
        tool: Binding<Tool>,
        providers: [Provider],
        tools: [Tool],
        hotkeys: Binding<HotkeyBindings>,
        availableSkills: [SliceCore.Skill] = [],
        onHotkeyCommit: (() -> Void)? = nil
    ) {
        self._tool = tool
        self.providers = providers
        self.tools = tools
        self._hotkeys = hotkeys
        self.availableSkills = availableSkills
        self.onHotkeyCommit = onHotkeyCommit
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
            } else if isAgentTool {
                // Agent 提示词分组：System / Initial User
                agentPromptCard

                // Agent Provider 与 ReAct 轮数分组
                agentProviderCard

                // Agent Skill 绑定分组
                agentSkillsCard

                // MCP allowlist 文本编辑分组
                agentMCPAllowlistCard

                // MCP 调用策略分组：总量、单轮、重复参数和限流停止
                agentToolCallPolicyCard
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
            Text(
                "变量名将作为提示词模板占位符，"
                + "例如填写 language 后可在 prompt 里用 {{language}} 引用。"
            )
        }
    }
}
