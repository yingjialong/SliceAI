import Foundation

/// 应用级统一错误，每类都有 userMessage（给用户看）与 developerContext（日志）
public enum SliceError: Error, Sendable, Equatable {
    case selection(SelectionError)
    case provider(ProviderError)
    case configuration(ConfigurationError)
    case permission(PermissionError)
    /// v2 上下文采集失败；细分语义见 `ContextError`
    case context(ContextError)
    /// v2 工具权限决策失败；细分语义见 `ToolPermissionError`
    case toolPermission(ToolPermissionError)
    /// 执行链非业务错误：not-implemented 边界 / 未分类异常 fallback
    case execution(ExecutionError)

    /// 面向最终用户的友好错误文案
    public var userMessage: String {
        switch self {
        case .selection(let e): return e.userMessage
        case .provider(let e): return e.userMessage
        case .configuration(let e): return e.userMessage
        case .permission(let e): return e.userMessage
        case .context(let e): return e.userMessage
        case .toolPermission(let e): return e.userMessage
        case .execution(let e): return e.userMessage
        }
    }

    /// 用于日志打印的开发者上下文
    /// 对携带任意字符串 payload 的 case 做脱敏，防止 API Key / 响应体 / JSON 原文流入日志
    public var developerContext: String {
        switch self {
        case .selection(let e):
            switch e {
            case .axUnavailable: return "selection.axUnavailable"
            case .axEmpty: return "selection.axEmpty"
            case .clipboardTimeout: return "selection.clipboardTimeout"
            case .textTooLong(let n): return "selection.textTooLong(\(n))"
            }
        case .provider(let e):
            switch e {
            case .unauthorized: return "provider.unauthorized"
            case .rateLimited(let t):
                let s = t.flatMap { $0.isFinite ? String(Int(max(0, $0.rounded(.up)))) : nil } ?? "nil"
                return "provider.rateLimited(\(s))"
            case .serverError(let code): return "provider.serverError(\(code))"
            case .networkTimeout: return "provider.networkTimeout"
            case .invalidResponse: return "provider.invalidResponse(<redacted>)"
            case .sseParseError: return "provider.sseParseError(<redacted>)"
            }
        case .configuration(let e):
            switch e {
            case .fileNotFound: return "configuration.fileNotFound"
            case .schemaVersionTooNew(let v): return "configuration.schemaVersionTooNew(\(v))"
            case .invalidJSON: return "configuration.invalidJSON(<redacted>)"
            case .referencedProviderMissing(let id): return "configuration.referencedProviderMissing(\(id))"
            // 脱敏规则：虽然 validationFailed 的 msg 由内部 validator 生成、不含用户自由文本（参见
            // Provider.validate / Tool.validate），但统一按"任意 String payload 一律 <redacted>"
            // 原则处理，避免未来扩展 validator 时误把 prompt / apiKey 等拼进 msg 导致日志泄漏。
            case .validationFailed: return "configuration.validationFailed(<redacted>)"
            // 脱敏规则：tool id / reason 都可能携带用户自由文本（自定义工具 id / validator 描述），
            // 一律 <redacted>，与 validationFailed 同口径。
            case .invalidTool: return "configuration.invalidTool(<redacted>)"
            }
        case .permission(let e):
            switch e {
            case .accessibilityDenied: return "permission.accessibilityDenied"
            case .inputMonitoringDenied: return "permission.inputMonitoringDenied"
            }
        // 脱敏规则：ContextKey.rawValue / ContextProvider id / underlying SliceError 都可能携带
        // 用户文件路径 / MCP server 名 / API 响应等敏感信息——按"任意 String payload 一律
        // <redacted>"原则统一脱敏，避免上下文采集失败的日志反向泄漏用户工作内容。
        case .context(let e):
            switch e {
            case .requiredFailed: return "context.requiredFailed(<redacted>)"
            case .providerNotFound: return "context.providerNotFound(<redacted>)"
            case .timeout: return "context.timeout(<redacted>)"
            }
        // 脱敏规则：所有 toolPermission 子 case 都可能携带敏感信息——
        // - missing 集合元素含 fileRead/fileWrite path（用户文件路径）/ mcp server 名 / appIntents bundleId
        // - denied/notGranted 同上 + reason 文案可能含外部错误信息
        // - unknownProvider id 可能是用户自定义工具的引用（如私有 MCP 名）
        // - sandboxViolation path 是用户文件路径
        // 一律 <redacted>，仅保留 .undeclared 的 count 作为日志可观测性数据。
        case .toolPermission(let e):
            switch e {
            case .undeclared(let missing): return "toolPermission.undeclared(count=\(missing.count))"
            case .denied: return "toolPermission.denied(<redacted>)"
            case .notGranted: return "toolPermission.notGranted"
            case .unknownProvider: return "toolPermission.unknownProvider(<redacted>)"
            case .sandboxViolation: return "toolPermission.sandboxViolation(<redacted>)"
            }
        // 脱敏规则：execution reason 可能来自未实现模式描述或外部 error.localizedDescription，
        // 统一不写入 developerContext，避免日志泄露用户配置、API 响应或密钥片段。
        case .execution(let e):
            switch e {
            case .notImplemented: return "execution.notImplemented(<redacted>)"
            case .unknown: return "execution.unknown(<redacted>)"
            }
        }
    }
}

