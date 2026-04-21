import SwiftUI

/// 小标签：neutral / accent / success / warning 四风格
public struct Chip: View {
    public enum Style { case neutral, accent, success, warning }

    let text: String
    let style: Style

    public init(_ text: String, style: Style = .neutral) {
        self.text = text
        self.style = style
    }

    public var body: some View {
        Text(text)
            .font(SliceFont.micro)
            .padding(.horizontal, 7)
            .padding(.vertical, SliceSpacing.xs)
            .foregroundColor(foreground)
            .background(RoundedRectangle(cornerRadius: SliceRadius.button).fill(background))
    }

    private var foreground: Color {
        switch style {
        case .neutral:  return SliceColor.textSecondary
        case .accent:   return SliceColor.accentText
        case .success:  return SliceColor.success
        case .warning:  return SliceColor.warning
        }
    }
    private var background: Color {
        switch style {
        case .neutral:  return SliceColor.hoverFill
        case .accent:   return SliceColor.accentFillLight
        case .success:  return SliceColor.success.opacity(0.15)
        case .warning:  return SliceColor.warningFill
        }
    }
}
