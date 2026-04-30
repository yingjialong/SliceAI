import Foundation
import SliceCore

/// PromptExecutor.run 的流式输出元素
///
/// **设计权衡**：早期方案曾尝试 `onCompletion: @escaping @Sendable (UsageStats) -> Void` 回调
/// 把最终 usage 透出，但 Swift 6 `StrictConcurrency=complete` 下，`@Sendable` 闭包不能捕获并修改
/// caller 的可变局部变量（典型场景：`ExecutionEngine.runMainFlow` 顶层的 `var promptUsage`）。
/// 改用枚举 stream + 顶层 `for try await` 顺序消费 → caller 直接读 local var 写入 `promptUsage`，
/// 无跨 task 边界，Swift 6 编译通过。
public enum PromptStreamElement: Sendable, Equatable {
    /// LLM 流式输出的一个增量片段
    case chunk(String)
    /// LLM stream 结束时一次性发出，携带最终 usage 估算
    ///
    /// 出现位置约定：永远是 stream 末尾（在所有 `.chunk(_)` 之后、`continuation.finish()` 之前）。
    /// 流空也至少发一次 `.completed(.zero)`，让 caller 一律按 `[chunk]* + completed` 模式消费。
    case completed(UsageStats)
}

/// LLM 调用的 token 使用统计
///
/// **M2 阶段**：由 `PromptExecutor` 内部按"输入消息总字符数 / 4"+"输出 chunk 累计字符数 / 4"
/// 估算（spec §4.4.2 经验值，OpenAI 英文约 3-4 chars/token，中文偏低，4 是保守上界）。
/// **Phase 1+**：`LLMProvider` protocol 加入 usage 字段后，本类型的字段透传 LLM 真实
/// `prompt_tokens` / `completion_tokens`，估算逻辑下线。
public struct UsageStats: Sendable, Equatable {
    /// 输入 prompt 的 token 数
    public let inputTokens: Int
    /// 输出 completion 的 token 数
    public let outputTokens: Int

    /// 构造 UsageStats
    /// - Parameters:
    ///   - inputTokens: 输入 token 数
    ///   - outputTokens: 输出 token 数
    public init(inputTokens: Int, outputTokens: Int) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
    }

    /// 全零 usage；用作 ExecutionEngine 顶层 `var promptUsage` 的初值
    public static let zero = UsageStats(inputTokens: 0, outputTokens: 0)
}

