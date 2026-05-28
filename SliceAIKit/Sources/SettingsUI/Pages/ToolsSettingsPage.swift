// SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift
//
// Tools 设置页：列表 + 草稿编辑展开区 + Reminders 风格拖拽排序
// 用户点击列表项即展开 ToolEditor v2（单选展开，再点收起）
//
// 拖拽方案（Reminders 风格）：
//   1. gripHandle 挂 `.onDrag`，把 tool.id 装进 NSItemProvider + 同步写 `draggedId`
//   2. 每行挂 `.onDrop(delegate: ToolReorderDropDelegate)`，delegate 的
//      `dropUpdated` 根据光标 y 是否过半判断"插入到本行前还是后"，更新
//      `dropTargetIndex`；**不做 move，只更新插入指示线位置**
//   3. 行上/下沿以 overlay 形式画 `InsertionIndicator`（蓝细线+空心圆）
//   4. `performDrop` 松手时才执行 `tools.move(fromOffsets:toOffset:)`
//   5. 持久化通过 `.onChange(of: tools)` 做 debounce 保存；ToolEditor v2
//      先写本地草稿，只有 Save 才更新 tools 并触发保存
//
// 这套相较于"实时挤开"方案更贴近 macOS 原生拖拽体感（Finder / Reminders）：
// 其他行不抖、被拖项由系统预览跟手、指示线清晰表达落位点。
import DesignSystem
import HotkeyManager
import SliceCore
import SwiftUI
import UniformTypeIdentifiers

// MARK: - ToolsSettingsPage

/// Tools 设置页
///
/// 布局：
///   - 顶部操作区：右对齐"添加工具"按钮
///   - 工具列表：每行显示图标 + 工具名 + 描述；点击展开编辑区
///   - 编辑区：ToolEditorV2View 内嵌于内联展开卡片；选另一行或空白处收起
///
/// 持久化：新增或编辑先进入 `ToolEditorDraftSession`，点击 Save 后才写回
/// `configuration.tools`；删除和拖拽仍直接修改 tools 并由 `.onChange(of: tools)`
/// 驱动 debounced save。
public struct ToolsSettingsPage: View {

    /// 写盘前的静默等待时长：用户连续编辑时避免频繁写盘
    static let saveDebounceInterval: UInt64 = 600_000_000  // 600 ms

    /// 拖拽上/下半判定用的行高估算值（硬编码）
    ///
    /// ToolRow 内容：icon 32pt + 上下 padding 8pt×2 = 48pt，加上文字换行约 50pt。
    /// 2~3pt 误差对"过半 / 未过半"判定不敏感；真实需要时再改为 PreferenceKey 测量。
    private static let estimatedRowHeight: CGFloat = 50

    /// 设置视图模型，用于读写 configuration.tools
    @ObservedObject var viewModel: SettingsViewModel

    /// 当前 ToolEditor 草稿会话；nil 表示无展开编辑器。
    @State var editingSession: ToolEditorDraftSession?

    /// 当前草稿校验错误；Save 或 Run 前校验失败时展示。
    @State var validationErrors: [ToolDraftValidationError] = []

    /// 待确认删除的 Tool id；非 nil 时弹出删除确认 alert
    @State var pendingDeleteId: String?

    /// 当前被拖动的 Tool.id；非 nil 表示正有一次拖拽进行中
    @State var draggedId: String?

    /// 如果此刻松手，插入点（Array.move 的 toOffset 语义，0…count）
    ///
    /// - nil：不显示任何指示线
    /// - 0：插入到第一个工具之前
    /// - N：插入到 tools[N] 之前（等于最后位置时在列表尾部）
    @State var dropTargetIndex: Int?

    /// debounced save 的当前 Task；新变动进来就 cancel 重排
    @State var saveDebounceTask: Task<Void, Never>?

