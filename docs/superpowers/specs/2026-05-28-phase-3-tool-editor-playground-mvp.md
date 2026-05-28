# Phase 3 ToolEditor v2 + Prompt Playground MVP Spec

> Status: Draft for user review
> Date: 2026-05-28
> Branch: `codex/phase2-completion`
> Scope: Phase 3 first frozen slice only

## 1. Background

SliceAI 已完成 Phase 2 completion：Skill Registry MVP、真实本地 skill E2E、公开 skill 仓库 smoke、supporting files 只读加载、Output lifecycle、SideEffect executor、多 DisplayMode、本地 TTS 和 English Tutor 默认工具均已落地。用户已明确选择跳过 Phase 2 release，不打 `v0.4.0` tag，不构建或发布 DMG，直接进入 Phase 3 规格收敛。

Roadmap 中的 Phase 3 主题是 Prompt IDE + 本地模型，包括 ToolEditor v2、Prompt Playground、样本管理、A/B 对比、版本历史、原生 Anthropic / Gemini / Ollama provider、Memory、Cost Panel 和 local-only 隐私闭环。该 roadmap 仍是 Directional outline，不能直接作为实现计划。本 spec 只冻结 Phase 3 的第一个可实施切片：ToolEditor v2 + Prompt Playground MVP。

## 2. Product Goal

MVP 的目标是让用户在 Settings 中编辑一个 Tool 的草稿，并立即在同一界面试跑，观察它在真实执行链下的行为：

- Prompt Tool：验证 system/user prompt、provider、model、temperature、变量替换和 DisplayMode 预览。
- Agent Tool：验证 system/initial user prompt、provider、ReAct 轮数、MCP allowlist、tool-call lifecycle、skill 渐进式加载和 structured 输出。
- 不保存样本、不保存运行结果、不做版本历史，避免首个切片同时引入持久化、隐私和迁移复杂度。

核心用户收益是“实验不污染正式工具配置”。用户可以在未保存草稿上运行 Playground；只有点击保存，正式 `config-v2.json` 中的 Tool 才会改变。

## 3. Non-Goals

本 MVP 明确不做以下能力，但全部作为技术债务记录在 §13：

- 原生 `AnthropicProvider` / `GeminiProvider` / `OllamaProvider`。
- Memory 存储、检索、prompt 注入和 MemoryPage。
- Cost Panel UI。
- A/B 双栏对比。
- 样本保存、expected output、回归结果历史。
- Tool version history、snapshot、diff、rollback。
- local-only privacy 闭环。
- `.pipeline` 执行器。
- Skill `scripts/` 执行或读取。
- InlineReplaceOverlay 确认 / 撤销浮条。
- Marketplace、Tool Pack、远端安装和自动更新。

## 4. Design Principles

1. **单一执行入口**：Playground 不创建第二套 prompt / agent runner，必须复用 `ExecutionEngine.execute(tool:seed:)`。
2. **草稿不污染正式配置**：Playground 运行使用临时 `Tool` snapshot，只有保存动作写 `config-v2.json`。
3. **副作用默认 dry-run**：Playground 不真实写文件、不替换选区、不写剪贴板、不发 TTS、不发通知、不执行 AppIntent。
4. **真实能力要可验证**：Prompt / Agent 仍可真实调用 LLM；Agent Tool 允许在权限闭环下真实调用 MCP tool，避免 Playground 变成只能看 prompt 的半功能。
5. **输出收敛在 Settings 右侧**：Playground 运行不打开 ResultPanel、不弹真实 BubblePanel、不改前台 App 选区；所有预览在右侧 Playground 面板内完成。
6. **不扩 schema**：MVP 不新增持久化数据模型，不提升 `Configuration.currentSchemaVersion`。
7. **安全可追踪**：真实 LLM / MCP 调用必须进入成本和审计记录，并标记为 Playground / dry-run，后续 Cost Panel 可过滤。

## 5. UX Shape

`ToolEditorView` 升级为左右布局：

- 左侧：kind-aware Tool 编辑器。
- 右侧：Prompt Playground。

左侧继续支持当前已有的 Prompt Tool 和 Agent Tool 编辑能力：

- 基础信息：名称、图标、描述、浮条显示、热键。
- Prompt Tool：system prompt、user prompt、provider、model override、temperature、DisplayMode、变量。
- Agent Tool：system prompt、initial user prompt、provider、model override、LLM 轮数、DisplayMode、Agent Skills、MCP allowlist、MCP 调用策略。

右侧 Playground 包含：

