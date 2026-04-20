// SliceAIKit/Sources/Permissions/OnboardingFlow.swift
import SwiftUI
import SliceCore

/// 首次启动引导视图，按 欢迎 → 授予辅助功能权限 → 录入 API Key 三步走完首开流程。
///
/// 视图由 `AppDelegate` 在首次启动时呈现，完成或跳过时通过 ``onFinish`` 回调
/// 将用户输入的 API Key 传回宿主（空串表示“稍后再说”）。`accessibilityMonitor`
/// 由外部持有以便轮询生命周期可控，视图只在第 2 步 `onAppear` 时启动监听。
public struct OnboardingFlow: View {

    /// 权限监听器；由外部注入，视图通过 `@ObservedObject` 订阅其状态变化。
    @ObservedObject var accessibilityMonitor: AccessibilityMonitor

    /// 完成或跳过时触发的回调。参数为用户录入的 API Key，空串表示跳过。
    let onFinish: (_ apiKey: String) -> Void

    /// 当前展示的步骤；初始值为欢迎页。
    @State private var step: Step = .welcome

    /// 第 3 步 `SecureField` 绑定的 API Key 文本。
    @State private var apiKey: String = ""

    /// 创建引导视图
    /// - Parameters:
    ///   - accessibilityMonitor: 由宿主持有的权限监听器，用于驱动第 2 步 UI 状态
    ///   - onFinish: 完成或跳过时的回调，传入用户录入的 API Key（空串表示跳过）
    public init(accessibilityMonitor: AccessibilityMonitor,
                onFinish: @escaping (String) -> Void) {
        self.accessibilityMonitor = accessibilityMonitor
        self.onFinish = onFinish
    }

    public var body: some View {
        VStack(spacing: 16) {
            // 根据当前步骤渲染不同的子视图；使用 switch 保证穷尽性
            switch step {
            case .welcome:
                welcomeStep
            case .accessibility:
                accessibilityStep
            case .apiKey:
                apiKeyStep
            }
        }
        .frame(width: 480, height: 340)
        .padding(24)
    }

    // MARK: Steps

    /// 第 0 步：欢迎页，点击“开始”进入权限步骤。
    private var welcomeStep: some View {
        VStack(spacing: 12) {
            Text("欢迎使用 SliceAI").font(.title).bold()
            Text("划词即调用 LLM 的工具栏。3 步开始使用。")
                .foregroundStyle(.secondary)
            Spacer()
            Button("开始") { step = .accessibility }
                .keyboardShortcut(.defaultAction)
        }
    }

    /// 第 1 步：辅助功能权限。根据监听器状态切换指示灯与“下一步”按钮可用性。
    private var accessibilityStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("第 1 步：辅助功能权限").font(.title2).bold()
            Text("SliceAI 需要辅助功能权限才能读取你选中的文字。点下面的按钮，系统会打开相应设置页面。")
                .fixedSize(horizontal: false, vertical: true)
            Divider()
            HStack {
                // 指示灯：已授予为绿色，未授予为橙色
                Circle()
                    .fill(accessibilityMonitor.isTrusted ? Color.green : Color.orange)
                    .frame(width: 10, height: 10)
                Text(accessibilityMonitor.isTrusted ? "已授予" : "未授予").bold()
            }
            Spacer()
            HStack {
                Button("打开辅助功能设置") { accessibilityMonitor.requestTrust() }
                Spacer()
                Button("下一步") { step = .apiKey }
                    .disabled(!accessibilityMonitor.isTrusted)
                    .keyboardShortcut(.defaultAction)
            }
        }
        // 进入本步骤时启动权限轮询，用户授权后 UI 会自动刷新
        .onAppear { accessibilityMonitor.startMonitoring() }
    }

    /// 第 2 步：录入 API Key。允许“稍后再说”跳过（回调空串），或在输入非空时“完成”。
    private var apiKeyStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("第 2 步：录入 OpenAI API Key").font(.title2).bold()
            Text("Key 会保存在 macOS Keychain，不会写入磁盘明文。")
                .foregroundStyle(.secondary)
            SecureField("sk-...", text: $apiKey)
                .textFieldStyle(.roundedBorder)
            Spacer()
            HStack {
                Button("稍后再说") { onFinish("") }
                Spacer()
                Button("完成") { onFinish(apiKey) }
                    .disabled(apiKey.trimmingCharacters(in: .whitespaces).isEmpty)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    /// 引导视图内部的步骤标识。
    enum Step { case welcome, accessibility, apiKey }
}
