// SliceAIApp/MenuBarController.swift
import AppKit

/// 菜单栏（系统右上角状态栏）控制器。
///
/// 职责：
///   - 在系统状态栏展示一枚 SF Symbol 图标；
///   - 提供打开设置、退出应用的菜单项；
///   - 菜单动作通过 `AppDelegate` 弱引用回调，避免循环引用。
///
/// 线程模型：`@MainActor` 限定；`NSStatusItem` / `NSMenu` 必须在主线程构造与使用。
/// 生命周期：由 `AppDelegate` 创建一次并持有，直到应用退出。
@MainActor
final class MenuBarController {

    /// 宿主 AppDelegate；用弱引用避免与 AppDelegate 之间形成循环
    weak var delegate: AppDelegate?

    /// 系统状态栏的挂载项；必须强引用，否则图标会消失
    private let statusItem: NSStatusItem

    /// 构造并向系统状态栏注册菜单项
    /// - Parameters:
    ///   - container: 组合根，当前未直接使用但保留以便未来在菜单里显示状态
    ///   - delegate: AppDelegate，用于响应菜单动作
    init(container: AppContainer, delegate: AppDelegate) {
        self.delegate = delegate
        // squareLength 让图标区保持方形宽度，与系统原生应用一致
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        // "scissors" SF Symbol 契合 SliceAI 的"划"字含义
        statusItem.button?.image = NSImage(
            systemSymbolName: "scissors",
            accessibilityDescription: "SliceAI"
        )
        statusItem.menu = buildMenu()
    }

    /// 构造菜单项；固定顺序便于测试
    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        // 第一项为展示性标题，点击无动作
        menu.addItem(NSMenuItem(title: "SliceAI", action: nil, keyEquivalent: ""))
        menu.addItem(.separator())
        // Settings…：Command+,（macOS 约定的设置快捷键）
        menu.addItem(
            NSMenuItem(
                title: "Settings…",
                action: #selector(openSettings),
                keyEquivalent: ","
            ).withTarget(self)
        )
        menu.addItem(.separator())
        // Quit：Command+Q；action 走 NSApplication.terminate 由系统处理退出
        menu.addItem(
            NSMenuItem(
                title: "Quit",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
        return menu
    }

    /// 打开设置窗口；委托给 AppDelegate，避免在菜单控制器内直接持有窗口状态
    @objc private func openSettings() {
        delegate?.showSettings()
    }
}

/// 便捷链式设置 `target` 的辅助扩展；只在本文件内使用
private extension NSMenuItem {
    /// 设置菜单项的 target 并返回自身，方便在 buildMenu 内链式调用
    func withTarget(_ target: AnyObject) -> NSMenuItem {
        self.target = target
        return self
    }
}
