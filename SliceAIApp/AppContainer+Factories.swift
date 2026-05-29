// SliceAIApp/AppContainer+Factories.swift
import AppKit
import Capabilities
import DesignSystem
import Foundation
import HotkeyManager
import LLMProviders
import Orchestration
import OSLog
import Permissions
import SelectionCapture
import SettingsUI
import SliceCore
import Windowing

/// AppContainer 生产 MCP runtime 依赖。
struct AppMCPRuntimeDependencies {
    let descriptorsProvider: @Sendable () async throws -> [MCPDescriptor]
    let client: any MCPClientProtocol
}

extension AppContainer {

    /// 创建生产 PermissionBroker。
    /// - Parameter appSupport: app support 目录。
    /// - Returns: 完整配置 presenter 与 persistent grant store 的 broker。
    static func makePermissionBroker(appSupport: URL) -> any PermissionBrokerProtocol {
        PermissionBroker(
            store: PermissionGrantStore(),
            persistentStore: PersistentPermissionGrantStore(
                fileURL: appSupport.appendingPathComponent("permission-grants.json")
            ),
            consentPresenter: AppPermissionConsentPresenter()
        )
    }

    /// 创建生产 MCP runtime。
    /// - Parameter appSupport: app support 目录。
    /// - Returns: MCP descriptor provider 与 routing client。
    static func makeMCPRuntime(appSupport: URL) -> AppMCPRuntimeDependencies {
        let mcpServerStore = MCPServerStore(fileURL: appSupport.appendingPathComponent("mcp.json"))
        let descriptorsProvider: @Sendable () async throws -> [MCPDescriptor] = {
            try await mcpServerStore.snapshot()
        }
        let stdioMCPClient = StdioMCPClient(descriptors: descriptorsProvider)
        let streamableHTTPMCPClient = StreamableHTTPMCPClient(descriptors: descriptorsProvider)
        let routingMCPClient = RoutingMCPClient(
            descriptors: descriptorsProvider,
            stdio: stdioMCPClient,
            streamableHTTP: streamableHTTPMCPClient
        )
        return AppMCPRuntimeDependencies(descriptorsProvider: descriptorsProvider, client: routingMCPClient)
    }

    /// 创建生产 ProviderResolver。
    /// - Parameter configStore: v2 配置存储。
    /// - Returns: 使用最新配置快照解析 ProviderSelection 的 resolver。
    static func makeProviderResolver(configStore: ConfigurationStore) -> any ProviderResolverProtocol {
        DefaultProviderResolver(
            configurationProvider: { [configStore] in try await configStore.current() }
        )
    }

    /// 创建 cost sqlite 与 audit jsonl 遥测依赖。
    /// - Parameter appSupport: app support 目录。
    /// - Returns: cost 记账器与 audit 日志。
    /// - Throws: sqlite 或 jsonl 初始化失败时上抛。
    static func makeTelemetry(
        appSupport: URL
    ) throws -> (cost: CostAccounting, audit: any AuditLogProtocol) {
        let cost = try CostAccounting(dbURL: appSupport.appendingPathComponent("cost.sqlite"))
        let audit: any AuditLogProtocol = try JSONLAuditLog(
            fileURL: appSupport.appendingPathComponent("audit.jsonl")
        )
        return (cost, audit)
    }

    /// 创建生产上下文 provider 注册表。
    ///
    /// - Returns: 包含 Task 7 五个核心 provider 的 registry。
    static func makeContextProviderRegistry() -> ContextProviderRegistry {
        let providers: [String: any ContextProvider] = [
            "selection": SelectionContextProvider(),
            "app.windowTitle": AppWindowTitleContextProvider(),
            "app.url": AppURLContextProvider(),
            "clipboard.current": ClipboardCurrentContextProvider(
                readString: AppContextAdapters.readClipboardString
            ),
            "file.read": FileReadContextProvider(sandbox: PathSandbox())
        ]
        return ContextProviderRegistry(providers: providers)
    }

    /// 创建选区捕获服务：AX 为主路径，剪贴板为 fallback。
    ///
    /// - Returns: 完整配置 primary/fallback 的 `SelectionService`。
    static func makeSelectionService() -> SelectionService {
        SelectionService(
            primary: AXSelectionSource(),
            fallback: ClipboardSelectionSource(
                pasteboard: SystemPasteboard(),
                copyInvoker: SystemCopyKeystrokeInvoker(),
                focusProvider: { @MainActor in
                    guard let app = NSWorkspace.shared.frontmostApplication else {
                        return nil
                    }
                    return FocusInfo(
                        bundleID: app.bundleIdentifier ?? "",
                        appName: app.localizedName ?? "",
                        url: nil,
                        screenPoint: NSEvent.mouseLocation
                    )
                }
            )
        )
    }

