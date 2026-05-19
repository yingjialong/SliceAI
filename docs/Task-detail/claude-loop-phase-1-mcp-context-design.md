---
slug: phase-1-mcp-context-design
created: 2026-05-06T20:26:04+0800
last_updated: 2026-05-06T20:54:06+0800
status: complete
total_rounds: 3
max_iterations: 5
reviewer_model: opus
---

# Claude Review Loop - Phase 1 MCP Context Design

## Goal Contract

**Task.** Review `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md` before implementation planning. The review should catch material design risks, internal inconsistencies, missing Phase 1 acceptance criteria, or divergence from the v2 roadmap/security model before `superpowers:writing-plans` produces the implementation plan.

**Reference Documents.**
- Project background and current status: `README.md`
- Current task record: `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
- Phase dashboard and SOP: `docs/v2-refactor-master-todolist.md`
- Upstream v2 roadmap and Phase 1 DoD: `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`
- Review target: `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Relevant current code boundary: `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
- Relevant current code boundary: `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- Relevant current code boundary: `SliceAIKit/Sources/Orchestration/Context/ContextCollector.swift`
- Relevant current code boundary: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift`
- Relevant current code boundary: `SliceAIApp/AppContainer.swift`

**In-scope.**
- `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Findings that require tiny consistency edits to the task/dashboard docs already changed in the same branch:
  - `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
  - `docs/v2-refactor-master-todolist.md`

**Out-of-scope.**
- No production code implementation.
- No Phase 1 implementation plan drafting in this loop.
- No broad rewrite of the v2 roadmap unless the target spec contradicts a frozen security or Phase 1 DoD constraint.
- No expansion into Phase 2+ Skill, Pipeline, Marketplace, Memory, or full release engineering details beyond what Phase 1 depends on.
- No changes to API/data model names unless required to fix a concrete inconsistency in the design spec.

**Definition of Done.**
1. Claude returns the explicit approve signal: `verdict: "approve"` and `findings: []`, OR remaining findings are low and rejected/deferred with stable reasons.
2. Relevant document validation passes (`git diff --check` at minimum).
3. No accepted critical/high finding remains unfixed.

**Max iterations.** 5 (upper bound; exit early on approve)

**Review scope.** `branch --base origin/main`, with primary review attention limited to `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`.

## Focus Prompt For Current Round

<goal_contract>
Task: Review `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md` before implementation planning. The review should catch material design risks, internal inconsistencies, missing Phase 1 acceptance criteria, or divergence from the v2 roadmap/security model before `superpowers:writing-plans` produces the implementation plan.
In-scope:
- `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Tiny consistency edits to `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md` or `docs/v2-refactor-master-todolist.md` only if the target spec fix requires them.
Out-of-scope:
- Production code implementation.
- Phase 1 implementation plan drafting.
- Broad rewrite of the v2 roadmap unless the target spec contradicts a frozen security or Phase 1 DoD constraint.
- Phase 2+ Skill, Pipeline, Marketplace, Memory, or full release engineering details beyond Phase 1 dependencies.
Definition of Done:
1. Claude returns the explicit approve signal (`verdict: "approve"` and `findings: []`) OR all remaining findings are low and rejected/deferred with stable reasons.
2. Relevant document validation passes.
3. No accepted critical/high finding remains unfixed.
Max iterations: 5 (upper bound, not a required number of rounds)
</goal_contract>

