# Orchestration

执行层（M2 填实）。职责：ExecutionEngine、ContextCollector、PermissionBroker、CostAccounting、AuditLog、OutputDispatcher、PromptExecutor、PermissionGraph。

## Phase 0 M1 状态
仅建空 target + 占位 Swift 文件，让 `swift build` 可成功。所有实现将在 M2 (`docs/superpowers/plans/*-phase-0-m2-*.md`) 加入。

依赖：`SliceCore` / `Capabilities`（后者暂未依赖，M2 再加）。
