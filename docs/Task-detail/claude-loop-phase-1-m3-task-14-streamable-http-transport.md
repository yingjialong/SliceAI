---
slug: phase-1-m3-task-14-streamable-http-transport
created: 2026-05-09T09:23:16+08:00
last_updated: 2026-05-09T09:41:45+08:00
status: complete
total_rounds: 2
max_iterations: 5
reviewer_model: opus
---

# Claude Review Loop - Phase 1 M3 Task 14 Streamable HTTP Transport

<goal_contract>
Task: Review Task 14 implementation for MCP Streamable HTTP transport. The task adds a real
`StreamableHTTPMCPClient`, routes `.streamableHTTP` through `RoutingMCPClient`, wires it in
`AppContainer`, and updates MCP server validation so streamable HTTP descriptors can be saved
without re-enabling deprecated SSE.

In-scope:
- `SliceAIKit/Sources/Capabilities/MCP/StreamableHTTPMCPClient.swift`
- `SliceAIKit/Sources/Capabilities/MCP/RoutingMCPClient.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift`
- `SliceAIApp/AppContainer.swift`
- `SliceAIKit/Tests/CapabilitiesTests/StreamableHTTPMCPClientTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/RoutingMCPClientTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift`
- Task documentation changes for Task 14

Out-of-scope:
- Legacy SSE fallback or `LegacySSEMCPClient`
- MCP draft headers such as `Mcp-Method` / `Mcp-Name`; current implementation targets protocol
  version `2025-06-18`
- Broad SwiftLint cleanup in unrelated historical files
- Settings UI redesign beyond existing validation/store behavior
- Redirect policy hardening unless it is a critical correctness or security bug in the committed scope

Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all
   remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass.
3. No accepted critical/high finding remains unfixed.

Max iterations: 5 (upper bound; exit early on approve)
</goal_contract>

<reference_documents>
- Task details: `docs/Task-detail/2026-05-09-phase-1-m3-task-14-streamable-http-transport.md`
- Phase plan: `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- Project overview: `README.md`
- Project conventions: `CLAUDE.md`
</reference_documents>

<prior_round_decisions>
Round 1:
- F1.1 (high, `StreamableHTTPMCPClient.swift`): accepted and fixed. Root cause: production default
  URLSession followed redirects and could forward MCP session headers / JSON-RPC body outside the
  validated endpoint. Fix: default redirect-blocking URLSession delegate, with internal test factory.
- F1.2 (medium, `StreamableHTTPMCPClient.swift`): accepted and fixed. Root cause: HTTP 404 with an
  existing `Mcp-Session-Id` did not clear cached session state. Fix: detect session-expired 404,
  reset the server session, and retry the high-level operation once.
</prior_round_decisions>

<review_constraints>
- Material findings only.
- Keep the review inside in-scope. Out-of-scope items must be `[ADVISORY]`.
- Challenge rejected findings only with new evidence.
- Prefer root-cause findings over symptom lists.
- Flag KISS violations only when they create concrete risk or scope creep.
- Reject low-value filler, but list all same-severity material findings before returning.
- Do not stop after the first critical/high issue when another material issue of that same severity is in scope.
- If no material findings remain, emit the approve signal: `verdict: "approve"` with `findings: []`.
</review_constraints>

<round_meta>
Round: 2
Loop max iterations: 5; upper bound only.
Cumulative files changed in loop so far: 3
Review scope: branch diff `HEAD~2..HEAD`
</round_meta>

## Goal Contract

**Task.** Review Task 14 implementation for MCP Streamable HTTP transport, ensuring the new
transport is correct, secure within the planned boundary, and integrated without reviving
deprecated SSE behavior.

**Reference Documents.**
- Task details: `docs/Task-detail/2026-05-09-phase-1-m3-task-14-streamable-http-transport.md`
- Phase plan: `docs/superpowers/plans/2026-05-06-phase-1-mcp-context.md`
- Project overview: `README.md`
- Project conventions: `CLAUDE.md`

**In-scope.**
- Task 14 MCP transport, routing, validation, AppContainer wiring, tests, and documentation.

**Out-of-scope.**
- Legacy SSE fallback, draft MCP headers, broad unrelated lint cleanup, Settings UI redesign,
  and non-critical future hardening outside this transport implementation.

**Definition of Done.**
1. Claude returns the explicit approve signal: `verdict: "approve"` and `findings: []`, OR
   remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass.
3. No accepted critical/high finding remains unfixed.

**Max iterations.** 5 (upper bound; exit early on approve)

## Rounds

### Round 1 - 2026-05-09T09:33:24+08:00

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 1 high / 1 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | high | URLSession 默认跟随 redirect 绕过 HTTPS / 本机 host 校验，泄露 Mcp-Session-Id | `StreamableHTTPMCPClient.swift:17` | accept | Root cause: production default `URLSession.shared` follows redirect and can forward MCP session headers / JSON-RPC body outside the validated endpoint. Fix: replace production default with a redirect-blocking URLSession delegate; keep injected session initializer internal for tests. |
| F1.2 | medium | HTTP 404 + Mcp-Session-Id 未触发会话重建，server 重启后 client 永久失败 | `StreamableHTTPMCPClient.swift:249` | accept | Root cause: non-2xx handling collapsed 404 into generic transport failure without clearing cached session state. Fix: detect 404 when `state.sessionID != nil`, reset that server session, retry the high-level operation once, and otherwise surface transport failure. |

- **Root-cause groups.** Streamable HTTP session lifecycle hardening: redirect policy and expired-session recovery.
- **Fix applied.** Added redirect-blocking default session, internal test factory, session-expired internal control flow, reset/retry wrapper, and two regression tests.
- **Tests.**
  - `cd SliceAIKit && swift test --filter CapabilitiesTests.StreamableHTTPMCPClientTests`：通过，8 tests。
  - `cd SliceAIKit && swift test --filter CapabilitiesTests`：通过，92 tests。
  - `cd SliceAIKit && swift test`：第一次出现一次既有 cancellation 时序测试间歇失败；单测复跑通过；第二次全量通过，728 tests。
  - targeted `swiftlint lint --strict`：通过，0 violations。
  - `git diff --check`：通过。
  - `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`：通过。
- **Files touched.**
  - `SliceAIKit/Sources/Capabilities/MCP/StreamableHTTPMCPClient.swift`
  - `SliceAIKit/Tests/CapabilitiesTests/StreamableHTTPMCPClientTests.swift`
  - docs/README/task history updates
- **Drift.** in-scope-only
- **Status.** continue

### Round 2 - 2026-05-09T09:41:45+08:00

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| - | - | No findings | - | approve | Round 2 confirmed Round 1 findings are fixed and no new material issues remain. |

- **Root-cause groups.** None.
- **Fix applied.** None in Round 2.
- **Tests.** Reused post-fix verification from Round 1 fix: focused transport tests, CapabilitiesTests, full SwiftPM, targeted lint, `git diff --check`, and App Debug build passed.
- **Files touched.** Loop log and task documentation only.
- **Drift.** in-scope-only
- **Status.** exit-approve

## Final Summary

**Termination reason.** Claude returned explicit approve signal.
**Total rounds.** 2
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 2
- Rejected: 0
- Deferred: 0
- Partial: 0
**Deferred follow-ups.**
- None.
