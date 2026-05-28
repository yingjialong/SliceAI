import DesignSystem
import Orchestration
import SliceCore
import SwiftUI

/// ToolEditor 右侧 Playground 视图。
struct ToolPlaygroundView: View {
    /// 当前未保存的 Tool 草稿快照。
    let tool: Tool
    /// Settings Playground runner；nil 时禁用运行入口。
    let runner: (any ToolPlaygroundRunning)?
    /// Run 前复用保存校验，避免 Playground 绕过草稿规则。
    let validateBeforeRun: () -> [ToolDraftValidationError]
    /// Playground UI 状态。
    @Binding var state: ToolPlaygroundState

    /// 当前运行任务；非 nil 时 Cancel 可用。
    @State private var runTask: Task<Void, Never>?

    /// 当前有效运行 token；防止旧 Task 回写新 run 的状态。
    @State private var activeRunID: UUID?

    /// 渲染 Playground 输入、控制和输出区。
    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.base) {
            header
            inputs
            controls
            output
        }
        .frame(minWidth: 280, minHeight: 360)
        .onDisappear {
            cancelActiveRun()
        }
    }

    /// 顶部标题和 dry-run 状态提示。
    private var header: some View {
        HStack {
            Text("Playground")
                .font(SliceFont.headline)
            Spacer()
            Text("side effects dry-run")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textSecondary)
        }
    }

    /// 本次试跑的 selection 和 MCP 显式开关。
    private var inputs: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.sm) {
            PromptTextEditor(
                label: "Selection",
                placeholder: "输入本次试跑的选区文本",
                required: true,
                text: $state.selectionText,
                minHeight: 88
            )
            Toggle("允许本次运行调用 MCP tools", isOn: $state.allowMCPToolCalls)
                .font(SliceFont.caption)
        }
    }

    /// Run / Cancel / Clear 控制按钮。
    private var controls: some View {
        HStack {
            PillButton("Run", icon: "play.fill", style: .primary) { startRun() }
                .disabled(runDisabled)
            PillButton("Cancel", icon: "stop.fill", style: .secondary) { cancelRun() }
                .disabled(runTask == nil)
            PillButton("Clear", icon: "xmark", style: .secondary) { clearState() }
        }
    }

    /// Playground 输出预览区。
    private var output: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: SliceSpacing.sm) {
                if !state.promptPreview.isEmpty {
                    Text(state.promptPreview)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                        .textSelection(.enabled)
                }
                ForEach(Array(state.permissionRows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.warning)
                }
                if let errorMessage = state.errorMessage {
                    Text(errorMessage)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.error)
                }
                if shouldShowDisplaySummary {
                    Text(state.displayPreview.summary)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text(primaryOutputText)
                    .font(SliceFont.body)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                ForEach(Array(state.toolCallRows.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                }
                ForEach(Array(state.skippedSideEffects.enumerated()), id: \.offset) { _, row in
                    Text(row)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                }
                if !state.reportSummary.isEmpty {
                    Text(state.reportSummary)
                        .font(SliceFont.caption)
                        .foregroundColor(SliceColor.textSecondary)
                }
            }
            .padding(SliceSpacing.base)
        }
        .frame(minHeight: 180)
        .background(SliceColor.background)
        .clipShape(RoundedRectangle(cornerRadius: SliceRadius.control))
    }

    /// Run 按钮是否应禁用。
    private var runDisabled: Bool {
        runner == nil || state.selectionText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// 主输出文本；streaming 存在时显示 raw text，否则显示 DisplayMode 摘要。
    private var primaryOutputText: String {
        state.streamedText.isEmpty ? state.displayPreview.summary : state.streamedText
    }

    /// 是否额外展示 DisplayMode dry-run 摘要。
    private var shouldShowDisplaySummary: Bool {
        !state.streamedText.isEmpty
            && !state.displayPreview.summary.isEmpty
            && state.displayPreview.summary != state.streamedText
    }

    /// 启动一次 Playground 运行。
    private func startRun() {
        guard let runner else { return }
        let runID = UUID()
        let previousTask = runTask
        activeRunID = runID
        runTask = nil
        previousTask?.cancel()

        let validationErrors = validateBeforeRun()
        guard validationErrors.isEmpty else {
            let message = validationErrors.map { $0.localizedDescription }.joined(separator: "\n")
            activeRunID = nil
            state.markValidationFailed(message)
            print("[ToolPlaygroundView] startRun blocked by validation errors count=\(validationErrors.count)")
            return
        }

        state.status = .running
        let request = ToolPlaygroundRunRequest(
            tool: tool,
            selectionText: state.selectionText,
            appName: state.appName,
            windowTitle: state.windowTitle.isEmpty ? nil : state.windowTitle,
            url: playgroundURL,
            allowMCPToolCalls: state.allowMCPToolCalls
        )
        runTask = Task { @MainActor in
            defer {
                if activeRunID == runID {
                    activeRunID = nil
                    runTask = nil
                }
            }
            do {
                for try await event in runner.run(request) {
                    guard activeRunID == runID, !Task.isCancelled else {
                        break
                    }
                    state.reduce(event, tool: tool)
                }
            } catch {
                guard activeRunID == runID, !Task.isCancelled else { return }
                // 用户主动取消时保留 cancelling 状态，不把取消渲染成失败。
                state.status = .failed(error.localizedDescription)
                state.errorMessage = error.localizedDescription
            }
        }
    }

    /// 取消当前 Playground 运行。
    private func cancelRun() {
        state.markCancelling()
        cancelActiveRun()
    }

    /// 清空 Playground 输入与输出状态。
    private func clearState() {
        cancelActiveRun()
        state = ToolPlaygroundState()
    }

    /// 取消当前 active run，不修改 UI 状态。
    private func cancelActiveRun() {
        activeRunID = nil
        runTask?.cancel()
        runTask = nil
    }

    /// 解析用户输入的 URL；空白输入不传入执行上下文。
    private var playgroundURL: URL? {
        let raw = state.urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
    }
}
