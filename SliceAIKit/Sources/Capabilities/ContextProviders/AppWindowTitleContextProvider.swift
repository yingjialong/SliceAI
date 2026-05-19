import Foundation
import SliceCore

/// 返回当前前台 app 快照中的窗口标题。
public struct AppWindowTitleContextProvider: ContextProvider {
    /// Provider 注册名。
    public let name = "app.windowTitle"

    /// 构造前台窗口标题上下文提供方。
    public init() {}

    /// 推导窗口标题读取所需权限。
    ///
    /// - Parameter args: 当前 provider 不读取参数。
    /// - Returns: 标题来自 `ExecutionSeed.frontApp` 快照，不触发额外权限。
    public static func inferredPermissions(for args: [String: String]) -> [Permission] {
        []
    }

    /// 解析前台窗口标题。
    ///
    /// - Parameters:
    ///   - request: 原始上下文请求；当前实现不读取额外参数。
    ///   - seed: 选区快照；当前实现不读取。
    ///   - app: 前台 app 快照。
    /// - Returns: 前台窗口标题；快照缺失时返回空字符串。
    public func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        // 纯内存读取；nil 标题按空文本降级，避免把可选元数据缺失升级成 required 失败。
        .text(app.windowTitle ?? "")
    }
}
