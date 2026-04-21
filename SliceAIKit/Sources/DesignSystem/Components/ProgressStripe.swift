import SwiftUI

/// 流式进度条（indeterminate），1.5pt 高紫色渐变条在顶部持续向右滑动
///
/// 动画：accent 渐变色光条在容器宽度范围内无限循环平移（`SliceAnimation.progress`：1.4s linear 无限循环）。
/// 出现 / 消失通过 `opacity` transition 柔和过渡。
///
/// 使用方式：
/// ```swift
/// VStack(spacing: 0) {
///     if viewModel.isStreaming {
///         ProgressStripe()
///     }
///     contentView
/// }
/// ```
public struct ProgressStripe: View {
    /// 光条横向偏移比例，-1 为完全在左侧容器外，+1 为完全在右侧容器外
    @State private var offset: CGFloat = -1

    public init() {}

    public var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            // 渐变光条宽度为容器的 50%，产生短促高亮效果
            LinearGradient(
                colors: [.clear, SliceColor.accent, .clear],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(width: width * 0.5, height: 1.5)
            // offset 从 -1 动画到 1，实际移动距离为 width * 1.5
            // 使光条从左侧完全出框滑行到右侧完全出框
            .offset(x: offset * width * 1.5 + width * 0.5)
            .onAppear {
                // 触发无限循环动画（SliceAnimation.progress = 1.4s linear repeatForever）
                withAnimation(SliceAnimation.progress) {
                    offset = 1
                }
            }
        }
        .frame(height: 1.5)
        .clipped() // 裁剪溢出容器的光条部分，避免渗出到外部
        .transition(.opacity.animation(SliceAnimation.standard)) // 出现/消失用 180ms opacity 过渡
    }
}
