# Phase 2 Completion Spec

## 目标

把 Phase 2 从“Skill Registry 已可用”推进到“Skill + 多 DisplayMode”真正完成：`bubble / replace / file / silent / structured` 不再 fallback 到 window，side effects 能实际执行，TTS 可用，并提供首方 `english-tutor` Agent Tool 作为端到端示范。

## 当前事实

已完成：

- 本地 Skill Registry MVP：skill roots、`SKILL.md` parser/scanner、Skills 设置页、Agent Tool 最多 5 个 skill 绑定。
- `sliceai_load_skill` 渐进式加载。
- 真实本地 Claude / Codex 风格 Skill E2E。
- 公开 Anthropic / OpenAI / Codex skill 仓库 smoke。
- `sliceai_load_skill_resource` supporting files 只读加载：`references/` 与文本型 `assets/` 可按需读取，`scripts/` 不读取、不执行。

仍未完成：

- `OutputDispatcher` 当前只有 `.window` 真实 sink；其它 5 个 mode fallback 到 window。
- `ExecutionEngine.runSideEffects` 当前只做 PermissionBroker gate、事件和 audit，不执行真实副作用。
- `BubblePanel`、`InlineReplaceOverlay`、`StructuredResultView` 尚未实现。
- TTS capability 尚未实现。
- `english-tutor` 内置 Agent Tool 尚未实现。

## 范围

本 spec 包含：

- Output lifecycle foundation：让输出 sink 能收到 begin / chunk / finish / fail，并拿到最终文本。
- 多 DisplayMode：
  - `.window` 保持现有 ResultPanel 行为。
  - `.silent` 不展示 UI，只收集最终文本并执行 side effects。
  - `.file` 将最终文本 append 到配置声明的文件路径。
  - `.replace` 在最终输出完成后替换当前选区；失败时降级为复制到剪贴板并通知用户。
  - `.bubble` 用小气泡展示最终摘要，2.5 秒自动消失。
  - `.structured` 将最终 JSON 渲染为结构化视图，至少支持 string、number、bool、enum-like string、array、object。
- SideEffect 实执行：
  - `appendToFile`
  - `copyToClipboard`
  - `notify`
  - `callMCP`
  - `tts`
- TTS：
  - 默认本地 `AVSpeechSynthesizer`。
  - 可选 OpenAI-compatible TTS 预留为配置项与 provider adapter；默认不开启。
- English Tutor：
  - 首方内置 Agent Tool。
  - 使用 skill + structured output + TTS side effect。
  - 对新配置默认可见；旧 v3 配置迁移到 v4 时只追加一次。
- 文档、测试、release gate。

## 明确不做

- 不执行 skill `scripts/`，不读取 `scripts/` 内容。
- 不实现 marketplace、远端安装、自动更新、`.slicepack`。
- 不实现 PipelineExecutor；`.pipeline` 继续留到 Phase 5。
- 不实现真正 `writeMemory`；该 side effect 在本阶段返回受控 unsupported 结果。
- 不实现原生 Anthropic / Gemini / Ollama provider。
- 不做复杂 JSON Schema 完整验证器；`structured` 本阶段只做 KISS 渲染和安全解析。
- 不把 OpenAI TTS 作为默认路径；默认使用系统本地 TTS，避免引入额外网络和成本。

## 设计决策

### Output Lifecycle

现有 `OutputDispatcherProtocol.handle(chunk:mode:invocationId:)` 只能处理流式 chunk，无法支持只在最终文本后执行的 `.replace`、`.file`、`.structured` 和 TTS。新增生命周期 API：

```swift
public struct OutputInvocationContext: Sendable, Equatable {
    public let invocationId: UUID
    public let toolId: String
    public let toolName: String
    public let mode: DisplayMode
    public let screenAnchor: CGPoint
}

public protocol OutputDispatcherProtocol: Sendable {
    func begin(context: OutputInvocationContext) async throws
    func handle(chunk: String, context: OutputInvocationContext) async throws -> DispatchOutcome
    func finish(finalText: String, context: OutputInvocationContext) async throws
    func fail(error: SliceError, context: OutputInvocationContext) async
}
```

