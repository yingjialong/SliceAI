// SliceAIApp/AppContainer.swift
import AppKit
import Capabilities
import DesignSystem
import Foundation
import HotkeyManager
import LLMProviders
import Orchestration
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

    /// 创建 `ExecutionEngine` 所需的内部依赖集合，避免 helper 参数列表继续膨胀。
    private struct ExecutionEngineDependencies {
        let providerRegistry: ContextProviderRegistry
        let permissionBroker: any PermissionBrokerProtocol
        let providerResolver: any ProviderResolverProtocol
        let promptExecutor: PromptExecutor
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
        let ui = makeUIDependencies(
            configStore: configStore,
            keychain: keychain
        )
        let v2Runtime = try await makeV2RuntimeDependencies(
            appSupport: appSupport,
            configStore: configStore,
            keychain: keychain,
            llmProviderFactory: llmProviderFactory,
            resultPanel: ui.resultPanel
        )

        return AppContainer(
            configStore: configStore,
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
        keychain: KeychainStore
    ) -> UIDependencies {
        UIDependencies(
            keychain: keychain,
            selectionService: makeSelectionService(),
            hotkeyRegistrar: HotkeyRegistrar(),
            floatingToolbar: FloatingToolbarPanel(),
            commandPalette: CommandPalettePanel(),
            resultPanel: ResultPanel(),
            accessibilityMonitor: AccessibilityMonitor(),
            settingsViewModel: SettingsViewModel(store: configStore, keychain: keychain),
            themeManager: makeThemeManager(configStore: configStore)
        )
    }

    /// 创建 v2 additive runtime，并触发 v2 配置首次加载。
    ///
    /// - Parameters:
    ///   - appSupport: app support 目录，用于持久化 v2 config、audit 和 cost 数据。
    ///   - configStore: 已完成首次加载的 v2 配置存储。
    ///   - keychain: v1/v2 共用的 Keychain 访问器。
    ///   - llmProviderFactory: v1/v2 共用的 LLM provider 工厂。
    ///   - resultPanel: 既有结果面板，作为 v2 window sink 的最终承载。
    /// - Returns: v2 runtime dependency bundle。
    /// - Throws: v2 配置、cost sqlite 或 audit jsonl 初始化失败时上抛。
    private static func makeV2RuntimeDependencies(
        appSupport: URL,
        configStore: ConfigurationStore,
        keychain: KeychainStore,
        llmProviderFactory: any LLMProviderFactory,
        resultPanel: ResultPanel
    ) async throws -> RuntimeDependencies {
        let providerRegistry = ContextProviderRegistry(providers: [:])
        let permissionBroker: any PermissionBrokerProtocol = PermissionBroker(store: PermissionGrantStore())
        let providerResolver: any ProviderResolverProtocol = DefaultProviderResolver(
            configurationProvider: { [configStore] in try await configStore.current() }
        )
        let promptExecutor = PromptExecutor(keychain: keychain, llmProviderFactory: llmProviderFactory)
        let costAccounting = try CostAccounting(dbURL: appSupport.appendingPathComponent("cost.sqlite"))
        let auditLog: any AuditLogProtocol = try JSONLAuditLog(
            fileURL: appSupport.appendingPathComponent("audit.jsonl")
        )
        let invocationGate = InvocationGate()
        let resultPanelAdapter = ResultPanelWindowSinkAdapter(panel: resultPanel, gate: invocationGate)
        let outputDispatcher: any OutputDispatcherProtocol = OutputDispatcher(windowSink: resultPanelAdapter)
        let engineDependencies = ExecutionEngineDependencies(
            providerRegistry: providerRegistry,
            permissionBroker: permissionBroker,
            providerResolver: providerResolver,
            promptExecutor: promptExecutor,
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

    /// 创建 v2 `ExecutionEngine`，集中保留 mock MCP/Skill 依赖的边界。
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
            mcpClient: MockMCPClient(),
            skillRegistry: MockSkillRegistry(),
            costAccounting: dependencies.costAccounting,
            auditLog: dependencies.auditLog,
            output: dependencies.outputDispatcher
        )
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
