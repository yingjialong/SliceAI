// SliceAIKit/Sources/Windowing/CommandPalettePanel.swift
import AppKit
import DesignSystem
import SliceCore
import SwiftUI

/// ⌥Space 调出的中央命令面板（Raycast 风格美化版）
///
/// 职责：在屏幕居中偏上 30% 处显示 560×420pt 的命令面板；
/// 支持选中文本预览、搜索过滤、键盘导航（↑↓/↵/ESC）；
/// 使用 DesignSystem 的 SliceColor / SliceFont / SliceSpacing / SliceRadius token。
/// 线程模型：整个类在主 actor 上运行，保证 NSPanel / NSHostingView 的安全访问。
@MainActor
public final class CommandPalettePanel {

    /// 当前承载面板的 NSPanel，dismiss 后置 nil
    private var panel: NSPanel?

    /// 无状态构造器
    public init() {}

    /// 在屏幕居中偏上 30% 处显示命令面板
    /// - Parameters:
    ///   - tools: 可供筛选与选择的工具列表
    ///   - preview: 可选的选区预览文本，若为空则不显示预览行
    ///   - onPick: 用户选中某工具后的回调（在主线程触发）
    public func show(tools: [Tool], preview: String?, onPick: @escaping (Tool) -> Void) {
        // 固定面板尺寸 560×420pt，比老版宽 80pt，更接近 Raycast 黄金比例
        let size = CGSize(width: 560, height: 420)
        // 主屏幕可见区为基准；垂直取 minY + height * 0.55 达到"居中偏上 30%"效果
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let origin = CGPoint(
            x: screen.midX - size.width / 2,
            y: screen.minY + screen.height * 0.55
        )
        let panel = makePanel(size: size, origin: origin)
        let hosting = NSHostingView(rootView: PaletteContent(
            tools: tools,
            preview: preview ?? "",
            onPick: { [weak self] tool in
                // 先通知业务方执行具体工具，再关闭面板，避免回调读已失效状态
                onPick(tool)
                self?.dismiss()
            },
            onCancel: { [weak self] in self?.dismiss() }
        ))
        hosting.frame = NSRect(origin: .zero, size: size)
        // 允许 hosting view 跟随 panel resize（虽然当前面板固定尺寸，但保留容错）
        hosting.autoresizingMask = [.width, .height]
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
        // .utilityWindow：避免触发 Dock 跳动，且不会出现在 Expose/Mission Control 缩略图中
        let panel = NSPanel(
            contentRect: NSRect(origin: origin, size: size),
            styleMask: [.titled, .fullSizeContentView, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.level = .floating
        // canJoinAllSpaces：跨 Desktop 不会消失
        panel.collectionBehavior = [.canJoinAllSpaces]
        // 让 SwiftUI 的圆角背景透出：设置透明底色 + 非不透明窗体
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        return panel
    }
}

// MARK: - PaletteContent

/// 命令面板内部的 SwiftUI 视图：选区预览 + 搜索框 + 结果列表 + footer
private struct PaletteContent: View {
    let tools: [Tool]
    let preview: String
    let onPick: (Tool) -> Void
    let onCancel: () -> Void

    /// 搜索输入
    @State private var query: String = ""
    /// 列表当前高亮项的索引（对应 filtered 数组）
    @State private var selection: Int = 0
    /// AppKit local 键盘事件监视器；仅在面板可见期间持有。
    ///
    /// 为什么不用 `.onKeyPress(...)`：SwiftUI 的 onKeyPress 要求视图参与 focus 链，
    /// 但命令面板里 TextField 默认拿走 keyboard focus，方向键/ESC/回车的路由在
    /// NSPanel 宿主下不稳定（Task 22 后的实测现象）。改用 AppKit 层的 local monitor：
    ///   - 事件优先级高于 SwiftUI 的任何 onKeyPress；
    ///   - 返回 nil 即"吃掉"事件，不会再流向 TextField（避免 ↑↓ 意外移动光标）；
    ///   - monitor 作用域严格限定在面板生命周期（onAppear 安装、onDisappear 移除）。
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // MARK: 选区预览行（仅在 preview 非空时显示）
            if !preview.isEmpty {
                HStack(spacing: SliceSpacing.md) {
                    // overline label：大写小字，字距宽，辅助区分语义
                    Text("选中文本")
                        .font(SliceFont.overline)
                        .kerning(SliceKerning.wide)
                        .foregroundColor(SliceColor.textTertiary)
                    // 原文预览：斜体、单行截断，防止长文本撑高布局
                    Text(preview)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                        .italic()
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
                .padding(.horizontal, SliceSpacing.xxl)
                .padding(.top, SliceSpacing.base)
                .padding(.bottom, SliceSpacing.md)
                Divider().background(SliceColor.divider)
            }

            // MARK: 搜索框区域
            HStack(spacing: SliceSpacing.lg) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15))
                    .foregroundColor(SliceColor.textTertiary)
                // placeholder 包含操作教学，降低首次使用学习成本
                TextField(
                    "",
                    text: $query,
                    prompt: Text("输入工具名，或按 ↑↓ 选择 · ↵ 执行 · ESC 关闭")
                )
                .textFieldStyle(.plain)
                .font(SliceFont.headline)
                .foregroundColor(SliceColor.textPrimary)
                .kerning(SliceKerning.snug)
                // query 变化时重置高亮索引，避免旧索引超出新 filtered 范围导致回车静默失效
                .onChange(of: query) { _, _ in selection = 0 }
            }
            .padding(.horizontal, SliceSpacing.xxl)
            .padding(.vertical, SliceSpacing.lg)
            Divider().background(SliceColor.divider)

