# Task 24 · SliceAI v2.0 Roadmap 规范评审

**任务开始时间**：2026-04-23
**任务状态**：已完成

---

## 任务背景

项目在 2026-04-23 新增了 v2.0 roadmap，产品定位从“划词 LLM 工具”重塑为“划词触发型 AI Agent 配置框架”。该 roadmap 涉及：

1. 产品定位、竞品锚点与目标用户整体切换
2. `SliceCore` 数据模型升级、`Orchestration` / `Capabilities` 两个新 target 引入
3. `ToolExecutor` 到 Agent/Pipeline 执行模型的根本性迁移
4. 配置 schema 从 v1 升级到 v2，并在后续 phase 中叠加 MCP / Skill / Marketplace / Prompt IDE / Pipeline

该类文档不是普通功能 spec，而是决定未来几个月研发方向的总设计，因此必须先做一次高强度评审，避免把错误抽象冻结为项目基线。

---

## 评审目标

### Step 1：核对当前项目真实基线

阅读 `README.md`、`docs/Task_history.md`、当前 `SliceAIKit/Package.swift`、`SliceCore/Tool.swift`、`SliceCore/Configuration.swift`、`SliceCore/ToolExecutor.swift`、`SliceAIApp/AppContainer.swift`，确认 roadmap 与当前实现之间的差距是真实存在还是叙事性夸大。

### Step 2：审查 roadmap 自身质量

重点检查：

- 是否真正覆盖产品核心诉求，而不是把“想象力”包装成无边界 scope
- 是否存在架构自相矛盾、抽象过度、阶段切分失真
- 是否补齐迁移、回滚、安全、权限、审计、实施顺序这些高风险工程问题

### Step 3：形成可执行的修正建议

输出决策结论、严重问题列表、建议修订方向，作为后续 Phase 0 plan 的前置输入。

---

## ToDoList

- [x] 阅读 `README.md`，确认项目当前对外叙事
- [x] 阅读 roadmap 全文并做逐段审查
- [x] 对照当前代码结构验证 roadmap 的迁移难度
- [x] 输出审查结论与问题分级
- [x] 更新 `docs/Task_history.md`
- [x] 创建本任务文档

---

## 评审结论

- **最终结论**：`REWORK_REQUIRED`
- **置信度**：`Medium`
- **总体判断**：方向是对的，说明你已经从“AI 写作小工具”转向更有潜力的“选中内容驱动的 Agent 配置工具”；但这份 roadmap 仍然把太多战略愿望、架构洁癖和生态想象压进了一份冻结规范里，缺少足够严格的 Phase 0 边界、迁移/回滚设计和安全闭环。若按原文直接开干，极大概率会在重构期失速。

---

## 主要发现

### P0 / P1 级问题

1. **Phase 0 不是“无感重构”，而是高风险换心手术**
   - roadmap 一边要求“用户视觉无感、无新功能”，一边在 Phase 0 中引入 `ExecutionContext`、`Permission`、`OutputBinding`、`Skill`、`MCPDescriptor`、`ExecutionEngine`、`ContextCollector`、`CostAccounting`、`AuditLog`、`ConfigMigratorV1ToV2` 等一整套新骨架。
   - 这不是单纯重构，而是“执行链路 + 持久化模型 + 依赖装配 + 测试边界”一起换。
   - 建议：把当前 Phase 0 拆为两个子阶段。Phase 0A 只做兼容性数据模型和 façade 包装，不删除 `ToolExecutor`；Phase 0B 再在旧行为完全回归后引入新的编排层。

2. **配置迁移是单向破坏式升级，没有可靠回滚策略**
   - roadmap 明确写了 `schemaVersion: 2` 自动迁移、备份旧文件、且“不做降级”。
   - 这意味着只要用户启动 v2 分支，配置即被提升到新格式，旧分支/旧 tag 立刻失去可逆兼容性。
   - 建议：至少二选一：
     - 双读双写一段时间，旧字段保留到 Phase 1 结束；
     - 或者 v2 beta 使用独立 config 路径，先避免污染主配置。

