import Foundation
import SliceCore

/// V2Provider / V2Configuration 测试 fixture 构造工具，供 OrchestrationTests 共用
///
/// 统一在此集中管理测试用的 provider stub 和配置骨架，避免各测试文件各自硬编码，
/// 并确保 URL / model / capability 等常量值前后一致。
public enum MockProvider {

    // MARK: - Provider stubs

    /// OpenAI 兼容协议 stub（需要 baseURL，默认使用 OpenAI 官方 endpoint）
    /// - Parameter id: provider id，默认 `"openai-stub"`
    /// - Parameter defaultModel: 默认模型，默认 `"gpt-5"`
    /// - Returns: kind=.openAICompatible 的 V2Provider 测试 stub
    public static func openAIStub(
        id: String = "openai-stub",
        defaultModel: String = "gpt-5"
    ) -> V2Provider {
        // swiftlint:disable:next force_unwrapping — 硬编码测试用常量 URL，启动时强制解包安全
        let baseURL = URL(string: "https://api.openai.com/v1")!
        return V2Provider(
            id: id,
            kind: .openAICompatible,
            name: "OpenAI Stub",
            baseURL: baseURL,
            apiKeyRef: "keychain:\(id)",
            defaultModel: defaultModel,
            capabilities: [.toolCalling, .promptCaching]
        )
    }

    /// Anthropic 协议 stub（官方 SDK endpoint 固定，baseURL 为 nil）
    /// - Parameter id: provider id，默认 `"anthropic-stub"`
    /// - Parameter defaultModel: 默认模型，默认 `"claude-sonnet-4-6"`
    /// - Returns: kind=.anthropic 的 V2Provider 测试 stub
    public static func anthropicStub(
        id: String = "anthropic-stub",
        defaultModel: String = "claude-sonnet-4-6"
    ) -> V2Provider {
        V2Provider(
            id: id,
            kind: .anthropic,
            name: "Anthropic Stub",
            baseURL: nil,
            apiKeyRef: "keychain:\(id)",
            defaultModel: defaultModel,
            capabilities: [.toolCalling, .promptCaching, .extendedThinking]
        )
    }

    // MARK: - V2Configuration builder

    /// 构造仅包含指定 providers 的最小化 V2Configuration（tools 空、hotkeys / triggers / telemetry 保守默认）
    ///
    /// 与 DefaultV2Configuration.initial() 对齐，仅替换 providers 字段；
    /// 测试只关心 providers 列表，其余字段使用 MVP 保守默认值。
    /// - Parameter providers: 测试需要的 V2Provider 列表
    /// - Returns: 可直接注入 DefaultProviderResolver 的 V2Configuration
    public static func configWith(_ providers: [V2Provider]) -> V2Configuration {
        V2Configuration(
            schemaVersion: V2Configuration.currentSchemaVersion,
            providers: providers,
            tools: [],
            hotkeys: HotkeyBindings(toggleCommandPalette: "option+space"),
            triggers: TriggerSettings(
                floatingToolbarEnabled: true,
                commandPaletteEnabled: true,
                minimumSelectionLength: 1,
                triggerDelayMs: 150
            ),
            telemetry: TelemetrySettings(enabled: false),
            appBlocklist: [],
            appearance: .auto
        )
    }
}
