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
/// **来源**：本类型由 v1 `SliceCore/ToolExecutor.swift` 的 `execute` 主流程**复制并改造**而来
/// （§C-7 复制非替换；ToolExecutor.swift 在本阶段保留不动，M3 rename pass 删除）。
/// 关键差异：
/// 1. 入参类型从 v1 `Tool` / `SelectionPayload` 改为 v2 `PromptTool` / `ResolvedExecutionContext`；
/// 2. 入参 `provider: V2Provider`（而非 v1 `Provider`），内部用 helper 适配为 v1 `Provider` 视图，
///    再调既有 `LLMProviderFactory.make(for:apiKey:)`（M2 阶段 LLMProviderFactory zero-touch；
///    M3 一并升级到 V2Provider）；
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

    /// Keychain 访问协议，按 v1 `Provider.keychainAccount` 的 account 名读取 API Key
    private let keychain: any KeychainAccessing
    /// LLM Provider 工厂（v1 类型）；M3 升级到 V2Provider 后本字段类型变更、`toV1Provider` helper 删除
    private let llmProviderFactory: any LLMProviderFactory

    /// 构造 PromptExecutor
    /// - Parameters:
    ///   - keychain: Keychain 访问实现（生产用真实 Keychain，测试注入 Fake）
    ///   - llmProviderFactory: 创建 LLMProvider 实例的工厂（M2 仍用 v1 形态，M3 升级 V2Provider）
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
    /// - Parameters:
    ///   - promptTool: PromptTool 配置（systemPrompt / userPrompt / variables / temperature / maxTokens）
    ///   - resolved: ContextCollector 已解析的执行上下文（提供 selection.text / frontApp 用于变量注入）
    ///   - provider: V2Provider 配置；M2 仅支持 `kind == .openAICompatible`
    /// - Returns: AsyncThrowingStream of `PromptStreamElement`
    public func run(
        promptTool: PromptTool,
        resolved: ResolvedExecutionContext,
        provider: V2Provider
    ) -> AsyncThrowingStream<PromptStreamElement, any Error> {
        // 注：stream closure 是 @Sendable 非 actor-isolated；闭包内必须用 Task { [weak self] in ... }
        // 跨边界跳进 actor，才能访问 self.keychain / self.llmProviderFactory（actor state）
        AsyncThrowingStream { continuation in
            Task { [weak self] in
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
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Actor-isolated 主流程

    /// `run` 内部承载主流程的 actor-isolated 方法；与 v1 ToolExecutor.execute 步骤一一对应
    ///
    /// 步骤分解：
    /// 1. V2Provider → v1 Provider 适配（限定 .openAICompatible）
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
        provider: V2Provider,
        continuation: AsyncThrowingStream<PromptStreamElement, any Error>.Continuation
    ) async throws {
        // 1. V2Provider → v1 Provider 适配
        let v1Provider = try toV1Provider(provider)

        // 2. 解析 Keychain account；非 keychain: 前缀或空 API Key 一律按未授权处理
        guard let account = v1Provider.keychainAccount else {
            throw SliceError.provider(.unauthorized)
        }
        guard let apiKey = try await keychain.readAPIKey(providerId: account),
              !apiKey.isEmpty else {
            throw SliceError.provider(.unauthorized)
        }

        // 3. 注入内置变量
        //    约定：内置变量总是覆盖同名工具变量（与 v1 ToolExecutor 行为一致），避免用户配置
        //    `variables = ["selection": "..."]` 把真实选区盖掉
        let messages = renderMessages(promptTool: promptTool, resolved: resolved)

        // 5. 构造 ChatRequest
        //    model 选择：v1Provider.defaultModel
        //    （ProviderSelection.fixed.modelId 已由 Task 2 ProviderResolver 解析阶段固化为
        //    V2Provider.defaultModel；本层不重复解析，避免双源真理）
        let request = ChatRequest(
            model: v1Provider.defaultModel,
            messages: messages,
            temperature: promptTool.temperature,
            maxTokens: promptTool.maxTokens
        )

        // 估算 inputTokens（M2：所有 message content 字符数累加 / 4；下限 1，避免空输入算成 0）
        let inputCharCount = messages.reduce(0) { $0 + $1.content.count }
        let inputTokens = max(1, inputCharCount / 4)

        // 6. 工厂创建 LLMProvider 实例 + 启动流式调用
        let llm = try llmProviderFactory.make(for: v1Provider, apiKey: apiKey)
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
    /// 同时保持渲染逻辑可单独测试 / 阅读。返回数组顺序与 v1 ToolExecutor 一致：
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

    /// V2Provider → v1 Provider 适配
    ///
    /// **范围限制（M2）**：仅 `.openAICompatible` 通过；其他 kind 抛 `.validationFailed`，
    /// caller（ExecutionEngine Step 6）通过 `for try await` 第一次 `next()` 即拿到错误，
    /// 走 `finishFailure` 路径输出 `.failed` 事件。
    /// 严禁 `fatalError` / `!` 强解包：V2Provider 在 init / decode 时虽已校验 `.openAICompatible`
    /// 必须有 baseURL，但仍用 `guard let` 兜底（防御性，避免 V2Provider 来源不经 decoder 时崩）。
    private func toV1Provider(_ v2: V2Provider) throws -> Provider {
        guard v2.kind == .openAICompatible else {
            throw SliceError.configuration(.validationFailed(
                "PromptExecutor M2 only supports .openAICompatible providers; "
                + "\(v2.id) is .\(v2.kind.rawValue)"
            ))
        }
        guard let baseURL = v2.baseURL else {
            throw SliceError.configuration(.validationFailed(
                "V2Provider \(v2.id) (.openAICompatible) has nil baseURL"
            ))
        }
        // v1 Provider 的 5 参数 init：id / name / baseURL / apiKeyRef / defaultModel
        return Provider(
            id: v2.id,
            name: v2.name,
            baseURL: baseURL,
            apiKeyRef: v2.apiKeyRef,
            defaultModel: v2.defaultModel
        )
    }
}
