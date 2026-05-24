// SliceAIApp/AppContainer.swift
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

/// 应用的依赖注入组合根（Composition Root）。
///
/// 职责：
///   - 在应用启动的单点集中创建所有跨模块依赖，避免在业务层四处分散 `init`；
///   - 对外暴露只读属性，让 `AppDelegate` 在整个生命周期内持有并读取；
///   - 通过显式依赖注入，使 Swift 6 严格并发下的 `Sendable` 边界清晰可控。
///
/// M3.0 Step 1 状态：
///   - `configStore` 已切到 `ConfigurationStore`；
///   - 触发链通过 `ExecutionEngine` 执行 Tool；
///   - 旧配置存储与旧执行器装配已从 App 组合根移除。
///
/// 线程模型：`@MainActor` 限定，保证所有 UI 面板 / 监视器的创建都发生在主线程。
/// 生命周期：由 `AppDelegate.applicationDidFinishLaunching` 异步调用 `bootstrap()` 创建一次。
@MainActor
final class AppContainer {

    // MARK: - v2 配置与执行链

    /// v2 配置文件读写 actor；路径固定为 config-v2.json，保留 legacy config.json 迁移入口
    let configStore: ConfigurationStore
    /// 生产 SkillRegistry；Settings、AgentExecutor 和 ExecutionEngine 共用同一个实例
    let skillRegistry: any SkillRegistryProtocol
    /// v2 执行引擎；AppDelegate 触发链通过它消费 ExecutionEvent stream
    let executionEngine: ExecutionEngine
    /// chunk 路由 dispatcher；window 模式最终投递到 ResultPanel adapter
    let outputDispatcher: any OutputDispatcherProtocol
    /// single-flight gate；同一实例由 AppDelegate 与 ResultPanel adapter 共用
    let invocationGate: InvocationGate
    /// ResultPanel window sink adapter；把 OutputDispatcher 的 window chunk 投递到既有面板
    let resultPanelAdapter: ResultPanelWindowSinkAdapter
    // MARK: - 既有跨层依赖

    /// macOS Keychain 读写结构体；按 providerId 查 API Key
    let keychain: KeychainStore
    /// 选中文字捕获协调器；AX 为主、Clipboard 为备
    let selectionService: SelectionService
    /// 全局快捷键注册器（Carbon）
    let hotkeyRegistrar: HotkeyRegistrar
    /// 划词浮条面板（A 模式）
    let floatingToolbar: FloatingToolbarPanel
    /// 命令面板（Option+Space 调出）
    let commandPalette: CommandPalettePanel
    /// 流式结果面板
    let resultPanel: ResultPanel
    /// 辅助功能权限轮询监视器
    let accessibilityMonitor: AccessibilityMonitor
    /// 设置界面视图模型
    let settingsViewModel: SettingsViewModel
    /// 主题管理器：持有当前 AppearanceMode，驱动 SwiftUI ColorScheme 与 NSAppearance
    let themeManager: ThemeManager

    /// 私有构造函数；外部必须通过 `bootstrap()` 完成 async/throwing 装配。
    ///
    /// 参数较多是 composition root 的合理成本：依赖在这里集中显式注入，避免在业务层隐藏创建逻辑。
    private init(
        configStore: ConfigurationStore,
        skillRegistry: any SkillRegistryProtocol,
        keychain: KeychainStore,
        selectionService: SelectionService,
        hotkeyRegistrar: HotkeyRegistrar,
        floatingToolbar: FloatingToolbarPanel,
        commandPalette: CommandPalettePanel,
        resultPanel: ResultPanel,
        accessibilityMonitor: AccessibilityMonitor,
        settingsViewModel: SettingsViewModel,
        themeManager: ThemeManager,
        executionEngine: ExecutionEngine,
        outputDispatcher: any OutputDispatcherProtocol,
        invocationGate: InvocationGate,
        resultPanelAdapter: ResultPanelWindowSinkAdapter
    ) {
        self.configStore = configStore
        self.skillRegistry = skillRegistry
        self.keychain = keychain
        self.selectionService = selectionService
        self.hotkeyRegistrar = hotkeyRegistrar
        self.floatingToolbar = floatingToolbar
        self.commandPalette = commandPalette
        self.resultPanel = resultPanel
        self.accessibilityMonitor = accessibilityMonitor
        self.settingsViewModel = settingsViewModel
        self.themeManager = themeManager
        self.executionEngine = executionEngine
        self.outputDispatcher = outputDispatcher
        self.invocationGate = invocationGate
        self.resultPanelAdapter = resultPanelAdapter
    }

    /// bootstrap 期间创建出的 UI 依赖集合。
    private struct UIDependencies {
        let keychain: KeychainStore
        let selectionService: SelectionService
        let hotkeyRegistrar: HotkeyRegistrar
        let floatingToolbar: FloatingToolbarPanel
        let commandPalette: CommandPalettePanel
        let resultPanel: ResultPanel
        let accessibilityMonitor: AccessibilityMonitor
        let settingsViewModel: SettingsViewModel
        let themeManager: ThemeManager
    }

