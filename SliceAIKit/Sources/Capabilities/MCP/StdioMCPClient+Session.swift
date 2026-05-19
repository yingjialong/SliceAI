import Foundation
import SliceCore

/// actor 内部持有的 stdio 进程状态。
final class StdioMCPProcessSession {
    let descriptor: MCPDescriptor
    let process: Process
    let stdin: FileHandle
    let stdout: FileHandle
    let stderr: FileHandle
    let responseRouter: StdioMCPResponseRouter
    let stderrBuffer: StdioMCPStderrLineBuffer
    let stdoutReaderTask: Task<Void, Never>
    let stderrReaderTask: Task<Void, Never>
    var nextID = 1
    var cachedToolDescriptors: [MCPToolDescriptor]?

    /// 构造 stdio 进程状态。
    init(
        descriptor: MCPDescriptor,
        process: Process,
        stdin: FileHandle,
        stdout: FileHandle,
        stderr: FileHandle,
        responseRouter: StdioMCPResponseRouter,
        stderrBuffer: StdioMCPStderrLineBuffer,
        stdoutReaderTask: Task<Void, Never>,
        stderrReaderTask: Task<Void, Never>
    ) {
        self.descriptor = descriptor
        self.process = process
        self.stdin = stdin
        self.stdout = stdout
        self.stderr = stderr
        self.responseRouter = responseRouter
        self.stderrBuffer = stderrBuffer
        self.stdoutReaderTask = stdoutReaderTask
        self.stderrReaderTask = stderrReaderTask
    }

    /// 判断当前运行进程是否仍匹配新的 stdio 启动配置。
    ///
    /// `MCPDescriptor ==` 只比较稳定 id，不能用于这里；运行中进程必须按真实启动输入
    /// 比较，否则 Settings 修改 command / args / env 后会继续复用旧子进程。
    /// - Parameter incoming: 最新 descriptor。
    /// - Returns: 启动配置一致时返回 true。
    func matchesLaunchConfiguration(of incoming: MCPDescriptor) -> Bool {
        descriptor.transport == incoming.transport
            && descriptor.command == incoming.command
            && (descriptor.args ?? []) == (incoming.args ?? [])
            && (descriptor.env ?? [:]) == (incoming.env ?? [:])
            && descriptor.url == incoming.url
    }
}

