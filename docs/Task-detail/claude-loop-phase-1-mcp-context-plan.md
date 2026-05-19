---
slug: phase-1-mcp-context-plan
created: 2026-05-06T13:34:26Z
last_updated: 2026-05-06T14:47:38Z
status: approve
total_rounds: 8
max_iterations: 8
reviewer_model: opus
---

# Claude Review Loop - Phase 1 MCP Context Implementation Plan

<goal_contract>
Task: Review `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md` before Phase 1 implementation begins. The plan should be actionable for agentic workers, aligned with the approved Phase 1 design spec, and should not silently widen scope beyond the v0.3 DoD.

In-scope:
- `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`

Out-of-scope:
- Do not re-open the approved design direction unless the plan contradicts it or omits a required implementation path.
- Do not review implementation code quality; this is a plan review, not a code review.
- Treat `README.md`, `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`, `docs/v2-refactor-master-todolist.md`, and `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md` as reference context only.
- Historical `.claude-review-loop/runs/phase-1-mcp-context-design/**` outputs and handoff files are out of scope.

Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all remaining findings are low and rejected/deferred with stable reasons.
2. The plan has no accepted critical/high finding left unfixed.
3. Relevant document checks pass: plan red-flag scan and `git diff --check`.

Max iterations: 8 total. Original loop reached 5 rounds; user explicitly authorized 1-3 follow-up rounds on 2026-05-06, so rounds 6-8 are allowed. Exit early on approve.
</goal_contract>

