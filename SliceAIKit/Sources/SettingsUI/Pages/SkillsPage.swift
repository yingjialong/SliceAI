import AppKit
import Capabilities
import DesignSystem
import SliceCore
import SwiftUI

/// Skills 设置页。
///
/// 展示用户配置的 skill roots、registry skills 与扫描诊断；所有修改通过
/// `SkillsViewModel` 写回 `Configuration.skillSettings`。
public struct SkillsPage: View {

    /// 页面级 VM 使用 StateObject，避免 SettingsScene body 重算导致状态丢失。
    @StateObject private var viewModel: SkillsViewModel

    /// 构造 Skills 设置页。
    /// - Parameters:
    ///   - settingsViewModel: Settings 主 VM。
    ///   - skillRegistry: Skill registry 抽象。
    public init(settingsViewModel: SettingsViewModel, skillRegistry: any SkillRegistryProtocol) {
        _viewModel = StateObject(
            wrappedValue: SkillsViewModel(
                settingsViewModel: settingsViewModel,
                skillRegistry: skillRegistry
            )
        )
    }

    public var body: some View {
        SettingsPageShell(title: "Skills", subtitle: "管理 Skill 来源和启停状态。") {
            actionRow
            sourcesCard
            skillsCard
            diagnosticsCard
        }
        .task {
            await viewModel.reload()
        }
    }

    /// 顶部操作行。
    private var actionRow: some View {
        HStack {
            if viewModel.isReloading {
                ProgressView()
                    .controlSize(.small)
            }
            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(SliceFont.caption)
                    .foregroundColor(.red)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            PillButton("添加目录", icon: "folder.badge.plus", style: .primary) {
                openDirectoryPanel()
            }
        }
    }

    /// Sources 分组。
    private var sourcesCard: some View {
        SectionCard("Sources") {
            if viewModel.sources.isEmpty {
                Text("暂无目录")
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SliceSpacing.sm)
            } else {
                ForEach(Array(viewModel.sources.enumerated()), id: \.element.id) { index, source in
                    sourceRow(source, index: index)
                    if source.id != viewModel.sources.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    /// 单个 source 行。
    /// - Parameters:
    ///   - source: source 数据。
    ///   - index: 当前展示序号。
    /// - Returns: source 行视图。
    private func sourceRow(_ source: SkillSource, index: Int) -> some View {
        HStack(spacing: SliceSpacing.base) {
            Image(systemName: source.isEnabled ? "folder" : "folder.badge.minus")
                .foregroundColor(SliceColor.textSecondary)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.displayName)
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textPrimary)
                Text(source.rootPath)
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: SliceSpacing.base)
            Button {
                Task { await moveSource(at: index, delta: -1) }
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .disabled(index == 0)

            Button {
                Task { await moveSource(at: index, delta: 1) }
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .disabled(index >= viewModel.sources.count - 1)

            Button(role: .destructive) {
                Task { await viewModel.removeSource(id: source.id) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(.vertical, SliceSpacing.xs)
    }

    /// Skills 分组。
    private var skillsCard: some View {
        SectionCard("Skills") {
            if viewModel.skills.isEmpty {
                Text("暂无 Skills")
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SliceSpacing.sm)
            } else {
                ForEach(viewModel.skills) { skill in
                    skillRow(skill)
                    if skill.id != viewModel.skills.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    /// 单个 skill 行。
    /// - Parameter skill: skill 数据。
    /// - Returns: skill 行视图。
    private func skillRow(_ skill: SliceCore.Skill) -> some View {
        HStack(alignment: .top, spacing: SliceSpacing.base) {
            Image(systemName: iconName(for: skill.state))
                .foregroundColor(color(for: skill.state))
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 4) {
                Text(skill.canonicalName)
                    .font(SliceFont.body)
                    .foregroundColor(SliceColor.textPrimary)
                Text(skill.manifest.description)
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textSecondary)
                    .lineLimit(2)
                Text(skill.source.rootPath)
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: SliceSpacing.base)
            Picker("", selection: overrideBinding(for: skill.id)) {
                Text("默认").tag(SkillEnablementOverride?.none)
                Text("启用").tag(SkillEnablementOverride?.some(.on))
                Text("禁用").tag(SkillEnablementOverride?.some(.off))
            }
            .pickerStyle(.menu)
            .labelsHidden()
            .frame(width: 86)
        }
        .padding(.vertical, SliceSpacing.xs)
    }

    /// Diagnostics 分组。
    @ViewBuilder
    private var diagnosticsCard: some View {
        if !viewModel.diagnostics.isEmpty {
            SectionCard("Diagnostics") {
                ForEach(Array(viewModel.diagnostics.enumerated()), id: \.offset) { _, diagnostic in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(diagnostic.code.rawValue)
                            .font(SliceFont.caption)
                            .foregroundColor(.orange)
                        Text(diagnostic.message)
                            .font(SliceFont.body)
                            .foregroundColor(SliceColor.textSecondary)
                        if let path = diagnostic.path {
                            Text(path)
                                .font(SliceFont.caption)
                                .foregroundColor(SliceColor.textTertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, SliceSpacing.xs)
                }
            }
        }
    }

    /// 打开目录选择面板并添加 source。
    private func openDirectoryPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await viewModel.addSource(path: url.path) }
        }
    }

    /// 移动 source。
    /// - Parameters:
    ///   - index: 当前索引。
    ///   - delta: 移动方向，-1 上移，1 下移。
    private func moveSource(at index: Int, delta: Int) async {
        let destination = index + delta
        guard destination >= 0, destination < viewModel.sources.count else { return }
        let toOffset = delta > 0 ? destination + 1 : destination
        await viewModel.moveSource(fromOffsets: IndexSet(integer: index), toOffset: toOffset)
    }

    /// 为 skill override 创建 Picker 绑定。
    /// - Parameter skillID: skill id。
    /// - Returns: override 绑定。
    private func overrideBinding(for skillID: String) -> Binding<SkillEnablementOverride?> {
        Binding(
            get: {
                viewModel.override(for: skillID)
            },
            set: { override in
                Task { await viewModel.setOverride(override, for: skillID) }
            }
        )
    }

    /// skill 状态图标。
    /// - Parameter state: registry state。
    /// - Returns: SF Symbol 名称。
    private func iconName(for state: SkillRegistryState) -> String {
        switch state {
        case .enabled:
            return "checkmark.circle.fill"
        case .disabled, .defaultDisabled:
            return "minus.circle"
        case .parseError, .sourceError, .tooLarge:
            return "exclamationmark.triangle.fill"
        case .shadowed:
            return "square.2.layers.3d"
        }
    }

    /// skill 状态颜色。
    /// - Parameter state: registry state。
    /// - Returns: 展示颜色。
    private func color(for state: SkillRegistryState) -> Color {
        switch state {
        case .enabled:
            return .green
        case .disabled, .defaultDisabled, .shadowed:
            return SliceColor.textTertiary
        case .parseError, .sourceError, .tooLarge:
            return .orange
        }
    }
}
