# Phase 2 Completion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Complete Phase 2 by implementing non-window DisplayModes, real side effects, TTS, and the first-party English Tutor tool.

**Architecture:** Extend output dispatch from a chunk-only API to a lifecycle API that preserves final text, then add small sink/executor adapters behind existing protocols. Keep `SliceCore` as pure data, put system integrations in `Capabilities`/`Windowing`, and keep `ExecutionEngine` as the single production execution path.

**Tech Stack:** Swift 6.0, SwiftPM, XCTest, AppKit, SwiftUI, AVFoundation, existing OpenAI-compatible provider infrastructure.

---

## File Structure

- Modify `SliceAIKit/Sources/Orchestration/Output/OutputDispatcherProtocol.swift`: add lifecycle context and new begin/finish/fail methods.
- Modify `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift`: route lifecycle events to sink protocols and remove non-window fallback behavior.
- Add `SliceAIKit/Sources/Orchestration/Output/FinalTextBuffer.swift`: accumulate final output per invocation for final-only modes.
- Add `SliceAIKit/Sources/Orchestration/Output/SideEffectExecutorProtocol.swift`: declare side effect execution boundary.
- Add `SliceAIKit/Sources/Orchestration/Output/SideEffectExecutor.swift`: implement pure orchestration of approved side effects.
- Modify `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`: use lifecycle output and call side effect executor.
- Modify `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`: inject side effect executor.
- Modify `SliceAIKit/Tests/OrchestrationTests/Helpers/MockOutputDispatcher.swift`: support lifecycle assertions.
- Add `SliceAIKit/Tests/OrchestrationTests/Output/OutputLifecycleTests.swift`: lifecycle and non-window routing tests.
- Add `SliceAIKit/Tests/OrchestrationTests/Output/SideEffectExecutorTests.swift`: side effect execution tests.
- Add `SliceAIKit/Sources/Capabilities/TTS/TTSCapability.swift`: local TTS protocol and AVSpeech implementation.
- Add `SliceAIKit/Sources/Capabilities/TTS/MockTTSCapability.swift`: tests/previews.
- Add `SliceAIKit/Sources/Windowing/BubblePanel.swift`: small result bubble.
- Add `SliceAIKit/Sources/Windowing/InlineReplaceOverlay.swift`: replacement result/fallback UI boundary.
- Add `SliceAIKit/Sources/Windowing/StructuredResultView.swift`: structured JSON renderer.
- Add `SliceAIKit/Tests/WindowingTests/StructuredResultViewStateTests.swift`: pure view model/parser tests.
- Modify `SliceAIApp/AppDelegate+Execution.swift`: open ResultPanel only for `.window` and `.structured`; provide anchors for output contexts.
- Modify `SliceAIApp/AppContainer.swift`: wire new sinks, side effect executor and TTS.
- Modify `SliceAIKit/Sources/SliceCore/Configuration.swift`: bump schema to 4 and add TTS / first-party migration metadata if needed.
- Modify `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`: add `english-tutor` tool.
- Add `SliceAIKit/Sources/SliceCore/EnglishTutorToolFactory.swift`: keep default tool construction focused.
- Add bundled skill files under `SliceAIKit/Sources/Capabilities/Skills/Bundled/english-tutor/SKILL.md`.
- Update `config.schema.json`, README, AGENTS, module docs, master todolist and task detail.

## Task 1: Output Lifecycle Foundation

- [x] **Step 1: Write failing lifecycle protocol tests**

Add tests to `SliceAIKit/Tests/OrchestrationTests/Output/OutputLifecycleTests.swift`:

```swift
func test_promptStream_callsBeginChunkAndFinishWithFinalText() async throws {
    let output = MockOutputDispatcher()
    let bundle = try makeEngine(output: output, chunks: [
        ChatChunk(delta: "Hello", finishReason: nil),
        ChatChunk(delta: " world", finishReason: nil)
    ])
    let tool = makeStubTool(displayMode: .silent)
    _ = await collectEvents(from: bundle.engine.execute(tool: tool, seed: makeStubSeed()))
    let calls = await output.lifecycleCalls
    XCTAssertEqual(calls.map(\\.kind), [.begin, .chunk, .chunk, .finish])
    XCTAssertEqual(calls.last?.finalText, "Hello world")
}
```

