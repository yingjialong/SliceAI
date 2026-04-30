import CoreGraphics
import Foundation

/// 划词事件的载荷，在 SelectionCapture 与 Windowing / ToolExecutor 之间传递
public struct SelectionPayload: Sendable, Equatable, Codable {
    public let text: String
    public let appBundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint
    public let source: Source
    public let timestamp: Date

    public init(
        text: String, appBundleID: String, appName: String,
        url: URL?, screenPoint: CGPoint, source: Source, timestamp: Date
    ) {
        self.text = text
        self.appBundleID = appBundleID
        self.appName = appName
        self.url = url
        self.screenPoint = screenPoint
        self.source = source
        self.timestamp = timestamp
    }

    /// 选中文字的来源，用于日志与诊断
    public enum Source: String, Sendable, Codable {
        case accessibility       // 通过 AX API 直接读取
        case clipboardFallback   // 通过模拟 Cmd+C + 剪贴板备份恢复获取
    }
}

// MARK: - v1 触发层包装 → v2 ExecutionSeed 单一入口

public extension SelectionPayload {

    /// 把触发层 SelectionPayload 翻译为 v2 ExecutionSeed。
    ///
    /// - Parameters:
    ///   - triggerSource: 调用方决定本次执行来自浮条、命令面板或快捷键。
    ///   - isDryRun: dry-run 模式；v0.2 触发链默认 false。
    /// - Returns: 可直接传给 ExecutionEngine 的不可变执行种子。
    func toExecutionSeed(triggerSource: TriggerSource, isDryRun: Bool = false) -> ExecutionSeed {
        let snapshot = SelectionSnapshot(
            text: text,
            source: source.toSelectionOrigin(),
            length: text.count,
            language: nil,
            contentType: nil
        )
        let appSnapshot = AppSnapshot(
            bundleId: appBundleID,
            name: appName,
            url: url,
            windowTitle: nil
        )

        return ExecutionSeed(
            invocationId: UUID(),
            selection: snapshot,
            frontApp: appSnapshot,
            screenAnchor: screenPoint,
            timestamp: timestamp,
            triggerSource: triggerSource,
            isDryRun: isDryRun
        )
    }
}

public extension SelectionPayload.Source {

    /// 单方向映射 v1 触发层 source 到 v2 SelectionOrigin。
    ///
    /// - Returns: 与当前 SelectionPayload.Source 等价的 v2 来源枚举。
    func toSelectionOrigin() -> SelectionOrigin {
        switch self {
        case .accessibility:
            return .accessibility
        case .clipboardFallback:
            return .clipboardFallback
        }
    }
}
