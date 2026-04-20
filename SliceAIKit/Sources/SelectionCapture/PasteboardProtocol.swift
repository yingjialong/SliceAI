import AppKit

/// NSPasteboard 的抽象接口，便于测试注入假实现
public protocol PasteboardProtocol: Sendable {
    /// 当前剪贴板变更计数，用于检测写入是否被其他应用覆盖
    var changeCount: Int { get }

    /// 读取指定类型的字符串；不存在返回 nil
    func string(forType type: NSPasteboard.PasteboardType) -> String?

    /// 清空剪贴板内容；返回新的 changeCount
    @discardableResult
    func clearContents() -> Int

    /// 写入字符串；返回是否成功
    @discardableResult
    func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool

    /// 读取全部 pasteboard item，用于完整备份恢复
    func pasteboardItems() -> [NSPasteboardItem]?

    /// 批量写入 pasteboard object，用于恢复备份
    func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool
}

/// 系统 NSPasteboard 的默认适配
///
/// 此类型包装 `NSPasteboard`，而 AppKit 并未将 `NSPasteboard` 标注为 `Sendable`。
/// 这里使用 `@unchecked Sendable` 是可接受的：所有调用都是短暂的同步读写，
/// 且常见用法是 `.general`（进程级单例）。若调用方注入命名或自定义 pasteboard
/// （如拖拽专用 pasteboard），其线程安全由调用方自行保证。
/// 需要在不同隔离域间共享非单例 pasteboard 的调用方，必须自行确保访问串行化。
public struct SystemPasteboard: @unchecked Sendable, PasteboardProtocol {
    private let pb: NSPasteboard

    public init(_ pb: NSPasteboard = .general) {
        self.pb = pb
    }

    public var changeCount: Int { pb.changeCount }

    public func string(forType type: NSPasteboard.PasteboardType) -> String? {
        pb.string(forType: type)
    }

    @discardableResult
    public func clearContents() -> Int {
        pb.clearContents()
    }

    @discardableResult
    public func setString(_ string: String, forType type: NSPasteboard.PasteboardType) -> Bool {
        pb.setString(string, forType: type)
    }

    public func pasteboardItems() -> [NSPasteboardItem]? {
        pb.pasteboardItems
    }

    public func writeObjects(_ objects: [any NSPasteboardWriting]) -> Bool {
        pb.writeObjects(objects)
    }
}
