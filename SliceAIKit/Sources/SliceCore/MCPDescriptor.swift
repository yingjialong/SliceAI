import Foundation

/// MCP server 配置描述；`mcp.json` 中一条记录对应一个 MCPDescriptor
///
/// 兼容 Claude Desktop `mcpServers` 格式：stdio 下填 `command + args + env`。
/// 远程传输使用 Streamable HTTP；旧 SSE / WebSocket 只保留解码兼容，不允许在设置页新建。
///
/// `provenance` 由安装流程写入；`.unknown` 来源的 MCPDescriptor 在**安装流程入口**被拒绝，
/// 不会被构造出来（D-23 / §3.9.4.2）。
public struct MCPDescriptor: Identifiable, Sendable, Codable, Equatable, Hashable {
    /// 本地注册名
    public let id: String
    /// 传输方式
    public let transport: MCPTransport
    /// stdio 的命令（如 `npx` / `node` / `python`）；非 stdio 时 nil
    public let command: String?
    /// stdio 的命令参数；非 stdio 时 nil
    public let args: [String]?
    /// 远程端点；stdio 时 nil
    public let url: URL?
    /// 环境变量；stdio 用于 `ProcessInfo.processEnv`
    public let env: [String: String]?
    /// 声明能提供的能力
    public let capabilities: [MCPCapability]
    /// 信任来源（仅 `.firstParty` / `.communitySigned` / `.selfManaged`；不可为 `.unknown`）
    ///
    /// `var` 允许安装流程在签名校验完成后更新；运行时消费方（MCPClient 启动检查、PermissionBroker）
    /// **不得 mutate**，按只读语义消费。`.unknown` 在安装流程入口被拒绝（D-23 / §3.9.4.2），
    /// 理论上不会被构造出来，本字段也不在代码层强制——信任边界在安装流程。
    public var provenance: Provenance

    /// 构造 MCPDescriptor
    public init(
        id: String,
        transport: MCPTransport,
        command: String?,
        args: [String]?,
        url: URL?,
        env: [String: String]?,
        capabilities: [MCPCapability],
        provenance: Provenance
    ) {
        self.id = id
        self.transport = transport
        self.command = command
        self.args = args
        self.url = url
        self.env = env
        self.capabilities = capabilities
        self.provenance = provenance
    }

    /// MCPDescriptor 的本地注册身份只由稳定 ID 决定，不按 transport/capabilities/provenance 做内容相等。
    public static func == (lhs: MCPDescriptor, rhs: MCPDescriptor) -> Bool {
        lhs.id == rhs.id
    }

    /// 仅用稳定注册 ID 参与哈希，保持 Equatable/Hashable 身份语义一致。
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

/// MCP 传输方式
public enum MCPTransport: String, Sendable, Codable, CaseIterable {
    /// 标准输入输出
    case stdio
    /// Streamable HTTP
    case streamableHTTP = "streamable-http"
    /// 旧 HTTP+SSE 传输；仅保留解码兼容，Phase 1 不支持新建或连接
    case sse
    /// WebSocket
    case websocket

    /// Phase 1 设置页是否允许新建该 transport。
    public var isCreatableInPhase1Settings: Bool {
        switch self {
        case .stdio, .streamableHTTP:
            return true
        case .sse, .websocket:
            return false
        }
    }
}

/// MCP server 能力声明
///
/// **手写 Codable（模板 C）**：三 case 都是 `[String]`，直接 encode 数组。
/// 同时采用 Task 3/8/10/11 同款 wire-format 硬化（allKeys.count == 1 guard + cleaner 未知键 throw）。
public enum MCPCapability: Sendable, Equatable, Codable {
    /// 工具列表
    case tools([String])
    /// 资源列表
    case resources([String])
    /// Prompt 模板列表
    case prompts([String])

    private enum CodingKeys: String, CodingKey { case tools, resources, prompts }

    /// 从解码器构造；严格校验只能出现一个 case key，未知 case key 抛 `DecodingError`
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard c.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "MCPCapability requires exactly one key, got \(c.allKeys.count)"
            ))
        }
        if let a = try c.decodeIfPresent([String].self, forKey: .tools) { self = .tools(a); return }
        if let a = try c.decodeIfPresent([String].self, forKey: .resources) { self = .resources(a); return }
        if let a = try c.decodeIfPresent([String].self, forKey: .prompts) { self = .prompts(a); return }
        throw DecodingError.dataCorrupted(.init(
            codingPath: c.codingPath,
            debugDescription: "MCPCapability encountered unknown case key"
        ))
    }

    /// 编码到编码器；每个 case 直接 encode 底层 `[String]`，避免 `_0` 包装
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .tools(let a): try c.encode(a, forKey: .tools)
        case .resources(let a): try c.encode(a, forKey: .resources)
        case .prompts(let a): try c.encode(a, forKey: .prompts)
        }
    }
}
