import Capabilities
import Foundation
import SliceCore

/// D-24 静态权限闭环（spec §3.9.6.5）：聚合 tool 各来源的 inferred permission，
/// 与 `tool.permissions` 静态声明集合做 ⊆ 校验。
///
/// **聚合来源 4 类**：
/// 1. `tool.contexts` 里每个 `ContextRequest` → `type(of: provider).inferredPermissions(for: request.args)`
///    （provider 实例由构造期注入的 `ContextProviderRegistry` 路由）
/// 2. `outputBinding.sideEffects` 里每个 `SideEffect.inferredPermissions`
/// 3. `agent.mcpAllowlist` / `pipeline.mcp` step / `sideEffect.callMCP` 中的 `MCPToolRef`
///    → `.mcp(server:tools:)`（按 server 维度去重）
/// 4. `agent.builtinCapabilities` → 通过 `mapBuiltin(_:scope:)` 映射成 1-2 条 Permission
///
/// **不变量（D-17 + D-24）**：
/// - 纯静态：方法不做 IO，只读 tool 字段；可以反复调用得到一致结果
/// - 不硬编码 provider 名字：所有 ContextProvider 路由通过注入的 registry，便于扩展
/// - Pipeline 递归：`pipeline.steps` 里的 `.prompt(inline:)` 与 `.mcp(ref:)` 也参与聚合
///
/// **why actor**：保留 actor 形态便于 M3+ 引入"按用户配置缓存 inferred 结果"等 stateful 操作；
/// 当前实现内部纯函数化、可平移到 struct，但保持类型签名稳定避免 ExecutionEngine 频繁改动。
public actor PermissionGraph {

    // MARK: - Stored

    /// 共享 ContextProviderRegistry——构造期注入；与 `ContextCollector` 使用同一实例
    /// 才能保证 `inferredPermissions(for:)` 的 provider 与运行时实际 resolve 的 provider 一致
    private let providerRegistry: ContextProviderRegistry

    // MARK: - Init

    /// 构造 PermissionGraph
    /// - Parameter providerRegistry: 与 `ContextCollector` 共享的 ContextProvider 注册表；
    ///   若调用方未注入 provider（registry.providers 为空），但 tool 含 `ContextRequest`，
    ///   `compute(tool:)` 会按设计抛 `.toolPermission(.unknownProvider)`。
    public init(providerRegistry: ContextProviderRegistry) {
        self.providerRegistry = providerRegistry
    }

    // MARK: - Public API

    /// 计算 tool 的 EffectivePermissions（D-24 静态闭环）
    ///
    /// **流程**（actor 方法但不做 IO，async 仅为承诺未来兼容缓存的 actor hop）：
    /// 1. 遍历所有 `ContextRequest`：registry 路由 provider；找不到 → throw
    ///    `SliceError.toolPermission(.unknownProvider(id: request.provider))`
    /// 2. 遍历所有 `SideEffect`：调 `.inferredPermissions` 进 fromSideEffects
    /// 3. 遍历所有 `MCPToolRef`：转成 `.mcp(server:tools:[ref.tool])` 进 fromMCP
    /// 4. 遍历所有 `BuiltinCapability`：调 `mapBuiltin(_:scope:)` 进 fromBuiltins
    ///
    /// - Parameter tool: Tool 完整定义
    /// - Returns: 聚合后的 `EffectivePermissions`（含 declared + 4 个 from* set）
    /// - Throws: `SliceError.toolPermission(.unknownProvider)` 当 ContextRequest 引用未注册的 provider 时
    public func compute(tool: Tool) async throws -> EffectivePermissions {
        // declared 直接来自 tool.permissions，转 Set 便于 union 去重
        let declared = Set(tool.permissions)

        // ===== Step 1: contexts → fromContexts =====
        // 静态方法 type(of:) 取出 ContextProvider 子类型，调 inferredPermissions(for:)；
        // provider 实例本身不参与计算（只用 metatype），但仍需路由到注册表里的实例以拿到正确的子类型。
        var fromContexts: Set<Permission> = []
        for request in Self.extractContexts(from: tool) {
            guard let provider = providerRegistry.providers[request.provider] else {
                // 未注册 provider → 静态闭环无法继续，抛 .unknownProvider 让上层定位到 manifest 错误
                throw SliceError.toolPermission(.unknownProvider(id: request.provider))
            }
            // 通过 type(of:) 拿元类型，再调 protocol requirement 的静态方法
            let inferred = type(of: provider).inferredPermissions(for: request.args)
            fromContexts.formUnion(inferred)
        }

        // ===== Step 2: sideEffects → fromSideEffects =====
        // 直接调 SliceCore 已实现的 SideEffect.inferredPermissions（spec §3.3.4）
        var fromSideEffects: Set<Permission> = []
        for sideEffect in Self.extractSideEffects(from: tool) {
            fromSideEffects.formUnion(sideEffect.inferredPermissions)
        }

        // ===== Step 3: MCP refs → fromMCP =====
        // 同时收集 agent.mcpAllowlist / pipeline.step.mcp / sideEffect.callMCP 中的 MCPToolRef；
        // 注意：sideEffect.callMCP 已经在 Step 2 把 .mcp 累计到 fromSideEffects，这里再重复
        // 收一次到 fromMCP——按 D-24 设计 4 个 from* set 各自独立暴露，同一 permission 在
        // EffectivePermissions.union 里通过 Set.union 自然去重，不会双计影响 ⊆ 校验。
        var fromMCP: Set<Permission> = []
        for ref in Self.extractMCPRefs(from: tool) {
            fromMCP.insert(.mcp(server: ref.server, tools: [ref.tool]))
        }

        // ===== Step 4: agent.builtinCapabilities → fromBuiltins =====
        // mapBuiltin 用 tool.id 作为 .memoryAccess 的 scope（与 SideEffect.writeMemory 的 scope 同口径）
        var fromBuiltins: Set<Permission> = []
        for capability in Self.extractBuiltins(from: tool) {
            fromBuiltins.formUnion(Self.mapBuiltin(capability, scope: tool.id))
        }

        // 中文调试日志：聚合摘要——便于在 ExecutionEngine 日志里追排"哪类来源贡献了什么权限"
        // KISS：使用 count 维度避免泄漏具体权限项
        return EffectivePermissions(
            declared: declared,
            fromContexts: fromContexts,
            fromSideEffects: fromSideEffects,
            fromMCP: fromMCP,
            fromBuiltins: fromBuiltins
        )
    }

    // MARK: - Private helpers (extract from tool.kind)

    /// 聚合 tool 中所有 ContextRequest——含 PromptTool / AgentTool 直接的 contexts，
    /// 以及 PipelineStep.prompt(inline:) 中嵌套的 contexts
    private static func extractContexts(from tool: Tool) -> [ContextRequest] {
        switch tool.kind {
        case .prompt(let p):
            return p.contexts
        case .agent(let a):
            return a.contexts
        case .pipeline(let pipeline):
            // 仅 .prompt(inline:) step 的 inline.contexts 参与；其他 step 类型（tool / mcp / transform / branch）
            // 没有直接的 ContextRequest，这是 spec §3.4 Step 3 的设计——pipeline 不嵌套 contexts 字段
            var collected: [ContextRequest] = []
            for step in pipeline.steps {
                if case .prompt(let inline, _) = step {
                    collected.append(contentsOf: inline.contexts)
                }
            }
            return collected
        }
    }

    /// 聚合 tool 中所有 SideEffect——目前只来自 outputBinding.sideEffects
    /// （spec §3.3.4：sideEffects 是 outputBinding 的子字段，不在 kind 内）
    private static func extractSideEffects(from tool: Tool) -> [SideEffect] {
        tool.outputBinding?.sideEffects ?? []
    }

    /// 聚合 tool 中所有 MCPToolRef——含 agent.mcpAllowlist / pipeline.step.mcp / sideEffect.callMCP
    private static func extractMCPRefs(from tool: Tool) -> [MCPToolRef] {
        var collected: [MCPToolRef] = []

        // 1) agent.mcpAllowlist：Agent 工具显式允许的 MCP tool 列表
        if case .agent(let a) = tool.kind {
            collected.append(contentsOf: a.mcpAllowlist)
        }

        // 2) pipeline.step.mcp：Pipeline 中 .mcp(ref:) step
        if case .pipeline(let pipeline) = tool.kind {
            for step in pipeline.steps {
                if case .mcp(let ref, _) = step {
                    collected.append(ref)
                }
            }
        }

        // 3) sideEffect.callMCP：outputBinding 中 .callMCP(ref:) 副作用
        for sideEffect in extractSideEffects(from: tool) {
            if case .callMCP(let ref, _) = sideEffect {
                collected.append(ref)
            }
        }

        return collected
    }

    /// 聚合 tool 中所有 BuiltinCapability——仅 AgentTool 暴露此字段
    private static func extractBuiltins(from tool: Tool) -> [BuiltinCapability] {
        if case .agent(let a) = tool.kind {
            return a.builtinCapabilities
        }
        return []
    }

    /// `BuiltinCapability` → `Permission` 静态映射
    ///
    /// **设计决策（M2 安全姿态；M3+ 加细粒度 manifest 后下放精度）**：
    /// - `.filesystem` → `.fileRead("**")` + `.fileWrite("**")`：通用文件 IO，全开通配
    /// - `.shell`      → `.shellExec(commands: [])`：空 commands = 全开（最保守）；M3+ 加白名单
    /// - `.vision`     → `.screen`：vision 分析当前主要走截屏（spec §3.3.3 / §3.4 暗示）
    /// - `.tts`        → `.systemAudio`：与 `SideEffect.tts` 同口径
    /// - `.memory`     → `.memoryAccess(scope: tool.id)`：scope 用 tool 自身 id，与
    ///                  `SideEffect.writeMemory(tool:)` 一致
    /// - `.screen`     → `.screen`：直接对应
    ///
    /// - Parameters:
    ///   - capability: 待映射的内置能力
    ///   - scope: `.memoryAccess(scope:)` 的 scope 字段，调用方传入 tool.id
    /// - Returns: 映射后的 Permission 列表（可能 1 - 2 条）
    private static func mapBuiltin(_ capability: BuiltinCapability, scope: String) -> [Permission] {
        switch capability {
        case .filesystem:
            // 通配符 "**" 与 Permission.swift 注释中"~/Documents/**/*.md"格式同口径，PathSandbox 规范化
            return [.fileRead(path: "**"), .fileWrite(path: "**")]
        case .shell:
            // commands=[] 表示全开；M3+ 改成显式白名单后这里同步收紧
            return [.shellExec(commands: [])]
        case .vision:
            return [.screen]
        case .tts:
            return [.systemAudio]
        case .memory:
            return [.memoryAccess(scope: scope)]
        case .screen:
            return [.screen]
        }
    }
}

