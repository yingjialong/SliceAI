import SwiftUI

/// 结果面板错误展示块
///
/// 展示结构：
/// - 左侧：红色圆形感叹号图标（16pt）
/// - 右侧：标题（红色）+ 描述文本 + 可折叠详情区域
/// - 底部：可选"重试"和"打开设置"按钮（`PillButton`）
///
/// 可折叠详情：点击"查看详情"展开 monospace 代码块，支持文本选择（复制堆栈 / 错误码）。
///
/// 使用示例：
/// ```swift
/// ErrorBlock(
///     title: "请求失败",
///     message: "无法连接到服务器，请检查网络",
///     detail: "URLError: -1001",
///     onRetry: { viewModel.retry() },
///     onOpenSettings: { openSettings() }
/// )
/// ```
public struct ErrorBlock: View {

    // MARK: - Properties

    /// 错误标题（红色加粗，简明描述问题类型）
    let title: String

    /// 错误描述（灰色正文，友好的用户可读文案）
    let message: String

    /// 可折叠技术详情（可选，展示后支持文本选择）
    let detail: String?

    /// 重试回调（nil 时不渲染重试按钮）
    /// @Sendable 确保 Swift 6 strict concurrency 下跨 actor 安全传递
    let onRetry: (@Sendable () -> Void)?

    /// 打开设置回调（nil 时不渲染打开设置按钮）
    /// @Sendable 同上
    let onOpenSettings: (@Sendable () -> Void)?

    // MARK: - State

    /// 控制详情区域展开 / 收起
    @State private var showDetail: Bool = false

    // MARK: - Init

    public init(
        title: String,
        message: String,
        detail: String? = nil,
        onRetry: (@Sendable () -> Void)? = nil,
        onOpenSettings: (@Sendable () -> Void)? = nil
    ) {
        self.title = title
        self.message = message
        self.detail = detail
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }

    // MARK: - Body

    public var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.base) {
            // 主内容行：图标 + 文字区域
            HStack(alignment: .top, spacing: SliceSpacing.lg) {
                // 红色圆形感叹号图标
                errorIcon

                // 标题 + 描述 + 可折叠详情
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(SliceFont.bodyEmphasis)
                        .foregroundColor(SliceColor.error)

                    Text(message)
                        .font(SliceFont.callout)
                        .foregroundColor(SliceColor.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)

                    // 可折叠详情区域（仅 detail 非空时渲染）
                    if let detail, !detail.isEmpty {
                        detailSection(detail: detail)
                    }
                }
            }

            // 操作按钮行（仅当至少有一个回调时渲染）
            if onRetry != nil || onOpenSettings != nil {
                HStack(spacing: SliceSpacing.md) {
                    if let onRetry {
                        PillButton("重试", icon: "arrow.clockwise", style: .danger, action: onRetry)
                    }
                    if let onOpenSettings {
                        PillButton("打开设置", icon: "gearshape", style: .secondary, action: onOpenSettings)
                    }
                }
            }
        }
        .padding(SliceSpacing.xl)
        .background(
            RoundedRectangle(cornerRadius: SliceRadius.control)
                .fill(SliceColor.errorFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SliceRadius.control)
                .stroke(SliceColor.errorBorder, lineWidth: 0.5)
        )
    }

    // MARK: - Private Views

    /// 红色圆形感叹号图标（16×16pt）
    private var errorIcon: some View {
        ZStack {
            Circle().fill(SliceColor.error)
            Image(systemName: "exclamationmark")
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(.white)
        }
        .frame(width: 16, height: 16)
        // 顶部对齐 1pt 偏移，与标题文字基线对齐
        .padding(.top, 1)
    }

    /// 可折叠详情区域：展开/收起按钮 + 详情代码块
    @ViewBuilder
    private func detailSection(detail: String) -> some View {
        // 展开/收起切换按钮
        Button {
            // 切换详情展开状态
            showDetail.toggle()
        } label: {
            HStack(spacing: 2) {
                Image(systemName: showDetail ? "chevron.down" : "chevron.right")
                    .font(.system(size: 9))
                Text("查看详情")
                    .font(SliceFont.caption)
            }
            .foregroundColor(SliceColor.textTertiary)
        }
        .buttonStyle(.plain)

        // 展开时显示 monospace 详情块，支持用户文本选择
        if showDetail {
            Text(detail)
                .font(SliceFont.monoSmall)
                .foregroundColor(SliceColor.textSecondary)
                .padding(SliceSpacing.base)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: SliceRadius.tight)
                        .fill(SliceColor.hoverFill)
                )
                // 允许用户选中复制错误详情（如 URLError code、HTTP 状态码）
                .textSelection(.enabled)
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("ErrorBlock · full") {
    ErrorBlock(
        title: "请求失败",
        message: "API Key 无效或已过期，请前往设置页重新填写。",
        detail: "HTTP 401 Unauthorized\nWWW-Authenticate: Bearer error=\"invalid_token\"",
        onRetry: { print("重试") },
        onOpenSettings: { print("打开设置") }
    )
    .frame(width: 360)
    .padding()
}

#Preview("ErrorBlock · no detail, no buttons") {
    ErrorBlock(
        title: "选取失败",
        message: "未能获取选中文本，请重新划词后再试。"
    )
    .frame(width: 360)
    .padding()
}

#Preview("ErrorBlock · detail only") {
    ErrorBlock(
        title: "网络超时",
        message: "请求超时，请检查网络后重试。",
        detail: "URLError(-1001): The request timed out."
    )
    .frame(width: 360)
    .padding()
}
#endif
