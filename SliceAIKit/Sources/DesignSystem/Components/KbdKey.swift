import SwiftUI

/// 键盘按键提示视觉
public struct KbdKey: View {
    let label: String

    public init(_ label: String) { self.label = label }

    public var body: some View {
        Text(label)
            .font(SliceFont.monoSmall)
            .padding(.horizontal, SliceSpacing.md)
            .padding(.vertical, SliceSpacing.xs)
            .foregroundColor(SliceColor.textSecondary)
            .background(RoundedRectangle(cornerRadius: SliceRadius.tight).fill(SliceColor.hoverFill))
    }
}
