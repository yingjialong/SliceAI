import Foundation

/// structured 结果中的单个字段。
public struct StructuredField: Sendable, Equatable, Identifiable {
    /// 字段稳定标识；当前使用 key，满足 `ForEach` 渲染需求。
    public var id: String { key }
    /// JSON object 中的字段名。
    public let key: String
    /// 字段对应的结构化值。
    public let value: StructuredValue

    /// 构造结构化字段。
    public init(key: String, value: StructuredValue) {
        self.key = key
        self.value = value
    }
}

/// structured 结果支持的 JSON 值类型。
public indirect enum StructuredValue: Sendable, Equatable {
    /// 字符串值。
    case string(String)
    /// 数字值。
    case number(Double)
    /// 布尔值。
    case bool(Bool)
    /// 数组值。
    case array([StructuredValue])
    /// 对象值。
    case object([StructuredField])
    /// JSON null。
    case null
}

/// structured 结果解析错误。
public enum StructuredResultParseError: Error, Sendable, Equatable {
    /// 输入不是合法 JSON。
    case invalidJSON
    /// 顶层 JSON 不是 object，无法渲染为字段列表。
    case topLevelNotObject
    /// JSONSerialization 返回了当前 UI 不支持的值。
    case unsupportedValue
}

/// structured final text 的 JSON 解析器。
public enum StructuredResultParser {

    /// 解析顶层 JSON object，并按字段名排序返回稳定字段列表。
    ///
    /// - Parameter text: LLM 返回的完整 final text。
    /// - Returns: 可供 `StructuredResultView` 渲染的字段列表。
    /// - Throws: `StructuredResultParseError`，避免把 Foundation 原始异常泄露到 UI。
    public static func parseObject(from text: String) throws -> [StructuredField] {
        guard let data = text.data(using: .utf8) else {
            throw StructuredResultParseError.invalidJSON
        }
        let object: Any
        do {
            object = try JSONSerialization.jsonObject(with: data, options: [])
        } catch {
            throw StructuredResultParseError.invalidJSON
        }
        guard let dictionary = object as? [String: Any] else {
            throw StructuredResultParseError.topLevelNotObject
        }
        return try parseObject(dictionary)
    }

    /// 解析 JSON object，并按 key 排序以保证测试和 UI 渲染稳定。
    private static func parseObject(_ dictionary: [String: Any]) throws -> [StructuredField] {
        try dictionary.keys.sorted().map { key in
            guard let rawValue = dictionary[key] else {
                throw StructuredResultParseError.unsupportedValue
            }
            return StructuredField(key: key, value: try parseValue(rawValue))
        }
    }

    /// 递归解析 JSONSerialization 返回的 Foundation 值。
    private static func parseValue(_ rawValue: Any) throws -> StructuredValue {
        if rawValue is NSNull {
            return .null
        }
        if let string = rawValue as? String {
            return .string(string)
        }
        if let number = rawValue as? NSNumber {
            // JSONSerialization 会把 Bool 桥接为 NSNumber，必须先按 CFBoolean 识别。
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        }
        if let array = rawValue as? [Any] {
            return .array(try array.map(parseValue))
        }
        if let object = rawValue as? [String: Any] {
            return .object(try parseObject(object))
        }
        throw StructuredResultParseError.unsupportedValue
    }
}

/// bubble 面板的纯展示状态。
public struct BubblePresentationState: Sendable, Equatable {
    /// 当前是否可见。
    public private(set) var isVisible: Bool
    /// 当前展示文本；由 output finish 阶段写入完整 final text。
    public private(set) var text: String
    /// 自动隐藏的目标时间；nil 表示尚未进入完成倒计时。
    public private(set) var dismissAt: Date?

    /// 构造默认隐藏状态。
    public init(isVisible: Bool = false, text: String = "", dismissAt: Date? = nil) {
        self.isVisible = isVisible
        self.text = text
        self.dismissAt = dismissAt
    }

    /// 展示 bubble，并清除上一次自动隐藏时间。
    ///
    /// - Parameters:
    ///   - text: 要展示的完整 final text。
    ///   - now: 当前时间；保留入参便于测试确定性。
    public mutating func show(text: String, now: Date = Date()) {
        _ = now
        self.text = text
        isVisible = true
        dismissAt = nil
    }

    /// 标记输出完成，并设置自动隐藏时间。
    ///
    /// - Parameters:
    ///   - now: 完成时刻。
    ///   - autoDismissDelay: 完成后延迟隐藏的秒数。
    public mutating func finish(now: Date = Date(), autoDismissDelay: TimeInterval) {
        dismissAt = now.addingTimeInterval(autoDismissDelay)
    }

    /// 根据当前时间更新可见状态。
    ///
    /// - Parameter now: 当前时间。
    public mutating func update(now: Date = Date()) {
        guard let dismissAt, now >= dismissAt else { return }
        isVisible = false
    }
}
