import AppKit
import Foundation
import SliceCore

/// 抽象"按下 ⌘C"的能力，便于测试
public protocol CopyKeystrokeInvoking: Sendable {
    /// 模拟系统级 ⌘C 按键以触发前台 App 把选中文字写入剪贴板
    func sendCopy() async throws
}

/// 提供前台窗口信息，便于测试
public struct FocusInfo: Sendable {
    public let bundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint

    /// 构造一次前台焦点信息快照，用于补全 SelectionReadResult 中的来源元数据
    public init(bundleID: String, appName: String, url: URL?, screenPoint: CGPoint) {
        self.bundleID = bundleID
        self.appName = appName
        self.url = url
        self.screenPoint = screenPoint
    }
}

/// 基于"备份剪贴板 + 模拟 ⌘C + 读 + 恢复"路径的选中文字读取
///
/// 该类型本身只保存不可变依赖（`any PasteboardProtocol`、`any CopyKeystrokeInvoking`、
/// 不可变闭包与数值），依赖均已约束为 `Sendable`。使用 `@unchecked Sendable` 是为了
/// 让编译器接受存在类型（`any`）成员的类在严格并发下被跨 actor 共享。
public final class ClipboardSelectionSource: SelectionReader, @unchecked Sendable {

    private let pasteboard: any PasteboardProtocol
    private let copyInvoker: any CopyKeystrokeInvoking
    private let focusProvider: @MainActor @Sendable () -> FocusInfo?
    private let pollInterval: TimeInterval
    private let timeout: TimeInterval

    /// 构造剪贴板回退式 SelectionReader
    /// - Parameters:
    ///   - pasteboard: 剪贴板抽象，生产环境注入 `SystemPasteboard()`
    ///   - copyInvoker: ⌘C 注入器，生产环境注入真实 CGEvent 实现
    ///   - focusProvider: 返回当前前台 App 信息的闭包；nil 表示无法读取。
    ///     标注为 `@MainActor`，因为内部通常访问 `NSWorkspace` / `NSEvent`
    ///     这类主线程隔离的 AppKit API。
    ///   - pollInterval: 轮询剪贴板 changeCount 的间隔，默认 10ms
    ///   - timeout: 最长等待时间；超时后判定为读取失败，默认 150ms
    public init(
        pasteboard: any PasteboardProtocol,
        copyInvoker: any CopyKeystrokeInvoking,
        focusProvider: @escaping @MainActor @Sendable () -> FocusInfo?,
        pollInterval: TimeInterval = 0.01,
        timeout: TimeInterval = 0.15
    ) {
        self.pasteboard = pasteboard
        self.copyInvoker = copyInvoker
        self.focusProvider = focusProvider
        self.pollInterval = pollInterval
        self.timeout = timeout
    }

    /// 读取当前选中文字；流程为 "备份 -> ⌘C -> 轮询 -> 读取 -> 恢复"
    ///
    /// 备份策略：完整拷贝 pasteboard 中的所有 item（含 RTF/HTML/图像/文件 URL 等富内容），
    /// 读取成功后再通过 `writeObjects` 原样恢复。注意 `NSPasteboard.pasteboardItems`
    /// 返回的 item 归属于 pasteboard 本身，`clearContents()` 后会失效，因此必须在清空前
    /// 深拷贝成独立的 `NSPasteboardItem`。
    public func readSelection() async throws -> SelectionReadResult? {
        // 1. 备份现有剪贴板：深拷贝全部 items 以支持富内容恢复；changeCount 用于检测变化
        let originalChange = pasteboard.changeCount
        let originalItems: [NSPasteboardItem]? = pasteboard.pasteboardItems()?.map { item in
            // 对每个 item 中的每种 type 做一次 data 拷贝，构造一个脱离原 pasteboard 的独立副本
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            return copy
        }

        // 2. 发 ⌘C，让前台 App 把选中文字写入剪贴板
        try await copyInvoker.sendCopy()

        // 3. 轮询等待 changeCount 变化；到 deadline 仍未变即视为未选中文字
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if pasteboard.changeCount != originalChange { break }
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        }
        let changed = pasteboard.changeCount != originalChange
        let text = changed ? pasteboard.string(forType: .string) : nil

        // 4. 恢复原剪贴板：仅在 changeCount 真的发生变化时写回，避免不必要的计数增长。
        //    使用 writeObjects(originalItems) 恢复全部类型（RTF/HTML/图片/文件 URL 等），
        //    避免只保留 .string 时对富内容造成不可逆的数据丢失。
        if changed, let originalItems {
            pasteboard.clearContents()
            _ = pasteboard.writeObjects(originalItems)
        }

        // 5. 空文本或无前台焦点信息时，返回 nil。
        //    focusProvider 为 @MainActor 隔离，需通过 await 跳到主线程调用，
        //    避免在非 actor 隔离的 async 上下文里用 MainActor.assumeIsolated 造成运行时陷阱。
        guard let text, !text.isEmpty else { return nil }
        guard let focus = await focusProvider() else { return nil }
        return SelectionReadResult(
            text: text,
            appBundleID: focus.bundleID,
            appName: focus.appName,
            url: focus.url,
            screenPoint: focus.screenPoint,
            source: .clipboardFallback
        )
    }
}