<reference_documents>
- Project status: `README.md`
- Current task record: `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
- Approved design spec: `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Phase tracker: `docs/v2-refactor-master-todolist.md`
- Review target: `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
</reference_documents>

<prior_round_decisions>
Round 1:
- F1.1 (high, plan lines 232-277): accepted and fixed. Root cause: `MCPJSONValue` declared `Codable` without locking transparent raw JSON shape, so synthesized enum JSON could leak into MCP wire contracts. Fix: Task 1 now requires single-value raw JSON Codable and adds a concrete round-trip assertion.
- F1.2 (high, plan lines 909-1090): accepted and fixed. Root cause: permission UI ownership was ambiguous between broker and callers. Fix: Task 8 now chooses broker-owned consent via injected `PermissionConsentPresenting`; Task 9 wires the AppKit presenter; Task 11 says AgentExecutor does not call the presenter.
- F1.3 (medium, plan lines 977-988): accepted and fixed. Root cause: the broker snippet omitted the existing dry-run `wouldRequireConsent` branch. Fix: Task 8 now preserves dry-run for network-write/exec and adds a regression test name.
- F1.4 (medium, plan lines 1224-1262): accepted and fixed. Root cause: AgentExecutor's MCP approval path lacked the concrete permission gate sequence. Fix: Task 11 now spells out `.mcp(server:tools:)`, broker call parameters, approved/denied/error handling, and non-persistence.
- F1.5 (medium, plan lines 909-988): accepted and fixed. Root cause: persistent grant storage did not enforce non-cacheable permission invariants directly. Fix: Task 8 now requires storage-boundary rejection and adds `test_persistentStore_rejectsMCPPermission`.
Round 2:
- F2.1 (medium, plan lines 800-830): accepted and fixed. Root cause: static file permission coverage omitted the design-spec hard-deny check. Fix: Task 6 now requires `PathSandbox.isHardDenied(_:)`, hard-deny regression tests, and coverage failure before exact/prefix/glob matching.
- F2.2 (medium, plan lines 1303-1453): accepted and fixed. Root cause: denial/error lifecycle control flow and event names were not pinned down. Fix: Task 11/12 now use stable tool-call IDs, `.toolCallDenied`, `.toolCallError`, and denial/error-as-tool-result continuation to final answer.
- F2.3 (medium, plan lines 359-1370): accepted and fixed. Root cause: MCP tool input schemas did not flow through the MCP client protocol. Fix: Task 1/2/4/11 now define `MCPToolDescriptor` and require AgentExecutor to build `ChatTool.inputSchema` from `tools(list)`.
- F2.4 (medium, plan lines 130-681): accepted and fixed. Root cause: SettingsUI files import Capabilities but Package.swift did not add the target dependency. Fix: Task 5 now updates the `SettingsUI` target dependencies and documents the architectural choice.
Round 3:
- F3.1 (medium, plan lines 1339-1423): accepted and fixed. Root cause: AgentExecutor could call `tools(for:)` only with a full `MCPDescriptor`, but it only had `MCPToolRef.server`. Fix: Task 3 adds `MCPServerStore.snapshot()`, Task 9 injects an `mcpDescriptors` closure, and Task 11 adds that dependency to AgentExecutor.
- F3.2 (medium, plan lines 1245-1421): accepted and fixed. Root cause: Task 10 did not define the `LLMProvider` tool-calling method or tool-result message encoding. Fix: Task 10 now defines `ChatToolRequest`, `ChatToolChoice`, `ChatMessage` tool result shape, and `LLMProvider.streamToolChat(request:)`; Task 11 uses those contracts.
Round 4:
- F4.1 (medium, plan lines 1452-1709): accepted and fixed. Root cause: multiple MCP transport clients had no concrete routing model. Fix: Task 4 adds `RoutingMCPClient`, Task 9 injects it, and Task 14 extends it for Streamable HTTP / legacy SSE.
- F4.2 (medium, plan lines 1499-1503): accepted and fixed. Root cause: AgentExecutor did not distinguish thrown transport/protocol errors from successful MCP calls that return `MCPCallResult.isError == true`. Fix: Task 11 now maps `isError == true` to `.toolCallError` and adds a dedicated test.
Round 5:
- F5.1 (medium, plan lines 1514-1539): accepted and fixed. Root cause: AgentExecutor appended `role: "tool"` messages without explicitly appending the preceding assistant `tool_calls` message. Fix: Task 11 now appends assistant tool-call messages before any tool result / denial / error message and adds a regression test.
Follow-up authorization:
- User authorized 1-3 additional review rounds to try to obtain explicit Claude `approve`. Do not run beyond Round 8 without a new user instruction.
Round 6:
- F6.1 (medium, plan lines 1517-1551): accepted and fixed. Root cause: missing MCP descriptor was described as a pre-LLM error but still mapped to synthetic tool-call UI / final-answer wording. Fix: Task 11 now fails before first LLM call with configuration invalidTool, adds a missing-descriptor test, and forbids synthetic tool rows for this branch.
- F6.2 (medium, plan lines 1448-1670): accepted and fixed. Root cause: AgentExecutor text deltas were not explicitly routed through existing `.llmChunk` / OutputDispatcher flow. Fix: Task 11 now yields `.llmChunk(delta:)` for `ChatStreamEvent.textDelta`, and Task 12 maps `.llmChunk` through the unchanged OutputDispatcher path.
Round 7:
- F7.1 (medium, plan lines 1463-1554): accepted and fixed. Root cause: model-issued out-of-allowlist tool calls had no event/history contract. Fix: Task 11 now emits proposed + denied, appends a synthetic tool-role message, and forbids broker/MCP calls for this branch.
- F7.2 (medium, plan lines 1517-1556): accepted and fixed. Root cause: same-turn multiple tool calls were not explicitly processed. Fix: Task 11 now processes assembled tool calls in order and appends exactly one `role: .tool` message per provider tool_call_id before the next model turn.
- F7.3 (medium, plan lines 1382-1556): accepted and fixed. Root cause: malformed tool-call arguments had no failure mode. Fix: Task 10 now preserves `argumentsRaw`, Task 11 treats parse failure as `.toolCallError`, appends a tool-role error message, and skips broker/MCP calls.
Round 8:
- Claude returned explicit approve: `verdict: "approve"` and `findings: []`.
</prior_round_decisions>

<review_constraints>
- Material findings only.
- Keep the review inside the implementation plan. Out-of-scope items must be `[ADVISORY]`.
- The review target is currently an untracked file; use the Read tool to inspect `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md` directly rather than relying only on `git diff`.
- Focus on whether the plan is executable, internally consistent, aligned with the approved design spec, and safe against implementation-order mistakes.
- Challenge implementation tasks that reference types, protocols, test targets, or files that the plan never defines.
- Prefer root-cause findings over symptom lists.
- Flag KISS violations only when they create concrete delivery risk or scope creep.
- Reject low-value filler, but list all same-severity material findings before returning. Do not stop after the first critical/high issue when another material issue of the same severity is in scope.
- If no material findings remain, emit the approve signal: `verdict: "approve"` with `findings: []`.
</review_constraints>

<round_meta>
Round: 8 complete
Loop max iterations: 8 total; follow-up ended on approve
Cumulative files changed in loop so far: 2
</round_meta>

## Goal Contract

**Task.** Review the Phase 1 MCP + Context implementation plan before implementation begins. The review should catch plan-level defects that would make worker execution unsafe, incomplete, or inconsistent with the approved design spec.

**Reference Documents.**
- Project status: `README.md`
- Current task record: `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
- Approved design spec: `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Phase tracker: `docs/v2-refactor-master-todolist.md`
- Review target: `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`

**In-scope.**
- `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`

**Out-of-scope.**
- Implementation code quality.
- Rewriting approved architecture without concrete contradiction evidence.
- Historical Claude review output files and handoff files.

**Definition of Done.**
1. Claude returns the explicit approve signal: `verdict: "approve"` and `findings: []`, OR remaining findings are low and rejected/deferred with stable reasons.
2. Relevant document checks pass.
3. No accepted critical/high finding remains unfixed.

**Max iterations.** 8 total. Rounds 6-8 are follow-up rounds explicitly authorized by the user; exit early on approve.

## Rounds

### Round 1 - 2026-05-06T13:47:29Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 2 high / 3 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | high | MCPJSONValue Codable JSON shape never specified | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:232` | accept | Root cause: arbitrary JSON value contract allowed synthesized enum Codable. Fixed by requiring transparent raw JSON shape and adding round-trip tests. |
| F1.2 | high | PermissionBroker / presenter boundary unspecified | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:909` | accept | Root cause: plan mixed broker-owned and caller-owned consent. Fixed by choosing broker-owned presenter injection and updating AppContainer / AgentExecutor steps. |
| F1.3 | medium | Dry-run branch omitted from broker snippet | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:977` | accept | Fixed by preserving `wouldRequireConsent` for dry-run network-write/exec and adding a regression test. |
| F1.4 | medium | AgentExecutor per-tool gate flow unspecified | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1224` | accept | Fixed by spelling out the exact `.mcp` permission, broker call, approval/denial/error transitions, and non-persistence. |
| F1.5 | medium | Persistent store lacks non-cacheable invariant | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:909` | accept | Fixed by requiring storage-boundary rejection for `.mcp`, `.network`, `.shellExec`, and `.appIntents`. |