- 临时 selection 输入框。
- 可选基础上下文输入：front app 名称、window title、URL。MVP 可用默认空值或当前 App 快照；必须在 UI 上显示这些值会参与本次试跑。
- 运行控制：Run、Cancel、Clear。
- 状态标记：Unsaved draft、Playground run、side effects dry-run。
- 权限提示区：展示本次运行会请求或已请求的权限，尤其是 MCP。
- 输出区：streaming Markdown、tool-call lifecycle、structured 解析、DisplayMode 预览。

布局响应：

- 默认窗口宽度足够时使用左右双栏。
- 小宽度时降级为上下布局：编辑器在上，Playground 在下。
- 右侧输出区必须有固定最小高度和可滚动区域，避免 streaming / tool-call 行撑坏 Settings 页面。

## 6. Playground Run Policy

现有 `ExecutionSeed.isDryRun` 是布尔值，语义接近“预览模式，不执行需要真实落地的副作用”。但本 MVP 有更细的要求：

- LLM：允许真实调用。
- MCP：Agent Tool 允许在现有 PermissionBroker 下真实调用。
- Side effects：全部 dry-run。
- Output sink：全部写入 Playground preview sink，不写生产窗口 / 文件 / 前台 App。
- Audit / cost：必须记录，并标记为 Playground / dry-run。

因此 spec 要求新增一个明确边界，命名可在 plan 阶段确定，例如：

```swift
public struct ExecutionRunPolicy: Sendable, Equatable {
    public let source: ExecutionRunSource
    public let sideEffects: SideEffectRunMode
    public let mcpToolCalls: MCPToolCallRunMode
    public let outputRouting: OutputRoutingMode
}
```

建议语义：

- `source = .playground`
- `sideEffects = .dryRun`
- `mcpToolCalls = .realWithPermissionBroker`
- `outputRouting = .playgroundPreview`

实现可以选择最小可行形态，不一定第一步就公开上述完整 API；但不能用一个含混的 `isDryRun` 同时表达所有行为。若为了兼容保留 `ExecutionSeed.isDryRun`，它只能继续表示“副作用 dry-run / 终态 outcome 标记”，并由新的 run policy 补充 MCP 和 output routing 语义。

## 7. Data Flow

### 7.1 Draft Construction

Playground 运行时，SettingsUI 从当前左侧编辑状态构造临时 `Tool` snapshot：

1. 复制当前编辑中的 `Tool`。
2. 保留未保存的 prompt/provider/model/temperature/displayMode/MCP/skills/policy 修改。
3. 保留正式 Tool id，便于审计和成本关联；同时在 run metadata 中标记 source 为 Playground，避免把它误认为生产触发。
4. 调用 `Tool.validate()`。如果 displayMode 与 outputBinding.primary 不一致、Agent skills 超过 5 等，直接在 Playground 显示配置错误，不调用 LLM。

### 7.2 Seed Construction

Playground 使用临时输入构造 `ExecutionSeed`：

- `selection.text` 来自右侧输入框。
- `frontApp` 来自用户填写的基础上下文或 Settings app 默认上下文。
- `screenAnchor` 使用 Settings 窗口内安全锚点；Playground preview sink 不应依赖真实屏幕定位。
- `triggerSource` 应新增或复用一个能表示 Playground 的来源。若现有 `TriggerSource` 没有 `.playground`，MVP 应新增它，便于审计、日志和后续过滤。
- `isDryRun` 仍设为 true，用于 side effect dry-run 和 dry-run outcome，但 MCP 是否真实执行由 run policy 控制。

### 7.3 Execution

运行入口仍是 `ExecutionEngine.execute(tool:seed:)`，但 Playground 需要注入专用输出依赖：

- `PlaygroundOutputDispatcher` 或 `OutputDispatcher` 的 preview sink 组合。
- `PlaygroundWindowSink`：收集 `.window` streaming chunk 到右侧输出区。
- `PlaygroundStructuredSink`：finish 后解析 JSON 并渲染字段。
- `PlaygroundBubbleSink`：在右侧输出区展示 bubble preview，不创建真实 `BubblePanel`。
- `PlaygroundReplacementSink`：显示“would replace selected text”摘要和 final text，不调用 AX 或剪贴板。
- `PlaygroundFileSink`：显示“would append to path”摘要和 final text，不写文件。
- `.silent`：显示 dry-run 摘要和 final text，避免用户以为运行无结果。

生产 `AppContainer` 当前创建的 `OutputDispatcher` 已绑定 ResultPanel、BubblePanel 和真实 replacement client。Playground 不能直接复用这组 output dependencies，否则 Settings 试跑会打开生产窗口或替换前台选区。MVP 应通过独立 runner 或独立 dependency bundle 复用 ExecutionEngine 逻辑，但替换 output 和 side-effect 行为。

