import SliceCore
import SwiftUI

// MARK: - Agent Skill Bindings

extension ToolEditorView {

    /// 当前 Agent Tool 已绑定的 skill ids。
    var selectedAgentSkillIDs: [String] {
        if case .agent(let agentTool) = tool.kind {
            return agentTool.skills.map(\.id)
        }
        return []
    }

    /// 当前是否还能新增一条 Agent skill 绑定。
    var canAddAgentSkillBinding: Bool {
        selectedAgentSkillIDs.count < 5 && !unboundAgentSkillIDs.isEmpty
    }

    /// 判断指定 skill 是否已绑定到当前 Agent Tool。
    /// - Parameter id: skill id。
    /// - Returns: 已绑定返回 true。
    func isAgentSkillSelected(id: String) -> Bool {
        selectedAgentSkillIDs.contains(id)
    }

    /// 设置指定 skill 的 Agent 绑定状态，最多保留 5 个绑定。
    /// - Parameters:
    ///   - id: skill id。
    ///   - isSelected: true 表示添加绑定，false 表示移除绑定。
    func setAgentSkill(id: String, isSelected: Bool) {
        guard case .agent(var agentTool) = tool.kind else { return }
        if isSelected {
            guard !agentTool.skills.contains(where: { $0.id == id }) else { return }
            guard agentTool.skills.count < 5 else {
                print("[ToolEditorView] agent skill binding ignored: max 5 reached for tool '\(tool.id)'")
                return
            }
            agentTool.skills.append(SkillReference(id: id, pinVersion: nil))
        } else {
            agentTool.skills.removeAll { $0.id == id }
        }
        tool.kind = .agent(agentTool)
        print("[ToolEditorView] agent skills updated for tool '\(tool.id)' count=\(agentTool.skills.count)")
    }

    /// 追加一条新的 Agent skill 绑定，默认选择第一个未绑定的 enabled skill。
    func addAgentSkillBinding() {
        guard canAddAgentSkillBinding, let nextID = unboundAgentSkillIDs.first else {
            print("[ToolEditorView] add agent skill ignored for tool '\(tool.id)'")
            return
        }
        setAgentSkill(id: nextID, isSelected: true)
    }

    /// 删除指定行的 Agent skill 绑定。
    /// - Parameter index: 绑定行下标。
    func removeAgentSkill(at index: Int) {
        guard case .agent(var agentTool) = tool.kind,
              agentTool.skills.indices.contains(index) else {
            print("[ToolEditorView] remove agent skill ignored for tool '\(tool.id)' index=\(index)")
            return
        }
        agentTool.skills.remove(at: index)
        tool.kind = .agent(agentTool)
        print("[ToolEditorView] agent skill removed for tool '\(tool.id)' count=\(agentTool.skills.count)")
    }

    /// 替换指定行的 Agent skill 绑定，拒绝与其它行重复。
    /// - Parameters:
    ///   - index: 绑定行下标。
    ///   - id: 新 skill id。
    func setAgentSkill(at index: Int, id: String) {
        guard case .agent(var agentTool) = tool.kind,
              agentTool.skills.indices.contains(index),
              selectableAgentSkillIDs(forRow: index).contains(id) else {
            print("[ToolEditorView] set agent skill ignored for tool '\(tool.id)' index=\(index)")
            return
        }
        agentTool.skills[index] = SkillReference(id: id, pinVersion: nil)
        tool.kind = .agent(agentTool)
        print("[ToolEditorView] agent skill row updated for tool '\(tool.id)' index=\(index)")
    }

    /// 返回指定行 Picker 可选择的 skill ids。
    ///
    /// 当前行自己的 skill 会保留在列表中，其它行已选的 skill 会被排除，避免重复绑定。
    /// - Parameter index: 绑定行下标。
    /// - Returns: 当前行可选 skill ids。
    func selectableAgentSkillIDs(forRow index: Int) -> [String] {
        guard selectedAgentSkillIDs.indices.contains(index) else {
            return unboundAgentSkillIDs
        }
        let currentID = selectedAgentSkillIDs[index]
        let selectedByOtherRows = Set(selectedAgentSkillIDs.enumerated().compactMap { item in
            item.offset == index ? nil : item.element
        })
        var ids = availableSkills
            .map(\.id)
            .filter { $0 == currentID || !selectedByOtherRows.contains($0) }
        if !ids.contains(currentID) {
            ids.insert(currentID, at: 0)
        }
        return ids
    }

    /// 指定行的 Picker 绑定。
    /// - Parameter index: 绑定行下标。
    /// - Returns: skill id 字符串绑定。
    func agentSkillSelectionBinding(forRow index: Int) -> Binding<String> {
        Binding(
            get: {
                guard selectedAgentSkillIDs.indices.contains(index) else { return "" }
                return selectedAgentSkillIDs[index]
            },
            set: { newID in
                setAgentSkill(at: index, id: newID)
            }
        )
    }

    /// 根据 id 查找可展示的 skill。
    /// - Parameter id: skill id。
    /// - Returns: 当前 registry 可选 skills 中的匹配项。
    func availableSkill(id: String) -> SliceCore.Skill? {
        availableSkills.first { $0.id == id }
    }

    /// 当前 Agent Tool 尚未绑定的 skill ids。
    private var unboundAgentSkillIDs: [String] {
        let selected = Set(selectedAgentSkillIDs)
        return availableSkills.map(\.id).filter { !selected.contains($0) }
    }
}
