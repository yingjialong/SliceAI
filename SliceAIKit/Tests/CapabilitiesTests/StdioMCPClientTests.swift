import Foundation
import SliceCore
import XCTest
@testable import Capabilities

/// stdio MCP client 的端到端 fixture 测试。
final class StdioMCPClientTests: XCTestCase {

    /// stdio client 必须 lazy 启动 fixture 进程，并完成 initialize → initialized → tools/list。
    func test_stdioClient_listsToolsFromFixtureProcess() async throws {
        let descriptor = fixtureDescriptor()
        let client = StdioMCPClient(descriptors: { [descriptor] })

        let tools = try await client.tools(for: descriptor)

        XCTAssertEqual(tools.count, 1)
        XCTAssertEqual(tools[0].ref, MCPToolRef(server: "fixture", tool: "echo"))
        XCTAssertEqual(tools[0].title, "Echo Query")
        XCTAssertEqual(tools[0].description, "Echo query")
        XCTAssertEqual(tools[0].inputSchema["type"], .string("object"))
    }

    /// tools/call 必须发送结构化 arguments，并把 fixture 返回的 text content 解码为 MCPCallResult。
    func test_stdioClient_callsToolWithStructuredArguments() async throws {
        let descriptor = fixtureDescriptor()
        let client = StdioMCPClient(descriptors: { [descriptor] })

        let result = try await client.call(
            ref: MCPToolRef(server: "fixture", tool: "echo"),
            args: ["query": .string("hello stdio")]
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content, [.text("hello stdio")])
    }

    /// 首次公开调用如果是 tools/call，也必须先完成 initialize → initialized → tools/list → tools/call。
    func test_stdioClient_callFirstPerformsToolsListBeforeToolCall() async throws {
        let descriptor = fixtureDescriptor()
        let client = StdioMCPClient(descriptors: { [descriptor] })

        let result = try await client.call(
            ref: MCPToolRef(server: "fixture", tool: "echo"),
            args: ["query": .string("call first")]
        )

        XCTAssertFalse(result.isError)
        XCTAssertEqual(result.content, [.text("call first")])
    }

    /// idle timeout 到期后必须停止子进程；下一次请求应能重新 lazy 启动。
    func test_stdioClient_idleTimeoutStopsProcess() async throws {
        let descriptor = fixtureDescriptor()
        let recorder = DiagnosticRecorder()
        let client = StdioMCPClient(
            descriptors: { [descriptor] },
            idleTimeoutNanoseconds: 80_000_000,
            diagnosticLog: MCPDiagnosticLog { message in
                await recorder.append(message)
            }
        )

        _ = try await client.tools(for: descriptor)
        try await Task.sleep(nanoseconds: 180_000_000)
        let messages = await recorder.messages

        XCTAssertTrue(
            messages.contains { $0.contains("idle_timeout") },
            "idle timeout 应写入诊断日志，实际 messages=\(messages)"
        )

        let toolsAfterRestart = try await client.tools(for: descriptor)
        XCTAssertEqual(toolsAfterRestart.map(\.ref.tool), ["echo"])
    }

    /// stderr diagnostic 必须脱敏 bearer、sk-、Authorization、Cookie 后再暴露给日志 sink。
    func test_stdioClient_redactsStderrDiagnostics() async throws {
        let descriptor = fixtureDescriptor()
        let recorder = DiagnosticRecorder()
        let client = StdioMCPClient(
            descriptors: { [descriptor] },
            diagnosticLog: MCPDiagnosticLog { message in
                await recorder.append(message)
            }
        )

        _ = try await client.call(
            ref: MCPToolRef(server: "fixture", tool: "echo"),
            args: [
                "query": .string("stderr"),
                "writeStderr": .bool(true),
            ]
        )
        try await Task.sleep(nanoseconds: 80_000_000)

        let joined = await recorder.messages.joined(separator: "\n")
        XCTAssertTrue(joined.contains("<redacted>"))
        XCTAssertFalse(joined.contains("Bearer secret-token"))
        XCTAssertFalse(joined.contains("sk-1234567890abcdef"))
        XCTAssertFalse(joined.contains("session=secret"))
        XCTAssertFalse(joined.contains("Authorization: token"))
    }