### 7.4 Events

Playground UI 消费 `ExecutionEvent`：

- `.started`：进入 running 状态。
- `.promptRendered`：展示脱敏 prompt preview。
- `.permissionWouldBeRequested`：展示“真实执行会请求权限”提示。
- `.toolCallProposed` / `.toolCallApproved` / `.toolCallResult` / `.toolCallDenied` / `.toolCallError`：渲染 tool-call lifecycle。
- `.llmChunk`：追加 streaming 文本。
- `.sideEffectSkippedDryRun`：展示 dry-run 副作用清单。
- `.finished`：显示 tokens、cost estimate、dry-run / playground 标记。
- `.failed`：显示中文用户错误和脱敏 developer context。
- `.notImplemented`：用于 pipeline 或未支持分支。

## 8. Permission And Safety

### 8.1 MCP Permission

Agent Playground 允许真实 MCP 调用，但必须复用现有 PermissionBroker：

- MCP allowlist 仍由 Agent Tool 配置决定。
- 未在 allowlist 的 tool call 必须被拒绝。
- `.mcp` 权限仍按现有规则 gate；不可因为 Playground 而自动放行。
- Permission UI 文案应标明“Playground run”，避免用户误以为这是生产划词触发。
- 可缓存权限仍遵守现有 cacheable 规则，例如 Brave Web Search 的特殊缓存边界；不要为 Playground 新增更宽松规则。

### 8.2 Side Effects

Playground MVP 中所有 side effects 都不真实执行：

- `appendToFile`：不写文件，只显示目标路径和 final text 摘要。
- `copyToClipboard`：不写剪贴板，只显示 would copy。
- `notify`：不发系统通知，只显示 would notify。
- `callMCP` side effect：不执行。注意这与 Agent Tool 的 MCP tool call 不同；Agent MCP 是推理过程的一部分，side effect MCP 是输出后的副作用。
- `tts`：不发声，只显示 would speak；structured JSON 中 `ttsText` 的提取逻辑可以预览。
- `runAppIntent`：不执行。
- `writeMemory`：仍 unsupported。

### 8.3 Logging / Redaction

Playground 不得把完整 selection、API Key、完整 provider response、完整 MCP result、完整 prompt payload 写入自由日志。可记录：

- invocationId
- tool id
- source = playground
- 输出长度
- 权限类型
- 脱敏后的错误类别

UI 内可以显示用户自己输入的 selection 和模型输出；审计 / 日志仍遵守现有脱敏规则。

## 9. Error Handling

Playground 错误应尽量就地显示在右侧面板，不打开 ResultPanel：

- 配置错误：缺 provider、缺 API key、`Tool.validate()` 失败、displayMode/outputBinding 不一致。
- 权限错误：未声明权限、用户拒绝 MCP 权限、MCP allowlist 拒绝。
- 上下文错误：required context 解析失败。
- Provider 错误：网络失败、认证失败、invalid response、SSE parse error。UI 展示 `SliceError.userMessage`，developer context 只展示脱敏摘要。
- Structured parse 错误：显示原始 final text 的安全预览和 parse 错误，不崩溃。
- Cancel：用户点击 Cancel 后应停止 stream，不写 failed audit；现有 ExecutionEngine cancellation 语义应保持。

错误状态需要可恢复：用户修改草稿后可以再次 Run，不要求关闭编辑器或重新打开 Settings。

## 10. UI State Model

建议新增独立 Playground 状态对象，避免继续膨胀 `ToolEditorView`：

- `ToolPlaygroundState`
  - draft input text
  - optional app/window/url context
  - run status: idle/running/cancelling/succeeded/failed
  - rendered prompt preview
  - streamed text
  - tool-call rows
  - skipped side effects
  - display preview state
  - last report summary
  - last error

- `ToolPlaygroundRunner`
  - 构造 draft Tool snapshot
  - 构造 ExecutionSeed
  - 启动 ExecutionEngine stream
  - 持有 cancellation task
  - 把 ExecutionEvent reduce 到 `ToolPlaygroundState`

`ToolEditorView` 目前直接绑定 `Configuration.tools[i]`，修改会即时反映到 ViewModel。MVP 需要明确保存语义：

