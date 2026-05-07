---
slug: m1-task-4-stdio-mcp-json-rpc-client
created: 2026-05-07T13:20:00+08:00
last_updated: 2026-05-07T15:38:00+08:00
status: approved
total_rounds: 3
max_iterations: 5
reviewer_model: opus
review_scope: branch cfcf80b..HEAD
---

# Claude Review Loop - M1 Task 4 Stdio MCP JSON-RPC Client

## Goal Contract

**Task.** Review M1 Task 4: add the first real MCP client transport for local stdio servers. The change introduces MCP JSON-RPC framing, `StdioMCPClient`, `RoutingMCPClient`, stderr diagnostics redaction, process lifecycle handling, and tests. The goal is to catch material correctness, security, concurrency, protocol, and maintainability issues before continuing to later Phase 1 tasks.

**Reference Documents.**
- Project status and change log: `README.md`
- Task implementation record: `docs/Task-detail/2026-05-07-phase-1-m1-task-4-stdio-mcp-json-rpc-client.md`
- Phase 1 plan: `/Users/majiajun/workspace/SliceAI/docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- Capabilities module notes: `docs/Module/Capabilities.md`

**In-scope.**
- `SliceAIKit/Sources/Capabilities/MCP/MCPJSONRPC.swift`
- `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift`
- `SliceAIKit/Sources/Capabilities/MCP/RoutingMCPClient.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPDiagnosticLog.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- `SliceAIKit/Tests/CapabilitiesTests/MCPJSONRPCTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/StdioMCPClientTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/RoutingMCPClientTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/Fixtures/stdio-mcp-fixture.js`
- `SliceAIKit/Package.swift` test resource wiring
- Task 4 documentation updates in `README.md`, `docs/Module/Capabilities.md`, `docs/Task_history.md`, and the Task 4 detail doc

**Out-of-scope.**
- Implementing Streamable HTTP remote MCP transport. That remains a later M4 task.
- Implementing legacy HTTP+SSE. The user explicitly decided to deprecate/skip old SSE and support Streamable HTTP only later.
- Wiring real MCP calls into `AgentExecutor` or app runtime beyond the current routing facade boundary.
- Settings UI for remote servers, per-tool hotkeys, five-server E2E, release docs, or broad Phase 1 planning changes.
- Rewriting the existing SliceCore canonical MCP data model unless Task 4 introduces a concrete incompatibility.

**Definition of Done.**
1. Claude returns the explicit approve signal: `verdict: "approve"` and `findings: []`, OR remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass.
3. No accepted critical/high finding remains unfixed.

**Max iterations.** 5. This is an upper bound, not a required number of rounds; exit early on approve.

## Current Focus Prompt

<goal_contract>
Task: Review M1 Task 4: real stdio MCP JSON-RPC client, JSON-RPC framing, routing facade, diagnostics redaction, process lifecycle handling, and tests.
In-scope:
- `SliceAIKit/Sources/Capabilities/MCP/MCPJSONRPC.swift`
- `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift`
- `SliceAIKit/Sources/Capabilities/MCP/RoutingMCPClient.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPDiagnosticLog.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- `SliceAIKit/Tests/CapabilitiesTests/MCPJSONRPCTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/StdioMCPClientTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/RoutingMCPClientTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/Fixtures/stdio-mcp-fixture.js`
- `SliceAIKit/Package.swift`
- Task 4 documentation updates
Out-of-scope:
- Streamable HTTP implementation, legacy HTTP+SSE implementation, AgentExecutor runtime wiring, Settings UI, per-tool hotkeys, E2E/release docs, and broad data model redesigns.
Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass.
3. No accepted critical/high finding remains unfixed.
Max iterations: 5, upper bound only.
</goal_contract>

<reference_documents>
- Project status and change log: `README.md`
- Task implementation record: `docs/Task-detail/2026-05-07-phase-1-m1-task-4-stdio-mcp-json-rpc-client.md`
- Phase 1 plan: `/Users/majiajun/workspace/SliceAI/docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- Capabilities module notes: `docs/Module/Capabilities.md`
</reference_documents>

<prior_round_decisions>
Round 1:
- F1.1 (medium, `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift:272`): accepted and fixed. Root cause: stale idle timeout tasks had no generation/token validation, so a task that had already passed `Task.sleep` could still run after `cancelIdleTimeout` and close an in-flight session. Fix: add actor-isolated idle task generations and validate the generation before `stopIdleSession` tears down a session; cancel clears both task and generation.
Round 2:
- F2.1 (high, `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift:87`): accepted and fixed. Root cause: actor reentrancy allowed concurrent same-server first callers to observe no session before initialize completed, starting duplicate stdio processes. Fix: add per-server `sessionStartTasks` single-flight so concurrent callers await the same start/initialize task.
- F2.2 (high, `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift:156`): accepted and fixed. Root cause: stdout/stderr handlers spawned one unstructured Task per chunk, so chunk delivery to routers depended on scheduler ordering. Fix: replace per-chunk Task hops with one FIFO `AsyncStream<Data>` consumer task per pipe.

