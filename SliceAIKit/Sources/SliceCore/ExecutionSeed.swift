import CoreGraphics
import Foundation

/// 触发层（FloatingToolbar / CommandPalette / Hotkey / Shortcuts / URL Scheme / Services）
/// 产出的不可变执行种子；`ExecutionEngine.execute(tool:seed:)` 的入参
///
/// 含所有"一发即知"的信息；但**尚未**采集 Tool 声明的 `ContextRequest`。
/// 第二阶段由 `ContextCollector.resolve(seed:requests:)` 消费此 seed、产出
/// `ResolvedExecutionContext`——两者都不可 mutation（INV-6 / D-16）。
///
/// 任何需要新增字段的场景：
/// - 若信息在触发瞬间已知 → 加到 `ExecutionSeed`
/// - 若需要 I/O 或 MCP 采集才能获得 → 做成 `ContextProvider`，由 Tool 显式声明
public struct ExecutionSeed: Sendable, Equatable, Codable {
    /// 贯穿日志的追踪 id；同一次划词 / 快捷键触发只生成一次
    public let invocationId: UUID
    /// 选中文字快照
    public let selection: SelectionSnapshot
    /// 前台 app 快照
    public let frontApp: AppSnapshot
    /// 屏幕锚点（光标位置），浮条 / 结果面板定位使用
    public let screenAnchor: CGPoint
    /// 触发时间戳
    public let timestamp: Date
    /// 触发通路
    public let triggerSource: TriggerSource
    /// 预览模式；true 时 OutputDispatcher 跳过所有副作用、只展示流
    public let isDryRun: Bool

    /// 构造 ExecutionSeed
    /// - Parameters:
    ///   - invocationId: 本次调用的唯一 id
    ///   - selection: 选中文字快照
    ///   - frontApp: 前台 app 快照
    ///   - screenAnchor: 屏幕锚点（像素坐标，左下为原点）
    ///   - timestamp: 触发时间戳
    ///   - triggerSource: 触发通路
    ///   - isDryRun: 是否预览模式
    public init(
        invocationId: UUID,
        selection: SelectionSnapshot,
        frontApp: AppSnapshot,
        screenAnchor: CGPoint,
        timestamp: Date,
        triggerSource: TriggerSource,
        isDryRun: Bool
    ) {
        self.invocationId = invocationId
        self.selection = selection
        self.frontApp = frontApp
        self.screenAnchor = screenAnchor
        self.timestamp = timestamp
        self.triggerSource = triggerSource
        self.isDryRun = isDryRun
    }
}