    /// 构造 Tools 设置页
    /// - Parameter viewModel: 宿主注入的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        SettingsPageShell(title: "Tools", subtitle: "管理工具列表、Prompt 与 Agent 配置。") {
            actionRow
            if case .creating = editingSession {
                creatingEditor
            }
            if viewModel.configuration.tools.isEmpty {
                emptyState
            } else {
                toolList
            }
        }
        // 删除确认：用户误点垃圾桶时提供二次确认兜底
        .alert("删除工具", isPresented: deleteAlertPresented, presenting: pendingDeleteTool) { tool in
            Button("删除", role: .destructive) {
                performDelete(id: tool.id)
                pendingDeleteId = nil
            }
            Button("取消", role: .cancel) { pendingDeleteId = nil }
        } message: { tool in
            Text("确定要删除「\(tool.name)」吗？此操作不可撤销。")
        }
        // 核心持久化钩子：Save、排序、删除造成的 tools 变动会在停手后落盘；
        // 未保存草稿不触碰 tools，因此不会误触发这里。
        .onChange(of: viewModel.configuration.tools) { _, _ in
            scheduleDebouncedSave()
        }
    }

    /// 将 pendingDeleteId 适配为 alert 的 Bool 绑定
    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { pendingDeleteId != nil },
            set: { if !$0 { pendingDeleteId = nil } }
        )
    }

    /// 当前待删除的 Tool 对象，用于 alert 展示真实名称
    private var pendingDeleteTool: Tool? {
        guard let id = pendingDeleteId else { return nil }
        return viewModel.configuration.tools.first { $0.id == id }
    }

    // MARK: - 顶部操作行

    /// 顶部右对齐"添加工具"按钮
    private var actionRow: some View {
        HStack {
            Spacer()
            PillButton("添加 Prompt", icon: "plus", style: .secondary) {
                addPromptTool()
            }
            PillButton("添加 Agent", icon: "plus", style: .primary) {
                addAgentTool()
            }
        }
    }

    // MARK: - 空态

    /// 空列表提示
    private var emptyState: some View {
        SectionCard {
            VStack(spacing: SliceSpacing.base) {
                Image(systemName: "hammer")
                    .font(.system(size: 28))
                    .foregroundColor(SliceColor.textTertiary)
                Text("暂无工具，点击\u{201C}添加工具\u{201D}开始配置。")
                    .font(SliceFont.callout)
                    .foregroundColor(SliceColor.textSecondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SliceSpacing.xl)
        }
    }

    // MARK: - 工具列表

    /// 完整工具列表（每行是 drop 目标 + 可能叠加插入指示线）
    ///
    /// 外层 VStack 上挂一个兜底 `.onDrop(delegate:)`——用户把拖拽松手在行
    /// 之间的空隙或者列表底部 padding 区时，行内 delegate 不会触发，这里兜底
    /// commit 一次 reorder；同时也作为 dropUpdated 的默认容器处理最顶/最底的
    /// 特殊插入位置。
    private var toolList: some View {
        VStack(spacing: SliceSpacing.sm) {
            ForEach(viewModel.configuration.tools.indices, id: \.self) { index in
                toolListItem(for: $viewModel.configuration.tools[index], index: index)
            }
        }
        // 插入指示线切换时淡入淡出，避免线在不同 slot 之间"闪"
        .animation(.easeOut(duration: 0.12), value: dropTargetIndex)
        // 兜底 drop：行外空白区松手也能完成 reorder；detecting only）
        .onDrop(of: [UTType.plainText], isTargeted: nil) { _ in
            commitReorder()
            return true
        }
    }

    /// 单个工具列表项（行 + 展开编辑区 + drop 接收 + 插入指示线 overlay）
    ///
    /// - Parameters:
    ///   - binding: Tool 的双向绑定；行展示仍使用配置快照，编辑器改用本地草稿
    ///   - index: 当前行在 tools 数组中的索引
    @ViewBuilder
    private func toolListItem(for binding: Binding<Tool>, index: Int) -> some View {
        let tool = binding.wrappedValue
        let isExpanded = isEditing(tool.id)
        let isLast = index == viewModel.configuration.tools.count - 1

        VStack(spacing: 0) {
            makeToolRow(tool: tool, isExpanded: isExpanded)
            if isExpanded {
                Rectangle().fill(SliceColor.divider).frame(height: 0.5)
                toolEditorV2(fallbackTool: tool).transition(.opacity)
            }
        }
        .clipped()
        .background(rowBackground(isExpanded: isExpanded))
        // 顶部指示线（插入到 index 之前）
        .overlay(alignment: .top) {
            if dropTargetIndex == index {
                InsertionIndicator()
                    .padding(.horizontal, SliceSpacing.xs)
                    .offset(y: -(SliceSpacing.sm / 2 + InsertionIndicator.height / 2))
            }
        }
        // 底部指示线（仅最后一行显示——插入到末尾，dropTargetIndex == count）
        .overlay(alignment: .bottom) {
            if isLast && dropTargetIndex == viewModel.configuration.tools.count {
                InsertionIndicator()
                    .padding(.horizontal, SliceSpacing.xs)
                    .offset(y: SliceSpacing.sm / 2 + InsertionIndicator.height / 2)
            }
        }
        // 本行的 drop 委派：更新 dropTargetIndex / commit reorder
        .onDrop(
            of: [UTType.plainText],
            delegate: ToolReorderDropDelegate(
                targetIndex: index,
                rowHeight: Self.estimatedRowHeight,
                tools: $viewModel.configuration.tools,
                draggedId: $draggedId,
                dropTargetIndex: $dropTargetIndex
            )
        )
    }

    /// 构造列表行视图
    /// - Parameters:
    ///   - tool: 当前行对应的工具（只读快照）
    ///   - isExpanded: 是否当前展开编辑区
    private func makeToolRow(tool: Tool, isExpanded: Bool) -> ToolRow {
        ToolRow(
            tool: tool,
            isExpanded: isExpanded,
            onToggle: {
                // 拖动中忽略 tap，避免松手瞬间误触切换
                guard draggedId == nil else { return }
                guard canReplaceEditingSession() else { return }
                withAnimation(SliceAnimation.standard) {
                    if case .editingExisting(let original, _) = editingSession, original.id == tool.id {
                        editingSession = nil
                    } else {
                        editingSession = .existing(
                            original: tool,
                            hotkeys: viewModel.configuration.hotkeys
                        )
                        validationErrors = []
                    }
                }
            },
            onDelete: { pendingDeleteId = tool.id },
            onDragStart: {
                if editingSession != nil {
                    guard canReplaceEditingSession() else { return }
                    editingSession = nil
                    validationErrors = []
                }
                draggedId = tool.id
                dropTargetIndex = nil
                print("[ToolsSettingsPage] drag: start id=\(tool.id)")
            }
        )
    }

    /// 行背景：圆角表面 + 边框描边（展开时描边变 accent 色）
    private func rowBackground(isExpanded: Bool) -> some View {
        let strokeColor = isExpanded ? SliceColor.accent.opacity(0.4) : SliceColor.border
        return RoundedRectangle(cornerRadius: SliceRadius.card)
            .fill(SliceColor.surface)
            .overlay(
                RoundedRectangle(cornerRadius: SliceRadius.card)
                    .stroke(strokeColor, lineWidth: 0.5)
            )
    }

    // MARK: - 内联编辑区

    /// 创建新工具时显示在操作行下方的草稿编辑器。
    private var creatingEditor: some View {
        VStack(spacing: 0) {
            toolEditorV2(fallbackTool: nil)
        }
        .background(rowBackground(isExpanded: true))
    }

    /// 当前是否正在编辑指定 Tool。
    /// - Parameter toolId: Tool id。
    /// - Returns: 若当前 editing session 指向该 Tool 则返回 true。
    private func isEditing(_ toolId: String) -> Bool {
        guard case .editingExisting(let original, _) = editingSession else { return false }
        return original.id == toolId
    }

    /// 构造 ToolEditor v2，使用本地草稿 binding 避免直接写入正式配置。
    /// - Parameter fallbackTool: SwiftUI 关闭编辑器瞬间的兜底 Tool。
    /// - Returns: ToolEditor v2 容器。
    private func toolEditorV2(fallbackTool: Tool?) -> some View {
        let binding = Binding<ToolEditorDraft>(
            get: {
                if let editingSession {
                    return editingSession.draft
                }
                let tool = fallbackTool ?? viewModel.configuration.tools.first ?? makeEmptyPromptDraftTool()
                return ToolEditorDraft(tool: tool, hotkeys: viewModel.configuration.hotkeys)
            },
            set: { newDraft in
                editingSession?.draft = newDraft
            }
        )
        return VStack(alignment: .leading, spacing: SliceSpacing.base) {
            ToolEditorV2View(
                draft: binding,
                providers: viewModel.configuration.providers,
                tools: viewModel.configuration.tools,
                availableSkills: viewModel.availableAgentSkills,
                runner: viewModel.playgroundRunner,
                validateDraft: validateDraftForRun,
                onSave: saveEditingSession,
                onRevert: revertEditingSession
            )
            if !validationErrors.isEmpty {
                validationErrorList
            }
        }
        .padding(SliceSpacing.xl)
    }

    /// 草稿校验错误列表。
    private var validationErrorList: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.xs) {
            ForEach(Array(validationErrors.enumerated()), id: \.offset) { _, error in
                Text(error.localizedDescription)
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.error)
            }
        }
    }

    /// Save 和 Playground Run 共用的草稿校验。
    /// - Parameter draft: 当前待校验草稿。
    /// - Returns: 校验错误列表，空数组表示可保存或运行。
    func validateDraftForRun(_ draft: ToolEditorDraft) -> [ToolDraftValidationError] {
        ToolDraftValidator.validate(
            draft: draft,
            existingTools: viewModel.configuration.tools,
            availableSkills: viewModel.availableAgentSkills,
            originalToolId: editingSession?.originalToolId,
            commandPaletteEnabled: viewModel.configuration.triggers.commandPaletteEnabled
        )
    }

    /// 清理指向指定 Tool 的编辑会话。
    /// - Parameter toolId: 可能被删除或移动的 Tool id。
    func clearEditingSessionIfNeeded(toolId: String) {
        if case .editingExisting(let original, _) = editingSession, original.id == toolId {
            editingSession = nil
            validationErrors = []
        }
    }

    /// 创建一个兜底 Prompt Tool 草稿。
    /// - Returns: 可用于瞬时 fallback 的 Prompt Tool。
    private func makeEmptyPromptDraftTool() -> Tool {
        let providerId = viewModel.configuration.providers.first?.id ?? ""
        return Tool(
            id: makeNewToolID(prefix: "tool"),
            name: "新工具",
            icon: "wand.and.stars",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: nil,
                userPrompt: "{{selection}}",
                contexts: [],
                provider: .fixed(providerId: providerId, modelId: nil),
                temperature: 0.7,
                maxTokens: nil,
                variables: [:]
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
    }

}