<reference_documents>
- Project background and current status: `README.md`
- Current task record: `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
- Phase dashboard and SOP: `docs/v2-refactor-master-todolist.md`
- Upstream v2 roadmap and Phase 1 DoD: `docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`
- Review target: `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- Relevant current code boundary: `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
- Relevant current code boundary: `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- Relevant current code boundary: `SliceAIKit/Sources/Orchestration/Context/ContextCollector.swift`
- Relevant current code boundary: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift`
- Relevant current code boundary: `SliceAIApp/AppContainer.swift`
</reference_documents>

<prior_round_decisions>
Round 1:
- F1.1 (high, target spec §4.4): accepted and fixed. MCP tool call now explicitly requires every-time confirmation, never writes `PermissionGrantStore`, and any repeat-call relief is UI-only read statistics that cannot affect `PermissionBroker`.
- F1.2 (medium, target spec §4.3): accepted and fixed. The spec now defines `MCPTransport` treatment: M1 only permits `.stdio`, M4 adds `.streamableHTTP`, `.sse` becomes legacy HTTP+SSE compatibility, `.websocket` remains decode-compatible but not newly created.
- F1.3 (medium, target spec §4.2): accepted and fixed. The spec now places JSON value/content item canonical types in `SliceCore`, requires Phase 1 migration of MCPClient/SideEffect contracts, and defines recursive string-leaf template rendering while preserving JSON shape.
- F1.4 (medium, target spec §4.5/§6/§8): accepted and fixed. The spec now requires Phase 1 ContextProviders and mcpAllowlist to feed `PermissionGraph.compute(tool:)`, with tests for undeclared permissions and no bypass from AgentExecutor.
Round 2:
- F2.1 (medium, target spec §4.5/§8): partial and fixed. The spec now defines D-24 as case-aware coverage rather than raw Set equality: file permissions support normalized exact/prefix/glob coverage, MCP declared `tools=nil` or tool superset covers concrete inferred tools, and scalar permissions remain exact. The recommendation to treat `shellExec(commands: [])` as wildcard was rejected because shell remains high-risk and out of Phase 1.
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
Round: 3
Loop max iterations: 5 (upper bound only)
Cumulative files changed in loop so far: 2
</round_meta>

## Rounds

### Round 1 - 2026-05-06T20:32:30+0800

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 1 high / 3 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F1.1 | high | MCP grant 缓存语义内部矛盾且与现有 PermissionBroker / GrantStore 实现冲突 | `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md:72` | accept | Root cause: spec 把 MCP tool call "每次确认" 和 grant 复用混在一起，和 D-22 / 当前 `.mcp -> networkWrite -> cacheable=false` 冲突。Fix: 明确 MCP tool call 永不写入 grant store；如需重复提示，只能做只读统计，不影响 broker 决策。 |
| F1.2 | medium | 远程传输改名未交代现有 canonical `MCPTransport` 枚举如何处置 | `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md:64` | accept | Root cause: spec 修正了协议口径，但没有绑定现有 SliceCore enum 的迁移策略。Fix: 明确 M1 不动 enum，M4 新增 `.streamableHTTP`、把 `.sse` 限定为旧 HTTP+SSE 兼容路径、废弃 `.websocket`，并说明 Claude Desktop import 默认推断 stdio。 |
| F1.3 | medium | 结构化 JSON 类型未锚定到现有 SideEffect/PipelineStep/MCPClientProtocol 的破坏性影响 | `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md:53` | accept | Root cause: JSON value/content item 被描述成 MCPClient 层问题，但实际是 SliceCore/Capabilities/Orchestration 共用契约。Fix: 明确 JSON value/content item 放在 SliceCore；Phase 1 至少迁移 MCPClientProtocol、MCPCallResult、SideEffect.callMCP，PipelineStep 只更新类型契约但不实现 PipelineExecutor。 |
| F1.4 | medium | 未把 PermissionGraph 静态校验绑定到真实 ContextProvider 与 mcpAllowlist | `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md:172` | accept | Root cause: spec 只强调 PermissionBroker UI gate，遗漏 D-24 静态闭环在 Phase 1 真实 provider 上的要求。Fix: 增补 PermissionGraph 约束、错误处理和测试策略，要求 5 个 ContextProvider 实现 inferredPermissions 且 AgentExecutor 不绕过 ExecutionEngine 静态校验。 |

- **Root-cause groups.** One root cause: Phase 1 design spec still leaves several frozen security/data-contract decisions implicit, which would push design decisions into the implementation plan.
- **Fix applied.** Updated the design spec to make MCP tool calls non-cacheable, define `MCPTransport` migration, place MCP JSON/content item types in `SliceCore`, require PermissionGraph static closure for Phase 1 ContextProviders/mcpAllowlist, and align the context data flow wording with `ExecutionEngine -> ContextCollector -> AgentExecutor`.
- **Tests.** `git diff --check` passed.
- **Files touched.** `docs/Task-detail/claude-loop-phase-1-mcp-context-design.md`, `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- **Drift.** in-scope-only
- **Status.** continue

### Round 2 - 2026-05-06T20:45:25+0800

- **Claude verdict.** needs_attention
- **Severity counts.** 0 critical / 0 high / 1 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| F2.1 | medium | D-24 ⊆ 校验对路径 / tools 列表用字面 hash 相等，与 v2 数据模型允许的通配 / 宽声明语义不一致 | `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md:98` | partial | Root cause valid: Phase 1 spec must define permission coverage semantics instead of relying on Set hash equality. Fix: add `Permission.covers(_:)`-style semantics for file path normalization/globs and MCP `tools=nil` / superset coverage; add positive and negative tests. Reject overreach: do not treat `shellExec(commands: [])` as wildcard because exec remains high-risk and should stay exact unless a future spec explicitly changes it. |

- **Root-cause groups.** One root cause: D-24 uses set notation, but Phase 1 needs case-aware permission coverage semantics for permissions whose associated values are ranges or sets.
- **Fix applied.** Updated the design spec to define `effectivePermissions ⊆ tool.permissions` as case-aware permission coverage, including normalized file path exact/prefix/glob matching, MCP `tools=nil`/superset matching, exact shell command matching, and positive/negative validation requirements.
- **Tests.** `git diff --check` passed.
- **Files touched.** `docs/Task-detail/claude-loop-phase-1-mcp-context-design.md`, `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`
- **Drift.** in-scope-only
- **Status.** continue

### Round 3 - 2026-05-06T20:54:06+0800

- **Claude verdict.** approve
- **Severity counts.** 0 critical / 0 high / 0 medium / 0 low
- **Decision ledger.**

| # | Severity | Title | File:line | Decision | Reason / fix plan |
|---|---|---|---|---|---|
| — | — | No findings | — | — | Claude returned explicit approve signal with `findings: []`. |

- **Root-cause groups.** None.
- **Fix applied.** None.
- **Tests.** `git diff --check` passed after prior fixes.
- **Files touched.** `docs/Task-detail/claude-loop-phase-1-mcp-context-design.md`, `docs/superpowers/specs/2026-05-06-phase-1-mcp-context-design.md`, `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`, `docs/Task_history.md`, `docs/v2-refactor-master-todolist.md`
- **Drift.** in-scope-only
- **Status.** exit-approve

## Final Summary

**Termination reason.** Claude returned explicit approve signal in Round 3.
**Total rounds.** 3
**Final verdict.** approve
**Net findings.**
- Accepted and fixed: 4
- Rejected: 0
- Deferred: 0
- Partial: 1
**Deferred follow-ups.**
- None.