- 若当前 Settings 仍是即时保存模型，ToolEditor v2 必须引入草稿层，否则“未保存草稿试跑”无法成立。
- 推荐把 Tool editor 改为 local draft editing：打开编辑器时复制 Tool，左侧改动先进入 draft；点击 Save 后写回 `Configuration.tools[i]` 并保存；点击 Revert/Cancel 恢复正式配置。
- 这属于 ToolEditor v2 的核心改造，不是可选 polish。否则 Playground 的“不污染正式配置”会被现有 binding 破坏。

## 11. Settings Integration

Tools 设置页当前以内联展开卡片嵌入 `ToolEditorView`。MVP 有两种实现选择，plan 阶段再定：

1. 保持 inline editor，但展开内容变为左右布局。
2. 展开行只显示摘要，点击 Edit 打开专门的 ToolEditor v2 页面 / sheet。

Spec 推荐先采用 inline 左右布局，因为它对导航结构改动小；但如果现有行内宽度无法容纳 Playground，plan 阶段可改为独立 editor scene。无论哪种 UI 容器，核心边界不变：

- 草稿层与正式配置分离。
- Playground 使用草稿 snapshot。
- Save 才写配置。
- Run 不写配置。

## 12. Testing Strategy

MVP 必须覆盖以下测试：

### SliceCore / Orchestration

- Playground run source / run policy 的 Codable 或 Equatable 测试（如果新增 SliceCore 类型）。
- `ExecutionEngine` 在 Playground policy 下：
  - 真实 prompt stream 可完成。
  - side effects 只 yield skipped/dry-run，不调用 executor。
  - final report 标记 playground/dry-run。
- Agent Tool 在 Playground policy 下：
  - allowlist 内 MCP tool call 仍走 PermissionBroker 并可真实执行。
  - allowlist 外 MCP tool call 被拒绝。
  - side effect `callMCP` 不执行。

### SettingsUI

- ToolEditor v2 使用 local draft，编辑 prompt/provider/model/temperature 不立即写回正式 Tool。
- Save 写回正式 Tool 并触发配置保存。
- Revert/Cancel 丢弃草稿。
- Prompt Tool Playground 可从临时 selection 运行并显示 streaming 输出。
- Agent Tool Playground 可显示 tool-call lifecycle。
- DisplayMode preview：
  - `.window` 显示 streaming text。
  - `.structured` 显示字段或 parse error。
  - `.bubble` 显示面板内气泡 preview。
  - `.file/.replace/.silent` 显示 dry-run 摘要。

### App / Integration

- App Debug build。
- Focused manual smoke：
  - Prompt Tool 草稿试跑不改 `config-v2.json`。
  - Agent Tool 草稿试跑可调用 Brave Search MCP（若本机配置可用）并在 UI 显示 lifecycle。
  - `.replace` / `.file` / `.tts` 在 Playground 不改前台 App、不写文件、不发声。

最终 gate 至少包括：

