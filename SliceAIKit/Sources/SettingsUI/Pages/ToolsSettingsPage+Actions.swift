import DesignSystem
import HotkeyManager
import SliceCore
import SwiftUI

// MARK: - ToolsSettingsPage Actions

extension ToolsSettingsPage {

    /// 添加新 Prompt 工具并自动展开编辑区（save 由 onChange(tools) 兜底）。
    func addPromptTool() {
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
        viewModel.configuration.tools.append(newTool)
        withAnimation(SliceAnimation.standard) {
            expandedId = newId
        }
    }

    /// 添加新 Agent 工具并自动展开编辑区（save 由 onChange(tools) 兜底）。
    func addAgentTool() {
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
        viewModel.configuration.tools.append(newTool)
        withAnimation(SliceAnimation.standard) {
            expandedId = newId
        }
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
            if expandedId == id { expandedId = nil }
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