    /// bootstrap 期间创建出的 v2 runtime 依赖集合。
    private struct RuntimeDependencies {
        let executionEngine: ExecutionEngine
        let outputDispatcher: any OutputDispatcherProtocol
        let invocationGate: InvocationGate
        let resultPanelAdapter: ResultPanelWindowSinkAdapter
    }

    /// 创建 v2 runtime 所需的输入依赖集合，避免 helper 参数列表持续膨胀。
    private struct V2RuntimeDependencyInputs {
        let appSupport: URL
        let configStore: ConfigurationStore
        let keychain: KeychainStore
        let llmProviderFactory: any LLMProviderFactory
        let resultPanel: ResultPanel
        let skillRegistry: any SkillRegistryProtocol
    }

    /// 创建 `ExecutionEngine` 所需的内部依赖集合，避免 helper 参数列表继续膨胀。
    private struct ExecutionEngineDependencies {
        let providerRegistry: ContextProviderRegistry
        let permissionBroker: any PermissionBrokerProtocol
        let providerResolver: any ProviderResolverProtocol
        let promptExecutor: PromptExecutor
        let agentExecutor: AgentExecutor
        let mcpClient: any MCPClientProtocol
        let skillRegistry: any SkillRegistryProtocol
        let costAccounting: CostAccounting
        let auditLog: any AuditLogProtocol
        let outputDispatcher: any OutputDispatcherProtocol
    }

    /// 异步装配所有依赖，并触发 v2 配置的首次加载 / 迁移 / 默认写盘。
    ///
    /// - Returns: 完整装配后的应用容器。
    /// - Throws: app support 目录创建、v2 配置加载、cost sqlite 或 audit jsonl 初始化失败时上抛。
    static func bootstrap() async throws -> AppContainer {
        let appSupport = try makeAppSupportDir()
        let configStore = ConfigurationStore(
            fileURL: appSupport.appendingPathComponent("config-v2.json"),
            legacyFileURL: appSupport.appendingPathComponent("config.json")
        )
        // 启动期 fail-fast：迁移 legacy 或首次写默认 config-v2.json，并把错误交给 AppDelegate alert。
        _ = try await configStore.current()

        let keychain = KeychainStore()
        let llmProviderFactory: any LLMProviderFactory = OpenAIProviderFactory()
        let skillRegistry = makeSkillRegistry(configStore: configStore)
        let ui = makeUIDependencies(
            configStore: configStore,
            keychain: keychain,
            skillRegistry: skillRegistry
        )
        let v2Runtime = try await makeV2RuntimeDependencies(inputs: V2RuntimeDependencyInputs(
            appSupport: appSupport,
            configStore: configStore,
            keychain: keychain,
            llmProviderFactory: llmProviderFactory,
            resultPanel: ui.resultPanel,
            skillRegistry: skillRegistry
        ))

        return AppContainer(
            configStore: configStore,
            skillRegistry: skillRegistry,
            keychain: keychain,
            selectionService: ui.selectionService,
            hotkeyRegistrar: ui.hotkeyRegistrar,
            floatingToolbar: ui.floatingToolbar,
            commandPalette: ui.commandPalette,
            resultPanel: ui.resultPanel,
            accessibilityMonitor: ui.accessibilityMonitor,
            settingsViewModel: ui.settingsViewModel,
            themeManager: ui.themeManager,
            executionEngine: v2Runtime.executionEngine,
            outputDispatcher: v2Runtime.outputDispatcher,
            invocationGate: v2Runtime.invocationGate,
            resultPanelAdapter: v2Runtime.resultPanelAdapter
        )
    }

    /// 创建 UI 面板和 Settings 依赖。
    ///
    /// - Parameters:
    ///   - configStore: v2 配置存储，SettingsUI 与 ThemeManager 共用。
    ///   - keychain: Keychain 访问器。
    /// - Returns: `AppDelegate` 使用的 UI dependency bundle。
    private static func makeUIDependencies(
        configStore: ConfigurationStore,
        keychain: KeychainStore,
        skillRegistry: any SkillRegistryProtocol
    ) -> UIDependencies {
        UIDependencies(
            keychain: keychain,
            selectionService: makeSelectionService(),
            hotkeyRegistrar: HotkeyRegistrar(),
            floatingToolbar: FloatingToolbarPanel(),
            commandPalette: CommandPalettePanel(),
            resultPanel: ResultPanel(),
            accessibilityMonitor: AccessibilityMonitor(),
            settingsViewModel: SettingsViewModel(
                store: configStore,
                keychain: keychain,
                skillRegistry: skillRegistry
            ),
            themeManager: makeThemeManager(configStore: configStore)
        )
    }

