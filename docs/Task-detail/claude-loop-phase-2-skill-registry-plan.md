---
slug: phase-2-skill-registry-plan
created: 2026-05-21T06:42:08Z
last_updated: 2026-05-21T07:17:39Z
status: complete
total_rounds: 3
max_iterations: 5
reviewer_model: opus
---

# Claude Review Loop - Phase 2 Skill Registry MVP Plan

<goal_contract>
Task: Review and harden the Phase 2 Skill Registry MVP implementation plan before implementation. The plan must be executable by Codex without hidden design gaps, compile-time dead ends, or divergence from the approved MVP spec.

In-scope:
- `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`
- Direct consistency with `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`
- Existing code references needed to judge whether the plan is executable

Out-of-scope:
- Implementing Phase 2 production code or tests.
- Redesigning the MVP beyond the frozen Skill Registry scope.
- Release draft, tags, CI artifacts, and unrelated Phase 0/1 documentation.
- Broad rewrites of README, roadmap, or task history except where the plan itself requires a precise reference.

Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all remaining findings are low and rejected/deferred with stable reasons.
2. The plan remains KISS-oriented, bounded to the MVP, and clear enough for implementation without guesswork on critical runtime, security, or test wiring details.
3. No accepted critical/high finding remains unfixed.

Max iterations: 5 (upper bound; exit early on approve)
</goal_contract>

<reference_documents>
- Spec / motivation: `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`
- Implementation plan under review: `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`
- Existing core model: `SliceAIKit/Sources/SliceCore/Skill.swift`
- Existing agent tool model: `SliceAIKit/Sources/SliceCore/ToolKind.swift`
- Existing agent executor tool catalog/calls: `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCatalog.swift`, `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`
- Existing tool-call request encoding: `SliceAIKit/Sources/SliceCore/ChatTypes.swift`
</reference_documents>

<prior_round_decisions>
Round 1:
- F1.1 (high, plan Task 1): accepted and fixed. Root cause: the plan changed `SliceCore.Skill` / `SkillManifest` and `AgentTool.skill` public shape without telling implementers to rewrite existing locked tests and compile callsites.
- F1.2 (high, plan Task 3): accepted and fixed. Root cause: the plan removed the old `Capabilities.Skill` model but did not explicitly delete stale `SkillRegistryProtocolTests` / `allSkills()` coverage.
- F1.3 (high, plan Task 4): accepted and fixed. Root cause: pseudo-tool dispatch was placed before `.toolCallProposed`, breaking ResultPanel lifecycle.
- F1.4 (medium, plan Task 2): accepted and fixed. Root cause: scanner instructions did not resolve symlinks and enforce source-root containment.
- F1.5 (medium, plan Tasks 2/3): accepted and fixed. Root cause: missing `description` was parsed as empty without warning/state handling.
- F1.6 (low, plan Task 1): accepted and fixed. Root cause: config compatibility JSON used stale `TriggerSettings` keys.
- F1.7 (low, plan Task 3): accepted and fixed. Root cause: the 128 KiB constant had no read-time enforcement path.
Round 2:
- F2.1 (medium, plan Task 4): accepted and fixed. Root cause: Task 4 promised duplicate-loading and metadata-budget coverage but only listed two tests; added tests for hidden pseudo-tool when unbound, duplicate-load de-dupe, and 8,000-character metadata truncation contract.
</prior_round_decisions>

<review_constraints>
- Material findings only.
- Keep the review inside in-scope. Out-of-scope items must be `[ADVISORY]`.
- Challenge rejected findings only with new evidence.
- Prefer root-cause findings over symptom lists.
- Flag KISS violations only when they create concrete risk or scope creep.
- Require complete material coverage at the current highest severity; do not stop after the first critical/high issue if another same-severity material issue is in scope.
- Treat `max_iterations` as an upper bound, not a required number of rounds.
- If no material findings remain, emit the approve signal: `verdict: "approve"` with `findings: []`.
</review_constraints>

<round_meta>
Round: complete
Loop max iterations: 5 (upper bound only)
Cumulative files changed in loop so far: 3
Review scope for final round was `working-tree`; Claude read the full current plan/spec files and returned approve.
</round_meta>

## Goal Contract

**Task.** Review and harden the Phase 2 Skill Registry MVP implementation plan before implementation. The plan must be executable by Codex without hidden design gaps, compile-time dead ends, or divergence from the approved MVP spec.

**Reference Documents.**
- Spec / motivation: `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`
- Implementation plan under review: `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`

**In-scope.**
- `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`
- Direct consistency with `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`
- Existing code references needed to judge whether the plan is executable

