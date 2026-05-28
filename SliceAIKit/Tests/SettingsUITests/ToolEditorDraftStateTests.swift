import HotkeyManager
import SliceCore
import SwiftUI
import XCTest
@testable import SettingsUI

/// ToolEditor v2 草稿状态和保存校验测试。
final class ToolEditorDraftStateTests: XCTestCase {

    /// 编辑已有 Tool 时，修改草稿不应提前污染原始 Tool。
    func test_existingDraftSaveDoesNotMutateOriginalUntilCommit() throws {
        let original = makePromptTool(id: "translate", name: "Translate")
        var session = ToolEditorDraftSession.existing(original: original, hotkeys: makeHotkeys())
        session.draft.tool.name = "Translate Draft"

        XCTAssertEqual(original.name, "Translate")
        XCTAssertEqual(session.draft.tool.name, "Translate Draft")
    }

    /// 新建 Tool 草稿时，不允许使用已存在的 Tool id。
    func test_validatorRejectsDuplicateToolIdForCreatingDraft() {
        let existing = makePromptTool(id: "translate", name: "Translate")
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Other"), hotkeys: makeHotkeys())

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [existing],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains(.duplicateToolId("translate")))
    }

    /// 编辑已有 Tool 时，原始 id 允许保持不变。
    func test_validatorAllowsSameIdForExistingDraft() {
        let existing = makePromptTool(id: "translate", name: "Translate")
        let draft = ToolEditorDraft(
            tool: makePromptTool(id: "translate", name: "Translate Draft"),
            hotkeys: makeHotkeys()
        )

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [existing],
            availableSkills: [],
            originalToolId: "translate"
        )

        XCTAssertFalse(errors.contains(.duplicateToolId("translate")))
    }

    /// Agent Tool 绑定 disabled skill 时应拒绝保存。
    func test_validatorRejectsDisabledSkills() {
        let skill = Skill(
            id: "english",
            canonicalName: "english",
            path: URL(fileURLWithPath: "/tmp/skills/english"),
            skillFile: URL(fileURLWithPath: "/tmp/skills/english/SKILL.md"),
            manifest: SkillManifest(name: "english", description: "English"),
            resources: [],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 0)),
            source: SkillSourceRef(sourceId: "test", rootPath: "/tmp/skills"),
            state: .disabled
        )
        var tool = makeAgentTool(id: "agent")
        tool.kind = .agent(AgentTool(
            systemPrompt: "system",
            initialUserPrompt: "{{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai", modelId: nil),
            skills: [SkillReference(id: "english", pinVersion: nil)],
            mcpAllowlist: [],
            builtinCapabilities: [],
            maxSteps: 4,
            stopCondition: .finalAnswerProvided,
            toolCallPolicy: nil
        ))

        let errors = ToolDraftValidator.validate(
            draft: ToolEditorDraft(tool: tool, hotkeys: makeHotkeys()),
            existingTools: [tool],
            availableSkills: [skill],
            originalToolId: "agent"
        )

        XCTAssertTrue(errors.contains(.skillNotEnabled("english")))
    }

    /// Agent Tool 绑定 registry 中不存在的 skill 时应拒绝保存。
    func test_validatorRejectsUnknownSkills() {
        var tool = makeAgentTool(id: "agent")
        tool.kind = .agent(AgentTool(
            systemPrompt: "system",
            initialUserPrompt: "{{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai", modelId: nil),
            skills: [SkillReference(id: "missing", pinVersion: nil)],
            mcpAllowlist: [],
            builtinCapabilities: [],
            maxSteps: 4,
            stopCondition: .finalAnswerProvided,
            toolCallPolicy: nil
        ))

        let errors = ToolDraftValidator.validate(
            draft: ToolEditorDraft(tool: tool, hotkeys: makeHotkeys()),
            existingTools: [tool],
            availableSkills: [],
            originalToolId: "agent"
        )

        XCTAssertTrue(errors.contains(.skillNotEnabled("missing")))
    }

    /// Tool 结构性校验失败时，应展示 SliceError.userMessage，而不是系统默认 localizedDescription。
    func test_validatorUsesSliceErrorUserMessageForInvalidTool() {
        var tool = makePromptTool(id: "translate", name: "Translate")
        tool.outputBinding = OutputBinding(primary: .bubble, sideEffects: [])

        let errors = ToolDraftValidator.validate(
            draft: ToolEditorDraft(tool: tool, hotkeys: makeHotkeys()),
            existingTools: [],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains { error in
            guard case .invalidTool(let message) = error else { return false }
            return message.contains("配置校验失败")
        })
    }

    /// 工具热键不应与命令面板热键冲突。
    func test_validatorRejectsToolHotkeyConflictWithCommandPalette() {
        var hotkeys = makeHotkeys()
        hotkeys.tools["translate"] = "option+space"
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Translate"), hotkeys: hotkeys)

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains { error in
            if case .hotkeyConflict = error { return true }
            return false
        })
    }

    /// 命令面板关闭时，工具热键可与命令面板配置值相同。
    func test_validatorIgnoresCommandPaletteHotkeyWhenCommandPaletteDisabled() {
        var hotkeys = makeHotkeys()
        hotkeys.tools["translate"] = "option+space"
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Translate"), hotkeys: hotkeys)

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [],
            availableSkills: [],
            originalToolId: nil,
            commandPaletteEnabled: false
        )

        XCTAssertFalse(errors.contains { error in
            if case .hotkeyConflict = error { return true }
            return false
        })
    }

    /// 集中式工具热键应继续检测旧 Tool.hotkey fallback 的冲突。
    func test_validatorRejectsLegacyFallbackToolHotkeyConflict() {
        var other = makePromptTool(id: "summarize", name: "Summarize")
        other.hotkey = "command+k"
        var hotkeys = makeHotkeys()
        hotkeys.tools["translate"] = "command+k"
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Translate"), hotkeys: hotkeys)

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [other],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains { error in
            if case .hotkeyConflict = error { return true }
            return false
        })
    }

    /// 保存前应拒绝无法解析的工具热键。
    func test_validatorRejectsInvalidToolHotkey() {
        var hotkeys = makeHotkeys()
        hotkeys.tools["translate"] = "not-a-hotkey"
        let draft = ToolEditorDraft(tool: makePromptTool(id: "translate", name: "Translate"), hotkeys: hotkeys)

        let errors = ToolDraftValidator.validate(
            draft: draft,
            existingTools: [],
            availableSkills: [],
            originalToolId: nil
        )

        XCTAssertTrue(errors.contains(.invalidHotkey("not-a-hotkey")))
    }

    /// ToolEditor v2 组合视图应能用本地草稿和空 Playground runner 构造。
    @MainActor
    func test_toolEditorV2ViewCanBeConstructedWithDraftSession() {
        var draft = ToolEditorDraft(
            tool: makePromptTool(id: "translate", name: "Translate"),
            hotkeys: makeHotkeys()
        )
        let binding = Binding<ToolEditorDraft>(
            get: { draft },
            set: { draft = $0 }
        )

        _ = ToolEditorV2View(
            draft: binding,
            providers: [],
            tools: [draft.tool],
            availableSkills: [],
            runner: nil,
            validateDraft: { _ in [] },
            onSave: {},
            onRevert: {}
        )
    }

    /// Tools 页 Run/Save 共用校验应显式尊重命令面板启停状态。
    @MainActor
    func test_toolsPageValidateDraftForRunHonorsDisabledCommandPalette() async throws {
        let viewModel = SettingsViewModel(
            store: ConfigurationStore(fileURL: try makeTemporaryFileURL(), legacyFileURL: nil),
            keychain: ToolEditorDraftStateTestKeychain()
        )
        await viewModel.reload()
        var configuration = DefaultConfiguration.initial()
        configuration.tools = []
        configuration.hotkeys = makeHotkeys()
        configuration.hotkeys.tools["translate"] = "option+space"
        configuration.triggers.commandPaletteEnabled = false
        viewModel.configuration = configuration

        let page = ToolsSettingsPage(viewModel: viewModel)
        let draft = ToolEditorDraft(
            tool: makePromptTool(id: "translate", name: "Translate"),
            hotkeys: configuration.hotkeys
        )

        let errors = page.validateDraftForRun(draft)

        XCTAssertFalse(errors.contains { error in
            if case .hotkeyConflict = error { return true }
            return false
        })
    }

    /// 构造 Prompt Tool fixture。
    /// - Parameters:
    ///   - id: Tool id。
    ///   - name: Tool 名称。
    /// - Returns: Prompt Tool。
    private func makePromptTool(id: String, name: String) -> Tool {
        Tool(
            id: id,
            name: name,
            icon: "wand.and.stars",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: nil,
                userPrompt: "{{selection}}",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
                temperature: nil,
                maxTokens: nil,
                variables: [:]
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
    }

    /// 构造 Agent Tool fixture。
    /// - Parameter id: Tool id。
    /// - Returns: Agent Tool。
    private func makeAgentTool(id: String) -> Tool {
        Tool(
            id: id,
            name: "Agent",
            icon: "brain",
            description: nil,
            kind: .agent(AgentTool(
                systemPrompt: "system",
                initialUserPrompt: "{{selection}}",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
                skills: [],
                mcpAllowlist: [],
                builtinCapabilities: [],
                maxSteps: 4,
                stopCondition: .finalAnswerProvided,
                toolCallPolicy: nil
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
    }

    /// 构造默认热键配置 fixture。
    /// - Returns: 命令面板使用 option+space 的 HotkeyBindings。
    private func makeHotkeys() -> HotkeyBindings {
        HotkeyBindings(toggleCommandPalette: "option+space")
    }

    /// 创建测试用临时 config-v2.json 路径。
    /// - Returns: 位于临时目录下的配置文件 URL。
    private func makeTemporaryFileURL() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("config-v2.json")
    }
}

/// ToolEditorDraftStateTests 使用的内存 Keychain。
private final actor ToolEditorDraftStateTestKeychain: KeychainAccessing {

    /// 内存 API Key 字典。
    private var values: [String: String] = [:]

    /// 读取测试 API Key。
    /// - Parameter providerId: Provider keychain account。
    /// - Returns: 已保存值或 nil。
    func readAPIKey(providerId: String) async throws -> String? {
        values[providerId]
    }

    /// 写入测试 API Key。
    /// - Parameters:
    ///   - value: API Key。
    ///   - providerId: Provider keychain account。
    func writeAPIKey(_ value: String, providerId: String) async throws {
        values[providerId] = value
    }

    /// 删除测试 API Key。
    /// - Parameter providerId: Provider keychain account。
    func deleteAPIKey(providerId: String) async throws {
        values.removeValue(forKey: providerId)
    }
}
