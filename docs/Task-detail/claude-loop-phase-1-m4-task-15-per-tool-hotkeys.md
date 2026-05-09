---
slug: phase-1-m4-task-15-per-tool-hotkeys
created: 2026-05-09T12:57:29Z
last_updated: 2026-05-09T13:15:05Z
status: complete
total_rounds: 2
max_iterations: 5
reviewer_model: opus
review_scope: branch
review_base: HEAD~2
---

# Claude Review Loop - Phase 1 M4 Task 15 Per-Tool Hotkeys

<goal_contract>
Task: Review Task 15 implementation for per-tool global hotkeys. The task adds a centralized
`HotkeyBindings.tools` map, Settings UI editing and validation, runtime registration for command
palette plus tool hotkeys, and direct tool execution by tool id.

In-scope:
- `SliceAIKit/Sources/SliceCore/ConfigurationComponents.swift`
- `SliceAIKit/Sources/HotkeyManager/HotkeyBindingValidator.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Bindings.swift`
- `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/HotkeySettingsPage.swift`
- `SliceAIApp/AppDelegate.swift`
- `SliceAIApp/AppDelegate+Hotkeys.swift`
- Task 15 tests and task documentation changed in commits `1834288` and `b76ae5f`.

Out-of-scope:
- Rewriting Carbon hotkey registration or replacing `HotkeyRegistrar`.
- Designing a new trigger system or changing `TriggerSource`.
- Refactoring unrelated MCP, permission, or Settings UI files only to satisfy existing full-repo
  SwiftLint violations.
- Changing persisted schema version or adding a database migration.

Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all
   remaining findings are low and rejected/deferred with stable reasons.
2. Relevant tests pass.
3. No accepted critical/high finding remains unfixed.

Max iterations: 5 (upper bound; exit early on approve)
</goal_contract>

<reference_documents>
- Project state and recent changes: `README.md`
- Task implementation record: `docs/Task-detail/2026-05-09-phase-1-m4-task-15-per-tool-hotkeys.md`
- Task index: `docs/Task_history.md`
- Prior handoff context: `docs/handoffs/2026-05-08-phase-1-mcp-context.md`
</reference_documents>

<prior_round_decisions>
Round 1:
- F1.1 (medium, `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift:311`):
  accepted and fixed. Root cause: tool deletion removed config data but only used debounced
  `save()`, which does not invoke `onHotkeysChanged`; Carbon registrations could remain occupied
  until another hotkey edit or restart. Fix: detect whether the deleted tool had an effective
  hotkey and call `saveHotkeys()` after removal to persist and trigger hotkey reload.
- F1.2 (low, `SliceAIKit/Sources/SettingsUI/ToolEditorView+Bindings.swift:170`):
  accepted and fixed. Root cause: runtime merged every tool's legacy `Tool.hotkey` fallback, while
  UI validation merged only the current tool or none. Fix: expose a shared
  `HotkeyBindingValidator.effectiveToolHotkeys(bindings:tools:)` helper and use it in runtime,
  Tool editor validation, and Hotkey settings validation.
</prior_round_decisions>

<review_constraints>
- Material findings only.
- Keep the review inside in-scope. Out-of-scope items must be `[ADVISORY]`.
- Challenge rejected findings only with new evidence.
- Prefer root-cause findings over symptom lists.
- Flag KISS violations only when they create concrete risk or scope creep.
- Reject low-value filler, but list all same-severity material findings before returning.
- If no material findings remain, emit the approve signal: `verdict: "approve"` with `findings: []`.
</review_constraints>

<round_meta>
Round: 2
Loop max iterations: 5 (upper bound only)
Cumulative files changed in loop so far: 6
</round_meta>

## Rounds

### Round 1 - 2026-05-09T12:57:29Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 1 medium / 1 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | medium | Deleting a tool leaves its global hotkey registered until next saveHotkeys/restart | `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift:311` | accept | Root cause: delete path changed tools and hotkey config but only triggered debounced `save()`, which does not call `onHotkeysChanged`. Fix: after deleting a tool with an effective hotkey, call `saveHotkeys()` so Carbon registrations reload immediately. |
| F1.2 | low | Settings UI conflict checks ignore other tools' legacy `Tool.hotkey`, while runtime blocks them | `SliceAIKit/Sources/SettingsUI/ToolEditorView+Bindings.swift:170` | accept | Root cause: UI and runtime used different effective hotkey maps. Fix: introduce one shared effective-map helper and feed it to both UI validation and runtime registration. |

- **Root-cause groups.** Hotkey lifecycle consistency: deletion reload and shared effective map.
- **Fix applied.** Commit `b76ae5f fix(app): keep tool hotkey validation in sync`.
- **Tests.** `swift test --filter HotkeyManagerTests` passed, 10 tests; `swift test --filter SettingsUITests` passed, 15 tests; touched source `swiftlint lint --strict` passed; `git diff --check` passed.
- **Files touched.** `HotkeyBindingValidator.swift`, `ToolEditorView.swift`, `ToolEditorView+Bindings.swift`, `ToolsSettingsPage.swift`, `HotkeySettingsPage.swift`, `HotkeyTests.swift`.
- **Drift.** in-scope-only
- **Status.** continue

### Round 2 - 2026-05-09T13:06:43Z

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.** No findings; explicit approve with `findings: []`.
- **Root-cause groups.** None.
- **Fix applied.** None in Round 2.
- **Tests.** No new code changes after Round 2; Round 1 fix tests remained valid.
- **Files touched.** None.
- **Drift.** in-scope-only
- **Status.** exit-approve

## Final Summary

**Termination reason.** Round 2 explicit approve.
**Total rounds.** 2
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 2
- Rejected: 0
- Deferred: 0
- Partial: 0
**Deferred follow-ups.**
- None.
