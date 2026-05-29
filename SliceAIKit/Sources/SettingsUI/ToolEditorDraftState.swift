import Foundation
import HotkeyManager
import OSLog
import SliceCore

/// ToolEditor v2 的可保存草稿。
public struct ToolEditorDraft: Sendable, Equatable {
    /// 未保存的 Tool 草稿。
    public var tool: Tool
    /// 未保存的 hotkey 草稿。
    public var hotkeys: HotkeyBindings

    /// 构造草稿。
    public init(tool: Tool, hotkeys: HotkeyBindings) {
        self.tool = tool
        self.hotkeys = hotkeys
    }
}

/// ToolEditor 当前会话。
public enum ToolEditorDraftSession: Sendable, Equatable {
    /// 编辑已有工具。
    case editingExisting(original: Tool, draft: ToolEditorDraft)
    /// 创建新工具。
    case creating(draft: ToolEditorDraft)

    /// 创建已有工具编辑会话。
    public static func existing(original: Tool, hotkeys: HotkeyBindings) -> ToolEditorDraftSession {
        .editingExisting(original: original, draft: ToolEditorDraft(tool: original, hotkeys: hotkeys))
    }

    /// 当前草稿。
    public var draft: ToolEditorDraft {
        get {
            switch self {
            case .editingExisting(_, let draft), .creating(let draft):
                return draft
            }
        }
        set {
            switch self {
            case .editingExisting(let original, _):
                self = .editingExisting(original: original, draft: newValue)
            case .creating:
                self = .creating(draft: newValue)
            }
        }
    }

    /// 已有工具原始 id；创建新工具时为 nil。
    public var originalToolId: String? {
        if case .editingExisting(let original, _) = self {
            return original.id
        }
        return nil
    }
}

/// Tool 草稿校验错误。
public enum ToolDraftValidationError: Sendable, Equatable, LocalizedError {
    /// Tool id 与现有工具重复。
    case duplicateToolId(String)
    /// Tool 自身不变量校验失败。
    case invalidTool(String)
    /// Agent 绑定的 Skill 未启用或不存在。
    case skillNotEnabled(String)
    /// 工具热键无法解析。
    case invalidHotkey(String)
    /// 工具热键与命令面板或其它工具冲突。
    case hotkeyConflict(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateToolId(let id):
            return "工具 id 已存在：\(id)"
        case .invalidTool(let message):
            return message
        case .skillNotEnabled(let skill):
            return "Skill 未启用或不存在：\(skill)"
        case .invalidHotkey(let hotkey):
            return "快捷键无效：\(hotkey)"
        case .hotkeyConflict(let hotkey):
            return "快捷键冲突：\(hotkey)"
        }
    }
}

/// ToolEditor v2 草稿保存前校验。
public enum ToolDraftValidator {
    private static let logger = Logger(subsystem: "com.sliceai.settings", category: "ToolDraftValidator")

    /// 校验草稿。
    public static func validate(
        draft: ToolEditorDraft,
        existingTools: [Tool],
        availableSkills: [SliceCore.Skill],
        originalToolId: String?,
        commandPaletteEnabled: Bool = true
    ) -> [ToolDraftValidationError] {
        var errors: [ToolDraftValidationError] = []

        if existingTools.contains(where: { $0.id == draft.tool.id && $0.id != originalToolId }) {
            errors.append(.duplicateToolId(draft.tool.id))
        }

        do {
            try draft.tool.validate()
        } catch let error as SliceError {
            errors.append(.invalidTool(error.userMessage))
        } catch {
            errors.append(.invalidTool(error.localizedDescription))
        }

        errors.append(contentsOf: validateSkills(tool: draft.tool, availableSkills: availableSkills))
        errors.append(contentsOf: validateHotkeys(
            draft: draft,
            tools: existingTools,
            originalToolId: originalToolId,
            commandPaletteEnabled: commandPaletteEnabled
        ))

        let originalID = originalToolId ?? "nil"
        logger.debug("校验 Tool 草稿完成，toolID=\(draft.tool.id, privacy: .public)")
        logger.debug("Tool 草稿原始 id：\(originalID, privacy: .public)")
        logger.debug("Tool 草稿校验错误数量：\(errors.count, privacy: .public)")
        return errors
    }

    /// 校验 Agent skill 绑定必须来自 enabled skills。
    private static func validateSkills(
        tool: Tool,
        availableSkills: [SliceCore.Skill]
    ) -> [ToolDraftValidationError] {
        guard case .agent(let agent) = tool.kind else { return [] }
        let enabled = Set(availableSkills.filter { $0.state == .enabled }.map(\.id))
        return agent.skills
            .map(\.id)
            .filter { !enabled.contains($0) }
            .map { .skillNotEnabled($0) }
    }

    /// 校验工具热键不与命令面板或其它工具冲突。
    private static func validateHotkeys(
        draft: ToolEditorDraft,
        tools: [Tool],
        originalToolId: String?,
        commandPaletteEnabled: Bool
    ) -> [ToolDraftValidationError] {
        var comparisonTools = tools.filter { tool in
            tool.id != originalToolId && tool.id != draft.tool.id
        }
        // 把草稿 Tool 放入比较集合，确保旧 Tool.hotkey fallback 与集中 hotkeys 走同一套规则。
        comparisonTools.append(draft.tool)

        let effectiveToolHotkeys = HotkeyBindingValidator.effectiveToolHotkeys(
            bindings: draft.hotkeys,
            tools: comparisonTools
        )
        let commandPalette = commandPaletteEnabled ? draft.hotkeys.toggleCommandPalette : ""
        let issues = HotkeyBindingValidator.issues(
            commandPalette: commandPalette,
            tools: effectiveToolHotkeys
        )
        return issues.compactMap { issue in
            guard HotkeyBindingValidator.issue(issue, involves: draft.tool.id) else { return nil }
            switch issue {
            case .invalidCommandPalette:
                return nil
            case .invalidTool(_, let rawHotkey):
                return .invalidHotkey(rawHotkey)
            case .commandPaletteConflict(_, let normalizedHotkey):
                return .hotkeyConflict(normalizedHotkey)
            case .toolConflict(_, _, let normalizedHotkey):
                return .hotkeyConflict(normalizedHotkey)
            }
        }
    }
}
