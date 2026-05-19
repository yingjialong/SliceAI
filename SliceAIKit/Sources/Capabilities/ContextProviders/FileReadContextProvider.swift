import Foundation
import SliceCore

/// 读取 PathSandbox 允许范围内的文本文件。
public struct FileReadContextProvider: ContextProvider {
    /// 默认最大读取字节数：1 MiB，适合作为 prompt context 的保守文本上限。
    public static let defaultMaxBytes = 1_048_576

    /// 默认单次读取块大小：64 KiB，避免一次性把大文件载入内存。
    public static let defaultChunkSize = 65_536

    /// Provider 注册名。
    public let name = "file.read"

    /// 文件路径沙箱；生产默认使用内置白名单，测试可注入用户白名单。
    private let sandbox: PathSandbox
    /// 单次读取允许的最大字节数。
    private let maxBytes: Int
    /// 单次文件 IO 的读取块大小。
    private let chunkSize: Int
    /// 每次成功读取 chunk 后调用的 hook；测试用于稳定验证取消传播。
    private let afterChunkRead: @Sendable () async throws -> Void

    /// 构造文件读取上下文提供方。
    ///
    /// - Parameters:
    ///   - sandbox: 路径访问沙箱，默认使用 `PathSandbox()`。
    ///   - maxBytes: 最大读取字节数，默认 1 MiB。
    ///   - chunkSize: 单次读取块大小，默认 64 KiB。
    ///   - afterChunkRead: chunk 读取后的测试 hook，生产默认 no-op。
    public init(
        sandbox: PathSandbox = PathSandbox(),
        maxBytes: Int = Self.defaultMaxBytes,
        chunkSize: Int = Self.defaultChunkSize,
        afterChunkRead: @escaping @Sendable () async throws -> Void = {}
    ) {
        self.sandbox = sandbox
        self.maxBytes = max(0, maxBytes)
        self.chunkSize = max(1, chunkSize)
        self.afterChunkRead = afterChunkRead
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
    /// - Returns: 文件 UTF-8 文本内容，最大读取 `maxBytes` 字节。
    /// - Throws: `PathSandboxError` 或 Foundation 文件读取错误。
    public func resolve(
        request: ContextRequest,
        seed: SelectionSnapshot,
        app: AppSnapshot
    ) async throws -> ContextValue {
        let rawPath = request.args["path"] ?? ""
        let fileURL = try sandbox.normalize(rawPath, role: .read)

        let data = try await readBoundedData(from: fileURL)
        guard let text = String(data: data, encoding: .utf8) else {
            throw SliceError.execution(.unknown("file.read.invalidUTF8"))
        }

        // 读取完成后仅返回文本，不额外猜测 MIME，保持 provider 行为简单。
        print("[ContextProvider] file.read resolved textLength=\(text.count)")
        return .text(text)
    }

    /// 分块读取文件并强制执行最大字节数限制。
    ///
    /// - Parameter fileURL: 已通过 `PathSandbox` 规范化和校验的文件 URL。
    /// - Returns: 不超过 `maxBytes` 的文件数据。
    /// - Throws: 文件 IO 错误、取消错误，或非敏感的 `file.read.maxBytesExceeded` 错误。
    private func readBoundedData(from fileURL: URL) async throws -> Data {
        try Task.checkCancellation()
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }
        try Task.checkCancellation()

        var data = Data()
        data.reserveCapacity(min(maxBytes, chunkSize))

        while true {
            try Task.checkCancellation()
            let remainingBeforeLimit = maxBytes - data.count
            let readSize = min(chunkSize, remainingBeforeLimit + 1)
            let chunk = try handle.read(upToCount: readSize) ?? Data()
            try Task.checkCancellation()

            guard !chunk.isEmpty else {
                break
            }
            guard data.count + chunk.count <= maxBytes else {
                throw SliceError.execution(.unknown("file.read.maxBytesExceeded"))
            }

            data.append(chunk)
            try await afterChunkRead()
            try Task.checkCancellation()
        }

        try Task.checkCancellation()
        return data
    }
}