    /// 创建 ThemeManager，并把外观变化持久化回 v2 配置。
    ///
    /// - Parameter configStore: v2 配置存储。
    /// - Returns: 初始为 `.auto` 的主题管理器。
    static func makeThemeManager(configStore: ConfigurationStore) -> ThemeManager {
        let themeManager = ThemeManager(initialMode: .auto)
        themeManager.onModeChange = { @MainActor mode in
            Task {
                do {
                    // 磁盘写失败不阻断 UI 切换；后续 Settings 保存路径仍会暴露真实错误。
                    var configuration = try await configStore.current()
                    configuration.appearance = mode
                    try await configStore.update(configuration)
                } catch {
                    // 主题 UI 已即时切换，配置写盘失败不打断用户操作。
                }
            }
        }
        return themeManager
    }

    /// 创建 `~/Library/Application Support/SliceAI/` 目录。
    ///
    /// - Returns: SliceAI app support 目录 URL。
    /// - Throws: 目录创建失败时上抛，由 AppDelegate 转为启动失败 alert。
    static func makeAppSupportDir() throws -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }

    /// 创建生产 SkillRegistry，并从配置存储读取最新 skill settings。
    static func makeSkillRegistry(configStore: ConfigurationStore) -> any SkillRegistryProtocol {
        LocalSkillRegistry(settingsProvider: { [configStore] in
            do {
                return try await configStore.current().skillSettings
            } catch {
                print("[AppContainer] skill settings load failed - \(error.localizedDescription)")
                return .empty
            }
        })
    }

    /// 创建生产 SideEffectExecutor。
    static func makeSideEffectExecutor(mcpClient: any MCPClientProtocol) -> any SideEffectExecutorProtocol {
        SideEffectExecutor(
            clipboard: AppClipboardWriter(),
            notifier: AppUserNotifier(),
            speaker: AVSpeechTTSCapability(),
            mcpClient: mcpClient,
            pathSandbox: PathSandbox()
        )
    }

    /// 创建生产 v2 `ExecutionEngine`，集中保留 runtime 依赖的装配边界。
    ///
    /// - Parameter dependencies: 创建执行引擎所需的 v2 内部依赖集合。
    /// - Returns: 完整装配但尚未接入 caller 的 v2 执行引擎。
    static func makeExecutionEngine(dependencies: ExecutionEngineDependencies) -> ExecutionEngine {
        ExecutionEngine(
            contextCollector: ContextCollector(registry: dependencies.providerRegistry),
            permissionBroker: dependencies.permissionBroker,
            permissionGraph: PermissionGraph(providerRegistry: dependencies.providerRegistry),
            providerResolver: dependencies.providerResolver,
            promptExecutor: dependencies.promptExecutor,
            mcpClient: dependencies.mcpClient,
            skillRegistry: dependencies.skillRegistry,
            costAccounting: dependencies.costAccounting,
            auditLog: dependencies.auditLog,
            output: dependencies.outputDispatcher,
            agentExecutor: dependencies.agentExecutor,
            sideEffectExecutor: dependencies.sideEffectExecutor
        )
    }

    /// 创建 Settings Playground 专用 runner。
    ///
    /// Playground 复用生产上下文、权限、Provider、Prompt、MCP、Skill、Cost 和 Audit 依赖；
    /// 只替换输出 dispatcher，并禁用 side effect executor，避免试跑污染生产 UI 或外部状态。
    ///
    /// - Parameter dependencies: 生产执行引擎依赖集合。
    /// - Returns: 可注入 SettingsUI 的 Playground runner。
    static func makePlaygroundRunner(
        dependencies: ExecutionEngineDependencies
    ) -> any ToolPlaygroundRunning {
        let previewEngine = ExecutionEngine(
            contextCollector: ContextCollector(registry: dependencies.providerRegistry),
            permissionBroker: dependencies.permissionBroker,
            permissionGraph: PermissionGraph(providerRegistry: dependencies.providerRegistry),
            providerResolver: dependencies.providerResolver,
            promptExecutor: dependencies.promptExecutor,
            mcpClient: dependencies.mcpClient,
            skillRegistry: dependencies.skillRegistry,
            costAccounting: dependencies.costAccounting,
            auditLog: dependencies.auditLog,
            output: PlaygroundOutputDispatcher(),
            agentExecutor: dependencies.agentExecutor,
            sideEffectExecutor: nil
        )
        return ToolPlaygroundRunner(engine: previewEngine)
    }
}
