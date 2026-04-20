import Foundation

/// 应用级统一错误，每类都有 userMessage（给用户看）与 developerContext（日志）
public enum SliceError: Error, Sendable, Equatable {
    case selection(SelectionError)
    case provider(ProviderError)
    case configuration(ConfigurationError)
    case permission(PermissionError)

    /// 面向最终用户的友好错误文案
    public var userMessage: String {
        switch self {
        case .selection(let e): return e.userMessage
        case .provider(let e): return e.userMessage
        case .configuration(let e): return e.userMessage
        case .permission(let e): return e.userMessage
        }
    }

    /// 用于日志打印的开发者上下文，不含敏感信息
    public var developerContext: String {
        switch self {
        case .selection(let e): return "selection.\(e)"
        case .provider(let e): return "provider.\(e)"
        case .configuration(let e): return "configuration.\(e)"
        case .permission(let e): return "permission.\(e)"
        }
    }
}

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
            if let t { return "请求过于频繁，请 \(Int(t)) 秒后重试。" }
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

public enum ConfigurationError: Error, Sendable, Equatable {
    case fileNotFound
    case schemaVersionTooNew(Int)
    case invalidJSON(String)
    case referencedProviderMissing(String)

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
        }
    }
}

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