// MARK: - ToolReorderDropDelegate

/// 工具行的 drop 接收代理——只负责更新插入指示线位置，不做实时 reorder
///
/// 与旧版"dropEntered 立即 move"的实现相反：本实现在 `dropUpdated` 里根据
/// 光标在本行的上/下半，更新 `dropTargetIndex`，**不触碰 tools 数组**。
/// 真正的 `tools.move` 发生在 `performDrop`——这让其他行始终不动，被拖项
/// 由系统拖拽预览跟随光标，UI 视觉完全稳定、没有"乱挤开"的抖动。
///
/// 设计取舍：不从 NSItemProvider 解析 draggedId（避免异步 loadObject 的 latency），
/// 而是直接读 @Binding；payload 仅作为 SwiftUI drag 管道的契约占位。
private struct ToolReorderDropDelegate: DropDelegate {

    /// 本行在 tools 数组中的索引
    let targetIndex: Int

    /// 用于判断光标落在本行上半 / 下半的行高估算值
    let rowHeight: CGFloat

    /// 全局 v2 工具数组的 @Binding；delegate 在 performDrop 里 mutate
    @Binding var tools: [Tool]

    /// 当前被拖的 Tool.id；由外层 `.onDrag` 写入，commit 后置 nil
    @Binding var draggedId: String?

