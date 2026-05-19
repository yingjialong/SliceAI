import AppKit
import Foundation
import SliceCore

/// 读取当前系统剪贴板文本。
public struct ClipboardCurrentContextProvider: ContextProvider {
    /// Provider 注册名。
    public let name = "clipboard.current"

    /// 剪贴板文本读取闭包；测试中可注入，生产默认读取 `NSPasteboard.general`。
    private let readString: @Sendable () async throws -> String?

    /// 构造剪贴板上下文提供方。
    ///
    /// - Parameter readString: 剪贴板文本读取闭包；默认读取系统剪贴板字符串。
    public init(readString: @escaping @Sendable () async throws -> String? = {
        NSPasteboard.general.string(forType: .string)
    }) {
        self.readString = readString
    }

    /// 推导剪贴板读取所需权限。
    ///
    /// - Parameter args: 当前 provider 不读取参数。
    /// - Returns: 读取剪贴板需要 `.clipboard` 权限。
    public static func inferredPermissions(for args: [String: String]) -> [Permission] {
        [.clipboard]
    }

    /// 解析当前剪贴板文本。
    ///
    /// - Parameters:
    ///   - request: 原始上下文请求；当前实现不读取额外参数。
    ///   - seed: 选区快照；当前实现不读取。
    ///   - app: 前台 app 快照；当前实现不读取。
    /// - Returns: 剪贴板文本；剪贴板无字符串时返回空字符串。
    public func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        try Task.checkCancellation()
        let text = try await readString()
        try Task.checkCancellation()
        // IO 边界后只做 nil 降级，不把空剪贴板当错误处理。
        print("[ContextProvider] clipboard.current resolved textLength=\(text?.count ?? 0)")
        return .text(text ?? "")
    }
}
