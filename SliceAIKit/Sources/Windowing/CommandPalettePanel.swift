// SliceAIKit/Sources/Windowing/CommandPalettePanel.swift
import AppKit
import SwiftUI
import SliceCore

/// 快捷键 ⌥Space 调出的中央命令面板（C 模式）
///
/// 职责：在屏幕正中央显示一个带搜索框与工具列表的命令面板；
/// 支持键盘上下键切换、回车确认、ESC 取消；也可选显示一段当前选区预览。
/// 线程模型：整个类在主 actor 上运行，保证 `NSPanel` / `NSHostingView` 的安全访问。
@MainActor
public final class CommandPalettePanel {

    /// 当前承载面板的 NSPanel，dismiss 后置 nil
    private var panel: NSPanel?

    /// 无状态构造器
    public init() {}

    /// 在屏幕中央显示命令面板
    /// - Parameters:
    ///   - tools: 可供筛选与选择的工具列表
    ///   - preview: 可选的选区预览文本，若为空则不显示预览行
    ///   - onPick: 用户选中某工具后的回调
    public func show(tools: [Tool], preview: String?, onPick: @escaping (Tool) -> Void) {
        // 固定面板尺寸 480×360，兼顾搜索框、预览与多行列表
        let size = CGSize(width: 480, height: 360)
        // 主屏幕可见区为基准计算中心 origin；多屏场景下仅使用主屏即可满足 MVP 需求
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screen.midX - size.width / 2,
            y: screen.midY - size.height / 2
        )
        // 构造 NSPanel 并以 SwiftUI 视图填充
        let panel = makePanel(size: size, origin: origin)
        let hosting = NSHostingView(rootView: PaletteContent(
            tools: tools,
            preview: preview ?? "",
            onPick: { [weak self] t in
                // 先通知业务方执行具体工具，再关闭面板，避免回调读已失效状态
                onPick(t)
                self?.dismiss()
            },
            onCancel: { [weak self] in self?.dismiss() }
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        panel.contentView = hosting
        // makeKeyAndOrderFront 让面板获取键盘焦点，以便 TextField/onKeyPress 接收按键
        panel.makeKeyAndOrderFront(nil)
        // 激活本应用，确保 ⌥Space 在其他 App 前台时依然能把焦点抢到命令面板
        NSApp.activate(ignoringOtherApps: true)
        self.panel = panel
    }

    /// 立即关闭面板并清理状态
    public func dismiss() {
        panel?.orderOut(nil)
        panel = nil
    }

    /// 构造带标题栏但隐藏标题、可拖拽、悬浮于所有 Space 的 NSPanel
    private func makePanel(size: CGSize, origin: CGPoint) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .closable, .fullSizeContentView, .utilityWindow],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces]
        // 让 SwiftUI 的圆角背景透出：设置透明底色 + 非不透明窗体
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }
}

/// 命令面板内部的 SwiftUI 视图：预览 + 搜索框 + 结果列表 + 键盘事件处理
private struct PaletteContent: View {
    let tools: [Tool]
    let preview: String
    let onPick: (Tool) -> Void
    let onCancel: () -> Void

    /// 搜索输入
    @State private var query: String = ""
    /// 列表当前高亮项的索引（对应 filtered 数组）
    @State private var selection: Int = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !preview.isEmpty {
                // 预览行：斜体、暗色、最多两行，辅助用户确认当前要处理的文本
                Text(preview)
                    .font(.system(size: 11))
                    .italic()
                    .foregroundColor(PanelColors.textSecondary)
                    .lineLimit(2)
                    .padding(.horizontal, 14).padding(.top, 12)
            }
            TextField("Search tools…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 16))
                .padding(14)
                .foregroundColor(PanelColors.text)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // 使用 enumerated().map 把 EnumeratedSequence 转为数组，满足 ForEach 要求；
                    // 以 offset 作为 id 在查询变化时会触发“移动”动画，但对 MVP 可接受。
                    ForEach(filtered.enumerated().map({ $0 }), id: \.offset) { idx, tool in
                        Button { onPick(tool) } label: {
                            HStack {
                                Text(tool.icon).font(.system(size: 18))
                                Text(tool.name)
                                    .foregroundColor(PanelColors.text)
                                Spacer()
                            }
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(idx == selection ? PanelColors.accent : Color.clear)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            // 键盘导航：上/下切换选中项，回车确认，ESC 取消
            .onKeyPress(.upArrow) { selection = max(0, selection - 1); return .handled }
            .onKeyPress(.downArrow) {
                selection = min(filtered.count - 1, selection + 1)
                return .handled
            }
            .onKeyPress(.return) {
                if filtered.indices.contains(selection) { onPick(filtered[selection]) }
                return .handled
            }
            .onKeyPress(.escape) { onCancel(); return .handled }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PanelColors.background)
        .clipShape(RoundedRectangle(cornerRadius: PanelStyle.cornerRadius))
    }

    /// 基于 query 进行大小写不敏感的名称/描述模糊筛选；query 为空则返回全部
    private var filtered: [Tool] {
        guard !query.isEmpty else { return tools }
        let q = query.lowercased()
        return tools.filter {
            $0.name.lowercased().contains(q)
            || ($0.description?.lowercased().contains(q) ?? false)
        }
    }
}
