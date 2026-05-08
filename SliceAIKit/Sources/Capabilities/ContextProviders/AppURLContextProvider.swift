import Foundation
import SliceCore

/// 返回当前前台 app 快照中的 URL。
public struct AppURLContextProvider: ContextProvider {
    /// Provider 注册名。
    public let name = "app.url"

    /// 构造前台 URL 上下文提供方。
    public init() {}

    /// 推导 URL 读取所需权限。
    ///
    /// - Parameter args: 当前 provider 不读取参数。
    /// - Returns: URL 来自 `ExecutionSeed.frontApp` 快照，不触发额外权限。
    public static func inferredPermissions(for args: [String: String]) -> [Permission] {
        []
    }

    /// 解析前台 app URL。
    ///
    /// - Parameters:
    ///   - request: 原始上下文请求；当前实现不读取额外参数。
    ///   - seed: 选区快照；当前实现不读取。
    ///   - app: 前台 app 快照。
    /// - Returns: URL 的 `absoluteString`；快照缺失时返回空字符串。
    public func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        // 纯内存读取；非浏览器 app 没有 URL 时按空文本降级。
        .text(app.url?.absoluteString ?? "")
    }
}
