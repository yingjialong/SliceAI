// SliceAIApp/AppContextAdapters.swift
import AppKit
import Foundation
import OSLog

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
