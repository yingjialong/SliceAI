---
slug: m1-task-1-mcp-json-contract
created: 2026-05-06T15:46:05Z
last_updated: 2026-05-06T16:10:22Z
status: approve
total_rounds: 2
max_iterations: 5
reviewer_model: opus
---

# Claude Review Loop - M1 Task 1 MCP JSON Contract

## Goal Contract

**Task.** Review M1 Task 1 implementation: establish the SliceCore MCP JSON/value contract needed by Phase 1 before moving to the canonical MCP client protocol work. The review should catch material bugs in raw JSON encoding, MCP content/result wire shape, MCP nested arguments, audit redaction, and documentation ownership created by this task.

**Reference Documents.**
- Project status: `README.md`
- Task implementation record: `docs/Task-detail/2026-05-06-phase-1-m1-task-1-mcp-json-contract.md`
- Approved design spec: `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Approved implementation plan: `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- SliceCore MCP descriptor boundary: `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
- Existing Capabilities MCP boundary: `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- Audit redaction boundary: `SliceAIKit/Sources/Orchestration/Telemetry/JSONLAuditLog.swift`

**In-scope.**
- `SliceAIKit/Sources/SliceCore/MCPJSONValue.swift`
- `SliceAIKit/Sources/SliceCore/MCPContentItem.swift`
- `SliceAIKit/Sources/SliceCore/MCPToolDescriptor.swift`
- `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
- `SliceAIKit/Sources/SliceCore/OutputBinding.swift`
- `SliceAIKit/Sources/SliceCore/ToolKind.swift`
- `SliceAIKit/Tests/SliceCoreTests/MCPJSONValueTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/MCPContentItemTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/MCPDescriptorTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/OutputBindingTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`
- Minimal downstream adaptation caused directly by moving `MCPCallResult` into SliceCore or changing `SideEffect.callMCP` / `PipelineStep.mcp` params to `MCPJSONValue.Object`:
  - `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
  - `SliceAIKit/Tests/CapabilitiesTests/MCPClientProtocolTests.swift`
  - `SliceAIKit/Sources/Orchestration/Telemetry/JSONLAuditLog.swift`
  - `SliceAIKit/Tests/OrchestrationTests/JSONLAuditLogTests.swift`
- Documentation touched by Task 1:
  - `README.md`
  - `docs/Module/Capabilities.md`
  - `docs/Module/SliceCore.md`
  - `docs/Task_history.md`
  - `docs/Task-detail/2026-05-06-phase-1-m1-task-1-mcp-json-contract.md`

**Out-of-scope.**
- Task 2 canonical MCP client protocol migration: do not require deleting Capabilities' duplicate simplified `MCPDescriptor`, changing `MCPClientProtocol.tools(for:)` to return `MCPToolDescriptor`, or changing `MCPClientProtocol.call(ref:args:)` to `MCPJSONValue.Object` in this Task 1 review.
- Real MCP transport/client implementation, MCP server store, Settings UI, AgentExecutor tool-calling, permission UX, and context providers.
- Broad API redesign beyond the public shapes required by Task 1.
- Findings that only restate already-planned Task 2 work should be marked `[ADVISORY]` unless they create a Task 1 regression.

**Definition of Done.**
1. Claude returns the explicit approve signal: `verdict: "approve"` and `findings: []`, OR all remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass, including full `swift test`.
3. No accepted critical/high finding remains unfixed.

**Max iterations.** 5 (upper bound; exit early on approve)

**Review scope.** `branch --base f73d09b`, reviewing the single Task 1 implementation commit currently at `ed33a8894042943c485af54c561aa66eb547b946`.

## Focus Prompt For Current Round

<goal_contract>
Task: Review M1 Task 1 implementation: establish the SliceCore MCP JSON/value contract needed by Phase 1 before moving to canonical MCP client protocol work.
In-scope:
- SliceCore MCP JSON/value contract files and tests.
- Minimal downstream adaptation caused directly by moving `MCPCallResult` into SliceCore or changing `SideEffect.callMCP` / `PipelineStep.mcp` params to `MCPJSONValue.Object`.
- Task 1 documentation updates.
Out-of-scope:
- Task 2 canonical MCP client protocol migration: do not require deleting Capabilities' duplicate simplified `MCPDescriptor`, changing `tools(for:)` to return `MCPToolDescriptor`, or changing `call(ref:args:)` to `MCPJSONValue.Object` in this Task 1 review.
- Real MCP clients/transports, MCP server store, Settings UI, AgentExecutor tool calling, permission UX, and context providers.
- Broad redesign beyond Task 1 public shapes.
Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass, including full `swift test`.
3. No accepted critical/high finding remains unfixed.
Max iterations: 5 (upper bound, not a required number of rounds)
</goal_contract>

