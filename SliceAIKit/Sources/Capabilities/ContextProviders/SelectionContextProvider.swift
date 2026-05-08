import Foundation
import SliceCore

/// 返回当前执行种子中的选区文本。
public struct SelectionContextProvider: ContextProvider {
    /// Provider 注册名。
    public let name = "selection"

    /// 构造选区上下文提供方。
    public init() {}

    /// 推导选区读取所需权限。
    ///
    /// - Parameter args: 当前 provider 不读取参数。
    /// - Returns: 选区来自 `ExecutionSeed`，不触发额外权限。
    public static func inferredPermissions(for args: [String: String]) -> [Permission] {
        []
    }

    /// 解析当前选区文本。
    ///
    /// - Parameters:
    ///   - request: 原始上下文请求；当前实现不读取额外参数。
    ///   - seed: 执行种子中的选区快照。
    ///   - app: 前台 app 快照；当前实现不读取。
    /// - Returns: `.text(seed.text)`。
    public func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        // 纯内存读取，不触发 IO；保持 provider 行为可预测。
        .text(seed.text)
    }
}
