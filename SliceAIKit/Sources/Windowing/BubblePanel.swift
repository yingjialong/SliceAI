import AppKit
import DesignSystem
import OSLog
import SwiftUI

/// final text 气泡面板，供 `.bubble` DisplayMode 使用。
@MainActor
public final class BubblePanel {

    /// 承载内容的非激活面板。
    private var panel: NSPanel?
    /// SwiftUI 内容状态。
    private let viewModel = BubblePanelViewModel()
    /// 纯展示状态，便于保持 auto-dismiss 行为可测试。
    private var state = BubblePresentationState()
    /// 屏幕边界定位器。
    private let positioner = ScreenAwarePositioner()
    /// 当前自动隐藏任务。
    private var autoDismissTask: Task<Void, Never>?
    /// 诊断日志；只记录长度，不记录文本。
    private let logger = Logger(subsystem: "com.sliceai.app", category: "BubblePanel")

    /// 无状态构造器。
    public init() {}

    /// 展示完整 final text，并在延迟后自动隐藏。
    ///
    /// - Parameters:
    ///   - text: LLM 完整最终输出。
    ///   - anchor: 触发时的屏幕坐标。
    ///   - autoDismissDelay: 完成后自动隐藏的秒数。
    public func show(
        text: String,
        anchor: CGPoint,
        autoDismissDelay: TimeInterval = 4
    ) {
        autoDismissTask?.cancel()
        let now = Date()
        state.show(text: text, now: now)
        state.finish(now: now, autoDismissDelay: autoDismissDelay)
        viewModel.text = state.text

        let size = panel?.frame.size ?? CGSize(width: 360, height: 132)
        let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.contains(anchor)
        })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero
        let origin = positioner.position(anchor: anchor, size: size, screen: screen, offset: 12)

        if panel == nil {
            panel = makePanel(size: size, origin: origin)
        } else {
            panel?.setFrameOrigin(origin)
        }

        logger.debug("bubble show length=\(text.count, privacy: .public)")
        panel?.orderFrontRegardless()
        scheduleAutoDismiss(delay: autoDismissDelay)
    }

    /// 主动隐藏气泡。
    public func hide() {
        autoDismissTask?.cancel()
        state.update(now: Date.distantFuture)
        panel?.orderOut(nil)
    }

    /// 创建气泡 NSPanel。
    private func makePanel(size: CGSize, origin: CGPoint) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.isReleasedWhenClosed = false

        let hosting = NSHostingView(rootView: BubbleContentView(viewModel: viewModel))
        hosting.frame = NSRect(origin: .zero, size: size)
        hosting.autoresizingMask = [.width, .height]
        panel.contentView = hosting
        return panel
    }

    /// 安排自动隐藏任务。
    private func scheduleAutoDismiss(delay: TimeInterval) {
        let nanoseconds = UInt64(max(delay, 0) * 1_000_000_000)
        autoDismissTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard let self else { return }
            state.update(now: Date())
            if !state.isVisible {
                logger.debug("bubble auto dismissed")
                panel?.orderOut(nil)
            }
        }
    }
}

/// 气泡内容状态。
@MainActor
private final class BubblePanelViewModel: ObservableObject {
    /// 当前气泡文本。
    @Published var text: String = ""
}

/// 气泡内容视图。
private struct BubbleContentView: View {
    /// 气泡视图模型。
    @ObservedObject var viewModel: BubblePanelViewModel

    /// 渲染气泡正文。
    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.sm) {
            Text(viewModel.text)
                .font(SliceFont.body)
                .foregroundColor(SliceColor.textPrimary)
                .lineLimit(6)
                .truncationMode(.tail)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, SliceSpacing.xl)
        .padding(.vertical, SliceSpacing.lg)
        .glassBackground(.hud, cornerRadius: SliceRadius.card)
        .overlay(
            RoundedRectangle(cornerRadius: SliceRadius.card)
                .stroke(SliceColor.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: SliceRadius.card))
    }
}
