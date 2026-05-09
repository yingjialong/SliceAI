import Foundation
import SliceCore

/// 快捷键绑定校验结果
public enum HotkeyBindingIssue: Equatable, Sendable {
    /// 命令面板热键字符串无法解析
    case invalidCommandPalette(rawHotkey: String)
    /// 指定工具的热键字符串无法解析
    case invalidTool(toolID: String, rawHotkey: String)
    /// 工具热键与命令面板热键冲突
    case commandPaletteConflict(toolID: String, normalizedHotkey: String)
    /// 两个工具热键冲突
    case toolConflict(firstToolID: String, secondToolID: String, normalizedHotkey: String)
}

/// 快捷键绑定校验器
public enum HotkeyBindingValidator {

    /// 计算命令面板与工具热键之间的无效项和冲突项
    /// - Parameters:
    ///   - commandPalette: 命令面板热键字符串
    ///   - tools: 工具 id 到热键字符串的映射
    /// - Returns: 稳定排序的校验问题列表；空字符串会被忽略
    public static func issues(commandPalette: String, tools: [String: String]) -> [HotkeyBindingIssue] {
        var issues: [HotkeyBindingIssue] = []
        let commandPaletteNormalized = normalizedCommandPalette(commandPalette, issues: &issues)
        let normalizedTools = normalizedToolHotkeys(tools, issues: &issues)

        if let commandPaletteNormalized {
            for item in normalizedTools where item.normalizedHotkey == commandPaletteNormalized {
                issues.append(.commandPaletteConflict(
                    toolID: item.toolID,
                    normalizedHotkey: item.normalizedHotkey
                ))
            }
        }

        let grouped = Dictionary(grouping: normalizedTools, by: \.normalizedHotkey)
        for hotkey in grouped.keys.sorted() {
            let toolIDs = grouped[hotkey, default: []].map(\.toolID).sorted()
            guard let first = toolIDs.first, toolIDs.count > 1 else { continue }
            for second in toolIDs.dropFirst() {
                issues.append(.toolConflict(
                    firstToolID: first,
                    secondToolID: second,
                    normalizedHotkey: hotkey
                ))
            }
        }
        return issues
    }

    /// 判断指定工具是否被任一校验问题影响
    /// - Parameters:
    ///   - toolID: 工具 id
    ///   - issue: 单个校验问题
    /// - Returns: `true` 表示该工具不应注册热键
    public static func issue(_ issue: HotkeyBindingIssue, involves toolID: String) -> Bool {
        switch issue {
        case .invalidCommandPalette:
            return false
        case .invalidTool(let id, _), .commandPaletteConflict(let id, _):
            return id == toolID
        case .toolConflict(let first, let second, _):
            return first == toolID || second == toolID
        }
    }

    /// 标准化命令面板热键；空字符串视为未绑定
    private static func normalizedCommandPalette(
        _ rawHotkey: String,
        issues: inout [HotkeyBindingIssue]
    ) -> String? {
        let trimmed = rawHotkey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        do {
            return try Hotkey.parse(trimmed).description
        } catch {
            issues.append(.invalidCommandPalette(rawHotkey: rawHotkey))
            return nil
        }
    }

    /// 标准化工具热键；空字符串视为未绑定
    private static func normalizedToolHotkeys(
        _ tools: [String: String],
        issues: inout [HotkeyBindingIssue]
    ) -> [NormalizedToolHotkey] {
        tools.keys.sorted().compactMap { toolID in
            guard let rawHotkey = tools[toolID] else { return nil }
            let trimmed = rawHotkey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            do {
                return NormalizedToolHotkey(
                    toolID: toolID,
                    normalizedHotkey: try Hotkey.parse(trimmed).description
                )
            } catch {
                issues.append(.invalidTool(toolID: toolID, rawHotkey: rawHotkey))
                return nil
            }
        }
    }
}

/// 已标准化的工具热键条目
private struct NormalizedToolHotkey: Equatable {
    let toolID: String
    let normalizedHotkey: String
}

/// 可交给 AppDelegate 注册的工具热键条目
public struct ToolHotkeyRegistration: Equatable, Sendable {
    /// 工具 id
    public let toolID: String
    /// 工具名称，仅用于诊断日志
    public let toolName: String
    /// 原始配置字符串
    public let rawHotkey: String
    /// 已解析的热键对象
    public let hotkey: Hotkey

    /// 从完整配置中提取可注册的工具热键
    /// - Parameter configuration: 当前配置快照
    /// - Returns: 按 `configuration.tools` 顺序排列的有效注册项；无效、冲突、缺失工具会被跳过
    public static func validRegistrations(in configuration: Configuration) -> [ToolHotkeyRegistration] {
        let commandPalette = configuration.triggers.commandPaletteEnabled
            ? configuration.hotkeys.toggleCommandPalette
            : ""
        let toolHotkeys = effectiveToolHotkeys(in: configuration)
        let issues = HotkeyBindingValidator.issues(
            commandPalette: commandPalette,
            tools: toolHotkeys
        )
        let blockedToolIDs = Set(toolHotkeys.keys.filter { toolID in
            issues.contains { HotkeyBindingValidator.issue($0, involves: toolID) }
        })

        return configuration.tools.compactMap { tool in
            guard !blockedToolIDs.contains(tool.id) else { return nil }
            let rawHotkey = toolHotkeys[tool.id, default: ""]
            let trimmed = rawHotkey.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let hotkey = try? Hotkey.parse(trimmed) else { return nil }
            return ToolHotkeyRegistration(
                toolID: tool.id,
                toolName: tool.name,
                rawHotkey: rawHotkey,
                hotkey: hotkey
            )
        }
    }

    /// 生成运行时使用的工具热键映射，优先使用集中配置并兼容旧 `Tool.hotkey`
    private static func effectiveToolHotkeys(in configuration: Configuration) -> [String: String] {
        var toolHotkeys = configuration.hotkeys.tools
        for tool in configuration.tools where toolHotkeys[tool.id] == nil {
            // 旧配置可能只写在 Tool.hotkey；注册前统一纳入冲突校验，避免重复注册同一组合键。
            if let hotkey = tool.hotkey {
                toolHotkeys[tool.id] = hotkey
            }
        }
        return toolHotkeys
    }
}
