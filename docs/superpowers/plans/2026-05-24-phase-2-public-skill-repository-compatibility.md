# Phase 2 Public Skill Repository Compatibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Validate SliceAI Skill Registry compatibility against fixed public Anthropic / OpenAI / Codex skill repository snapshots.

**Architecture:** Keep normal SwiftPM tests offline by adding an opt-in XCTest that reads a manifest path from `SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST`. Add a shell script that shallow-fetches fixed public repository commits with sparse checkout, writes the manifest, and runs the smoke test. Fix scanner support for official OpenAI collection layout with bounded one-extra-level scanning under known skill parent directories.

**Tech Stack:** Swift 6.0, XCTest, `Capabilities.LocalSkillRegistry`, Bash, Git sparse checkout.

---

## Files

- Modify: `SliceAIKit/Sources/Capabilities/Skills/SkillDirectoryScanner.swift`
- Modify: `SliceAIKit/Tests/CapabilitiesTests/SkillDirectoryScannerTests.swift`
- Create: `SliceAIKit/Tests/CapabilitiesTests/PublicSkillRepositorySmokeTests.swift`
- Create: `scripts/phase2-public-skill-smoke.sh`
- Modify: `docs/Task-detail/2026-05-24-phase-2-public-skill-repository-compatibility.md`
- Modify: `docs/Task_history.md`
- Modify: `docs/v2-refactor-master-todolist.md`
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`

## Task 1: TDD Scanner Collection Layout

**Files:**
- Modify: `SliceAIKit/Tests/CapabilitiesTests/SkillDirectoryScannerTests.swift`
- Modify: `SliceAIKit/Sources/Capabilities/Skills/SkillDirectoryScanner.swift`

- [x] **Step 1: Add failing scanner test**

Add a test that writes:

```text
skills/.curated/openai-docs/SKILL.md
skills/.system/skill-creator/SKILL.md
```

Expected scanner candidates include `openai-docs` and `skill-creator`.

- [x] **Step 2: Run red test**

Run:

```bash
swift test --package-path SliceAIKit --filter CapabilitiesTests.SkillDirectoryScannerTests/test_scannerFindsKnownCollectionLayoutsUnderSkillsDirectory
```

Expected before implementation: fail because current scanner only checks direct children of `skills/`.

- [x] **Step 3: Implement bounded collection scan**

In `SkillDirectoryScanner`, keep existing direct parent scanning, then scan one additional level below known parent directories. Only include collection directories that are themselves inside source root and only inspect their direct children. Do not add unbounded recursion.

- [x] **Step 4: Run green tests**

Run:

```bash
swift test --package-path SliceAIKit --filter CapabilitiesTests.SkillDirectoryScannerTests
```

Expected: all scanner tests pass.

## Task 2: Add Opt-In Public Repository Smoke XCTest

**Files:**
- Create: `SliceAIKit/Tests/CapabilitiesTests/PublicSkillRepositorySmokeTests.swift`

- [x] **Step 1: Create manifest model and skip behavior**

Create a test file with `PublicSkillSmokeManifest` / `PublicSkillSmokeRepository` `Codable` structs. In the test, read `SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST`; if missing, throw `XCTSkip`.

- [x] **Step 2: Validate expected skills**

The test should:

1. Decode manifest JSON.
2. Build one `SkillSource` per repository root.
3. Use `LocalSkillRegistry`.
4. Assert every expected skill is present and `.enabled`.
5. Call `loadSkillInstructions` for every expected skill and assert instructions are not empty.
6. Assert each loaded `skillFile` path remains inside the repository root from the manifest.

- [x] **Step 3: Run skip path**

Run:

```bash
swift test --package-path SliceAIKit --filter CapabilitiesTests.PublicSkillRepositorySmokeTests
```

Expected without env: test suite passes with the smoke test skipped.

## Task 3: Add Public Repository Smoke Script

**Files:**
- Create: `scripts/phase2-public-skill-smoke.sh`

- [x] **Step 1: Add bash script**

The script should:

1. `set -euo pipefail`.
2. Create a temp directory.
3. Fetch fixed commits:
   - `anthropics/skills` at `690f15cac7f7b4c055c5ab109c79ed9259934081`
   - `openai/skills` at `b0401f07213a66414d84a65cb50c1d226f99485a`
   - `jMerta/codex-skills` at `1be063de2a730d61133e957dfc01a670cce7abd4`
4. Sparse checkout only the selected sample skill directories.
5. Write manifest JSON.
6. Run the opt-in smoke XCTest with `SLICEAI_PUBLIC_SKILL_SMOKE_MANIFEST`.

- [x] **Step 2: Run smoke script**

Run:

```bash
bash scripts/phase2-public-skill-smoke.sh
```

Expected: the script clones the fixed snapshots and the opt-in XCTest passes.

## Task 4: Documentation and Full Gate

**Files:**
- Modify: `README.md`
- Modify: `AGENTS.md`
- Modify: `CLAUDE.md`
- Modify: `docs/Task_history.md`
- Modify: `docs/v2-refactor-master-todolist.md`
- Modify: `docs/Task-detail/2026-05-24-phase-2-public-skill-repository-compatibility.md`

- [x] **Step 1: Update documentation**

Record:

- the three public repositories and fixed commits;
- the scanner collection-layout compatibility fix;
- smoke command and result;
- non-goals that remain pending.

- [x] **Step 2: Run full validation gate**

Run:

```bash
swift test --package-path SliceAIKit
swiftlint lint --strict
git diff --check
```

Expected: all pass.

## Self-Review

- Spec coverage: This plan covers public repository smoke, bounded collection scanning, docs, and full gate.
- Scope check: It does not implement scripts, supporting-file loading, marketplace, remote install, or DisplayMode.
- Placeholder scan: No placeholder tasks remain.
- Type consistency: Uses existing `SkillSource`, `SkillSettings`, `LocalSkillRegistry`, `SkillRegistrySnapshot`, and `SkillInstructionPayload`.

## Execution Result

- Red test confirmed: `test_scannerFindsKnownCollectionLayoutsUnderSkillsDirectory` failed with empty candidates before implementation.
- Scanner fix implemented: `skills/.curated/<skill>/SKILL.md` and `skills/.system/<skill>/SKILL.md` are now scanned as bounded collection layouts.
- Public smoke passed: `bash scripts/phase2-public-skill-smoke.sh` validated 3 repositories and 9 public skills.
- Full validation passed: `swift test --package-path SliceAIKit`（798 tests，1 skipped）、`swiftlint lint --strict`、`git diff --check`。