3. **安全模型不够硬，无法支撑你宣称的“信任第一”**
   - 文档允许未来接入 `shell`、`filesystem`、`mcp`、`AppIntents`、`Marketplace`、`Tool Pack`，但安全控制大多停留在“权限弹窗 + 默认确认”层。
   - 对于“导入陌生 pack / skill / MCP server”这种高风险入口，签名校验、来源标记、path canonicalization、输出脱敏、日志保留周期、危险操作审计都没有成体系定义。
   - 建议：先写威胁模型文档，再决定哪些能力能进 Phase 1，哪些必须推迟到有签名或隔离机制之后。

4. **核心领域模型存在自相矛盾，说明抽象还没收敛**
   - `ExecutionContext` 被定义为构建后只读不可变，但执行流程又让 `ContextCollector` 在运行时“填充” `context.contexts`。
   - `ContextCollector` 声称要按 DAG 调度，但 `ContextRequest` 结构中并没有 `depends` 字段。
   - 建议：先统一模型：
     - 用 `ExecutionSeed -> ResolvedExecutionContext` 两阶段对象；
     - 或者取消 DAG，Phase 1 仅保留平铺并发采集。

5. **路线图 scope 仍然过宽，产品核心会被生态功能稀释**
   - 你的真正机会点是“选中内容 -> 调用自定义能力 -> 回到当前工作流”。
   - 但 roadmap 同时塞进了 Marketplace、SliceAI as MCP server、Services、URL Scheme、Prompt IDE、Memory、TTS、Pipeline 可视化编辑器、Smart Actions 等多条大线。
   - 建议：明确一条主线作为 v2 核心：
     - “划词触发 Prompt/Agent/MCP”；
     - 其余全部降为候选扩展，不要先写进冻结 spec。

### P2 级问题

1. **竞品与“独占格”叙事证据不足**
   - “划词 × MCP 独家”是漂亮口号，但它是时效性很强的市场判断，文档里没有证据链，也没有把 moat 落到真正的用户迁移成本上。
   - 建议：把“独家”改成“当前主打差异化假设”，避免未来被市场事实反打脸。

2. **Provider capability 抽象提前过度**
   - 当前代码只有 OpenAI 兼容 provider，一口气把 Anthropic / Gemini / Ollama / capability routing / cascade 全推入核心模型，属于典型的“先为未来抽象”。
   - 建议：Phase 0 保留 `fixed(providerId, modelId)`；等第二种真实 provider 落地后再升维。

3. **成功指标带有明显愿望化叙事**
   - `DAU 5000`、`GitHub Stars 5k+`、`HN 首页`、`PH Top 5` 更像传播目标，不是实施阶段可验证的工程指标。
   - 建议：替换成能在单人开源项目里真正采集和校验的指标，例如：
     - 首个自定义 Tool 从创建到跑通的中位时长
     - 安装 MCP 后首次成功调用率
     - 选中触发到首 token 的分位响应时间

4. **文档体系已开始漂移**
   - `Task_history.md` 已把 v2 roadmap 记为“冻结规划”，但根目录 `README.md` 仍把项目定义为“macOS 开源划词触发 LLM 工具栏”，且状态写的是 `v0.1 开发中`。
   - 建议：只有当你真正接受本次评审后的修订版本时，再同步更新 `README.md`，否则仓库会同时存在两套互相冲突的对外叙事。

---

## 与当前代码基线的差距评估

### 当前基线

- `SliceAIKit/Package.swift` 当前只有 8 个 library target，还没有 `Orchestration` / `Capabilities`
- `SliceCore/Tool.swift` 仍是单次 prompt 调用模型
- `SliceCore/Configuration.swift` 当前 `schemaVersion` 还是 `1`
- `SliceCore/ToolExecutor.swift` 仍是“读取配置 -> 渲染 prompt -> 调用 provider”的单执行器架构
- `SliceAIApp/AppContainer.swift` 也是围绕旧执行模型装配

### 结论

这说明 roadmap 并不是“轻量升级”，而是一次结构级迁移。你的文档已经意识到这一点，但 Phase 0 时间与风险预算仍然偏乐观。

---

## 建议的修订方向

1. **把 v2.0 spec 收缩成“一个主张 + 一个核心 execution model + 一个最小可交付 phase”**
   - 主张：划词触发自定义 Prompt / Agent / MCP
   - 核心 execution model：先只支持 PromptTool + 受限 AgentTool，暂不引入 Pipeline
   - 最小可交付：Claude Desktop 风格 `mcp.json` 导入 + 单个受控 Agent demo