// MARK: - Permission coverage

/// 文件权限路径规范化协议，隔离 Permission coverage 与具体 PathSandbox 实现。
protocol FilePermissionNormalizing: Sendable {
    /// 规范化文件权限路径，用于 exact / prefix / glob 覆盖比较。
    ///
    /// - Parameter raw: 权限声明或 effective permission 中的原始路径。
    /// - Returns: 展开 `~`、解析 symlink、消除 `..` 后的路径；无效输入返回 `nil`。
    func normalizeFilePermissionPath(_ raw: String) -> String?

    /// 判断文件权限路径是否命中 PathSandbox hard-deny。
    ///
    /// - Parameter raw: 权限声明或 effective permission 中的原始路径。
    /// - Returns: hard-deny 命中时返回 `true`。
    func isHardDeniedFilePermissionPath(_ raw: String) -> Bool
}

/// 默认文件权限 normalizer：仅做路径标准化和 hard-deny 判断，不引入 allowlist 语义。
struct DefaultFilePermissionNormalizer: FilePermissionNormalizing {
    /// 共享默认实例，避免每次 undeclared 计算重复构造依赖。
    static let `default` = DefaultFilePermissionNormalizer()

    private let sandbox = PathSandbox()

    /// 规范化文件权限路径。
    ///
    /// - Parameter raw: 权限声明或 effective permission 中的原始路径。
    /// - Returns: 展开 `~`、解析 symlink、消除 `..` 后的路径；无效输入返回 `nil`。
    func normalizeFilePermissionPath(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let expanded = (trimmed as NSString).expandingTildeInPath
        if expanded.contains("*"), !expanded.hasPrefix("/") {
            // 内置 filesystem 能力用 "**" 表达全局 glob；它不是可解析的绝对路径，
            // 但仍可作为 pattern 参与匹配，hard-deny 由 effective path 单独兜底。
            return expanded
        }
        guard expanded.hasPrefix("/") else { return nil }

        return URL(fileURLWithPath: expanded)
            .resolvingSymlinksInPath()
            .standardizedFileURL
            .path
    }

