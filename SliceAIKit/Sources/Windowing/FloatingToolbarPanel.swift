// SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift
import AppKit
import SwiftUI
import SliceCore

/// 划词后弹出的紧贴选区浮条（A 模式）
///
/// 职责：根据选区中心点 `anchor`，在屏幕合适位置展示一排工具图标；
/// 用户点击或 5 秒无交互后自动关闭。
/// 线程模型：整个类在主 actor 上运行，避免 `NSPanel` / `NSHostingView` 跨线程访问。
@MainActor
public final class FloatingToolbarPanel {

    /// 当前承载浮条的 NSPanel，dismiss 后置 nil
    private var panel: NSPanel?
    /// 屏幕边界感知的坐标计算器（无状态，可复用）
    private let positioner = ScreenAwarePositioner()
    /// 5 秒自动关闭任务，每次 show 都会取消旧任务重新计时
    private var autoDismissTask: Task<Void, Never>?

    /// 无状态构造器
    public init() {}

    /// 显示浮条
    /// - Parameters:
    ///   - tools: 要展示的工具列表（按顺序从左至右）
    ///   - anchor: 选区中心（屏幕坐标，左下原点）
    ///   - onPick: 用户点击某工具时回调
    public func show(tools: [Tool], anchor: CGPoint, onPick: @escaping (Tool) -> Void) {
        // 按工具数量动态计算宽度：按钮宽 + 4px 间距 + 两侧 padding；保证最低 120px 宽
        let width = CGFloat(tools.count) * (PanelStyle.toolbarButtonSize.width + 4)
            + PanelStyle.toolbarPadding * 2
        let height = PanelStyle.toolbarButtonSize.height + PanelStyle.toolbarPadding * 2
        let size = CGSize(width: max(width, 120), height: height)

        // 选锚点所在屏幕，fallback 到主屏；再 fallback 到零矩形避免 nil
        let screen = NSScreen.screens.first(where: {
            $0.visibleFrame.contains(anchor)
        })?.visibleFrame ?? NSScreen.main?.visibleFrame ?? .zero

        // 通过 positioner 计算 origin：默认锚点下方 8px，越界时翻到上方并水平夹紧
        let origin = positioner.position(anchor: anchor, size: size, screen: screen, offset: 8)

        // 构造 NSPanel 并以 SwiftUI 视图填充内容区
        let panel = makePanel(size: size, origin: origin)
        let hosting = NSHostingView(rootView: ToolbarContent(tools: tools, onPick: { [weak self] t in
            // 点击工具后先回调业务方，再关闭浮条，避免回调中再次读取已失效状态
            onPick(t)
            self?.dismiss()
        }))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        panel.orderFrontRegardless()
        self.panel = panel

        // 5 秒无交互自动消失：取消旧任务，启动新任务
        // 用 @MainActor Task 直接调用 dismiss()，避免嵌套 MainActor.run（Swift 6 严格并发推荐写法）
        autoDismissTask?.cancel()
        autoDismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled else { return }
            self?.dismiss()
        }
    }

    /// 立即关闭浮条并清理状态
    public func dismiss() {
        autoDismissTask?.cancel()
        panel?.orderOut(nil)
        panel = nil
    }

    /// 创建无边框、悬浮于所有 Space 的 NSPanel，关键配置见注释
    private func makePanel(size: CGSize, origin: CGPoint) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        // 提升到 statusBar 层，避免被普通窗口挡住；同时不抢占焦点
        panel.level = .statusBar
        // canJoinAllSpaces：在任意 Space 都显示；fullScreenAuxiliary：在全屏应用上也可见
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.hasShadow = true
        // 让 SwiftUI 的圆角背景透出：设置透明底色 + 非不透明窗体
        panel.backgroundColor = .clear
        panel.isOpaque = false
        return panel
    }
}

/// 浮条内部的 SwiftUI 视图：一排可点击的工具图标按钮
private struct ToolbarContent: View {
    let tools: [Tool]
    let onPick: (Tool) -> Void

    var body: some View {
        HStack(spacing: 4) {
            ForEach(tools) { tool in
                Button { onPick(tool) } label: {
                    Text(tool.icon)
                        .font(.system(size: 16))
                        .frame(width: PanelStyle.toolbarButtonSize.width,
                               height: PanelStyle.toolbarButtonSize.height)
                        .background(PanelColors.button)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .help(tool.name)
            }
        }
        .padding(PanelStyle.toolbarPadding)
        .background(PanelColors.background)
        .clipShape(RoundedRectangle(cornerRadius: PanelStyle.cornerRadius))
    }
}
