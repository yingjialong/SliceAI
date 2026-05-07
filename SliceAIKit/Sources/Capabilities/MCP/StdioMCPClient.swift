import Foundation
import OSLog
import SliceCore

/// 基于 stdio 的 MCP JSON-RPC client。
public final actor StdioMCPClient: MCPClientProtocol {
    private let descriptors: @Sendable () async throws -> [MCPDescriptor]
    private let idleTimeoutNanoseconds: UInt64
    private let diagnosticLog: MCPDiagnosticLog
    private let requestTimeoutNanoseconds: UInt64
    private let logger = Logger(subsystem: "SliceAIKit", category: "StdioMCPClient")
    private let encoder: JSONEncoder
    private let decoder = JSONDecoder()

    private var sessions: [String: StdioMCPProcessSession] = [:]
    private var sessionStartTasks: [String: Task<Void, any Error>] = [:]
    private var idleTasks: [String: Task<Void, Never>] = [:]
    private var idleTaskGenerations: [String: UInt64] = [:]
    private var nextIdleTaskGeneration: UInt64 = 0

    /// 构造 stdio MCP client；进程会在首次 `tools(for:)` 或 `call(ref:args:)` 时 lazy 启动。
    public init(
        descriptors: @escaping @Sendable () async throws -> [MCPDescriptor],
        idleTimeoutNanoseconds: UInt64 = 300 * 1_000_000_000,
        diagnosticLog: MCPDiagnosticLog = .disabled,
        requestTimeoutNanoseconds: UInt64 = 30 * 1_000_000_000
    ) {
        self.descriptors = descriptors
        self.idleTimeoutNanoseconds = idleTimeoutNanoseconds
        self.diagnosticLog = diagnosticLog
        self.requestTimeoutNanoseconds = requestTimeoutNanoseconds
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    /// 查询 stdio MCP server 暴露的工具列表。
    public func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolDescriptor] {
        do {
            let session = try await session(for: descriptor)
            let tools = try await listToolsIfNeeded(session: session)
            scheduleIdleTimeout(serverID: descriptor.id)
            return tools
        } catch {
            await teardownSessionIfPresent(serverID: descriptor.id, reason: teardownReason(for: error))
            throw error
        }
    }

    /// 调用 MCP tool；`isError == true` 的工具执行错误作为结果返回，不转换为 JSON-RPC 协议错误。
    public func call(ref: MCPToolRef, args: MCPJSONValue.Object) async throws -> MCPCallResult {
        var resolvedServerID: String?
        do {
            let descriptor = try await descriptor(forServerID: ref.server)
            resolvedServerID = descriptor.id
            let session = try await session(for: descriptor)
            _ = try await listToolsIfNeeded(session: session)
            let params: MCPJSONValue = .object([
                "name": .string(ref.tool),
                "arguments": .object(args),
            ])
            let result: MCPCallResult = try await sendRequest(
                method: "tools/call",
                params: params,
                session: session
            )
            scheduleIdleTimeout(serverID: descriptor.id)
            logger.debug("MCP tools/call completed server=\(descriptor.id, privacy: .private)")
            return result
        } catch {
            if let resolvedServerID {
                await teardownSessionIfPresent(serverID: resolvedServerID, reason: teardownReason(for: error))
            }
            throw error
        }
    }

    /// 按 server id 从 descriptors provider 解析 descriptor。
    private func descriptor(forServerID serverID: String) async throws -> MCPDescriptor {
        let availableDescriptors = try await descriptors()
        guard let descriptor = availableDescriptors.first(where: { $0.id == serverID }) else {
            throw MCPClientError.toolNotFound(ref: MCPToolRef(server: serverID, tool: "<unknown>"))
        }
        return descriptor
    }

    /// 获取已有 session；不存在或进程已退出时启动新 stdio 进程并完成 initialize 握手。
    private func session(for descriptor: MCPDescriptor) async throws -> StdioMCPProcessSession {
        guard descriptor.transport == .stdio else {
            throw MCPClientError.unsupportedTransport(descriptor.transport)
        }
        if let startTask = sessionStartTasks[descriptor.id] {
            try await startTask.value
            guard let session = sessions[descriptor.id], session.process.isRunning else {
                throw MCPClientError.transportFailed(reason: "stdio session unavailable after start")
            }
            return session
        }
        if let existing = sessions[descriptor.id], existing.process.isRunning {
            cancelIdleTimeout(serverID: descriptor.id)
            return existing
        }
        let startTask = Task { [weak self] in
            guard let self else {
                throw MCPClientError.transportFailed(reason: "stdio client deallocated during start")
            }
            try await self.startAndRegisterSession(for: descriptor)
        }
        sessionStartTasks[descriptor.id] = startTask
        try await startTask.value
        guard let session = sessions[descriptor.id], session.process.isRunning else {
            throw MCPClientError.transportFailed(reason: "stdio session unavailable after start")
        }
        return session
    }

    /// 启动并登记 session；通过 `sessionStartTasks` 做 per-server single-flight，避免并发重复拉起进程。
    private func startAndRegisterSession(for descriptor: MCPDescriptor) async throws {
        defer {
            sessionStartTasks[descriptor.id] = nil
        }
        if let existing = sessions.removeValue(forKey: descriptor.id) {
            await stop(session: existing)
        }
        let session = try startProcess(for: descriptor)
        cancelIdleTimeout(serverID: descriptor.id)
        do {
            try await initialize(session: session)
        } catch {
            await stop(session: session)
            await diagnosticLog.record("stdio process stopped server=<redacted> reason=\(teardownReason(for: error))")
            throw error
        }
        sessions[descriptor.id] = session
    }

    /// 启动 stdio 子进程并接好 stdin/stdout/stderr pipe。
    private func startProcess(for descriptor: MCPDescriptor) throws -> StdioMCPProcessSession {
        guard let command = descriptor.command, !command.isEmpty else {
            throw MCPClientError.transportFailed(reason: "stdio descriptor missing command")
        }
        let process = Process()
        process.executableURL = executableURL(for: command)
        process.arguments = descriptor.args ?? []

        var environment = ProcessInfo.processInfo.environment
        for (key, value) in descriptor.env ?? [:] {
            environment[key] = value
        }
        process.environment = environment

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        let responseRouter = StdioMCPResponseRouter()
        let stderrBuffer = StdioMCPStderrLineBuffer(diagnosticLog: diagnosticLog)
        let stdoutReaderTask = attachStdoutRouter(stdout.fileHandleForReading, router: responseRouter)
        let stderrReaderTask = attachStderrDiagnostics(stderr.fileHandleForReading, buffer: stderrBuffer)

        do {
            try process.run()
            logger.debug("MCP stdio process started server=\(descriptor.id, privacy: .private)")
            return StdioMCPProcessSession(
                descriptor: descriptor,
                process: process,
                stdin: stdin.fileHandleForWriting,
                stdout: stdout.fileHandleForReading,
                stderr: stderr.fileHandleForReading,
                responseRouter: responseRouter,
                stderrBuffer: stderrBuffer,
                stdoutReaderTask: stdoutReaderTask,
                stderrReaderTask: stderrReaderTask
            )
        } catch {
            stdout.fileHandleForReading.readabilityHandler = nil
            stderr.fileHandleForReading.readabilityHandler = nil
            stdoutReaderTask.cancel()
            stderrReaderTask.cancel()
            throw MCPClientError.transportFailed(reason: "failed to start stdio process: \(error)")
        }
    }

    /// 为 stdout pipe 安装非阻塞 response router，避免 actor 被同步 read 占住。
    private nonisolated func attachStdoutRouter(
        _ handle: FileHandle,
        router: StdioMCPResponseRouter
    ) -> Task<Void, Never> {
        let stream = AsyncStream<Data> { continuation in
            handle.readabilityHandler = { readableHandle in
                let data = readableHandle.availableData
                if data.isEmpty {
                    readableHandle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                continuation.yield(data)
            }
        }
        return Task {
            for await data in stream {
                await router.receive(data)
            }
            await router.receive(Data())
        }
    }

    /// 为 stderr pipe 安装行缓冲诊断 handler，并在完整行进入 sink 前脱敏。
    private nonisolated func attachStderrDiagnostics(
        _ handle: FileHandle,
        buffer: StdioMCPStderrLineBuffer
    ) -> Task<Void, Never> {
        let stream = AsyncStream<Data> { continuation in
            handle.readabilityHandler = { readableHandle in
                let data = readableHandle.availableData
                if data.isEmpty {
                    readableHandle.readabilityHandler = nil
                    continuation.finish()
                    return
                }
                continuation.yield(data)
            }
        }
        return Task {
            for await data in stream {
                await buffer.receive(data)
            }
            await buffer.flush()
        }
    }

    /// 完成 MCP initialize 握手，并发送 notifications/initialized。
    private func initialize(session: StdioMCPProcessSession) async throws {
        let params: MCPJSONValue = .object([
            "protocolVersion": .string("2025-06-18"),
            "capabilities": .object(["tools": .object([:])]),
            "clientInfo": .object([
                "name": .string("SliceAI"),
                "version": .string("0.3.0"),
            ]),
        ])
        let _: MCPInitializeResult = try await sendRequest(method: "initialize", params: params, session: session)
        try sendNotification(method: "notifications/initialized", params: nil, session: session)
    }

    /// 确保当前 session 已执行 tools/list，并返回缓存后的 canonical tool descriptors。
    private func listToolsIfNeeded(session: StdioMCPProcessSession) async throws -> [MCPToolDescriptor] {
        if let cachedToolDescriptors = session.cachedToolDescriptors {
            return cachedToolDescriptors
        }
        let result: MCPToolsListResult = try await sendRequest(
            method: "tools/list",
            params: nil,
            session: session
        )
        let toolDescriptors = result.tools.map { $0.descriptor(serverID: session.descriptor.id) }
        session.cachedToolDescriptors = toolDescriptors
        logger.debug("MCP tools/list completed server=\(session.descriptor.id, privacy: .private)")
        return toolDescriptors
    }

    /// 发送有 id 的 JSON-RPC request，并通过 stdout router 异步等待匹配 id 的 response。
    private func sendRequest<Response: Decodable & Sendable>(
        method: String,
        params: MCPJSONValue?,
        session: StdioMCPProcessSession
    ) async throws -> Response {
        let id = session.nextID
        session.nextID += 1
        let request = MCPJSONRPCRequest(id: id, method: method, params: params)
        try await session.responseRouter.prepare(id: id)
        let line: String
        do {
            try write(request: request, to: session)
            line = try await session.responseRouter.waitPreparedLine(
                id: id,
                timeoutNanoseconds: requestTimeoutNanoseconds
            )
        } catch {
            await session.responseRouter.cancel(id: id, reason: teardownReason(for: error))
            throw error
        }
        let data = Data(line.utf8)
        let response = try decodeResponse(Response.self, from: data)
        guard response.id == id else {
            throw MCPClientError.decodingFailed(reason: "JSON-RPC id mismatch")
        }
        return try response.resultOrThrow()
    }

    /// 发送无 id 的 JSON-RPC notification。
    private func sendNotification(
        method: String,
        params: MCPJSONValue?,
        session: StdioMCPProcessSession
    ) throws {
        let request = MCPJSONRPCRequest(id: nil, method: method, params: params)
        try write(request: request, to: session)
    }

    /// 把 request 编码为单行 JSON 并写入 stdin。
    private func write(request: MCPJSONRPCRequest, to session: StdioMCPProcessSession) throws {
        do {
            var data = try encoder.encode(request)
            data.append(0x0A)
            try session.stdin.write(contentsOf: data)
        } catch {
            throw MCPClientError.transportFailed(reason: "failed to write JSON-RPC request: \(error)")
        }
    }

    /// 解码 JSON-RPC response，并把 JSON 解码失败收敛为 `MCPClientError.decodingFailed`。
    private func decodeResponse<Response: Decodable & Sendable>(
        _ type: Response.Type,
        from data: Data
    ) throws -> MCPJSONRPCResponse<Response> {
        do {
            return try decoder.decode(MCPJSONRPCResponse<Response>.self, from: data)
        } catch {
            throw MCPClientError.decodingFailed(reason: "failed to decode JSON-RPC response: \(error)")
        }
    }

    /// 为 server 安排 idle timeout，到期后停止对应进程。
    private func scheduleIdleTimeout(serverID: String) {
        cancelIdleTimeout(serverID: serverID)
        let timeout = idleTimeoutNanoseconds
        nextIdleTaskGeneration &+= 1
        let generation = nextIdleTaskGeneration
        idleTaskGenerations[serverID] = generation
        idleTasks[serverID] = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: timeout)
                await self?.stopIdleSession(serverID: serverID, generation: generation)
            } catch {
                return
            }
        }
    }

    /// 取消 server 当前 idle timeout 任务。
    private func cancelIdleTimeout(serverID: String) {
        idleTasks[serverID]?.cancel()
        idleTasks[serverID] = nil
        idleTaskGenerations[serverID] = nil
    }

    /// idle timeout 到期后停止进程并写入诊断日志。
    private func stopIdleSession(serverID: String, generation: UInt64) async {
        guard idleTaskGenerations[serverID] == generation else { return }
        idleTaskGenerations[serverID] = nil
        idleTasks[serverID] = nil
        guard let session = sessions.removeValue(forKey: serverID) else { return }
        await stop(session: session)
        await diagnosticLog.record("stdio process stopped server=<redacted> reason=idle_timeout")
    }

    /// 请求失败后丢弃现有 session，避免复用协议状态未知的连接。
    private func teardownSessionIfPresent(serverID: String, reason: String) async {
        guard let session = sessions.removeValue(forKey: serverID) else { return }
        cancelIdleTimeout(serverID: serverID)
        await stop(session: session)
        await diagnosticLog.record("stdio process stopped server=<redacted> reason=\(reason)")
    }

    /// 停止 stdio session 并清理 pipe handler。
    private func stop(session: StdioMCPProcessSession) async {
        session.stdout.readabilityHandler = nil
        session.stderr.readabilityHandler = nil
        session.stdoutReaderTask.cancel()
        session.stderrReaderTask.cancel()
        await session.responseRouter.close(reason: "stdio session stopped")
        await session.stderrBuffer.flush()
        try? session.stdin.close()
        try? session.stdout.close()
        try? session.stderr.close()
        if session.process.isRunning {
            session.process.terminate()
        }
    }

    /// 把错误归一化为诊断日志 reason，避免把服务端 payload 直接写入日志。
    private func teardownReason(for error: any Error) -> String {
        if case MCPClientError.transportFailed(let reason) = error,
           reason.contains("request_timeout") {
            return "request_timeout"
        }
        return "request_failed"
    }

    /// 把 command 解析为 Process 可执行 URL；裸命令按 PATH 查找。
    private func executableURL(for command: String) -> URL {
        if command.contains("/") {
            return URL(fileURLWithPath: command)
        }
        let paths = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":")
        for path in paths {
            let candidate = URL(fileURLWithPath: String(path)).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate.path) {
                return candidate
            }
        }
        return URL(fileURLWithPath: command)
    }
}

/// actor 内部持有的 stdio 进程状态。
private final class StdioMCPProcessSession {
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
}

/// stdout JSON-RPC response router；按 id 分发 NDJSON response，避免阻塞 client actor。
private actor StdioMCPResponseRouter {
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
private actor StdioMCPStderrLineBuffer {
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
