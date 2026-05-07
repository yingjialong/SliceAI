---
slug: m1-task-3-mcp-server-store-claude-desktop-import
created: 2026-05-07T09:50:00+08:00
last_updated: 2026-05-07T12:05:00+08:00
status: complete
total_rounds: 4
max_iterations: 5
reviewer_model: opus
review_scope: branch
review_base: HEAD^
review_head: HEAD
---

# Claude Review Loop - M1 Task 3 MCP Server Store And Claude Desktop Import

<goal_contract>
Task: Review M1 Task 3, which adds the local MCP server configuration store, fail-closed validation, Claude Desktop stdio import, tests, and documentation. The purpose is to catch material correctness/security regressions before moving to M1 Task 4 stdio JSON-RPC client.

In-scope:
- README.md
- SliceAIKit/Sources/Capabilities/MCP/MCPServerStore.swift
- SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift
- SliceAIKit/Sources/Capabilities/MCP/ClaudeDesktopMCPImporter.swift
- SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift
- SliceAIKit/Tests/CapabilitiesTests/ClaudeDesktopMCPImporterTests.swift
- docs/Module/Capabilities.md
- docs/Task_history.md
- docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md

Out-of-scope:
- Real MCP transport/client implementation.
- JSON-RPC framing, stdio process lifecycle, routing client, or Task 4 behavior.
- Settings UI pages and AppContainer runtime wiring.
- M2+ context providers, permission broker persistence, AgentExecutor, or tool calling.
- Reworking the approved Phase 1 plan/design unless this Task 3 diff contradicts it.
- Broad style/doc rewrites unrelated to Task 3 correctness.

Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass: `swift test --filter CapabilitiesTests.MCPServerStoreTests`, `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`, `swift test --filter CapabilitiesTests`, and `swift test`.
3. No accepted critical/high finding remains unfixed.

Max iterations: 5 (upper bound only; exit early on approve)
</goal_contract>

<reference_documents>
- Project current status: README.md
- Task implementation record: docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md
- Phase 1 design: docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md
- Canonical MCP descriptor: SliceAIKit/Sources/SliceCore/MCPDescriptor.swift
- Task 3 implementation: SliceAIKit/Sources/Capabilities/MCP/MCPServerStore.swift, SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift, SliceAIKit/Sources/Capabilities/MCP/ClaudeDesktopMCPImporter.swift
</reference_documents>

<prior_round_decisions>
None yet.
</prior_round_decisions>

<review_constraints>
- Material findings only.
- Keep the review inside in-scope. Out-of-scope items must be `[ADVISORY]`.
- Challenge rejected findings only with new evidence.
- Prefer root-cause findings over symptom lists.
- Preserve KISS; do not expand this review into Task 4 transport/client work.
- Pay special attention to fail-closed validation, schema/version handling, duplicate ids, command path privacy, runner confirmation, and importer/store boundary.
- Reject low-value filler, but list all same-severity material findings before returning. Do not stop after the first critical/high issue when another material issue of that same severity is in scope.
- If no material findings remain, emit the approve signal: `verdict: "approve"` with `findings: []`.
</review_constraints>

<round_meta>
Round: 1
Loop max iterations: 5 (upper bound only)
Cumulative files changed in loop so far: 0
Review command scope: branch --base HEAD^
</round_meta>

## Goal Contract

**Task.** Review M1 Task 3: local MCP server store, Claude Desktop stdio import, validation, tests, and docs.

