import Capabilities
import Foundation
import OSLog
import SliceCore

/// SideEffect 执行结果。
public enum SideEffectExecutionOutcome: Sendable, Equatable {
    /// 副作用已执行成功。
    case executed
    /// 当前 Phase 明确不支持该副作用。
    case unsupported(reason: String)
    /// 副作用执行失败；reason 必须是脱敏后的诊断信息。
    case failed(reason: String)
}

/// 副作用执行协议。
public protocol SideEffectExecutorProtocol: Sendable {
    /// 执行单个副作用。
    /// - Parameters:
    ///   - sideEffect: 要执行的声明式副作用。
    ///   - finalText: 当前 invocation 的完整最终输出。
    ///   - invocationId: 当前 invocation 标识，用于日志关联。
    /// - Returns: 执行结果；失败不会抛出，调用方据此决定 partial failure。
    func execute(
        _ sideEffect: SideEffect,
        finalText: String,
        invocationId: UUID
    ) async -> SideEffectExecutionOutcome
}

/// 剪贴板写入边界。
public protocol ClipboardWriting: Sendable {
    /// 写入纯文本到剪贴板。
    /// - Parameter text: 要写入的文本。
    func writeString(_ text: String) async throws
}

/// 用户通知边界。
public protocol UserNotifying: Sendable {
    /// 发送用户可见通知。
    /// - Parameters:
    ///   - title: 通知标题。
    ///   - body: 通知正文。
    func notify(title: String, body: String) async throws
}

/// 默认 SideEffect 执行器。
public struct SideEffectExecutor: SideEffectExecutorProtocol {

    private let clipboard: any ClipboardWriting
    private let notifier: any UserNotifying
    private let speaker: any TTSCapability
    private let mcpClient: any MCPClientProtocol
    private let fileAppender: any FinalTextFileAppending
    private let logger = Logger(subsystem: "com.sliceai.app", category: "side-effects")

    /// 构造 SideEffectExecutor。
    /// - Parameters:
    ///   - clipboard: 剪贴板写入 adapter。
    ///   - notifier: 用户通知 adapter。
    ///   - speaker: TTS adapter。
    ///   - mcpClient: MCP client。
    ///   - pathSandbox: 文件写入沙箱。
    public init(
        clipboard: any ClipboardWriting,
        notifier: any UserNotifying,
        speaker: any TTSCapability,
        mcpClient: any MCPClientProtocol,
        pathSandbox: PathSandbox
    ) {
        self.clipboard = clipboard
        self.notifier = notifier
        self.speaker = speaker
        self.mcpClient = mcpClient
        self.fileAppender = SandboxedFinalTextFileAppender(pathSandbox: pathSandbox)
    }

    /// 执行单个 SideEffect。
    public func execute(
        _ sideEffect: SideEffect,
        finalText: String,
        invocationId: UUID
    ) async -> SideEffectExecutionOutcome {
        let outcome = await executeUnchecked(sideEffect, finalText: finalText)
        logOutcome(sideEffect: sideEffect, outcome: outcome, invocationId: invocationId)
        return outcome
    }

    /// 按 case 分派副作用执行。
    private func executeUnchecked(
        _ sideEffect: SideEffect,
        finalText: String
    ) async -> SideEffectExecutionOutcome {
        do {
            switch sideEffect {
            case .appendToFile(let path, let header):
                try await fileAppender.append(finalText: finalText, to: path, header: header)
            case .copyToClipboard:
                try await clipboard.writeString(finalText)
            case .notify(let title, let body):
                try await notifier.notify(title: title, body: body)
            case .runAppIntent:
                return .unsupported(reason: "runAppIntent is not implemented")
            case .callMCP(let ref, let params):
                return await callMCP(ref: ref, params: params)
            case .writeMemory:
                return .unsupported(reason: "writeMemory is planned for Phase 3")
            case .tts(let voice):
                return await speak(finalText: finalText, voice: voice)
            }
            return .executed
        } catch {
            return .failed(reason: "side effect execution failed")
        }
    }

    /// 调用 MCP side effect。
    private func callMCP(ref: MCPToolRef, params: MCPJSONValue.Object) async -> SideEffectExecutionOutcome {
        do {
            let result = try await mcpClient.call(ref: ref, args: params)
            return result.isError ? .failed(reason: "mcp side effect returned error") : .executed
        } catch {
            return .failed(reason: "mcp side effect failed")
        }
    }

    /// 朗读 final text。
    private func speak(finalText: String, voice: String?) async -> SideEffectExecutionOutcome {
        let speechText = preferredSpeechText(from: finalText)
        guard !speechText.isEmpty else {
            return .failed(reason: "No text to speak")
        }
        do {
            try await speaker.speak(speechText, voice: voice)
            return .executed
        } catch {
            return .failed(reason: "tts side effect failed")
        }
    }

    /// structured JSON 输出包含 `ttsText` 时优先朗读该字段。
    private func preferredSpeechText(from finalText: String) -> String {
        guard let data = finalText.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let ttsText = object["ttsText"] as? String,
              !ttsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return finalText
        }
        return ttsText
    }

    /// 输出脱敏诊断日志。
    private func logOutcome(
        sideEffect: SideEffect,
        outcome: SideEffectExecutionOutcome,
        invocationId: UUID
    ) {
        let id = invocationId.uuidString
        logger.info(
            """
            sideEffect kind=\(sideEffect.kindName, privacy: .public) \
            outcome=\(outcome.logName, privacy: .public) invocation=\(id, privacy: .public)
            """
        )
    }
}

private extension SideEffect {

    /// 日志用副作用类型名；不包含路径、正文、MCP 参数等用户数据。
    var kindName: String {
        switch self {
        case .appendToFile: return "appendToFile"
        case .copyToClipboard: return "copyToClipboard"
        case .notify: return "notify"
        case .runAppIntent: return "runAppIntent"
        case .callMCP: return "callMCP"
        case .writeMemory: return "writeMemory"
        case .tts: return "tts"
        }
    }
}

private extension SideEffectExecutionOutcome {

    /// 日志用结果名；不包含失败详情 payload。
    var logName: String {
        switch self {
        case .executed: return "executed"
        case .unsupported: return "unsupported"
        case .failed: return "failed"
        }
    }
}
