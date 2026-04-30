import Foundation

/// 选中事件的文字内容快照；`ExecutionSeed.selection` 字段的类型
///
/// **干净 v2 类型**：只含 `text / source / length / language / contentType` 五字段。
/// 与 v1 `SelectionPayload` 是**两个独立类型**（不做别名桥接 / 不搬 v1 的 init / 不搬 v1 的字段 / 不搬 v1 的 Codable key）。
/// `SelectionPayload` 仍在 `SelectionPayload.swift` 保留，服务 SelectionCapture 与 app 触发层；
/// M3 在触发层做一次性 `SelectionPayload → ExecutionSeed` 映射。
///
/// 相对 v1 新增的三个字段为下游 D-24 / §3.9.5 / §3.3.7 留结构位：
/// - `length`：显式长度，让 AuditLog 能写 sha256+len 而不读原文
/// - `language`：BCP-47 语言代码（"en" / "zh-CN"）；M1 填 nil，Phase 1+ 由 SelectionCapture 填充
/// - `contentType`：内容类型启发式；同上
///
/// v1 的 app / url / 屏幕点 / 时间戳等元数据字段**不在本类型里**——
/// 它们分别对应 `ExecutionSeed.frontApp` / `ExecutionSeed.screenAnchor` / `ExecutionSeed.timestamp`。
public struct SelectionSnapshot: Sendable, Equatable, Codable {
    /// 选中文字
    public let text: String
    /// 来源渠道（AX / clipboard fallback / 命令面板输入框）
    public let source: SelectionOrigin
    /// 字符长度（`text.count`，显式字段便于日志不写原文）
    public let length: Int
    /// BCP-47 语言代码；Phase 0 M1 可为 nil，Phase 1+ 填充
    public let language: String?
    /// 内容类型启发式；Phase 0 M1 可为 nil
    public let contentType: SelectionContentType?

    /// 构造选中文字快照
    /// - Parameters:
    ///   - text: 选中文字内容
    ///   - source: 来源渠道
    ///   - length: 字符数；调用方负责计算（通常 `text.count`）
    ///   - language: BCP-47 语言代码，未知传 nil
    ///   - contentType: 内容类型，未识别传 nil
    public init(
        text: String,
        source: SelectionOrigin,
        length: Int,
        language: String?,
        contentType: SelectionContentType?
    ) {
        self.text = text
        self.source = source
        self.length = length
        self.language = language
        self.contentType = contentType
    }
}

// 注意：这里**不**做 `SelectionPayload = SelectionSnapshot` 的别名桥接 —— 两者是独立类型。
// 注意：这里**不**添加 v1 字段 / v1 init / v1 Codable key / v1 compat accessor。