- **Root-cause groups.** JSON wire contract; permission consent ownership and persistence invariants.
- **Fix applied.** Updated Task 1, Task 8, Task 9, Task 11, M2 gate, and Self-Review sections in the plan.
- **Tests.** `rg` red-flag scan passed after removing banned marker patterns; `git diff --check` passed.
- **Files touched.** `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`, `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`.
- **Drift.** in-scope-only; loop log update is required by the review-loop skill.
- **Status.** continue

### Round 7 - 2026-05-06T14:43:14Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 3 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F7.1 | medium | Out-of-allowlist tool call lacks event/history contract | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1463` | accept | Fixed by emitting proposed + denied, appending a tool-role not-allowed message, and asserting no broker/MCP calls. |
| F7.2 | medium | Parallel tool calls in one assistant turn not explicitly handled | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1517` | accept | Fixed by requiring sequential processing of all assembled tool calls and exactly one tool-role response per provider `tool_call_id`. |
| F7.3 | medium | Malformed tool-call arguments failure mode unspecified | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1382` | accept | Fixed by preserving `argumentsRaw`, allowing nil parsed arguments, surfacing invalid arguments as `.toolCallError`, and skipping broker/MCP. |

- **Root-cause groups.** Tool-call conversation history completeness; malformed argument handling.
- **Fix applied.** Updated Task 10, Task 11, and Self-Review sections.
- **Tests.** `rg` red-flag scan passed; `git diff --check` passed.
- **Files touched.** `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`, `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`.
- **Drift.** in-scope-only; loop log update is required by the review-loop skill.
- **Status.** continue

