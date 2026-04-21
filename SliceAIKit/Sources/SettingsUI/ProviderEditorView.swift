// SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift
import SliceCore
import SwiftUI

/// 单个 Provider 的编辑表单，含 API Key 的 Keychain 读写入口与连接测试
///
/// API Key 不存 Configuration，而是通过注入的 `onSaveKey` / `onLoadKey` 回调
/// 间接访问 Keychain；连接测试通过 `onTestKey` 回调（通常由 ViewModel 转发到
/// LLMProviders）。这样本视图无需感知具体存储 / 网络实现，便于预览与单元测试。
public struct ProviderEditorView: View {

    /// 指向 Configuration 中某个 Provider 的双向绑定
    @Binding public var provider: Provider

    /// 当前编辑态的 API Key 明文（只在内存中，不写回 Configuration）
    @State private var apiKey: String = ""

    /// 已从 Keychain 预读的 API Key；Test connection 在 `apiKey` 为空时回退使用
    /// （遵循"typed first, saved fallback"约定，让用户改完 key 不必先 Save 也能 Test）
    @State private var savedKey: String = ""

    /// Save key 后的状态消息：成功绿/灰、失败红；成功 2 秒自动消失
    @State private var saveMessage: StatusMessage?

    /// Test connection 后的状态消息：成功绿/灰、失败红；成功 2 秒自动消失
    @State private var testMessage: StatusMessage?

    /// Test 是否进行中；为 true 时禁用按钮 + 显示"测试中…"
    @State private var isTesting: Bool = false

    /// 保存 API Key 的异步回调；改成 throws 让错误能在 UI 层呈现"保存失败：xxx"
    private let onSaveKey: @Sendable (String) async throws -> Void

    /// 读取 API Key 的异步回调；返回 nil 表示不存在
    private let onLoadKey: @Sendable () async -> String?

    /// 测试连接的异步回调；签名 (key, baseURL, model)。
    /// 由调用方（通常 SettingsScene → SettingsViewModel.testProvider）注入
    /// 真正的 LLM 探测请求；本视图只负责 UI 状态与错误展示。
    private let onTestKey: @Sendable (String, URL, String) async throws -> Void

    /// 构造 Provider 编辑视图
    /// - Parameters:
    ///   - provider: 指向 Configuration 中某个 Provider 的绑定
    ///   - onSaveKey: 保存 API Key 的异步回调；抛错会被 UI 转成"保存失败"提示
    ///   - onLoadKey: 读取 API Key 的异步回调；返回 nil 表示槽位为空
    ///   - onTestKey: 测试连接的异步回调；抛错会被 UI 转成"测试失败"提示
    public init(
        provider: Binding<Provider>,
        onSaveKey: @escaping @Sendable (String) async throws -> Void,
        onLoadKey: @escaping @Sendable () async -> String?,
        onTestKey: @escaping @Sendable (String, URL, String) async throws -> Void
    ) {
        self._provider = provider
        self.onSaveKey = onSaveKey
        self.onLoadKey = onLoadKey
        self.onTestKey = onTestKey
    }

    public var body: some View {
        Form {
            basicsSection
            apiKeySection
        }
        .formStyle(.grouped)
        .task {
            // 视图首次出现时尝试预填已有 API Key，便于用户确认当前状态。
            // 预读的值同时存入 savedKey 供 Test connection 在 SecureField 为空时回退
            if let existing = await onLoadKey() {
                apiKey = existing
                savedKey = existing
            }
        }
    }

    /// 基础信息：名称 / Base URL / 默认模型
    private var basicsSection: some View {
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
    }

    /// API Key + Save / Test 按钮 + 状态消息
    private var apiKeySection: some View {
        Section("API Key") {
            SecureField("sk-…", text: $apiKey)
            HStack(spacing: 12) {
                Button("Save key") {
                    Task { await saveKey() }
                }
                .disabled(apiKey.isEmpty)

                Button("Test connection") {
                    Task { await testKey() }
                }
                .disabled(isTesting || effectiveKey.isEmpty)

                Spacer()
                Text("Stored in macOS Keychain")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            // 状态消息独立于 HStack 排列，避免按钮行 layout 抖动
            if let msg = saveMessage {
                statusLabel(msg)
            }
            if let msg = testMessage {
                statusLabel(msg)
            }
        }
    }

    /// Test 实际使用的 key：SecureField 非空用 typed；否则用预读的 saved key
    /// 任一非空 Test 即可触发；都为空则按钮 disabled，引导用户先填 key
    private var effectiveKey: String {
        apiKey.isEmpty ? savedKey : apiKey
    }

    /// 执行保存：捕获当前 apiKey、调用 onSaveKey、按结果更新 saveMessage
    /// 成功消息 2 秒后自动消失（如果期间没被错误覆盖）；失败消息保留到下次保存
    private func saveKey() async {
        let key = apiKey
        do {
            try await onSaveKey(key)
            // 同步更新 savedKey，让 Test 立即可用最新已保存值
            savedKey = key
            saveMessage = StatusMessage(text: "已保存", isError: false)
            // 成功消息 2 秒后清；期间被错误覆盖则跳过清除
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if saveMessage?.isError == false {
                saveMessage = nil
            }
        } catch {
            saveMessage = StatusMessage(
                text: "保存失败：\(error.localizedDescription)",
                isError: true
            )
        }
    }

    /// 执行连接测试：用 effectiveKey + 当前 baseURL/model，调 onTestKey
    /// 期间禁用 Test 按钮 + 显示"测试中…"；结束后立即恢复按钮状态
    private func testKey() async {
        let key = effectiveKey
        guard !key.isEmpty else { return }
        isTesting = true
        testMessage = StatusMessage(text: "测试中…", isError: false)
        do {
            try await onTestKey(key, provider.baseURL, provider.defaultModel)
            // 拿到首 chunk / 流结束即视为成功，由 onTestKey 内部判定
            testMessage = StatusMessage(text: "✓ 连接成功", isError: false)
            isTesting = false
            // 成功消息 2 秒后清；期间被错误覆盖则跳过清除
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if testMessage?.isError == false {
                testMessage = nil
            }
        } catch let err as SliceError {
            // SliceError 已带友好文案，直接展示 userMessage
            testMessage = StatusMessage(text: "✗ \(err.userMessage)", isError: true)
            isTesting = false
        } catch {
            testMessage = StatusMessage(
                text: "✗ \(error.localizedDescription)",
                isError: true
            )
            isTesting = false
        }
    }

    /// 状态消息标签：错误用红色、成功/进行中用次要灰色
    @ViewBuilder
    private func statusLabel(_ msg: StatusMessage) -> some View {
        Text(msg.text)
            .font(.caption)
            .foregroundStyle(msg.isError ? Color.red : Color.secondary)
            .lineLimit(2)
    }
}

/// 文件内私有：状态消息载体
/// 用于 saveMessage / testMessage 双 @State，统一展示样式
private struct StatusMessage: Equatable, Sendable {
    let text: String
    let isError: Bool
}