<reference_documents>
- Project status: `README.md`
- Task implementation record: `docs/Task-detail/2026-05-06-phase-1-m1-task-1-mcp-json-contract.md`
- Approved design spec: `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Approved implementation plan: `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- Review target diff: branch `feature/phase-1-mcp-context` against base `f73d09b`
- Official MCP schema reference for content item wire shape: `https://modelcontextprotocol.io/specification/2025-06-18/schema`
</reference_documents>

<prior_round_decisions>
Round 1:
- F1.1 (medium, `SliceAIKit/Sources/SliceCore/MCPContentItem.swift:145`): accepted and fixed. Root cause: synthesized `Codable` mapped Swift `MCPCallResult.meta` to JSON key `meta`, but MCP Result metadata uses `_meta`. Fix: added explicit `CodingKeys` mapping `meta = "_meta"` and tests for encoding `_meta` plus decoding wire `_meta`.
</prior_round_decisions>

<review_constraints>
- Material findings only.
- Keep the review inside Task 1. Out-of-scope items must be `[ADVISORY]`.
- Challenge the Task 1 / Task 2 boundary only with concrete evidence that the Task 1 commit itself breaks tests, leaks secrets, or creates an incompatible public contract.
- Prefer root-cause findings over symptom lists.
- Flag KISS violations only when they create concrete correctness, security, maintainability, or scope-creep risk.
- Verify MCP JSON/content wire shapes, raw JSON Codable behavior, audit redaction, and documentation consistency.
- Reject low-value filler, but list all same-severity material findings before returning. Do not stop after the first critical/high issue when another material issue of the same severity is in scope.
- If no material findings remain, emit the approve signal: `verdict: "approve"` with `findings: []`.
</review_constraints>

<round_meta>
Round: 2
Loop max iterations: 5 (upper bound only)
Cumulative files changed in loop so far: 4
</round_meta>

## Rounds

### Round 1 - 2026-05-06T15:58:10Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 1 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | medium | `MCPCallResult.meta` uses `meta` instead of MCP wire `_meta` | `SliceAIKit/Sources/SliceCore/MCPContentItem.swift:145` | accept | Root cause: synthesized `Codable` maps the Swift property name `meta` directly, but MCP result metadata is `_meta`. Fix: add explicit `CodingKeys` mapping `meta = "_meta"` and golden/decode tests to lock the wire shape. |

- **Root-cause groups.** MCP call result metadata wire key not pinned by tests.
- **Fix applied.** Added explicit `MCPCallResult.CodingKeys` mapping `meta = "_meta"` and two regression tests covering `_meta` encode/decode. Updated SliceCore module docs and Task 1 task record to document the wire key.
- **Tests.** Red: `swift test --filter SliceCoreTests.MCPContentItemTests` failed with `meta == nil` on `_meta` decode and encoded JSON containing `meta`. Green: `swift test --filter SliceCoreTests.MCPContentItemTests` passed 15 tests; `swift test` passed 593 tests; `git diff --check` passed.
- **Files touched.** `SliceAIKit/Sources/SliceCore/MCPContentItem.swift`, `SliceAIKit/Tests/SliceCoreTests/MCPContentItemTests.swift`, `docs/Module/SliceCore.md`, `docs/Task-detail/2026-05-06-phase-1-m1-task-1-mcp-json-contract.md`
- **Drift.** in-scope-only.
- **Status.** continue

### Round 2 - 2026-05-06T16:10:22Z

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| — | — | No findings | — | — | Claude returned explicit approve signal with `findings: []`. |

- **Root-cause groups.** None.
- **Fix applied.** None.
- **Tests.** Round 2 reviewer accepted prior verification: `swift test --filter SliceCoreTests.MCPContentItemTests` passed 15 tests and `swift test` passed 593 tests after Round 1 fix.
- **Files touched.** None.
- **Drift.** in-scope-only.
- **Status.** exit-approve

## Final Summary

**Termination reason.** Claude returned explicit approve signal in Round 2.
**Total rounds.** 2
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 1
- Rejected: 0
- Deferred: 0
- Partial: 0
**Deferred follow-ups.**
- None.
