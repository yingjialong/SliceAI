import Foundation
import Orchestration
import OSLog
import SliceCore

/// Playground 运行状态。
public enum ToolPlaygroundRunStatus: Sendable, Equatable {
    /// 尚未运行。
    case idle
    /// 正在执行。
    case running
    /// 正在取消。
    case cancelling
    /// 执行成功。
    case succeeded
    /// 执行失败，携带用户可读错误文案。
    case failed(String)
}

/// DisplayMode 预览类型。
public enum ToolPlaygroundPreviewKind: Sendable, Equatable {
    /// window 输出预览。
    case window
    /// bubble 输出预览。
    case bubble
    /// replace 输出预览。
    case replace
    /// file 输出预览。
    case file
    /// silent 输出预览。
    case silent
    /// structured 输出预览。
    case structured
}

/// Playground DisplayMode 预览摘要。
public struct ToolPlaygroundDisplayPreview: Sendable, Equatable {
    /// 预览类型。
    public var kind: ToolPlaygroundPreviewKind
    /// 预览摘要。
    public var summary: String

    /// 构造 DisplayMode 预览摘要。
    public init(kind: ToolPlaygroundPreviewKind, summary: String) {
        self.kind = kind
        self.summary = summary
    }
}

/// Playground UI 状态。
public struct ToolPlaygroundState: Sendable, Equatable {
    /// Playground 试跑 selection 输入。
    public var selectionText = ""
    /// Playground 试跑 app name。
    public var appName = "Playground"
    /// Playground 试跑 window title。
    public var windowTitle = ""
    /// Playground 试跑 URL。
    public var urlText = ""
    /// 是否允许本次 Playground 真实调用 Agent MCP tools。
    public var allowMCPToolCalls = false
    /// 当前运行状态。
    public var status: ToolPlaygroundRunStatus = .idle
    /// LLM streaming 文本累积。
    public var streamedText = ""
    /// 脱敏 prompt preview。
    public var promptPreview = ""
    /// MCP tool-call 生命周期行。
    public var toolCallRows: [String] = []
    /// 权限 dry-run 提示行。
    public var permissionRows: [String] = []
    /// dry-run 跳过的 side effect 行。
    public var skippedSideEffects: [String] = []
    /// 当前 DisplayMode 预览。
    public var displayPreview = ToolPlaygroundDisplayPreview(kind: .window, summary: "")
    /// 最近一次完成报告。
    public var lastReport: InvocationReport?
    /// 最近一次完成报告摘要。
    public var reportSummary = ""
    /// 最近一次错误的用户可读文案。
    public var errorMessage: String?

    private static let logger = Logger(subsystem: "com.sliceai.settings", category: "ToolPlaygroundState")

    /// 构造空状态。
    public init() {}

    /// 根据 ExecutionEvent 更新 UI 状态。
    public mutating func reduce(_ event: ExecutionEvent, tool: Tool) {
        switch event {
        case .started(let invocationId):
            status = .running
            streamedText = ""
            promptPreview = ""
            toolCallRows = []
            permissionRows = []
            skippedSideEffects = []
            lastReport = nil
            reportSummary = ""
            errorMessage = nil
            displayPreview = preview(for: tool, finalText: "")
            Self.logger.debug("Playground reducer started invocation=\(invocationId.uuidString, privacy: .public)")
        case .promptRendered(let preview):
            promptPreview = preview
        case .permissionWouldBeRequested(let permission, let uxHint):
            permissionRows.append("would request \(permission.playgroundName): \(uxHint)")
        case .llmChunk(let delta):
            // streaming 正文属于用户可见结果，只存入 UI 状态，不写入日志。
            streamedText += delta
        case .toolCallProposed(_, let ref, _):
            toolCallRows.append("proposed \(ref.server).\(ref.tool)")
        case .toolCallApproved:
            toolCallRows.append("approved")
        case .toolCallDenied(_, let reason):
            toolCallRows.append("denied \(reason)")
        case .toolCallResult(_, let summary):
            toolCallRows.append("result \(summary)")
        case .toolCallError(_, let summary):
            toolCallRows.append("error \(summary)")
        case .sideEffectSkippedDryRun(let sideEffect):
            skippedSideEffects.append(sideEffect.previewName)
        case .finished(let report):
            status = .succeeded
            lastReport = report
            reportSummary = report.playgroundSummary
            displayPreview = preview(for: tool, finalText: streamedText)
            Self.logger.debug("Playground reducer finished toolID=\(report.toolId, privacy: .public)")
        case .failed(let error):
            errorMessage = error.userMessage
            status = .failed(error.userMessage)
            displayPreview = preview(for: tool, finalText: streamedText)
            Self.logger.debug("Playground reducer failed error=\(error.developerContext, privacy: .public)")
        default:
            break
        }
    }

    /// 生成 DisplayMode 预览。
    private func preview(for tool: Tool, finalText: String) -> ToolPlaygroundDisplayPreview {
        switch tool.displayMode {
        case .window:
            return .init(kind: .window, summary: finalText)
        case .bubble:
            return .init(kind: .bubble, summary: "would show bubble: \(finalText)")
        case .replace:
            return .init(kind: .replace, summary: "would replace selected text: \(finalText)")
        case .file:
            let path = tool.outputBinding?.appendToFilePreviewPath ?? "<missing appendToFile path>"
            return .init(kind: .file, summary: "would append to \(path): \(finalText)")
        case .silent:
            return .init(kind: .silent, summary: "silent dry-run final text: \(finalText)")
        case .structured:
            return .init(kind: .structured, summary: structuredSummary(finalText))
        }
    }

    /// 生成结构化 JSON 预览摘要。
    private func structuredSummary(_ text: String) -> String {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            Self.logger.debug("Playground structured preview parse failed")
            return "structured parse error"
        }
        return object.keys.sorted().joined(separator: ", ")
    }
}

private extension SideEffect {
    /// Playground side effect 预览名称。
    var previewName: String {
        switch self {
        case .appendToFile(let path, _):
            return "would append to \(path)"
        case .copyToClipboard:
            return "would copy to clipboard"
        case .notify:
            return "would notify"
        case .runAppIntent:
            return "would run AppIntent"
        case .callMCP(let ref, _):
            return "would call MCP \(ref.server).\(ref.tool)"
        case .writeMemory:
            return "would write memory"
        case .tts:
            return "would speak"
        }
    }
}

private extension Permission {
    /// Playground permission 预览名称。
    var playgroundName: String {
        String(describing: self)
    }
}

private extension InvocationReport {
    /// Playground report 摘要，供右侧面板显示 tokens / cost / flags。
    var playgroundSummary: String {
        let flagsText = flags.map(\.rawValue).sorted().joined(separator: ", ")
        return "tokens \(totalTokens), cost \(estimatedCostUSD), outcome \(outcome.playgroundName), flags \(flagsText)"
    }
}

private extension InvocationOutcome {
    /// Playground outcome 预览名称。
    var playgroundName: String {
        switch self {
        case .success:
            return "success"
        case .dryRunCompleted:
            return "dry-run completed"
        case .failed(let errorKind):
            return "failed \(errorKind.rawValue)"
        }
    }
}

private extension OutputBinding {
    /// `.file` 预览路径。
    var appendToFilePreviewPath: String? {
        for sideEffect in sideEffects {
            if case .appendToFile(let path, _) = sideEffect {
                return path
            }
        }
        return nil
    }
}
