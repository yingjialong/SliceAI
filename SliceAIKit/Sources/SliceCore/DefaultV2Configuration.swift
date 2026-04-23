import Foundation

/// v2 默认配置（migrator 无 v1 文件时 fallback，以及 V2ConfigurationStore 首次启动使用）
///
/// 内容与 v1 `DefaultConfiguration.initial()` 同构：1 个 OpenAI Provider + 4 个内置 Prompt Tool。
/// 不复用 `DefaultConfiguration` 的产物——直接用 V2Tool / V2Provider 类型构造。
public enum DefaultV2Configuration {

    /// 生成 v2 默认配置
    public static func initial() -> V2Configuration {
        // 组装 v2 聚合配置（触发、快捷键、遥测均使用保守默认值，与 v1 DefaultConfiguration 对齐）
        V2Configuration(
            schemaVersion: V2Configuration.currentSchemaVersion,
            providers: [openAIDefault],
            tools: [translate, polish, summarize, explain],
            hotkeys: HotkeyBindings(toggleCommandPalette: "option+space"),
            triggers: TriggerSettings(
                floatingToolbarEnabled: true,
                commandPaletteEnabled: true,
                minimumSelectionLength: 1,
                triggerDelayMs: 150,
                floatingToolbarAutoDismissSeconds: 5
            ),
            telemetry: TelemetrySettings(enabled: false),
            appBlocklist: [
                // 常见密码 / 密钥管理类 App，默认屏蔽以降低泄露风险
                "com.apple.keychainaccess",
                "com.1password.1password",
                "com.1password.1password7",
                "com.bitwarden.desktop"
            ],
            appearance: .auto
        )
    }

    /// OpenAI 官方 API Provider，作为首次启动时唯一预置的 v2 Provider
    public static let openAIDefault = V2Provider(
        id: "openai-official",
        kind: .openAICompatible,
        name: "OpenAI",
        // 硬编码的常量字符串 URL，启动时强制解包安全
        baseURL: URL(string: "https://api.openai.com/v1")!, // swiftlint:disable:this force_unwrapping
        apiKeyRef: "keychain:openai-official",
        defaultModel: "gpt-5",
        capabilities: []
    )

    // MARK: - Tools（4 个内置工具，对齐 v1 DefaultConfiguration 文案）

    /// 翻译工具：将选中文字翻译为 variables["language"] 指定的语言
    public static let translate = makePromptTool(
        id: "translate", name: "Translate", icon: "🌐",
        description: "将选中文字翻译为指定语言",
        spec: PromptSpec(
            systemPrompt: "You are a professional translator. Translate faithfully and naturally. "
                        + "Output only the translation without explanations.",
            userPrompt: "Translate the following to {{language}}:\n\n{{selection}}",
            temperature: 0.3,
            variables: ["language": "Simplified Chinese"]
        )
    )

    /// 润色工具：在保持原意的前提下润色选中文字
    public static let polish = makePromptTool(
        id: "polish", name: "Polish", icon: "📝",
        description: "在保持原意的前提下润色文字",
        spec: PromptSpec(
            systemPrompt: "You are an expert editor. Polish the text while preserving the author's "
                        + "voice and meaning. Output only the polished version.",
            userPrompt: "Polish the following text:\n\n{{selection}}",
            temperature: 0.4,
            variables: [:]
        )
    )

    /// 摘要工具：用 Markdown 列表总结选中文字
    public static let summarize = makePromptTool(
        id: "summarize", name: "Summarize", icon: "✨",
        description: "总结关键要点",
        spec: PromptSpec(
            systemPrompt: "You are an expert summarizer. Produce concise, structured summaries.",
            userPrompt: "Summarize the key points of the following text. "
                      + "Use Markdown bullet points:\n\n{{selection}}",
            temperature: 0.3,
            variables: [:]
        )
    )

    /// 解释工具：用浅显语言解释选中的术语或句子
    public static let explain = makePromptTool(
        id: "explain", name: "Explain", icon: "💡",
        description: "解释专业术语或生词",
        spec: PromptSpec(
            systemPrompt: "You are a patient teacher. Explain concepts clearly, assuming an "
                        + "educated but non-expert audience.",
            userPrompt: "Explain the following in simple terms. If it's a technical term or acronym, "
                      + "expand and contextualize:\n\n{{selection}}",
            temperature: 0.4,
            variables: [:]
        )
    )

    // MARK: - Private helpers

    /// prompt 型工具的 prompt/模型参数聚合，避免 makePromptTool 参数过多触发 SwiftLint
    private struct PromptSpec {
        let systemPrompt: String
        let userPrompt: String
        let temperature: Double
        let variables: [String: String]
    }

    /// 构造一个 `.prompt` kind 的 V2Tool（均使用 openAIDefault 作为 fixed provider）
    /// - Parameters:
    ///   - id: 工具唯一 id
    ///   - name: 显示名
    ///   - icon: 浮条图标（emoji 或 SF Symbol）
    ///   - description: 中文描述，供 Settings UI 展示
    ///   - spec: prompt / 温度 / 变量打包后的规格
    /// - Returns: 首方工具（.firstParty）、窗口展示（.window）、图标标签（.icon）的 V2Tool
    private static func makePromptTool(
        id: String,
        name: String,
        icon: String,
        description: String,
        spec: PromptSpec
    ) -> V2Tool {
        V2Tool(
            id: id, name: name, icon: icon, description: description,
            kind: .prompt(PromptTool(
                systemPrompt: spec.systemPrompt,
                userPrompt: spec.userPrompt,
                contexts: [],
                provider: .fixed(providerId: openAIDefault.id, modelId: nil),
                temperature: spec.temperature,
                maxTokens: nil,
                variables: spec.variables
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
    }
}