- [x] **Step 2: Run test to verify it fails**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.OutputLifecycleTests`

Expected: compile failure because `OutputInvocationContext`, lifecycle methods and `lifecycleCalls` do not exist.

- [x] **Step 3: Add lifecycle API**

Implement in `OutputDispatcherProtocol.swift`:

```swift
public struct OutputInvocationContext: Sendable, Equatable {
    public let invocationId: UUID
    public let toolId: String
    public let toolName: String
    public let mode: DisplayMode
    public let screenAnchor: CGPoint
}
```

Then extend `OutputDispatcherProtocol` with:

```swift
func begin(context: OutputInvocationContext) async throws
func handle(chunk: String, context: OutputInvocationContext) async throws -> DispatchOutcome
func finish(finalText: String, context: OutputInvocationContext) async throws
func fail(error: SliceError, context: OutputInvocationContext) async
```

Keep the old chunk method only as a temporary default wrapper if needed to reduce one-step churn, then remove direct callers inside this task.

- [x] **Step 4: Update ExecutionEngine stream consumption**

In `runPromptStream` and `forwardLLMChunk`, create the context from `tool`, `seed.screenAnchor`, and `context.invocationId`. Accumulate `finalText` while streaming chunks. Call:

```swift
try await output.begin(context: outputContext)
_ = try await output.handle(chunk: chunk, context: outputContext)
try await output.finish(finalText: finalText, context: outputContext)
```

On failure paths that occur after begin, call `await output.fail(error: error, context: outputContext)`.

- [x] **Step 5: Run focused tests**

Run: `swift test --package-path SliceAIKit --filter 'OrchestrationTests.OutputLifecycleTests|OrchestrationTests.ExecutionEngineTests|OrchestrationTests.AgentExecutorTests'`

Expected: pass.

- [x] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Orchestration SliceAIKit/Tests/OrchestrationTests
git commit -m "feat: add output lifecycle foundation"
```

## Task 2: SideEffect Executor

- [ ] **Step 1: Write failing executor tests**

Add `SideEffectExecutorTests` covering:

```swift
func test_execute_copyToClipboard_writesFinalText() async throws
func test_execute_appendToFile_appendsHeaderAndFinalText() async throws
func test_execute_notify_doesNotExposeRawSelectionInLogs() async throws
func test_execute_callMCP_usesConfiguredRefAndParams() async throws
func test_execute_tts_speaksFinalText() async throws
func test_execute_writeMemory_returnsUnsupported() async throws
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.SideEffectExecutorTests`

Expected: compile failure because `SideEffectExecutorProtocol` does not exist.

- [ ] **Step 3: Add side effect execution boundary**

Create `SideEffectExecutorProtocol.swift`:

```swift
public enum SideEffectExecutionOutcome: Sendable, Equatable {
    case executed
    case unsupported(reason: String)
    case failed(reason: String)
}

public protocol SideEffectExecutorProtocol: Sendable {
    func execute(
        _ sideEffect: SideEffect,
        finalText: String,
        invocationId: UUID
    ) async -> SideEffectExecutionOutcome
}
```

- [ ] **Step 4: Implement concrete executor**

Implement `SideEffectExecutor` with injected adapters:

- clipboard writer
- file appender with `PathSandbox`
- notification presenter
- MCP client
- TTS capability

Do not implement memory writes. Return `.unsupported(reason: "writeMemory is planned for Phase 3")`.

- [ ] **Step 5: Wire ExecutionEngine**

Add a `sideEffectExecutor` dependency to `ExecutionEngine`. In `runSideEffects`, after gate approval and non-dry-run check, call executor with final text. Preserve current `.sideEffectTriggered` and audit behavior only after `.executed`.

- [ ] **Step 6: Run focused tests**