    /// 判断文件权限路径是否命中 PathSandbox hard-deny。
    ///
    /// - Parameter raw: 权限声明或 effective permission 中的原始路径。
    /// - Returns: hard-deny 命中时返回 `true`。
    func isHardDeniedFilePermissionPath(_ raw: String) -> Bool {
        sandbox.isHardDenied(raw)
    }
}

extension Permission {
    /// 判断当前 declared permission 是否覆盖传入的 effective permission。
    ///
    /// 覆盖规则：
    /// - 标量 case 仅同 case 且关联值相等才覆盖；
    /// - 文件权限在 hard-deny 拦截后，支持 exact、目录前缀和 `*` / `**` glob；
    /// - MCP 要求 server 相同，declared tools 为 nil 或 declared tools 为 effective tools 超集；
    /// - shellExec 必须命令数组完全一致，空数组不代表全部命令。
    ///
    /// - Parameters:
    ///   - effective: 实际推导出的 effective permission。
    ///   - fileNormalizer: 文件路径 normalizer。
    /// - Returns: 能覆盖返回 `true`，否则返回 `false`。
    func covers(_ effective: Permission, fileNormalizer: any FilePermissionNormalizing) -> Bool {
        switch (self, effective) {
        case (.network(let declaredHost), .network(let effectiveHost)):
            return declaredHost == effectiveHost
        case (.fileRead(let declaredPath), .fileRead(let effectivePath)):
            return Self.coversFilePath(declaredPath, effectivePath, fileNormalizer: fileNormalizer)
        case (.fileWrite(let declaredPath), .fileWrite(let effectivePath)):
            return Self.coversFilePath(declaredPath, effectivePath, fileNormalizer: fileNormalizer)
        case (.clipboard, .clipboard),
             (.clipboardHistory, .clipboardHistory),
             (.screen, .screen),
             (.systemAudio, .systemAudio):
            return true
        case (.shellExec(let declaredCommands), .shellExec(let effectiveCommands)):
            return declaredCommands == effectiveCommands
        case (.mcp(let declaredServer, let declaredTools), .mcp(let effectiveServer, let effectiveTools)):
            return Self.coversMCP(
                declaredServer: declaredServer,
                declaredTools: declaredTools,
                effectiveServer: effectiveServer,
                effectiveTools: effectiveTools
            )
        case (.memoryAccess(let declaredScope), .memoryAccess(let effectiveScope)):
            return declaredScope == effectiveScope
        case (.appIntents(let declaredBundleId), .appIntents(let effectiveBundleId)):
            return declaredBundleId == effectiveBundleId
        case (.network, _),
             (.fileRead, _),
             (.fileWrite, _),
             (.clipboard, _),
             (.clipboardHistory, _),
             (.shellExec, _),
             (.mcp, _),
             (.screen, _),
             (.systemAudio, _),
             (.memoryAccess, _),
             (.appIntents, _):
            return false
        }
    }

