// SliceAIApp/ExecutionEventConsumer.swift
import Foundation
import Orchestration
import OSLog
import SliceCore
import Windowing

/// 将 `ExecutionEvent` 流翻译为 `ResultPanel` 的 UI 状态变化。
///
/// 约束：
///   - `.llmChunk` 只记日志，不直接写入面板；
///   - chunk 唯一写入路径是 `OutputDispatcher -> WindowSink -> ResultPanel.append`；
///   - stale invocation gating 由调用方在调用 `handle` 前完成。
@MainActor
final class ExecutionEventConsumer {

    /// 事件消费日志；仅记录无敏感信息的固定字段。
    private let logger = Logger(subsystem: "com.sliceai.app", category: "executionevent")

    /// 用户点击错误态“重试”时执行的回调。
    private let onRetry: @MainActor () -> Void

    /// 用户点击错误态“打开设置”时执行的回调。
    private let onOpenSettings: @MainActor () -> Void

    /// 当前 invocation 是否已经展示过终态错误。
    ///
    /// `.notImplemented` 是 UI 终态错误；engine 仍可能随后发送 `.finished` 作为 audit stub，
    /// 这里必须忽略后续 finish，避免错误块被完成态覆盖。
    private var didPresentTerminalFailure = false

    /// 创建事件消费者。
    /// - Parameters:
    ///   - onRetry: 错误态重试回调。
    ///   - onOpenSettings: 错误态打开设置回调。
    init(
        onRetry: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }

    /// 处理单个执行事件，并更新结果面板状态。
    /// - Parameters:
    ///   - event: `ExecutionEngine` 产出的事件。
    ///   - panel: 需要更新的结果面板。
    func handle(_ event: ExecutionEvent, panel: ResultPanel) {
        switch event {
        case .started:
            didPresentTerminalFailure = false
            logPreparationEvent(event)
        case .contextResolved, .promptRendered, .llmChunk:
            logPreparationEvent(event)
        case .toolCallProposed, .toolCallApproved, .toolCallResult, .stepCompleted:
            logToolProgressEvent(event)
        case .sideEffectTriggered, .sideEffectSkippedDryRun, .permissionWouldBeRequested:
            logPermissionEvent(event)
        case .notImplemented(let reason):
            didPresentTerminalFailure = true
            panel.fail(
                with: .execution(.notImplemented(reason)),
                onRetry: nil,
                onOpenSettings: nil
            )

        case .finished:
            guard !didPresentTerminalFailure else {
                logger.debug("finished ignored because terminal failure is already visible")
                return
            }
            panel.finish()

        case .failed(let sliceError):
            didPresentTerminalFailure = true
            panel.fail(
                with: sliceError,
                onRetry: { [weak self] in self?.onRetry() },
                onOpenSettings: { [weak self] in self?.onOpenSettings() }
            )
        }
    }

    /// 记录上下文、prompt 与 LLM chunk 相关的非 UI 变更事件。
    /// - Parameter event: 需要记录的执行事件。
    private func logPreparationEvent(_ event: ExecutionEvent) {
        switch event {
        case .started(let invocationId):
            logger.debug("started invocation \(invocationId, privacy: .public)")
        case .contextResolved(let key, let valueDescription):
            logger.debug(
                "contextResolved key=\(key.rawValue, privacy: .public) preview=\(valueDescription, privacy: .private)"
            )
        case .promptRendered(let preview):
            logger.debug("promptRendered preview=\(preview, privacy: .private)")
        case .llmChunk(let delta):
            // 单一写入契约：这里不能 append，否则会与 OutputDispatcher 双写。
            logger.debug("llmChunk length=\(delta.count, privacy: .public)")
        default:
            break
        }
    }

    /// 记录工具调用与步骤推进相关的非 UI 变更事件。
    /// - Parameter event: 需要记录的执行事件。
    private func logToolProgressEvent(_ event: ExecutionEvent) {
        switch event {
        case .toolCallProposed(let ref, let argsDescription):
            let refDescription = String(describing: ref)
            logger.debug(
                "toolCallProposed ref=\(refDescription, privacy: .private) args=\(argsDescription, privacy: .private)"
            )
        case .toolCallApproved(let id):
            logger.debug("toolCallApproved id=\(id, privacy: .public)")
        case .toolCallResult(let id, let summary):
            logger.debug("toolCallResult id=\(id, privacy: .public) summary=\(summary, privacy: .private)")
        case .stepCompleted(let step, let total):
            logger.debug("stepCompleted \(step, privacy: .public)/\(total, privacy: .public)")
        default:
            break
        }
    }

    /// 记录权限与 side effect 相关的非 UI 变更事件。
    /// - Parameter event: 需要记录的执行事件。
    private func logPermissionEvent(_ event: ExecutionEvent) {
        switch event {
        case .sideEffectTriggered(let sideEffect):
            logger.debug("sideEffectTriggered case=\(sideEffect.caseName, privacy: .public)")
        case .sideEffectSkippedDryRun(let sideEffect):
            logger.debug("sideEffectSkippedDryRun case=\(sideEffect.caseName, privacy: .public)")
        case .permissionWouldBeRequested(let permission, let uxHint):
            let permissionCase = permission.caseName
            logger.debug(
                "permissionWouldBeRequested perm=\(permissionCase, privacy: .public) hint=\(uxHint, privacy: .private)"
            )
        default:
            break
        }
    }
}

// MARK: - 脱敏 caseName helper

/// 仅暴露 `SideEffect` case 名，不展开关联值。
///
/// 这些关联值可能包含用户路径、通知正文、MCP server/tool 或 memory 内容；
/// OSLog 公开日志只允许写固定 case 名，详细字段应查看已脱敏的 audit log。
private extension SideEffect {
    var caseName: String {
        switch self {
        case .appendToFile:    return "appendToFile"
        case .copyToClipboard: return "copyToClipboard"
        case .notify:          return "notify"
        case .runAppIntent:    return "runAppIntent"
        case .callMCP:         return "callMCP"
        case .writeMemory:     return "writeMemory"
        case .tts:             return "tts"
        }
    }
}

/// 仅暴露 `Permission` case 名，不展开关联值。
///
/// 权限关联值可能包含 host、文件路径、shell 命令、MCP server/tool 等敏感信息。
private extension Permission {
    var caseName: String {
        switch self {
        case .network:          return "network"
        case .fileRead:         return "fileRead"
        case .fileWrite:        return "fileWrite"
        case .clipboard:        return "clipboard"
        case .clipboardHistory: return "clipboardHistory"
        case .shellExec:        return "shellExec"
        case .mcp:              return "mcp"
        case .screen:           return "screen"
        case .systemAudio:      return "systemAudio"
        case .memoryAccess:     return "memoryAccess"
        case .appIntents:       return "appIntents"
        }
    }
}