Run: `swift test --package-path SliceAIKit --filter 'OrchestrationTests.SideEffectExecutorTests|OrchestrationTests.ExecutionEngineTests'`

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/Orchestration SliceAIKit/Tests/OrchestrationTests
git commit -m "feat: execute output side effects"
```

## Task 3: Silent And File DisplayModes

- [ ] **Step 1: Write failing DisplayMode tests**

Replace current fallback tests with assertions:

```swift
func test_silent_doesNotWriteWindowSink() async throws
func test_file_requiresAppendToFileDestination() async throws
func test_file_writesFinalTextAtFinish() async throws
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.OutputDispatcherFallbackTests`

Expected: fail because current implementation writes all non-window chunks to window sink.

- [ ] **Step 3: Implement `.silent`**

Route `.silent` to a no-op sink. It should accept begin/chunk/finish and never call the window sink.

- [ ] **Step 4: Implement `.file`**

At `finish`, find the destination from `outputBinding.sideEffects.first { case .appendToFile }`. If no destination exists, return a configuration failure. Reuse the same file append adapter as `SideEffectExecutor` so permission behavior and path sandboxing stay consistent.

- [ ] **Step 5: Run focused tests**

Run: `swift test --package-path SliceAIKit --filter 'OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.SideEffectExecutorTests'`

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Orchestration SliceAIKit/Tests/OrchestrationTests
git commit -m "feat: add silent and file display modes"
```

## Task 4: Replace DisplayMode

- [ ] **Step 1: Write failing replace tests**

Add tests for the replacement adapter:

```swift
func test_replace_usesTextReplacementWhenAvailable() async throws
func test_replace_fallsBackToClipboardAndNotificationWhenAXFails() async throws
func test_replace_waitsUntilFinishBeforeWriting() async throws
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path SliceAIKit --filter OrchestrationTests.ReplaceDisplayModeTests`

Expected: compile failure because replacement adapter does not exist.

- [ ] **Step 3: Add replacement protocol**

Create a small protocol in `Windowing` or `Capabilities`:

```swift
public protocol TextReplacementClient: Sendable {
    func replaceSelection(with text: String) async -> TextReplacementResult
}

public enum TextReplacementResult: Sendable, Equatable {
    case replaced
    case fallbackCopied(reason: String)
    case failed(reason: String)
}
```

- [ ] **Step 4: Implement AppKit adapter**

Use AX replacement where available. If it fails, write final text to pasteboard and show a local notification telling the user to paste manually. Do not stream partial chunks into the active app.

- [ ] **Step 5: Wire `.replace`**

`OutputDispatcher.finish(finalText:)` calls the replacement client only for `.replace`.

- [ ] **Step 6: Run focused tests**

