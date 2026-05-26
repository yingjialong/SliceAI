import Capabilities
import Foundation

/// final text 文件追加写入边界。
public protocol FinalTextFileAppending: Sendable {
    /// 追加 final text 到指定文件。
    /// - Parameters:
    ///   - finalText: 当前 invocation 的完整最终输出。
    ///   - path: 目标文件路径。
    ///   - header: 可选追加标题。
    func append(finalText: String, to path: String, header: String?) async throws
}

/// 使用 PathSandbox 的文件追加写入器。
public struct SandboxedFinalTextFileAppender: FinalTextFileAppending {
    private let pathSandbox: PathSandbox

    /// 构造文件追加写入器。
    /// - Parameter pathSandbox: 文件写入沙箱。
    public init(pathSandbox: PathSandbox = PathSandbox()) {
        self.pathSandbox = pathSandbox
    }

    /// 追加 final text 到沙箱允许的文件。
    public func append(finalText: String, to path: String, header: String?) async throws {
        let url = try pathSandbox.normalize(path, role: .write)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: appendPayload(finalText: finalText, header: header))
    }

    /// 构造追加写入 payload。
    private func appendPayload(finalText: String, header: String?) -> Data {
        var lines: [String] = []
        if let header, !header.isEmpty {
            lines.append(header)
        }
        lines.append(finalText)
        return (lines.joined(separator: "\n") + "\n").data(using: .utf8) ?? Data()
    }
}