    /// initialize 失败后必须丢弃坏 session；下一次调用应启动新进程并重新握手成功。
    func test_stdioClient_initializeFailureDiscardsSessionBeforeRetry() async throws {
        let stateURL = temporaryStateFileURL()
        let descriptor = fixtureDescriptor(extraArgs: ["first-init-error", stateURL.path])
        let client = StdioMCPClient(descriptors: { [descriptor] })

        do {
            _ = try await client.tools(for: descriptor)
            XCTFail("首次 initialize 失败应抛出 JSON-RPC 协议错误")
        } catch MCPClientError.protocolError(let code, let message) {
            XCTAssertEqual(code, -32001)
            XCTAssertEqual(message, "initialize failed once")
        } catch {
            XCTFail("首次 initialize 失败错误类型不符合预期：\(error)")
        }

        let toolsAfterRetry = try await client.tools(for: descriptor)
        XCTAssertEqual(toolsAfterRetry.map(\.ref.tool), ["echo"])
    }

    /// 同一 server 的并发首次请求必须共享同一个 start/initialize，不能重复拉起 stdio 进程。
    func test_stdioClient_concurrentFirstUseSharesSingleSessionStart() async throws {
        let stateURL = temporaryStateFileURL()
        let descriptor = fixtureDescriptor(extraArgs: ["count-initialize", stateURL.path])
        let client = StdioMCPClient(descriptors: { [descriptor] })

        async let firstTools = client.tools(for: descriptor)
        async let secondTools = client.tools(for: descriptor)
        let (first, second) = try await (firstTools, secondTools)

        XCTAssertEqual(first.map(\.ref.tool), ["echo"])
        XCTAssertEqual(second.map(\.ref.tool), ["echo"])
        let initializeCount = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertEqual(initializeCount, "1")
    }

    /// 同一 server id 的启动参数变化后必须重启 stdio 进程，避免 Settings 保存后仍使用旧 runner。
    func test_stdioClient_restartsSessionWhenDescriptorLaunchConfigChanges() async throws {
        let stateURL = temporaryStateFileURL()
        let firstDescriptor = fixtureDescriptor(extraArgs: ["count-initialize", stateURL.path, "v1"])
        let secondDescriptor = fixtureDescriptor(extraArgs: ["count-initialize", stateURL.path, "v2"])
        let client = StdioMCPClient(descriptors: { [secondDescriptor] })

        _ = try await client.tools(for: firstDescriptor)
        let firstInitializeCount = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertEqual(firstInitializeCount, "1")

        _ = try await client.tools(for: secondDescriptor)
        let secondInitializeCount = try String(contentsOf: stateURL, encoding: .utf8)
        XCTAssertEqual(secondInitializeCount, "2")
    }

    /// 响应超时必须中断当前请求并 teardown session，不能被无换行/慢响应永久占住 actor。
    func test_stdioClient_requestTimeoutTearsDownSessionAndAllowsActorToContinue() async throws {
        let descriptor = fixtureDescriptor(extraArgs: ["delayed-list"])
        let recorder = DiagnosticRecorder()
        let client = StdioMCPClient(
            descriptors: { [descriptor] },
            diagnosticLog: MCPDiagnosticLog { message in
                await recorder.append(message)
            },
            requestTimeoutNanoseconds: 60_000_000
        )

        let start = Date()
        do {
            _ = try await client.tools(for: descriptor)
            XCTFail("tools/list 延迟超过 request timeout 时应抛出 transportFailed")
        } catch MCPClientError.transportFailed(let reason) {
            XCTAssertTrue(reason.contains("request_timeout"), "错误原因应标明 request_timeout，实际：\(reason)")
        } catch {
            XCTFail("request timeout 错误类型不符合预期：\(error)")
        }

        XCTAssertLessThan(Date().timeIntervalSince(start), 0.2, "request timeout 应早于 fixture 的 250ms 延迟响应")

        let messages = await recorder.messages.joined(separator: "\n")
        XCTAssertTrue(messages.contains("request_timeout"), "timeout teardown 应写入诊断日志，实际：\(messages)")
    }

