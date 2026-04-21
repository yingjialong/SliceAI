import SwiftUI

/// 圆角白卡分组容器，用于设置窗口内容区
public struct SectionCard<Content: View>: View {
    let title: String?
    @ViewBuilder let content: () -> Content

    public init(_ title: String? = nil, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let title {
                Text(title.uppercased())
                    .font(SliceFont.captionEmphasis)
                    .kerning(SliceKerning.wide)
                    .foregroundColor(SliceColor.textSecondary)
                    .padding(.bottom, SliceSpacing.base)
            }
            VStack(spacing: 0) { content() }
        }
        .padding(SliceSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SliceRadius.card)
                .fill(SliceColor.surface)
                .overlay(
                    RoundedRectangle(cornerRadius: SliceRadius.card)
                        .stroke(SliceColor.border, lineWidth: 0.5)
                )
        )
    }
}