    /// 若此刻松手，插入位置（Array.move 的 toOffset 语义）；nil 不显示指示线
    @Binding var dropTargetIndex: Int?

    /// 保证系统光标显示"移动"而非"复制"箭头
    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard draggedId != nil else { return nil }
        // info.location.y 相对本行坐标系，0 在行顶部、rowHeight 在行底部
        let isUpperHalf = info.location.y < rowHeight / 2
        // 上半 → 插到本行前（index）；下半 → 插到本行后（index+1）
        let newIndex = isUpperHalf ? targetIndex : targetIndex + 1
        // 只在值真正变化时写回，避免 dropUpdated 高频触发导致无效重绘
        if dropTargetIndex != newIndex {
            dropTargetIndex = newIndex
        }
        return DropProposal(operation: .move)
    }

    /// 只有已经发起本页面内部拖拽才接受 drop——防御外部 drag 源误触
    func validateDrop(info: DropInfo) -> Bool {
        draggedId != nil
    }

    /// 拖入本行时：顺便把插入指示设一次，避免 dropUpdated 首帧延迟导致线不显示
    func dropEntered(info: DropInfo) {
        guard draggedId != nil else { return }
        let isUpperHalf = info.location.y < rowHeight / 2
        let newIndex = isUpperHalf ? targetIndex : targetIndex + 1
        if dropTargetIndex != newIndex {
            dropTargetIndex = newIndex
        }
    }

    /// 松手：执行最终的 reorder + 清状态；save 由外层 onChange(tools) 兜底
    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedId = nil
            dropTargetIndex = nil
        }
        guard let sourceId = draggedId,
              let from = tools.firstIndex(where: { $0.id == sourceId }),
              let target = dropTargetIndex else {
            return false
        }
        // target == from / target == from + 1 都等价于"不移动"，跳过无意义动画
        guard target != from, target != from + 1 else { return true }
        withAnimation(.easeInOut(duration: 0.25)) {
            tools.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: target
            )
        }
        return true
    }
}
