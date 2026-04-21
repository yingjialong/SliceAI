import SwiftUI

/// 通用图标按钮；支持 small (22×22) / regular (30×30) 两档
public struct IconButton: View {
    public enum Size {
        case small, regular
        var dimension: CGFloat { self == .small ? 22 : 30 }
        var iconSize: CGFloat { self == .small ? 12 : 15 }
    }

    let systemName: String?
    let text: String?
    let size: Size
    let isActive: Bool
    let help: String?
    let action: () -> Void

    public init(systemName: String? = nil, text: String? = nil,
                size: Size = .small, isActive: Bool = false,
                help: String? = nil, action: @escaping () -> Void) {
        self.systemName = systemName
        self.text = text
        self.size = size
        self.isActive = isActive
        self.help = help
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Group {
                if let systemName {
                    Image(systemName: systemName)
                        .font(.system(size: size.iconSize, weight: .medium))
                } else if let text {
                    Text(text).font(.system(size: size.iconSize))
                }
            }
            .foregroundColor(isActive ? SliceColor.accent : SliceColor.textSecondary)
            .frame(width: size.dimension, height: size.dimension)
            .hoverHighlight(cornerRadius: SliceRadius.button)
        }
        .pressScale()
        .help(help ?? "")
    }
}