Known issues already found and fixed before this Claude loop:
- First public entry via `call(ref:args:)` now performs `tools/list` before `tools/call`.
- `tools/list` optional MCP `title` is preserved with fallback to `name`.
- stdout response handling no longer performs actor-isolated blocking `readData`; it uses a response router and request timeout.
- initialize/request failure tears down bad sessions instead of reusing unknown protocol state.
- stderr diagnostics are buffered by line before redaction and do not include raw server id.
</prior_round_decisions>

<review_constraints>
- Material findings only.
- Keep the review inside in-scope. Out-of-scope items must be `[ADVISORY]`.
- Challenge prior fixes only with concrete evidence from the current code.
- Prefer root-cause findings over symptom lists.
- Flag KISS violations only when they create concrete risk or scope creep.
- Do not request legacy HTTP+SSE support in this Task 4 review.
- Reject low-value filler, but list all same-severity material findings before returning. Do not stop after the first critical/high issue when another material issue of that same severity is in scope.
- If no material findings remain, emit the approve signal: `verdict: "approve"` with `findings: []`.
</review_constraints>

<round_meta>
Round: 3
Loop max iterations: 5, upper bound only
Cumulative files changed in loop so far: 3
Review scope: branch diff `cfcf80b..HEAD`
</round_meta>

## Rounds

### Round 1 - 2026-05-07T15:14:00+08:00

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 1 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | medium | Idle teardown task can still execute after `cancelIdleTimeout` and stop an in-flight session | `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift:272` | accept | The race is real: cancellation only reliably stops `Task.sleep`; after sleep returns, old task can still enqueue `stopIdleSession`, which had no token/generation check. Fixed by adding actor-isolated idle task generations and validating generation before teardown. |

- **Root-cause groups.** Stale idle timeout teardown lacked a current-schedule guard.
- **Fix applied.** Added `idleTaskGenerations` / `nextIdleTaskGeneration`; `scheduleIdleTimeout` assigns a generation; `cancelIdleTimeout` clears it; `stopIdleSession(serverID:generation:)` returns if the generation is stale. Added a regression test that previously failed at the idle boundary and now passes.
- **Tests.**
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests/test_stdioClient_cancelledIdleTimeoutCannotStopInFlightRequest`：修复前失败，修复后 1 test passed。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests`：9 tests passed。
- **Files touched.**
  - `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift`
  - `SliceAIKit/Tests/CapabilitiesTests/StdioMCPClientTests.swift`
  - `SliceAIKit/Tests/CapabilitiesTests/Fixtures/stdio-mcp-fixture.js`
- **Drift.** in-scope-only
- **Status.** continue

### Round 2 - 2026-05-07T15:23:00+08:00

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 2 high / 0 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F2.1 | high | Actor reentrancy lets concurrent same-server callers spawn duplicate stdio processes that leak | `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift:87` | accept | The reentrancy window is real: `sessions[id]` was only assigned after `await initialize`, so concurrent first callers could each start a process. Fixed with per-server `sessionStartTasks` single-flight registered before the first await. |
| F2.2 | high | stdout/stderr readabilityHandlers spawn unordered Tasks, allowing NDJSON framing corruption and cross-chunk secret leakage | `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift:156` | accept | The per-chunk unstructured Task hop can reorder delivery to the target actor. Fixed by installing one FIFO `AsyncStream<Data>` consumer task per pipe and yielding chunks from the FileHandle handler. |

- **Root-cause groups.**
  - Session startup was not single-flight under actor reentrancy.
  - Pipe chunk delivery used unordered unstructured tasks instead of one ordered consumer.
- **Fix applied.**
  - Added `sessionStartTasks` to serialize start/initialize per descriptor id.
  - Added `test_stdioClient_concurrentFirstUseSharesSingleSessionStart`, with fixture initialize counting and delay.
  - Replaced stdout/stderr per-chunk `Task { await ... }` with one FIFO `AsyncStream<Data>` consumer per pipe.
  - Stored reader tasks in `StdioMCPProcessSession` and cancel them during `stop(session:)`.
- **Tests.**
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests`：10 tests passed。
- **Files touched.**
  - `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift`
  - `SliceAIKit/Tests/CapabilitiesTests/StdioMCPClientTests.swift`
  - `SliceAIKit/Tests/CapabilitiesTests/Fixtures/stdio-mcp-fixture.js`
- **Drift.** in-scope-only
- **Status.** continue

### Round 3 - 2026-05-07T15:35:00+08:00

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.** No findings.
- **Root-cause groups.** None.
- **Fix applied.** None.
- **Tests.**
  - `swift test --filter CapabilitiesTests.MCPJSONRPCTests`：3 tests passed。
  - `swift test --filter CapabilitiesTests.StdioMCPClientTests`：10 tests passed。
  - `swift test --filter CapabilitiesTests.RoutingMCPClientTests`：2 tests passed。
  - `swift test --filter CapabilitiesTests.MCPClientProtocolTests`：12 tests passed。
  - `swift test --filter CapabilitiesTests`：59 tests passed。
  - `swift test`：622 tests passed。
- **Files touched.** None in this round.
- **Drift.** in-scope-only
- **Status.** exit-approve

## Final Summary

**Termination reason.** Claude returned explicit approve signal in Round 3.
**Total rounds.** 3
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 3
- Rejected: 0
- Deferred: 0
- Partial: 0
**Deferred follow-ups.**
- None.
