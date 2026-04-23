import Foundation

/// 细粒度权限，Tool 静态声明在 `tool.permissions`；`ExecutionEngine` 执行前做 `effectivePermissions ⊆ tool.permissions` 校验（D-24）
///
/// 设计要点：
/// - 每个 case 的关联值必须能让 `PermissionBroker` 判定"允许 / 拒绝"不需要额外上下文
/// - 路径字段使用用户目录相对（`~/Documents/**/*.md`）或绝对路径；比较前由 `PathSandbox` 规范化
/// - 同一 case 不同关联值视为不同权限（`.fileRead("a") != .fileRead("b")`）
public enum Permission: Codable, Sendable, Hashable {
    /// 访问特定域名（HTTPS）；host 为精确匹配
    case network(host: String)
    /// 读文件；path 支持通配（`~/Documents/**/*.md`）
    case fileRead(path: String)
    /// 写文件；同上
    case fileWrite(path: String)
    /// 剪贴板读 / 写（单一权限，不区分方向——macOS pasteboard 模型如此）
    case clipboard
    /// 剪贴板历史访问（Phase 1+ 才用）
    case clipboardHistory
    /// 执行 shell 命令；commands 为允许的命令串白名单（精确匹配）
    case shellExec(commands: [String])
    /// 调用 MCP server；tools=nil 表示允许该 server 全部 tool，否则为白名单
    case mcp(server: String, tools: [String]?)
    /// 屏幕录制 / 抓图
    case screen
    /// 系统音频输出（TTS / 朗读）
    case systemAudio
    /// Tool 级 memory 访问；scope 一般是 tool id
    case memoryAccess(scope: String)
    /// 触发其他 App 的 AppIntent / Shortcut
    case appIntents(bundleId: String)

    // MARK: - 手写 Codable（见 plan 开头 Canonical JSON Schema 章节：模板 B + C 混合）
    // 产出形式：
    //   {"network":"api.openai.com"}   (模板 C, single String)
    //   {"fileRead":"~/Docs/**/*.md"}
    //   {"clipboard":{}}                (empty marker)
    //   {"mcp":{"server":"postgres","tools":["query"]}}  (模板 B, nested struct)

    private enum CodingKeys: String, CodingKey {
        case network, fileRead, fileWrite, clipboard, clipboardHistory, shellExec,
             mcp, screen, systemAudio, memoryAccess, appIntents
    }

    /// 空对象哨兵，用于无 associated value 的 case
    private struct EmptyMarker: Codable, Equatable {}

    /// 多 associated value 的 mcp case 的 Codable 中转
    private struct MCPAccessRepr: Codable, Equatable {
        let server: String
        let tools: [String]?
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let v = try c.decodeIfPresent(String.self, forKey: .network) { self = .network(host: v); return }
        if let v = try c.decodeIfPresent(String.self, forKey: .fileRead) { self = .fileRead(path: v); return }
        if let v = try c.decodeIfPresent(String.self, forKey: .fileWrite) { self = .fileWrite(path: v); return }
        if c.contains(.clipboard) {
            _ = try c.decode(EmptyMarker.self, forKey: .clipboard); self = .clipboard; return
        }
        if c.contains(.clipboardHistory) {
            _ = try c.decode(EmptyMarker.self, forKey: .clipboardHistory); self = .clipboardHistory; return
        }
        if let v = try c.decodeIfPresent([String].self, forKey: .shellExec) { self = .shellExec(commands: v); return }
        if let v = try c.decodeIfPresent(MCPAccessRepr.self, forKey: .mcp) {
            self = .mcp(server: v.server, tools: v.tools); return
        }
        if c.contains(.screen) {
            _ = try c.decode(EmptyMarker.self, forKey: .screen); self = .screen; return
        }
        if c.contains(.systemAudio) {
            _ = try c.decode(EmptyMarker.self, forKey: .systemAudio); self = .systemAudio; return
        }
        if let v = try c.decodeIfPresent(String.self, forKey: .memoryAccess) { self = .memoryAccess(scope: v); return }
        if let v = try c.decodeIfPresent(String.self, forKey: .appIntents) { self = .appIntents(bundleId: v); return }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.network, in: c,
            debugDescription: "Permission requires exactly one known case key"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .network(let host):           try c.encode(host, forKey: .network)
        case .fileRead(let path):          try c.encode(path, forKey: .fileRead)
        case .fileWrite(let path):         try c.encode(path, forKey: .fileWrite)
        case .clipboard:                   try c.encode(EmptyMarker(), forKey: .clipboard)
        case .clipboardHistory:            try c.encode(EmptyMarker(), forKey: .clipboardHistory)
        case .shellExec(let commands):     try c.encode(commands, forKey: .shellExec)
        case .mcp(let server, let tools):  try c.encode(MCPAccessRepr(server: server, tools: tools), forKey: .mcp)
        case .screen:                      try c.encode(EmptyMarker(), forKey: .screen)
        case .systemAudio:                 try c.encode(EmptyMarker(), forKey: .systemAudio)
        case .memoryAccess(let scope):     try c.encode(scope, forKey: .memoryAccess)
        case .appIntents(let bundleId):    try c.encode(bundleId, forKey: .appIntents)
        }
    }
}