2. **重写 Phase 0 边界**
   - 只保留：
     - `Tool` 向后兼容升级
     - `ProviderSelection` 的最小版本
     - `ExecutionEngine` façade
     - config 双读或独立 beta 路径
   - 砍掉：
     - `CostAccounting`
     - `AuditLog`
     - `ContextCollector` DAG
     - `Skill` / `Marketplace` 相关数据结构预埋

3. **在进入实施前补两份文档**
   - `docs/superpowers/specs/2026-04-23-sliceai-v2-security-model.md`
   - `docs/superpowers/plans/2026-04-24-phase-0-refactor.md`

4. **重新定义“冻结”**
   - 现在这份文档不应该叫 Design Freeze。
   - 更准确的状态应是：`Draft reviewed, rework required`。

---

## 本次文档变动

| 文件 | 变更类型 | 说明 |
|------|---------|------|
| `docs/Task_history.md` | 修改 | 新增 Task 24 评审索引 |
| `docs/Task-detail/sliceai-v2-roadmap-review-2026-04-23.md` | 新建 | 记录本次规范评审过程与结论 |

---

## 测试与验证

本次任务为文档评审任务，未执行 `swift build` / `swift test`。验证方式为：

1. 通读 roadmap 全文并逐段交叉审查
2. 对照当前仓库核心代码与包结构验证迁移难度
3. 依据评审结论形成问题分级和修订建议

---

## 后续动作建议

1. 先不要直接开始 Phase 0 编码
2. 先按本评审意见重写 roadmap 的以下部分：
   - Phase 0 范围
   - 迁移/回滚策略
   - 安全模型
   - 成功指标
3. 重写后再产出新的 Phase 0 实施计划文档

---

## 第二轮复审补充（基于 Task 25 修订版）

