# Task 28 · Phase 0 M1 实施计划评审

**任务开始时间**：2026-04-23
**任务状态**：已完成

---

## 任务背景

在 v2 roadmap 已被评审并收敛到 `CONDITIONAL_APPROVE` 后，项目新增了 M1 实施计划文档：

- `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`

该文档不再是方向性 spec，而是可直接驱动实现的执行手册。因此评审标准比 roadmap 更严格，重点不再是“想法是否合理”，而是：

1. 是否忠实落实已冻结的 roadmap
2. 是否把 M1 范围控制在“核心类型 + 配置迁移”内
3. 是否为了保留旧调用方而把兼容层做得过重，反过来污染 v2 模型
4. DoD / 测试 / 验证路径是否真的覆盖了真实运行路径，而不是只在单测里成立

---

## 评审结论

- **最终结论**：`REWORK_REQUIRED`
- **置信度**：`High`
- **总体判断**：计划写得很细，执行性很强，但它正在用“大量 compatibility shim”换取“外部调用方零改动”。这条路线短期省改动，长期会把 v2 的 source-of-truth 再次搅混，已经超过 KISS 边界。

---

## 主要发现

### P1

1. **`SelectionSnapshot` 兼容方案重新把已上移到 `ExecutionSeed` 的字段塞回核心模型**
   - **影响**：破坏 v2 的两阶段上下文分层，让 `SelectionSnapshot` 同时承载“文字快照”和“前台 app / URL / 屏幕点 / 时间戳”两套语义；更糟的是计划还让这些旧字段参与 Codable 输出，会把 v2 JSON 再次污染成“半新半旧”。
   - **证据**：
     - 计划明确承认这些字段已上移：`SelectionSnapshot` 注释写明 `appBundleID` / `appName` / `url` / `screenPoint` / `timestamp` 已上移到 `ExecutionSeed`，见 plan Task 4 说明
     - 随后又在同一任务里重新加回 `_legacyAppBundleID` / `_legacyURL` / `_legacyScreenPoint` / `_legacyTimestamp`，并在 `encode(to:)` 里条件写出这些旧字段
   - **Fix**：
     - 不要在 M1 重命名并兼容性改造 `SelectionPayload`
     - 更稳妥的做法是：**保留现有 `SelectionPayload` 不动**，新增真正的 `SelectionSnapshot` 与 `ExecutionSeed`
     - 等 M3 切换调用链时，再删旧 `SelectionPayload`
     - 如果坚持 M1 重命名，也必须保证旧字段只存在于内存适配层，不得写回 v2 schema

2. **`Tool` 的 v1 读写桥对非 `.prompt` 形态存在静默语义破坏**
   - **影响**：计划为了让 `ToolEditorView` 零改动，给 `Tool` 加了大量 computed property 兼容桥。但这些桥在 `.agent` / `.pipeline` 下要么返回空字符串、要么 no-op、要么把 `.capability` / `.cascade` provider 直接降级成 `.fixed`。这会导致未来一旦有非 `.prompt` tool 被旧 UI 读写，配置会被静默篡改或用户修改被无声吞掉。
   - **证据**：
     - `systemPrompt` / `userPrompt` setter 对非 `.prompt` 直接 no-op
     - `providerId` setter 会把 `.capability` / `.cascade` 强制改写成 `.fixed`
     - `pipeline` 形态下读取 `userPrompt` 返回空字符串
   - **Fix**：
     - 不要让旧平坦字段对所有 `ToolKind` 都“假装可编辑”
     - M1 更合理的策略是：
       - v1 兼容桥**只支持 `.prompt`**
       - 对 `.agent` / `.pipeline` 在 DEBUG 下断言、在生产下拒绝编辑并给出明确错误
       - 同时在 SettingsUI / ViewModel 层显式限制 M1 只编辑 `.prompt` 工具

### P2

1. **M1 对 `ConfigurationStore` / migrator 的验收口径与真实默认运行路径脱节**
   - **影响**：计划一方面写“`FileConfigurationStore` 默认改读 v2 路径，启动时 migration”，另一方面又保留 `standardFileURL()` 返回 v1，让未修改的 `AppContainer` 在 M1 继续走旧路径。这意味着真实 app 默认路径在 M1 并不会触发 v1→v2 迁移，而 DoD 又写“作者本人的 `config.json` 被 migrator 生成 `config-v2.json`”，容易形成“单测闭环 ≠ 运行闭环”的假完成。
   - **Fix**：
     - 把 M1 DoD 改写成更准确的表述：
       - “迁移器与 v2 path 行为已由单测和手动注入 store 验证”
       - 不要暗示未改 `AppContainer` 的默认 app 路径已经自动完成迁移
     - 或者如果真的要求“app 启动时作者 config 自动迁移”，那就必须把 `AppContainer` / `standardFileURL()` 切到 v2，这已超出 M1 边界

2. **计划内部仍保留多处“实现时再决定”的分支，冻结度不够**
   - **影响**：例如 Task 4 / Task 7 存在明显的“如果 build 失败就再加 shim”“如果 SliceError 不支持 Codable 就改成不 Codable”的分支。这说明实现方案还没有完全收敛，执行者会在编码时继续做设计决策，违背了 plan 作为执行手册的职责。
   - **Fix**：
     - 在进入实施前，把这些分支全部收敛成唯一方案
     - 不能在 plan 里留下“写着写着看编译器报错再决定”的策略

---

## 与已冻结 roadmap 的偏差

### 已对齐的部分

- M1 / M2 / M3 的阶段拆分与 roadmap 基本一致
- `Provenance` / `ContextProvider.inferredPermissions` / `SideEffect.inferredPermissions` 已进入 plan
- `config-v2.json` 独立路径与 `LegacyConfigV1` → `ConfigMigratorV1ToV2` 方向是对的

### 未对齐的部分

- roadmap 把 `SelectionSnapshot` 明确收缩为“选中了什么文字”，计划却为了兼容把旧 `SelectionPayload` 字段塞回来了
- roadmap 只要求 M1 落“类型 + 迁移”，计划却试图让旧 UI 直接在同一个 `Tool` 结构上兼容未来全部 `ToolKind`

---

## 建议的修订方向

1. **收缩 `SelectionSnapshot` 方案**
   - M1 保留旧 `SelectionPayload` 不动
   - 新增 `SelectionSnapshot` 与 `ExecutionSeed`
   - 把真正的调用链切换留给 M3

2. **收缩 `Tool` 兼容桥**
   - 只保障 `.prompt` 工具兼容现有 `ToolEditorView`
   - 非 `.prompt` 工具在 M1 不允许通过旧 UI 编辑

3. **修正 M1 DoD 与验证措辞**
   - 区分“单测/注入路径已验证”与“真实默认运行路径已切换”
   - 不要把 M3 的运行态效果提前写进 M1 完成条件

---

## 本次文档变动

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `docs/Task_history.md` | 修改 | 新增 Task 28 索引 |
| `docs/Task-detail/phase-0-m1-plan-review-2026-04-24.md` | 新建 | 记录本次 M1 plan 评审结论 |

---

## 测试与验证

本次任务为文档评审任务，未执行 `swift build` / `swift test`。验证方式为：

1. 阅读 plan 全文
2. 对照已冻结的 v2 roadmap
3. 对照当前 `SliceCore` / `SettingsUI` / `ConfigurationStore` 实现，判断兼容方案是否会引入额外技术债

---

## 后续动作建议

1. 先不要按当前 plan 直接开工
2. 先收敛 `SelectionSnapshot` 与 `Tool` 的 compatibility strategy
3. 收敛后再进入 M1 实施