兼容原则：

- `Tool.displayMode` 仍是单一事实源。
- `OutputBinding.primary` 若存在，必须与 `Tool.displayMode` 一致。
- `.replace`、`.file`、`.structured` 都以最终文本为输入，不做逐 chunk 破坏性操作。
- 输出 sink 不记录完整用户选区或完整模型输出到日志。

### SideEffect Executor

新增 `SideEffectExecutorProtocol`，由 `ExecutionEngine.runSideEffects` 在 gate 通过后调用。该 executor 与 `OutputDispatcher` 解耦，避免把副作用混进展示 sink。

执行策略：

- dry-run：只 yield `.sideEffectSkippedDryRun`，不执行。
- gate deny / consent missing：标记 partial failure，不中止主输出。
- side effect 执行失败：yield 受控错误事件并标记 partial failure；不回滚已经完成的主输出。
- `writeMemory`：本阶段明确 unsupported，返回 partial failure，并在文档标记 Phase 3+。

### DisplayMode 权限

- `.file` 要求 Tool 声明目标路径的 `.fileWrite` 权限；推荐通过 `outputBinding.sideEffects` 中的 `.appendToFile` 表达目标。
- `.replace` 需要 `.clipboard` 权限，因为 fallback 会写剪贴板；AX 直接 setSelectedText 不新增 Permission case。
- `.silent` 本身不新增权限；只执行 side effects 的权限。
- `.structured` 本身不新增权限。
- `.bubble` 本身不新增权限。

### TTS

默认本地 TTS：

- 使用 `AVSpeechSynthesizer`。
- `SideEffect.tts(voice:)` 映射到 `.systemAudio`。
- voice 未配置时使用系统默认声音。

可选远端 TTS：

- 作为后续可配置 adapter 留接口，不作为默认。
- OpenAI 当前官方 TTS 可使用 `gpt-4o-mini-tts`；默认 voice 选择 `marin`。
- UI / 文档需要提示远端 TTS 会把文本发送到 provider，并可能产生费用。

### English Tutor

`english-tutor` 是 Phase 2 demo tool，不是独立产品线。它证明以下链路贯通：

- Agent Tool 绑定首方 skill。
- skill instructions 渐进式加载。
- structured 输出解析和展示。
- TTS side effect 朗读改写句子。

输出结构采用固定 JSON，避免本阶段引入完整 schema engine：

```json
{
  "issues": [
    {
      "type": "grammar",
      "original": "He go to school.",
      "suggestion": "He goes to school.",
      "explanation": "Subject-verb agreement requires 'goes'."
    }
  ],
  "rewrites": {
    "natural": "He goes to school.",
    "polished": "He attends school."
  },
  "practice": [
    "Make one sentence using 'goes'."
  ],
  "ttsText": "He goes to school."
}
```

## 验收标准

- `.bubble / .replace / .file / .silent / .structured` 不再 fallback 到 `.window`。
- `OutputDispatcher` focused tests 覆盖 begin/chunk/finish/fail 生命周期。
- `ExecutionEngine` focused tests 证明 final text 能传递到 output finish 与 side effect executor。
- `appendToFile / copyToClipboard / notify / callMCP / tts` 都有 executor 测试。
- `.replace` 在 Notes / VSCode 实机通过；Slack / Figma 不可写时降级为复制 + 通知。
- `.structured` 支持至少 5 种字段类型并有 Windowing 状态模型测试。
- `english-tutor` 默认配置存在，能通过 Agent Tool 路径输出结构化 JSON 并触发 TTS side effect。
- `swift test --package-path SliceAIKit`、`swiftlint lint --strict`、`git diff --check`、`xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 通过。

