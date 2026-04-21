import SwiftUI

/// 胶囊按钮：primary / secondary / danger 三风格
public struct PillButton: View {
    public enum Style { case primary, secondary, danger }

    let title: String
    let icon: String?
    let style: Style
    let action: () -> Void

    public init(_ title: String, icon: String? = nil,
                style: Style = .secondary, action: @escaping () -> Void) {
        self.title = title
        self.icon = icon
        self.style = style
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: SliceSpacing.sm) {
                if let icon { Image(systemName: icon).font(.system(size: 11, weight: .medium)) }
                Text(title).font(.system(size: 11.5, weight: .medium))
            }
            .padding(.horizontal, SliceSpacing.lg)
            .padding(.vertical, SliceSpacing.sm)
            .foregroundColor(foreground)
            .background(RoundedRectangle(cornerRadius: SliceRadius.button).fill(background))
        }
        .pressScale()
        .buttonStyle(.plain)
    }

    private var foreground: Color {
        switch style {
        case .primary, .danger: return .white
        case .secondary:        return SliceColor.textPrimary
        }
    }
    private var background: Color {
        switch style {
        case .primary:   return SliceColor.accent
        case .secondary: return SliceColor.hoverFill
        case .danger:    return SliceColor.error
        }
    }
}
