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
                onCancel: { editorSession = nil },
                onSave: { descriptor in
                    Task {
                        await viewModel.save(descriptor)
                        editorSession = nil
                    }
                }
            )
        }
        .sheet(isPresented: $isImportSheetPresented) {
            ClaudeDesktopImportSheet(
                jsonText: $importJSONText,
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
                        isTesting: viewModel.testingServerID == descriptor.id,
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
            importJSONText = ""
            isImportSheetPresented = false
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

// MARK: - MCPServerEditorSheet

/// MCP server 新增/编辑 sheet。
private struct MCPServerEditorSheet: View {

    /// sheet 内部可编辑草稿。
    @State private var draft: MCPServerDraft

    /// 本地表单校验提示。
    @State private var localValidationMessage: String?

    /// 取消回调。
    let onCancel: () -> Void

    /// 保存回调。
    let onSave: (MCPDescriptor) -> Void

    /// 构造 MCP server 编辑 sheet。
    /// - Parameters:
    ///   - session: 当前编辑会话。
    ///   - onCancel: 取消回调。
    ///   - onSave: 保存回调。
    init(
        session: MCPServerEditorSession,
        onCancel: @escaping () -> Void,
        onSave: @escaping (MCPDescriptor) -> Void
    ) {
        self._draft = State(initialValue: session.draft)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.lg) {
            Text("MCP Server")
                .font(SliceFont.title)
                .foregroundColor(SliceColor.textPrimary)

            SectionCard("Stdio") {
                SettingsRow("ID") {
                    TextField("filesystem", text: $draft.id)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
                SettingsRow("Command") {
                    TextField("/opt/homebrew/bin/mcp-server", text: $draft.command)
                        .textFieldStyle(.plain)
                        .multilineTextAlignment(.trailing)
                }
                multilineField(title: "Args", text: $draft.argsText)
                multilineField(title: "Env", text: $draft.envText)
            }

            if let localValidationMessage {
                MCPStatusBanner(text: localValidationMessage, isError: true)
            }

            HStack {
                Spacer()
                PillButton("取消", style: .secondary, action: onCancel)
                PillButton("保存", icon: "checkmark", style: .primary) {
                    saveDraft()
                }
            }
        }
        .padding(SliceSpacing.xl)
        .frame(width: 520)
    }

    /// 多行文本字段。
    /// - Parameters:
    ///   - title: 字段标题。
    ///   - text: 字段文本绑定。
    /// - Returns: 多行输入视图。
    private func multilineField(title: String, text: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: SliceSpacing.sm) {
            Text(title)
                .font(SliceFont.subheadline)
                .foregroundColor(SliceColor.textPrimary)
            TextEditor(text: text)
                .font(SliceFont.body)
                .scrollContentBackground(.hidden)
                .frame(minHeight: 68)
                .padding(SliceSpacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: SliceRadius.control)
                        .fill(SliceColor.hoverFill)
                )
        }
        .padding(.vertical, SliceSpacing.base)
    }

    /// 校验并保存当前草稿。
    private func saveDraft() {
        guard let descriptor = draft.makeDescriptor() else {
            localValidationMessage = "请检查 ID、Command 与 Env"
            print("[MCPServerEditorSheet] saveDraft: invalid draft")
            return
        }
        localValidationMessage = nil
        print("[MCPServerEditorSheet] saveDraft: id=\(descriptor.id)")
        onSave(descriptor)
    }
}

// MARK: - ClaudeDesktopImportSheet

/// Claude Desktop JSON 粘贴导入 sheet。
private struct ClaudeDesktopImportSheet: View {

    /// JSON 文本绑定。
    @Binding var jsonText: String

    /// 取消回调。
    let onCancel: () -> Void

