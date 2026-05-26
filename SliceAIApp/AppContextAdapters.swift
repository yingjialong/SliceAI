// SliceAIApp/AppContextAdapters.swift
import AppKit
import ApplicationServices
import Foundation
import Orchestration
import OSLog
import SliceCore
@preconcurrency import UserNotifications
import Windowing

private let appContextAdaptersLog = Logger(subsystem: "com.sliceai.app", category: "AppContextAdapters")

/// App 层上下文适配器集合。
///
/// 该类型把 AppKit / NSPasteboard 等平台 API 隔离在 App target 内，避免 `AppContainer`
/// 直接散落平台读取细节。当前 Task 9 只需要剪贴板读取；后续 AX / URL 快照如需补强，
/// 应继续放在这里而不是扩散到 Orchestration。
enum AppContextAdapters {

    /// 异步读取当前系统剪贴板字符串。
    ///
    /// - Returns: 当前剪贴板中的字符串；没有字符串时返回 nil。
    static func readClipboardString() async throws -> String? {
        await MainActor.run {
            let text = NSPasteboard.general.string(forType: .string)
            appContextAdaptersLog.debug("clipboard string read length=\(text?.count ?? 0)")
            return text
        }
    }
}

/// AppKit / Accessibility 文本替换适配器。
///
/// 该类型只接收 final text，不处理 streaming chunk。直接替换失败时写入剪贴板并发送本地通知，
/// 提醒用户手动粘贴；日志只记录长度和结果，避免泄露用户原文。
final class AppTextReplacementClient: TextReplacementClient, @unchecked Sendable {

    /// 默认构造器。
    init() {}

    /// 用完整 final text 替换当前前台 App 选区。
    /// - Parameter text: LLM 完整最终输出。
    /// - Returns: 直接替换、复制 fallback 或失败结果。
    func replaceSelection(with text: String) async -> TextReplacementResult {
        await MainActor.run {
            replaceSelectionOnMain(with: text)
        }
    }

    /// 在主线程执行 AX 替换。
    @MainActor
    private func replaceSelectionOnMain(with text: String) -> TextReplacementResult {
        let systemWide = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let focusedError = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )
        guard focusedError == .success, let focused else {
            return copyToPasteboardAndNotify(text, reason: "focused element unavailable")
        }

        // AX focused element 的 CF 类型只能在运行时确认；与 AXSelectionSource 保持同一边界。
        // swiftlint:disable:next force_cast
        let element = focused as! AXUIElement
        let setError = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        guard setError == .success else {
            return copyToPasteboardAndNotify(text, reason: "ax set selected text failed")
        }

        appContextAdaptersLog.info("replace succeeded length=\(text.count, privacy: .public)")
        return .replaced
    }

    /// 直接替换失败时复制到剪贴板并发送通知。
    @MainActor
    private func copyToPasteboardAndNotify(_ text: String, reason: String) -> TextReplacementResult {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let copied = pasteboard.setString(text, forType: .string)
        guard copied else {
            appContextAdaptersLog.error("replace fallback clipboard write failed")
            return .failed(reason: "clipboard write failed")
        }

        postFallbackNotification()
        appContextAdaptersLog.info(
            "replace fallback copied length=\(text.count, privacy: .public)"
        )
        return .fallbackCopied(reason: reason)
    }

    /// 发送本地通知，提醒用户结果已经复制到剪贴板。
    private func postFallbackNotification() {
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "SliceAI"
            content.body = "无法直接替换当前选区，结果已复制到剪贴板。"
            let request = UNNotificationRequest(
                identifier: "sliceai.replace.\(UUID().uuidString)",
                content: content,
                trigger: nil
            )
            center.add(request)
        }
    }
}

/// App 层 bubble 输出 sink。
///
/// 该类型把 Orchestration 的 final text 展示请求桥接到 Windowing 的 `BubblePanel`；
/// 日志只记录长度与 invocation，不记录模型输出正文。
final class AppBubbleOutputSink: BubbleOutputSink, @unchecked Sendable {

    /// 注入的气泡面板。
    private let panel: BubblePanel

    /// 构造 bubble sink。
    /// - Parameter panel: AppContainer 持有的气泡面板。
    init(panel: BubblePanel) {
        self.panel = panel
    }

    /// 展示 bubble final text。
    /// - Parameters:
    ///   - finalText: LLM 完整最终输出。
    ///   - context: 当前输出上下文。
    func showBubble(finalText: String, context: OutputInvocationContext) async throws {
        let logger = Logger(subsystem: "com.sliceai.app", category: "AppContextAdapters")
        let length = finalText.count
        logger.debug(
            "bubble show id=\(context.invocationId, privacy: .public) len=\(length, privacy: .public)"
        )
        await MainActor.run {
            panel.show(text: finalText, anchor: context.screenAnchor)
        }
    }
}

/// App 层 structured 输出 sink。
///
/// 解析失败会抛出受控 `SliceError`，由 AppDelegate 统一写入 ResultPanel 错误态。
final class AppStructuredOutputSink: StructuredOutputSink, @unchecked Sendable {

    /// 注入的结果面板。
    private let panel: ResultPanel

    /// 构造 structured sink。
    /// - Parameter panel: AppContainer 持有的结果面板。
    init(panel: ResultPanel) {
        self.panel = panel
    }

    /// 展示 structured final text。
    /// - Parameters:
    ///   - finalText: LLM 完整最终输出，预期为顶层 JSON object。
    ///   - context: 当前输出上下文。
    func showStructured(finalText: String, context: OutputInvocationContext) async throws {
        let logger = Logger(subsystem: "com.sliceai.app", category: "AppContextAdapters")
        do {
            let fields = try StructuredResultParser.parseObject(from: finalText)
            let fieldCount = fields.count
            logger.debug(
                "structured show id=\(context.invocationId, privacy: .public) fields=\(fieldCount, privacy: .public)"
            )
            await MainActor.run {
                panel.showStructured(fields: fields, rawText: finalText)
            }
        } catch {
            logger.error(
                "structured sink parse failed invocation=\(context.invocationId, privacy: .public)"
            )
            throw SliceError.execution(.unknown("structured result parse failed"))
        }
    }
}
