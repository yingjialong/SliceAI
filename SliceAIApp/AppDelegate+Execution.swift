// SliceAIApp/AppDelegate+Execution.swift
import Foundation
import Orchestration
import OSLog
import SelectionCapture
import SliceCore
import Windowing

// MARK: - V2 Execution

/// 单次 V2 工具执行在 UI 层需要反复透传的上下文。
private struct ExecutionStreamContext {

    /// 当前执行的 V2 工具。
    let tool: SliceCore.V2Tool

    /// 当前选区 payload。
    let payload: SelectionPayload

    /// 当前触发来源。
    let triggerSource: TriggerSource

    /// 当前 invocation 标识。
    let invocationId: UUID
}

@MainActor
extension AppDelegate {

    /// 触发一次 V2 工具执行：设置 single-flight gate → 打开结果窗 → 消费 ExecutionEngine 事件流。
    ///
    /// 关键顺序：
    ///   1. 取消旧 stream task；
    ///   2. 用当前 payload 构造 `ExecutionSeed`；
    ///   3. 先把 `InvocationGate` 切到新 invocationId；
    ///   4. 再打开 ResultPanel 并启动 stream 消费。
    ///
    /// 这样旧 invocation 的 chunk / finish / fail 事件都会被 gate 拦截，不会污染新面板。
    /// - Parameters:
    ///   - tool: 要执行的 V2 工具定义。
    ///   - payload: 选中文字及其来源上下文。
    ///   - triggerSource: 触发来源，用于审计和后续遥测区分浮条 / 命令面板等路径。
    func execute(
        tool: SliceCore.V2Tool,
        payload: SelectionPayload,
        triggerSource: TriggerSource = .floatingToolbar
    ) {
        guard let container else { return }
        streamTask?.cancel()

        let seed = payload.toExecutionSeed(triggerSource: triggerSource)
        let invocationId = seed.invocationId
        container.invocationGate.setActiveInvocation(invocationId)

        openResultPanel(
            tool: tool,
            payload: payload,
            triggerSource: triggerSource,
            invocationId: invocationId
        )
        startExecutionStream(
            tool: tool,
            payload: payload,
            triggerSource: triggerSource,
            seed: seed,
            invocationId: invocationId
        )
    }

    /// 打开结果面板，并接入 dismiss / regenerate 对 invocation gate 的生命周期控制。
    /// - Parameters:
    ///   - tool: 当前执行的 V2 工具。
    ///   - payload: 当前选区 payload。
    ///   - triggerSource: 当前触发来源。
    ///   - invocationId: 当前 invocation 标识。
    private func openResultPanel(
        tool: SliceCore.V2Tool,
        payload: SelectionPayload,
        triggerSource: TriggerSource,
        invocationId: UUID
    ) {
        guard let container else { return }
        container.resultPanel.open(
            toolName: tool.name,
            model: Self.modelLabel(for: tool),
            anchor: payload.screenPoint,
            onDismiss: { [weak self] in
                self?.streamTask?.cancel()
                self?.container?.invocationGate.clearActiveInvocation(ifCurrent: invocationId)
            },
            onRegenerate: { [weak self] in
                self?.streamTask?.cancel()
                let source = triggerSource.rawValue
                Self.log.info(
                    "onRegenerate: re-running tool=\(tool.name, privacy: .public) source=\(source, privacy: .public)"
                )
                self?.execute(tool: tool, payload: payload, triggerSource: triggerSource)
            }
        )
    }

    /// 启动并消费 ExecutionEngine 事件流。
    /// - Parameters:
    ///   - tool: 当前执行的 V2 工具。
    ///   - payload: 当前选区 payload。
    ///   - triggerSource: 当前触发来源。
    ///   - seed: 由 payload 映射出的执行种子。
    ///   - invocationId: 当前 invocation 标识。
    private func startExecutionStream(
        tool: SliceCore.V2Tool,
        payload: SelectionPayload,
        triggerSource: TriggerSource,
        seed: ExecutionSeed,
        invocationId: UUID
    ) {
        guard let container else { return }
        let context = ExecutionStreamContext(
            tool: tool,
            payload: payload,
            triggerSource: triggerSource,
            invocationId: invocationId
        )
        let stream = container.executionEngine.execute(tool: tool, seed: seed)
        let consumer = ExecutionEventConsumer(
            onRetry: { [weak self] in self?.execute(tool: tool, payload: payload, triggerSource: triggerSource) },
            onOpenSettings: { [weak self] in self?.showSettings() }
        )

        streamTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer {
                self.container?.invocationGate.clearActiveInvocation(ifCurrent: invocationId)
            }
            await self.consumeExecutionStream(
                stream,
                consumer: consumer,
                context: context
            )
        }
    }

    /// 顺序消费事件流，并只接受当前 active invocation 的事件。
    /// - Parameters:
    ///   - stream: ExecutionEngine 返回的事件流。
    ///   - consumer: 将事件翻译到 ResultPanel 的消费者。
    ///   - context: 当前执行上下文。
    private func consumeExecutionStream(
        _ stream: AsyncThrowingStream<ExecutionEvent, any Error>,
        consumer: ExecutionEventConsumer,
        context: ExecutionStreamContext
    ) async {
        do {
            for try await event in stream {
                guard container?.invocationGate.shouldAccept(invocationId: context.invocationId) == true else {
                    continue
                }
                guard let panel = container?.resultPanel else { return }
                consumer.handle(event, panel: panel)
            }
        } catch is CancellationError {
            return
        } catch let urlError as URLError where urlError.code == .cancelled {
            return
        } catch let sliceError as SliceError {
            showExecutionFailure(
                sliceError,
                context: context
            )
        } catch {
            showExecutionFailure(
                .execution(.unknown(error.localizedDescription)),
                context: context
            )
        }
    }

    /// 将执行错误写入结果面板，并保持 retry / settings 操作可用。
    /// - Parameters:
    ///   - error: 要展示的 SliceError。
    ///   - context: 当前执行上下文。
    private func showExecutionFailure(
        _ error: SliceError,
        context: ExecutionStreamContext
    ) {
        guard container?.invocationGate.shouldAccept(invocationId: context.invocationId) == true else {
            return
        }
        container?.resultPanel.fail(
            with: error,
            onRetry: { [weak self] in
                self?.execute(
                    tool: context.tool,
                    payload: context.payload,
                    triggerSource: context.triggerSource
                )
            },
            onOpenSettings: { [weak self] in self?.showSettings() }
        )
    }

    /// 为结果面板标题提取模型标签。
    /// - Parameter tool: 当前执行的 V2 工具。
    /// - Returns: prompt/fixed provider 的 modelId，无法确定时返回 `"default"`。
    private static func modelLabel(for tool: SliceCore.V2Tool) -> String {
        guard case .prompt(let promptTool) = tool.kind else { return "default" }
        if case .fixed(_, let modelId) = promptTool.provider {
            return modelId ?? "default"
        }
        return "default"
    }
}
