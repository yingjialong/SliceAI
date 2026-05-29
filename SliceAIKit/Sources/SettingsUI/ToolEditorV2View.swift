import DesignSystem
import Orchestration
import SliceCore
import SwiftUI

/// ToolEditor v2：左侧草稿编辑器，右侧 Playground。
struct ToolEditorV2View: View {
    /// 当前本地 Tool 草稿。
    @Binding var draft: ToolEditorDraft
    /// 可选 Provider 列表。
    let providers: [Provider]
    /// 当前配置中的工具列表，用于编辑器内部冲突提示。
    let tools: [Tool]
    /// 当前可绑定的 enabled skills。
    let availableSkills: [SliceCore.Skill]
    /// Settings Playground runner。
    let runner: (any ToolPlaygroundRunning)?
    /// Save 和 Run 共用的草稿校验。
    let validateDraft: (ToolEditorDraft) -> [ToolDraftValidationError]
    /// 保存草稿回调。
    let onSave: () -> Void
    /// 放弃草稿回调。
    let onRevert: () -> Void

    /// 右侧 Playground 的本地状态。
    @State private var playgroundState = ToolPlaygroundState()

    /// 渲染双栏 ToolEditor v2。
    var body: some View {
        VStack(alignment: .leading, spacing: SliceSpacing.base) {
            toolbar
            HStack(alignment: .top, spacing: SliceSpacing.lg) {
                ToolEditorView(
                    tool: $draft.tool,
                    providers: providers,
                    tools: tools,
                    hotkeys: $draft.hotkeys,
                    availableSkills: availableSkills,
                    onHotkeyCommit: nil
                )
                .frame(minWidth: 300)

                ToolPlaygroundView(
                    tool: draft.tool,
                    runner: runner,
                    validateBeforeRun: { validateDraft(draft) },
                    state: $playgroundState
                )
            }
        }
    }

    /// 顶部保存 / 放弃工具栏。
    private var toolbar: some View {
        HStack {
            Text("Unsaved draft")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textSecondary)
            Spacer()
            PillButton("Revert", icon: "arrow.uturn.backward", style: .secondary, action: onRevert)
            PillButton("Save", icon: "checkmark", style: .primary, action: onSave)
        }
    }
}