**复审时间**：2026-04-23
**复审对象**：`docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（Claude 按 Task 24 评审意见修订后的版本）

### 复审结论

- **更新后的结论**：仍为 `REWORK_REQUIRED`，但问题范围已明显收缩
- **变化判断**：
  - 已真实修复：`ExecutionSeed -> ResolvedExecutionContext` 两阶段模型、移除 Context DAG、Phase 0 拆 M1/M2/M3、独立 `config-v2.json` 路径、Phase 0–1 Freeze / Phase 2–5 Directional
  - 仍未过关：安全模型内部规则冲突、MCP 子进程信任边界判断失真、权限声明与上下文真实访问之间缺少强绑定、文档残余漂移

### 第二轮主要发现

1. **P1：Security Model 内部仍然自相矛盾**
   - `§3.9.1` 写 `firstParty` “全部能力默认授权”，但 `§3.9.2` 又规定 `network-write` / `exec` 必须每次确认，`§3.9.6` 还写“所有非 readonly-local 默认未授权”。
   - 这会直接导致 `PermissionBroker` 的判定表无法落地：实现者不知道“来源级别”是否可以覆盖“能力级别”的最低安全下限。
   - 建议：明确一个不可突破的规则层级：
     - 能力分级决定**最低 gate 下限**
     - 来源分级只能在下限之上放宽，例如“安装时一次确认”替代“首次运行确认”
     - `exec` / `network-write` 永远不能因为 `firstParty` 而静默放行

2. **P1：把 stdio MCP 子进程当成“已有隔离”是错误的威胁建模**
   - 文档把 “不需要额外 sandboxing（stdio 子进程本就是进程隔离）” 作为结论，这是技术上不成立的。
   - stdio MCP server 一旦启动，就是用户身份下的本地任意代码执行；`PermissionBroker`、`PathSandbox`、`Tool allowlist` 只能约束 **通过 SliceAI 协议暴露的调用面**，不能约束 server 进程自己的系统访问。
   - 建议：在 spec 里明确写死：
     - “启动未知 stdio MCP server = 用户授权本地代码执行”
     - Phase 1 只推荐 first-party / 本地自管 server
     - unknown 来源的 stdio MCP 不应被描述为“可通过运行时 gate 安全兜住”

3. **P1：权限模型还没有和 ContextRequest 的真实访问强绑定**
   - 当前文档里 `ContextProvider` 有 `requiredPermissions`，但执行流只在开头做 `PermissionBroker.check(tool.permissions, ...)`，随后 `ContextCollector.resolve(seed:requests:)` 就会真正访问外部资源。
   - 这意味着如果 `tool.permissions` 漏填了某个 `file.read` / `network(host)` / `mcp.call` 请求，而 `PathSandbox` 又允许该路径，系统可能发生“未出现在授权清单中的真实访问”。
   - 建议：补一条硬约束：
     - `ContextRequest` 在进入 `ContextCollector` 前先被解析成 `effectivePermissions`
     - `effectivePermissions` 必须是 `tool.permissions` 的子集，否则执行失败
     - `OutputBinding.sideEffects` 也要做同样的“声明权限 = 实际权限”校验

4. **P2：文档仍有多处残余漂移，说明 consistency pass 没做完**
   - 典型残留：
     - 哲学对应表仍写 `ExecutionContext`
     - 分层图和模块职责表仍写 `ExecutionContext`
     - Agent loop 伪代码参数仍写 `ctx: ExecutionContext`
     - 附录 A 仍写“自动迁移 + v1 备份”，和 `config-v2.json` 独立路径策略不一致
     - 附录 C 仍保留旧的 `0.1 / 0.2 / 0.10 ...` 顺序，而不是 M1/M2/M3
     - 文档头部仍写“规划冻结（Design Freeze）”，但正文明确只有 Phase 0–1 Freeze
   - 建议：在进入 plan.md 前先做一次全文一致性清理，否则后续实施会反复被旧术语误导。

### 第二轮建议后的下一步

1. 先修完 §3.9 的三处问题：来源级别 vs 能力级别、MCP stdio 信任边界、权限声明与真实访问绑定
2. 再做一次全文 consistency pass，清掉旧 `ExecutionContext`、旧 Appendix 和错误冻结状态
3. 以上两步完成后，这份 spec 才适合从 `REWORK_REQUIRED` 升到 `CONDITIONAL_APPROVE`

---

## 最小修订清单草案（把 spec 从 `REWORK_REQUIRED` 推到 `CONDITIONAL_APPROVE`）

下面这份清单刻意**只保留最小必要改动**，不再扩 scope，不引入新模块，也不重写 phase 结构。目标只有一个：让 roadmap 内部自洽、能安全实施。

### A. 安全模型必改项

#### A1. 增加“规则优先级”小节，解决 `Provenance` 与 `Capability Tier` 打架

- **修改位置**：`§3.9.2` 前或后新增一个 3–6 行的小节，例如 `§3.9.2a 判定优先级`
- **必须写清楚的规则**：
  1. `Capability Tier` 决定**最低安全下限**
  2. `Provenance` 只影响确认频率和安装时 friction，**不能突破下限**
  3. `network-write` 与 `exec` 对所有来源都不能静默放行
- **建议写法**：
  - `readonly-local`：`firstParty/communitySigned` 可静默，`unknown` 首次确认
  - `readonly-network` / `local-write`：`firstParty/communitySigned` 首次或会话级确认，`unknown` 每次或每会话确认
  - `network-write` / `exec`：**所有 provenance 一律每次确认**
- **验收标准**：
  - `§3.9.1`、`§3.9.2`、`§3.9.6` 三处不再互相矛盾
  - `M2.3 PermissionBroker` 的测试表可以直接从 spec 抄出来实现

#### A2. 改写 `§3.9.1 Provenance` 的默认策略描述

- **修改位置**：`§3.9.1` 的表格
- **必须删除或改写的表述**：
  - `firstParty` 当前的“全部能力默认授权”
- **建议替换成**：
  - `firstParty`：按 capability floor 执行，安装时可预授权 `readonly-local`
  - `communitySigned`：按 capability floor 执行，可减少重复确认
  - `unknown`：按 capability floor 执行，且确认频率最严格
- **验收标准**：
  - 不再出现“来源等级覆盖危险能力下限”的歧义

#### A3. 重写 `§3.9.4` 对 stdio MCP server 的安全表述

- **修改位置**：`§3.9.4 Pack / Skill / MCP 安装校验`
- **必须新增的明确声明**：
  1. “启动 stdio MCP server = 在当前用户身份下执行本地代码”
  2. “进程隔离 != 权限隔离；PermissionBroker/allowlist 只能约束 SliceAI 暴露给 LLM 的协议面，不能约束 server 进程自身的系统访问”
  3. “unknown 来源 stdio MCP server 默认禁用，首次启用需用户明确确认风险”
- **建议写法**：
  - Phase 1 推荐 only：
    - 作者自管 server
    - 官方示例 server
    - 已签名或已审阅配置
  - 对 `unknown` 来源增加一条高亮警告文案要求
- **验收标准**：
  - 文档中不再出现“stdio 子进程本就是进程隔离，所以无需额外 sandboxing”这类误导性结论

#### A4. 建立“声明权限 = 实际权限”的硬约束

- **修改位置**：至少补到 `§3.3.3`、`§3.4`、`§3.9.2/§3.9.6`
- **必须新增的规则**：
  1. `ContextRequest` 在执行前解析成 `effectivePermissions`
  2. `effectivePermissions` 必须是 `tool.permissions` 的子集，否则执行失败
  3. `OutputBinding.sideEffects` 同样要先解析出权限，再做子集校验
  4. `ContextProvider.requiredPermissions` 只是 provider 能力声明，**不是**自动授权
- **建议写法**：
  - 在 `ExecutionEngine` 流程里加一步：
    - `PermissionPlanner.resolve(tool, requests, sideEffects) -> [Permission]`
    - 若 `resolved ⊄ tool.permissions`，直接 `.failed(.configuration(.undeclaredPermission(...)))`
- **验收标准**：
  - 任何真实 IO/网络/进程访问都能追溯到 `tool.permissions`
  - `M2.2` / `M2.3` / `M2.6` 的测试用例可覆盖“声明缺失 -> 执行失败”

### B. 文档一致性必改项

#### B1. 统一文档头部状态

- **修改位置**：文档头第 5 行状态
- **当前问题**：还写“规划冻结（Design Freeze）”，但正文明确只有 Phase 0–1 Freeze
- **建议改成**：
  - `状态：评审修订版；Phase 0–1 为 Design Freeze，Phase 2–5 为 Directional Outline`
- **验收标准**：
  - 头部状态和 `§4.1` 完全一致

#### B2. 全文替换残留的旧 `ExecutionContext`

- **修改位置**：
  - `§2.3 哲学与设计对应表`
  - `§3.1 架构分层图`
  - `§3.2 模块职责表`
  - `§3.4 Agent loop 伪代码`
  - `§5.2 D-3`
- **建议替换原则**：
  - 触发层输入统一叫 `ExecutionSeed`
  - 执行器消费上下文统一叫 `ResolvedExecutionContext`
  - 若是泛指执行链概念，可写 “执行上下文（ExecutionSeed / ResolvedExecutionContext 两阶段）”
- **验收标准**：
  - 全文搜索 `ExecutionContext` 时，只保留“历史修正说明”里的引用，不再作为当前正式模型名出现

#### B3. 修正附录 A 的迁移描述

- **修改位置**：`§7 附录 A`
- **当前问题**：`schemaVersion` 这一行还写“自动迁移 + v1 备份”，已和 `config-v2.json` 独立路径方案冲突
- **建议改成**：
  - `自动迁移生成 config-v2.json；v1 config.json 保持只读，不覆盖`
- **验收标准**：
  - 附录 A 与 `§3.7` 的迁移策略完全一致

#### B4. 重写附录 C 的实施顺序

- **修改位置**：`§7 附录 C`
- **当前问题**：仍然保留旧版 `0.1 / 0.2 / 0.10 ...` 顺序，不匹配 M1/M2/M3
- **建议改成**：
  1. M1：target + SliceCore 新类型 + config-v2 migrator
  2. M2：Orchestration / Capabilities skeleton + 安全 hook
  3. M3：AppContainer 切换 + 删除旧 ToolExecutor + 回归
- **验收标准**：
  - 附录 C 与 `§4.2.3` 一一对应，不再出现旧任务编号

#### B5. 清理“冻结范围”和“Directional”相关残余表述

- **修改位置**：
  - 文档开头
  - `§0.3`
  - `§8 维护说明`
- **建议检查点**：
  - 不再暗示 Phase 2–5 已冻结
  - 不再写“下一步直接展开 Phase 0 总 plan”这种会模糊 M1/M2/M3 的表述
- **验收标准**：
  - 全文对外只传达一个信息：`现在真正冻结的只有 Phase 0–1`

### C. 完成后应达到的状态

如果上面 A+B 两组改动全部完成，这份 roadmap 可以从当前的 `REWORK_REQUIRED` 提升为：

- **建议决策**：`CONDITIONAL_APPROVE`
- **剩余保留意见**：
  - 成功指标仍偏愿望化，但不阻断 Phase 0–1
  - `ProviderCapability` 抽象仍偏超前，但已不构成当前实施阻断
  - README 与 spec 的对外叙事差异可延后到 Phase 0 合入后统一

### D. 建议 Claude 按这个顺序改

1. 先改 `§3.9`，把安全逻辑闭环补齐
2. 再做一次全文 `ExecutionContext` / `Design Freeze` / `config-v2` consistency pass
3. 最后再建 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`

