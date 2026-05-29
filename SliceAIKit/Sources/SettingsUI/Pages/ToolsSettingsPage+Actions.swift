import DesignSystem
import HotkeyManager
import SliceCore
import SwiftUI

// MARK: - ToolsSettingsPage Actions

extension ToolsSettingsPage {

    /// 添加新 Prompt 工具草稿，不立即写入正式配置。
    func addPromptTool() {
        guard canReplaceEditingSession() else { return }
        let newId = makeNewToolID(prefix: "tool")
        let providerId = viewModel.configuration.providers.first?.id ?? ""
        let prompt = PromptTool(
            systemPrompt: nil,
            userPrompt: "{{selection}}",
            contexts: [],
            provider: .fixed(providerId: providerId, modelId: nil),
            temperature: 0.7,
            maxTokens: nil,
            variables: [:]
        )
        let newTool = Tool(
            id: newId,
            name: "新工具",
            icon: "wand.and.stars",
            description: nil,
            kind: .prompt(prompt),
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
        print("[ToolsSettingsPage] addPromptTool: id=\(newId)")
        editingSession = .creating(draft: ToolEditorDraft(
            tool: newTool,
            hotkeys: viewModel.configuration.hotkeys
        ))
        validationErrors = []
    }

    /// 添加新 Agent 工具草稿，不立即写入正式配置。
    func addAgentTool() {
        guard canReplaceEditingSession() else { return }
        let newId = makeNewToolID(prefix: "agent")
        let providerId = preferredToolCallingProviderID()
        let agent = AgentTool(
            systemPrompt: "You are a concise tool-calling agent. Use allowed MCP tools only when needed.",
            initialUserPrompt: "Use the available tools when useful for:\n\n{{selection}}",
            contexts: [selectionContextRequest()],
            provider: .fixed(providerId: providerId, modelId: nil),
            skills: [],
            mcpAllowlist: [],
            builtinCapabilities: [],
            maxSteps: 4,
            stopCondition: .finalAnswerProvided,
            toolCallPolicy: nil
        )
        let newTool = Tool(
            id: newId,
            name: "新 Agent",
            icon: "sparkles",
            description: nil,
            kind: .agent(agent),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: ["agent", "mcp"]
        )
        print("[ToolsSettingsPage] addAgentTool: id=\(newId)")
        editingSession = .creating(draft: ToolEditorDraft(
            tool: newTool,
            hotkeys: viewModel.configuration.hotkeys
        ))
        validationErrors = []
    }

    /// 保存当前 ToolEditor 草稿。
    func saveEditingSession() {
        guard let session = editingSession else { return }
        let previousHotkeys = viewModel.configuration.hotkeys
        let errors = validateDraftForRun(session.draft)
        guard errors.isEmpty else {
            validationErrors = errors
            print("[ToolsSettingsPage] saveEditingSession: validation failed count=\(errors.count)")
            return
        }
        guard commitDraftToConfiguration(session) else { return }
        validationErrors = []
        editingSession = nil
        finishSaveAfterCommit(previousHotkeys: previousHotkeys)
    }

    /// 把校验通过的草稿写回正式配置；遇到结构性错误时返回 false 并保留会话。
    /// - Parameter session: 当前编辑会话。
    /// - Returns: 写回成功返回 true；index 缺失或创建 id 重复时返回 false。
    private func commitDraftToConfiguration(_ session: ToolEditorDraftSession) -> Bool {
        switch session {
        case .editingExisting(let original, let draft):
            guard let index = viewModel.configuration.tools.firstIndex(where: { $0.id == original.id }) else {
                return false
            }
            let mergedHotkeys = Self.mergedHotkeysForSavingDraft(
                current: viewModel.configuration.hotkeys,
                draft: draft,
                originalToolId: original.id
            )
            viewModel.configuration.tools[index] = draft.tool
            viewModel.configuration.hotkeys = mergedHotkeys
        case .creating(let draft):
            guard !viewModel.configuration.tools.contains(where: { $0.id == draft.tool.id }) else {
                validationErrors = [.duplicateToolId(draft.tool.id)]
                print("[ToolsSettingsPage] saveEditingSession: duplicate creating id=\(draft.tool.id)")
                return false
            }
            let mergedHotkeys = Self.mergedHotkeysForSavingDraft(
                current: viewModel.configuration.hotkeys,
                draft: draft,
                originalToolId: nil
            )
            viewModel.configuration.tools.append(draft.tool)
            viewModel.configuration.hotkeys = mergedHotkeys
        }
        return true
    }

    /// 草稿写回后处理 hotkey 重新注册或 debounced save。
    /// - Parameter previousHotkeys: 写回前的全局 hotkey 配置。
    private func finishSaveAfterCommit(previousHotkeys: HotkeyBindings) {
        if previousHotkeys != viewModel.configuration.hotkeys {
            print("[ToolsSettingsPage] saveEditingSession: hotkeys changed, reloading registrations")
            Task {
                await viewModel.saveHotkeys()
            }
        } else {
            scheduleDebouncedSave()
        }
    }

    /// 放弃当前草稿。
    func revertEditingSession() {
        print("[ToolsSettingsPage] revertEditingSession")
        validationErrors = []
        editingSession = nil
    }

    /// 合并当前草稿工具的 hotkey，不回写草稿里其它工具的旧快照。
    /// - Parameters:
    ///   - current: 保存瞬间的全局 hotkey 配置。
    ///   - draft: 当前 ToolEditor 草稿。
    ///   - originalToolId: 编辑已有工具时的原始 id；创建新工具时为 nil。
    /// - Returns: 只更新当前工具 hotkey 后的新配置。
    nonisolated static func mergedHotkeysForSavingDraft(
        current: HotkeyBindings,
        draft: ToolEditorDraft,
        originalToolId: String?
    ) -> HotkeyBindings {
        var merged = current
        if let originalToolId, originalToolId != draft.tool.id {
            merged.tools.removeValue(forKey: originalToolId)
        }

        // 先删除当前 id，再按草稿显式值或旧 Tool.hotkey fallback 写入，空值表示清除。
        merged.tools.removeValue(forKey: draft.tool.id)
        if let rawHotkey = toolHotkeyValue(
            toolId: draft.tool.id,
            hotkeys: draft.hotkeys,
            tool: draft.tool
        ) {
            merged.tools[draft.tool.id] = rawHotkey
        }
        return merged
    }

    /// 当前编辑会话是否存在未保存改动。
    /// - Parameters:
    ///   - session: 当前 ToolEditor 会话。
    ///   - currentTools: 保存前的正式工具列表。
    ///   - currentHotkeys: 保存前的正式 hotkey 配置。
    /// - Returns: 存在未保存改动时返回 true。
    nonisolated static func hasUnsavedEditingChanges(
        session: ToolEditorDraftSession?,
        currentTools: [Tool],
        currentHotkeys: HotkeyBindings
    ) -> Bool {
        guard let session else { return false }
        switch session {
        case .creating:
            return true
        case .editingExisting(let original, let draft):
            let currentTool = currentTools.first { $0.id == original.id } ?? original
            if draft.tool != currentTool {
                return true
            }
            let currentHotkey = toolHotkeyValue(
                toolId: currentTool.id,
                hotkeys: currentHotkeys,
                tool: currentTool
            )
            let draftHotkey = toolHotkeyValue(
                toolId: draft.tool.id,
                hotkeys: draft.hotkeys,
                tool: draft.tool
            )
            return currentHotkey != draftHotkey
        }
    }

    /// 检查当前编辑会话是否可以被替换或关闭。
    /// - Returns: 没有未保存改动时返回 true；否则保留当前会话并展示提示。
    func canReplaceEditingSession() -> Bool {
        guard Self.hasUnsavedEditingChanges(
            session: editingSession,
            currentTools: viewModel.configuration.tools,
            currentHotkeys: viewModel.configuration.hotkeys
        ) else {
            validationErrors = []
            return true
        }
        validationErrors = [.invalidTool(Self.unsavedDraftMessage)]
        print("[ToolsSettingsPage] replace editing session blocked by unsaved draft")
        return false
    }

    /// dirty guard 展示给用户的提示文案。
    nonisolated static var unsavedDraftMessage: String {
        "请先保存或撤销当前草稿后再继续。"
    }

    /// 取某个工具的 hotkey 值，空白字符串按清除处理。
    /// - Parameters:
    ///   - toolId: Tool id。
    ///   - hotkeys: 待读取的 hotkey 配置。
    ///   - tool: Tool 自身，提供旧 `Tool.hotkey` fallback。
    /// - Returns: 非空 hotkey 字符串；无 hotkey 时返回 nil。
    nonisolated private static func toolHotkeyValue(
        toolId: String,
        hotkeys: HotkeyBindings,
        tool: Tool
    ) -> String? {
        let raw = hotkeys.tools[toolId] ?? tool.hotkey
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return raw
    }

    /// 生成尽量不冲突的新工具 id。
    /// - Parameter prefix: id 前缀。
    /// - Returns: 当前配置内唯一的新工具 id。
    func makeNewToolID(prefix: String) -> String {
        let timestamp = Int(Date().timeIntervalSince1970)
        var candidate = "\(prefix)-\(timestamp)"
        var suffix = 1
        let existingIds = Set(viewModel.configuration.tools.map(\.id))
        while existingIds.contains(candidate) {
            suffix += 1
            candidate = "\(prefix)-\(timestamp)-\(suffix)"
        }
        return candidate
    }

    /// 创建一个兜底 Prompt Tool 草稿。
    /// - Returns: 可用于瞬时 fallback 的 Prompt Tool。
    func makeEmptyPromptDraftTool() -> Tool {
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

    /// 选择默认 Agent Provider，优先使用声明 toolCalling 能力的 Provider。
    /// - Returns: Provider id；没有 Provider 时返回空字符串，等待用户在设置页补齐。
    func preferredToolCallingProviderID() -> String {
        viewModel.configuration.providers.first { $0.capabilities.contains(.toolCalling) }?.id
            ?? viewModel.configuration.providers.first?.id
            ?? ""
    }

    /// 新建 Agent 默认使用选区作为上下文。
    /// - Returns: selection 上下文请求。
    func selectionContextRequest() -> ContextRequest {
        ContextRequest(
            key: .init(rawValue: "selection"),
            provider: "selection",
            args: [:],
            cachePolicy: .none,
            requiredness: .required
        )
    }

    /// 实际执行删除（alert 确认后才调用；save 由 onChange(tools) 兜底）。
    /// - Parameter id: 待删除工具 id。
    func performDelete(id: String) {
        print("[ToolsSettingsPage] performDelete: id=\(id)")
        let toolHotkeys = HotkeyBindingValidator.effectiveToolHotkeys(
            bindings: viewModel.configuration.hotkeys,
            tools: viewModel.configuration.tools
        )
        let removedToolHadHotkey = !(toolHotkeys[id]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
        withAnimation(SliceAnimation.standard) {
            viewModel.configuration.hotkeys.tools.removeValue(forKey: id)
            viewModel.configuration.tools.removeAll { $0.id == id }
            clearEditingSessionIfNeeded(toolId: id)
        }
        if removedToolHadHotkey {
            print("[ToolsSettingsPage] performDelete: hotkey removed, reloading registrations")
            Task {
                await viewModel.saveHotkeys()
            }
        }
    }

    /// 拖拽结束（行 / 外层兜底）时统一调用：执行 Array.move 并清理状态。
    func commitReorder() {
        defer {
            draggedId = nil
            dropTargetIndex = nil
        }
        guard let sourceId = draggedId,
              let from = viewModel.configuration.tools.firstIndex(where: { $0.id == sourceId }),
              let target = dropTargetIndex else {
            return
        }
        // target == from / target == from + 1 都等价于"不移动"，跳过避免无意义动画。
        guard target != from, target != from + 1 else { return }
        print("[ToolsSettingsPage] commitReorder: \(from) → \(target)")
        withAnimation(.easeInOut(duration: 0.25)) {
            viewModel.configuration.tools.move(
                fromOffsets: IndexSet(integer: from),
                toOffset: target
            )
        }
    }

    /// 安排一次 debounced save（取消上一个挂起 Task 再启新）。
    func scheduleDebouncedSave() {
        saveDebounceTask?.cancel()
        saveDebounceTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: Self.saveDebounceInterval)
            guard !Task.isCancelled else { return }
            do {
                try await viewModel.save()
                print("[ToolsSettingsPage] debounced save OK")
            } catch {
                print("[ToolsSettingsPage] debounced save failed – \(error.localizedDescription)")
            }
        }
    }
}