/// 权限授予记录
public struct PermissionGrant: Codable, Sendable, Equatable {
    /// 被授予的权限
    public let permission: Permission
    /// 授予时间
    public let grantedAt: Date
    /// 授予来源（用户同意 / 安装时确认 / 开发者）
    public let grantedBy: GrantSource
    /// 授权时长
    public let scope: GrantScope

    /// 构造权限授予记录
    /// - Parameters:
    ///   - permission: 被授予的权限
    ///   - grantedAt: 授予时间戳
    ///   - grantedBy: 授予来源
    ///   - scope: 授权时长
    public init(permission: Permission, grantedAt: Date, grantedBy: GrantSource, scope: GrantScope) {
        self.permission = permission
        self.grantedAt = grantedAt
        self.grantedBy = grantedBy
        self.scope = scope
    }
}

/// 授予来源
public enum GrantSource: String, Codable, Sendable, CaseIterable {
    /// 运行时弹窗由用户确认
    case userConsent
    /// Tool 安装流程中批量确认
    case toolInstall
    /// 开发 / 测试环境直接放行（仅 DEBUG 构建）
    case developer
}

/// 授权时长
public enum GrantScope: String, Codable, Sendable, CaseIterable {
    /// 本次调用后失效
    case oneTime
    /// App 进程生命周期内有效
    case session
    /// 写入 config，跨启动保留
    case persistent
}

/// 信任来源分级（D-23 / D-25）
///
/// 由安装 / 导入流程写入 `Tool` / `Skill` / `MCPDescriptor` 等顶层资源的 `provenance` 字段；
/// 运行时只读。`PermissionBroker` 决策规则：**能力分级决定最低下限（§3.9.2），Provenance 只能
/// 在下限之上调节 UX 文案，不能减少确认次数**（D-25）。
///
/// canonical 定义仅在本文件；spec §3.9.1 / §3.9.4.2 只做引用。
public enum Provenance: Codable, Sendable, Equatable {
    /// 随 App 打包的 Starter Pack / 内置工具
    case firstParty
    /// 从官方 Marketplace 安装且签名校验通过（Phase 4+）
    case communitySigned(publisher: String, signedAt: Date)
    /// 用户本地 clone / 自己写的资源，安装时已显式承认"我已审读来源"
    /// Phase 1 仅 `MCPDescriptor` 使用此态（见 spec §3.9.4.2）
    case selfManaged(userAcknowledgedAt: Date)
    /// 手动导入文件 / URL clone / sideload；`MCPDescriptor` 不允许此态——Phase 1 安装流程直接拒绝
    case unknown(importedFrom: URL?, importedAt: Date)

    // MARK: - 手写 Codable（模板 A + B；产出 `{"firstParty":{}}` / `{"communitySigned":{"publisher":...,"signedAt":...}}` 等）

    private enum CodingKeys: String, CodingKey {
        case firstParty, communitySigned, selfManaged, unknown
    }

    private struct EmptyMarker: Codable, Equatable {}
    private struct CommunitySignedRepr: Codable, Equatable { let publisher: String; let signedAt: Date }
    private struct SelfManagedRepr: Codable, Equatable { let userAcknowledgedAt: Date }
    private struct UnknownRepr: Codable, Equatable { let importedFrom: URL?; let importedAt: Date }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.firstParty) {
            _ = try c.decode(EmptyMarker.self, forKey: .firstParty); self = .firstParty; return
        }
        if let r = try c.decodeIfPresent(CommunitySignedRepr.self, forKey: .communitySigned) {
            self = .communitySigned(publisher: r.publisher, signedAt: r.signedAt); return
        }
        if let r = try c.decodeIfPresent(SelfManagedRepr.self, forKey: .selfManaged) {
            self = .selfManaged(userAcknowledgedAt: r.userAcknowledgedAt); return
        }
        if let r = try c.decodeIfPresent(UnknownRepr.self, forKey: .unknown) {
            self = .unknown(importedFrom: r.importedFrom, importedAt: r.importedAt); return
        }
        throw DecodingError.dataCorruptedError(
            forKey: CodingKeys.firstParty, in: c,
            debugDescription: "Provenance requires one of: firstParty, communitySigned, selfManaged, unknown"
        )
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .firstParty:
            try c.encode(EmptyMarker(), forKey: .firstParty)
        case .communitySigned(let publisher, let signedAt):
            try c.encode(CommunitySignedRepr(publisher: publisher, signedAt: signedAt), forKey: .communitySigned)
        case .selfManaged(let at):
            try c.encode(SelfManagedRepr(userAcknowledgedAt: at), forKey: .selfManaged)
        case .unknown(let from, let at):
            try c.encode(UnknownRepr(importedFrom: from, importedAt: at), forKey: .unknown)
        }
    }
}