---

## 第三轮复审补充（Claude 已按最小清单修订后）

**复审时间**：2026-04-23
**复审对象**：`docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（按“最小修订清单草案”再次修订后的版本）

### 复审结论

- **更新后的结论**：仍为 `REWORK_REQUIRED`
- **原因**：上一轮要求修复的四类问题里，大部分已经修到位，但安全模型的**规范化定义**还没有闭合，导致实现层仍然会面对“正文说要有，正式数据结构却没有”的歧义。

### 第三轮主要发现

1. **P1：安全模型依赖的 canonical schema 仍未闭合，`provenance` / `inferredPermissions` 都没真正进入正式定义**
   - `§3.9.1` 明确要求“每个 Tool / Pack / Skill / MCPDescriptor 都带 `provenance: Provenance` 字段”，执行流程也直接使用 `tool.provenance` 做 gate。
   - `§3.9.6.5` 又明确要求 `ContextProvider.inferredPermissions(for:)` 与 `SideEffect.inferredPermissions` 进入协议 / 类型设计，供 `PermissionGraph.compute(tool:)` 在执行前做静态闭环校验。
   - 但 `§3.3.1` 的 `Tool` 正式定义里没有 `provenance` 字段；`§3.3.8` 的 `Skill` / `MCPDescriptor` 正式定义里也没有；`§3.3.3` 的 `ContextProvider` 正式定义里没有 `inferredPermissions`；`§3.3.6` / 附录 B 的 `SideEffect` 也没有任何对应入口。
   - 文档内部还出现了两个不一致的 `Provenance` enum：早前版本没有 `.selfManaged`，后面 MCP 小节才加上，说明 canonical definition 仍未统一。
   - 影响：实现者无法判断 `provenance` / `inferredPermissions` 是不是正式 schema / protocol 字段、哪些类型必须持久化它们、迁移器是否要写它们，`ExecutionEngine` 的 `tool.provenance` 与 `PermissionGraph.compute(tool:)` 都缺少稳定的数据来源。
   - 修复建议：
     - 在 `§3.3.1 Tool`、`§3.3.8 Skill / MCPDescriptor`、附录 B 的正式定义里补上 `provenance: Provenance`
     - 只保留**一个** canonical `Provenance` enum 定义，并包含 `.selfManaged`
     - 在 `§3.3.3 ContextProvider` 的正式协议里补上 `inferredPermissions(for:)`
     - 在 `§3.3.6 / 附录 B` 的 `SideEffect` 定义里补上 `inferredPermissions` 映射入口或等价声明
     - 同步修正附录 A / 附录 C 中“Tool/Provider 补 provenance”的错误表述，去掉 `Provider`

2. **P1：权限判定规则仍有一处关键冲突，`PermissionBroker` 语义还没完全定死**
   - `§3.9.1` 中 `firstParty` 行写“对 `readonly-network` / `local-write` 可做‘已声明即授权’”，看起来像安装后无需首次确认。
   - 但 `§3.9.2` 的能力下限又把 `readonly-network` / `local-write` 定为“首次确认”；`§3.9.6` 还写“新装 Tool：所有非 `readonly-local` 能力默认未授权，首次触发时由 `PermissionBroker` gate”。
   - 这三处并不能同时成立。即便 `network-write` / `exec` 已经被修正，`readonly-network` / `local-write` 仍然存在“安装即授权”还是“首次运行确认”的歧义。
   - 影响：`PermissionBroker` 的测试矩阵仍不能唯一推出；M2.3 会在 `firstParty` 的 `readonly-network` / `local-write` 场景遇到实现分歧。
   - 修复建议：
     - 三选一并全文统一：
       1. `firstParty` 的 `readonly-network` / `local-write` 也要首次确认
       2. 或者仅安装时一次确认，运行时不再确认
       3. 但不能同时写“已声明即授权”与“首次确认”
     - 如果保留“已声明即授权”，就必须同步删除 `§3.9.6` 中“所有非 readonly-local 默认未授权”的绝对化表述

### 本轮判断

这份 roadmap 已经比第一次评审时成熟很多，尤其是：

- `ExecutionSeed -> ResolvedExecutionContext` 两阶段模型已基本稳定
- MCP stdio 风险表述已从“虚假安全感”改为真实威胁建模
- `effectivePermissions ⊆ tool.permissions` 的静态闭环已经进入主流程
- 文档的大部分旧术语漂移已被清掉

但在 `provenance` 没进入正式 schema、授权矩阵还存在一处剩余冲突之前，我不建议把结论升到 `CONDITIONAL_APPROVE`。

### 达到 `CONDITIONAL_APPROVE` 的最后门槛

1. 把 `provenance` 补进 `Tool` / `Skill` / `MCPDescriptor` / 附录 B 的正式定义，并统一 `Provenance` enum
2. 把 `firstParty + readonly-network/local-write` 的授权策略收敛成唯一规则，消除 `§3.9.1`、`§3.9.2`、`§3.9.6` 三处冲突

这两项修完后，这份 spec 基本就可以进入 `CONDITIONAL_APPROVE`

---

## 第四轮复审补充（按第三轮阻断项修复后）

**复审时间**：2026-04-23
**复审对象**：`docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（按第三轮阻断项继续修订后的版本）