/// Prompt 执行器：渲染 prompt → 取 API Key → 调 LLMProvider 流式
///
/// **来源**：本类型由 legacy prompt 执行流程**复制并改造**而来。
/// 关键差异：
/// 1. 入参类型从 v1 `Tool` / `SelectionPayload` 改为 v2 `PromptTool` / `ResolvedExecutionContext`；
/// 2. 入参 `provider: Provider`，直接传给 `LLMProviderFactory.make(for:apiKey:)`；
/// 3. 流元素从 `ChatChunk` 改为 `PromptStreamElement`，在 stream 末尾追加一次 `.completed(UsageStats)`。
///
/// **协议族支持范围（M2）**：仅 `.openAICompatible`；其他 kind（`.anthropic` / `.gemini` / `.ollama`）
/// 由 Phase 1+ 落地的 native provider 处理，本阶段直接 throw `.validationFailed`。
///
/// **并发模型**：
/// - `actor` 隔离 `keychain` / `llmProviderFactory` 引用，避免多次并发触发时内部依赖被竞争访问；
/// - `run(...)` 是 actor-isolated 同步方法（默认隔离，无 `async` / 无 `nonisolated`），跨 actor 边界
///   通过 `await` 调用即可拿到 stream（plan §C-10.1 audit 表）；
/// - stream closure 是 `@Sendable`、不在 actor 隔离内执行；闭包内用 `Task { [weak self] in ... }`
///   跨边界把工作交给 actor-isolated `runInternal`，从而合法访问 `self.keychain` / `self.llmProviderFactory`。
public actor PromptExecutor {

    /// Keychain 访问协议，按 `Provider.keychainAccount` 的 account 名读取 API Key
    private let keychain: any KeychainAccessing
    /// LLM Provider 工厂，直接消费 Provider
    private let llmProviderFactory: any LLMProviderFactory

    /// 构造 PromptExecutor
    /// - Parameters:
    ///   - keychain: Keychain 访问实现（生产用真实 Keychain，测试注入 Fake）
    ///   - llmProviderFactory: 创建 LLMProvider 实例的工厂
    public init(
        keychain: any KeychainAccessing,
        llmProviderFactory: any LLMProviderFactory
    ) {
        self.keychain = keychain
        self.llmProviderFactory = llmProviderFactory
    }

    // MARK: - Public API

    /// 执行一次 prompt 渲染 + LLM 流式调用
    ///
    /// 流式语义：
    /// - `[.chunk(String)]*` 0 或多次（按 LLMProvider 实际产出）
    /// - 末尾 `.completed(UsageStats)` 恰好 1 次
    /// - 然后 stream finish；任何阶段抛错则 stream finish(throwing:)，已 yield 的 chunk 不撤回
    ///
    /// 调用约定（与 plan §C-10.1 audit 表对齐）：
    /// - 跨 actor 取 stream 必须 `await`：`let s = await promptExecutor.run(...)`
    /// - 不需要 `try`：本方法本身不 throws；错误延迟到 `for try await element in s` 处抛出
    ///
    /// **取消语义**：保存内部 producer Task handle 并通过 `continuation.onTermination` 在
    /// stream consumer drop iterator（如 ExecutionEngine 外层 task cancel / 测试 break for-await）
    /// 时主动 `task.cancel()`。runInternal 在 keychain / LLM stream 等关键 await 边界显式
    /// `try Task.checkCancellation()`，让 cancel 信号 cascade 到 LLMProvider.stream 内部
    /// （URLSession byte stream 通过其自身 onTermination 链终止）——避免 consumer 已离场后
    /// 仍持续消耗网络 / token / 计费。
    ///
    /// - Parameters:
    ///   - promptTool: PromptTool 配置（systemPrompt / userPrompt / variables / temperature / maxTokens）
    ///   - resolved: ContextCollector 已解析的执行上下文（提供 selection.text / frontApp 用于变量注入）
    ///   - provider: Provider 配置；M2 仅支持 `kind == .openAICompatible`
    /// - Returns: AsyncThrowingStream of `PromptStreamElement`
    public func run(
        promptTool: PromptTool,
        resolved: ResolvedExecutionContext,
        provider: Provider
    ) -> AsyncThrowingStream<PromptStreamElement, any Error> {
        // 注：stream closure 是 @Sendable 非 actor-isolated；闭包内必须用 Task { [weak self] in ... }
        // 跨边界跳进 actor，才能访问 self.keychain / self.llmProviderFactory（actor state）
        AsyncThrowingStream { continuation in
            // 保存 task handle，让 onTermination 能 cancel 到内部 producer。
            // Task.init（unstructured）不继承外层 task 的 cancellation —— 必须手动桥接。
            let task = Task { [weak self] in
                guard let self else {
                    // self 已释放（执行引擎销毁）：以取消语义结束 stream，调用方 catch CancellationError 处理
                    continuation.finish(throwing: CancellationError())
                    return
                }
                do {
                    try await self.runInternal(
                        promptTool: promptTool,
                        resolved: resolved,
                        provider: provider,
                        continuation: continuation
                    )
                    continuation.finish()
                } catch is CancellationError {
                    // 静默取消：consumer drop iterator 已触发 onTermination → continuation 已 drain。
                    // 不 finish(throwing:) 以避免 ExecutionEngine.runPromptStream 的 catch 路径误报。
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            // consumer drop iterator → onTermination → task.cancel() → runInternal 内部
            // `try Task.checkCancellation()` / `Task.sleep` / cooperative `for try await` 抛
            // CancellationError → 上面 catch is CancellationError 静默 finish。
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Actor-isolated 主流程

    /// `run` 内部承载主流程的 actor-isolated 方法。
    ///
    /// 步骤分解：
    /// 1. provider preflight：先检查协议族 / endpoint，再读 Keychain
    /// 2. 解析 keychainAccount + 读取 API Key（空字符串视为缺失）
    /// 3. 注入内置变量（覆盖同名工具变量）
    /// 4. 渲染 systemPrompt / userPrompt → ChatMessage 数组
    /// 5. 估算 inputTokens（输入消息总字符数 / 4，下限 1）
    /// 6. 创建 LLMProvider 实例并启动流式
    /// 7. 转发 ChatChunk.delta 为 PromptStreamElement.chunk + 累计输出字符数
    /// 8. 流结束后估算 outputTokens 并 yield .completed(UsageStats)
    private func runInternal(
        promptTool: PromptTool,
        resolved: ResolvedExecutionContext,
        provider: Provider,
        continuation: AsyncThrowingStream<PromptStreamElement, any Error>.Continuation
    ) async throws {
        // 1. provider preflight：先检查协议族 / endpoint，再读 Keychain。
        //    这样 unsupported kind 不会被误报为"未配置 API Key"。
        try llmProviderFactory.validate(provider: provider)

        // 2. 解析 Keychain account；非 keychain: 前缀或空 API Key 一律按未授权处理
        guard let account = provider.keychainAccount else {
            throw SliceError.provider(.unauthorized)
        }
        // 取消短路：keychain 实现（含生产 Keychain）可能不响应 cooperative cancel；
        // consumer drop iterator 时显式 check 让 task.cancel() 立即抛 CancellationError，
        // 避免读 Keychain 触发系统授权弹窗 / 占用 IO。
        try Task.checkCancellation()
        guard let apiKey = try await keychain.readAPIKey(providerId: account),
              !apiKey.isEmpty else {
            throw SliceError.provider(.unauthorized)
        }

        // 3. 注入内置变量
        //    约定：内置变量总是覆盖同名工具变量，避免用户配置
        //    `variables = ["selection": "..."]` 把真实选区盖掉
        let messages = renderMessages(promptTool: promptTool, resolved: resolved)

        // 4. 构造 ChatRequest
        //    model 选择：promptTool.provider.fixed.modelId 优先，缺省 fall back provider.defaultModel。
        //    与 legacy 执行器的 `tool.modelId ?? provider.defaultModel` 同口径——
        //    ProviderResolver 当前不消费 modelId（见 ProviderResolverProtocol 文档），由本层解析；
        //    M3 切换到新执行链路后用户工具级 modelId 不再被静默换成 provider.defaultModel。
        let selectedModel = Self.resolveModel(
            selection: promptTool.provider, fallback: provider.defaultModel
        )
        let request = ChatRequest(
            model: selectedModel,
            messages: messages,
            temperature: promptTool.temperature,
            maxTokens: promptTool.maxTokens
        )

        // 5. 估算 inputTokens（M2：所有 message content 字符数累加 / 4；下限 1，避免空输入算成 0）
        let inputCharCount = messages.reduce(0) { $0 + $1.content.count }
        let inputTokens = max(1, inputCharCount / 4)

        // 6. 工厂创建 LLMProvider 实例 + 启动流式调用
        let llm = try llmProviderFactory.make(for: provider, apiKey: apiKey)
        // 取消短路：llm.stream 内部立即发起 URLSession 连接 / token 消耗；
        // consumer drop iterator 时让 task.cancel() 在网络握手前抛错，避免计费。
        try Task.checkCancellation()
        let chatStream = try await llm.stream(request: request)

        // 7. 转发 chunks 并累计输出字符数
        var outputCharCount = 0
        for try await chatChunk in chatStream {
            outputCharCount += chatChunk.delta.count
            continuation.yield(.chunk(chatChunk.delta))
        }

        // 8. 估算 outputTokens 并发出 .completed
        //    空输出（0 chunk 或 chunk delta 全为空）也允许 outputTokens=0；调用方按 .completed 收口
        let outputTokens = max(0, outputCharCount / 4)
        continuation.yield(.completed(UsageStats(inputTokens: inputTokens, outputTokens: outputTokens)))
    }

    // MARK: - Private helpers

    /// 渲染 ChatMessage 数组：注入内置变量 + 应用 mustache 模板
    ///
    /// 拆出 helper 是为了让 `runInternal` 的函数体长度落在 swiftlint 80 行硬上限以内，
    /// 同时保持渲染逻辑可单独测试 / 阅读。返回数组顺序与 legacy 执行器一致：
    /// 若 systemPrompt 非空，先 system 后 user；否则只有 user。
    private func renderMessages(
        promptTool: PromptTool,
        resolved: ResolvedExecutionContext
    ) -> [ChatMessage] {
        // 注入内置变量：内置覆盖工具自定义同名 key
        var variables: [String: String] = promptTool.variables
        variables["selection"] = resolved.selection.text
        variables["app"] = resolved.frontApp.name
        variables["url"] = resolved.frontApp.url?.absoluteString ?? ""
        // language 缺省补空串，避免 {{language}} 字面残留在 prompt 里
        if variables["language"] == nil { variables["language"] = "" }

        let userText = PromptTemplate.render(promptTool.userPrompt, variables: variables)
        var messages: [ChatMessage] = []
        if let sys = promptTool.systemPrompt, !sys.isEmpty {
            let systemText = PromptTemplate.render(sys, variables: variables)
            messages.append(ChatMessage(role: .system, content: systemText))
        }
        messages.append(ChatMessage(role: .user, content: userText))
        return messages
    }

    /// 解析工具级 model override：与 legacy 执行器同口径
    ///
    /// `nonisolated` + `private static`：纯函数，无 actor 状态依赖，不引入 actor hop。
    /// pipeline / capability / cascade 三种 selection 形态都没有顶层 modelId override 概念，
    /// 一致回 fallback；只有 `.fixed(providerId, modelId:)` 且 modelId 非 nil 时才走 override。
    private nonisolated static func resolveModel(
        selection: ProviderSelection, fallback: String
    ) -> String {
        if case .fixed(_, let modelId) = selection, let modelId {
            return modelId
        }
        return fallback
    }

}