Run: `swift test --package-path SliceAIKit --filter 'OrchestrationTests.ReplaceDisplayModeTests|OrchestrationTests.OutputLifecycleTests'`

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources SliceAIKit/Tests
git commit -m "feat: add replace display mode"
```

## Task 5: Bubble And Structured DisplayModes

- [ ] **Step 1: Write failing Windowing state tests**

Add `StructuredResultViewStateTests`:

```swift
func test_parseStructuredObject_supportsStringNumberBoolArrayAndObject() throws
func test_parseStructuredObject_returnsFailureForInvalidJSON() throws
func test_bubbleState_autoDismissesAfterFinishDelay() async throws
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path SliceAIKit --filter WindowingTests.StructuredResultViewStateTests`

Expected: compile failure because parser/view state types do not exist.

- [ ] **Step 3: Implement structured parser/state**

Add pure state types first:

```swift
public enum StructuredValue: Sendable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case array([StructuredValue])
    case object([(String, StructuredValue)])
    case null
}
```

Parse final text as JSON. If the top-level value is not an object, show a controlled error state.

- [ ] **Step 4: Implement SwiftUI views**

Add `StructuredResultView` and `BubblePanel` using existing DesignSystem tokens. Keep layout compact and non-marketing.

- [ ] **Step 5: Wire AppDelegate UI behavior**

Only open ResultPanel before execution for `.window` and `.structured`. `.bubble` opens the bubble on finish. `.silent`, `.file`, and `.replace` do not open ResultPanel up front.

- [ ] **Step 6: Run focused tests**

Run: `swift test --package-path SliceAIKit --filter 'WindowingTests|OrchestrationTests.OutputLifecycleTests'`

Expected: pass.

- [ ] **Step 7: Commit**

```bash
git add SliceAIApp SliceAIKit/Sources/Windowing SliceAIKit/Sources/Orchestration SliceAIKit/Tests
git commit -m "feat: add bubble and structured display modes"
```

## Task 6: TTS Capability

- [ ] **Step 1: Write failing TTS tests**

Add tests:

```swift
func test_ttsSideEffect_requiresSystemAudioPermission() throws
func test_localTTS_speaksProvidedFinalText() async throws
func test_ttsSideEffect_dryRunDoesNotSpeak() async throws
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path SliceAIKit --filter 'CapabilitiesTests.TTSCapabilityTests|OrchestrationTests.SideEffectExecutorTests'`

Expected: compile failure because TTS capability does not exist.

- [ ] **Step 3: Add TTS protocol and AVSpeech adapter**

Create `TTSCapability.swift`:

```swift
public protocol TTSCapability: Sendable {
    func speak(_ text: String, voice: String?) async throws
}
```

Implement `AVSpeechTTSCapability` in a macOS-safe target using `AVFoundation`. Keep text logging disabled.

- [ ] **Step 4: Wire side effect executor**

`SideEffect.tts(voice:)` calls injected TTS with final text. If final text is empty, return `.failed(reason: "No text to speak")`.

- [ ] **Step 5: Run focused tests**

Run: `swift test --package-path SliceAIKit --filter 'CapabilitiesTests.TTSCapabilityTests|OrchestrationTests.SideEffectExecutorTests'`

Expected: pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Capabilities SliceAIKit/Sources/Orchestration SliceAIKit/Tests
git commit -m "feat: add local tts side effect"
```

## Task 7: English Tutor Default Tool

- [ ] **Step 1: Write failing configuration tests**

Add tests:

```swift
func test_defaultConfiguration_containsEnglishTutor() throws
func test_schemaV4Migration_appendsEnglishTutorOnce() throws
func test_englishTutor_declaresStructuredAndTTSRequirements() throws
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `swift test --package-path SliceAIKit --filter SliceCoreTests.ConfigurationTests`

Expected: fail because schema version remains 3 and `english-tutor` does not exist.

- [ ] **Step 3: Add bundled skill**

Create bundled first-party skill:

```markdown
---
name: english-tutor
description: Diagnose English grammar, rewrite naturally, and provide short practice prompts.
---

Return concise tutoring feedback. Prefer concrete corrections over broad lectures.
```

- [ ] **Step 4: Add tool factory**

`EnglishTutorToolFactory.make()` returns an Agent Tool with:

- `displayMode: .structured`
- `outputBinding.sideEffects: [.tts(voice: nil)]`
- provider selection `.capability(requires: [.toolCalling], prefer: [])`
- skill binding `english-tutor`
- permissions including `.systemAudio`

- [ ] **Step 5: Add schema v4 migration**

Bump `Configuration.currentSchemaVersion` to 4. When loading v3 config, append `english-tutor` only if no tool with that id exists. Do not re-add it after a v4 user deletes it.

- [ ] **Step 6: Update config schema**

Update `config.schema.json` to schemaVersion 4 and include TTS / English Tutor relevant fields.

- [ ] **Step 7: Run focused tests**

Run: `swift test --package-path SliceAIKit --filter 'SliceCoreTests.ConfigurationTests|SliceCoreTests.ConfigurationStoreTests|SettingsUITests'`

Expected: pass.

- [ ] **Step 8: Commit**

```bash
git add SliceAIKit/Sources/SliceCore SliceAIKit/Sources/Capabilities SliceAIKit/Tests config.schema.json
git commit -m "feat: add english tutor tool"
```

## Task 8: App Wiring And Manual Smoke

- [ ] **Step 1: Build App wiring**

Wire:

- `OutputDispatcher` sinks.
- `SideEffectExecutor`.
- `AVSpeechTTSCapability`.
- Bubble/replace/structured UI adapters.
- ResultPanel opening policy by display mode.

- [ ] **Step 2: Run App build**

Run: `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Manual smoke matrix**