    /// 旧 idle timeout 任务即使已越过 sleep，也不能在取消后误停新的 in-flight request。
    func test_stdioClient_cancelledIdleTimeoutCannotStopInFlightRequest() async throws {
        let descriptor = fixtureDescriptor()
        let client = StdioMCPClient(
            descriptors: { [descriptor] },
            idleTimeoutNanoseconds: 4_000_000,
            requestTimeoutNanoseconds: 500_000_000
        )

        _ = try await client.tools(for: descriptor)

        for index in 0..<40 {
            try await Task.sleep(nanoseconds: 4_000_000)
            do {
                let result = try await client.call(
                    ref: MCPToolRef(server: "fixture", tool: "echo"),
                    args: [
                        "query": .string("idle boundary \(index)"),
                        "delayCallMs": .number(20),
                    ]
                )
                XCTAssertEqual(result.content, [.text("idle boundary \(index)")])
            } catch MCPClientError.transportFailed(let reason) {
                XCTFail("取消后的旧 idle task 不应误停 in-flight request，实际 reason=\(reason)")
            } catch {
                throw error
            }
        }
    }

    /// stderr 分块输出时必须先缓冲完整行再脱敏，诊断日志也不能包含原始 server id。
    func test_stdioClient_buffersStderrLinesBeforeRedactionAndRedactsServerID() async throws {
        let sensitiveServerID = "stdio:///Users/majiajun/secret-host/server"
        let descriptor = fixtureDescriptor(id: sensitiveServerID)
        let recorder = DiagnosticRecorder()
        let client = StdioMCPClient(
            descriptors: { [descriptor] },
            diagnosticLog: MCPDiagnosticLog { message in
                await recorder.append(message)
            }
        )

        _ = try await client.call(
            ref: MCPToolRef(server: sensitiveServerID, tool: "echo"),
            args: [
                "query": .string("chunked stderr"),
                "writeChunkedStderr": .bool(true),
            ]
        )
        try await Task.sleep(nanoseconds: 100_000_000)

        let joined = await recorder.messages.joined(separator: "\n")
        XCTAssertTrue(joined.contains("<redacted>"))
        XCTAssertFalse(joined.contains("secret"), "stderr 跨 chunk secret 不应泄漏，实际日志：\(joined)")
        XCTAssertFalse(joined.contains(sensitiveServerID), "诊断日志不应包含原始 server id，实际日志：\(joined)")
        XCTAssertFalse(joined.contains("/Users/majiajun"))
        XCTAssertFalse(joined.contains("secret-host"))
    }

    /// 构造指向 test fixture 的 stdio descriptor。
    private func fixtureDescriptor(id: String = "fixture", extraArgs: [String] = []) -> MCPDescriptor {
        MCPDescriptor(
            id: id,
            transport: .stdio,
            command: "/usr/bin/env",
            args: ["node", fixtureURL().path] + extraArgs,
            url: nil,
            env: nil,
            capabilities: [.tools(["echo"])],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))
        )
    }

    /// 返回测试使用的临时状态文件路径，fixture 用它跨进程记录一次性失败。
    private func temporaryStateFileURL() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    }

    /// 返回 SwiftPM 复制到测试 bundle 的 fixture URL。
    private func fixtureURL() -> URL {
        Bundle.module.url(
            forResource: "stdio-mcp-fixture",
            withExtension: "js",
            subdirectory: "Fixtures"
        )!
    }
}

/// 测试用诊断日志收集器，actor 隔离避免异步 stderr handler 竞态。
private actor DiagnosticRecorder {
    private var storage: [String] = []

    /// 记录一条诊断消息。
    func append(_ message: String) {
        storage.append(message)
    }

    /// 返回当前已收集的诊断消息。
    var messages: [String] {
        storage
    }
}
