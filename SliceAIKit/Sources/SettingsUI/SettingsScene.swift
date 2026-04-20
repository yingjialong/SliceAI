// SliceAIKit/Sources/SettingsUI/SettingsScene.swift
import SwiftUI
import SliceCore

/// 设置主界面：Tools / Providers / Hotkeys / Triggers 四个标签页
///
/// 由 `SettingsViewModel` 提供数据，视图内只做编排，不直接访问磁盘或 Keychain。
///
/// 保存逻辑抽离到底部全局保存栏（`saveBar`），四个标签页共用同一套保存入口，
/// 避免出现“只在 Tools 页有保存按钮、切到其它标签页改动丢失”的问题。
public struct SettingsScene: View {

    /// 设置视图模型；由宿主创建并注入，保证生命周期与窗口一致
    @ObservedObject var viewModel: SettingsViewModel

    /// Tools 标签页当前选中的 Tool id
    @State private var selectedToolID: String?

    /// Providers 标签页当前选中的 Provider id
    @State private var selectedProviderID: String?

    /// 底部保存栏当前展示的状态消息（成功 / 失败 / nil 表示无消息）
    @State private var saveMessage: SaveMessage?

    /// 底部保存栏展示的消息载体
    ///
    /// - `text`: 展示给用户看的中文提示；
    /// - `isError`: 控制文案颜色（红 or 次要灰）与自动清除策略。
    ///   仅当 `isError == false`（成功态）时，`save()` 中会在 2 秒后自动清除该消息，
    ///   避免成功提示长期占位；错误消息保留展示，直到下一次保存覆盖它。
    private struct SaveMessage: Equatable {
        let text: String
        let isError: Bool
    }

    /// 构造设置主视图
    /// - Parameter viewModel: 由宿主创建的设置视图模型
    public init(viewModel: SettingsViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        // 外层 VStack 让 TabView 和底部保存栏共存；TabView 自己占据剩余空间，
        // Divider + saveBar 固定在窗口底部，所有标签页共用。
        VStack(spacing: 0) {
            TabView {
                toolsTab.tabItem { Label("Tools", systemImage: "hammer") }
                providersTab.tabItem { Label("Providers", systemImage: "network") }
                hotkeyTab.tabItem { Label("Hotkeys", systemImage: "keyboard") }
                triggersTab.tabItem { Label("Triggers", systemImage: "cursorarrow.click") }
            }
            Divider()
            saveBar
        }
        // 增加 ~40px 高度容纳底部保存栏
        .frame(width: 720, height: 520)
    }

    // MARK: - Tabs

    /// Tools 标签页：左侧列表 + 右侧编辑表单，顶部工具栏负责新增 / 保存
    private var toolsTab: some View {
        HSplitView {
            toolsList
            toolsDetail
        }
        .toolbar { toolsToolbar }
    }

    /// Tools 列表，支持选择和删除
    private var toolsList: some View {
        List(selection: $selectedToolID) {
            ForEach($viewModel.configuration.tools) { $tool in
                HStack {
                    Text(tool.icon)
                    Text(tool.name)
                }
                .tag(tool.id as String?)
            }
            .onDelete { offsets in
                viewModel.configuration.tools.remove(atOffsets: offsets)
            }
        }
        .frame(minWidth: 200)
    }

