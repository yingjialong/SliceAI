import SliceCore
@testable import SettingsUI
import SwiftUI
import XCTest

/// ToolEditor Agent Skill 绑定行为测试。
@MainActor
final class ToolEditorSkillsBindingTests: XCTestCase {

    /// Agent 工具应能增删 skill binding，并写回 `AgentTool.skills`。
    func test_agentSkillBindingWritesAgentToolSkills() {
        let box = ToolBox(tool: makeAgentTool(skills: []))
        let view = makeEditor(toolBox: box, availableSkillIDs: ["writing"])

        view.setAgentSkill(id: "writing", isSelected: true)
        XCTAssertEqual(currentSkillIDs(in: box.tool), ["writing"])

        view.setAgentSkill(id: "writing", isSelected: false)
        XCTAssertEqual(currentSkillIDs(in: box.tool), [])
    }

    /// Agent 工具最多只能绑定 5 个 skills，第 6 个选择应被忽略。
    func test_agentSkillBindingCapsAtFiveSkills() {
        let existing = (1...5).map { SkillReference(id: "skill-\($0)", pinVersion: nil) }
        let box = ToolBox(tool: makeAgentTool(skills: existing))
        let view = makeEditor(
            toolBox: box,
            availableSkillIDs: (1...6).map { "skill-\($0)" }
        )

        view.setAgentSkill(id: "skill-6", isSelected: true)

        XCTAssertEqual(currentSkillIDs(in: box.tool), existing.map(\.id))
    }

    /// 点击加号应逐条添加尚未绑定的 skill，并在没有可选项时停止。
    func test_addAgentSkillBindingAddsOneUnboundSkillAtATime() {
        let box = ToolBox(tool: makeAgentTool(skills: []))
        let view = makeEditor(toolBox: box, availableSkillIDs: ["writing", "review"])

        XCTAssertTrue(view.canAddAgentSkillBinding)
        view.addAgentSkillBinding()
        XCTAssertEqual(currentSkillIDs(in: box.tool), ["writing"])

        XCTAssertTrue(view.canAddAgentSkillBinding)
        view.addAgentSkillBinding()
        XCTAssertEqual(currentSkillIDs(in: box.tool), ["writing", "review"])

        XCTAssertFalse(view.canAddAgentSkillBinding)
        view.addAgentSkillBinding()
        XCTAssertEqual(currentSkillIDs(in: box.tool), ["writing", "review"])
    }

    /// 每行下拉选项应只包含当前行 skill 和尚未被其它行绑定的 skills，避免重复绑定。
    func test_selectableAgentSkillIDsExcludeSkillsSelectedByOtherRows() {
        let box = ToolBox(tool: makeAgentTool(skills: [
            SkillReference(id: "writing", pinVersion: nil),
            SkillReference(id: "review", pinVersion: nil)
        ]))
        let view = makeEditor(toolBox: box, availableSkillIDs: ["writing", "review", "debug"])

        XCTAssertEqual(view.selectableAgentSkillIDs(forRow: 0), ["writing", "debug"])
        XCTAssertEqual(view.selectableAgentSkillIDs(forRow: 1), ["review", "debug"])
    }

    /// 下拉选择应替换当前行 skill；删除按钮应按行移除绑定。
    func test_agentSkillRowSelectionAndRemovalUpdateBindings() {
        let box = ToolBox(tool: makeAgentTool(skills: [
            SkillReference(id: "writing", pinVersion: nil),
            SkillReference(id: "review", pinVersion: nil)
        ]))
        let view = makeEditor(toolBox: box, availableSkillIDs: ["writing", "review", "debug"])

        view.setAgentSkill(at: 0, id: "debug")
        XCTAssertEqual(currentSkillIDs(in: box.tool), ["debug", "review"])

        view.setAgentSkill(at: 1, id: "debug")
        XCTAssertEqual(currentSkillIDs(in: box.tool), ["debug", "review"])

        view.removeAgentSkill(at: 0)
        XCTAssertEqual(currentSkillIDs(in: box.tool), ["review"])

        view.removeAgentSkill(at: 10)
        XCTAssertEqual(currentSkillIDs(in: box.tool), ["review"])
    }

    /// 构造 ToolEditorView。
    /// - Parameters:
    ///   - toolBox: 可变 tool 容器。
    ///   - availableSkillIDs: 可选 skill ids。
    /// - Returns: 可直接调用 binding helper 的 editor。
    private func makeEditor(toolBox: ToolBox, availableSkillIDs: [String]) -> ToolEditorView {
        ToolEditorView(
            tool: Binding(
                get: { toolBox.tool },
                set: { toolBox.tool = $0 }
            ),
            providers: [],
            tools: [toolBox.tool],
            hotkeys: .constant(HotkeyBindings(toggleCommandPalette: "option+space", tools: [:])),
            availableSkills: availableSkillIDs.map { makeSkill(id: $0) }
        )
    }

    /// 构造 Agent Tool fixture。
    /// - Parameter skills: 初始 skill binding。
    /// - Returns: Agent Tool。
    private func makeAgentTool(skills: [SkillReference]) -> Tool {
        Tool(
            id: "agent",
            name: "Agent",
            icon: "sparkles",
            description: nil,
            kind: .agent(AgentTool(
                systemPrompt: nil,
                initialUserPrompt: "{{selection}}",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
                skills: skills,
                mcpAllowlist: [],
                builtinCapabilities: [],
                maxSteps: 3,
                stopCondition: .finalAnswerProvided,
                toolCallPolicy: nil
            )),
            visibleWhen: nil,
            displayMode: .window,
            outputBinding: nil,
            permissions: [],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 0)),
            budget: nil,
            hotkey: nil,
            labelStyle: .iconAndName,
            tags: []
        )
    }

    /// 构造 Skill fixture。
    /// - Parameter id: skill id。
    /// - Returns: enabled Skill。
    private func makeSkill(id: String) -> Skill {
        Skill(
            id: id,
            canonicalName: id,
            path: URL(fileURLWithPath: "/tmp/\(id)"),
            skillFile: URL(fileURLWithPath: "/tmp/\(id)/SKILL.md"),
            manifest: SkillManifest(name: id, description: "Test skill \(id)"),
            resources: [],
            provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 0)),
            source: SkillSourceRef(sourceId: "test", rootPath: "/tmp"),
            state: .enabled
        )
    }

    /// 读取当前 Agent Tool skills。
    /// - Parameter tool: Tool fixture。
    /// - Returns: 当前绑定的 skill ids。
    private func currentSkillIDs(in tool: Tool) -> [String] {
        guard case .agent(let agentTool) = tool.kind else {
            XCTFail("Expected agent tool")
            return []
        }
        return agentTool.skills.map(\.id)
    }
}

/// 测试用可变 Tool 容器。
private final class ToolBox {

    /// 当前 Tool 值。
    var tool: Tool

    /// 构造容器。
    /// - Parameter tool: 初始 Tool。
    init(tool: Tool) {
        self.tool = tool
    }
}
