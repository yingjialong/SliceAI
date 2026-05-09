import DesignSystem
import SliceCore
import SwiftUI

// MARK: - MCPServersPage

/// MCP Servers 设置页。
///
/// 提供本地 `mcp.json` 的 server 列表、stdio server 新增/编辑/删除、Claude Desktop JSON 粘贴导入，
/// 以及基于 `tools/list` 的测试连接预览。页面不提供 legacy SSE 新建入口。
public struct MCPServersPage: View {

    /// MCP Servers 页面内部持有的 ViewModel。
    @StateObject private var viewModel = MCPServersViewModel()

    /// 当前编辑 sheet 会话；nil 表示未打开。
    @State private var editorSession: MCPServerEditorSession?

    /// Claude Desktop JSON 导入 sheet 是否展示。
    @State private var isImportSheetPresented = false

    /// 导入 sheet 中的 JSON 文本。
    @State private var importJSONText = ""

    /// 构造 MCP Servers 设置页。
    public init() {}

    public var body: some View {
        SettingsPageShell(title: "MCP Servers", subtitle: "管理本地 MCP server 与工具预览。") {
            actionRow
            messageArea
            if viewModel.servers.isEmpty {
                emptyState
            } else {
                serverList
            }
        }
        .task {
            await viewModel.reload()
        }
        .sheet(item: $editorSession) { session in
            MCPServerEditorSheet(
                session: session,
                validationMessage: viewModel.validationMessage,
                onCancel: { editorSession = nil },
                onSave: { descriptor, originalID in
                    Task {
                        await viewModel.save(descriptor, replacing: originalID)
                        if viewModel.validationMessage == nil {
                            editorSession = nil
                        }
                    }
                }
            )
        }
        .sheet(isPresented: $isImportSheetPresented) {
            ClaudeDesktopImportSheet(
                jsonText: $importJSONText,
                validationMessage: viewModel.validationMessage,
                onCancel: {
                    importJSONText = ""
                    isImportSheetPresented = false
                },
                onImport: {
                    importClaudeDesktopJSON()
                }
            )
        }
    }

    /// 顶部操作按钮行。
    private var actionRow: some View {
        HStack(spacing: SliceSpacing.base) {
            PillButton("导入 Claude JSON", icon: "square.and.arrow.down", style: .secondary) {
                isImportSheetPresented = true
            }
            PillButton("添加 Server", icon: "plus", style: .primary) {
                openNewServerEditor()
            }
            Spacer()
        }
    }

    /// 页面状态消息区域。
    @ViewBuilder
    private var messageArea: some View {
        if let validationMessage = viewModel.validationMessage {
            MCPStatusBanner(text: validationMessage, isError: true)
        } else if let connectionMessage = viewModel.connectionMessage {
            MCPStatusBanner(text: connectionMessage, isError: false)
        }
    }

    /// 空列表提示。
    private var emptyState: some View {
        SectionCard {
            VStack(spacing: SliceSpacing.base) {
                Image(systemName: "server.rack")
                    .font(.system(size: 28))
                    .foregroundColor(SliceColor.textTertiary)
                Text("暂无 MCP server。")
                    .font(SliceFont.callout)
                    .foregroundColor(SliceColor.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, SliceSpacing.xl)
        }
    }

    /// MCP server 列表卡片。
    private var serverList: some View {
        SectionCard("Servers") {
            VStack(spacing: 0) {
                ForEach(viewModel.servers) { descriptor in
                    MCPServerRow(
                        descriptor: descriptor,
                        tools: viewModel.toolsByServerID[descriptor.id] ?? [],
                        isTesting: viewModel.isTesting(id: descriptor.id),
                        onEdit: { openEditor(for: descriptor) },
                        onTest: {
                            Task {
                                await viewModel.testConnection(id: descriptor.id)
                            }
                        },
                        onDelete: {
                            Task {
                                await viewModel.delete(id: descriptor.id)
                            }
                        }
                    )
                }
            }
        }
    }

    /// 打开新增 server 编辑器。
    private func openNewServerEditor() {
        editorSession = MCPServerEditorSession(draft: .new())
        print("[MCPServersPage] openNewServerEditor")
    }

    /// 打开指定 server 的编辑器。
    /// - Parameter descriptor: 要编辑的 server descriptor。
    private func openEditor(for descriptor: MCPDescriptor) {
        editorSession = MCPServerEditorSession(draft: MCPServerDraft(descriptor: descriptor))
        print("[MCPServersPage] openEditor: id=\(descriptor.id)")
    }

    /// 执行 Claude Desktop JSON 粘贴导入。
    private func importClaudeDesktopJSON() {
        let data = Data(importJSONText.utf8)
        Task {
            await viewModel.importClaudeDesktopConfig(data)
            if viewModel.validationMessage == nil {
                importJSONText = ""
                isImportSheetPresented = false
            }
        }
    }
}

// MARK: - MCPServerRow

/// MCP server 列表行。
private struct MCPServerRow: View {

    /// 当前行展示的 server descriptor。
    let descriptor: MCPDescriptor

    /// 当前 server 最近一次 tools/list 返回的工具列表。
    let tools: [MCPToolDescriptor]

    /// 当前行是否正在测试连接。
    let isTesting: Bool

    /// 编辑按钮回调。
    let onEdit: () -> Void

    /// 测试连接按钮回调。
    let onTest: () -> Void

    /// 删除按钮回调。
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.base) {
            rowHeader
            if tools.isEmpty == false {
                toolPreview
            }
        }
        .padding(.vertical, SliceSpacing.base)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(SliceColor.divider)
                .frame(height: 0.5)
                .padding(.horizontal, -SliceSpacing.xl)
        }
    }

    /// server 行主内容。
    private var rowHeader: some View {
        HStack(spacing: SliceSpacing.base) {
            iconView

            VStack(alignment: .leading, spacing: 3) {
                Text(descriptor.id)
                    .font(SliceFont.subheadline)
                    .foregroundColor(SliceColor.textPrimary)
                    .lineLimit(1)
                Text("\(descriptor.transport.rawValue) · \(MCPProvenanceSummary.text(for: descriptor.provenance))")
                    .font(SliceFont.caption)
                    .foregroundColor(SliceColor.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(SliceColor.textSecondary)

            Button(action: onTest) {
                Image(systemName: isTesting ? "hourglass" : "network")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(SliceColor.accent)
            .disabled(isTesting)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.plain)
            .foregroundColor(SliceColor.error)
        }
    }

    /// server 行左侧图标。
    private var iconView: some View {
        ZStack {
            RoundedRectangle(cornerRadius: SliceRadius.control)
                .fill(SliceColor.hoverFill)
                .frame(width: 32, height: 32)
            Image(systemName: "server.rack")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(SliceColor.accent)
        }
    }

    /// tools/list 预览区域。
    private var toolPreview: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.xs) {
            ForEach(tools, id: \.ref) { tool in
                HStack(spacing: SliceSpacing.sm) {
                    Text(tool.title)
                        .font(SliceFont.captionEmphasis)
                        .foregroundColor(SliceColor.textPrimary)
                    if let description = tool.description, description.isEmpty == false {
                        Text(description)
                            .font(SliceFont.caption)
                            .foregroundColor(SliceColor.textSecondary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.leading, 44)
    }
}