            // MARK: 工具列表
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // enumerated().map 将枚举序列转为数组，满足 ForEach 的 RandomAccessCollection 要求
                    ForEach(filtered.enumerated().map({ $0 }), id: \.offset) { index, tool in
                        PaletteRow(tool: tool, isSelected: index == selection)
                            .contentShape(Rectangle())
                            .onTapGesture { onPick(tool) }
                    }
                    // 空状态：区分"未配置工具"与"搜索无匹配"两种情况，避免文案误导
                    if filtered.isEmpty {
                        Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "尚未配置任何工具"
                            : "没有匹配的工具")
                            .font(SliceFont.callout)
                            .foregroundColor(SliceColor.textTertiary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(SliceSpacing.group)
                    }
                }
                .padding(.horizontal, SliceSpacing.md)
                .padding(.top, SliceSpacing.md)
            }
            // 键盘导航由 onAppear 安装的 NSEvent local monitor 统一处理，
            // 避免与 TextField 的 focus 争用（见 keyMonitor 字段注释）

            // MARK: Footer：快捷键帮助 + 计数
            Divider().background(SliceColor.divider)
            HStack {
                HStack(spacing: SliceSpacing.md) {
                    HStack(spacing: SliceSpacing.xs) {
                        KbdKey("↵")
                        Text("执行")
                    }
                    HStack(spacing: SliceSpacing.xs) {
                        KbdKey("ESC")
                        Text("关闭")
                    }
                }
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
                Spacer()
                // 计数格式：当前匹配数 / 总工具数
                Text("\(filtered.count) / \(tools.count)")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
            }
            .padding(.horizontal, SliceSpacing.xxl)
            .padding(.vertical, SliceSpacing.base)
        }
        // 毛玻璃背景：.popover 材质，10pt 圆角（SliceRadius.sheet）
        .glassBackground(.popover, cornerRadius: SliceRadius.sheet)
        // 0.5pt 边框描边，增加面板层次感
        .overlay(
            RoundedRectangle(cornerRadius: SliceRadius.sheet)
                .stroke(SliceColor.border, lineWidth: 0.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: SliceRadius.sheet))
        // MARK: 键盘导航：onAppear 安装 local monitor、onDisappear 拆除
        .onAppear { installKeyMonitor() }
        .onDisappear { removeKeyMonitor() }
    }

    /// 安装 AppKit local key monitor，拦截 ↑↓/↵/ESC 并驱动 selection / onPick / onCancel
    ///
    /// local monitor 的回调在主线程同步执行，返回 nil 表示"吃掉"事件不再向下游派发，
    /// 这样即使 TextField 正聚焦也不会把方向键当成光标移动处理。
    /// 其它按键（字母/数字/删除等）return event 原样放行给 TextField 输入。
    private func installKeyMonitor() {
        // 重复安装防御：理论上 onAppear 只触发一次，但面板复用时可能二次调用
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // 主线程同步分发：local monitor 文档保证在主线程调用，可直接更新 @State
            switch event.keyCode {
            case 126: // up
                selection = max(0, selection - 1)
                return nil
            case 125: // down
                selection = min(max(0, filtered.count - 1), selection + 1)
                return nil
            case 36, 76: // return / keypad enter
                if filtered.indices.contains(selection) { onPick(filtered[selection]) }
                return nil
            case 53: // escape
                onCancel()
                return nil
            default:
                // 其它按键继续走默认 responder chain，TextField 收到字母/数字作搜索输入
                return event
            }
        }
    }

    /// 移除 local key monitor；幂等，未安装时直接跳过
    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    /// 基于 query 进行大小写不敏感的名称 / 描述模糊筛选；query 为空或纯空白则返回全部
    private var filtered: [Tool] {
        // 先 trim 再判空：避免用户输入空格时被视为有效查询
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return tools }
        return tools.filter {
            $0.name.lowercased().contains(trimmedQuery)
                || ($0.description?.lowercased().contains(trimmedQuery) ?? false)
        }
    }
}

// MARK: - PaletteRow

/// 单个工具行：28×28 图标 + 工具名 + 描述 + 选中时显示 ↵ kbd
private struct PaletteRow: View {
    let tool: Tool
    let isSelected: Bool

    var body: some View {
        HStack(spacing: SliceSpacing.xl) {
            // 图标容器：28×28，选中时换强调填充色
            ZStack {
                RoundedRectangle(cornerRadius: SliceRadius.control)
                    .fill(isSelected ? SliceColor.accentFillStrong : SliceColor.hoverFill)
                Text(tool.icon)
                    .font(.system(size: 15))
                    .foregroundColor(isSelected ? SliceColor.accent : SliceColor.textPrimary)
            }
            .frame(width: 28, height: 28)

            // 工具名 + 描述（描述存在且非空时才渲染第二行）
            VStack(alignment: .leading, spacing: 1) {
                Text(tool.name)
                    .font(SliceFont.body)
                    .foregroundColor(isSelected ? SliceColor.accentText : SliceColor.textPrimary)
                if let description = tool.description, !description.isEmpty {
                    Text(description)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textTertiary)
                        .lineLimit(1)
                }
            }
            Spacer()
            // 仅选中项显示 ↵ 键位提示
            if isSelected { KbdKey("↵") }
        }
        .padding(.horizontal, SliceSpacing.xl)
        .padding(.vertical, SliceSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: SliceRadius.control)
                .fill(isSelected ? SliceColor.accentFillLight : .clear)
        )
    }
}
