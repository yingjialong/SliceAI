# Phase 2 Skill Supporting Files Read-Only Loading Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add safe, read-only loading for skill `references/` and text `assets/` supporting files.

**Architecture:** Keep `SliceCore.SkillResource` as the lightweight resource index. Add a `SkillResourcePayload` and `loadSkillResource` API in Capabilities, implement resource indexing/loading in `LocalSkillRegistry`, then expose a second AgentExecutor pseudo-tool that reads only resources for already loaded bound skills.

**Tech Stack:** Swift 6.0, SwiftPM, XCTest, existing `AgentExecutor` pseudo-tool flow, existing `sanitizeToolMessageContent` redaction/truncation.

---

## File Structure

- Modify `SliceAIKit/Sources/Capabilities/Skills/SkillRegistryProtocol.swift`: add payload type and protocol method.
- Modify `SliceAIKit/Sources/Capabilities/Skills/LocalSkillRegistry.swift`: index resources and read resource content safely.
- Modify `SliceAIKit/Sources/Capabilities/Skills/MockSkillRegistry.swift`: support tests/previews for resource payloads.
- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCatalog.swift`: add `sliceai_load_skill_resource` schema/ref.
- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`: handle resource pseudo-tool.
- Add `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+SkillResources.swift`: keep resource validation/loading out of the general MCP tool-call file.
- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`: include resource paths and footer instructions.
- Test `SliceAIKit/Tests/CapabilitiesTests/LocalSkillRegistryTests.swift`.
- Test `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`.
- Update project docs.

## Task 1: Registry Resource Index And Loader

- [x] Add failing tests in `LocalSkillRegistryTests` for resource indexing, successful read, script rejection, traversal rejection, symlink escape rejection.
- [x] Run focused registry tests and confirm failure.
- [x] Add `SkillResourcePayload` and `loadSkillResource` to the protocol.
- [x] Implement resource scanning under `references/` and text `assets/`.
- [x] Implement path validation, UTF-8 read, 64 KiB max file size, symlink containment.
- [x] Run focused registry tests until green.

## Task 2: Agent Pseudo-Tool

- [x] Add failing tests in `AgentExecutorTests` for `sliceai_load_skill_resource`.
- [x] Run focused AgentExecutor tests and confirm failure.
- [x] Add resource pseudo-tool schema and synthetic ref.
- [x] Handle resource tool calls locally after `sliceai_load_skill`.
- [x] Ensure unbound skill, unloaded skill, bad args, and blocked paths return tool-call errors.
- [x] Run focused AgentExecutor tests until green.

## Task 3: Prompt Metadata And E2E Guard

- [x] Update `AgentPromptBuilder` metadata to list resource relative paths within the existing 8,000 character budget.
- [x] Extend or add E2E coverage proving references/assets are no longer only inert fixtures.
- [x] Ensure scripts remain unlisted/unread.
- [x] Run Skill E2E and public smoke focused checks.

## Task 4: Documentation And Gates

- [x] Update README, AGENTS, CLAUDE, master todolist and task detail.
- [x] Run `swift test --package-path SliceAIKit --filter CapabilitiesTests.LocalSkillRegistryTests`.
- [x] Run `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests`.
- [x] Run `swift test --package-path SliceAIKit`.
- [x] Run `swiftlint lint --strict`.
- [x] Run `git diff --check`.

## Verification Results

- `swift test --package-path SliceAIKit --filter CapabilitiesTests.LocalSkillRegistryTests`: 11 tests, 0 failures.
- `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorTests`: 35 tests, 0 failures.
- `swift test --package-path SliceAIKit --filter OrchestrationTests.AgentExecutorSkillE2ETests`: 1 test, 0 failures.
- `bash scripts/phase2-public-skill-smoke.sh`: passed, 3 repositories / 9 public skills.
- `swift test --package-path SliceAIKit`: 803 tests, 1 skipped, 0 failures.
- `swiftlint lint --strict`: 0 violations.
- `git diff --check`: passed.
- `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`: `BUILD SUCCEEDED`.

## Self-Review

- Spec coverage: registry API, Agent pseudo-tool, prompt metadata, safety constraints and docs are covered.
- Placeholder scan: no task relies on TBD behavior.
- Type consistency: `SkillResourcePayload`, `loadSkillResource`, `sliceai_load_skill_resource` are the canonical names for this slice.
