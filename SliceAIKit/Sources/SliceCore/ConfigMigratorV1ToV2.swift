import Foundation
import OSLog

private let migrationLog = Logger(subsystem: "com.sliceai.core", category: "ConfigMigration")

/// v1 → v2 配置迁移器
///
/// 纯函数转换；不做磁盘 IO。调用流程：
///   1. 调用方读 `config.json` 原文 → JSONDecode 为 `LegacyConfigV1`
///   2. `ConfigMigratorV1ToV2.migrate(v1)` 返回 `Configuration`
///   3. 调用方（ConfigurationStore）写入 `config-v2.json`
///
/// 迁移规则：
/// - v1 扁平 Tool → `Tool.kind = .prompt(PromptTool)`，provenance = `.firstParty`
/// - v1 Provider → `Provider`（kind=.openAICompatible, capabilities=[]）
/// - v1 可选 UI 字段缺失时 → 用 DefaultConfiguration 默认
/// - v1 `displayMode` 解析失败 → 回退 `.window`
internal enum ConfigMigratorV1ToV2 {

    /// 执行迁移
    /// - Parameter v1: v1 配置快照
    /// - Returns: Configuration（独立 v2 类型）
    /// - Throws: `SliceError.configuration(.schemaVersionTooNew)` 当 v1.schemaVersion != 1
    ///
    /// 访问控制说明（评审修正 Codex 第六轮 P1-2）：`LegacyConfigV1` 是 `internal`，
    /// 因此 `ConfigMigratorV1ToV2` 与 `migrate(_:)` 也必须是 `internal`——否则 Swift
    /// 会报"public API uses internal type"编译错误。M1 只有 SliceCore 内部与
    /// `@testable import SliceCore` 的测试需要访问；外部模块不直接调 migrator。
    ///
    /// **schemaVersion 校验（第八轮 P2-3 修复）**：v1 schema 只有版本 1；非 1 说明文件
    /// 本身不是 v1（可能是用户手把 v2 写进了 config.json、未来版本降级、或无关格式恰好
    /// 通过了 LegacyConfigV1.Decodable）。即使字段碰巧对齐也不能当作 v1 迁移——盲目映射
    /// 会让 v2 配置被错值覆盖且随后由 ConfigurationStore 写盘，彻底破坏用户数据。
    internal static func migrate(_ v1: LegacyConfigV1) throws -> Configuration {
        // 严格拒绝非 v1 schema；错误沿用 schemaVersionTooNew（语义："应用不理解此版本"）
        guard v1.schemaVersion == 1 else {
            throw SliceError.configuration(.schemaVersionTooNew(v1.schemaVersion))
        }
        let providers = v1.providers.map(migrateProvider)
        let tools = v1.tools.map(migrateTool)
        let hotkeys = HotkeyBindings(toggleCommandPalette: v1.hotkeys.toggleCommandPalette)
        let triggers = TriggerSettings(
            floatingToolbarEnabled: v1.triggers.floatingToolbarEnabled,
            commandPaletteEnabled: v1.triggers.commandPaletteEnabled,
            minimumSelectionLength: v1.triggers.minimumSelectionLength,
            triggerDelayMs: v1.triggers.triggerDelayMs,
            floatingToolbarMaxTools: v1.triggers.floatingToolbarMaxTools ?? 6,
            floatingToolbarSize: migrateToolbarSize(v1.triggers.floatingToolbarSize),
            floatingToolbarAutoDismissSeconds: v1.triggers.floatingToolbarAutoDismissSeconds ?? 5
        )
        let telemetry = TelemetrySettings(enabled: v1.telemetry.enabled)
        let appearance = migrateAppearance(v1.appearance)

        // 中文日志：记录迁移产出规模，便于排查 v1 → v2 切换后字段丢失问题
        let providerCount = providers.count
        let toolCount = tools.count
        migrationLog.info("migrated v1 → v2: providers=\(providerCount, privacy: .public)")
        migrationLog.info("migrated v1 → v2: tools=\(toolCount, privacy: .public)")

        return Configuration(
            schemaVersion: Configuration.currentSchemaVersion,
            providers: providers,
            tools: tools,
            hotkeys: hotkeys,
            triggers: triggers,
            telemetry: telemetry,
            appBlocklist: v1.appBlocklist,
            appearance: appearance
        )
    }

    // MARK: - Helpers

    /// v1 Provider → Provider
    private static func migrateProvider(_ v1p: LegacyConfigV1.Provider) -> Provider {
        Provider(
            id: v1p.id,
            kind: .openAICompatible,
            name: v1p.name,
            baseURL: v1p.baseURL,
            apiKeyRef: v1p.apiKeyRef,
            defaultModel: v1p.defaultModel,
            capabilities: []
        )
    }

    /// v1 Tool → Tool（.prompt kind + firstParty provenance）
    private static func migrateTool(_ v1t: LegacyConfigV1.Tool) -> Tool {
        let displayMode = DisplayMode(rawValue: v1t.displayMode) ?? .window
        if displayMode.rawValue != v1t.displayMode {
            // 中文日志：非法 displayMode 已回退 window，保留原始值方便定位用户定制的错值
            let rawMode = v1t.displayMode
            let toolId = v1t.id
            migrationLog.warning("unknown displayMode '\(rawMode, privacy: .public)' tool=\(toolId, privacy: .public)")
        }
        let labelStyle = ToolLabelStyle(rawValue: v1t.labelStyle ?? "icon") ?? .icon

        let pt = PromptTool(
            systemPrompt: v1t.systemPrompt,
            userPrompt: v1t.userPrompt,
            contexts: [],
            provider: .fixed(providerId: v1t.providerId, modelId: v1t.modelId),
            temperature: v1t.temperature,
            maxTokens: nil,
            variables: v1t.variables
        )

        return Tool(
            id: v1t.id,
            name: v1t.name,
            icon: v1t.icon,
            description: v1t.description,
            kind: .prompt(pt),
            visibleWhen: nil,
            displayMode: displayMode,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: labelStyle,
            tags: []
        )
    }

    private static func migrateToolbarSize(_ raw: String?) -> ToolbarSize {
        guard let raw, let size = ToolbarSize(rawValue: raw) else { return .compact }
        return size
    }

    private static func migrateAppearance(_ raw: String?) -> AppearanceMode {
        guard let raw, let mode = AppearanceMode(rawValue: raw) else { return .auto }
        return mode
    }
}
