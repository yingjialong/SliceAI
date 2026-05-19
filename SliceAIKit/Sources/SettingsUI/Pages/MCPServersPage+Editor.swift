import DesignSystem
import Foundation
import SliceCore
import SwiftUI

// MARK: - MCPServerEditorSheet

/// MCP server 新增/编辑 sheet。
struct MCPServerEditorSheet: View {

    /// sheet 内部可编辑草稿。
    @State private var draft: MCPServerDraft

    /// 本地表单校验提示。
    @State private var localValidationMessage: String?

    /// ViewModel 返回的保存错误提示。
    let validationMessage: String?

    /// 取消回调。
    let onCancel: () -> Void

    /// 保存回调。
    let onSave: (MCPDescriptor, String?) -> Void

    /// 构造 MCP server 编辑 sheet。
    /// - Parameters:
    ///   - session: 当前编辑会话。
    ///   - validationMessage: ViewModel 返回的保存错误提示。
    ///   - onCancel: 取消回调。
    ///   - onSave: 保存回调。
    init(
        session: MCPServerEditorSession,
        validationMessage: String?,
        onCancel: @escaping () -> Void,
        onSave: @escaping (MCPDescriptor, String?) -> Void
    ) {
        self._draft = State(initialValue: session.draft)
        self.validationMessage = validationMessage
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

            if let message = localValidationMessage ?? validationMessage {
                MCPStatusBanner(text: message, isError: true)
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
        onSave(descriptor, draft.originalID)
    }
}

// MARK: - ClaudeDesktopImportSheet

/// Claude Desktop JSON 粘贴导入 sheet。
struct ClaudeDesktopImportSheet: View {

    /// JSON 文本绑定。
    @Binding var jsonText: String

    /// ViewModel 返回的导入错误提示。
    let validationMessage: String?

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

            if let validationMessage {
                MCPStatusBanner(text: validationMessage, isError: true)
            }

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
struct MCPStatusBanner: View {

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
struct MCPServerEditorSession: Identifiable {

    /// sheet identity，避免用户编辑 server id 时影响 sheet 身份。
    let id = UUID()

    /// 当前编辑草稿。
    let draft: MCPServerDraft
}

// MARK: - MCPServerDraft

/// MCP server 表单草稿。
struct MCPServerDraft {

    /// 编辑前的 server id；新增时为 nil。
    var originalID: String?

    /// server id。
    var id: String

    /// stdio command。
    var command: String

    /// args 多行文本。
    var argsText: String

    /// env 多行文本。
    var envText: String

    /// 原始 capabilities；编辑时必须保留，避免 UI 改基础字段时丢 metadata。
    var capabilities: [MCPCapability]

    /// 原始 provenance；编辑时必须保留，避免信任来源被重置。
    var provenance: Provenance

    /// 构造新增 server 草稿。
    /// - Returns: 默认空 command 的 stdio 草稿。
    static func new() -> MCPServerDraft {
        MCPServerDraft(
            originalID: nil,
            id: "server-\(Int(Date().timeIntervalSince1970))",
            command: "",
            argsText: "",
            envText: "",
            capabilities: [],
            provenance: .selfManaged(userAcknowledgedAt: Date())
        )
    }

    /// 从 descriptor 构造编辑草稿。
    /// - Parameter descriptor: 要编辑的 MCP descriptor。
    init(descriptor: MCPDescriptor) {
        self.originalID = descriptor.id
        self.id = descriptor.id
        self.command = descriptor.command ?? ""
        self.argsText = (descriptor.args ?? []).joined(separator: "\n")
        self.envText = (descriptor.env ?? [:])
            .sorted { lhs, rhs in lhs.key < rhs.key }
            .map { key, value in "\(key)=\(value)" }
            .joined(separator: "\n")
        self.capabilities = descriptor.capabilities
        self.provenance = descriptor.provenance
    }

    /// 构造草稿。
    /// - Parameters:
    ///   - originalID: 编辑前的 server id；新增时为 nil。
    ///   - id: server id。
    ///   - command: stdio command。
    ///   - argsText: args 多行文本。
    ///   - envText: env 多行文本。
    ///   - capabilities: 原始 capabilities。
    ///   - provenance: 原始 provenance。
    init(
        originalID: String? = nil,
        id: String,
        command: String,
        argsText: String,
        envText: String,
        capabilities: [MCPCapability] = [],
        provenance: Provenance = .selfManaged(userAcknowledgedAt: Date())
    ) {
        self.originalID = originalID
        self.id = id
        self.command = command
        self.argsText = argsText
        self.envText = envText
        self.capabilities = capabilities
        self.provenance = provenance
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
            capabilities: capabilities,
            provenance: provenance
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
enum MCPProvenanceSummary {

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
