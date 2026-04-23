import Foundation

/// ContextCollector 采集的键值对容器；`ResolvedExecutionContext.contexts` 的类型
///
/// 仅 Sendable + Equatable，**不实现 Codable**（`ContextValue.error(SliceError)` 需要 SliceError 实现 Codable，
/// 为避免大面积侵入 SliceError，ContextBag 不参与 JSON 序列化；它是运行时构造产物）。
/// 不暴露可变 API——ContextCollector 一次性构造、使用者只读（INV-6）。
public struct ContextBag: Sendable, Equatable {
    /// 底层键值映射；保持 public 便于调试，但生产代码应优先用 subscript
    public let values: [ContextKey: ContextValue]

    /// 构造 ContextBag
    /// - Parameter values: 键值字典
    public init(values: [ContextKey: ContextValue]) {
        self.values = values
    }

    /// 只读下标；命中返回值，未命中返回 nil
    public subscript(key: ContextKey) -> ContextValue? { values[key] }
}

/// ContextProvider 产出的值类型
///
/// 仅 Sendable + Equatable（见 ContextBag 说明）。
public enum ContextValue: Sendable, Equatable {
    /// 纯文本
    case text(String)
    /// JSON 数据（由 provider 预解析后传入，调用方可按 schema 再解）
    case json(Data)
    /// 文件引用：URL + MIME；实际内容由消费方按需读
    case file(URL, mimeType: String)
    /// 图像数据：format 为 "png" / "jpeg" 等
    case image(Data, format: String)
    /// 采集失败也记录下来，供 prompt 模板降级（如 `{{vocab|default:""}}`）
    case error(SliceError)
}
