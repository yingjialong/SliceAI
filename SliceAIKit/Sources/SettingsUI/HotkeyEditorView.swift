// SliceAIKit/Sources/SettingsUI/HotkeyEditorView.swift
import SwiftUI
import SliceCore

/// 命令面板快捷键编辑视图
///
/// 仅做"非空"弱校验，真正的冲突/合法性检查由 `HotkeyRegistrar`（运行时）
/// 承担。这里不强依赖 HotkeyManager 模块，避免把 Carbon 解析逻辑下沉到设置 UI。
public struct HotkeyEditorView: View {

    /// 指向 Configuration.hotkeys.toggleCommandPalette 的双向绑定
    @Binding public var binding: String

    /// 本地的校验错误描述；nil 表示暂未出错
    @State private var error: String?

    /// 构造快捷键编辑视图
    /// - Parameter binding: 指向 Configuration 中命令面板快捷键字符串的绑定
    public init(binding: Binding<String>) {
        self._binding = binding
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Command Palette")
                    .frame(width: 140, alignment: .leading)
                TextField("option+space", text: $binding)
                    .onSubmit { validate() }
            }
            if let error {
                Text(error)
                    .foregroundColor(.red)
                    .font(.caption)
            }
            Text("支持: cmd / option / shift / ctrl / space / a–z / 0–9 / f1–f12 / 方向键 / return / esc")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
    }

    /// 轻量校验：仅拒绝空串；真正的 parse 由 HotkeyRegistrar 在注册时负责
    private func validate() {
        if binding.isEmpty {
            error = "不能为空"
            return
        }
        error = nil
    }
}
