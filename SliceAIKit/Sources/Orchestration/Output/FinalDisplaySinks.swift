import Foundation

/// `.bubble` DisplayMode 的 final-only 展示 sink。
public protocol BubbleOutputSink: Sendable {

    /// 展示完整 final text。
    ///
    /// - Parameters:
    ///   - finalText: LLM 完整最终输出。
    ///   - context: 当前输出生命周期上下文。
    func showBubble(finalText: String, context: OutputInvocationContext) async throws
}

/// `.structured` DisplayMode 的 final-only 展示 sink。
public protocol StructuredOutputSink: Sendable {

    /// 展示完整 final text，并由 sink 负责解析和渲染。
    ///
    /// - Parameters:
    ///   - finalText: LLM 完整最终输出。
    ///   - context: 当前输出生命周期上下文。
    func showStructured(finalText: String, context: OutputInvocationContext) async throws
}
