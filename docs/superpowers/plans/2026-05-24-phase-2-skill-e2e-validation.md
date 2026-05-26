# Phase 2 Skill E2E Validation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prove Phase 2 Skill Registry compatibility with three realistic local Claude / Codex-style skills, from filesystem discovery through `LocalSkillRegistry` and AgentExecutor `sliceai_load_skill`.

**Architecture:** Add repeatable XCTest coverage that creates real temporary skill roots and uses production `SkillDirectoryScanner`, `SkillMarkdownParser`, and `LocalSkillRegistry`. The test then injects that registry into `AgentExecutor` with a scripted tool-calling LLM and verifies metadata exposure, per-tool skill binding, progressive loading, and non-reading of supporting files.

**Tech Stack:** Swift 6.0, XCTest, `Capabilities.LocalSkillRegistry`, `Orchestration.AgentExecutor`, existing Orchestration test mocks, no network or external services in the automated test.

---

## Scope

This plan validates the already-implemented Skill Registry MVP. It does not implement supporting file reading, script execution, marketplace, remote install, DisplayMode, TTS, or English Tutor.

The validation fixtures intentionally include `scripts/`, `references/`, `assets/`, and `agents/openai.yaml` to prove current MVP compatibility with official directory shapes while preserving the current product boundary: only `SKILL.md` is loaded into the Agent.

## Files

- Create: `SliceAIKit/Tests/OrchestrationTests/AgentExecutorSkillE2ETests.swift`
- Modify: `docs/Task-detail/2026-05-24-phase-2-skill-e2e-validation.md`
- Modify: `docs/Task_history.md`
- Modify: `docs/v2-refactor-master-todolist.md`
- Modify: `README.md`

## Task 1: Add Real Filesystem Skill E2E Test

**Files:**
- Create: `SliceAIKit/Tests/OrchestrationTests/AgentExecutorSkillE2ETests.swift`

- [x] **Step 1: Add test skeleton and helpers**

Create a new XCTest file that imports `Capabilities`, `SliceCore`, and `@testable import Orchestration`. Add helpers to create a temporary root, write `SKILL.md`, write supporting files, construct `AgentExecutor`, construct an `AgentTool`, collect events, and script `sliceai_load_skill` tool-call turns.

- [x] **Step 2: Add the 3-skill fixture**

In the test, create these directories under one temporary root:

```text
skills/prose-polisher/SKILL.md
skills/prose-polisher/references/style.md
skills/prose-polisher/assets/template.md
skills/prose-polisher/scripts/check.sh
skills/prose-polisher/agents/openai.yaml

.claude/skills/claude-research/SKILL.md
.claude/skills/claude-research/references/checklist.md

.agents/skills/codex-review/SKILL.md
.agents/skills/codex-review/agents/openai.yaml
```

The fixtures must include `name`, `description`, `allowed-tools`, `disable-model-invocation`, and `user-invocable` combinations drawn from the official Codex / Claude skill formats.

- [x] **Step 3: Assert registry compatibility**

Use:

```swift
let settings = SkillSettings(
    sources: [SkillSource(id: "project", displayName: "Project Skills", rootPath: root.path, isEnabled: true, order: 0)],
    overrides: ["claude-research": .on]
)
let registry = LocalSkillRegistry(settingsProvider: { settings })
let snapshot = try await registry.snapshot()
```

Assert:

- exactly 3 enabled skills are visible;
- `prose-polisher`, `claude-research`, and `codex-review` are present;
- `claude-research` is enabled because of override `.on`;
- `allowedTools` is parsed into manifest fields;
- no diagnostics are emitted for the three valid skills.

- [x] **Step 4: Assert AgentExecutor progressive loading**

Construct an Agent Tool bound to all 3 skills and run `AgentExecutor` with `LocalSkillRegistry`.

The scripted LLM should:

1. call `sliceai_load_skill` with `{"name":"prose-polisher"}`;
2. call `sliceai_load_skill` with `{"name":"claude-research"}`;
3. return final text.

Assert:

- initial provider request exposes `sliceai_load_skill`;
- initial prompt contains the three skill metadata lines;
- `toolCallResult` contains the real `SKILL.md` body for loaded skills;
- result does not contain content from `references/style.md` or `scripts/check.sh`;
- no MCP tool call is made for `sliceai_load_skill`.

- [x] **Step 5: Run focused test**

Run:

```bash
swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorSkillE2ETests
```

Expected: pass. If it fails, fix the product code or test expectation based on the failure.

## Task 2: Fix Compatibility Issues If Found

**Files:**
- Modify only the product files implicated by the focused E2E failure.
- Update or extend the E2E test to prove the fixed behavior.

- [x] **Step 1: Diagnose failure from evidence**

Use the exact failure output to classify whether the issue is scanner, parser, registry state, Agent prompt metadata, pseudo-tool dispatch, or unsupported fixture expectation.

- [x] **Step 2: Make the smallest product fix**

Preserve current MVP non-goals:

- Do not read `references/` or `assets/`.
- Do not execute `scripts/`.
- Do not map `allowed-tools` to SliceAI `Permission`.
- Do not add Prompt Tool skill binding.

- [x] **Step 3: Re-run focused test**

Run:

```bash
swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorSkillE2ETests
```

Expected: pass.

## Task 3: Documentation and Gate

**Files:**
- Modify: `docs/Task-detail/2026-05-24-phase-2-skill-e2e-validation.md`
- Modify: `docs/Task_history.md`
- Modify: `docs/v2-refactor-master-todolist.md`
- Modify: `README.md`

- [x] **Step 1: Update task docs**

Record:

- the three fixture layouts;
- any compatibility issues found;
- whether product code changed;
- focused and full validation results.

- [x] **Step 2: Update master todolist**

Mark Phase 2 “真实 Skill E2E 兼容性验证” as complete only after the focused E2E and full gate pass. Keep Anthropic public repo compatibility, supporting files, DisplayMode, TTS, and English Tutor as pending.

- [x] **Step 3: Run full validation gate**

Run:

```bash
swift test --package-path SliceAIKit
swiftlint lint --strict
git diff --check
```

Expected:

- SwiftPM tests pass.
- SwiftLint exits 0.
- `git diff --check` has no output.

## Self-Review

- Spec coverage: This plan covers the accepted next step, “真实 Skill E2E 兼容性验证”.
- Scope check: It validates local Claude / Codex style skills only; public Anthropic repository validation remains a separate Phase 2 task.
- Placeholder scan: No TBD / TODO placeholders remain.
- Type consistency: Uses current `SkillSettings`, `SkillSource`, `LocalSkillRegistry`, `AgentExecutor`, and provider-visible `sliceai_load_skill` names.

## Execution Result

- Focused Skill E2E passed: `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorSkillE2ETests`.
- No product compatibility fix was needed for Skill scanner / parser / registry / AgentExecutor.
- Full gate first exposed an existing prompt-stream cancellation test race; `ExecutionEngineTests` now uses a cancellation-aware first-chunk dispatcher fixture to make the cancellation assertion deterministic.
- Full validation passed: `swift test --package-path SliceAIKit`（796 tests）、`swiftlint lint --strict`、`git diff --check`。
