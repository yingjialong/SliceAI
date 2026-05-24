import Capabilities
import Foundation
import SliceCore
import SwiftUI

/// Skills 设置页视图模型。
///
/// 负责把 `Configuration.skillSettings` 的 source / override 编辑持久化，
/// 并从 `SkillRegistryProtocol` 读取可展示的 skills 与 diagnostics。
@MainActor
public final class SkillsViewModel: ObservableObject {

    /// 当前配置中的 source 列表，按 `order` 升序展示。
    @Published public private(set) var sources: [SkillSource]

    /// 当前 registry 快照中的 skills，已套用本地 override 用于 UI 展示。
    @Published public private(set) var skills: [SliceCore.Skill] = []

    /// 当前 registry 快照中的诊断信息。
    @Published public private(set) var diagnostics: [SkillRegistryDiagnostic] = []

    /// 最近一次刷新或保存失败的错误文案。
    @Published public private(set) var errorMessage: String?

    /// 是否正在刷新 registry 快照。
    @Published public private(set) var isReloading = false

    /// Settings 主 VM，作为配置持久化的唯一入口。
    private let settingsViewModel: SettingsViewModel

    /// Skill registry，生产路径为本地扫描实现，测试可注入固定快照。
    private let skillRegistry: any SkillRegistryProtocol

    /// 构造 Skills 设置页 VM。
    /// - Parameters:
    ///   - settingsViewModel: Settings 主 VM。
    ///   - skillRegistry: Skill registry 抽象。
    public init(settingsViewModel: SettingsViewModel, skillRegistry: any SkillRegistryProtocol) {
        self.settingsViewModel = settingsViewModel
        self.skillRegistry = skillRegistry
        self.sources = Self.orderedSources(settingsViewModel.configuration.skillSettings.sources)
    }

    /// 重新加载 source、skills 与 diagnostics。
    ///
    /// source 来自当前配置，skills / diagnostics 来自 registry snapshot。UI 侧调用该方法
    /// 可以在 source 或 override 保存后重新扫描并刷新列表。
    public func reload() async {
        isReloading = true
        defer { isReloading = false }

        sources = Self.orderedSources(settingsViewModel.configuration.skillSettings.sources)
        do {
            let snapshot = try await skillRegistry.snapshot()
            let overrides = settingsViewModel.configuration.skillSettings.overrides
            skills = snapshot.skills
                .map { Self.skill($0, applying: overrides[$0.id]) }
                .sorted { $0.canonicalName.localizedCaseInsensitiveCompare($1.canonicalName) == .orderedAscending }
            diagnostics = snapshot.diagnostics
            errorMessage = nil
            await settingsViewModel.reloadSkills()
            print("[SkillsViewModel] reload: skills=\(skills.count) diagnostics=\(diagnostics.count)")
        } catch {
            skills = []
            diagnostics = []
            errorMessage = error.localizedDescription
            print("[SkillsViewModel] reload: failed – \(error.localizedDescription)")
        }
    }

    /// 添加一个 skill root source。
    /// - Parameter path: 用户选择的目录路径。
    public func addSource(path: String) async {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        guard !settingsViewModel.configuration.skillSettings.sources.contains(where: { $0.rootPath == trimmed }) else {
            print("[SkillsViewModel] addSource: duplicate path ignored")
            return
        }

        let url = URL(fileURLWithPath: trimmed)
        var updated = Self.orderedSources(settingsViewModel.configuration.skillSettings.sources)
        updated.append(SkillSource(
            id: "source-\(UUID().uuidString)",
            displayName: url.lastPathComponent.isEmpty ? trimmed : url.lastPathComponent,
            rootPath: trimmed,
            isEnabled: true,
            order: updated.count
        ))
        await persistSources(updated, operation: "addSource")
    }

    /// 删除一个 skill root source。
    /// - Parameter id: source id。
    public func removeSource(id: String) async {
        let updated = Self.orderedSources(settingsViewModel.configuration.skillSettings.sources)
            .filter { $0.id != id }
        await persistSources(updated, operation: "removeSource")
    }

    /// 移动 skill root source 顺序。
    /// - Parameters:
    ///   - source: SwiftUI `onMove` 的源索引集合。
    ///   - destination: SwiftUI `onMove` 的目标索引。
    public func moveSource(fromOffsets source: IndexSet, toOffset destination: Int) async {
        var updated = Self.orderedSources(settingsViewModel.configuration.skillSettings.sources)
        updated.move(fromOffsets: source, toOffset: destination)
        await persistSources(updated, operation: "moveSource")
    }

    /// 设置或清除单个 skill 的启停 override。
    /// - Parameters:
    ///   - override: `.on` / `.off`；传 nil 表示恢复默认。
    ///   - skillID: skill id。
    public func setOverride(_ override: SkillEnablementOverride?, for skillID: String) async {
        if let override {
            settingsViewModel.configuration.skillSettings.overrides[skillID] = override
        } else {
            settingsViewModel.configuration.skillSettings.overrides.removeValue(forKey: skillID)
        }
        await persistSettings(operation: "setOverride")
    }

    /// 读取当前配置中的 skill override。
    /// - Parameter skillID: skill id。
    /// - Returns: `.on` / `.off`；未设置时返回 nil。
    public func override(for skillID: String) -> SkillEnablementOverride? {
        settingsViewModel.configuration.skillSettings.overrides[skillID]
    }

    /// 持久化 source 列表，并统一重排 `order`。
    /// - Parameters:
    ///   - sources: 待保存的 source 列表。
    ///   - operation: 日志中的操作名。
    private func persistSources(_ sources: [SkillSource], operation: String) async {
        settingsViewModel.configuration.skillSettings.sources = Self.reindexed(sources)
        await persistSettings(operation: operation)
    }

    /// 持久化当前 skillSettings，并刷新页面状态。
    /// - Parameter operation: 日志中的操作名。
    private func persistSettings(operation: String) async {
        do {
            try await settingsViewModel.save()
            print("[SkillsViewModel] \(operation): persisted")
            await reload()
        } catch {
            errorMessage = error.localizedDescription
            print("[SkillsViewModel] \(operation): persist failed – \(error.localizedDescription)")
        }
    }

    /// 对 source 按 order 升序排序。
    /// - Parameter sources: 原始 source 列表。
    /// - Returns: 排序后的 source 列表。
    private static func orderedSources(_ sources: [SkillSource]) -> [SkillSource] {
        sources.sorted {
            if $0.order == $1.order {
                return $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
            return $0.order < $1.order
        }
    }

    /// 重排 source.order，保证配置文件中的顺序稳定。
    /// - Parameter sources: 当前展示顺序的 source 列表。
    /// - Returns: order 从 0 递增的 source 列表。
    private static func reindexed(_ sources: [SkillSource]) -> [SkillSource] {
        sources.enumerated().map { index, source in
            var copy = source
            copy.order = index
            return copy
        }
    }

    /// 根据 override 生成 UI 展示用 skill 状态。
    /// - Parameters:
    ///   - skill: registry 原始 skill。
    ///   - override: 配置中的 override。
    /// - Returns: 套用 override 后的 skill。
    private static func skill(
        _ skill: SliceCore.Skill,
        applying override: SkillEnablementOverride?
    ) -> SliceCore.Skill {
        var updated = skill
        switch override {
        case .on:
            updated.state = .enabled
        case .off:
            updated.state = .disabled
        case .none:
            break
        }
        return updated
    }
}