    /// 导入回调。
    let onImport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.lg) {
            Text("Claude Desktop JSON")
                .font(SliceFont.title)
                .foregroundColor(SliceColor.textPrimary)

            TextEditor(text: $jsonText)
                .font(.system(.body, design: .monospaced))
                .scrollContentBackground(.hidden)
                .frame(minHeight: 260)
                .padding(SliceSpacing.base)
                .background(
                    RoundedRectangle(cornerRadius: SliceRadius.control)
                        .fill(SliceColor.hoverFill)
                )

            HStack {
                Spacer()
                PillButton("取消", style: .secondary, action: onCancel)
                PillButton("导入", icon: "square.and.arrow.down", style: .primary, action: onImport)
                    .disabled(jsonText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(SliceSpacing.xl)
        .frame(width: 560)
    }
}

// MARK: - MCPStatusBanner

/// MCP 设置页状态提示。
private struct MCPStatusBanner: View {

    /// 展示文本。
    let text: String

    /// 是否为错误态。
    let isError: Bool

    var body: some View {
        HStack(spacing: SliceSpacing.sm) {
            Image(systemName: isError ? "exclamationmark.triangle" : "checkmark.circle")
                .font(.system(size: 12, weight: .medium))
            Text(text)
                .font(SliceFont.caption)
                .lineLimit(2)
            Spacer()
        }
        .foregroundColor(isError ? SliceColor.error : SliceColor.success)
        .padding(.horizontal, SliceSpacing.lg)
        .padding(.vertical, SliceSpacing.base)
        .background(
            RoundedRectangle(cornerRadius: SliceRadius.control)
                .fill((isError ? SliceColor.error : SliceColor.success).opacity(0.08))
        )
    }
}

// MARK: - MCPServerEditorSession

/// MCP server 编辑 sheet 会话。
private struct MCPServerEditorSession: Identifiable {

    /// sheet identity，避免用户编辑 server id 时影响 sheet 身份。
    let id = UUID()

    /// 当前编辑草稿。
    let draft: MCPServerDraft
}

// MARK: - MCPServerDraft

/// MCP server 表单草稿。
private struct MCPServerDraft {

    /// server id。
    var id: String

    /// stdio command。
    var command: String

    /// args 多行文本。
    var argsText: String

    /// env 多行文本。
    var envText: String

    /// 构造新增 server 草稿。
    /// - Returns: 默认空 command 的 stdio 草稿。
    static func new() -> MCPServerDraft {
        MCPServerDraft(
            id: "server-\(Int(Date().timeIntervalSince1970))",
            command: "",
            argsText: "",
            envText: ""
        )
    }

    /// 从 descriptor 构造编辑草稿。
    /// - Parameter descriptor: 要编辑的 MCP descriptor。
    init(descriptor: MCPDescriptor) {
        self.id = descriptor.id
        self.command = descriptor.command ?? ""
        self.argsText = (descriptor.args ?? []).joined(separator: "\n")
        self.envText = (descriptor.env ?? [:])
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { key, value in "\(key)=\(value)" }
            .joined(separator: "\n")
    }

    /// 构造草稿。
    /// - Parameters:
    ///   - id: server id。
    ///   - command: stdio command。
    ///   - argsText: args 多行文本。
    ///   - envText: env 多行文本。
    init(id: String, command: String, argsText: String, envText: String) {
        self.id = id
        self.command = command
        self.argsText = argsText
        self.envText = envText
    }

    /// 将表单草稿转换为 `MCPDescriptor`。
    /// - Returns: 合法时返回 stdio descriptor；表单缺少必填项或 env 格式错误时返回 nil。
    func makeDescriptor() -> MCPDescriptor? {
        let trimmedID = id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedID.isEmpty == false, trimmedCommand.isEmpty == false else {
            return nil
        }
        guard isEnvTextValid() else {
            return nil
        }
        return MCPDescriptor(
            id: trimmedID,
            transport: .stdio,
            command: trimmedCommand,
            args: parsedArgs(),
            url: nil,
            env: parsedEnv(),
            capabilities: [],
            provenance: .selfManaged(userAcknowledgedAt: Date())
        )
    }

    /// 解析 args 多行文本。
    /// - Returns: 非空参数数组；没有参数时返回 nil。
    private func parsedArgs() -> [String]? {
        let args = argsText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }
        return args.isEmpty ? nil : args
    }

    /// 解析 env 多行文本。
    /// - Returns: 合法环境变量字典；没有 env 时返回 nil；格式错误时返回 nil。
    private func parsedEnv() -> [String: String]? {
        var result: [String: String] = [:]
        let lines = envText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        for line in lines {
            guard let separator = line.firstIndex(of: "=") else {
                return nil
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            let valueStart = line.index(after: separator)
            let value = String(line[valueStart...]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else {
                return nil
            }
            // value 允许为空字符串，便于用户显式覆盖环境变量。
            result[key] = value
        }

        return result.isEmpty ? nil : result
    }

    /// 校验 env 多行文本是否为 `KEY=VALUE` 形态。
    /// - Returns: 空文本或所有非空行合法时返回 true。
    private func isEnvTextValid() -> Bool {
        let lines = envText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { $0.isEmpty == false }

        for line in lines {
            guard let separator = line.firstIndex(of: "=") else {
                return false
            }
            let key = String(line[..<separator]).trimmingCharacters(in: .whitespacesAndNewlines)
            if key.isEmpty {
                return false
            }
        }
        return true
    }
}

// MARK: - MCPProvenanceSummary

/// Provenance 列表摘要。
private enum MCPProvenanceSummary {

    /// 生成 provenance 摘要文本。
    /// - Parameter provenance: 目标 provenance。
    /// - Returns: 短文本摘要。
    static func text(for provenance: Provenance) -> String {
        switch provenance {
        case .firstParty:
            return "first party"
        case .communitySigned(let publisher, _):
            return "signed: \(publisher)"
        case .selfManaged:
            return "self managed"
        case .unknown:
            return "unknown"
        }
    }
}
