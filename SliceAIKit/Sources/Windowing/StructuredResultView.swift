import DesignSystem
import SwiftUI

/// structured DisplayMode 的字段列表视图。
public struct StructuredResultView: View {
    /// 要展示的结构化字段。
    private let fields: [StructuredField]

    /// 构造结构化结果视图。
    ///
    /// - Parameter fields: 已解析并排序的结构化字段。
    public init(fields: [StructuredField]) {
        self.fields = fields
    }

    /// 渲染结构化字段列表。
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(fields) { field in
                    StructuredFieldRow(field: field)
                    if field.id != fields.last?.id {
                        Divider()
                            .background(SliceColor.divider)
                    }
                }
            }
            .padding(.horizontal, SliceSpacing.xl)
            .padding(.vertical, SliceSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// structured 字段行。
private struct StructuredFieldRow: View {
    /// 当前字段。
    let field: StructuredField

    /// 渲染字段名和值。
    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.sm) {
            Text(field.key)
                .font(SliceFont.captionEmphasis)
                .foregroundColor(SliceColor.textSecondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Text(StructuredValueFormatter.string(from: field.value))
                .font(.system(size: 13, weight: .regular, design: .monospaced))
                .foregroundColor(SliceColor.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, SliceSpacing.md)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(field.key): \(StructuredValueFormatter.string(from: field.value))")
    }
}

/// 将 `StructuredValue` 转成紧凑、稳定的展示文本。
private enum StructuredValueFormatter {

    /// 格式化结构化值。
    static func string(from value: StructuredValue) -> String {
        switch value {
        case .string(let string):
            return string
        case .number(let number):
            return numberString(number)
        case .bool(let value):
            return value ? "true" : "false"
        case .array(let values):
            return "[\(values.map(string(from:)).joined(separator: ", "))]"
        case .object(let fields):
            return objectString(fields)
        case .null:
            return "null"
        }
    }

    /// 格式化 JSON object 字段。
    private static func objectString(_ fields: [StructuredField]) -> String {
        guard !fields.isEmpty else { return "{}" }
        let body = fields
            .map { "\($0.key): \(string(from: $0.value))" }
            .joined(separator: "\n")
        return "{\n\(body)\n}"
    }

    /// 格式化数字，避免整数显示为 `1.0`。
    private static func numberString(_ number: Double) -> String {
        if number.rounded() == number {
            return String(Int(number))
        }
        return String(number)
    }
}