**Out-of-scope.**
- Implementing Phase 2 production code or tests.
- Redesigning the MVP beyond the frozen Skill Registry scope.
- Release draft, tags, CI artifacts, and unrelated Phase 0/1 documentation.
- Broad rewrites of README, roadmap, or task history except where the plan itself requires a precise reference.

**Definition of Done.**
1. Claude returns the explicit approve signal: `verdict: "approve"` and `findings: []`, OR remaining findings are low and rejected/deferred with stable reasons.
2. The plan remains KISS-oriented, bounded to the MVP, and clear enough for implementation without guesswork on critical runtime, security, or test wiring details.
3. No accepted critical/high finding remains unfixed.

**Max iterations.** 5 (upper bound; exit early on approve)

## Rounds

### Round 1 - 2026-05-21T06:57:31Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 3 high / 2 medium / 2 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | high | Task 1 invalidates existing SliceCore Skill tests but plan never says to rewrite/delete them | `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md:159` | accept | Added explicit stale `SkillTests` rewrite list, fixed config JSON, and enumerated `AgentTool(skill:)` callsite migration as part of Task 1. |
| F1.2 | high | Task 3 removes Capabilities.Skill but does not address existing SkillRegistryProtocolTests | `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md:819` | accept | Added explicit deletion of old `Capabilities.Skill`, removal of `allSkills()`, and replacement `SkillRegistryProtocolTests` coverage using `SliceCore.Skill`. |
| F1.3 | high | `sliceai.load_skill` dispatch skips `.toolCallProposed` lifecycle event | `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md:1177` | accept | Moved pseudo-tool branch after proposed + args parse and before MCP allowlist/gate; added synthetic lifecycle ref and test assertion. |
| F1.4 | medium | Scanner has no symlink-escape check | `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md:744` | accept | Added `scan(in:)`, scanner rejections, symlink resolution, component-prefix containment, and regression test. |
| F1.5 | medium | Parser silently accepts empty description | `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md:681` | accept | Added parser warnings, missing-description test, registry `.defaultDisabled` mapping, and diagnostic requirements. |
| F1.6 | low | Config compatibility JSON uses invalid TriggerSettings keys | `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md:262` | accept | Replaced `mouseSelection` fixture with valid `floatingToolbarEnabled` / `commandPaletteEnabled` keys. |
| F1.7 | low | `maxSkillBytes` declared but never enforced | `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md:681` | accept | Added registry read-time `Data` size guard, `.tooLarge` state/diagnostic, and non-loadable oversize test. |

- **Root-cause groups.** Public model migration completeness; pseudo-tool lifecycle and provider naming; scanner/parser security and state semantics.
- **Fix applied.** Updated plan and a targeted spec erratum for provider function name `sliceai_load_skill`.
- **Tests.** Documentation-only changes; no Swift tests run.
- **Files touched.** `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`, `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`, `docs/Task-detail/claude-loop-phase-2-skill-registry-plan.md`
- **Drift.** in-scope-only
- **Status.** continue

### Round 2 - 2026-05-21T07:09:10Z

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 1 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F2.1 | medium | Task 4 only writes 2 of the 7 spec §14.3 OrchestrationTests | `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md:73` | accept | Added tests for no-bound-skills hiding the pseudo-tool/metadata, duplicate `sliceai_load_skill` de-dupe with a counting registry, and 8,000-character metadata truncation preserving name/path. Pinned truncation helper contract. |

- **Root-cause groups.** Task 4 test matrix completeness for subtle runtime invariants.
- **Fix applied.** Expanded Task 4 failing tests and specified metadata budget algorithm.
- **Tests.** Documentation-only changes; no Swift tests run.
- **Files touched.** `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`, `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`, `docs/Task-detail/claude-loop-phase-2-skill-registry-plan.md`
- **Drift.** in-scope-only
- **Status.** continue

### Round 3 - 2026-05-21T07:17:39Z

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| - | - | No findings | - | approve | Claude returned `verdict: "approve"` with `findings: []`. |

- **Root-cause groups.** None.
- **Fix applied.** None.
- **Tests.** Documentation-only changes; no Swift tests run.
- **Files touched.** `docs/superpowers/plans/2026-05-21-phase-2-skill-registry-mvp.md`, `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`, `docs/Task-detail/claude-loop-phase-2-skill-registry-plan.md`
- **Drift.** in-scope-only
- **Status.** exit-approve

## Final Summary

**Termination reason.** Claude approve.
**Total rounds.** 3
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 8
- Rejected: 0
- Deferred: 0
- Partial: 0
**Deferred follow-ups.**
- None.