/// 选中文字捕获环节的错误
public enum SelectionError: Error, Sendable, Equatable {
    case axUnavailable
    case axEmpty
    case clipboardTimeout
    case textTooLong(Int)

    public var userMessage: String {
        switch self {
        case .axUnavailable: return "SliceAI 需要辅助功能权限才能读取你选中的文字。"
        case .axEmpty: return "无法读取当前选中的文字，请确认已选中文本。"
        case .clipboardTimeout: return "读取选中文字超时，请再试一次。"
        case .textTooLong(let n): return "选中的文字过长（\(n) 字符），请缩短选区。"
        }
    }
}

/// LLM 供应商调用环节的错误
public enum ProviderError: Error, Sendable, Equatable {
    case unauthorized
    case rateLimited(retryAfter: TimeInterval?)
    case serverError(Int)
    case networkTimeout
    case invalidResponse(String)
    case sseParseError(String)

    public var userMessage: String {
        switch self {
        case .unauthorized:
            return "API Key 无效或未设置，请在设置中检查。"
        case .rateLimited(let t):
            if let t, t.isFinite, t > 0 {
                let secs = max(1, Int(t.rounded(.up)))
                return "请求过于频繁，请 \(secs) 秒后重试。"
            }
            return "请求过于频繁，请稍后重试。"
        case .serverError(let code):
            return "服务端返回错误（HTTP \(code)），请稍后重试或切换模型。"
        case .networkTimeout:
            return "网络请求超时，请检查连接。"
        case .invalidResponse:
            return "服务端响应异常，无法解析。"
        case .sseParseError:
            return "接收到的流式数据格式无法识别。"
        }
    }
}

/// 配置加载/校验环节的错误
public enum ConfigurationError: Error, Sendable, Equatable {
    case fileNotFound
    case schemaVersionTooNew(Int)
    case invalidJSON(String)
    case referencedProviderMissing(String)
    /// 配置落盘前的类型不变量校验失败（第八轮 P2 新增）
    ///
    /// 由 `Provider.validate()` / `Tool.validate()` 抛出，`ConfigurationStore.save()`
    /// 在写入磁盘前调用。msg 由 validator 生成，只包含 provider id / tool id / 字段名等"技术描述"——
    /// **不得**包含 prompt / API Key 等用户自由文本。
    case validationFailed(String)
    /// Tool manifest 配置错误（如引用未注册的 ContextProvider id / 不合法的 builtinCapability）
    ///
    /// 与 `validationFailed` 的区别：`validationFailed` 是结构性 / 字段级校验，
    /// `invalidTool` 是引用 / 关系级校验（manifest 自身合法但跨资源引用断链）。
    /// 由 `PermissionGraph.compute(tool:)` 等更晚阶段的处理器抛出。
    case invalidTool(id: String, reason: String)

    public var userMessage: String {
        switch self {
        case .fileNotFound:
            return "找不到配置文件，将使用默认配置。"
        case .schemaVersionTooNew(let v):
            return "配置文件的 schemaVersion=\(v) 高于当前应用支持版本，请升级 SliceAI。"
        case .invalidJSON:
            return "配置文件 JSON 格式不正确，请参考 config.schema.json 校验。"
        case .referencedProviderMissing(let id):
            return "工具引用的供应商 \"\(id)\" 不存在。"
        case .validationFailed(let msg):
            // validator 生成的 msg 原样带给用户，便于定位到具体 provider / tool 字段
            return "配置校验失败：\(msg)"
        case .invalidTool(let id, let reason):
            // tool id + reason 拼成可读文案，便于用户在 Settings 里定位到出错的工具
            return "工具 \"\(id)\" 配置错误：\(reason)"
        }
    }
}

/// 系统权限相关错误
public enum PermissionError: Error, Sendable, Equatable {
    case accessibilityDenied
    case inputMonitoringDenied

    public var userMessage: String {
        switch self {
        case .accessibilityDenied:
            return "辅助功能权限未授予，SliceAI 无法读取划词。"
        case .inputMonitoringDenied:
            return "输入监控权限未授予，快捷键可能无法工作。"
        }
    }
}

/// 执行链顶层错误（与 ExecutionEvent 的 notImplemented / catch-all unknown 对接）
public enum ExecutionError: Error, Sendable, Equatable {
    /// spec 设计期声明的 not-implemented 边界（如 v0.2 .skill / .agent）
    case notImplemented(String)
    /// 非 SliceError / 非 CancellationError 的 catch-all 兜底
    case unknown(String)

    /// 面向最终用户的友好错误文案。
    public var userMessage: String {
        switch self {
        case .notImplemented(let reason):
            // notImplemented 的 reason 由调用方提供，面向用户可读；开发日志仍统一脱敏。
            return "该能力在当前版本（v0.2）尚未实现：\(reason)。请等待后续版本。"
        case .unknown:
            // unknown 不回显外部错误描述，避免把 provider / 系统错误中的敏感内容
            // 展示给用户。
            return "执行过程中发生未知错误，请稍后重试或联系支持。"
        }
    }
}
