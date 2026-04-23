import Foundation

/// Tool 声明的一次上下文采集请求
///
/// 由 `ContextCollector` 解析 provider 名找到对应 `ContextProvider` 并传入 args 执行。
/// M1 定义数据结构；M2 填实 `ContextCollector.resolve(seed:requests:)`。
public struct ContextRequest: Sendable, Equatable, Codable {
    /// 采集结果在 `ContextBag` 中的键名
    public let key: ContextKey
    /// 采集器 provider 注册名（如 `file.read` / `clipboard.current` / `mcp.call`）
    public let provider: String
    /// 透传给 provider 的参数（如 `["path": "~/vocab.md"]`）
    public let args: [String: String]
    /// 缓存策略
    public let cachePolicy: CachePolicy
    /// 失败容忍策略
    public let requiredness: Requiredness

    /// 构造 ContextRequest
    public init(
        key: ContextKey,
        provider: String,
        args: [String: String],
        cachePolicy: CachePolicy,
        requiredness: Requiredness
    ) {
        self.key = key
        self.provider = provider
        self.args = args
        self.cachePolicy = cachePolicy
        self.requiredness = requiredness
    }
}

/// 采集缓存策略
///
/// **手写 Codable（模板 A + C）**
public enum CachePolicy: Sendable, Equatable, Codable {
    case none
    case session
    case ttl(TimeInterval)

    private enum CodingKeys: String, CodingKey { case none, session, ttl }
    private struct EmptyMarker: Codable, Equatable {}

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if c.contains(.none) { _ = try c.decode(EmptyMarker.self, forKey: .none); self = .none; return }
        if c.contains(.session) { _ = try c.decode(EmptyMarker.self, forKey: .session); self = .session; return }
        if let t = try c.decodeIfPresent(TimeInterval.self, forKey: .ttl) { self = .ttl(t); return }
        throw DecodingError.dataCorruptedError(forKey: CodingKeys.none, in: c,
            debugDescription: "CachePolicy requires one of: none, session, ttl")
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .none:    try c.encode(EmptyMarker(), forKey: .none)
        case .session: try c.encode(EmptyMarker(), forKey: .session)
        case .ttl(let t): try c.encode(t, forKey: .ttl)
        }
    }
}

/// 上下文采集器契约；内置 provider 与第三方 provider 均实现此协议
///
/// 注册：M2 的 `ContextCollector` 维护一个 `[name: any ContextProvider]` 字典，
/// 在 app 启动时把所有内置 provider 装入。
///
/// 关键静态方法 `inferredPermissions(for:)` 是 D-24 权限声明闭环的基石：
/// - `PermissionGraph.compute(tool:)` 聚合所有 `tool.contexts` 中每个 request
///   的 `type(of: provider).inferredPermissions(for: request.args)` 结果；
/// - 要求该方法是纯函数、无副作用、不访问外部资源。
/// - 漏报 → 运行时“权限未声明”错误；多报 → 声明超出实际、影响 UX 无安全风险。
public protocol ContextProvider: Sendable {
    /// Provider 注册名，需全局唯一
    var name: String { get }

    /// 静态推导本次采集会触发哪些 Permission
    /// - Parameter args: ContextRequest.args 原样透传
    /// - Returns: 本次采集需要的权限；无权限需求返回空数组
    static func inferredPermissions(for args: [String: String]) -> [Permission]

    /// 实际执行采集；调用前 `PermissionBroker.gate` 已通过
    /// - Parameters:
    ///   - request: 原始 request
    ///   - seed: 当前 ExecutionSeed 中的 selection（便于基于选区参数化）
    ///   - app: 前台 app 快照
    /// - Returns: 采集结果 ContextValue
    func resolve(request: ContextRequest, seed: SelectionSnapshot, app: AppSnapshot) async throws -> ContextValue
}
