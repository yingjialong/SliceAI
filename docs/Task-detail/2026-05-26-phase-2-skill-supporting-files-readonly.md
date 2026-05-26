# 2026-05-26 · Phase 2 Skill Supporting Files Read-Only Loading

## 背景

Phase 2 Skill Registry MVP 已支持本地 skill roots、`SKILL.md` parser/scanner、Settings Skills 页面、Agent Tool 最多 5 个 skill 绑定，以及 `sliceai_load_skill` 渐进式加载。Task 60/61 已分别完成本地 Claude / Codex 风格 skill E2E 与公开仓库 smoke。

当前缺口是 supporting files：真实 Codex / Anthropic 风格 skill 常把长参考文档、模板和示例放在 `references/`、`assets/` 等目录中。SliceAI 目前只加载 `SKILL.md` body，不读取这些辅助文件，所以很多真实 skill 的主说明可见，但关键参考材料不可用。

OpenAI Codex Skills 文档说明 skill 是包含 `SKILL.md` 的目录，可选 `scripts/`、`references/`、`assets/`、`agents/openai.yaml`，并采用渐进式披露。SliceAI 本切片只做只读 supporting files，不执行 scripts。

## 设计边界

- 支持读取已绑定、已启用 skill 内的 `references/` 文件。
- 支持读取文本型 `assets/` 文件，例如 Markdown / TXT / JSON / YAML / CSV / XML / HTML / CSS / JS / TS / Swift / Python / Shell 等。
- 不执行 `scripts/`，也不把 `scripts/` 作为可读 supporting file 暴露给模型。
- 不读取二进制 asset；二进制文件可以存在于 skill 目录，但不会进入模型 payload。
- 读取必须基于相对路径，拒绝绝对路径、`..`、空路径和符号链接越界。
- 单个 supporting file 有大小上限；超限、非 UTF-8、未索引或越界路径都返回脱敏错误。
- Agent 运行时先通过 `sliceai_load_skill` 加载 `SKILL.md`，再通过新的只读 pseudo-tool 读取列出的 supporting file。

## ToDoList

- [x] 创建任务文档、spec 与 implementation plan。
- [x] 写 LocalSkillRegistry supporting files 索引与读取失败测试。
- [x] 写 AgentExecutor supporting file pseudo-tool 失败测试。
- [x] 实现 registry 资源索引和只读加载 API。
- [x] 实现 AgentExecutor provider-visible pseudo-tool 和 prompt metadata。
- [x] 更新 README / AGENTS / CLAUDE / master todolist 等状态文档。
- [x] 运行 focused tests、full SwiftPM tests、SwiftLint strict 和 `git diff --check`。

## 预期验收

- `LocalSkillRegistry.snapshot()` 为 enabled skill 填充可读 supporting files 的 `resources`。
- `LocalSkillRegistry.loadSkillResource(id:relativePath:)` 只读取已索引资源。
- Agent 初始 prompt 展示可读 supporting file 相对路径。
- Provider 可调用 `sliceai_load_skill_resource` 读取资源内容；未先加载 skill、未绑定 skill、脚本路径、越界路径均失败。
- 默认公开仓库 smoke 仍只做扫描/解析/加载 `SKILL.md`，不执行任何仓库脚本。

## 变动文件清单

- `SliceAIKit/Sources/Capabilities/Skills/SkillRegistryProtocol.swift`：新增 `SkillResourcePayload` 和 `loadSkillResource(id:relativePath:)` 协议方法。
- `SliceAIKit/Sources/Capabilities/Skills/LocalSkillRegistry.swift`：索引 `references/` 与文本型 `assets/`，并实现只读资源加载、安全路径校验、64 KiB 上限和 UTF-8 校验。
- `SliceAIKit/Sources/Capabilities/Skills/MockSkillRegistry.swift`：支持测试注入 resource payload。
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCatalog.swift`：新增 provider-visible `sliceai_load_skill_resource` schema 和 synthetic ref。
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`：接入 resource pseudo-tool 分支。
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+SkillResources.swift`：承载 supporting file 请求校验、加载和 tool message 构造。
- `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`：在 8,000 字符预算内列出可读 resource path，并提示只读取已列出的 `references/` / `assets/`。
- `SliceAIKit/Tests/CapabilitiesTests/LocalSkillRegistryTests.swift`：覆盖资源索引、成功读取、脚本拒绝和 traversal 拒绝。
- `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`：覆盖 `sliceai_load_skill_resource` 成功路径和未先加载 skill 的失败路径。
- `SliceAIKit/Tests/OrchestrationTests/AgentExecutorSkillE2ETests.swift`：真实临时 skill root E2E 证明 `references/style.md` 可按需进入模型 tool message，`scripts/check.sh` 仍不进入 payload。
- `SliceAIKit/Tests/SettingsUITests/SkillsViewModelTests.swift`：补齐测试 registry 协议实现。
- `README.md`、`AGENTS.md`、`CLAUDE.md`、`docs/Module/Orchestration.md`、`docs/Module/SliceCore.md`、`docs/v2-refactor-master-todolist.md`、`docs/Task_history.md`、本任务文档和 implementation plan：同步项目状态与验证结果。

## 修改逻辑

1. Registry 层仍以 `Skill.resources` 作为轻量索引，snapshot 只暴露相对路径和 MIME，不主动读取文件正文。
2. `loadSkillResource` 只接受已启用、已绑定 skill 的已索引资源；路径必须是 POSIX 相对路径，禁止绝对路径、空片段、`.`、`..`、反斜杠和 NUL。
3. 文件读取前再次解析 symlink 并确认仍在 skill 根目录下；文件大小超过 64 KiB 或不是 UTF-8 时失败，错误信息保持脱敏。
4. AgentExecutor 只在 skill 已绑定且已通过 `sliceai_load_skill` 加载后，允许 `sliceai_load_skill_resource` 返回正文；该 pseudo-tool 不经过 MCP client，也不触发 MCP allowlist 或权限 broker。
5. Prompt metadata 只列出可读 resource path；`scripts/`、`agents/`、二进制 assets 和未知扩展不会被列出，也不会被执行。

## 测试结果

- `swift test --package-path SliceAIKit --filter CapabilitiesTests.LocalSkillRegistryTests`：11 tests，0 failures。
- `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests`：35 tests，0 failures。
- `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorSkillE2ETests`：1 test，0 failures。
- `swift test --package-path SliceAIKit --filter CapabilitiesTests.SkillRegistryProtocolTests`：4 tests，0 failures。
- `bash scripts/phase2-public-skill-smoke.sh`：passed，3 repositories / 9 public skills。
- `swift test --package-path SliceAIKit`：803 tests，1 skipped，0 failures。
- `swiftlint lint --strict`：0 violations。
- `git diff --check`：passed。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：`BUILD SUCCEEDED`。

## 结论

Task 62 已完成。SliceAI 现在具备 Phase 2 skill supporting files 的最小安全闭环：`SKILL.md` 继续渐进式加载，长参考材料可通过只读 pseudo-tool 按需加载，脚本执行和二进制 asset 处理仍明确不在本切片范围内。
