import Foundation
import SliceCore

/// 读取 PathSandbox 允许范围内的文本文件。
public struct FileReadContextProvider: ContextProvider {
    /// Provider 注册名。
    public let name = "file.read"

    /// 文件路径沙箱；生产默认使用内置白名单，测试可注入用户白名单。
    private let sandbox: PathSandbox

    /// 构造文件读取上下文提供方。
    ///
    /// - Parameter sandbox: 路径访问沙箱，默认使用 `PathSandbox()`。
    public init(sandbox: PathSandbox = PathSandbox()) {
        self.sandbox = sandbox
    }

    /// 推导文件读取所需权限。
    ///
    /// - Parameter args: 读取参数，使用 `args["path"]` 作为文件路径。
    /// - Returns: 存在 path 时返回对应 `.fileRead(path:)`；缺失时返回空数组。
    public static func inferredPermissions(for args: [String: String]) -> [Permission] {
        guard let path = args["path"] else {
            return []
        }
        return [.fileRead(path: path)]
    }

    /// 解析白名单内文本文件内容。
    ///
    /// - Parameters:
    ///   - request: 原始上下文请求，需提供 `args["path"]`。
    ///   - seed: 选区快照；当前实现不读取。
    ///   - app: 前台 app 快照；当前实现不读取。
    /// - Returns: 文件 UTF-8 文本内容。
    /// - Throws: `PathSandboxError` 或 Foundation 文件读取错误。
    public func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        let rawPath = request.args["path"] ?? ""
        let fileURL = try sandbox.normalize(rawPath, role: .read)

        try Task.checkCancellation()
        let text = try String(contentsOf: fileURL, encoding: .utf8)
        try Task.checkCancellation()

        // 读取完成后仅返回文本，不额外猜测 MIME，保持 provider 行为简单。
        print("[ContextProvider] file.read resolved textLength=\(text.count)")
        return .text(text)
    }
}