**Reference Documents.**
- Project current status: `README.md`
- Task implementation record: `docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md`
- Phase 1 design: `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Canonical MCP descriptor: `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`

**In-scope.**
- `README.md`
- `SliceAIKit/Sources/Capabilities/MCP/MCPServerStore.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift`
- `SliceAIKit/Sources/Capabilities/MCP/ClaudeDesktopMCPImporter.swift`
- `SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift`
- `SliceAIKit/Tests/CapabilitiesTests/ClaudeDesktopMCPImporterTests.swift`
- `docs/Module/Capabilities.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md`

**Out-of-scope.**
- Real MCP transport/client implementation.
- JSON-RPC framing, stdio process lifecycle, routing client, or Task 4 behavior.
- Settings UI pages and AppContainer runtime wiring.
- M2+ context providers, permission broker persistence, AgentExecutor, or tool calling.
- Reworking the approved Phase 1 plan/design unless this Task 3 diff contradicts it.
- Broad style/doc rewrites unrelated to Task 3 correctness.

**Definition of Done.**
1. Claude returns the explicit approve signal: `verdict: "approve"` and `findings: []`, OR remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass.
3. No accepted critical/high finding remains unfixed.

**Max iterations.** 5 (upper bound; exit early on approve)

## Rounds

### Round 1 - 2026-05-07T09:50:00+08:00

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 1 high / 0 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | high | Absolute-path invocation bypasses runner typed confirmation | `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift:87` | accept | Root cause: runner detection only compared the full command string, so `/usr/local/bin/npx` went through the absolute-path branch and skipped typed confirmation. Fix: add a failing test for absolute runner paths, detect allowlisted runners by basename after path validation, and require confirmation using the runner basename. |

- **Root-cause groups.** Runner typed-confirmation bypass for absolute-path runner invocations.
- **Fix applied.** Added absolute-path runner coverage and updated `MCPServerValidation` to extract basename for allowlisted runner paths before requiring typed confirmation.
- **Tests.** `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_runnerConfirmationRequiredForAbsoluteRunnerPaths` passed after first confirming the same test failed before production fix; `swift test --filter CapabilitiesTests.MCPServerStoreTests`, `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`, `swift test --filter CapabilitiesTests`, `swift test`, and `git diff --check` passed after the fix.
- **Files touched.** `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift`, `SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift`, `README.md`, `docs/Module/Capabilities.md`, `docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md`.
- **Drift.** No scope drift; changes stay inside Task 3 validation/tests/docs.
- **Status.** continue

### Round 2 - 2026-05-07T11:51:00+08:00

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 1 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F2.1 | medium | Versioned runner binary paths bypass typed runner confirmation | `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift:122` | accept | Root cause remains runner identity matching by exact basename. `python3.11` and `Node22` are executable runner variants with the same arbitrary-code risk as `python3` and `node`. Fix: add a failing test for versioned/case-varied absolute runner paths, normalize absolute-path basenames case-insensitively to runner families, and require typed confirmation using the canonical runner command. |

- **Root-cause groups.** Runner typed-confirmation bypass for versioned/case-varied absolute-path runner invocations.
- **Fix applied.** Added versioned Python/Node coverage and normalized absolute runner basenames to canonical runner family names before confirmation lookup.
- **Tests.** `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_runnerConfirmationRequiredForVersionedRunnerPaths` passed after first confirming the same test failed before production fix; `swift test --filter CapabilitiesTests.MCPServerStoreTests`, `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`, `swift test --filter CapabilitiesTests`, `swift test`, and `git diff --check` passed after the fix.
- **Files touched.** `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift`, `SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift`, `README.md`, `docs/Module/Capabilities.md`, `docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md`.
- **Drift.** No scope drift; changes stay inside Task 3 validation/tests/docs.
- **Status.** continue

### Round 3 - 2026-05-07T11:58:00+08:00

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 1 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F3.1 | medium | Wrapper commands can indirectly invoke runners without typed confirmation | `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift:87` | accept | Root cause remains runner identity hidden behind another executable. Parsing shell `-c` payloads or full `/usr/bin/env` semantics would be fragile and broader than M1. Fix: add a failing test for `/usr/bin/env npx` and `/bin/sh -c npx ...`, then reject known wrapper basenames with the existing redacted `.invalidCommandPath` error. |

- **Root-cause groups.** Runner typed-confirmation bypass through wrapper commands.
- **Fix applied.** Added wrapper command rejection for `env`, `sh`, `bash`, `zsh`, `fish`, and `dash`.
- **Tests.** `swift test --filter CapabilitiesTests.MCPServerStoreTests/test_storeRejectsWrapperCommandsThatCanHideRunners` passed after first confirming the same test failed before production fix; `swift test --filter CapabilitiesTests.MCPServerStoreTests`, `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests`, `swift test --filter CapabilitiesTests`, `swift test`, and `git diff --check` passed after the fix.
- **Files touched.** `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift`, `SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift`, `README.md`, `docs/Module/Capabilities.md`, `docs/Task-detail/2026-05-07-phase-1-m1-task-3-mcp-server-store-claude-desktop-import.md`.
- **Drift.** No scope drift; changes stay inside Task 3 validation/tests/docs.
- **Status.** continue

### Round 4 - 2026-05-07T12:04:00+08:00

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.** No findings.
- **Root-cause groups.** None.
- **Fix applied.** None.
- **Tests.** `swift test --filter CapabilitiesTests.MCPServerStoreTests` passed, 9 tests; `swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests` passed, 2 tests; `swift test --filter CapabilitiesTests` passed, 44 tests; `swift test` passed, 607 tests; `git diff --check` passed.
- **Files touched.** None by Claude; runner mutation check reported no mutation.
- **Drift.** No scope drift.
- **Status.** complete

## Final Summary

**Termination reason.** Claude returned explicit approve signal in Round 4: `verdict: "approve"` and `findings: []`.
**Total rounds.** 4
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 3
- Rejected: 0
- Deferred: 0
- Partial: 0
**Deferred follow-ups.**
- None.