    /// Tools 右侧编辑区：根据选中 id 渲染 ToolEditorView 或占位
    @ViewBuilder
    private var toolsDetail: some View {
        if let id = selectedToolID,
           let idx = viewModel.configuration.tools.firstIndex(where: { $0.id == id }) {
            ToolEditorView(
                tool: $viewModel.configuration.tools[idx],
                providers: viewModel.configuration.providers
            )
        } else {
            Text("Select a tool")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Tools 顶部工具栏：仅保留新增按钮；保存按钮已移至全局底部保存栏
    @ToolbarContentBuilder
    private var toolsToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                addTool()
            } label: {
                Image(systemName: "plus")
            }
            .help("新增 Tool")
        }
    }

    /// 新增 Tool：默认绑定到第一个 Provider（若存在）并把列表选中切到新条目
    private func addTool() {
        let firstProviderId = viewModel.configuration.providers.first?.id ?? ""
        let new = Tool(
            id: UUID().uuidString,
            name: "New Tool",
            icon: "⚡",
            description: nil,
            systemPrompt: nil,
            userPrompt: "{{selection}}",
            providerId: firstProviderId,
            modelId: nil,
            temperature: 0.3,
            displayMode: .window,
            variables: [:]
        )
        viewModel.configuration.tools.append(new)
        selectedToolID = new.id
    }

    /// Providers 标签页：左侧列表 + 右侧编辑表单；顶部工具栏负责新增 / 删除
    private var providersTab: some View {
        HSplitView {
            providersList
            providersDetail
        }
        .toolbar { providersToolbar }
    }

    /// Providers 列表，左侧窄栏展示当前所有 Provider 供选择
    private var providersList: some View {
        List(selection: $selectedProviderID) {
            ForEach($viewModel.configuration.providers) { $provider in
                Text(provider.name).tag(provider.id as String?)
            }
        }
        .frame(minWidth: 200)
    }

    /// Providers 顶部工具栏：新增按钮 + 删除按钮
    ///
    /// 与 Tools 工具栏保持一致的“加号/减号”交互，对应规格 §1.4 关于
    /// “用户能在 Settings 界面添加新工具 / 新供应商”的要求。
    @ToolbarContentBuilder
    private var providersToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button {
                addProvider()
            } label: {
                Image(systemName: "plus")
            }
            .help("新增 Provider")

            Button {
                deleteSelectedProvider()
            } label: {
                Image(systemName: "minus")
            }
            .disabled(selectedProviderID == nil)
            .help("删除选中的 Provider")
        }
    }

    /// 新增 Provider：使用 UUID 作为 id，默认 `apiKeyRef = keychain:<id>`
    ///
    /// 这样与 `SettingsViewModel.setAPIKey` 解析 keychain account 的约定一致，
    /// 新建后用户在编辑器里填入 API Key 即可直接写入 Keychain，不需要再改
    /// `apiKeyRef`。baseURL 使用 OpenAI 官方地址作为最常见缺省，用户可在
    /// 详情面板中修改。
    private func addProvider() {
        let newId = UUID().uuidString
        guard let defaultURL = URL(string: "https://api.openai.com/v1") else {
            // URL 字面量恒合法，理论不可达；保底不崩溃，直接返回
            return
        }
        let new = Provider(
            id: newId,
            name: "New Provider",
            baseURL: defaultURL,
            apiKeyRef: "\(Provider.keychainRefPrefix)\(newId)",
            defaultModel: "gpt-5"
        )
        viewModel.configuration.providers.append(new)
        selectedProviderID = newId
    }

    /// 删除当前选中 Provider；删除后清空选中态，避免右侧详情指向无效 id
    ///
    /// 注意：此处并不主动清理 Keychain 中对应 account 的 API Key；
    /// 保留密钥槽位是为了让“误删 -> 再新建同 id Provider”的场景依旧可用。
    /// 如果未来需要彻底清理，可在 ViewModel 层加显式清除方法。
    private func deleteSelectedProvider() {
        guard let id = selectedProviderID,
              let idx = viewModel.configuration.providers.firstIndex(where: { $0.id == id }) else {
            return
        }
        viewModel.configuration.providers.remove(at: idx)
        selectedProviderID = nil
    }

    /// Providers 右侧编辑区：根据选中 id 渲染 ProviderEditorView 或占位
    ///
    /// 注意：`onSaveKey` / `onLoadKey` 闭包通过值捕获当前 `provider` 快照，
    /// 让 Keychain 读写的 account 与 `Provider.apiKeyRef` 保持一致，
    /// 这样写入槽位与 `ToolExecutor` 读取槽位对齐，避免 provider.id 与
    /// `apiKeyRef` 指向的 account 不一致时出现“写入后读不到密钥”的情况。
    ///
    /// 值捕获的副作用：若用户在编辑器中修改 `apiKeyRef` 后立即点 Save，
    /// 由于 SwiftUI 对 `$viewModel.configuration.providers` 的绑定改动会重建
    /// 该分支视图与闭包，捕获到的是“最新一次渲染时”的 provider 快照，
    /// 因此在本轮交互下是安全的。
    @ViewBuilder
    private var providersDetail: some View {
        if let id = selectedProviderID,
           let idx = viewModel.configuration.providers.firstIndex(where: { $0.id == id }) {
            // 捕获 provider 值而非 id，确保闭包使用的是当下快照的 apiKeyRef
            let provider = viewModel.configuration.providers[idx]
            ProviderEditorView(
                provider: $viewModel.configuration.providers[idx],
                onSaveKey: { [vm = viewModel, provider] key in
                    try? await vm.setAPIKey(key, for: provider)
                },
                onLoadKey: { [vm = viewModel, provider] in
                    (try? await vm.readAPIKey(for: provider)) ?? nil
                }
            )
        } else {
            Text("Select a provider")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
        }
    }

    /// Hotkeys 标签页：当前只暴露命令面板快捷键
    private var hotkeyTab: some View {
        HotkeyEditorView(binding: $viewModel.configuration.hotkeys.toggleCommandPalette)
    }

    /// Triggers 标签页：划词/命令面板的启用开关与阈值
    private var triggersTab: some View {
        Form {
            Toggle(
                "Floating Toolbar 启用",
                isOn: $viewModel.configuration.triggers.floatingToolbarEnabled
            )
            Toggle(
                "Command Palette 启用",
                isOn: $viewModel.configuration.triggers.commandPaletteEnabled
            )
            Stepper(
                "最小选中长度: \(viewModel.configuration.triggers.minimumSelectionLength)",
                value: $viewModel.configuration.triggers.minimumSelectionLength,
                in: 1...100
            )
            Stepper(
                "触发延迟: \(viewModel.configuration.triggers.triggerDelayMs) ms",
                value: $viewModel.configuration.triggers.triggerDelayMs,
                in: 0...2000,
                step: 50
            )
        }
        .formStyle(.grouped)
        .padding()
    }

    // MARK: - Global Save Bar

    /// 全局底部保存栏：左侧状态消息 + 右侧保存按钮
    ///
    /// 所有四个标签页共用该保存入口，绑定 `⌘S` 快捷键满足 macOS 习惯。
    /// 保存结果通过 `saveMessage` 展示在左侧：成功 2 秒后自动消失，
    /// 失败文案使用红色并保留直到下一次保存覆盖。
    private var saveBar: some View {
        HStack(spacing: 12) {
            if let msg = saveMessage {
                Text(msg.text)
                    .font(.caption)
                    .foregroundStyle(msg.isError ? Color.red : Color.secondary)
                    .lineLimit(1)
            }
            Spacer()
            Button("保存") {
                Task { await save() }
            }
            .keyboardShortcut("s", modifiers: .command)
            .help("保存当前设置（⌘S）")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// 执行保存：调用 ViewModel.save()，根据结果更新底部保存栏文案
    ///
    /// 成功分支会延迟 2 秒后自动清除成功消息；延迟期间如果已经被一次新的
    /// 错误覆盖（`saveMessage?.isError == true`），则跳过清除，避免把错误
    /// 提示覆盖回空。
    private func save() async {
        do {
            try await viewModel.save()
            saveMessage = SaveMessage(text: "已保存", isError: false)
            // 2 秒后自动清除成功消息；错误消息保留直到下一次保存
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if saveMessage?.isError == false {
                saveMessage = nil
            }
        } catch {
            saveMessage = SaveMessage(
                text: "保存失败: \(error.localizedDescription)",
                isError: true
            )
        }
    }
}
