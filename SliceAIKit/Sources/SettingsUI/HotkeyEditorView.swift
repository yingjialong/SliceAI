// SliceAIKit/Sources/SettingsUI/HotkeyEditorView.swift
import AppKit
import HotkeyManager
import SliceCore
import SwiftUI

/// 命令面板快捷键"按键录制"编辑视图
///
/// 用户点击录制框 → 按下任一组合键 → 立即反序列化为 `Hotkey.description`
/// 字符串写回 binding；无需手动敲字母。放弃原有"手敲字符串 + onSubmit 校验"方案，
/// 避免用户误输入导致 `HotkeyRegistrar.register` 静默失败。
///
/// 实现要点：
///   - 交互入口是 SwiftUI 的 `Button`：点击可靠地切换录制态，规避 NSViewRepresentable
///     在 SwiftUI Settings 窗口里拿不到 firstResponder 的坑；
///   - 录制态下用 `NSEvent.addLocalMonitorForEvents(matching: .keyDown)` 在 AppKit
///     层直接拦截按键，返回 nil 吃掉事件，避免波及 TextField/菜单快捷键；
///   - 反向序列化统一走 `Hotkey.from(keyCode:modifierFlags:)`，复用 HotkeyManager
///     的 keyCode 白名单（与 `Hotkey.parse` 对称，可互相反解）；
///   - UI 层强制至少一个修饰键（否则按 A 就绑定 A，必然误触）；
///   - ESC / 再次点击按钮 取消录制；清除按钮把 binding 置空并立即持久化。
public struct HotkeyEditorView: View {

    /// 指向 Configuration.hotkeys.toggleCommandPalette 的双向绑定
    @Binding public var binding: String

    /// 录制态标志：控制外观 + 是否安装 NSEvent 监视器
    @State private var isRecording = false

    /// 本地的校验错误描述；nil 表示暂未出错
    @State private var error: String?

    /// AppKit local 键盘事件监视器；仅在录制期间持有，录制结束立即移除
    @State private var keyMonitor: Any?

    /// 录制成功后的外部回调（可选），用于让调用方立即持久化配置
    private let onCommit: (() -> Void)?

    /// 构造快捷键编辑视图
    /// - Parameters:
    ///   - binding: 指向 Configuration 中命令面板快捷键字符串的绑定
    ///   - onCommit: 录制成功后的回调（可选）；调用方可在此触发 saveHotkeys()
    public init(binding: Binding<String>, onCommit: (() -> Void)? = nil) {
        self._binding = binding
        self.onCommit = onCommit
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // 录制按钮：点击切换录制态；SwiftUI Button 点击路由 100% 可靠
                Button {
                    toggleRecording()
                } label: {
                    recorderLabel
                }
                .buttonStyle(.plain)
                .contentShape(Rectangle())

                // 清除按钮：写空串 + 立即持久化；AppDelegate 下次注册会 skip
                Button {
                    clearBinding()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .help("清除已绑定的快捷键")
                .disabled(binding.isEmpty && !isRecording)
            }

            if let error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }

            Text(isRecording
                 ? "按下组合键（例：⌘⌥Space）· ESC 取消"
                 : "点击录制框后按下组合键；清除按钮可取消绑定")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        // 视图消失时兜底移除 monitor，防止关闭设置窗口时残留
        .onDisappear { removeKeyMonitor() }
    }

    /// 录制框的 SwiftUI 外观：圆角 + 边框 + 中间文字；录制态换 accentColor 高亮
    private var recorderLabel: some View {
        Text(displayText)
            .font(.system(size: 13, weight: .medium))
            .foregroundColor(.primary)
            .frame(maxWidth: .infinity)
            .frame(height: 28)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isRecording
                          ? Color.accentColor.opacity(0.15)
                          : Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isRecording ? Color.accentColor : Color(nsColor: .separatorColor),
                            lineWidth: isRecording ? 1.5 : 0.5)
            )
    }

    /// 录制框内显示的文本：优先展示当前绑定，录制中 / 未绑定时给出明确提示
    private var displayText: String {
        if isRecording { return "按下组合键…" }
        if binding.isEmpty { return "未绑定" }
        return binding
    }

    // MARK: - 录制状态控制

    /// Button 点击切换录制态：录制中再点一次视为"取消录制"
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    /// 进入录制态：清除上次错误、安装 NSEvent monitor
    private func startRecording() {
        error = nil
        isRecording = true
        installKeyMonitor()
    }

    /// 结束录制态：移除 monitor，不修改 binding（保留当前值）
    private func stopRecording() {
        isRecording = false
        removeKeyMonitor()
    }

    /// 清除按钮处理：置空 binding 并立即持久化；幂等地退出录制态
    private func clearBinding() {
        binding = ""
        error = nil
        stopRecording()
        onCommit?()
    }

    // MARK: - NSEvent 监视器

    /// 安装 local key monitor，拦截 keyDown 事件做反向序列化
    ///
    /// local monitor 只接收本 App 事件，同步返回 NSEvent?；返回 nil 即"吃掉"事件，
    /// 避免 TextField / 菜单快捷键等后续 responder 误处理。返回 event 表示放行。
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // keyCode 53 = Escape：取消录制，不写回
            if event.keyCode == 53 {
                stopRecording()
                return nil
            }

            // 反向解析：命中 Hotkey 白名单 → 校验修饰键 → 写回 binding 或提示错误
            if let hotkey = Hotkey.from(keyCode: event.keyCode, modifierFlags: event.modifierFlags) {
                // UI 层业务校验：至少一个修饰键，否则按 A 会绑定 A 必然误触
                guard !hotkey.modifiers.isEmpty else {
                    error = "至少同时按住一个修饰键（⌘⌥⌃⇧）"
                    return nil
                }
                // 成功录制：写回 binding、退出录制、持久化
                binding = hotkey.description
                error = nil
                isRecording = false
                removeKeyMonitor()
                onCommit?()
                return nil
            } else {
                error = "不支持的按键；仅支持 a-z / 0-9 / F1-F12 / 方向键 / space / return / tab"
                return nil
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
}
