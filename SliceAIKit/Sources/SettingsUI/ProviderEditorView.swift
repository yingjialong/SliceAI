// SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift
import SwiftUI
import SliceCore

/// 单个 Provider 的编辑表单，含 API Key 的 Keychain 读写入口
///
/// API Key 不存 Configuration，而是通过注入的 `onSaveKey` / `onLoadKey` 回调
/// 间接访问 Keychain。这样本视图无需感知具体存储实现，便于预览与单元测试。
public struct ProviderEditorView: View {

    /// 指向 Configuration 中某个 Provider 的双向绑定
    @Binding public var provider: Provider

    /// 当前编辑态的 API Key 明文（只在内存中，不写回 Configuration）
    @State private var apiKey: String = ""

    /// 保存 API Key 的异步回调；Sendable 以满足 Swift 6 闭包检查
    private let onSaveKey: @Sendable (String) async -> Void

    /// 读取 API Key 的异步回调；Sendable 以满足 Swift 6 闭包检查
    private let onLoadKey: @Sendable () async -> String?

    /// 构造 Provider 编辑视图
    /// - Parameters:
    ///   - provider: 指向 Configuration 中某个 Provider 的绑定
    ///   - onSaveKey: 保存 API Key 的异步回调（宿主通常转发给 Keychain）
    ///   - onLoadKey: 读取 API Key 的异步回调；返回 nil 表示不存在
    public init(
        provider: Binding<Provider>,
        onSaveKey: @escaping @Sendable (String) async -> Void,
        onLoadKey: @escaping @Sendable () async -> String?
    ) {
        self._provider = provider
        self.onSaveKey = onSaveKey
        self.onLoadKey = onLoadKey
    }

    public var body: some View {
        Form {
            Section("Basics") {
                TextField("Name", text: $provider.name)
                TextField(
                    "Base URL",
                    text: Binding(
                        get: { provider.baseURL.absoluteString },
                        set: { newValue in
                            // 仅在能解析为合法 URL 时才覆盖，避免把无效字符串存入 Configuration
                            if let url = URL(string: newValue) {
                                provider.baseURL = url
                            }
                        }
                    )
                )
                TextField("Default Model", text: $provider.defaultModel)
            }

            Section("API Key") {
                SecureField("sk-…", text: $apiKey)
                HStack {
                    Button("Save key") {
                        // 捕获局部 key 值后交给 Task，避免 await 过程中状态被意外修改
                        let key = apiKey
                        Task { await onSaveKey(key) }
                    }
                    .disabled(apiKey.isEmpty)
                    Spacer()
                    Text("Stored in macOS Keychain")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task {
            // 视图首次出现时尝试预填已有 API Key，便于用户确认当前状态
            if let existing = await onLoadKey() {
                apiKey = existing
            }
        }
    }
}
