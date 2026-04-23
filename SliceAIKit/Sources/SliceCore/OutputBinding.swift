import Foundation

/// Tool 的输出绑定；决定结果展示形态 + 并行副作用
public struct OutputBinding: Sendable, Equatable, Codable {
    /// 主展示方式
    public let primary: PresentationMode
    /// 并行副作用；按数组顺序触发
    public let sideEffects: [SideEffect]

    /// 构造 OutputBinding
    public init(primary: PresentationMode, sideEffects: [SideEffect]) {
        self.primary = primary
        self.sideEffects = sideEffects
    }
}

/// v2 结果展示模式；六种模式都作为正式成员进入数据模型（spec §3.3.6）
///
/// **命名说明**：命名有意避开 `Tool.swift:85` 既有 v1 `public enum DisplayMode`（3-case，
/// Tool v1 专用）。v2 canonical 6-case 使用 `PresentationMode`；v1 `DisplayMode` 原封保留，
/// 与本类型无继承关系，M3 rename 阶段再统一。rawValue 完全包含 v1 的三个字符串
/// （"window" / "bubble" / "replace"），方便 migrator 零损失迁移。
///
/// Phase 0 M1 仅定义 enum；各模式的 UI 实现按 phase 渐进：
/// - Phase 0 (v0.1 继承): `.window`
/// - Phase 2: `.replace` / `.bubble` / `.structured` / `.silent`
///   （配合 InlineReplaceOverlay / BubblePanel / StructuredResultView）
/// - Phase 2+: `.file`
public enum PresentationMode: String, Sendable, Codable, CaseIterable {
    /// 独立浮窗（v0.1 默认）
    case window
    /// 小气泡，自动消失
    case bubble
    /// 替换选区（AX setSelectedText 或 paste fallback）
    case replace
    /// 写文件
    case file
    /// 无 UI，只做副作用
    case silent
    /// JSONSchema 结构化结果，UI 自动渲染表单/表格
    case structured
}

/// 副作用：声明式列表，执行引擎按顺序触发
///
/// D-24 要求每个 case 能**静态推导** 所需 Permission，见 `inferredPermissions` extension。
public enum SideEffect: Sendable, Equatable, Codable {
    case appendToFile(path: String, header: String?)
    case copyToClipboard
    case notify(title: String, body: String)
    case runAppIntent(bundleId: String, intent: String, params: [String: String])
    case callMCP(ref: MCPToolRef, params: [String: String])
    /// 写 Tool 级 memory；`tool` 必须是调用方 Tool 的 `id`，会映射为 `.memoryAccess(scope: tool)` 权限
    case writeMemory(tool: String, entry: String)
    case tts(voice: String?)

    // MARK: - 手写 Codable（模板 A + B，含 Task 3/8 统一的单键 guard + 明确未知键 throw）

    private enum CodingKeys: String, CodingKey {
        case appendToFile, copyToClipboard, notify, runAppIntent, callMCP, writeMemory, tts
    }
    private struct EmptyMarker: Codable, Equatable {}
    private struct AppendRepr: Codable, Equatable { let path: String; let header: String? }
    private struct NotifyRepr: Codable, Equatable { let title: String; let body: String }
    private struct AppIntentRepr: Codable, Equatable {
        let bundleId: String
        let intent: String
        let params: [String: String]
    }
    private struct CallMCPRepr: Codable, Equatable { let ref: MCPToolRef; let params: [String: String] }
    private struct MemoryRepr: Codable, Equatable { let tool: String; let entry: String }
    private struct TTSRepr: Codable, Equatable { let voice: String? }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // 单键 canonical contract（与 Permission/Provenance/CachePolicy 同款）
        guard c.allKeys.count == 1 else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: c.codingPath,
                debugDescription: "SideEffect requires exactly one key, got \(c.allKeys.count)"
            ))
        }
        if let r = try c.decodeIfPresent(AppendRepr.self, forKey: .appendToFile) {
            self = .appendToFile(path: r.path, header: r.header); return
        }
        if c.contains(.copyToClipboard) {
            _ = try c.decode(EmptyMarker.self, forKey: .copyToClipboard); self = .copyToClipboard; return
        }
        if let r = try c.decodeIfPresent(NotifyRepr.self, forKey: .notify) {
            self = .notify(title: r.title, body: r.body); return
        }
        if let r = try c.decodeIfPresent(AppIntentRepr.self, forKey: .runAppIntent) {
            self = .runAppIntent(bundleId: r.bundleId, intent: r.intent, params: r.params); return
        }
        if let r = try c.decodeIfPresent(CallMCPRepr.self, forKey: .callMCP) {
            self = .callMCP(ref: r.ref, params: r.params); return
        }
        if let r = try c.decodeIfPresent(MemoryRepr.self, forKey: .writeMemory) {
            self = .writeMemory(tool: r.tool, entry: r.entry); return
        }
        if let r = try c.decodeIfPresent(TTSRepr.self, forKey: .tts) {
            self = .tts(voice: r.voice); return
        }
        throw DecodingError.dataCorrupted(.init(
            codingPath: c.codingPath,
            debugDescription: "SideEffect encountered unknown case key"
        ))
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .appendToFile(let p, let h): try c.encode(AppendRepr(path: p, header: h), forKey: .appendToFile)
        case .copyToClipboard:            try c.encode(EmptyMarker(), forKey: .copyToClipboard)
        case .notify(let t, let b):       try c.encode(NotifyRepr(title: t, body: b), forKey: .notify)
        case .runAppIntent(let b, let i, let p):
            try c.encode(AppIntentRepr(bundleId: b, intent: i, params: p), forKey: .runAppIntent)
        case .callMCP(let r, let p):      try c.encode(CallMCPRepr(ref: r, params: p), forKey: .callMCP)
        case .writeMemory(let t, let e):  try c.encode(MemoryRepr(tool: t, entry: e), forKey: .writeMemory)
        case .tts(let v):                 try c.encode(TTSRepr(voice: v), forKey: .tts)
        }
    }
}

public extension SideEffect {

    /// D-24：静态推导本 side effect 会触发哪些 Permission
    ///
    /// 规则：
    /// - 不可读外部状态；只能基于 case 关联值推导
    /// - 新增 case 必须同步在此返回对应 Permission，否则 PermissionGraph 漏报
    /// - 本地通知（`.notify`）不计为 permission；macOS 首次通知时系统会独立弹框
    var inferredPermissions: [Permission] {
        switch self {
        case .appendToFile(let path, _):
            return [.fileWrite(path: path)]
        case .copyToClipboard:
            return [.clipboard]
        case .notify:
            return []
        case .runAppIntent(let bundleId, _, _):
            return [.appIntents(bundleId: bundleId)]
        case .callMCP(let ref, _):
            return [.mcp(server: ref.server, tools: [ref.tool])]
        case .writeMemory(let toolId, _):
            return [.memoryAccess(scope: toolId)]
        case .tts:
            return [.systemAudio]
        }
    }
}

/// 对某个 MCP tool 的引用；`AgentTool.mcpAllowlist` 与 `SideEffect.callMCP` 共用
public struct MCPToolRef: Sendable, Equatable, Hashable, Codable {
    /// MCP server 的本地注册名
    public let server: String
    /// server 暴露的 tool 名
    public let tool: String

    /// 构造 MCPToolRef
    public init(server: String, tool: String) {
        self.server = server
        self.tool = tool
    }
}