/// stdout JSON-RPC response router；按 id 分发 NDJSON response，避免阻塞 client actor。
actor StdioMCPResponseRouter {
    private struct PendingWaiter {
        let continuation: CheckedContinuation<String, any Error>
        let timeoutTask: Task<Void, Never>
    }

    private var buffer = Data()
    private var preparedIDs = Set<Int>()
    private var pendingLines: [Int: String] = [:]
    private var waiters: [Int: PendingWaiter] = [:]
    private var isClosed = false
    private let maxLineBytes = 1_048_576

    /// 预登记即将发送的 JSON-RPC id，允许响应先于 waiter 建立时被缓存。
    func prepare(id: Int) throws {
        guard !isClosed else {
            throw MCPClientError.transportFailed(reason: "stdio response router closed")
        }
        guard !preparedIDs.contains(id), waiters[id] == nil else {
            throw MCPClientError.transportFailed(reason: "duplicate JSON-RPC request id")
        }
        preparedIDs.insert(id)
    }

    /// 等待指定 id 的 response line；超过 timeout 时恢复 continuation 并清理 pending 状态。
    func waitPreparedLine(id: Int, timeoutNanoseconds: UInt64) async throws -> String {
        if let line = pendingLines.removeValue(forKey: id) {
            preparedIDs.remove(id)
            return line
        }
        guard !isClosed else {
            preparedIDs.remove(id)
            throw MCPClientError.transportFailed(reason: "stdio response router closed")
        }
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let timeoutTask = Task { [weak self] in
                    do {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                        await self?.timeout(id: id)
                    } catch {
                        return
                    }
                }
                waiters[id] = PendingWaiter(continuation: continuation, timeoutTask: timeoutTask)
            }
        } onCancel: { [weak self] in
            Task {
                await self?.cancel(id: id, reason: "request_cancelled")
            }
        }
    }

    /// 接收 stdout 新数据，按换行拆分 NDJSON line 并路由到对应 request id。
    func receive(_ data: Data) {
        guard !data.isEmpty else {
            close(reason: "stdio process closed stdout")
            return
        }
        buffer.append(data)
        guard buffer.count <= maxLineBytes else {
            close(reason: "stdout line exceeds maximum length")
            return
        }

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            route(lineData: Data(lineData))
        }
    }

    /// 取消指定 id 的等待状态；用于外层请求失败后的兜底清理。
    func cancel(id: Int, reason: String) {
        preparedIDs.remove(id)
        pendingLines.removeValue(forKey: id)
        if let waiter = waiters.removeValue(forKey: id) {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(throwing: MCPClientError.transportFailed(reason: reason))
        }
    }

    /// 关闭 router 并恢复所有等待中的 request。
    func close(reason: String) {
        guard !isClosed else { return }
        isClosed = true
        buffer.removeAll(keepingCapacity: false)
        pendingLines.removeAll(keepingCapacity: false)
        preparedIDs.removeAll(keepingCapacity: false)
        let activeWaiters = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in activeWaiters.values {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(throwing: MCPClientError.transportFailed(reason: reason))
        }
    }

    /// request timeout 到期时恢复对应 waiter。
    private func timeout(id: Int) {
        preparedIDs.remove(id)
        pendingLines.removeValue(forKey: id)
        guard let waiter = waiters.removeValue(forKey: id) else { return }
        waiter.continuation.resume(throwing: MCPClientError.transportFailed(reason: "request_timeout"))
    }

    /// 把一行 stdout JSON 解出 id 后路由到 waiter 或预登记缓存。
    private func route(lineData: Data) {
        guard !lineData.isEmpty else { return }
        let id: Int
        do {
            guard let decodedID = try JSONDecoder().decode(MCPJSONRPCIDEnvelope.self, from: lineData).id else {
                return
            }
            id = decodedID
        } catch {
            close(reason: "failed to decode JSON-RPC response id")
            return
        }
        guard let line = String(data: lineData, encoding: .utf8) else {
            close(reason: "stdout line is not valid UTF-8")
            return
        }

        if let waiter = waiters.removeValue(forKey: id) {
            preparedIDs.remove(id)
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(returning: line)
        } else if preparedIDs.contains(id) {
            pendingLines[id] = line
        }
    }
}

/// stderr 行缓冲器；完整行脱敏后才写诊断日志，避免 secret 跨 chunk 泄漏。
actor StdioMCPStderrLineBuffer {
    private let diagnosticLog: MCPDiagnosticLog
    private var buffer = Data()
    private let maxBufferBytes = 16 * 1024

    /// 构造 stderr 行缓冲器。
    init(diagnosticLog: MCPDiagnosticLog) {
        self.diagnosticLog = diagnosticLog
    }

    /// 接收 stderr chunk；EOF 时 flush 剩余片段。
    func receive(_ data: Data) async {
        guard !data.isEmpty else {
            await flush()
            return
        }
        buffer.append(data)

        while let newlineIndex = buffer.firstIndex(of: 0x0A) {
            let lineData = buffer[..<newlineIndex]
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
            await emit(lineData: Data(lineData))
        }

        if buffer.count > maxBufferBytes {
            buffer.removeAll(keepingCapacity: false)
            await diagnosticLog.record("stderr server=<redacted>: <truncated>")
        }
    }

    /// flush EOF 或 teardown 时尚未带换行的 stderr 片段。
    func flush() async {
        guard !buffer.isEmpty else { return }
        let lineData = buffer
        buffer.removeAll(keepingCapacity: false)
        await emit(lineData: lineData)
    }

    /// 写入一行诊断日志；server 标识固定脱敏，line 内容交给 MCPDiagnosticLog 统一脱敏。
    private func emit(lineData: Data) async {
        guard let line = String(data: lineData, encoding: .utf8) else {
            await diagnosticLog.record("stderr server=<redacted>: <invalid utf8>")
            return
        }
        let normalized = line.trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
        guard !normalized.isEmpty else { return }
        await diagnosticLog.record("stderr server=<redacted>: \(normalized)")
    }
}

/// 只解 JSON-RPC response id 的轻量 envelope。
private struct MCPJSONRPCIDEnvelope: Decodable {
    let id: Int?
}