### 复审结论

- **更新后的结论**：`CONDITIONAL_APPROVE`
- **原因**：前三轮指出的 P1 阻断项已经全部被修到“可实施”的程度：
  - `provenance` 已进入 `Tool` / `Skill` / `MCPDescriptor` 的正式定义
  - `ContextProvider.inferredPermissions(for:)` 与 `SideEffect.inferredPermissions` 已进入 canonical schema
  - `firstParty + readonly-network/local-write` 的授权规则已经收敛成唯一语义：**默认未授权，按 capability 下限确认，provenance 只调 UX**
  - `PermissionGraph.compute(tool:)` 与 `ExecutionEngine` Step 2 的静态 ⊆ 校验已经形成闭环

### 本轮剩余问题

1. **P3：附录里的迁移说明还有一处小口误**
   - 附录 A 与附录 C 仍写“给所有 v1 Tool/Provider 补 `provenance = .firstParty`”，但 `Provider` 的正式定义并没有 `provenance` 字段。
   - 这是文档一致性小问题，不再构成实施阻断，但建议顺手改掉，避免后续实现 migrator 时误以为 `Provider` 也要持久化 provenance。
   - 建议改成：
     - “给所有 v1 Tool 补 `provenance = .firstParty`”
     - 如需覆盖其他资源，明确写 `Skill / MCPDescriptor` 的安装默认来源，而不是写 `Provider`

### 当前判断

这份 spec 现在已经可以进入 Phase 0 的实施计划编写与开发：

- **建议决策**：`CONDITIONAL_APPROVE`
- **前提**：
  - 在开写 `docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md` 前，顺手修掉上面的 `Provider` 口误
  - README 继续维持 v0.1 对外叙事，等 Phase 0 合入后再同步更新

### 复审后的建议动作

1. 先做 2 分钟文档清理：把附录 A / C 中的 `Tool/Provider` 改成正确表述
2. 然后直接进入 M1 plan.md 编写
3. 不建议再继续无限循环评审同一份 roadmap，下一步的价值在实施，不在继续抽象

### 后续处理结果

- 2026-04-23：已按本轮建议修正 roadmap 中附录 A / C 的 `Tool/Provider` 口误，统一为：
  - v1 → v2 migrator 只给 `Tool` 补 `provenance = .firstParty`
  - `Skill` / `MCPDescriptor` 的 provenance 由安装流程写入
