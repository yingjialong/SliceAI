# 2026-05-29 · Phase 3 SwiftLint Gate Fix

## 背景

Phase 3 ToolEditor v2 + Prompt Playground MVP 的实现、两轮 review-fix 和 plan compliance audit 都在一台**未安装 SwiftLint** 的机器上完成，因此 `swiftlint lint --strict` 这一关 final gate 一直被记为“环境缺失，未运行”（见 `2026-05-28-phase-3-tool-editor-playground-mvp-plan.md` Task 8 与 `2026-05-29-phase-3-plan-compliance-audit.md`）。

本次在一台**已安装 SwiftLint（`/opt/homebrew/bin/swiftlint` 0.63.2）**的机器上接续，第一时间补跑这一关。CI（`.github/workflows/ci.yml`）每次 push/PR 都强制跑 `swiftlint lint --strict`，因此必须先让它通过，分支才能集成。

## 现有问题

`swiftlint lint --strict` 报 **15 个 serious 违规，全部落在 Phase 3 切片改动过的文件上**（Phase 2 后的 `main` 是 lint-clean 的，说明这些是本切片在无 SwiftLint 的机器上新引入的回归）：

| 文件 | 违规 |
| --- | --- |
| `AppContainer.swift` | file_length 529>500、function_body @bootstrap 41>40、@makeV2RuntimeDependencies 42>40 |
| `ExecutionEngine+Steps.swift` | file_length 540>500 |
| `AgentExecutor.swift` | function_parameter_count @runSafely 6>5、@runInternal 6>5 |
| `AgentExecutor+ToolCalls.swift` | file_length 525>500、function_body @processOneToolCall 42>40、function_parameter_count @processToolCalls 6>5、@processOneToolCall 6>5 |
| `ToolPlaygroundRunner.swift` | function_body @run 50>40 |
| `ToolPlaygroundView.swift` | function_body @startRun 43>40 |
| `ToolPlaygroundState.swift` | cyclomatic_complexity @reduce 13>12 |
| `ToolsSettingsPage.swift` | type_body_length 256>250 |
| `ToolsSettingsPage+Actions.swift` | function_body @saveEditingSession 44>40 |

## 实施方案（全部保行为，仅结构 / 可见性调整）

1. **函数体超长 → 抽取子函数**
   - `ToolPlaygroundRunner.run` → 抽 `makeSeed(for:)`。
   - `ToolPlaygroundView.startRun` → 抽 `makeRunRequest()` + `launchRun(runner:request:runID:)`。
   - `ToolsSettingsPage+Actions.saveEditingSession` → 抽 `commitDraftToConfiguration(_:)` + `finishSaveAfterCommit(previousHotkeys:)`。
   - `AppContainer.bootstrap` → 抽 `assemble(ui:runtime:configStore:skillRegistry:keychain:)`（留在主文件，因需访问 private `init`）。
   - `AppContainer.makeV2RuntimeDependencies` → 抽 `makeTelemetry(appSupport:)`。
2. **圈复杂度超标 → 拆 switch**：`ToolPlaygroundState.reduce` 把 5 个 tool-call 生命周期 case 拆到 `reduceToolCallEvent(_:)`（13→~9）。
3. **参数过多(6>5) → 收进结构体**
   - `AgentExecutor.runSafely/runInternal` 收进新 `private struct AgentRunInput`（`run` 公开签名不变，内部构造后转发；`runInternal` 内联引用 `input.X`，不新增行以免触发 function_body）。
   - `processToolCalls/processOneToolCall` 改用已有的 `AgentToolTurnProcessingContext`（命名为 `turnContext` 以避免与局部 `AgentToolCallContext` 冲突）。
4. **文件超长(>500) → 拆分（沿用仓库既有 `+扩展文件` 模式）**
   - `AgentExecutor+ToolCalls.swift`(525) → 新建 `AgentExecutor+Skills.swift`，移入 `handleLoadSkill` + `skillToolMessage`，并新增 `handleBuiltInToolCall(_:catalog:toolCallState:)` 派发器（同时把 `processOneToolCall` 的内置 pseudo-tool 分派收敛进去，顺带降其函数体）。
   - `ExecutionEngine+Steps.swift`(540) → 新建 `ExecutionEngine+Terminal.swift`，移入终态 helpers（`makeReport` / `finishFailure` / `finishSuccess` / `finishNotImplementedKind`）。
   - `AppContainer.swift`(529) → 新建 `AppContainer+Factories.swift`，移入 `AppMCPRuntimeDependencies` 及全部工厂方法。
5. **类体超长(262>250)**：把 4 个工厂方法（`makeSkillRegistry` / `makeSideEffectExecutor` / `makeExecutionEngine` / `makePlaygroundRunner`）一并移到工厂文件后，`AppContainer` 类体只剩属性 + `init` + `bootstrap` + `assemble`。
6. **Xcode 工程登记（关键）**：新建的 App-target 文件 `AppContainer+Factories.swift` 必须在 `SliceAI.xcodeproj/project.pbxproj` 显式登记（SwiftPM 自动发现源文件，但 Xcode 工程不会）。按既有 `AppDelegate+Hotkeys.swift` 模式补了 4 处条目（PBXBuildFile / PBXFileReference / PBXGroup children / PBXSourcesBuildPhase），生成两个未冲突的 UUID（`533BFAC1…` / `533BFAC2…`）。SwiftPM 内的两个新文件（`AgentExecutor+Skills.swift`、`ExecutionEngine+Terminal.swift`）无需登记。

## 可见性变更说明

为支持跨文件拆分，少量 App-target 内部声明从 `private` 放宽到 `internal`：`ExecutionEngineDependencies`、`AppMCPRuntimeDependencies` 以及移出的工厂方法。仅在 App target 内可见，不构成任何对外 API 表面。

## 变动文件清单

修改（10）：
- `SliceAI.xcodeproj/project.pbxproj`
- `SliceAIApp/AppContainer.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`
- `SliceAIKit/Sources/Orchestration/Playground/ToolPlaygroundRunner.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Actions.swift`
- `SliceAIKit/Sources/SettingsUI/ToolPlaygroundState.swift`
- `SliceAIKit/Sources/SettingsUI/ToolPlaygroundView.swift`

新增（3）：
- `SliceAIApp/AppContainer+Factories.swift`
- `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Terminal.swift`
- `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+Skills.swift`

文档：
- `docs/Task-detail/2026-05-29-phase-3-swiftlint-gate-fix.md`（本文件）
- `docs/Task_history.md`（新增 Task 77）

## 验证

- `swiftlint lint --strict`：exit 0，**0 violations**（修复前 15 serious）。
- `swift build --package-path SliceAIKit`：Build complete。
- `swift test --package-path SliceAIKit`：**887 tests / 1 skipped / 0 failures**（与基线一致，行为未变）。
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：**BUILD SUCCEEDED**。
- `git diff --check`：无输出。
- `plutil -lint SliceAI.xcodeproj/project.pbxproj`：OK。

## 下一步

- 真实 App smoke（handoff 第 3 步）：构建并启动 Debug app，由用户在 GUI 中验证 Settings Tools 草稿编辑不污染配置、Playground 试跑、Save/Revert/Cancel、side effects dry-run；结果回填本文件或新建 smoke task detail。
- smoke 通过后再与用户确认集成路径（开 PR / 合 main / 保持分支继续下个切片）。