### Round 4 - 2026-05-06T14:17:54Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 2 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F4.1 | medium | AgentExecutor multi-transport MCPClient routing strategy undecided | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1452` | accept | Fixed by adding `RoutingMCPClient` as the single MCP client facade, injecting it in AppContainer, and extending it in Task 14. |
| F4.2 | medium | AgentExecutor does not handle `MCPCallResult.isError == true` | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1499` | accept | Fixed by mapping `isError == true` to `.toolCallError` and adding `test_agentExecutor_mcpResultIsErrorYieldsToolCallErrorEvent`. |

- **Root-cause groups.** MCP transport routing; MCP tool execution error modeling.
- **Fix applied.** Updated File Structure Map, Task 4, Task 9, Task 11, Task 14, and Self-Review sections.
- **Tests.** `rg` red-flag scan passed; `git diff --check` passed.
- **Files touched.** `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`, `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`.
- **Drift.** in-scope-only; loop log update is required by the review-loop skill.
- **Status.** continue

### Round 3 - 2026-05-06T14:09:29Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 2 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F3.1 | medium | AgentExecutor lacks MCPToolRef.server to MCPDescriptor injection path | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1339` | accept | Fixed by adding `MCPServerStore.snapshot()`, AppContainer `mcpDescriptors` injection, and an AgentExecutor constructor dependency. |
| F3.2 | medium | LLMProvider tool-calling stream API and tool-result message shape undefined | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1245` | accept | Fixed by defining `ChatToolRequest`, `ChatToolChoice`, tool-result `ChatMessage` encoding, and `LLMProvider.streamToolChat(request:)`; Task 11 now uses those contracts. |

- **Root-cause groups.** AgentExecutor runtime dependency injection; LLM tool-calling API contract.
- **Fix applied.** Updated Task 3, Task 9, Task 10, Task 11, and Self-Review sections.
- **Tests.** `rg` red-flag scan passed; `git diff --check` passed.
- **Files touched.** `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`, `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`.
- **Drift.** in-scope-only; loop log update is required by the review-loop skill.
- **Status.** continue

### Round 2 - 2026-05-06T14:01:27Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 4 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F2.1 | medium | PathSandbox hard-deny not enforced in coverage | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:800` | accept | Fixed Task 6 to require hard-deny rejection before exact/prefix/glob coverage and to add a regression test. |
| F2.2 | medium | AgentExecutor / ResultPanel denial and error event channel not pinned down | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1303` | accept | Fixed Task 11/12 to use stable IDs and explicit `.toolCallDenied` / `.toolCallError` events, with denial/error fed back as tool results for final answer generation. |
| F2.3 | medium | MCP input schema source missing from MCPClientProtocol | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:359` | accept | Fixed by introducing `MCPToolDescriptor`, returning it from `tools(for:)`, preserving schemas from `tools/list`, and adding AgentExecutor schema tests. |
| F2.4 | medium | SettingsUI target missing Capabilities dependency | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:130` | accept | Fixed Task 5 to add `Capabilities` to the `SettingsUI` target dependencies and document the dependency choice. |

- **Root-cause groups.** Static permission safety; tool-call lifecycle event contract; MCP tool schema flow; Package.swift dependency correctness.
- **Fix applied.** Updated Task 1, Task 2, Task 4, Task 5, Task 6, Task 11, Task 12, and Self-Review sections.
- **Tests.** `rg` red-flag scan passed; `git diff --check` passed.
- **Files touched.** `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`, `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`.
- **Drift.** in-scope-only; loop log update is required by the review-loop skill.
- **Status.** continue

### Round 5 - 2026-05-06T14:25:19Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 1 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F5.1 | medium | AgentExecutor loop omits assistant tool_calls message before tool results | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1514` | accept | Fixed by adding an explicit assistant tool-call `ChatMessage` append before any `role: "tool"` result / denial / error message, plus a regression test name. |

- **Root-cause groups.** Tool-calling conversation history correctness.
- **Fix applied.** Updated Task 11 loop rules and Self-Review.
- **Tests.** `rg` red-flag scan passed; `git diff --check` passed.
- **Files touched.** `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`, `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`.
- **Drift.** in-scope-only; loop log update is required by the review-loop skill.
- **Status.** exit-max-iterations

### Round 6 - 2026-05-06T14:37:40Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 2 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F6.1 | medium | Missing-server descriptor failure path inconsistent | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1517` | accept | Fixed by making missing descriptors a pre-LLM configuration failure and adding `test_agentExecutor_missingDescriptorFailsBeforeLLMCall`. |
| F6.2 | medium | AgentExecutor model text output path unspecified | `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md:1448` | accept | Fixed by requiring `.llmChunk(delta:)` for model text and the existing OutputDispatcher path, plus `test_agentExecutor_streamsModelTextDeltasAsLLMChunkEvents`. |

- **Root-cause groups.** Pre-LLM configuration failure semantics; agent text streaming / OutputDispatcher integration.
- **Fix applied.** Updated Task 11, Task 12, and Self-Review sections.
- **Tests.** `rg` red-flag scan passed; `git diff --check` passed.
- **Files touched.** `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`, `docs/Task-detail/claude-loop-phase-1-mcp-context-plan.md`.
- **Drift.** in-scope-only; loop log update is required by the review-loop skill.
- **Status.** continue

### Round 8 - 2026-05-06T14:47:38Z

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.** No findings.
- **Root-cause groups.** None.
- **Fix applied.** None.
- **Tests.** Claude returned `findings: []`; final local checks run after this round.
- **Files touched.** None for round output; loop log and status docs updated after approve.
- **Drift.** in-scope-only.
- **Status.** exit-approve

## Final Summary

**Termination reason.** Claude returned explicit approve in Round 8.
**Total rounds.** 8
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 19
- Rejected: 0
- Deferred: 0
- Partial: 0
**Deferred follow-ups.**
- None.