    /// 判断 declared 文件路径是否覆盖 effective 文件路径。
    ///
    /// - Parameters:
    ///   - declaredPath: Tool 静态声明的路径。
    ///   - effectivePath: 实际推导出的路径。
    ///   - fileNormalizer: 文件路径 normalizer。
    /// - Returns: 覆盖返回 `true`。
    private static func coversFilePath(
        _ declaredPath: String,
        _ effectivePath: String,
        fileNormalizer: any FilePermissionNormalizing
    ) -> Bool {
        // hard-deny 路径必须在 coverage 前失败，避免“声明敏感路径”绕过执行前阻断。
        guard !fileNormalizer.isHardDeniedFilePermissionPath(declaredPath),
              !fileNormalizer.isHardDeniedFilePermissionPath(effectivePath),
              let normalizedDeclared = fileNormalizer.normalizeFilePermissionPath(declaredPath),
              let normalizedEffective = fileNormalizer.normalizeFilePermissionPath(effectivePath)
        else {
            return false
        }

        if normalizedDeclared == normalizedEffective {
            return true
        }

        if isDeclaredDirectoryPrefix(declaredPath),
           normalizedEffective.hasPrefix(pathPrefixForDirectory(normalizedDeclared)) {
            return true
        }

        if containsGlob(declaredPath) {
            return glob(pattern: normalizedDeclared, matches: normalizedEffective)
        }

        return false
    }

