---
slug: phase-1-m3-task-10-llm-tool-calling-contract
created: 2026-05-08T13:35:52Z
last_updated: 2026-05-08T13:41:52Z
status: approved
total_rounds: 1
max_iterations: 5
reviewer_model: opus
---

# Claude Review Loop - Phase 1 M3 Task 10 LLM Tool Calling Contract

## Goal Contract

**Task.** Review M3 Task 10, which adds the SliceCore and LLMProviders contract for OpenAI-compatible tool calling: `ChatTool`, `ChatToolRequest`, `ChatStreamEvent`, `LLMProvider.streamToolChat(request:)`, OpenAI `delta.tool_calls` decoding, SSE tool-call streaming tests, and the minimal `PromptExecutor` adjustment needed for optional message content. Verify that the implementation is safe, scoped to Task 10, and does not prematurely implement AgentExecutor or UI behavior.

**Reference Documents.**
- Project state: `README.md`
- Task implementation record: `docs/Task-detail/2026-05-08-phase-1-m3-task-10-llm-tool-calling-contract.md`
- Phase 1 design spec: `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Phase 1 implementation plan: `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- Master dashboard: `docs/v2-refactor-master-todolist.md`

**In-scope.**
- `SliceAIKit/Sources/SliceCore/ChatTypes.swift`
- `SliceAIKit/Sources/SliceCore/LLMProvider.swift`
- `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift`
- `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift`
- `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`
- `SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift`
- `SliceAIKit/Tests/LLMProvidersTests/OpenAIDTOsTests.swift`
- `SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift`
- `SliceAIKit/Tests/LLMProvidersTests/Fixtures/openai_chat_tool_call.sse`
- Task 10 documentation and synced Phase 1 plan.

**Out-of-scope.**
- Implementing `AgentExecutor`, MCP allowlist validation, permission gating for MCP tool calls, ResultPanel tool-call lifecycle UI, or `web-search-summarize`; those belong to M3 Tasks 11-13.
- Implementing Streamable HTTP, per-tool hotkeys, or five-server E2E; those belong to M4.
- Broadly fixing historical `swiftlint --strict` violations in M1/M2 files unless Task 10 directly caused them.
- Changing provider selection, Keychain behavior, existing prompt-only streaming semantics, or MCP transport behavior.

**Definition of Done.**
1. Claude returns the explicit approve signal: `verdict: "approve"` and `findings: []`, OR remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass.
3. No accepted critical/high finding remains unfixed.
4. Mutation check shows no unexpected file drift outside the review output directory.

**Max iterations.** 5 (upper bound; exit early on approve)

**Review scope.** Branch review over `HEAD~1..HEAD` (`0099aa4 feat(llm): add openai tool call streaming`).

## Focus Prompt For Round 1

<goal_contract>
Task: Review M3 Task 10, which adds the OpenAI-compatible tool calling contract for SliceCore and LLMProviders. Verify that the new `ChatTool*` types, `LLMProvider.streamToolChat(request:)`, OpenAI DTO decoding, SSE streaming conversion, tests, and PromptExecutor optional-content adjustment are correct and scoped. The implementation must preserve prompt-only behavior and must not sneak in AgentExecutor, ResultPanel UI, Streamable HTTP, or per-tool hotkey behavior.
In-scope:
- SliceAIKit/Sources/SliceCore/ChatTypes.swift
- SliceAIKit/Sources/SliceCore/LLMProvider.swift
- SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift
- SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift
- SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift
- SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift
- SliceAIKit/Tests/LLMProvidersTests/OpenAIDTOsTests.swift
- SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift
- SliceAIKit/Tests/LLMProvidersTests/Fixtures/openai_chat_tool_call.sse
- Task 10 docs and synced Phase 1 plan.
Out-of-scope:
- AgentExecutor, MCP allowlist validation, MCP permission gating, ResultPanel tool-call UI, and built-in `web-search-summarize`.
- Streamable HTTP, per-tool hotkeys, and five-server E2E.
- Historical full-repo swiftlint cleanup outside files touched by Task 10.
- Changes to prompt-only provider behavior beyond optional `ChatMessage.content` compatibility.
Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass.
3. No accepted critical/high finding remains unfixed.
4. Mutation check shows no unexpected file drift outside the review output directory.
Max iterations: 5 (upper bound, not a required number of rounds)
</goal_contract>

<reference_documents>
- Project state: README.md
- Task implementation record: docs/Task-detail/2026-05-08-phase-1-m3-task-10-llm-tool-calling-contract.md
- Phase 1 design spec: docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md
- Phase 1 implementation plan: docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md
- Master dashboard: docs/v2-refactor-master-todolist.md
</reference_documents>

<prior_round_decisions>
None. This is the first Claude review round for M3 Task 10.
</prior_round_decisions>

<review_constraints>
- Material findings only.
- Keep the review inside in-scope. Out-of-scope items must be `[ADVISORY]`.
- Challenge rejected findings only with new evidence.
- Prefer root-cause findings over symptom lists.
- Flag KISS violations only when they create concrete risk or scope creep.
- Reject low-value filler, but list all same-severity material findings before returning. Do not stop after the first critical/high issue when another material issue of that same severity is in scope.
- If no material findings remain, emit the approve signal: `verdict: "approve"` with `findings: []`.
</review_constraints>

<round_meta>
Round: 1
Loop max iterations: 5
Cumulative files changed in loop so far: 0
</round_meta>

## Rounds

### Round 1 - 2026-05-08T13:41:52Z

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| None | none | No findings | n/a | n/a | Claude returned `verdict: "approve"` with `findings: []`. |

- **Root-cause groups.** None.
- **Fix applied.** None required.
- **Tests.** Implementation verification remains current: `swift test --filter SliceCoreTests.ChatTypesTests`, `swift test --filter LLMProvidersTests.OpenAIDTOsTests`, `swift test --filter LLMProvidersTests.OpenAICompatibleProviderTests`, `swift test --filter LLMProvidersTests`, `swift test --filter OrchestrationTests.PromptExecutorTests`, `swift test --filter OrchestrationTests.ExecutionEngineTests`, full `swift test`, `git diff --check`, touched Swift files targeted `swiftlint lint --strict`, and App Debug `xcodebuild` passed. Full-repo `swiftlint lint --strict` is blocked by historical M1/M2 violations outside Task 10 scope.
- **Files touched.** None during review round.
- **Drift.** in-scope-only; mutation check reported `mutation_detected: false`.
- **Status.** exit-approve

## Final Summary

**Termination reason.** Claude approve in round 1.
**Total rounds.** 1
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 0
- Rejected: 0
- Deferred: 0
- Partial: 0
**Deferred follow-ups.**
- None.

**Claude summary.** Task 10 establishes the OpenAI-compatible tool calling contract with the correct wire shape and streaming semantics, preserves prompt-only behavior, keeps `argumentsRaw` for Task 11 malformed JSON handling, and avoids out-of-scope AgentExecutor / ResultPanel UI / Streamable HTTP / per-tool hotkey work. No material findings remain.
