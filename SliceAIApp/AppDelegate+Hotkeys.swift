// SliceAIApp/AppDelegate+Hotkeys.swift
import Foundation
import HotkeyManager
import OSLog
import SliceCore

extension AppDelegate {

    /// 按配置重新注册命令面板热键与工具级热键
    ///
    /// 每次调用都会先 `unregisterAll` 清空上一次的 Carbon 注册，再按最新配置注册。
    /// 这样设置页改完热键立即生效，且避免旧热键遗留。
    ///
    /// 实现要点：
    ///   - 仅在 `triggers.commandPaletteEnabled == true` 时注册命令面板热键；
    ///   - 工具热键独立注册，直接按 tool id 捕获选区并执行工具；
    ///   - 解析失败或 Carbon 注册失败均静默忽略，遵循"无自由日志"规范；
    ///   - 回调中显式跳回 MainActor 以保持 UI 操作安全。
    func reloadHotkey() {
        guard let container else { return }
        // 先清空旧注册，避免设置页多次保存后旧热键仍然留在 Carbon 注册表里
        container.hotkeyRegistrar.unregisterAll()
        Task { @MainActor [weak self] in
            guard let self, let container = self.container else { return }
            let cfg: Configuration
            do {
                cfg = try await container.configStore.current()
            } catch {
                Self.log.info("hotkey: config load failed \(error.localizedDescription, privacy: .private)")
                return
            }
            self.registerCommandPaletteHotkeyIfNeeded(cfg, container: container)
            self.registerToolHotkeys(cfg, container: container)
        }
    }

    /// 注册命令面板热键
    /// - Parameters:
    ///   - cfg: 当前配置快照
    ///   - container: App 依赖容器
    private func registerCommandPaletteHotkeyIfNeeded(_ cfg: Configuration, container: AppContainer) {
        guard cfg.triggers.commandPaletteEnabled else {
            Self.log.info("hotkey: commandPaletteEnabled=false, skip command palette")
            return
        }
        let raw = cfg.hotkeys.toggleCommandPalette
        guard let hotkey = try? Hotkey.parse(raw) else {
            Self.log.info("hotkey: command palette parse failed for '\(raw, privacy: .public)'")
            return
        }
        do {
            _ = try container.hotkeyRegistrar.register(hotkey) { [weak self] in
                // Carbon 回调已经在主线程，但 Swift 6 严格并发需要显式跳回 MainActor
                Task { @MainActor in self?.showCommandPalette() }
            }
            Self.log.info("hotkey: command palette registered \(hotkey.description, privacy: .public)")
        } catch {
            Self.log.info("hotkey: command palette register failed \(String(describing: error), privacy: .public)")
        }
    }

    /// 注册所有有效的工具级热键
    /// - Parameters:
    ///   - cfg: 当前配置快照
    ///   - container: App 依赖容器
    private func registerToolHotkeys(_ cfg: Configuration, container: AppContainer) {
        let registrations = ToolHotkeyRegistration.validRegistrations(in: cfg)
        guard !registrations.isEmpty else {
            Self.log.info("hotkey: no tool hotkeys to register")
            return
        }
        for registration in registrations {
            registerToolHotkey(registration, container: container)
        }
    }

    /// 注册单个工具热键
    /// - Parameters:
    ///   - registration: 已解析且通过冲突校验的工具热键条目
    ///   - container: App 依赖容器
    private func registerToolHotkey(_ registration: ToolHotkeyRegistration, container: AppContainer) {
        do {
            _ = try container.hotkeyRegistrar.register(registration.hotkey) { [weak self] in
                let toolID = registration.toolID
                Task { @MainActor in self?.runToolHotkey(toolID: toolID) }
            }
            let toolID = registration.toolID
            let hotkey = registration.hotkey.description
            Self.log.info("hotkey: tool registered id=\(toolID, privacy: .public) key=\(hotkey, privacy: .public)")
        } catch {
            let toolID = registration.toolID
            Self.log.info("hotkey: tool register failed id=\(toolID, privacy: .public)")
        }
    }
}