```bash
swift test --package-path SliceAIKit
swiftlint lint --strict
git diff --check
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

若本机无 MCP / API key / Accessibility 权限，manual smoke 需明确记录未验证项和风险，不能声称通过。

## 13. Technical Debt Register

| ID | 后续能力 | 为什么不进 MVP | 触发条件 / 还债时机 |
|---|---|---|---|
| P3-DEBT-01 | Playground sample persistence | 会引入隐私、存储、删除、迁移和 UI 管理成本 | ToolEditor v2 MVP 稳定后，做测试用例管理切片 |
| P3-DEBT-02 | Expected output 与回归结果历史 | 需要结果 diff、失败分类和长期存储 | sample persistence 完成后 |
| P3-DEBT-03 | A/B 双栏对比 | 需要并发双 invocation、成本展示和结果 diff | 单栏 Playground 事件模型稳定后 |
| P3-DEBT-04 | Tool version history / snapshot / rollback | 需要配置 snapshot schema、diff UI 和恢复策略 | Save/Revert 草稿模型稳定后 |
| P3-DEBT-05 | 原生 AnthropicProvider | 需 Messages API、Prompt Caching、Extended Thinking 和错误映射 | Playground 可稳定比较 provider 行为后 |
| P3-DEBT-06 | 原生 GeminiProvider | 需 Gemini API、Grounding、JSON Schema output 和错误映射 | Anthropic 或 provider abstraction review 后 |
| P3-DEBT-07 | OllamaProvider | 需本地可用性检测、model list、function calling 稳定性验证 | 回答 roadmap Q3 后 |
| P3-DEBT-08 | Provider cascade 产品化 | 需要可靠策略、fallback 可观测和 UI 配置 | 多 provider 原生支持后 |
| P3-DEBT-09 | Memory storage / retrieval | 需权限、jsonl/FTS、prompt 注入和审计边界 | 单独 Memory spec |
| P3-DEBT-10 | MemoryPage | 依赖 Memory 数据模型 | Memory storage 完成后 |
| P3-DEBT-11 | Cost Panel | 需要 playground/production/filter 语义和 provider 账单校验 | 审计 / 成本标记稳定后 |
| P3-DEBT-12 | `privacy: local-only` | 依赖本地 provider 可用性和 fail-closed 策略 | OllamaProvider 完成后 |
| P3-DEBT-13 | InlineReplaceOverlay | Phase 2 仅完成 AX 替换 + fallback | DisplayMode hardening 切片 |
| P3-DEBT-14 | Skill scripts strategy | 安全策略未冻结，不能在 Playground 里打开执行面 | 单独安全 spec |
| P3-DEBT-15 | ToolEditor 独立页面 / sheet | MVP 先尝试 inline 左右布局 | 如果 inline 宽度和状态复杂度失控 |
| P3-DEBT-16 | Playground result export | 依赖结果历史或 explicit export UX | sample / history 能力完成后 |

## 14. Risks And Mitigations

| 风险 | 影响 | 缓解 |
|---|---|---|
| `isDryRun` 语义不足以表达真实 MCP + 副作用 dry-run | 容易误阻断 MCP 或误执行副作用 | 新增 run policy 或等价边界，禁止用布尔值硬凑全部语义 |
| 当前 ToolEditor 直接绑定配置，无法表达未保存草稿 | Run 会污染正式 config | ToolEditor v2 引入 local draft + Save/Revert |
| Playground 复用生产 output dispatcher 可能弹真实窗口或替换选区 | Settings 试跑产生副作用 | 使用 Playground preview sinks，不复用生产 ResultPanel/Bubble/Replacement sinks |
| Agent MCP 真调用可能产生外部状态变化 | 高风险 MCP tool 可能写数据库/文件 | 继续走 allowlist + PermissionBroker；不新增自动放行；UI 标明 Playground run |
| 不新增持久化导致用户不能保存样本 | 功能不完整 | 记录为技术债务，先验证运行闭环 |
| 右侧 UI 承载过多信息 | Settings 页面拥挤 | 固定输出区域、折叠 tool-call rows、小屏上下布局 |
| 审计/成本把 Playground 和生产混在一起 | 后续 Cost Panel 统计误导 | report flags/source 必须能区分 playground |

## 15. Open Questions For Implementation Plan

这些问题不阻塞 spec，但必须在 implementation plan 中落成具体任务：

1. `ExecutionRunPolicy` 应放在 `SliceCore` 还是 `Orchestration`？若要进入 audit/cost/report，倾向放在 `SliceCore`。
2. `InvocationReport.flags` 是否需要新增 `.playground`，或新增更结构化的 source 字段？
3. `TriggerSource` 是否新增 `.playground`？若新增，需同步 Codable 和测试。
4. Playground 是否创建第二个 `ExecutionEngine` 实例，还是复用生产 engine 但注入临时 output dispatcher？由于 `ExecutionEngine` 依赖在 init 时固定，倾向创建 Playground 专用 engine dependency bundle。
5. AgentExecutor 当前 `gateMCP(..., isDryRun: false)` 写死非 dry-run。MVP 需要明确它如何接收 run policy，避免 prompt 路径和 agent MCP 路径语义分裂。
6. CostAccounting 是否记录 dry-run cost？本 spec 要求记录真实 LLM/MCP 成本；若字段不足，需要新增 source/flags。
7. SettingsUI 是否继续 inline editor，还是改成独立 Tool editor scene？实现前需用窗口尺寸确认。

## 16. Definition Of Done

MVP 完成需要满足：

- 用户可在 ToolEditor v2 左侧编辑 Prompt Tool / Agent Tool 草稿，未保存改动不会写入正式配置。
- 用户可在右侧 Playground 输入临时 selection，运行当前草稿。
- Prompt Tool Playground 可真实调用 LLM 并显示 streaming 输出。
- Agent Tool Playground 可显示 tool-call lifecycle，并允许 allowlist 内 MCP 在 PermissionBroker 下真实执行。
- `.window/.structured/.bubble/.file/.replace/.silent` 都有右侧面板内预览，不触发生产窗口或真实副作用。
- Playground side effects 全部 dry-run，并在 UI 中列出 skipped side effects。
- 审计和成本记录能区分 Playground / dry-run 与生产触发。
- 保存动作才写 `config-v2.json`；Run 不写配置。
- 不新增 sample/version/history 持久化 schema。
- 自动化测试和 App Debug build 通过；若真实 MCP/App smoke 条件缺失，文档明确记录。
