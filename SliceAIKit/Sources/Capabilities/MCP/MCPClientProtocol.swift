import Foundation
import SliceCore

/// MCP（Model Context Protocol）客户端协议：抽象 stdio / SSE 传输，让 ExecutionEngine
/// 在 M2 阶段就能注入 Mock 跑通主流程。
///
/// 设计要点（KISS）：
/// - 只暴露两个动作：`tools(for:)` 询问 server 暴露的工具列表、`call(ref:args:)` 调单个工具。
/// - 本文件只定义 client protocol 与 `MCPClientError`；server/tool/result/JSON 等 canonical MCP
///   值类型来自 SliceCore，避免 Capabilities 再维护一套重复契约。
/// - **`MCPDescriptor` / `MCPToolDescriptor` / `MCPToolRef` / `MCPCallResult` 不在本文件**：
///   canonical 定义在 SliceCore，被
///   `AgentTool.mcpAllowlist` / `PipelineStep.mcp` / `SideEffect.callMCP` / `ExecutionEvent.toolCallProposed`
///   等多处引用——本协议直接 `import SliceCore` 复用，避免"传输层私有类型 vs 领域层 canonical 类型"
///   的双向适配；Phase 1 真实 client 接入 AgentTool / SideEffect 时无需做字段名翻译。
/// - Phase 1 才上真实 stdio / SSE 实现；本协议只先锁定 canonical contract。
public protocol MCPClientProtocol: Sendable {
    /// 查询某个 MCP server 当前暴露的工具列表。
    /// - Parameter descriptor: SliceCore canonical server 描述符。
    /// - Returns: 该 server 暴露的工具描述数组；server 没有工具时返回空数组。
    /// - Throws: `MCPClientError.transportFailed` / `.decodingFailed`（M2 Mock 实现不会主动抛错）。
    func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolDescriptor]

    /// 调用 MCP server 暴露的某个工具。
    /// - Parameters:
    ///   - ref: 目标工具引用（必须出现在该 server 之前 `tools(for:)` 返回的列表里）。
    ///   - args: 传给工具的结构化 JSON 参数。
    /// - Returns: server 返回的结果（见 `MCPCallResult.isError` 区分 server 端业务错误）。
    /// - Throws: `MCPClientError.toolNotFound`（工具不在已知列表）/ `.transportFailed` / `.decodingFailed`。
    func call(ref: MCPToolRef, args: MCPJSONValue.Object) async throws -> MCPCallResult
}

// MARK: - MCPClientError

/// MCP client 调用错误枚举。
///
/// case 的语义边界：
/// - `.toolNotFound`: 调用的 `MCPToolRef` 不在 server 暴露的 tools 列表里——属于"使用方拼错了"
///   的客户端错误，区别于 transport 层失败；
/// - `.transportFailed`: stdio / SSE 传输层失败（连接断 / 子进程 crash 等），M2 阶段用
///   `String` 简单描述原因；Phase 1 真实 client 落地时再考虑要不要拆出 underlying error。
/// - `.decodingFailed`: server 返回的 JSON-RPC 响应解析失败（M2 阶段无解析逻辑，由 Phase 1
///   触发——这里先把 case 占住保证 enum 闭集稳定，避免 Phase 1 改 enum 时连带影响 M2 测试）。
/// - `.protocolError`: server 返回 JSON-RPC error object，属于协议层错误；注意这不同于
///   `MCPCallResult.isError == true` 的工具执行错误，后者应作为正常 result 返回。
/// - `.unsupportedTransport`: 当前 milestone 不支持的 transport；M1 只启用 stdio，远程 transport
///   在 routing 层 fail-fast，避免上层执行器直接 switch `MCPTransport`。
///
/// 关联值与日志脱敏：
/// - **所有带用户/服务端 payload 的 case 全部脱敏**：`.toolNotFound` 关联的 `ref.server` / `ref.tool`
///   在 Phase 1 真实接入
///   用户配置的 MCP server 后，可能出现 `stdio:///Users/me/projects/secret/.mcp/server` 这类
///   含本地路径 / 项目名 / 私有主机名的字符串；`.transportFailed` / `.decodingFailed` 的 `reason`
///   以及 `.protocolError.message` 则可能携带 server 路径 / JSON 片段 / underlying error。统一脱敏与
///   `SliceError.developerContext`
///   对带 String / 路径 payload 的 case 同口径，避免 audit jsonl 与 Console 输出泄露用户配置。
/// - 需要排查 `.toolNotFound` 时改用单独的 opt-in debug trace（Phase 1+ 落地），或对
///   `ref.server` / `ref.tool` 做哈希 / 短 ID 后再写日志；本 PR 不引入此 opt-in 路径。
/// - AuditLog 写入应使用 `developerContext` 而非 `String(describing:)`。
public enum MCPClientError: Error, Sendable, Equatable {
    /// 调用的 tool 不在 server 暴露的 tools 列表里。
    case toolNotFound(ref: MCPToolRef)

    /// stdio / SSE 传输层失败（连接断 / 子进程 crash 等）。
    case transportFailed(reason: String)

    /// MCP server 返回的 JSON-RPC 响应解析失败。
    case decodingFailed(reason: String)

    /// MCP JSON-RPC error object，区别于 `MCPCallResult.isError == true` 的工具执行错误。
    case protocolError(code: Int, message: String)

    /// 当前阶段不支持的 MCP transport。
    case unsupportedTransport(MCPTransport)

    /// 用于日志打印的开发者上下文；所有用户/服务端 payload 一律脱敏，与 `SliceError` 同口径。
    /// 详见类型 doc"关联值与日志脱敏"段；调用方写 AuditLog 时请用本属性而非 `String(describing:)`。
    public var developerContext: String {
        switch self {
        case .toolNotFound:
            // ref.server / ref.tool 在 Phase 1 真实接入用户 MCP 配置后可能含路径 / 项目名 / 私有主机名
            return "toolNotFound(server=<redacted>, tool=<redacted>)"
        case .transportFailed:
            return "transportFailed(<redacted>)"
        case .decodingFailed:
            return "decodingFailed(<redacted>)"
        case .protocolError(let code, _):
            return "protocolError(code=\(code), message=<redacted>)"
        case .unsupportedTransport(let transport):
            return "unsupportedTransport(\(transport.rawValue))"
        }
    }
}