    /// 判断 declared MCP 权限是否覆盖 effective MCP 权限。
    ///
    /// - Parameters:
    ///   - declaredServer: 声明的 MCP server id。
    ///   - declaredTools: 声明的 tools；`nil` 表示同 server 全部 tool。
    ///   - effectiveServer: effective MCP server id。
    ///   - effectiveTools: effective tools。
    /// - Returns: 覆盖返回 `true`。
    private static func coversMCP(
        declaredServer: String,
        declaredTools: [String]?,
        effectiveServer: String,
        effectiveTools: [String]?
    ) -> Bool {
        guard declaredServer == effectiveServer else { return false }
        guard let declaredTools else { return true }
        guard let effectiveTools else { return false }
        return Set(declaredTools).isSuperset(of: Set(effectiveTools))
    }

    /// 判断原始声明是否显式表达目录前缀。
    ///
    /// - Parameter raw: Tool 静态声明路径。
    /// - Returns: 以 `/` 结尾且不含 glob 时返回 `true`。
    private static func isDeclaredDirectoryPrefix(_ raw: String) -> Bool {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.hasSuffix("/") && !containsGlob(trimmed)
    }

    /// 把规范化目录路径转换为安全前缀。
    ///
    /// - Parameter path: 已规范化目录路径。
    /// - Returns: 保证以 `/` 结尾的目录前缀。
    private static func pathPrefixForDirectory(_ path: String) -> String {
        path.hasSuffix("/") ? path : path + "/"
    }

    /// 判断路径声明是否含 glob 通配符。
    ///
    /// - Parameter raw: Tool 静态声明路径。
    /// - Returns: 含 `*` 返回 `true`。
    private static func containsGlob(_ raw: String) -> Bool {
        raw.contains("*")
    }

    /// 使用最小 glob 语义匹配路径。
    ///
    /// - Parameters:
    ///   - pattern: 已规范化的 declared glob pattern。
    ///   - path: 已规范化的 effective path。
    /// - Returns: glob 匹配返回 `true`。
    private static func glob(pattern: String, matches path: String) -> Bool {
        let regex = "^" + globPatternToRegex(pattern) + "$"
        return path.range(of: regex, options: .regularExpression) != nil
    }

    /// 将 `*` / `**` glob pattern 转换为正则表达式。
    ///
    /// - Parameter pattern: 已规范化的 glob pattern。
    /// - Returns: 可用于整串匹配的正则片段。
    private static func globPatternToRegex(_ pattern: String) -> String {
        let characters = Array(pattern)
        var index = 0
        var regex = ""

        while index < characters.count {
            let character = characters[index]
            if character == "*" {
                let nextIndex = index + 1
                if nextIndex < characters.count, characters[nextIndex] == "*" {
                    let slashIndex = index + 2
                    if slashIndex < characters.count, characters[slashIndex] == "/" {
                        // `**/` 覆盖零个或多个目录层级。
                        regex += "(?:.*/)?"
                        index += 3
                    } else {
                        regex += ".*"
                        index += 2
                    }
                } else {
                    regex += "[^/]*"
                    index += 1
                }
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(character))
                index += 1
            }
        }

        return regex
    }
}
