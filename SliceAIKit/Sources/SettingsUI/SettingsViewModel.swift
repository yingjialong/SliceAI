// SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift
import Foundation
import SliceCore
import SwiftUI

/// 设置界面主视图模型
///
/// 负责：
///   - 持有当前 `Configuration` 并在 `@Published` 下驱动 SwiftUI 刷新；
///   - 通过注入的 `ConfigurationProviding` 做加载/持久化；
///   - 通过注入的 `KeychainAccessing` 读写 API Key，避免把密钥塞进 Configuration。
///
/// 类型被标记为 `@MainActor`，保证 `@Published` 属性读写只发生在主线程，
/// 并兼容 Swift 6 严格并发检查。
@MainActor
public final class SettingsViewModel: ObservableObject {

    /// 当前正在编辑的完整配置；UI 通过 `$viewModel.configuration.xxx` 做双向绑定
    @Published public var configuration: Configuration

    /// 配置持久化抽象，生产环境通常注入 `FileConfigurationStore`
    private let store: any ConfigurationProviding

    /// Keychain 抽象，生产环境注入 `KeychainStore`
    private let keychain: any KeychainAccessing

    /// 构造设置视图模型
    /// - Parameters:
    ///   - store: 配置读写抽象
    ///   - keychain: Keychain 读写抽象
    ///
    /// 初始化时先塞入内存态的默认配置占位，随后异步 reload 真实磁盘值。
    /// 这样可避免首次渲染出现空白，也无需在调用方处理 async init。
    public init(store: any ConfigurationProviding, keychain: any KeychainAccessing) {
        self.store = store
        self.keychain = keychain
        self.configuration = DefaultConfiguration.initial()
        // 使用 [weak self] 捕获弱引用，避免在 Swift 6 严格并发下 self 在 init
        // 尚未完成时被强引用持有的诊断
        Task { [weak self] in await self?.reload() }
    }

    /// 从 store 拉取最新 Configuration 覆盖当前内存态
    public func reload() async {
        let cfg = await store.current()
        self.configuration = cfg
    }

    /// 将当前内存态 Configuration 写回 store
    /// - Throws: 底层 store 的 IO/序列化错误
    public func save() async throws {
        try await store.update(configuration)
    }

    /// 为指定 provider 写入 API Key
    /// - Parameters:
    ///   - key: 明文 API Key；空串语义由调用方决定
    ///   - providerId: Provider 标识，作为 Keychain 的 account
    public func setAPIKey(_ key: String, for providerId: String) async throws {
        try await keychain.writeAPIKey(key, providerId: providerId)
    }

    /// 读取指定 provider 的 API Key，不存在返回 nil
    /// - Parameter providerId: Provider 标识
    public func readAPIKey(for providerId: String) async throws -> String? {
        try await keychain.readAPIKey(providerId: providerId)
    }
}
