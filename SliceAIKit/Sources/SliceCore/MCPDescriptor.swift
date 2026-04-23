import Foundation

/// MCP server 配置描述；`mcp.json` 中一条记录对应一个 MCPDescriptor
///
/// 兼容 Claude Desktop `mcpServers` 格式：stdio 下填 `command + args + env`；
/// SSE / WebSocket 下填 `url`。Phase 1 的 `MCPClient` 消费此结构启动 / 连接 server。
///
/// `provenance` 由安装流程写入；`.unknown` 来源的 MCPDescriptor 在**安装流程入口**被拒绝，
/// 不会被构造出来（D-23 / §3.9.4.2）。
public struct MCPDescriptor: Identifiable, Sendable, Codable, Equatable {
    /// 本地注册名
    public let id: String
    /// 传输方式
    public let transport: MCPTransport
    /// stdio 的命令（如 `npx` / `node` / `python`）；非 stdio 时 nil
    public let command: String?
    /// stdio 的命令参数；非 stdio 时 nil
    public let args: [String]?
    /// SSE / WebSocket 端点；stdio 时 nil
    public let url: URL?
    /// 环境变量；stdio 用于 `ProcessInfo.processEnv`
    public let env: [String: String]?
    /// 声明能提供的能力
    public let capabilities: [MCPCapability]
    /// 信任来源（仅 `.firstParty` / `.communitySigned` / `.selfManaged`；不可为 `.unknown`）
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
}

/// MCP 传输方式
public enum MCPTransport: String, Sendable, Codable, CaseIterable {
    /// 标准输入输出
    case stdio
    /// Server-Sent Events
    case sse
    /// WebSocket
    case websocket
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
