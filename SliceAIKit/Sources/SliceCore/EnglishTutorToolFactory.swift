import Foundation

/// English Tutor 首方工具工厂。
public enum EnglishTutorToolFactory {

    /// 工具与内置 skill 的稳定 id。
    public static let toolId = "english-tutor"

    /// 创建 English Tutor Agent Tool。
    /// - Returns: 使用 structured 输出和本地 TTS side effect 的首方 Agent Tool。
    public static func make() -> Tool {
        Tool(
            id: toolId,
            name: "English Tutor",
            icon: "graduationcap",
            description: "分析英语语法、给出自然改写并朗读练习句",
            kind: .agent(makeAgentTool()),
            visibleWhen: nil,
            displayMode: .structured,
            outputBinding: OutputBinding(primary: .structured, sideEffects: [.tts(voice: nil)]),
            permissions: [.systemAudio],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: ["agent", "skill", "english", "structured", "tts"]
        )
    }

    /// 构造 English Tutor Agent payload。
    private static func makeAgentTool() -> AgentTool {
        AgentTool(
            systemPrompt: """
            You are a concise English tutor. Return only a valid JSON object with these keys:
            correctedText, issues, explanation, practice, ttsText.
            Keep corrections concrete and avoid broad lectures.
            """,
            initialUserPrompt: """
            Analyze this English text and return structured tutoring feedback:

            {{selection}}
            """,
            contexts: [
                ContextRequest(
                    key: .init(rawValue: "selection"),
                    provider: "selection",
                    args: [:],
                    cachePolicy: .none,
                    requiredness: .required
                )
            ],
            provider: .capability(requires: [.toolCalling], prefer: []),
            skills: [SkillReference(id: toolId, pinVersion: nil)],
            mcpAllowlist: [],
            builtinCapabilities: [],
            maxSteps: 3,
            stopCondition: .finalAnswerProvided
        )
    }
}
