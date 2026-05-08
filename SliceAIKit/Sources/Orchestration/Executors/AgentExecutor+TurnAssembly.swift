import Foundation
import SliceCore

/// 单轮 LLM 输出结果。
struct AgentTurn: Sendable {
    let assistantText: String
    let toolCalls: [ChatToolCall]
}

/// 聚合 streaming tool_call delta。
struct AgentToolCallAssembler: Sendable {
    private struct Partial: Sendable {
        var id: String?
        var name: String?
        var arguments = ""
    }

    private var partials: [Int: Partial] = [:]

    /// 构造空 assembler。
    init() {}

    /// 应用一片 delta。
    mutating func apply(_ delta: ChatToolCallDelta) {
        var partial = partials[delta.index] ?? Partial()
        if let id = delta.id { partial.id = id }
        if let name = delta.name { partial.name = name }
        partial.arguments += delta.argumentsDelta
        partials[delta.index] = partial
    }

    /// 组装完整 ChatToolCall。
    func assemble() throws -> [ChatToolCall] {
        try partials.keys.sorted().map { index in
            guard let partial = partials[index],
                  let id = partial.id,
                  let name = partial.name else {
                throw SliceError.provider(.invalidResponse("missing tool call id or name"))
            }
            return ChatToolCall(id: id, name: name, argumentsRaw: partial.arguments)
        }
    }
}