    /// 创建生产 SkillRegistry，并从配置存储读取最新 skill settings。
    private static func makeSkillRegistry(configStore: ConfigurationStore) -> any SkillRegistryProtocol {
        LocalSkillRegistry(settingsProvider: { [configStore] in
            do {
                return try await configStore.current().skillSettings
            } catch {
                print("[AppContainer] skill settings load failed - \(error.localizedDescription)")
                return .empty
            }
        })
    }

    /// 创建 v2 additive runtime，并触发 v2 配置首次加载。
    ///
    /// - Parameter inputs: v2 runtime 装配所需的输入依赖集合。
    /// - Returns: v2 runtime dependency bundle。
    /// - Throws: v2 配置、cost sqlite 或 audit jsonl 初始化失败时上抛。
    private static func makeV2RuntimeDependencies(
        inputs: V2RuntimeDependencyInputs
    ) async throws -> RuntimeDependencies {
        let providerRegistry = makeContextProviderRegistry()
        let permissionBroker = makePermissionBroker(appSupport: inputs.appSupport)
        let mcpRuntime = makeMCPRuntime(appSupport: inputs.appSupport)
        let providerResolver = makeProviderResolver(configStore: inputs.configStore)
        let promptExecutor = PromptExecutor(
            keychain: inputs.keychain,
            llmProviderFactory: inputs.llmProviderFactory
        )
        let agentExecutor = makeAgentExecutor(
            providerResolver: providerResolver,
            mcpRuntime: mcpRuntime,
            permissionBroker: permissionBroker,
            inputs: inputs
        )
        let costAccounting = try CostAccounting(dbURL: inputs.appSupport.appendingPathComponent("cost.sqlite"))
        let auditLog: any AuditLogProtocol = try JSONLAuditLog(
            fileURL: inputs.appSupport.appendingPathComponent("audit.jsonl")
        )
        let invocationGate = InvocationGate()
        let resultPanelAdapter = ResultPanelWindowSinkAdapter(panel: inputs.resultPanel, gate: invocationGate)
        let outputDispatcher: any OutputDispatcherProtocol = OutputDispatcher(windowSink: resultPanelAdapter)
        let engineDependencies = ExecutionEngineDependencies(
            providerRegistry: providerRegistry,
            permissionBroker: permissionBroker,
            providerResolver: providerResolver,
            promptExecutor: promptExecutor,
            agentExecutor: agentExecutor,
            mcpClient: mcpRuntime.client,
            skillRegistry: inputs.skillRegistry,
            costAccounting: costAccounting,
            auditLog: auditLog,
            outputDispatcher: outputDispatcher
        )
        let executionEngine = makeExecutionEngine(dependencies: engineDependencies)

        return RuntimeDependencies(
            executionEngine: executionEngine,
            outputDispatcher: outputDispatcher,
            invocationGate: invocationGate,
            resultPanelAdapter: resultPanelAdapter
        )
    }

    /// 创建生产 AgentExecutor，并注入 MCP runtime 与 SkillRegistry。
    private static func makeAgentExecutor(
        providerResolver: any ProviderResolverProtocol,
        mcpRuntime: AppMCPRuntimeDependencies,
        permissionBroker: any PermissionBrokerProtocol,
        inputs: V2RuntimeDependencyInputs
    ) -> AgentExecutor {
        AgentExecutor(
            providerResolver: providerResolver,
            mcpClient: mcpRuntime.client,
            permissionBroker: permissionBroker,
            keychain: inputs.keychain,
            llmProviderFactory: inputs.llmProviderFactory,
            mcpDescriptors: mcpRuntime.descriptorsProvider,
            skillRegistry: inputs.skillRegistry
        )
    }

    /// 创建生产 v2 `ExecutionEngine`，集中保留 runtime 依赖的装配边界。
    ///
    /// - Parameter dependencies: 创建执行引擎所需的 v2 内部依赖集合。
    /// - Returns: 完整装配但尚未接入 caller 的 v2 执行引擎。
    private static func makeExecutionEngine(dependencies: ExecutionEngineDependencies) -> ExecutionEngine {
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
            agentExecutor: dependencies.agentExecutor
        )
    }
}

/// AppContainer 生产 MCP runtime 依赖。
private struct AppMCPRuntimeDependencies {
    let descriptorsProvider: @Sendable () async throws -> [MCPDescriptor]
    let client: any MCPClientProtocol
}

private extension AppContainer {

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

    /// 创建生产上下文 provider 注册表。
    ///
    /// - Returns: 包含 Task 7 五个核心 provider 的 registry。
    private static func makeContextProviderRegistry() -> ContextProviderRegistry {
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
    private static func makeSelectionService() -> SelectionService {
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
    private static func makeThemeManager(configStore: ConfigurationStore) -> ThemeManager {
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
    private static func makeAppSupportDir() throws -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }
}