Run real app checks:

- `.window`: existing Translate still streams to ResultPanel.
- `.silent`: no window opens; configured side effect executes.
- `.file`: final text appends to allowed temp file.
- `.replace`: TextEdit or Notes selection is replaced after final output.
- `.bubble`: final text appears in auto-dismiss bubble.
- `.structured`: English Tutor JSON renders as structured UI.
- TTS: English Tutor speaks `ttsText` locally.

- [ ] **Step 4: Record findings**

Update `docs/Task-detail/2026-05-26-phase-2-completion.md` with exact commands, manual app versions, and any unsupported app fallback behavior.

- [ ] **Step 5: Commit**

```bash
git add SliceAIApp SliceAIKit docs
git commit -m "chore: wire phase 2 app smoke"
```

## Task 9: Final Documentation And Gate

- [ ] **Step 1: Update docs**

Update:

- `README.md`
- `AGENTS.md`
- `CLAUDE.md`
- `docs/v2-refactor-master-todolist.md`
- `docs/Module/SliceCore.md`
- `docs/Module/Orchestration.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-26-phase-2-completion.md`

- [ ] **Step 2: Run final automated gate**

Run:

```bash
swift test --package-path SliceAIKit
swiftlint lint --strict
git diff --check
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected:

- SwiftPM full suite passes.
- SwiftLint has 0 violations.
- Whitespace check passes.
- App Debug build succeeds.

- [ ] **Step 3: Optional public skill smoke**

Run:

```bash
bash scripts/phase2-public-skill-smoke.sh
```

Expected: 3 repositories / 9 public skills still pass scanning, parsing, enabling, `SKILL.md`, and resource loading invariants.

- [ ] **Step 4: Final self-review**

Check:

- No non-window mode falls back to window.
- No scripts execution path exists.
- No log writes secret, raw selection, or full provider payload.
- `writeMemory` remains explicitly unsupported.
- `config.schema.json` matches `Configuration.currentSchemaVersion`.

- [ ] **Step 5: Commit**

```bash
git add README.md AGENTS.md CLAUDE.md docs config.schema.json SliceAIKit SliceAIApp
git commit -m "docs: complete phase 2 status"
```

## Verification Results

Task 1 current verification:

- Red: `swift test --package-path SliceAIKit --filter OrchestrationTests.OutputLifecycleTests` failed before implementation because `MockOutputDispatcher.lifecycleCalls` did not exist.
- Red: after prompt lifecycle implementation, the Agent lifecycle test failed with empty lifecycle calls, proving the agent path still used chunk-only output.
- Green: `swift test --package-path SliceAIKit --filter OrchestrationTests.OutputLifecycleTests`: 2 tests, 0 failures.
- Green: `swift test --package-path SliceAIKit --filter 'OrchestrationTests.OutputLifecycleTests|OrchestrationTests.ExecutionEngineTests|OrchestrationTests.AgentExecutorTests'`: 56 tests, 0 failures.
- Green: `swift test --package-path SliceAIKit --filter 'OrchestrationTests.OutputDispatcherTests|OrchestrationTests.OutputDispatcherFallbackTests|OrchestrationTests.OutputLifecycleTests'`: 18 tests, 0 failures.
- Green: touched Swift files `swiftlint lint --strict ...`: 0 violations.
- Green: `git diff --check`: passed.

Pre-plan baseline from Task 62 was:

- `swift test --package-path SliceAIKit`: 803 tests, 1 skipped, 0 failures.
- `swiftlint lint --strict`: 0 violations.
- `git diff --check`: passed.
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`: `BUILD SUCCEEDED`.

## Self-Review

- Spec coverage: Output lifecycle, side effects, DisplayModes, TTS, English Tutor, docs and gates each have at least one task.
- Placeholder scan: no task uses vague placeholder wording; unsupported `writeMemory` is explicitly scoped to Phase 3.
- Type consistency: canonical new names are `OutputInvocationContext`, `SideEffectExecutorProtocol`, `TTSCapability`, `StructuredValue`, and `EnglishTutorToolFactory`.
