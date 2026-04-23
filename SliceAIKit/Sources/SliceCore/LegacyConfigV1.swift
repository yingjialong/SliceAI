import Foundation

/// v1 `config.json` 的精确快照结构；**仅用于 ConfigMigratorV1ToV2**
///
/// 与 `Configuration` / `Tool` / `Provider` 的 v2 Codable 完全解耦——避免 v2 的
/// 宽松反序列化（`decodeIfPresent` 兜底）掩盖字段缺失。本结构要求 v1 必填字段严格存在，
/// 任何 decode 失败都意味着 v1 JSON 本身破损或格式非 v1。
internal struct LegacyConfigV1: Decodable {
    let schemaVersion: Int
    let providers: [Provider]
    let tools: [Tool]
    let hotkeys: Hotkeys
    let triggers: Triggers
    let telemetry: Telemetry
    let appBlocklist: [String]
    let appearance: String?   // v1 后期加的可选字段

    struct Provider: Decodable {
        let id: String
        let name: String
        let baseURL: URL
        let apiKeyRef: String
        let defaultModel: String
    }

    struct Tool: Decodable {
        let id: String
        let name: String
        let icon: String
        let description: String?
        let systemPrompt: String?
        let userPrompt: String
        let providerId: String
        let modelId: String?
        let temperature: Double?
        let displayMode: String
        let variables: [String: String]
        let labelStyle: String?
    }

    struct Hotkeys: Decodable {
        let toggleCommandPalette: String
    }

    struct Triggers: Decodable {
        let floatingToolbarEnabled: Bool
        let commandPaletteEnabled: Bool
        let minimumSelectionLength: Int
        let triggerDelayMs: Int
        let floatingToolbarMaxTools: Int?
        let floatingToolbarSize: String?
        let floatingToolbarAutoDismissSeconds: Int?
    }

    struct Telemetry: Decodable {
        let enabled: Bool
    }
}
