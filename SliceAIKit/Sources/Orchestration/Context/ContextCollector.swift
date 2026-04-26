import Foundation
import SliceCore

// MARK: - ContextProviderRegistry

/// 上下文提供方注册表（M2 Task 5 新增）
///
/// 设计要点：
/// - **存实例不存 metatype**：让同一 provider 实例在 `ContextCollector` 与未来的
///   `PermissionGraph` 间共享，避免重复初始化、便于注入 mock。
/// - 字典 key 是 provider 注册名（与 `ContextRequest.provider` 字段一致）；查找
///   失败由 `ContextCollector.resolve` 决策（required → throw / optional → failures）。
/// - 不可变 Sendable：构造后只读，多 actor 安全共享。
public struct ContextProviderRegistry: Sendable {
    /// `[provider name : 实例]` 字典；构造时一次性注入，运行期只读
    public let providers: [String: any ContextProvider]

    /// 构造注册表
    /// - Parameter providers: provider 注册名到实例的映射；调用方负责保证 key 唯一
    public init(providers: [String: any ContextProvider]) {
        self.providers = providers
    }
}

// MARK: - ContextCollector

/// 平铺并发拉取所有 `ContextRequest` 的 collector（spec §3.3.3 + §3.4 Step 3）
///
/// **D-17 约束**：严禁 DAG / 拓扑排序 / 互相依赖。所有 request 互相独立、用
/// `withThrowingTaskGroup` 平铺并发，让单点慢路径不拖累其他 request。
///
/// 失败语义：
/// - `Requiredness.required` 失败 → throw `SliceError.context(.requiredFailed(key:, underlying:))`，
///   group 自动取消所有兄弟任务（结构化并发的取消传播）。
/// - `Requiredness.optional` 失败 → 进 `ResolvedExecutionContext.failures[key]`，主流程继续。
/// - registry 找不到 provider → required 抛 `.context(.providerNotFound(id:))`；
///   optional 写入同 case 至 failures。
/// - 单 request 超时 → throw / failures 进 `.context(.timeout(key:))`。
/// - provider 抛非 SliceError 的底层错误（URLError / DecodingError 等）→ 包装为
///   `SliceError.provider(.networkTimeout)` 作为 underlying（见私有 helper `wrapAsSliceError`
///   的注释；M3+ 若需要更精细的错误大类再按需扩展，**但不在 Task 5 范围**）。
public actor ContextCollector {

    // MARK: - Stored

    /// 共享的 provider 注册表（实例存储）
    private let registry: ContextProviderRegistry

    /// 单 request 默认 timeout（M1 `ContextRequest` 暂无 timeout 字段；M3 加字段后从 request 读）
    ///
    /// 用 nanoseconds 而非 `Duration` 以兼容旧 macOS 14 SDK 的 `Task.sleep(nanoseconds:)` API。
    private static let defaultTimeoutNanoseconds: UInt64 = 5 * 1_000_000_000

    // MARK: - Init

    /// 构造 collector
    /// - Parameter registry: 共享的 `ContextProviderRegistry`（与未来的 `PermissionGraph`
    ///   共用同一实例，避免双重注册）
    public init(registry: ContextProviderRegistry) {
        self.registry = registry
    }

    // MARK: - Public API

    /// 平铺并发解析所有 `ContextRequest`，产出 `ResolvedExecutionContext`
    ///
    /// - Parameters:
    ///   - seed: 触发种子；其 `selection` 与 `frontApp` 透传给每个 provider
    ///   - requests: Tool 声明的 `ContextRequest` 列表
    /// - Returns: 解析结果（含 contexts + failures + resolvedAt）
    /// - Throws: `SliceError.context(.requiredFailed)` / `.providerNotFound` / `.timeout`
    ///   ——当 required request 失败时
    public func resolve(
        seed: ExecutionSeed,
        requests: [ContextRequest]
    ) async throws -> ResolvedExecutionContext {
        // 边界：requests 为空，直接返回空 ContextBag + 空 failures
        guard !requests.isEmpty else {
            return ResolvedExecutionContext(
                seed: seed,
                contexts: ContextBag(values: [:]),
                resolvedAt: Date(),
                failures: [:]
            )
        }

        // 收集成功值与可选失败；用本地 var，子任务通过 group 返回值汇总到这里
        var successes: [ContextKey: ContextValue] = [:]
        var failures: [ContextKey: SliceError] = [:]

        // withThrowingTaskGroup：required 失败时让 throw 直接冒泡 + group 自动取消其他兄弟任务
        try await withThrowingTaskGroup(of: ChildResult.self) { group in
            for request in requests {
                // 在主 task 体内捕获 request（值类型，跨 actor 安全）+ registry / seed
                let registry = self.registry
                let timeout = Self.defaultTimeoutNanoseconds
                group.addTask {
                    await Self.runOne(
                        request: request,
                        seed: seed,
                        registry: registry,
                        timeoutNanoseconds: timeout
                    )
                }
            }

            // 顺序消费 group 结果；遇到 .requiredFailure 直接 throw（自动取消未完成兄弟任务）
            for try await child in group {
                switch child {
                case .success(let key, let value):
                    successes[key] = value
                case .optionalFailure(let key, let error):
                    failures[key] = error
                case .requiredFailure(let error):
                    throw error
                }
            }
        }

        // 全部成功（或 optional 失败已记入 failures），构造最终上下文
        return ResolvedExecutionContext(
            seed: seed,
            contexts: ContextBag(values: successes),
            resolvedAt: Date(),
            failures: failures
        )
    }

    // MARK: - 私有：单 request 执行

    /// 子任务返回类型：把 success / optional 失败 / required 失败明确成 3 态，
    /// 让主任务消费时按 case 分流到 successes / failures / throw
    private enum ChildResult: Sendable {
        case success(key: ContextKey, value: ContextValue)
        case optionalFailure(key: ContextKey, error: SliceError)
        case requiredFailure(error: SliceError)
    }

    /// 跑一个 request（含 provider 路由 + timeout race + 错误分类）
    ///
    /// 标 `static` 让闭包不捕获 `self`，避免 actor isolation 跨边界传递问题。
    /// 所有依赖通过参数显式注入（值语义、Sendable）。
    private static func runOne(
        request: ContextRequest,
        seed: ExecutionSeed,
        registry: ContextProviderRegistry,
        timeoutNanoseconds: UInt64
    ) async -> ChildResult {
        // Step A：provider 路由。registry 未命中 → 按 requiredness 分流
        guard let provider = registry.providers[request.provider] else {
            let err = SliceError.context(.providerNotFound(id: request.provider))
            return classifyFailure(request: request, error: err)
        }

        // Step B：跑 provider.resolve + 同时跑 sleep；先到先返回（race）
        do {
            let value = try await raceWithTimeout(
                timeoutNanoseconds: timeoutNanoseconds,
                key: request.key
            ) {
                try await provider.resolve(
                    request: request,
                    seed: seed.selection,
                    app: seed.frontApp
                )
            }
            return .success(key: request.key, value: value)
        } catch let sliceErr as SliceError {
            // provider 抛 SliceError（含 raceWithTimeout 抛出的 .context(.timeout)）
            return classifyFailure(request: request, error: sliceErr)
        } catch {
            // 非 SliceError 的底层错误（URLError / DecodingError / IO 等）→ 包装为通用 SliceError
            // 详见 `wrapAsSliceError` 的注释：选用 `.provider(.networkTimeout)` 作为通用 wrapper。
            let wrapped = wrapAsSliceError(error)
            let outer = SliceError.context(.requiredFailed(key: request.key, underlying: wrapped))
            return classifyFailure(request: request, error: outer)
        }
    }

    /// 把 SliceError 按 requiredness 分流为 ChildResult.requiredFailure / .optionalFailure
    ///
    /// 对 required：若错误尚未被外层包装为 `.context(.requiredFailed)` 形态，则补一层包装，
    /// 让 ExecutionEngine 上层只需 match `SliceError.context(.requiredFailed(...))` 一种形态。
    private static func classifyFailure(
        request: ContextRequest,
        error: SliceError
    ) -> ChildResult {
        switch request.requiredness {
        case .required:
            let normalized = ensureRequiredFailedShape(key: request.key, error: error)
            return .requiredFailure(error: normalized)
        case .optional:
            // optional 直接落 failures map；保留原 SliceError 形态便于 prompt 模板按 case 降级
            return .optionalFailure(key: request.key, error: error)
        }
    }

    /// 把任意 SliceError 包成 `SliceError.context(.requiredFailed(key:, underlying:))` 形态
    ///
    /// 已经是 `.context(.requiredFailed)` 的不再包装；其他 SliceError（含 .context 的其他子 case
    /// 如 .providerNotFound / .timeout）都被外层 wrap 为 requiredFailed，让上层 match 模式统一。
    private static func ensureRequiredFailedShape(
        key: ContextKey,
        error: SliceError
    ) -> SliceError {
        if case .context(.requiredFailed) = error {
            return error
        }
        return .context(.requiredFailed(key: key, underlying: error))
    }

    /// 把"非 SliceError"的底层错误包装为 SliceError
    ///
    /// **设计决策**：选用 `.provider(.networkTimeout)` 作为通用 wrapper，理由：
    /// - SliceCore 现存 4 个顶层 case（selection / provider / configuration / permission）+
    ///   Task 5 新增的 .context 中，IO / 网络 / 解码类底层错误语义最贴近"provider 行为类问题"。
    /// - 选 networkTimeout 而非 invalidResponse 是因为后者带 String payload（用户文本），
    ///   wrapper 不应携带任何上下文信息，networkTimeout 无关联值最安全。
    /// - 信息丢失（URLError.code / DecodingError.context）是可接受代价：开发期可在 ContextCollector
    ///   入口另加日志（本任务暂未加，遵守 CLAUDE.md "无自由日志"规范——后续 Task 9 AuditLog 处理）。
    /// - 测试断言只到外层 `.context(.requiredFailed(key:, underlying: _))`，不锁死 wrapper 的具体形态，
    ///   留出未来调整空间。
    private static func wrapAsSliceError(_ error: any Error) -> SliceError {
        if let sliceErr = error as? SliceError {
            return sliceErr
        }
        return .provider(.networkTimeout)
    }

    /// 跑 work + sleep 的 race（先到先返回，另一边 cancel）
    ///
    /// 使用 `withThrowingTaskGroup` 而非 `Task.detached + race`：结构化并发能保证两个子任务
    /// 在本函数返回前必定完成 / 取消，无悬空 Task；并且子任务取消由 group 自动传播，无需手写
    /// cancel handler。
    ///
    /// - Parameters:
    ///   - timeoutNanoseconds: 超时阈值
    ///   - key: 用于构造 `.context(.timeout(key:))` 错误
    ///   - work: 真正要跑的异步工作（provider.resolve）
    /// - Returns: work 在超时前的返回值
    /// - Throws: work 自身的错误；或在超时时抛 `SliceError.context(.timeout(key:))`
    private static func raceWithTimeout(
        timeoutNanoseconds: UInt64,
        key: ContextKey,
        work: @escaping @Sendable () async throws -> ContextValue
    ) async throws -> ContextValue {
        try await withThrowingTaskGroup(of: ContextValue.self) { group in
            // 子任务 1：真正的工作
            group.addTask {
                try await work()
            }
            // 子任务 2：sleep；到点抛 timeout 错误，由 group 抛给外层
            group.addTask {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
                throw SliceError.context(.timeout(key: key))
            }

            // 取第一个完成的结果（成功或抛错），另一个由 group cancel 取消
            // group.next() 已确保 child throws 会冒泡——work 抛错 / sleep 到点抛 timeout 都会进 catch
            guard let first = try await group.next() else {
                // 理论不会发生：addTask 了两个子任务
                throw SliceError.context(.timeout(key: key))
            }
            // 显式取消未完成的兄弟任务（structured concurrency 在 group scope 退出时也会做，
            // 但这里立刻取消能更早释放 sleep 占用的 Task slot）
            group.cancelAll()
            return first
        }
    }
}
