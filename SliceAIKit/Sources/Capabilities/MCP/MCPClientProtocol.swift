import Foundation

/// MCP（Model Context Protocol）客户端协议：抽象 stdio / SSE 传输，让 ExecutionEngine
/// 在 M2 阶段就能注入 Mock 跑通主流程。
///
/// 设计要点（KISS）：
/// - 只暴露两个动作：`tools(for:)` 询问 server 暴露的工具列表、`call(ref:args:)` 调单个工具。
/// - 全部 5 类型（protocol + `MCPDescriptor` + `MCPToolRef` + `MCPCallResult` + `MCPClientError`）
///   集中在同一文件，方便把"对外契约"作为单点阅读；任一类型语义改动都会落到这里，避免拆散到多文件后
///   review 时漏看。
/// - Phase 1 才上真实 stdio / SSE 实现；届时再决定是否把 `MCPCallResult` 升级为更细的 ContentItem
///   (text / image / blob) enum，以及把 args 从 `String → String` 扩到任意 JSON。
public protocol MCPClientProtocol: Sendable {
    /// 查询某个 MCP server 当前暴露的工具列表。
    /// - Parameter descriptor: server 描述符（含稳定 ID）。
    /// - Returns: 该 server 暴露的工具引用数组；server 没有工具时返回空数组。
    /// - Throws: `MCPClientError.transportFailed` / `.decodingFailed`（M2 Mock 实现不会主动抛错）。
    func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolRef]

    /// 调用 MCP server 暴露的某个工具。
    /// - Parameters:
    ///   - ref: 目标工具引用（必须出现在该 server 之前 `tools(for:)` 返回的列表里）。
    ///   - args: 传给工具的参数；M2 阶段约定为 `String → String` map（KISS），Phase 1 视真实需求扩展。
    /// - Returns: server 返回的结果（见 `MCPCallResult.isError` 区分 server 端业务错误）。
    /// - Throws: `MCPClientError.toolNotFound`（工具不在已知列表）/ `.transportFailed` / `.decodingFailed`。
    func call(ref: MCPToolRef, args: [String: String]) async throws -> MCPCallResult
}

// MARK: - MCPDescriptor

/// MCP server 描述符（最小 KISS 版本）。
///
/// 仅承载稳定 ID（如 `"stdio://my-server"` / `"sse://localhost:8765"`），用于：
/// - 让 `MCPClient` 路由到正确的传输层；
/// - 让 `MCPToolRef.server` 反向定位回 server。
///
/// Phase 1 真实 client 落地时，这里可能再加 `transport: enum { .stdio, .sse }` / `endpoint: URL`
/// 等字段；M2 阶段不需要这些信息——Mock 只用 ID 做 dictionary key。
public struct MCPDescriptor: Sendable, Equatable, Hashable, Codable {
    /// MCP server 的稳定 ID。
    /// 约定形如 `"stdio://my-server"` / `"sse://host:port"`，但 protocol 不强制 schema——
    /// 真正的解析责任在 Phase 1 的真实 client；M2 把 ID 当不透明字符串处理。
    public let id: String

    /// 构造一个 MCP server 描述符。
    /// - Parameter id: server 的稳定 ID。
    public init(id: String) {
        self.id = id
    }
}

// MARK: - MCPToolRef

/// MCP server 暴露的工具引用（最小 KISS 版本）。
///
/// 用 `(server, name)` 二元组定位一个工具——`server` 与 `MCPDescriptor.id` 对齐，`name` 在
/// 该 server 内部唯一。这套结构与 MCP 官方 JSON-RPC 协议的 `tools/call` 请求一一对应。
///
/// 故意做 `Hashable`：`MockMCPClient` 需要把 `[MCPToolRef: MCPCallResult]` 当字典 key 路由响应。
public struct MCPToolRef: Sendable, Equatable, Hashable, Codable {
    /// 工具所在 server 的 ID（与 `MCPDescriptor.id` 对齐）。
    public let server: String

    /// 工具名（在该 server 内唯一）。
    public let name: String

    /// 构造一个工具引用。
    /// - Parameters:
    ///   - server: server 的稳定 ID。
    ///   - name: 工具名。
    public init(server: String, name: String) {
        self.server = server
        self.name = name
    }
}

// MARK: - MCPCallResult

/// MCP 工具调用返回值。
///
/// 字段语义：
/// - `content`: 返回内容数组。MCP 协议允许多块（text / image / blob），M2 仅约定 text；
///   Phase 1 真实 client 落地时把这里扩为更细的 `ContentItem` enum 或迁出到 SliceCore。
/// - `isError`: server 端业务错误（区别于 transport / parse 错误——后者由 client 直接 throw）。
///   MCP 协议里 server 可以正常返回但带 `isError=true`，例如"找不到该资源"——这种语义错应该让上层
///   决定是否给用户提示，而不是 throw 把调用栈打断。
/// - `meta`: server 透传的元数据。脱敏责任在 server 端约束；`AuditLog` 入口的
///   `Redaction.scrubMetadata(...)` 兜底，避免 secret 流入审计日志。
public struct MCPCallResult: Sendable, Equatable, Codable {
    /// 返回内容（M2 约定为 text 段）。
    public let content: [String]

    /// server 端业务错误标志（true 表示 server 主动返回错误状态，但请求传输 / 解码均正常）。
    public let isError: Bool

    /// server 透传的 metadata；可为 `nil` 表示本次调用无 meta。
    public let meta: [String: String]?

    /// 构造一个 MCP 工具调用返回值。
    /// - Parameters:
    ///   - content: 返回内容（M2 约定 text 段）。
    ///   - isError: server 端业务错误标志，默认 `false`。
    ///   - meta: server 透传 metadata，默认 `nil`。
    public init(content: [String], isError: Bool, meta: [String: String]? = nil) {
        self.content = content
        self.isError = isError
        self.meta = meta
    }
}

// MARK: - MCPClientError

/// MCP client 调用错误枚举。
///
/// 三个 case 的语义边界：
/// - `.toolNotFound`: 调用的 `MCPToolRef` 不在 server 暴露的 tools 列表里——属于"使用方拼错了"
///   的客户端错误，区别于 transport 层失败；
/// - `.transportFailed`: stdio / SSE 传输层失败（连接断 / 子进程 crash 等），M2 阶段用
///   `String` 简单描述原因；Phase 1 真实 client 落地时再考虑要不要拆出 underlying error。
/// - `.decodingFailed`: server 返回的 JSON-RPC 响应解析失败（M2 阶段无解析逻辑，由 Phase 1
///   触发——这里先把 case 占住保证 enum 闭集稳定，避免 Phase 1 改 enum 时连带影响 M2 测试）。
///
/// 关联值仅承载已脱敏 / 客户端可控的字符串：
/// - `.toolNotFound` 的 `ref` 来自调用方，不会带敏感数据；
/// - `.transportFailed` / `.decodingFailed` 的 `reason` 由真实 client 在生成时自行脱敏，
///   M2 Mock 不会构造这两种 case，所以无脱敏风险。
public enum MCPClientError: Error, Sendable, Equatable {
    /// 调用的 tool 不在 server 暴露的 tools 列表里。
    case toolNotFound(ref: MCPToolRef)

    /// stdio / SSE 传输层失败（连接断 / 子进程 crash 等）。
    case transportFailed(reason: String)

    /// MCP server 返回的 JSON-RPC 响应解析失败。
    case decodingFailed(reason: String)
}
