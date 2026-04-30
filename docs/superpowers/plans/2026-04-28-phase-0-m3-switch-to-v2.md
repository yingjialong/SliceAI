# Phase 0 M3 — Switch to V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 V2 类型族 + Orchestration / Capabilities 真正接入 SliceAI app 启动链路；删除 v1 类型族；rename V2*/PresentationMode/SelectionOrigin 回 spec 原名；4 个内置工具实机行为与 v0.1 等价；发 v0.2.0 unsigned DMG。

**Architecture:**
- Phase 0 底层重构最后一里程碑——M1（数据模型）+ M2（执行引擎骨架）已落地为 zero-touch additive。M3 是首次让 v2 接入真实启动路径的 task。
- 执行序列：**M3.1 additive 装配 → M3.0 5 步 rename pass → M3.2/M3.3 验收 → M3.4 grep validation → M3.5 13 项手工回归 → M3.6 v0.2.0 release**。M3.1 必须先于 M3.0 因为 M3.0 Step 1 切 caller 时 `executionEngine` 必须已装配。
- 关键不变量：每个 commit 都过"swift build / swift test --parallel / xcodebuild Debug build / swiftlint --strict" 4 关 CI gate；v1 触发链在 M3.0 Step 1 切 caller 之前**全程可用**；M3.1 只 additive 装配不删 v1。

**Tech Stack:** Swift 6 strict concurrency, Xcode 26+, SwiftPM local package, SwiftUI + AppKit + Carbon hotkey, sqlite (via Cost), JSONL (via Audit), Sparkle ❌（v0.2 unsigned DMG 不带更新器）

**Reference Documents:**
- 已 approve mini-spec：`docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（~1040 行；R1~R10 approve，R11/R12 alignment 已同步）
- v2 spec：`docs/superpowers/specs/2026-04-23-sliceai-v2-roadmap.md`（§3.3 / §3.4 / §3.7 / §4.2.x）
- M1 plan：`docs/superpowers/plans/2026-04-24-phase-0-m1-core-types.md`
- M2 plan：`docs/superpowers/plans/2026-04-25-phase-0-m2-orchestration.md`
- M2 Task-detail：`docs/Task-detail/2026-04-25-phase-0-m2-orchestration.md`（§7.6 M3 backlog）
- 项目根 `CLAUDE.md`

---

## Plan-wide invariants

> 这些约束适用于本 plan 的**每个** task 与每次 commit。违反任何一条都视为 task 未完成。

1. **每步四关 CI gate 全绿**：`cd SliceAIKit && swift build` + `cd SliceAIKit && swift test --parallel --enable-code-coverage` + `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` + `swiftlint lint --strict` 任一红灯都不能 commit。
2. **不许 try! / fatalError / TODO / FIXME**：startup-time 错误必须走 NSAlert + terminate；要做的留 GitHub Issue 不留代码注释。
3. **不许 `--no-verify` 跳 hook / `--amend` 改已 push commit**。
4. **禁止 MainActor.assumeIsolated**：跨 actor 跳主线程一律用 `Task { @MainActor in ... }` + `await`（CLAUDE.md 既有规范）。
5. **任何修改 SliceAIApp 的 task 必须跑 xcodebuild**——SwiftPM 测试不会发现 app target 启动崩溃。
6. **mini-spec 是真值源**：与 plan 冲突时以 mini-spec 为准；plan 仅是落地步骤。
7. **不再回看 master todolist 的"删 SelectionPayload" / "不暴露 displayMode"等旧描述**——mini-spec §2.2 + D-28 + D-29 已显式覆盖。

---

## File structure (M3 期间新增 / 改动文件总览)

按职责分组列出 M3 期间会被新增 / 改动 / 删除的文件，方便交叉引用。

### 新增文件（M3.1 + M3.0 Step 2）

- `SliceAIKit/Sources/Orchestration/Output/InvocationGate.swift`（M3.1.C-1，~50 行）—— single-flight invocation 隔离状态唯一来源（F9.2/F3.4）
- `SliceAIKit/Tests/OrchestrationTests/Output/InvocationGateTests.swift`（M3.1.C-1，~120 行）—— 直接测试真实 `InvocationGate`，替代 SpyAdapter copy 模式
- `SliceAIApp/ResultPanelWindowSinkAdapter.swift`（M3.1.C-1，~40 行）—— 实现 `WindowSinkProtocol`，委托 `InvocationGate.gatedAppend(...)`
- `SliceAIApp/ExecutionEventConsumer.swift`（M3.0 Step 1，~120 行）—— 把 14 个 `ExecutionEvent` case 翻译为 `ResultPanel` API
- `SliceAIKit/Sources/SelectionCapture/SelectionReader.swift`（M3.0 Step 2，~80 行）—— v1 `protocol SelectionSource` 改名 + 含 `SelectionReadResult` struct；真实 v1 文件没有额外错误枚举
- `SliceAIApp/Tests/ExecutionEventConsumerTests.swift`（M3.0 Step 1.spy_tests，~150 行）—— 5 个 spy test 覆盖 D-30/F8.3/F9.2/F3.2

### 删除文件（M3.0 Step 2 — 同 commit 删 7 + 1 = 8 个文件）

- `SliceAIKit/Sources/SliceCore/Tool.swift`
- `SliceAIKit/Sources/SliceCore/Provider.swift`
- `SliceAIKit/Sources/SliceCore/Configuration.swift`
- `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift`（v1 `FileConfigurationStore`）
- `SliceAIKit/Sources/SliceCore/ConfigurationProviding.swift`
- `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
- `SliceAIKit/Sources/SliceCore/ToolExecutor.swift`
- `SliceAIKit/Sources/SelectionCapture/SelectionSource.swift`（v1 protocol）
- 对应 Tests：`ToolTests.swift` / `ConfigurationTests.swift` / `ToolExecutorTests.swift`（若存在）

### Rename 文件（M3.0 Step 3，git mv 5 个）

- `V2Tool.swift` → `Tool.swift`
- `V2Provider.swift` → `Provider.swift`
- `V2Configuration.swift` → `Configuration.swift`
- `V2ConfigurationStore.swift` → `ConfigurationStore.swift`
- `DefaultV2Configuration.swift` → `DefaultConfiguration.swift`
- 对应 Tests：`V2ToolTests.swift` → `ToolTests.swift` / `V2ProviderTests.swift` → `ProviderTests.swift` / `V2ConfigurationTests.swift` → `ConfigurationTests.swift` / `V2ConfigurationStoreTests.swift` → `ConfigurationStoreTests.swift`

### 改动文件（按 task 阶段拆解；详见各 Task）

- M3.1.A：`V2ConfigurationStore.swift` + `V2ConfigurationStoreTests.swift`
- M3.1.B：`SliceAI.xcodeproj/project.pbxproj`
- M3.1.C：`AppContainer.swift`
- M3.1.D：`AppDelegate.swift`
- M3.0 Step 1：30+ 文件涉及 SettingsUI / AppContainer / AppDelegate / Windowing / Tests
- M3.0 Step 2：3 个 LLMProviderFactory 相关文件 + v1 删除
- M3.0 Step 3-5：rename pass
- M3.6：`README.md` / `CLAUDE.md` / `docs/Module/*.md` / `docs/Task_history.md` / `docs/Task-detail/*.md` / `docs/v2-refactor-master-todolist.md`

---

## Task 1: M3.1 Sub-step A — V2ConfigurationStore.load both-missing 写盘 + 单测【F1.5】

**目标**：让 `V2ConfigurationStore.load()` 在 both-missing 分支显式 `try writeV2(default)`，使 M3.1 bootstrap 调 `try await v2ConfigStore.current()` 能创建 `config-v2.json` 文件。

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift:60-72`（load() 方法 both-missing 分支）
- Modify: `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift`（新增 `test_load_withNeither_writesDefaultToV2Path`；既有 `test_load_withNeither_returnsDefaultV2`（line 86-95）**不需修改**——它仅 assert 返回值不 assert file existence，新行为"写盘 + 返回 default"对它不 break，仍 pass）

- [ ] **Step 1: 写新单测（Round-1 R1.1 修订：XCTest 风格与既有文件一致；本 loop = M3 plan 第四次 codex review）**

> **Round-1 R1.1 修订（2026-04-30 本 loop = M3 plan 第四次 codex review）**：旧版 Step 1 代码用 Swift Testing `@Test("...") / #expect(...)` 风格，与真实 `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift`（XCTest 风格：`import XCTest` + `final class V2ConfigurationStoreTests: XCTestCase` + 既有 14 个 `func test_*` 全用 `XCTAssertEqual` / `XCTAssertTrue` / `XCTAssertFalse`）不兼容。Implementer 把 `@Test` macro 加进 XCTestCase class 内部会导致 macro 未在该上下文定义 → Swift compile error；即使 macro 在该 module 可用（实际 SliceAIKit 没 import Testing），swift test 不会发现该 test → Step 2 "跑单测验证它失败" 实际不跑 → Step 3 改 load() 也无法验证 → 整个 Task 1 TDD 链路失效。**修法**：用 XCTest 风格写新 test，复用既有 `tempDir` setUp/tearDown fixture（不要在 test 内手动 createDirectory + defer removeItem），与 line 86-95 `test_load_withNeither_returnsDefaultV2` 同模式。

新增到 `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift`（粘到既有 `test_load_withNeither_returnsDefaultV2`（line 86-95）测试附近，class V2ConfigurationStoreTests: XCTestCase 内部）：

```swift
func test_load_withNeither_writesDefaultToV2Path() async throws {
    // 复用 tempDir fixture（setUp 已 createDirectory；tearDown 已 removeItem）
    let v2URL = tempDir.appendingPathComponent("config-v2.json")
    let legacyURL = tempDir.appendingPathComponent("config.json")
    let store = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: legacyURL)

    // Pre-condition：两个文件都不存在
    XCTAssertFalse(FileManager.default.fileExists(atPath: v2URL.path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))

    // Action：调 current() 触发 load()
    let cfg = try await store.current()

    // Assertion 1：返回值 == DefaultV2Configuration.initial()
    let expected = DefaultV2Configuration.initial()
    XCTAssertEqual(cfg.providers.map(\.id), expected.providers.map(\.id))
    XCTAssertEqual(cfg.tools.map(\.id), expected.tools.map(\.id))

    // Assertion 2：v2 文件已创建
    XCTAssertTrue(FileManager.default.fileExists(atPath: v2URL.path))

    // Assertion 3：v1 文件**仍**不存在（v1 永不被写）
    XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
}
```

> **note**：既有 `test_load_withNeither_returnsDefaultV2`（line 86-95）保持原状——它仅 assert 返回值（`XCTAssertEqual(cfg.schemaVersion, 2)` + `XCTAssertEqual(cfg.tools.count, 4)`），不 assert file existence；F1.5 修订让 load() 在 both-missing 时新增"写盘"副作用，对既有 test 的断言无影响（returnsDefault 仍成立）。新 test 是"strict 版本"覆盖完整新行为（returnsDefault + writesV2 + 不写 v1）。

- [ ] **Step 2: 跑单测验证它失败**

Run: `cd SliceAIKit && swift test --filter "SliceCoreTests.V2ConfigurationStoreTests/test_load_withNeither_writesDefaultToV2Path"`
Expected: FAIL — assertion 2 失败（"FileManager.default.fileExists(atPath: v2URL.path)" 为 false），因为当前 load() 在 both-missing 分支不写盘

- [ ] **Step 3: 修改 load() 加写盘**

修改 `SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift` 的 `load()` 方法，把：

```swift
        v2ConfigLog.debug("load() neither v2 nor v1 exists, returning DefaultV2Configuration.initial()")
        return DefaultV2Configuration.initial()
```

改为：

```swift
        v2ConfigLog.debug("load() neither v2 nor v1 exists, writing DefaultV2Configuration.initial() to v2 path")
        let defaultCfg = DefaultV2Configuration.initial()
        try writeV2(defaultCfg)
        return defaultCfg
```

- [ ] **Step 4: 跑单测验证通过**

Run: `cd SliceAIKit && swift test --filter "SliceCoreTests.V2ConfigurationStoreTests"`
Expected: PASS — 新测试 `test_load_withNeither_writesDefaultToV2Path` 绿，且既有 `test_load_withNeither_returnsDefaultV2` 仍绿（写盘前的 default 内容不变）

- [ ] **Step 5: 跑完整 4 关 CI gate（Plan-wide invariant；Round-5 R5.1 修订）**

> **Round-5 R5.1 修订（2026-04-29 本 loop = M3 plan 第三次 codex review）**：旧 Step 5 第 2 关命令是 `swift test --filter SliceCoreTests`（仅跑 SliceCoreTests target，**不带** `--parallel --enable-code-coverage` flag），与 plan-wide invariant 第 1 条要求的 `swift test --parallel --enable-code-coverage` 不一致——会让 M3 第一枚 commit (Task 1 = M3.1.A) 缺并行执行 + 覆盖率门禁；同时漏测 SliceCore 改动对其他 target（LLMProviders / SelectionCapture / Orchestration / SettingsUI / Windowing 等）测试集的间接影响。修法：Step 5 严格用 plan-wide invariants 的 4 关命令（Step 4 已用 filtered TDD 命令跑过新增测试，Step 5 commit 前再跑一次全量是 KISS 安全网）。

Run:
```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
Expected: All PASS, 0 violations。即使本 task 只改 SliceCore，**全量** swift test + xcodebuild 都必须本地跑（plan-wide invariant 第 1 条 + 第 5 条）——SliceCore 改动可能间接 break LLMProviders / SelectionCapture / Orchestration / SettingsUI / Windowing 等下游 target。

> **note (M3.1.A → M3.1.B 过渡期)**：M3.1.A (Task 1) 是 M3 第一枚 commit；此时 `.github/workflows/ci.yml` 仍是 baseline 3 关（M3.1.B Task 2 Step 4.5 才把 xcodebuild 加进 ci.yml）。意味 PR CI 在 Task 1 commit 推上后**只跑 3 关**（swift build / test --parallel --enable-code-coverage / swiftlint --strict），**第 4 关 xcodebuild 由 implementer 本地跑**（本 Step 5 命令 #3）。Task 2 commit 推上后 ci.yml 才完整 4 关，从 Task 2 起 PR CI 全覆盖。这是已知的"先有 SliceCore 修订再扩 ci.yml"过渡期，不视作 plan failure；implementer 跑完本 Step 5 看到全 PASS 即可推 commit。

- [ ] **Step 6: Commit M3.1.A**

```bash
git add SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift
git commit -m "$(cat <<'EOF'
feat(slicecore): V2ConfigurationStore.load() writes default to v2 on both-missing

让 first-launch 全新安装路径（v2 / v1 都不存在）在 load() 内显式 writeV2(default)，
使 AppContainer.bootstrap() 调 v2ConfigStore.current() 能创建 config-v2.json。
F1.5 修订；M3.1 Sub-step A，必须先于 Sub-step C 装配。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 2: M3.1 Sub-step B — Xcode app target 加 Orchestration / Capabilities deps【F2.1】

**目标**：让 `SliceAI.xcodeproj` 的 SliceAI app target 能 `import Orchestration` 和 `import Capabilities`，使 M3.1.C 改 AppContainer 时不报 "No such module"。

**Files:**
- Modify: `SliceAI.xcodeproj/project.pbxproj`（packageProductDependencies + frameworksBuildPhase）
- Modify: `.github/workflows/ci.yml`（Step 4.5 新增 xcodebuild Debug build step；Round-2 R2.3 修订，与 pbxproj 同 commit）

- [ ] **Step 1: Open Xcode**

```bash
open SliceAI.xcodeproj
```

- [ ] **Step 2: 在 Xcode UI 加依赖**

1. 选中 SliceAI app target（Project Navigator 顶部）
2. 切到 "General" tab
3. 滚到 "Frameworks, Libraries, and Embedded Content" 区域
4. 点 "+" 按钮 → "Add Other..." → "Add Package Dependency..."
5. 由于 SliceAIKit 已经是 local package，直接在 "Search or Enter Package URL" 顶部找到 SliceAIKit
6. 在产品列表勾选 **Orchestration** 和 **Capabilities**（应该会 highlight 当前未勾选的）
7. 点 "Add"

或者直接用 plist 编辑（不推荐，但更精确）：编辑 `SliceAI.xcodeproj/project.pbxproj` 在 SliceAI app target 的 `packageProductDependencies` array 加两行：

```
XX1 /* Orchestration */,
XX2 /* Capabilities */,
```

并在 `XCSwiftPackageProductDependency` section 加对应：

```
XX1 /* Orchestration */ = {
    isa = XCSwiftPackageProductDependency;
    productName = Orchestration;
};
XX2 /* Capabilities */ = {
    isa = XCSwiftPackageProductDependency;
    productName = Capabilities;
};
```

（XX1/XX2 是 24 位十六进制 ID；用 `uuidgen | tr -d '-' | head -c 24 | tr 'a-z' 'A-Z'` 生成）

- [ ] **Step 3: 验证 xcodebuild 通过**

Run:
```
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug clean build
```
Expected: BUILD SUCCEEDED；output 末尾应能看到 "Compiling Orchestration" / "Compiling Capabilities" 的 log

- [ ] **Step 4: 临时验证 import 可用**

在 `SliceAIApp/AppContainer.swift` 顶部临时加（Step 5 commit 前删除）：

```swift
import Orchestration  // 临时验证 import
import Capabilities   // 临时验证 import
```

Run: `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build`
Expected: BUILD SUCCEEDED 不再报 "No such module"

- [ ] **Step 4.5: 把 xcodebuild Debug build 加进 .github/workflows/ci.yml（Round-2 R2.3 修订；本 loop = M3 plan 第三次 codex review）**

> **Round-2 R2.3 修订（2026-04-29 本 loop）**：plan-wide invariants 第 1 条把 xcodebuild Debug build 列为"4 关 CI gate"必过项，但真实 `.github/workflows/ci.yml`（M2 已落地版本）只跑 `swift build -v` + `swift test --parallel --enable-code-coverage` + `swiftlint lint --strict` 三项，**不跑 xcodebuild**。本 Sub-step B 起 pbxproj 持续被改 + Sub-step C 在 SliceAIApp 下加 `ResultPanelWindowSinkAdapter` / `ExecutionEventConsumer` 源文件 + M3.0 Step 1 大量改 AppDelegate / AppContainer wiring，这些都是 SwiftPM `swift build` 抓不到的 app target 改动；PR 可能 CI 全绿但 release tag 推后才发现 `xcodebuild` 失败。**修法**：本 step 把 xcodebuild Debug build 加进 ci.yml 作为强制 PR CI gate，让 plan-wide invariants 第 1 条名实一致；与 Step 5 pbxproj 同 commit 落地（避免 ci.yml 先上 PR CI 立刻挂起）。

修改 `.github/workflows/ci.yml`，在 `Run SwiftLint` step 之前插入 `Build SliceAI app target` step。改后 `jobs.build-and-test.steps` 完整序列（与 plan-wide invariants 第 1 条 4 关顺序一致：build → test → xcodebuild → swiftlint）：

```yaml
      - uses: actions/checkout@v4

      - name: Xcode version
        run: xcodebuild -version

      - name: Swift version
        run: swift --version

      - name: Build SliceAIKit
        working-directory: SliceAIKit
        run: swift build -v

      - name: Test SliceAIKit
        working-directory: SliceAIKit
        run: swift test --parallel --enable-code-coverage

      - name: Build SliceAI app target
        run: xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build

      - name: Install SwiftLint
        run: brew install swiftlint

      - name: Run SwiftLint
        run: swiftlint lint --strict
```

> **预跑验证**：本 step 改完后，本地跑 `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build` 应通过（Step 4 临时 import 已删，AppContainer 尚未真正引用 Orchestration/Capabilities，xcodebuild 会成功）。Sub-step C / D + M3.0 Step 1 加真实引用后 ci.yml 持续保持绿；任何 wiring 漏洞会在该 PR 的 CI run 立刻暴露。
> **edge case**：M2 baseline ci.yml 不跑 xcodebuild，意味着 main HEAD 当前未被 xcodebuild PR CI 覆盖；如果 main 上已存在某种 xcodebuild-only 失败的潜在问题（理论上不应有，M2 zero-touch SliceAIApp），本 step 会在第一次 PR run 时暴露。这是预期行为，不视作 plan failure。

- [ ] **Step 5: 删临时 import + 跑完整 4 关 CI gate + commit**

把临时 import 删掉（Sub-step C 才正式加），先跑完整 4 关：

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```

Expected: All PASS, 0 violations。然后：

```bash
git add SliceAI.xcodeproj/project.pbxproj .github/workflows/ci.yml
git status SliceAIApp/AppContainer.swift   # 应是 unchanged
git commit -m "$(cat <<'EOF'
chore(xcodeproj+ci): add Orchestration + Capabilities deps + xcodebuild PR CI gate

让 M3.1.C 装配 ExecutionEngine 时 AppContainer.swift 能 import Orchestration / Capabilities，
否则会触发 No such module 链接错误。F2.1 修订；M3.1 Sub-step B。

同步 Round-2 R2.3 修订：把 xcodebuild Debug build 加进 .github/workflows/ci.yml 作为
强制 PR CI gate（M2 baseline ci.yml 仅 swift build + swift test + swiftlint 三项；
M3.1.B 起 pbxproj 持续被改 + 后续 SliceAIApp 源文件大量增加，需要 PR CI 同步抓
app target 编译失败，避免 release tag 才发现）。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 3: M3.1 Sub-step C — 创建 InvocationGate + ResultPanelWindowSinkAdapter【F9.2 + F3.4 R3】

**目标**：把 single-flight 状态从 ResultPanelWindowSinkAdapter 抽出到独立 `InvocationGate` 类（放 Orchestration target）；adapter 持有 + 委托。这样 R2 spy test 可以直接测**真实 InvocationGate**，避免 R3 codex 指出的"SpyAdapter 是 copy 出来的契约，不能证明生产 adapter 的 single-flight 实际行为"假阳性问题。

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Output/InvocationGate.swift`（~50 行；F3.4 R3 单一 single-flight 状态来源）
- Create: `SliceAIKit/Tests/OrchestrationTests/Output/InvocationGateTests.swift`（~120 行；F3.4 R3 直接测真实 gate）
- Create: `SliceAIApp/ResultPanelWindowSinkAdapter.swift`（~40 行；持有 InvocationGate + 委托）

- [ ] **Step 1: 创建 InvocationGate.swift（F3.4 R3 — single-flight 状态唯一来源）**

写入 `SliceAIKit/Sources/Orchestration/Output/InvocationGate.swift`：

```swift
// SliceAIKit/Sources/Orchestration/Output/InvocationGate.swift
import Foundation

/// F9.2 single-flight invocation 隔离契约的状态持有者 + chunk gating 入口。
///
/// **F3.4 R3 + F4.2 R4 walking back**：R3 把 single-flight 状态抽到本类已是第一步；
/// R4 进一步把 "guard shouldAccept then call sink" 这个 chunk gating 逻辑也搬进本类
/// （`gatedAppend(...)`）。这样 ResultPanelWindowSinkAdapter 就只剩"持有 panel 闭包 + 1 行委托"，
/// 整个 single-flight 行为（state + gating）在本类内被 SwiftPM tests 直接覆盖——
/// adapter 漏 gate / new 错 gate / 注入错实例都不可能让测试假绿。
///
/// **为什么 @MainActor class 而非 actor**：被 ResultPanelWindowSinkAdapter（也是 @MainActor）持有；
/// AppDelegate.execute 在 @MainActor 上下文同步调用 setActive/clearActive — actor 会强制 await + 引入
/// race（R2 F2.2 已踩过这个坑）。@MainActor class 让所有访问都同步串行化在 main thread。
@MainActor
public final class InvocationGate {

    /// 当前接受 chunk 的 invocation；nil 时 shouldAccept 返回 false
    private var activeInvocationId: UUID?

    public init() {}

    /// 标记新 invocation 开始接受 chunk；调用时机：AppDelegate.execute 在 stream 创建前
    public func setActiveInvocation(_ id: UUID) {
        activeInvocationId = id
    }

    /// 清空 activeInvocationId — 必须带 ifCurrent: guard
    ///
    /// **F2.2 R2 修订**：onDismiss / defer 调用方传入自己的 invocationId；只有匹配 active 时才清空。
    /// 防止"旧 invocation 取消的 defer 晚于新 invocation setActive 运行 → 把 B 误清空" 竞态。
    public func clearActiveInvocation(ifCurrent id: UUID) {
        guard activeInvocationId == id else { return }
        activeInvocationId = nil
    }

    /// 判断 chunk 是否应被接受 — 等价于 invocationId == activeInvocationId
    /// 暴露给单测；生产代码应优先用 `gatedAppend(...)` 把 guard + 调用合在一起，避免外部漏 guard
    public func shouldAccept(invocationId: UUID) -> Bool {
        activeInvocationId == invocationId
    }

    /// **F4.2 R4 新增**：gate-guarded chunk append — 唯一入口
    ///
    /// 把 "if shouldAccept then call sink" 的 atomic 逻辑收到本类内，让生产 adapter 只需
    /// 1 行委托。SwiftPM tests 直接测本方法即可证明 stale chunk 真的不调 sink；adapter
    /// 漏 gate / new 错 gate / 注入错实例都不会让测试假绿（因为没有 adapter 层 if）。
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段
    ///   - invocationId: chunk 所属 invocation；与 active 不一致时 sink 闭包**不被调用**（静默丢弃）
    ///   - sink: 实际 chunk 投递闭包（生产代码传 `{ c in panel.append(c) }`；测试传 spy collector）
    public func gatedAppend(
        chunk: String,
        invocationId: UUID,
        sink: @MainActor (String) -> Void
    ) {
        guard activeInvocationId == invocationId else {
            // F9.2 隔离契约：过期 invocation 的 chunk 静默丢弃；sink 不被调用
            return
        }
        sink(chunk)
    }
}
```

- [ ] **Step 2: 创建 InvocationGateTests.swift（F3.4 R3 — 直接测真实 gate；4th-loop R4.X 修订：XCTest 风格统一）**

> **4th-loop R4.X 修订（2026-04-30 完整审核）**：旧版本用 Swift Testing `@Suite` / `@Test`，但 `OrchestrationTests` target 13 个既有测试文件 100% 用 XCTest（`import XCTest` + `XCTestCase`）；`Package.swift` testTarget 无 swift-testing dep。引入 Swift Testing 会破坏 target 风格一致性 + 强制改 Package.swift。**修法**：用 XCTest 风格（`final class : XCTestCase` + `func test_*` + `XCTAssertTrue` / `XCTAssertEqual`），与 OrchestrationTests target 既有 13 文件同模式。

写入 `SliceAIKit/Tests/OrchestrationTests/Output/InvocationGateTests.swift`：

```swift
import Foundation
import XCTest
@testable import Orchestration

/// F9.2 single-flight invocation 隔离契约 — 直接测真实 InvocationGate（非 spy copy）
///
/// **F3.4 R3 修订**：R2 SpyAdapter 是 copy 出来的契约，无法证明生产代码合契约。
/// 本测试直接 import Orchestration 的 InvocationGate 真实实现。
@MainActor
final class InvocationGateTests: XCTestCase {

    /// overlapping invocations: A's stale shouldAccept=false after switch to B
    func test_overlappingInvocations_dropStale() {
        let gate = InvocationGate()
        let a = UUID()
        let b = UUID()

        gate.setActiveInvocation(a)
        XCTAssertTrue(gate.shouldAccept(invocationId: a))
        XCTAssertFalse(gate.shouldAccept(invocationId: b))

        gate.setActiveInvocation(b)
        XCTAssertFalse(gate.shouldAccept(invocationId: a))  // A 现在过期
        XCTAssertTrue(gate.shouldAccept(invocationId: b))
    }

    /// clearActiveInvocation(ifCurrent:): only own invocation can clear
    func test_clearIfCurrent_guard() {
        let gate = InvocationGate()
        let a = UUID()
        let b = UUID()

        gate.setActiveInvocation(a)
        gate.clearActiveInvocation(ifCurrent: b)  // B 不是 active；no-op
        XCTAssertTrue(gate.shouldAccept(invocationId: a))  // A 仍 active

        gate.clearActiveInvocation(ifCurrent: a)  // A 是 active；清空
        XCTAssertFalse(gate.shouldAccept(invocationId: a))
    }

    /// F2.2 R2 race regression: A's stale defer 不能误清空 B 的 active
    func test_staleClearAfterSwitch_doesNotEvictNew() {
        let gate = InvocationGate()
        let a = UUID()
        let b = UUID()

        // A setActive → 切换到 B → A 的 defer 晚到（模拟 R1 fix race）
        gate.setActiveInvocation(a)
        gate.setActiveInvocation(b)
        gate.clearActiveInvocation(ifCurrent: a)  // A 的 defer 晚到 → ifCurrent guard 应阻止清空
        XCTAssertTrue(gate.shouldAccept(invocationId: b))  // B 仍 active
    }

    /// dismiss before first chunk: gate cleared blocks all subsequent chunks
    func test_dismissBeforeFirstChunk() {
        let gate = InvocationGate()
        let a = UUID()
        gate.setActiveInvocation(a)
        gate.clearActiveInvocation(ifCurrent: a)  // 模拟 dismiss

        XCTAssertFalse(gate.shouldAccept(invocationId: a))  // 后续 chunk 全部 reject
    }

    /// first chunk after setActive accepted
    func test_setActiveThenFirstChunk() {
        let gate = InvocationGate()
        let a = UUID()
        gate.setActiveInvocation(a)
        // 首 chunk 立即到达
        XCTAssertTrue(gate.shouldAccept(invocationId: a))
    }

    // MARK: - F4.2 R4: gatedAppend 端到端 chunk 投递测试

    /// F4.2 R4: gatedAppend with active invocation calls sink exactly once
    func test_gatedAppend_active_callsSink() {
        let gate = InvocationGate()
        let a = UUID()
        gate.setActiveInvocation(a)

        var received: [String] = []
        gate.gatedAppend(chunk: "hello", invocationId: a) { received.append($0) }

        XCTAssertEqual(received, ["hello"])
    }

    /// F4.2 R4: gatedAppend with stale invocation never calls sink
    func test_gatedAppend_stale_skipsSink() {
        let gate = InvocationGate()
        let a = UUID()
        let b = UUID()
        gate.setActiveInvocation(b)  // active 是 B

        var received: [String] = []
        gate.gatedAppend(chunk: "stale-A", invocationId: a) { received.append($0) }

        XCTAssertTrue(received.isEmpty)  // sink 闭包根本没被调用 — adapter 漏 guard 也不会出现 chunk
    }

    /// F4.2 R4: gatedAppend after clearIfCurrent never calls sink
    func test_gatedAppend_afterClear_skipsSink() {
        let gate = InvocationGate()
        let a = UUID()
        gate.setActiveInvocation(a)
        gate.clearActiveInvocation(ifCurrent: a)

        var received: [String] = []
        gate.gatedAppend(chunk: "post-dismiss", invocationId: a) { received.append($0) }

        XCTAssertTrue(received.isEmpty)
    }
}
```

Run: `cd SliceAIKit && swift test --filter OrchestrationTests.InvocationGateTests`
Expected: 8 PASS（5 个 gate 状态测试 + 3 个 gatedAppend 端到端测试）

- [ ] **Step 3: 创建 ResultPanelWindowSinkAdapter.swift（持有 InvocationGate + 委托）**

写入 `SliceAIApp/ResultPanelWindowSinkAdapter.swift`：

```swift
// SliceAIApp/ResultPanelWindowSinkAdapter.swift
import Foundation
import Orchestration
import Windowing

/// `WindowSinkProtocol` 的 SliceAIApp 层适配实现：把 `OutputDispatcher` 的 chunk
/// 路由到既有 `ResultPanel` 单实例 — single-flight 状态委托给 `InvocationGate`。
///
/// **F3.4 R3 walking back R2**：single-flight 逻辑（active id state + ifCurrent guard）
/// 抽到 Orchestration target 的 `InvocationGate`；adapter 仅持有 + 委托 + 调 panel.append。
/// 这样 SwiftPM 测试可以直接 import + 测试真实 InvocationGate（不是 SpyAdapter copy）。
///
/// **为什么放 SliceAIApp 而非 Windowing/**：adapter 跨 Windowing + Orchestration 两层依赖；
/// 放 SliceAIApp（composition root 层）保持"Windowing 仅依赖 DesignSystem"不变量。
@MainActor
public final class ResultPanelWindowSinkAdapter: WindowSinkProtocol {

    /// 注入的结果面板单实例
    private let panel: ResultPanel

    /// single-flight 状态持有者（F3.4 R3 抽出，可被 SwiftPM tests 直接测）
    private let gate: InvocationGate

    /// 构造 adapter
    /// - Parameters:
    ///   - panel: 注入的 ResultPanel（AppContainer 装配时传入）
    ///   - gate: 注入的 InvocationGate；AppContainer 同时注入给 AppDelegate 的 setActive/clearActive 路径
    public init(panel: ResultPanel, gate: InvocationGate) {
        self.panel = panel
        self.gate = gate
    }

    /// `WindowSinkProtocol` 实现：单行委托 — single-flight gating 全部在 InvocationGate.gatedAppend 内
    ///
    /// **F4.2 R4 walking back**：移除 adapter 自身的 `if shouldAccept then panel.append` 分支；
    /// chunk gating 全部下沉到 InvocationGate.gatedAppend(chunk:invocationId:sink:) 由 SwiftPM tests 直接覆盖。
    /// 本方法仅是把 panel.append 包装为 sink 闭包传给 gate；adapter 自身不含分支逻辑。
    ///
    /// - Parameters:
    ///   - chunk: 单个 LLM stream 片段
    ///   - invocationId: chunk 所属 invocation；gate 不接受时 sink 闭包不被调用（adapter 不知道 / 也不在乎）
    public func append(chunk: String, invocationId: UUID) async throws {
        gate.gatedAppend(chunk: chunk, invocationId: invocationId) { [weak panel] c in
            panel?.append(c)
        }
    }
}
```

> **note F3.4 R3 + F4.2 R4**：
> - adapter 不再持有 setActiveInvocation / clearActiveInvocation 方法——这些 API 移到了 InvocationGate。
> - AppDelegate.execute 改为直接调 `container.invocationGate.setActiveInvocation(...)` / `container.invocationGate.clearActiveInvocation(ifCurrent:)`（**而非 adapter 的同名方法**）。
> - AppContainer 必须**同时**持有 invocationGate + adapter，并把同一个 gate 实例注入给两者；不要 adapter init 内自己 new InvocationGate（否则 AppDelegate 拿不到同一个 gate 实例）。
> - **F4.2 R4**：adapter 内不再有 `if guard else return` 分支——chunk gating 完全在 InvocationGate.gatedAppend 内，sink 闭包是唯一交互点。adapter 漏 gate / new 错 gate / 注入错实例都被 SwiftPM gatedAppend tests 直接捕获（adapter 没有可绕过的 if）。

- [ ] **Step 3.5: 把 ResultPanelWindowSinkAdapter.swift 加入 Xcode app target Sources【F4.1 R4 必加】**

`SliceAI.xcodeproj` 用**显式 sources build phase**（不是 file system synchronized group），新文件**必须手工在 4 个位置注册**到 `SliceAI.xcodeproj/project.pbxproj`，否则 `xcodebuild` 找不到该 .swift（symptom：app target 调 `ResultPanelWindowSinkAdapter` 时报 "Cannot find type ... in scope"）。

参照已有 `MenuBarController.swift` 模式（已 4 处注册，UUID 533BA78A.../533BA784...）。本步骤新分配**两个稳定 UUID**，加 4 行；用 Edit 工具逐个打补丁：

| 用途 | 分配 UUID（24 hex）|
|---|---|
| `ResultPanelWindowSinkAdapter.swift in Sources` (PBXBuildFile) | `533BA7A02F9695D00078EF4F` |
| `ResultPanelWindowSinkAdapter.swift` 文件引用 (PBXFileReference) | `533BA7A12F9695D00078EF4F` |

> **UUID 选取原则**：复用既有项目的 24-char hex 形式 `533BA7XXXX2F9695D00078EF4F`（与现有 6 个 SliceAIApp 文件同 epoch，最大值 533BA791，挑 533BA7A0+ 起步避免冲突）。不要用 `uuidgen` 默认输出（带 `-` 且大小写混乱，pbxproj 解析依赖纯 hex）。

**Edit op 1 — PBXBuildFile section**：anchor 是已有 MenuBarController 那一行（pbxproj 当前 line 12 附近）

```diff
 		533BA78A2F9695D00078EF4F /* MenuBarController.swift in Sources */ = {isa = PBXBuildFile; fileRef = 533BA7842F9695D00078EF4F /* MenuBarController.swift */; };
+		533BA7A02F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift in Sources */ = {isa = PBXBuildFile; fileRef = 533BA7A12F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift */; };
 		533BA78B2F9695D00078EF4F /* SliceAIApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 533BA7862F9695D00078EF4F /* SliceAIApp.swift */; };
```

**Edit op 2 — PBXFileReference section**：anchor 是已有 MenuBarController.swift 引用（pbxproj 当前 line 29 附近）

```diff
 		533BA7842F9695D00078EF4F /* MenuBarController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = MenuBarController.swift; sourceTree = "<group>"; };
+		533BA7A12F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ResultPanelWindowSinkAdapter.swift; sourceTree = "<group>"; };
 		533BA7852F9695D00078EF4F /* SliceAI.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = SliceAI.entitlements; sourceTree = "<group>"; };
```

**Edit op 3 — SliceAIApp 子 Group 的 children**（pbxproj 当前 line 77 附近）

```diff
 			533BA7842F9695D00078EF4F /* MenuBarController.swift */,
 			533BA7852F9695D00078EF4F /* SliceAI.entitlements */,
+			533BA7A12F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift */,
 			533BA7862F9695D00078EF4F /* SliceAIApp.swift */,
```

**Edit op 4 — Sources build phase 的 files**（pbxproj 当前 line 175 附近）

```diff
 			533BA78A2F9695D00078EF4F /* MenuBarController.swift in Sources */,
+			533BA7A02F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift in Sources */,
 			533BA78B2F9695D00078EF4F /* SliceAIApp.swift in Sources */,
```

**Step 3.5 验证 grep gate**（必须在 Step 4 build 之前跑）：

```bash
echo "=== 文件是否已注册到 pbxproj 的 3 处必要位置 ===" && \
PBXFILE=SliceAI.xcodeproj/project.pbxproj && \
COUNT_FILEREF=$(grep -c "533BA7A12F9695D00078EF4F /\* ResultPanelWindowSinkAdapter\.swift \*/" "$PBXFILE") && \
COUNT_BUILDFILE=$(grep -c "533BA7A02F9695D00078EF4F /\* ResultPanelWindowSinkAdapter\.swift in Sources \*/" "$PBXFILE") && \
COUNT_GROUP=$(grep -c "533BA7A12F9695D00078EF4F /\* ResultPanelWindowSinkAdapter\.swift \*/," "$PBXFILE") && \
COUNT_SOURCESPHASE=$(grep -c "533BA7A02F9695D00078EF4F /\* ResultPanelWindowSinkAdapter\.swift in Sources \*/," "$PBXFILE") && \
echo "PBXFileReference 出现次数 = $COUNT_FILEREF（期望 ≥1，op2）" && \
echo "PBXBuildFile 出现次数 = $COUNT_BUILDFILE（期望 ≥1，op1）" && \
echo "Group children 引用次数 = $COUNT_GROUP（期望 ≥1，op3）" && \
echo "Sources build phase 引用次数 = $COUNT_SOURCESPHASE（期望 ≥1，op4）" && \
if [ "$COUNT_FILEREF" -lt 1 ] || [ "$COUNT_BUILDFILE" -lt 1 ] || [ "$COUNT_GROUP" -lt 1 ] || [ "$COUNT_SOURCESPHASE" -lt 1 ]; then echo "FAIL: 4 处注册不齐全"; exit 1; fi && \
echo "PASS: ResultPanelWindowSinkAdapter.swift 4 处注册齐全"
```

任何 `COUNT_XXX < 1` → 回头补对应 Edit op；4 处都 ≥1 才进 Step 4。

> **note**：本 grep gate 用 `[ -lt 1 ] && exit 1` 显式 fail，避免 `rg && echo` 模式被 0 命中误当成 success（rg 在 0 命中时 exit 1，shell 短路使后面的 echo 不执行，但脚本整体仍 exit 0 误报通过）。

- [ ] **Step 4: 验证完整 4 关 CI gate**

Run:
```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
Expected: All PASS, 0 violations；adapter + gate 都编译通过

- [ ] **Step 5: Commit M3.1.C-1（gate + adapter + pbxproj 一起 commit）**

```bash
git add SliceAIKit/Sources/Orchestration/Output/InvocationGate.swift SliceAIKit/Tests/OrchestrationTests/Output/InvocationGateTests.swift SliceAIApp/ResultPanelWindowSinkAdapter.swift SliceAI.xcodeproj/project.pbxproj
git commit -m "$(cat <<'EOF'
feat(orchestration+sliceaiapp): add InvocationGate + ResultPanelWindowSinkAdapter

InvocationGate（@MainActor class，Orchestration target）：单一 single-flight 状态来源；
含 setActiveInvocation / clearActiveInvocation(ifCurrent:) / shouldAccept(invocationId:) /
gatedAppend(chunk:invocationId:sink:) 四个 API。
ResultPanelWindowSinkAdapter（@MainActor class，SliceAIApp）：实现 WindowSinkProtocol；持有
InvocationGate + 委托；append 通过 gate.gatedAppend 决定是否投递 panel.append。
InvocationGateTests 直接测真实 gate（含 race regression test）— 替代 R2 SpyAdapter copy 模式。

F9.2 + F2.2 R2 + F3.4 R3 修订；M3.1 Sub-step C-1。M3.0 Step 1 接 chunk 流前不被任何 caller 调用。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 4: M3.1 Sub-step C — AppContainer additive 装配 v2 + 10 依赖（与 Task 5 原子合并）【F1.2 + F5.1】

**目标**：在 `AppContainer` 新增 v2 字段（v2ConfigStore / executionEngine / outputDispatcher 等 12 个），改 `init` 为 `static func bootstrap() async throws -> AppContainer`；**保留** v1 装配字段（configStore / toolExecutor）不动。Task 4 不允许独立提交，也不允许停在 broken state 后标记完成；必须继续完成 Task 5 的 AppDelegate async bootstrap 后，C+D 作为同一原子 commit 通过 4 关 CI gate。

**Files:**
- Modify: `SliceAIApp/AppContainer.swift`（当前 ~100 行 → ~250 行；改 init → bootstrap）
- Modify: `SliceAIApp/AppDelegate.swift`（`AppDelegate.init()` 内 `container = AppContainer()` 调用改为延后到 Task 5 处理）

- [ ] **Step 1: 改写 AppContainer.swift**

完全覆盖 `SliceAIApp/AppContainer.swift`：

```swift
// SliceAIApp/AppContainer.swift
import AppKit
import Capabilities
import DesignSystem
import Foundation
import HotkeyManager
import LLMProviders
import Orchestration
import Permissions
import SelectionCapture
import SettingsUI
import SliceCore
import Windowing

/// 应用的依赖注入组合根（Composition Root）。
///
/// 职责：
///   - 在应用启动的单点集中创建所有跨模块依赖，避免在业务层四处分散 init
///   - 对外暴露只读属性，让 AppDelegate 在整个生命周期内持有并读取
///   - 通过显式依赖注入，使 Swift 6 严格并发下的 Sendable 边界清晰可控
///
/// 线程模型：@MainActor 限定，保证所有 UI 面板 / 监视器的创建都发生在主线程。
/// 生命周期：由 AppDelegate.applicationDidFinishLaunching 内异步调用 bootstrap() 创建一次，随进程存活。
///
/// **M3.1 additive 装配状态**（F5.1）：
/// - v1 既有装配（configStore / toolExecutor）保留不动；触发链 AppDelegate.execute 仍调 v1
/// - v2 additive 加入（v2ConfigStore / executionEngine / outputDispatcher 等 12 个字段）；M3.1 期间无 caller 调用
/// - M3.0 Step 1 才把 caller 切到 v2 + 删 v1 字段
@MainActor
final class AppContainer {

    // MARK: - v1 既有装配（M3.1 保留；M3.0 Step 1 删字段引用，Step 2 git rm 物理文件）

    /// v1 配置文件读写 actor；路径固定为 ~/Library/Application Support/SliceAI/config.json
    let configStore: FileConfigurationStore
    /// v1 工具执行中枢；M3.0 Step 1 caller 切换后删字段，Step 2 git rm
    let toolExecutor: ToolExecutor

    // MARK: - 既有跨层依赖（不动）

    /// macOS Keychain 读写结构体
    let keychain: KeychainStore
    /// 选中文字捕获协调器
    let selectionService: SelectionService
    /// 全局快捷键注册器（Carbon）
    let hotkeyRegistrar: HotkeyRegistrar
    /// 划词浮条面板
    let floatingToolbar: FloatingToolbarPanel
    /// 命令面板
    let commandPalette: CommandPalettePanel
    /// 流式结果面板
    let resultPanel: ResultPanel
    /// 辅助功能权限轮询监视器
    let accessibilityMonitor: AccessibilityMonitor
    /// 设置界面视图模型
    let settingsViewModel: SettingsViewModel
    /// 主题管理器
    let themeManager: ThemeManager

    // MARK: - v2 additive 装配（M3.1 新增；M3.0 Step 1 后被 caller 调用）

    /// v2 配置文件读写 actor；路径 = config-v2.json；含 first-launch migrator
    /// M3.0 Step 1 删 v1 后 rename 为 configStore；M3.0 Step 3 类型 → ConfigurationStore
    let v2ConfigStore: V2ConfigurationStore
    /// 执行引擎 actor；含 10 依赖
    let executionEngine: ExecutionEngine
    /// chunk 路由 dispatcher
    let outputDispatcher: any OutputDispatcherProtocol
    /// F9.2 / F3.4 R3 single-flight gate；同一实例被 adapter + AppDelegate 共用
    let invocationGate: InvocationGate
    /// chunk → ResultPanel adapter（持有 invocationGate + 委托）
    let resultPanelAdapter: ResultPanelWindowSinkAdapter
    /// LLM provider 工厂（v1 toolExecutor + v2 promptExecutor 共用一个 instance）
    let llmProviderFactory: any LLMProviderFactory

    // MARK: - 私有初始化（外部用 bootstrap() 创建）

    private init(
        configStore: FileConfigurationStore,
        toolExecutor: ToolExecutor,
        keychain: KeychainStore,
        selectionService: SelectionService,
        hotkeyRegistrar: HotkeyRegistrar,
        floatingToolbar: FloatingToolbarPanel,
        commandPalette: CommandPalettePanel,
        resultPanel: ResultPanel,
        accessibilityMonitor: AccessibilityMonitor,
        settingsViewModel: SettingsViewModel,
        themeManager: ThemeManager,
        v2ConfigStore: V2ConfigurationStore,
        executionEngine: ExecutionEngine,
        outputDispatcher: any OutputDispatcherProtocol,
        invocationGate: InvocationGate,
        resultPanelAdapter: ResultPanelWindowSinkAdapter,
        llmProviderFactory: any LLMProviderFactory
    ) {
        self.configStore = configStore
        self.toolExecutor = toolExecutor
        self.keychain = keychain
        self.selectionService = selectionService
        self.hotkeyRegistrar = hotkeyRegistrar
        self.floatingToolbar = floatingToolbar
        self.commandPalette = commandPalette
        self.resultPanel = resultPanel
        self.accessibilityMonitor = accessibilityMonitor
        self.settingsViewModel = settingsViewModel
        self.themeManager = themeManager
        self.v2ConfigStore = v2ConfigStore
        self.executionEngine = executionEngine
        self.outputDispatcher = outputDispatcher
        self.invocationGate = invocationGate
        self.resultPanelAdapter = resultPanelAdapter
        self.llmProviderFactory = llmProviderFactory
    }

    /// 异步装配所有依赖；F3.1 修订 — async throws 因含 try await v2ConfigStore.current()
    static func bootstrap() async throws -> AppContainer {
        let appSupport = try makeAppSupportDir()

        // === v1 既有装配（M3.0 Step 1 才删） ===

        let configStore = FileConfigurationStore(fileURL: FileConfigurationStore.standardFileURL())
        let keychain = KeychainStore()

        // F6.2 / F7.1 / F9.1：M2 已落地无参 init；v1 toolExecutor + v2 promptExecutor 复用一个 instance；M3.0 Step 2 升级 protocol 接收 V2Provider
        let llmProviderFactory: any LLMProviderFactory = OpenAIProviderFactory()

        let toolExecutor = ToolExecutor(
            configurationProvider: configStore,
            providerFactory: llmProviderFactory,
            keychain: keychain
        )

        // === 既有跨层依赖 ===

        let selectionService = SelectionService(
            primary: AXSelectionSource(),
            fallback: ClipboardSelectionSource(
                pasteboard: SystemPasteboard(),
                copyInvoker: SystemCopyKeystrokeInvoker(),
                focusProvider: { @MainActor in
                    guard let app = NSWorkspace.shared.frontmostApplication else { return nil }
                    return FocusInfo(
                        bundleID: app.bundleIdentifier ?? "",
                        appName: app.localizedName ?? "",
                        url: nil,
                        screenPoint: NSEvent.mouseLocation
                    )
                }
            )
        )

        let hotkeyRegistrar = HotkeyRegistrar()
        let floatingToolbar = FloatingToolbarPanel()
        let commandPalette = CommandPalettePanel()
        let resultPanel = ResultPanel()
        let accessibilityMonitor = AccessibilityMonitor()
        let settingsViewModel = SettingsViewModel(store: configStore, keychain: keychain)
        let themeManager = ThemeManager(initialMode: .auto)

        let store = configStore
        themeManager.onModeChange = { @MainActor mode in
            Task { try? await store.updateAppearance(mode) }
        }

        // === v2 additive 装配（M3.1 新增）===

        let v2URL = appSupport.appendingPathComponent("config-v2.json")
        let legacyURL = appSupport.appendingPathComponent("config.json")
        let v2ConfigStore = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: legacyURL)

        // 触发 first-launch 写盘（含 §3.3 修订的 default 写盘 + 自动 migrator）
        // ★ Task 1 (Sub-step A) 已让 load() 在 both-missing 分支写盘；这里只是触发
        _ = try await v2ConfigStore.current()

        // F7.1：真实 init 是 (providers: [String: any ContextProvider])；v0.2 空 dict
        // builtin selection 由 ExecutionEngine.runMainFlow 内部组装 ResolvedExecutionContext.selection 提供，不走 registry
        let providerRegistry = ContextProviderRegistry(providers: [:])

        let contextCollector = ContextCollector(registry: providerRegistry)
        let permissionGraph = PermissionGraph(providerRegistry: providerRegistry)

        // F1.2：真实类型是 PermissionBroker（不是 DefaultPermissionBroker）；store 默认 PermissionGrantStore()
        let permissionBroker: any PermissionBrokerProtocol = PermissionBroker(store: PermissionGrantStore())

        // F1.2：真实参数名 configurationProvider；类型 @Sendable @escaping () async throws -> V2Configuration
        let providerResolver: any ProviderResolverProtocol = DefaultProviderResolver(
            configurationProvider: { [v2ConfigStore] in try await v2ConfigStore.current() }
        )

        // F1.2：真实 init (keychain: any KeychainAccessing, llmProviderFactory: any LLMProviderFactory)
        let promptExecutor = PromptExecutor(keychain: keychain, llmProviderFactory: llmProviderFactory)

        // F1.2：M2 已落地 production-side Mock；v0.2 仍用 Mock；Phase 1 / 2 接真实
        let mcpClient: any MCPClientProtocol = MockMCPClient()
        let skillRegistry: any SkillRegistryProtocol = MockSkillRegistry()

        // F1.2：CostAccounting / JSONLAuditLog 是 throwing init；上抛
        let costAccounting = try CostAccounting(dbURL: appSupport.appendingPathComponent("cost.sqlite"))
        let auditLog: any AuditLogProtocol = try JSONLAuditLog(fileURL: appSupport.appendingPathComponent("audit.jsonl"))

        // F9.2 / F3.4 R3：先建 InvocationGate（Orchestration target），让 adapter + AppDelegate 共用同一实例
        let invocationGate = InvocationGate()
        let resultPanelAdapter = ResultPanelWindowSinkAdapter(panel: resultPanel, gate: invocationGate)
        let outputDispatcher: any OutputDispatcherProtocol = OutputDispatcher(windowSink: resultPanelAdapter)

        // F1.2：真实 init 含 10 个依赖
        let executionEngine = ExecutionEngine(
            contextCollector: contextCollector,
            permissionBroker: permissionBroker,
            permissionGraph: permissionGraph,
            providerResolver: providerResolver,
            promptExecutor: promptExecutor,
            mcpClient: mcpClient,
            skillRegistry: skillRegistry,
            costAccounting: costAccounting,
            auditLog: auditLog,
            output: outputDispatcher
        )

        return AppContainer(
            configStore: configStore,
            toolExecutor: toolExecutor,
            keychain: keychain,
            selectionService: selectionService,
            hotkeyRegistrar: hotkeyRegistrar,
            floatingToolbar: floatingToolbar,
            commandPalette: commandPalette,
            resultPanel: resultPanel,
            accessibilityMonitor: accessibilityMonitor,
            settingsViewModel: settingsViewModel,
            themeManager: themeManager,
            v2ConfigStore: v2ConfigStore,
            executionEngine: executionEngine,
            outputDispatcher: outputDispatcher,
            invocationGate: invocationGate,
            resultPanelAdapter: resultPanelAdapter,
            llmProviderFactory: llmProviderFactory
        )
    }

    /// 创建 ~/Library/Application Support/SliceAI/ 目录（若不存在）
    private static func makeAppSupportDir() throws -> URL {
        // swiftlint:disable:next force_unwrapping
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("SliceAI", isDirectory: true)
        if !FileManager.default.fileExists(atPath: appSupport.path) {
            try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        }
        return appSupport
    }
}
```

- [ ] **Step 2: 继续完成 Task 5 后统一验证**

不在此处单独运行 xcodebuild，也不把 "AppDelegate 尚未改导致无法找到 AppContainer init" 当成可接受完成态。AppContainer 改造会改变启动装配边界，必须与 Task 5 的 AppDelegate async bootstrap 同时落地后再跑 4 关 CI gate。

如果实现过程中需要局部检查，仅允许用编辑器 / Swift 语法检查定位 AppContainer.swift 自身错误；正式验收一律在 Task 5 Step 5 完成。

- [ ] **Step 3: 暂时让 AppDelegate 编译通过（占位）**

为让 xcodebuild 暂时通过，在 `SliceAIApp/AppDelegate.swift` 找到 `init()` 内的 `container = AppContainer()`，临时改为：

```swift
// 临时占位（Task 5 改为 async bootstrap）
container = AppContainer.makeStub()
```

但 makeStub() 不存在，所以需要在 AppContainer.swift 加临时 stub method 或者直接做 Task 5。

**KISS 决策**：跳过本 step，继续到 Task 5（AppDelegate async bootstrap）。AppContainer.swift 与 AppDelegate.swift 的 bootstrap 改造合并到 Task 5 的同一个 commit 跑 4 关 CI gate。

> **note**: Task 4 不单独 commit、不单独标记完成；改动留在 working tree 等 Task 5 一起 commit。C+D 的原子边界来自 mini-spec R11，对齐 "每个 commit 四关绿" 不变量。

---

## Task 5: M3.1 Sub-step D — AppDelegate async bootstrap UX（提交 Task 4+5 原子改动）【F2.4 + F3.1】

**目标**：让 `AppDelegate.init()` 同步只初始化空状态；`applicationDidFinishLaunching(_:)` 启 `Task { @MainActor in try await AppContainer.bootstrap(); ... }` 跑 bootstrap；catch 走 NSAlert + terminate。**触发链 execute(tool:payload:) 不动**——M3.1 期间仍调 v1 toolExecutor。本 task 负责把 Task 4 的 AppContainer 改动一起收口为可编译、可提交状态。

**Files:**
- Modify: `SliceAIApp/AppDelegate.swift`（init + applicationDidFinishLaunching；触发链不动）

- [ ] **Step 1: 读 AppDelegate 当前 init / applicationDidFinishLaunching 区段**

Run: `grep -n "container =\|func application\|override init\|reloadHotkey\|MenuBarController(\|accessibilityMonitor\.startMonitoring\|cfg\.appearance\|themeManager\.setMode\|applyAppearanceToAllWindows\|startTrackingTheme" SliceAIApp/AppDelegate.swift | head -30`

记录关键行号（按当前真实代码：`override init()` 在 line 65；`applicationDidFinishLaunching` 在 line 67-93；`wireRuntime` 在 line 131；`reloadHotkey` 在 line 154；`execute(tool:payload:)` 在 line 331；`showSettings` 在 line 389）。

- [ ] **Step 2: 改 AppDelegate 顶部 stored property + init**

把 AppDelegate class 顶部既有 `let container: AppContainer`（line 26）改为：

```swift
/// 异步装配的依赖容器；启动 Task 完成前为 nil
private(set) var container: AppContainer?
/// 启动 Task；保留引用以便 cancel（理论上不会取消，仅供 audit）
private var startupTask: Task<Void, Never>?
```

把既有 `override init()`（line 64-67，body 是 `self.container = AppContainer(); super.init()`）改为：

```swift
override init() {
    super.init()
    // 同步只初始化空状态；不调任何 async / throwing 代码
    // bootstrap 在 applicationDidFinishLaunching 内的 startupTask 完成
}
```

- [ ] **Step 3: 改 applicationDidFinishLaunching — 完整替换 line 67-93 函数体**

定位既有 `func applicationDidFinishLaunching(_ notification: Notification)`（line 67-93），把整段函数体（含菜单栏创建 / 权限轮询启动 / trusted 分流 / Theme Task）替换为下面的 async bootstrap + completeStartup 双段；旧逻辑全部搬到 `completeStartup`，禁止用 ellipsis 占位：

```swift
func applicationDidFinishLaunching(_ notification: Notification) {
    Self.log.info("applicationDidFinishLaunching (async bootstrap)")

    // 启动期 UI 状态："启动中"——菜单栏 icon 暂不创建 / 划词不响应 / Settings 不可开
    // 通常 < 1s（sqlite open + jsonl 创建 + config-v2.json 读盘）；超过 5s 是异常
    startupTask = Task { @MainActor in
        do {
            let container = try await AppContainer.bootstrap()
            self.container = container
            // 装配完成：执行既有 v1 启动逻辑（rename 自原 applicationDidFinishLaunching 的同步部分）
            self.completeStartup(container: container)
        } catch {
            self.showStartupErrorAlertAndExit(error)
        }
    }
}

/// 装配完成后触发既有 v1 启动逻辑（rename 自 line 67-93 内联代码）
///
/// 真实代码完整迁移；不允许任何 ellipsis 占位。逐项对应：
/// - line 71-72 → 1. 菜单栏控制器
/// - line 74-83 → 2. 权限监控 + onboarding/wireRuntime 分流
/// - line 87-92 → 3. ThemeManager 主题装配（注意：字段名是 `cfg.appearance` 不是 `appearanceMode`）
private func completeStartup(container: AppContainer) {
    // 1. 菜单栏图标与菜单；创建后立即评估 provider 配置状态（是否需要显示小红点）
    menuBarController = MenuBarController(container: container, delegate: self)
    menuBarController?.refreshConfigStateIndicator()

    // 2. 权限监控：先启动轮询再根据当前状态分流
    //    未授予辅助功能 → 展示 onboarding；授予后再 wireRuntime（含 reloadHotkey + 鼠标监视器）
    container.accessibilityMonitor.startMonitoring()
    let trusted = container.accessibilityMonitor.isTrusted
    Self.log.info("AX trusted=\(trusted, privacy: .public)")
    if !trusted {
        Self.log.info("showOnboarding (AX not trusted)")
        showOnboarding()
    } else {
        wireRuntime()  // 内部调用 reloadHotkey() + 安装鼠标监视器
    }

    // 3. 异步同步 ThemeManager 初始模式（init 是同步的无法 await），并启动主题跟踪
    //    注意：configStore.current() 返回 V2Configuration，字段名是 `appearance` 不是 `appearanceMode`
    Task { @MainActor [weak self] in
        guard let self else { return }
        // 经 Task 7 Iteration G 改造后，configStore.current() 抛错；UI catch skip 不抢屏
        do {
            let cfg = try await container.configStore.current()
            container.themeManager.setMode(cfg.appearance)
            self.applyAppearanceToAllWindows()
            self.startTrackingTheme()
        } catch {
            // F8.2 UI 路径策略：log skip 不弹 alert（避免抢屏；用户配置损坏走启动 NSAlert 链路兜底）
            Self.log.warning("themeManager bootstrap skipped: \(error.localizedDescription, privacy: .private)")
        }
    }
}

/// 启动失败：弹 NSAlert + terminate
private func showStartupErrorAlertAndExit(_ error: Error) {
    let alert = NSAlert()
    alert.messageText = "SliceAI 启动失败"
    alert.informativeText = (error as? SliceError)?.userMessage ?? error.localizedDescription
    alert.addButton(withTitle: "退出")
    alert.runModal()
    NSApp.terminate(nil)
}
```

> **note**：本 task M3.1 阶段只改 `applicationDidFinishLaunching` + `init`，**不动 `wireRuntime` / `reloadHotkey` / `execute(tool:payload:)`**。其中 `reloadHotkey()`（不是 `registerHotkey()` — 真实方法名）继续静默吞错（CLAUDE.md "无自由日志" 规范）。`execute(tool:payload:)` 在 Task 7 Iteration D 才切到 ExecutionEngine。

- [ ] **Step 4: 把所有 `container.xxx` 调用前加 `guard let container = self.container else { return }`**

由于 `container` 现在是 Optional，所有引用必须做 nil check（仅 M3.1 期间；M3.0 Step 1 后 wireRuntime / execute 一并 audit）。grep 找出所有 `container.` 引用：

```
grep -n "container\." SliceAIApp/AppDelegate.swift
```

预期 callsite（按真实代码 line 序）：
- line 71（已在 completeStartup 内）：`MenuBarController(container: container, ...)`
- line 76：`container.accessibilityMonitor.startMonitoring()`
- line 89：`self.container.themeManager.setMode(...)` / `self.container.configStore.current()`
- line 131-153 wireRuntime / line 154-228 reloadHotkey 等：M3.1 期间这些 callsite 由 `wireRuntime()` 在 trusted 分支后才被调用，那时 `self.container` 已经赋值；但仍需对每个 `self.container.xxx` 加 `guard let container = self.container else { return }`

对每个新增的 outer-method callsite（`wireRuntime()` / `reloadHotkey()` / `execute(...)` / `showSettings()` / `installMouseMonitor()` 等），在方法体顶部加：

```swift
// 改前（举例 reloadHotkey 顶部）：
//   let cfg = await self.container.configStore.current()
// 改后：
guard let container = self.container else { return }
let cfg = await container.configStore.current()  // 注：try await 由 Task 7 Iteration G 一起加
```

> **note**：`completeStartup(container:)` 内已显式接收 container 参数，无需 guard；外部方法（wireRuntime / reloadHotkey 等）才需 guard。M3.1 期间不动 try await（暂沿用既有 await）；Task 7 Iteration G 一并加 try await + catch。

- [ ] **Step 5: 验证 4 关 CI gate**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
Expected: All PASS, 0 violations

- [ ] **Step 6: 实机启动冒烟（手工）**

```bash
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
open build/Build/Products/Debug/SliceAI.app   # 路径按 xcodebuild 输出调整
```

期望：
- App 启动不崩；菜单栏出现图标
- 触发 ⌥Space 命令面板能弹出
- 划词触发能出 v1 ResultPanel（v1 触发链仍在工作）
- ~/Library/Application Support/SliceAI/ 下出现 cost.sqlite / audit.jsonl / config-v2.json 三个新文件

实测：

```
ls -la ~/Library/Application\ Support/SliceAI/
```
应当看到：config.json (v1 既有) + config-v2.json (新建) + cost.sqlite (新建) + audit.jsonl (新建)

- [ ] **Step 7: Commit M3.1.C + D 合并**

```bash
git add SliceAIApp/AppContainer.swift SliceAIApp/AppDelegate.swift
git commit -m "$(cat <<'EOF'
feat(sliceaiapp): additive ExecutionEngine wiring + async AppDelegate bootstrap UX

- AppContainer.bootstrap() async throws：v1 装配保留 + v2 additive 装配（v2ConfigStore /
  executionEngine / outputDispatcher / resultPanelAdapter / 10 个依赖；MCP/Skill 仍 Mock；
  PermissionBroker 用 production-side default-allow + audit）
- AppDelegate：sync init 只初始化空状态；applicationDidFinishLaunching 启 Task 跑
  bootstrap；catch → NSAlert + terminate；触发链 execute(tool:payload:) 仍调 v1 toolExecutor
- M3.1 期间无 caller 调用 v2 装配（M3.0 Step 1 才切换）；v1 触发链全程可用

F1.2 + F2.1 + F2.4 + F3.1 + F5.1 修订；M3.1 Sub-step C + D 合并 commit。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 6: M3.1 Sub-step E — M3.1 冒烟验证（DoD 锁定）

**目标**：Run M3.1 Exit DoD 全部 checklist；任一失败回 Task 4/5 修。

**Files:** （无代码改动；仅验证）

- [ ] **Step 1: 4 关 CI gate**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```

- [ ] **Step 2: 验证 v1 装配字段保留**

```
grep -n "let configStore: FileConfigurationStore\|let toolExecutor: ToolExecutor" SliceAIApp/AppContainer.swift
```
Expected: 两个声明都存在

- [ ] **Step 3: 验证 v2 装配字段新增**

```
grep -n "let v2ConfigStore: V2ConfigurationStore\|let executionEngine: ExecutionEngine\|let outputDispatcher\|let resultPanelAdapter" SliceAIApp/AppContainer.swift
```
Expected: 4 个声明都存在

- [ ] **Step 4: 验证 v1 触发链仍工作（手工实机）**

启动 app → 在 Safari 选中文字 → 浮条出现 → 点 "Translate" → ResultPanel 出流式 token。
预期：与 v0.1 视觉等价。

⌥Space → 命令面板弹出 → 选工具 → ResultPanel 出流式 token。
预期：与 v0.1 视觉等价。

- [ ] **Step 5: 验证文件创建**

```
ls -la ~/Library/Application\ Support/SliceAI/
```
Expected: 含 config.json (v1) + config-v2.json (新) + cost.sqlite (新) + audit.jsonl (新)

```
cat ~/Library/Application\ Support/SliceAI/config-v2.json | head -30
```
Expected: 含 4 个内置工具默认配置 (Translate / Polish / Summarize / Explain)

- [ ] **Step 6: 验证 v2 caller 数 = 0**

```
grep -n "container.executionEngine\|container.outputDispatcher\|container.v2ConfigStore" SliceAIApp/
```
Expected: 0 匹配（除装配点外无任何 caller；M3.0 Step 1 才接通触发链）

- [ ] **Step 7: 验证启动失败 UX（手工模拟）**

```bash
APP_SUPPORT="$HOME/Library/Application Support/SliceAI"
mkdir -p "$APP_SUPPORT"
ORIG_MODE="$(stat -f '%Lp' "$APP_SUPPORT")"
chmod 555 "$APP_SUPPORT"
open build/Build/Products/Debug/SliceAI.app
```
Expected: App 启动后弹 NSAlert "SliceAI 启动失败" + 描述；点退出后 dock icon 立即消失。

测完后：

```bash
chmod "$ORIG_MODE" "$APP_SUPPORT"
```

如果 alert 不出 → 回 Task 5 检查 `showStartupErrorAlertAndExit` 实现。

- [ ] **Step 8: M3.1 标记完成**

无 commit（本 task 仅验证）；如果 Step 1-7 全过 → M3.1 完成；进 M3.0 Step 1。

---

## Task 7: M3.0 Step 1 — caller 切换 + AppDelegate ExecutionEngine + audit + 数据 binding（单 commit）

**目标**：把 SliceAIApp + SettingsUI + Windowing + Tests 中所有 v1 类型引用切到 V2*；AppDelegate.execute 改调 ExecutionEngine（含 ordering + single-flight）；audit 7 处 configStore.current() callsite；删 AppContainer v1 装配字段；零文件删除 + 零 rename；中间态完全可编译。

> **D-26 + 用户初审 Q3 决策 A**：本 task 是单 commit；内部 dev iteration A-J 不分别 commit，全部改完一次性 commit。Iteration 顺序按编译依赖：先做 helper 类（A-C） → 再改 caller（D-G） → 再删字段（H） → 再加 spy tests（I） → 最后 4 关 CI gate（J）。

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/SliceError.swift`（新增 .execution(ExecutionError) 顶层 case + ExecutionError 子枚举；F1.1 R1 修订）
- Create: `SliceAIApp/ExecutionEventConsumer.swift`（~120 行）
- Modify: `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift`（D-30b non-window fallback）
- Modify: `SliceAIKit/Sources/SliceCore/SelectionPayload.swift`（加 toExecutionSeed extension + Source.toSelectionOrigin）
- Modify: `SliceAIApp/AppDelegate.swift`（execute 触发链改造 + 7 处 configStore.current() audit + 顶部加 streamTask stored property）
- Modify: `SliceAIApp/MenuBarController.swift`（1 处 configStore.current() audit）
- Modify: `SliceAIApp/AppContainer.swift`（删 v1 装配字段 + rename v2ConfigStore → configStore）
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`（store 类型切到 V2ConfigurationStore + loadError state）
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`（ViewModel 类型跟随）
- Modify: `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`（addTool 内 v1 `Tool(...)` 改为 V2Tool；F1.2 R1 修订真实位置）
- Modify: `SliceAIKit/Sources/SettingsUI/Pages/ProvidersSettingsPage.swift`（addProvider 内 v1 `Provider(...)` 改为 V2Provider；F1.2 R1 修订真实位置）
- Modify: `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Row.swift`（Row VM 改吃 V2Tool）
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`（V2Tool / PromptTool 字段 binding）
- Modify: `SliceAIKit/Sources/SettingsUI/ProviderEditorView.swift`（V2Provider 字段 binding）
- Modify: `SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift`（show 签名从 `[Tool]/(Tool) -> Void` 切到 `[V2Tool]/(V2Tool) -> Void`；F1.2 R1）
- Modify: `SliceAIKit/Sources/Windowing/CommandPalettePanel.swift`（show 签名从 `[Tool]/(Tool) -> Void` 切到 `[V2Tool]/(V2Tool) -> Void`；F1.2 R1）
- Create: `SliceAIKit/Tests/OrchestrationTests/AdapterContractTests/ExecutionStreamOrderingTests.swift`（~110 行；F3.4 R3：fake stream + 真实 InvocationGate ordering 测试）
- Create: `SliceAIKit/Tests/OrchestrationTests/AdapterContractTests/SingleWriterContractTests.swift`（~50 行；OutputDispatcher 单一写入契约）
- Create: `SliceAIKit/Tests/OrchestrationTests/Output/OutputDispatcherFallbackTests.swift`（~120 行）
- ~~Create: `SliceAIKit/Tests/OrchestrationTests/AdapterContractTests/SingleFlightInvocationTests.swift`~~（F3.4 R3 删除——SpyAdapter copy 模式假阳性；single-flight 测试由 Task 3 InvocationGateTests.swift 直接测真实 gate 替代）

> **F1.2 R1 修订记录**：addTool / addProvider 的真实位置不在 SettingsViewModel.swift，而在 `Pages/ToolsSettingsPage.swift:270` / `Pages/ProvidersSettingsPage.swift:200`。FloatingToolbarPanel + CommandPalettePanel `show` 函数签名仍用 v1 `Tool` 类型（grep 验证：`SliceAIKit/Sources/Windowing/{FloatingToolbarPanel,CommandPalettePanel}.swift` line 27/57），必须在本 task 同 commit 切到 V2Tool，否则 v1 Tool 在 Task 8 删除后整个 Windowing target 编译失败。

### Iteration A0: 新增 SliceError.execution + 同步 InvocationOutcome.ErrorKind 全仓 exhaustive audit【F1.1 R1 前置依赖 + F2.1 R2 修订】

**目标**：ExecutionEventConsumer 翻译 `.notImplemented` / catch-all `unknown` 时需要 `SliceError.execution(.notImplemented(...))` / `.execution(.unknown(...))`，但当前 SliceError 只有 6 个顶层 case，**没有 .execution**。必须在 Iteration A 之前同 commit 加上。

> **F2.1 R2 修订**：新增顶层 case 影响**全仓 exhaustive switch on SliceError**——真实 `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift:134-143` 的 `InvocationOutcome.ErrorKind.from(_:)` 是 exhaustive switch（无 default），新增 .execution 后立即编译失败。同时按 CLAUDE.md "对带 String payload 的 case 一律输出 <redacted>" 规则，`.notImplemented(String)` / `.unknown(String)` 在 developerContext 一律脱敏（不要假设 spec 内 reason 字符串将来不会拼入外部错误）。

- [ ] **Step A0.0: grep 全仓 exhaustive switch on SliceError 找改造点**

> **audit-fix 2026-04-29**：旧 grep 用单行 alternation `case \.selection.*\bcase \.provider\b` 命中不到——Swift switch case 跨多行写。改为 §Iteration J Step J0 gate 2 同款 `rg -A 12 + awk 块解析` 模式（命中 switch 所在文件 + 后 12 行的 case 列表）：

```bash
# 任何对 SliceError 做 switch 的位置；新增顶层 case 后都要更新
# 第一遍：找出 switch on SliceError 的 file:line 入口
rg -n "switch[^{]*\b(SliceError|sliceError)\b" SliceAIKit/Sources/ SliceAIKit/Tests/ --type swift

# 第二遍：找出"包含 case .selection 但缺 case .execution"的不合规 switch（multi-line 块解析）
# 对照 §Iteration J Step J0 gate 2 完整脚本——本步骤手工跑一次相同 awk 逻辑即可
rg -n "switch[^{]*\b(SliceError|sliceError)\b" SliceAIKit/Sources/ SliceAIKit/Tests/ --type swift -A 12 | awk '
  /^--/ {
    if (block && block ~ /case[ \t]+\.selection/ && block !~ /case[ \t]+\.execution/) print block
    block = ""; next
  }
  { block = block $0 "\n" }
  END {
    if (block && block ~ /case[ \t]+\.selection/ && block !~ /case[ \t]+\.execution/) print block
  }
'
```

R1+R2 时点已知必须改造的 exhaustive switch 列表：
1. `SliceCore/SliceError.swift:16-23` — `userMessage` switch（A0.2 改）
2. `SliceCore/SliceError.swift:28+` — `developerContext` switch（A0.2 改）
3. `Orchestration/Events/InvocationReport.swift:134-143` — `InvocationOutcome.ErrorKind.from(_:)`（A0.4 改 + 同步加 ErrorKind.execution case）

implementer 实施时再跑一次 awk multi-line 块解析确保 R2 后无新增 exhaustive switch；落地后 §Iteration J Step J0 gate 2 会用完全一致的 awk 模式做 CI 兜底。

- [ ] **Step A0.1: 在 SliceError.swift 顶部 6 个 case 之后追加 .execution**

定位 `SliceAIKit/Sources/SliceCore/SliceError.swift` 内 `public enum SliceError: Error, Sendable, Equatable {`（line 4），在 `case toolPermission(ToolPermissionError)`（line 12）之后追加：

```swift
    /// 执行链非业务错误：not-implemented 边界 / 未分类异常 fallback
    case execution(ExecutionError)
```

文件**末尾**追加新枚举：

```swift
/// 执行链顶层错误（与 ExecutionEvent 流的 .notImplemented / catch-all unknown 对接）
public enum ExecutionError: Error, Sendable, Equatable {
    /// spec 设计期声明的 not-implemented 边界（如 v0.2 .skill / .agent / structured output）
    case notImplemented(String)
    /// 非 SliceError / 非 CancellationError 的 catch-all 兜底；reason 已脱敏的 localizedDescription
    case unknown(String)

    /// 用户可见文案——userMessage 可包含 reason（已经过脱敏：notImplemented reason 由 spec 内
    /// 固定字符串提供；unknown reason 来自 localizedDescription，调用方决定是否展示完整给用户）
    public var userMessage: String {
        switch self {
        case .notImplemented(let r):
            return "该能力在当前版本（v0.2）尚未实现：\(r)。请等待后续版本。"
        case .unknown:
            return "执行过程中发生未知错误，请稍后重试或联系支持。"
        }
    }
}
```

- [ ] **Step A0.2: 同步 SliceError.userMessage / developerContext switch — 加 .execution 分支（统一脱敏 String payload）**

在既有 `var userMessage: String` switch 末尾追加：

```swift
        case .execution(let e): return e.userMessage
```

在既有 `var developerContext: String` switch 末尾追加（**两个 sub-case 均脱敏**——CLAUDE.md "对带 String payload 一律输出 <redacted>"）：

```swift
        case .execution(let e):
            switch e {
            case .notImplemented: return "execution.notImplemented(<redacted>)"  // reason 来自外部 case 描述，统一脱敏
            case .unknown: return "execution.unknown(<redacted>)"  // reason 来自外部 error.localizedDescription，脱敏
            }
        }
```

> **note F2.1 R2**：注意 `.notImplemented` developerContext 不再原样 echo `r`——避免后续 reason 一旦拼入用户配置 / 外部错误流入日志。CLAUDE.md "无自由日志 + 脱敏" 规范是无条件规则；不要给"reason 是固定字符串"开后门。

- [ ] **Step A0.3: 加 SliceError 单测覆盖新 case + 脱敏断言（4th-loop R4.X 修订：XCTest 风格与既有文件一致）**

> **4th-loop R4.X 修订（2026-04-30 完整审核）**：旧版本用 Swift Testing `@Test` / `#expect`，但真实 `SliceAIKit/Tests/SliceCoreTests/SliceErrorTests.swift:1-3` 是 `import XCTest` + `final class SliceErrorTests: XCTestCase`，且 `Package.swift` 全部 testTarget 无 swift-testing dep。implementer 把 `@Test` macro 加进 XCTestCase class 内部会 compile fail "Cannot find 'Test' in scope"。**修法**：用 XCTest 风格（`func test_*` + `XCTAssertTrue` / `XCTAssertEqual`）追加到既有 class 末尾。

在 `SliceAIKit/Tests/SliceCoreTests/SliceErrorTests.swift` 既有 `final class SliceErrorTests: XCTestCase { ... }` 内部末尾追加：

```swift
    /// SliceError.execution.notImplemented developerContext 一律脱敏
    func test_executionNotImplemented_redacts() {
        let e = SliceError.execution(.notImplemented("v0.2 不支持 .skill 调用"))
        XCTAssertTrue(e.userMessage.contains("v0.2 不支持"))  // userMessage 允许带 reason
        XCTAssertEqual(e.developerContext, "execution.notImplemented(<redacted>)")  // developerContext 必须脱敏
    }

    /// SliceError.execution.unknown developerContext 脱敏
    func test_executionUnknown_redacts() {
        let e = SliceError.execution(.unknown("API key abc123 leaked"))
        XCTAssertEqual(e.developerContext, "execution.unknown(<redacted>)")
    }
```

Run: `cd SliceAIKit && swift test --filter SliceCoreTests.SliceErrorTests`
Expected: All PASS（含新 2 case）

- [ ] **Step A0.4: 同步 InvocationOutcome.ErrorKind 加 .execution case + 更新 from(_:) exhaustive switch + Tests【F2.1 R2 必修】**

定位 `SliceAIKit/Sources/Orchestration/Events/InvocationReport.swift`：

**改造点 1** — `public enum ErrorKind: String, Sendable, Codable, Equatable` 内 6 case 之后追加（line ~120）：

```swift
        /// 执行链顶层错误（SliceError.execution(ExecutionError)）
        case execution
```

**改造点 2** — `extension InvocationOutcome.ErrorKind { public static func from(_ error: SliceError) -> InvocationOutcome.ErrorKind { switch error { ... } } }`（line 134-143）追加 case：

```swift
        case .execution:      return .execution
```

**改造点 3** — 加 `InvocationReportTests.swift` 单测覆盖（4th-loop R4.X 修订：XCTest 风格统一）：

在 `SliceAIKit/Tests/OrchestrationTests/InvocationReportTests.swift` 既有 `final class InvocationReportTests: XCTestCase { ... }` 内部末尾追加：

```swift
    /// InvocationOutcome.ErrorKind.from maps SliceError.execution to .execution
    func test_errorKindFrom_execution() {
        XCTAssertEqual(InvocationOutcome.ErrorKind.from(.execution(.notImplemented("test"))), .execution)
        XCTAssertEqual(InvocationOutcome.ErrorKind.from(.execution(.unknown("test"))), .execution)
    }

    /// InvocationOutcome.ErrorKind.execution rawValue 持久化稳定
    func test_errorKindExecution_rawValue() {
        // ErrorKind 的 rawValue 写入 AuditLog 持久化；新增 case 不能改 rawValue 字符串
        XCTAssertEqual(InvocationOutcome.ErrorKind.execution.rawValue, "execution")
    }
```

Run: `cd SliceAIKit && swift test --filter OrchestrationTests.InvocationReportTests`
Expected: All PASS（含新 2 case + 既有 case）

> **note F2.1 R2**：ErrorKind 的 rawValue 写入 `AuditLog`（jsonl 持久化）；既有 6 case 的 rawValue 已用于线上数据，新增 .execution 不能误改既有 rawValue。implementer 改完跑 `cd SliceAIKit && swift test --filter OrchestrationTests` 全跑一遍。

### Iteration A: D-30b OutputDispatcher non-window fallback + log 节流

- [ ] **Step A1: 改 OutputDispatcher.handle 5 个 non-window case**

完全替换 `SliceAIKit/Sources/Orchestration/Output/OutputDispatcher.swift` 内的 `handle(...)` 方法 + 加 `loggedInvocations` actor state：

```swift
public actor OutputDispatcher: OutputDispatcherProtocol {

    private let windowSink: any WindowSinkProtocol
    /// F5.3 / D-30b：每个 invocation 仅首次进入 non-window fallback 时 log，避免高频刷屏。
    ///
    /// **v0.2 trade-off**（mini-spec D-30b R5 决议 line 895/901；本 loop Round-6 R6.1 partial-accept 强化警示）：
    /// 本 Set 在 invocation 结束时**不清理**——理由：① v0.2 用户基数小（作者本人 + 早期使用者，archival milestone
    /// 寿命预期 weeks-to-months）+ 每条 UUID 仅 16 bytes，长时间运行实际增长可忽略（300 invocation/月 ≈ 4.8 KB）；
    /// ② Phase 2 BubbleSink/InlineReplaceSink/StructuredSink 等真实 sink 落地后整个 fallback 分支删除，
    /// `loggedInvocations` Set 一并消失，不留内存泄漏。
    ///
    /// **DO NOT** 在 v0.2 引入 ExecutionEngine→OutputDispatcher 的 invocation-lifecycle cleanup 协议来"清理 Set"
    /// （即不要在 .finished / .failed / 取消路径显式 notify OutputDispatcher 删 invocationId）——理由：① 违反
    /// mini-spec D-30b 决议（spec 字面要求"不清理"）+ 偏离 plan-spec convergence；② 引入跨 actor 同步复杂度
    /// （ExecutionEngine actor → OutputDispatcher actor 反向通知协议）= worse problem than 4.8 KB 内存增长；
    /// ③ Phase 2 整个 fallback 删除时该协议反而成为 dead code。如果未来出现 long-running 场景（>10000 invocation）
    /// 内存增长压力，正确做法是直接做完整 Phase 2 真实 sink 替代 fallback（即 mini-spec D-30b "v0.2 → v0.3 / v0.4
    /// 升级"路径），而不是给 v0.2 妥协层加复杂度。
    private var loggedInvocations: Set<UUID> = []

    public init(windowSink: any WindowSinkProtocol) {
        self.windowSink = windowSink
    }

    /// 路由 chunk；window 走 sink；non-window 5 个 case fallback 到 sink + 首 chunk log
    /// D-30b 修订：v0.2 期间所有 mode 都走 windowSink；Phase 2 真实 sink 落地后回滚此分支
    public func handle(
        chunk: String,
        mode: PresentationMode,
        invocationId: UUID
    ) async throws -> DispatchOutcome {
        switch mode {
        case .window:
            try await windowSink.append(chunk: chunk, invocationId: invocationId)
            return .delivered
        case .bubble, .replace, .file, .silent, .structured:
            // D-30b：v0.2 lying UI 妥协——保留 v1 行为（总开 ResultPanel）；首 chunk 节流 log
            if !loggedInvocations.contains(invocationId) {
                loggedInvocations.insert(invocationId)
                // F5.2 R5：仓库 4 处 OSLog 调用都用 `import OSLog` + `Logger(...)`；
                // 不要写 `os.Logger(...)` / `import os.log` —— 与
                // SliceAIKit/Sources/SliceCore/{ConfigMigratorV1ToV2,ConfigurationStore,V2ConfigurationStore}.swift
                // + SliceAIApp/AppDelegate.swift 既有写法保持一致。
                let logger = Logger(subsystem: "com.sliceai.app", category: "outputdispatcher")
                logger.info("OutputDispatcher: mode \(String(describing: mode)) not yet implemented in v0.2; falling back to .window sink")
            }
            try await windowSink.append(chunk: chunk, invocationId: invocationId)
            return .delivered
        }
    }
}
```

记得在文件顶部加 `import OSLog`（**F5.2 R5 修订**：与仓库一致；不用 `import os.log`，那是 C-style overlay 老写法）。

- [ ] **Step A2: 加单测 — 5 个 mode case fallback 验证（4th-loop R4.X 修订：XCTest 风格统一）**

> **4th-loop R4.X 修订（2026-04-30 完整审核）**：旧版本用 Swift Testing `@Suite` / `@Test`，但 OrchestrationTests target 100% XCTest（含既有 OutputDispatcherTests.swift 同目录）。**修法**：用 XCTest 风格，与同目录 OutputDispatcherTests.swift 同模式。

新建 `SliceAIKit/Tests/OrchestrationTests/Output/OutputDispatcherFallbackTests.swift`（~140 行；放到既有 OutputDispatcherTests 同目录）：

```swift
import Foundation
import XCTest
@testable import Orchestration
import SliceCore

/// D-30b：5 个 non-window mode 都 fallback 到 windowSink + 仅首 chunk log
final class OutputDispatcherFallbackTests: XCTestCase {

    actor SpyWindowSink: WindowSinkProtocol {
        var calls: [(chunk: String, invocationId: UUID)] = []

        func append(chunk: String, invocationId: UUID) async throws {
            calls.append((chunk, invocationId))
        }
    }

    /// handle .bubble — fallback to windowSink, returns .delivered
    func test_handle_bubble_fallsBack() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let invocationId = UUID()

        let outcome = try await dispatcher.handle(chunk: "hello", mode: .bubble, invocationId: invocationId)

        XCTAssertEqual(outcome, .delivered)
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].chunk, "hello")
        XCTAssertEqual(calls[0].invocationId, invocationId)
    }

    /// handle .replace — fallback to windowSink, returns .delivered
    func test_handle_replace_fallsBack() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let outcome = try await dispatcher.handle(chunk: "x", mode: .replace, invocationId: UUID())
        XCTAssertEqual(outcome, .delivered)
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 1)
    }

    /// handle .file — fallback to windowSink, returns .delivered
    func test_handle_file_fallsBack() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let outcome = try await dispatcher.handle(chunk: "x", mode: .file, invocationId: UUID())
        XCTAssertEqual(outcome, .delivered)
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 1)
    }

    /// handle .silent — fallback to windowSink, returns .delivered
    func test_handle_silent_fallsBack() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let outcome = try await dispatcher.handle(chunk: "x", mode: .silent, invocationId: UUID())
        XCTAssertEqual(outcome, .delivered)
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 1)
    }

    /// handle .structured — fallback to windowSink, returns .delivered
    func test_handle_structured_fallsBack() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let outcome = try await dispatcher.handle(chunk: "x", mode: .structured, invocationId: UUID())
        XCTAssertEqual(outcome, .delivered)
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 1)
    }

    /// handle .window — direct passthrough, no fallback log
    func test_handle_window_unchanged() async throws {
        let spy = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: spy)
        let invocationId = UUID()
        // 跑 5 次，验证 window 模式每次都 .delivered + windowSink 被调 5 次
        for _ in 0..<5 {
            let outcome = try await dispatcher.handle(chunk: "x", mode: .window, invocationId: invocationId)
            XCTAssertEqual(outcome, .delivered)
        }
        let calls = await spy.calls
        XCTAssertEqual(calls.count, 5)
    }
}
```

Run: `cd SliceAIKit && swift test --filter OrchestrationTests.OutputDispatcherFallbackTests`
Expected: 6 PASS

### Iteration B: SelectionPayload.toExecutionSeed extension + Source.toSelectionOrigin

- [ ] **Step B1: 在 SelectionPayload.swift 加 extension**

在 `SliceAIKit/Sources/SliceCore/SelectionPayload.swift` 文件**末尾**追加（同文件 extension）：

```swift
// MARK: - F2.2 / F1.1 修订：v1 触发层包装 → v2 ExecutionSeed 单一入口

public extension SelectionPayload {
    /// 把 v1 触发层 SelectionPayload 翻译为 v2 ExecutionSeed
    /// - Parameters:
    ///   - triggerSource: 调用方决定是 floatingToolbar / commandPalette / hotkey / shortcutsApp
    ///   - isDryRun: dry-run 模式（v0.2 触发链不走 dry-run；默认 false）
    /// - Note: language / contentType / windowTitle 在 v0.2 一律 nil；Phase 1 加 ContextProvider 后填
    func toExecutionSeed(triggerSource: TriggerSource, isDryRun: Bool = false) -> ExecutionSeed {
        let snapshot = SelectionSnapshot(
            text: text,
            source: source.toSelectionOrigin(),
            length: text.count,
            language: nil,
            contentType: nil
        )
        let appSnapshot = AppSnapshot(
            bundleId: appBundleID,
            name: appName,
            url: url,
            windowTitle: nil
        )
        return ExecutionSeed(
            invocationId: UUID(),
            selection: snapshot,
            frontApp: appSnapshot,
            screenAnchor: screenPoint,
            timestamp: timestamp,
            triggerSource: triggerSource,
            isDryRun: isDryRun
        )
    }
}

public extension SelectionPayload.Source {
    /// 单方向映射 v1 触发层 source → v2 SelectionOrigin
    /// rename pass M3.0 Step 5 完成后类型名变为 SelectionSource，但 case 名不变
    func toSelectionOrigin() -> SelectionOrigin {
        switch self {
        case .accessibility:
            return .accessibility
        case .clipboardFallback:
            return .clipboardFallback
        }
    }
}
```

- [ ] **Step B2: 加单测覆盖 toExecutionSeed（4th-loop R4.X 修订：XCTest 风格统一 + 已存在文件不创建新 class）**

> **4th-loop R4.X 修订（2026-04-30 完整审核）**：旧版本用 Swift Testing `@Suite` / `@Test`，但真实 `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift:1-3` 已存在且是 `import XCTest` + `final class SelectionPayloadTests: XCTestCase`（内含 `test_equatableByAllFields` 等既有测试）。Plan 旧版本"若不存在则创建"分支 + Swift Testing `struct SelectionPayloadToExecutionSeedTests` 都不适用——文件存在 + 风格不兼容会双重 compile fail。**修法**：把 2 个新 test 追加到既有 `final class SelectionPayloadTests: XCTestCase` 内部末尾，复用 class 范围内的 `import XCTest` + `@testable import SliceCore` 顶部声明。

在 `SliceAIKit/Tests/SliceCoreTests/SelectionPayloadTests.swift` 既有 `final class SelectionPayloadTests: XCTestCase { ... }` 内部末尾追加（不需要新 import 也不需要新 class）：

```swift
    /// toExecutionSeed maps all 7 fields correctly
    func test_toExecutionSeed_mapsFields() {
        let payload = SelectionPayload(
            text: "hello world",
            appBundleID: "com.apple.Safari",
            appName: "Safari",
            url: URL(string: "https://example.com"),
            screenPoint: CGPoint(x: 100, y: 200),
            source: .accessibility,
            timestamp: Date(timeIntervalSince1970: 1_000_000)
        )

        let seed = payload.toExecutionSeed(triggerSource: .floatingToolbar)

        XCTAssertEqual(seed.selection.text, "hello world")
        XCTAssertEqual(seed.selection.source, .accessibility)
        XCTAssertEqual(seed.selection.length, 11)
        XCTAssertNil(seed.selection.language)
        XCTAssertNil(seed.selection.contentType)

        XCTAssertEqual(seed.frontApp.bundleId, "com.apple.Safari")
        XCTAssertEqual(seed.frontApp.name, "Safari")
        XCTAssertEqual(seed.frontApp.url?.absoluteString, "https://example.com")
        XCTAssertNil(seed.frontApp.windowTitle)

        XCTAssertEqual(seed.screenAnchor, CGPoint(x: 100, y: 200))
        XCTAssertEqual(seed.timestamp, Date(timeIntervalSince1970: 1_000_000))
        XCTAssertEqual(seed.triggerSource, .floatingToolbar)
        XCTAssertFalse(seed.isDryRun)
    }

    /// toSelectionOrigin maps clipboardFallback
    func test_toSelectionOrigin_clipboardFallback() {
        let source: SelectionPayload.Source = .clipboardFallback
        XCTAssertEqual(source.toSelectionOrigin(), .clipboardFallback)
    }
```

Run: `cd SliceAIKit && swift test --filter SliceCoreTests.SelectionPayloadTests/test_toExecutionSeed_mapsFields SliceCoreTests.SelectionPayloadTests/test_toSelectionOrigin_clipboardFallback`
Expected: 2 PASS（既有 `test_equatableByAllFields` 等也仍 PASS）

### Iteration C: ExecutionEventConsumer helper class（14 case 翻译）

- [ ] **Step C1: 创建 ExecutionEventConsumer.swift（按真实 ExecutionEvent + ResultPanel API）**

写入 `SliceAIApp/ExecutionEventConsumer.swift`。**实施前必须先 cat 真实 enum 校对 case 列表 + label**：

```bash
grep -n "^    case " SliceAIKit/Sources/Orchestration/Events/ExecutionEvent.swift
# 真实 14 case（M2 已合入 main）：
#   started(invocationId:) / contextResolved(key:valueDescription:) / promptRendered(preview:) /
#   llmChunk(delta:) / toolCallProposed(ref:argsDescription:) / toolCallApproved(id:) /
#   toolCallResult(id:summary:) / stepCompleted(step:total:) / sideEffectTriggered(SideEffect) /
#   finished(report:) / failed(SliceError) / notImplemented(reason:) /
#   permissionWouldBeRequested(permission:uxHint:) / sideEffectSkippedDryRun(SideEffect)
```

```swift
// SliceAIApp/ExecutionEventConsumer.swift
import Foundation
import OSLog
import Orchestration
import SliceCore
import Windowing

/// 把 ExecutionEvent stream 翻译为 ResultPanel API 调用
///
/// **F3.2 单一写入所有者**：chunk 写入路径**唯一通过** OutputDispatcher → WindowSink → ResultPanel.append；
/// 本 consumer 在 .llmChunk 事件**仅记日志**，不调 ResultPanel.append（否则同一 chunk 被 append 两次）
///
/// **D-30 14 case 翻译表**（依据 ExecutionEvent.swift 真实 case；R1 修订）：
/// - .started / .contextResolved / .promptRendered / .llmChunk / .toolCallProposed / .toolCallApproved /
///   .toolCallResult / .stepCompleted / .sideEffectTriggered / .sideEffectSkippedDryRun /
///   .permissionWouldBeRequested → 仅记日志
/// - .notImplemented(reason:) → panel.fail(with: .execution(.notImplemented(reason)), nil, nil)
/// - .finished(report:) → panel.finish()
/// - .failed(SliceError) → panel.fail(with: error, onRetry, onOpenSettings)
///
/// **F7.1 R7 — caller 必须 gate**：consumer 自身**不持有 InvocationGate**——
/// caller（`AppDelegate.execute` consumer Task 内）必须在 `consumer.handle(...)` 前
/// 用 `container.invocationGate.shouldAccept(invocationId: invocationId)` guard。
/// 否则在 Regenerate / 连续触发时，A 的 stale `.finished` / `.failed` / `.notImplemented`
/// 会污染 B 已 open 的 panel（chunk 路径已由 R4 `gatedAppend` 保护，但终态事件不经过 sink）。
/// 整段 race 见 codex-loop R7 F7.1 finding；回归测试由 InvocationGateTests + AppDelegate execute
/// integration test 联合覆盖。
@MainActor
final class ExecutionEventConsumer {

    private let logger = Logger(subsystem: "com.sliceai.app", category: "executionevent")
    private let onRetry: @MainActor () -> Void
    private let onOpenSettings: @MainActor () -> Void

    init(
        onRetry: @escaping @MainActor () -> Void,
        onOpenSettings: @escaping @MainActor () -> Void
    ) {
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }

    /// 翻译单个 ExecutionEvent 到 ResultPanel API；exhaustive switch 编译期保证覆盖所有 case
    /// - Note: 函数签名 sync——所有 case 翻译都不 await；调用方在 `for try await event in stream` 内已是 async ctx
    func handle(_ event: ExecutionEvent, panel: ResultPanel) {
        switch event {
        case .started(let invocationId):
            logger.debug("started invocation \(invocationId, privacy: .public)")

        case .contextResolved(let key, let valueDescription):
            // ContextKey 是 SliceCore 类型；按真实定义可能是 enum 而非 RawRepresentable，使用 description 兜底
            logger.debug("contextResolved key=\(String(describing: key), privacy: .public) preview=\(valueDescription, privacy: .private)")

        case .promptRendered(let preview):
            logger.debug("promptRendered preview=\(preview, privacy: .private)")

        case .llmChunk(let delta):
            // F3.2：chunk 不在此处写 ResultPanel.append——唯一写入路径走 OutputDispatcher → WindowSink → ResultPanel
            logger.debug("llmChunk delta length=\(delta.count, privacy: .public)")

        case .toolCallProposed(let ref, let argsDescription):
            // Round-3 R3.1（本 loop = M3 plan 第三次 codex review，2026-04-29）：ref 是 MCPToolRef，
            // JSONLAuditLog.scrubSideEffect 把整个 MCPToolRef 替换为 MCPToolRef(server: "<redacted>",
            // tool: "<redacted>")（参 SliceAIKit/Sources/Orchestration/Telemetry/JSONLAuditLog.swift:248-250）—
            // server/tool 是审计层脱敏边界内的敏感标识（私有 MCP server 域名 + 工具名暴露 = 用户工作流隐私）。
            // OSLog 公开输出会绕过该边界，故 ref 整体描述标 .private（与 args 同口径）。
            logger.debug("toolCallProposed ref=\(String(describing: ref), privacy: .private) args=\(argsDescription, privacy: .private)")

        case .toolCallApproved(let id):
            logger.debug("toolCallApproved id=\(id, privacy: .public)")

        case .toolCallResult(let id, let summary):
            logger.debug("toolCallResult id=\(id, privacy: .public) summary=\(summary, privacy: .private)")

        case .stepCompleted(let step, let total):
            logger.debug("stepCompleted \(step, privacy: .public)/\(total, privacy: .public)")

        // Round-3 R3.1 修订（本 loop = M3 plan 第三次 codex review，2026-04-29）：String(describing:)
        // 对 SideEffect / Permission（带关联值的 enum）会展开内部所有字段（appendToFile path/header；notify
        // title/body；runAppIntent params；callMCP server/tool/params；writeMemory tool/entry；fileRead/Write
        // path；mcp server/tools 等），privacy: .public 即把用户敏感字段写入 OSLog（Console.app + log show），
        // 完全绕过 JSONLAuditLog.scrubSideEffect 的脱敏边界（参 line 215-258：所有字段全 Redaction.scrub）。
        // 公开日志只输出 case 名 + invocationId 等"无 PII 的 fixed identifier"，详细字段查 audit.jsonl。
        // caseName helper 见本文件末尾（implementer 必须在 Step C1.4 同 commit 加 SideEffect/Permission caseName extension）。
        case .sideEffectTriggered(let sideEffect):
            logger.debug("sideEffectTriggered case=\(sideEffect.caseName, privacy: .public)")

        case .sideEffectSkippedDryRun(let sideEffect):
            logger.debug("sideEffectSkippedDryRun case=\(sideEffect.caseName, privacy: .public)")

        case .permissionWouldBeRequested(let permission, let uxHint):
            // uxHint 含动态用户文本（如 "请允许写入 ~/Documents/notes/work.md"，含用户路径）；标 .private 与字段策略一致
            logger.debug("permissionWouldBeRequested perm=\(permission.caseName, privacy: .public) hint=\(uxHint, privacy: .private)")

        case .notImplemented(let reason):
            // 不重试不开 Settings——这是 spec 设计期声明的 not-implemented 边界
            // 注意 ResultPanel.fail 的真实签名第一个参数有 `with:` label
            panel.fail(
                with: .execution(.notImplemented(reason)),
                onRetry: nil,
                onOpenSettings: nil
            )

        case .finished:
            panel.finish()

        case .failed(let sliceError):
            // 失败默认提供"重试"和"打开设置"两个动作；具体 closure 由 AppDelegate 注入
            panel.fail(
                with: sliceError,
                onRetry: { [weak self] in self?.onRetry() },
                onOpenSettings: { [weak self] in self?.onOpenSettings() }
            )
        }
    }
}
```

> **note**：
> - `panel.fail(with:onRetry:onOpenSettings:)` — 真实第一个参数 label 是 `with:` 而非 positional（见 `Windowing/ResultPanel.swift:139`）。
> - `SliceError.execution(.notImplemented(_))` — 由 Iteration A0 新增（Iteration A0 必须在本 Iteration 之前完成）。
> - `Permission` / `SideEffect` / `MCPToolRef` / `InvocationReport` / `ContextKey` 等类型 import：从 SliceCore + Orchestration target 引入。
> - 如果实施期发现 `ContextKey` / `MCPToolRef` 暴露了更精确的字段名（如 `ref.id` / `key.rawValue`），可替换 `String(describing:)`，但禁止臆造不存在的字段名（如曾经的 `ref.toolName`）。
> - **Round-3 R3.1 修订（2026-04-29 本 loop = M3 plan 第三次 codex review）**：`String(describing: sideEffect)` / `String(describing: permission)` 这两个具体形式被 §J0 gate 11 grep 兜底**任何 privacy 都拒绝**——SideEffect / Permission 关联值字段大量与 JSONLAuditLog 脱敏边界重合（appendToFile path / notify body / runAppIntent params / callMCP server-tool / writeMemory entry / fileRead-Write path / mcp server-tools / shellExec commands / memoryAccess scope / appIntents bundleId 等），OSLog 任何字段展开都视为脱敏失守，必须用 caseName helper（见 Step C1.4）。MCPToolRef 例外允许 `String(describing: ref)`（refs/tool 名形态多变，case-name helper 列举不全），但 privacy 必须 `.private`（与 args 同口径），不允许 `.public`——同样由 gate 11 兜底。

- [ ] **Step C1.4: 在 ExecutionEventConsumer.swift 末尾追加 caseName helper extension【Round-3 R3.1 必加】**

> **Round-3 R3.1（2026-04-29 本 loop）+ Round-4 R4.1 修订（2026-04-29 本 loop）**：Step C1 公开日志改用 `sideEffect.caseName` / `permission.caseName` 仅暴露 case 名（fixed identifier，无 PII 风险），与 JSONLAuditLog.scrubSideEffect 脱敏边界对齐。caseName extension 必须与 Step C1 同 commit 落地（否则 ExecutionEventConsumer.swift 引用 `.caseName` 立即编译失败）。**Round-4 R4.1 修订**：原 R3.1 模板 SideEffect 列 5 case + Permission 列 3 case（含**不存在的 `mcpAccess`**），与真实 SliceCore enum 不一致——implementer first-pass 复制后会同时遇到 nonexistent case + non-exhaustive switch，违反"每 commit 4 关 CI gate 全绿"硬约束。修法：模板已与真实 enum **完全对齐**（SideEffect 7 case = `OutputBinding.swift:47-55`；Permission 11 case = `Permission.swift:9-31`，注意是 `mcp` 不是 `mcpAccess`），implementer 直接复制即可编译；未来 SliceCore 加新 case 时 Swift exhaustive switch 编译期会立即报错强制更新本 helper。

把以下 extension 追加到 `SliceAIApp/ExecutionEventConsumer.swift` 文件末尾（紧跟 `final class ExecutionEventConsumer { ... }` 之后；与 ToolEditorView.swift 的 `private extension PresentationMode { displayLabel }` 同模式）：

```swift
// MARK: - Round-3 R3.1 caseName helper（脱敏边界对齐）

/// 仅返回 SideEffect case 名（不展开关联值字段）。
///
/// **为什么不直接用 `String(describing:)`**：String(describing:) 对 enum-with-associated-values
/// 会展开内部所有字段，OSLog 公开输出（privacy: .public）即把 path/title/body/params/server/tool 等
/// 用户敏感字段写入 Console.app + log show，**完全绕过** JSONLAuditLog.scrubSideEffect 的脱敏设计
/// （JSONLAuditLog line 215-258：所有字段全 Redaction.scrub；MCPToolRef 整体替换为 <redacted>）。
///
/// 本 helper 只暴露 case 名（fixed identifier，无 PII 风险），详细字段查
/// `~/Library/Application Support/SliceAI/audit.jsonl`（已脱敏）。
///
/// **Round-4 R4.1 verified（2026-04-29 本 loop）**：以下 7 case 与 `SliceAIKit/Sources/SliceCore/OutputBinding.swift:47-55`
/// 真实 `public enum SideEffect` 完全一致；implementer 直接复制即可，无需手动补全。未来 SliceCore 加新
/// case 时 Swift exhaustive switch 编译期会立即报错强制更新本 helper。
private extension SideEffect {
    var caseName: String {
        switch self {
        case .appendToFile:    return "appendToFile"
        case .copyToClipboard: return "copyToClipboard"
        case .notify:          return "notify"
        case .runAppIntent:    return "runAppIntent"
        case .callMCP:         return "callMCP"
        case .writeMemory:     return "writeMemory"
        case .tts:             return "tts"
        // 加新 case 时 Swift 会编译期报错提示这里更新；不要写 default 分支（会绕过 exhaustive 检查）
        }
    }
}

/// 仅返回 Permission case 名（不展开关联值字段）。同 SideEffect.caseName 设计。
///
/// **Round-4 R4.1 verified（2026-04-29）**：以下 11 case 与 `SliceAIKit/Sources/SliceCore/Permission.swift:9-31`
/// 真实 `public enum Permission` 完全一致（注意是 `mcp` 不是 `mcpAccess`——R3.1 旧模板写 `mcpAccess`
/// 是 case-name 错误已 R4.1 修正）。Permission 关联值（network host / fileRead-Write path / shellExec
/// commands / mcp server-tools / memoryAccess scope / appIntents bundleId 等）同样属于 JSONLAuditLog 脱敏
/// 边界，OSLog 公开输出必须避开。
private extension Permission {
    var caseName: String {
        switch self {
        case .network:          return "network"
        case .fileRead:         return "fileRead"
        case .fileWrite:        return "fileWrite"
        case .clipboard:        return "clipboard"
        case .clipboardHistory: return "clipboardHistory"
        case .shellExec:        return "shellExec"
        case .mcp:              return "mcp"
        case .screen:           return "screen"
        case .systemAudio:      return "systemAudio"
        case .memoryAccess:     return "memoryAccess"
        case .appIntents:       return "appIntents"
        // 加新 case 时 Swift 会编译期报错提示这里更新；不要写 default 分支
        }
    }
}
```

> **note**：
> - 上方 switch 已**与真实 enum exhaustive 同步**（Round-4 R4.1 verified 2026-04-29 本 loop）：SideEffect 7 case = `SliceAIKit/Sources/SliceCore/OutputBinding.swift:47-55`；Permission 11 case = `SliceAIKit/Sources/SliceCore/Permission.swift:9-31`。implementer 直接复制即可，**不要自行加 case**也**不要写 `default` 兜底**（会让 SliceCore 加新 case 时悄悄落入 default，绕过编译期检查）。如果 SliceCore 在 implementer 落地前已增加新 case，Swift 编译期会立即报错提示更新本 helper。
> - 不要 fancy reflection（`Mirror(reflecting:)` 抓 case label）：① Mirror 返回 String? 需要 force-unwrap 或兜底空字符串、引入潜在崩溃；② exhaustive switch 加新 case 时编译期立即报错强制更新，比 reflection 失败更可靠。
> - 这两个 extension **必须**在同 commit 与 Step C1 一起落地（plan §M3.0 Step 1 commit 单元；否则 ExecutionEventConsumer.swift 引用 `.caseName` 立即编译失败 → Step 1 commit 不绿）。

- [ ] **Step C1.5: 把 ExecutionEventConsumer.swift 加入 Xcode app target Sources【F4.1 R4 必加】**

同 Task 3 Step 3.5，`SliceAI.xcodeproj` 是显式 sources build phase，新文件**必须**手工注册到 `SliceAI.xcodeproj/project.pbxproj`，否则 app target 编译会找不到 `ExecutionEventConsumer` 类型。

分配两个稳定 UUID：

| 用途 | 分配 UUID（24 hex）|
|---|---|
| `ExecutionEventConsumer.swift in Sources` (PBXBuildFile) | `533BA7A22F9695D00078EF4F` |
| `ExecutionEventConsumer.swift` 文件引用 (PBXFileReference) | `533BA7A32F9695D00078EF4F` |

> **UUID 选取原则**：与 Task 3 Step 3.5 同 epoch；533BA7A2 / 533BA7A3 紧邻 ResultPanelWindowSinkAdapter 的 533BA7A0 / 533BA7A1，便于 review。

**Edit op 1 — PBXBuildFile section**：anchor 是 ResultPanelWindowSinkAdapter 那一行（Task 3 Step 3.5 已加）

```diff
 		533BA7A02F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift in Sources */ = {isa = PBXBuildFile; fileRef = 533BA7A12F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift */; };
+		533BA7A22F9695D00078EF4F /* ExecutionEventConsumer.swift in Sources */ = {isa = PBXBuildFile; fileRef = 533BA7A32F9695D00078EF4F /* ExecutionEventConsumer.swift */; };
 		533BA78B2F9695D00078EF4F /* SliceAIApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = 533BA7862F9695D00078EF4F /* SliceAIApp.swift */; };
```

**Edit op 2 — PBXFileReference section**：anchor 是 ResultPanelWindowSinkAdapter.swift 引用

```diff
 		533BA7A12F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ResultPanelWindowSinkAdapter.swift; sourceTree = "<group>"; };
+		533BA7A32F9695D00078EF4F /* ExecutionEventConsumer.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ExecutionEventConsumer.swift; sourceTree = "<group>"; };
 		533BA7852F9695D00078EF4F /* SliceAI.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = SliceAI.entitlements; sourceTree = "<group>"; };
```

**Edit op 3 — SliceAIApp 子 Group 的 children**

```diff
 			533BA7842F9695D00078EF4F /* MenuBarController.swift */,
+			533BA7A32F9695D00078EF4F /* ExecutionEventConsumer.swift */,
 			533BA7852F9695D00078EF4F /* SliceAI.entitlements */,
 			533BA7A12F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift */,
 			533BA7862F9695D00078EF4F /* SliceAIApp.swift */,
```

**Edit op 4 — Sources build phase 的 files**

```diff
 			533BA78A2F9695D00078EF4F /* MenuBarController.swift in Sources */,
 			533BA7A02F9695D00078EF4F /* ResultPanelWindowSinkAdapter.swift in Sources */,
+			533BA7A22F9695D00078EF4F /* ExecutionEventConsumer.swift in Sources */,
 			533BA78B2F9695D00078EF4F /* SliceAIApp.swift in Sources */,
```

**Step C1.5 验证 grep gate**（必须在 Step C2 build 之前跑）：

```bash
echo "=== ExecutionEventConsumer.swift 是否已注册到 pbxproj 的 4 处必要位置 ===" && \
PBXFILE=SliceAI.xcodeproj/project.pbxproj && \
COUNT_FILEREF=$(grep -c "533BA7A32F9695D00078EF4F /\* ExecutionEventConsumer\.swift \*/" "$PBXFILE") && \
COUNT_BUILDFILE=$(grep -c "533BA7A22F9695D00078EF4F /\* ExecutionEventConsumer\.swift in Sources \*/" "$PBXFILE") && \
COUNT_GROUP=$(grep -c "533BA7A32F9695D00078EF4F /\* ExecutionEventConsumer\.swift \*/," "$PBXFILE") && \
COUNT_SOURCESPHASE=$(grep -c "533BA7A22F9695D00078EF4F /\* ExecutionEventConsumer\.swift in Sources \*/," "$PBXFILE") && \
echo "PBXFileReference 出现次数 = $COUNT_FILEREF" && \
echo "PBXBuildFile 出现次数 = $COUNT_BUILDFILE" && \
echo "Group children 引用次数 = $COUNT_GROUP" && \
echo "Sources build phase 引用次数 = $COUNT_SOURCESPHASE" && \
if [ "$COUNT_FILEREF" -lt 1 ] || [ "$COUNT_BUILDFILE" -lt 1 ] || [ "$COUNT_GROUP" -lt 1 ] || [ "$COUNT_SOURCESPHASE" -lt 1 ]; then echo "FAIL: 4 处注册不齐全"; exit 1; fi && \
echo "PASS: ExecutionEventConsumer.swift 4 处注册齐全"
```

任何 `COUNT_XXX < 1` → 回头补对应 Edit op；4 处都 ≥1 才进 Step C2。

- [ ] **Step C2: 验证编译通过**

Run: `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

如果某个 ExecutionEvent case 翻译错（如 ` permissionWouldBeRequested` 的 label 名实际不同）：核对 `SliceAIKit/Sources/Orchestration/Events/ExecutionEvent.swift` 真实 enum case 后修正。

### Iteration D: AppDelegate.execute 切到 ExecutionEngine（含 ordering + single-flight + cancellation）

- [ ] **Step D0: 在 AppDelegate 顶部声明 streamTask stored property**

定位 AppDelegate 顶部 stored properties 区段（既有 `globalMouseMonitor` / `mouseDownMonitor` / `lastMouseDownLocation` / `debounceTask` / `menuBarController` / `settingsWindow` / `onboardingWindow`），追加：

```swift
/// F9.2 single-flight：当前正在跑的 ExecutionEngine consumer Task；新一次 execute 进来先 cancel 旧的
/// 与 debounceTask 不同 — debounceTask 是 mouseUp 防抖，streamTask 是流消费 task
private var streamTask: Task<Void, Never>?
```

> **note**：streamTask 必须是 `Task<Void, Never>`（consumer Task 内 catch 全部 error → 不向外抛），否则 `streamTask?.cancel()` 不可调。

- [ ] **Step D1: 改 AppDelegate.execute(tool:payload:) 整体（line 331）— 4th-loop R5.X 修订：setActive 提到 open 之前**

> **4th-loop R5.X 修订（2026-04-30 codex post-audit adversarial review）**：codex 提出 ordering 风险——cancel A → open(B) 之间若主 actor 出现 yield 点，A 的 stale `.finished` / `.failed` / `.notImplemented` 会在 gate 仍 active=A 的瞬间通过 consumer 的 shouldAccept guard，污染 B 已 reset 的 panel。
>
> **代码审计结论**：当前 sync 序列（cancel → toExecutionSeed → open → setActive → stream → Task）**严格不 yield 主 actor**，加上 line 2095/2108/2120 的 `shouldAccept(invocationId)` guard 覆盖**所有** events（chunk + 终态 + catch 路径），race 实际**不会**发生——属于 codex 的过度推断。
>
> **但仍采纳 codex Recommendation 作为纵深防御**：把 `setActiveInvocation(B)` **提到 `open(B)` 之前**，让 gate 成为第一道闸门，不再依赖"per-event guard 必须正确放置 + 主 actor 不 yield"两条隐性约束。未来若 implementer 在 guard 之前误加 panel-mutating 代码、或某条 panel 操作改成 async 引入 yield 点，新 ordering 仍能挡住 stale event。同步在 §Iteration I 增加 `test_staleEventAfterReopen_isDropped` 确定性测试，把这层保护变成可验证 invariant。

定位现有 `func execute(tool: SliceCore.Tool, payload: SelectionPayload)`（line 331）；完全替换为：

```swift
/// 触发一次工具执行：cancel 旧 stream → setActive 新 invocationId → open ResultPanel → 创建 stream → 启 consumer Task
///
/// **F8.3 ordering invariant**：先 open 再 stream（防止快路径首 chunk 被 open reset 丢失）
/// **F9.2 single-flight invocation**：cancel 旧 → setActive 新 → open 重置 panel；setActive 提到 open 之前
/// 让 gate 成为第一道闸门，stale invocation 的所有 panel-mutating events（chunk / .finished / .failed /
/// .notImplemented + catch 路径）一律先被 gate 过滤，不再依赖 per-event shouldAccept guard 正确覆盖
/// 每条路径。详见 4th-loop R5.X 修订背景（codex post-audit adversarial review）。
///
/// **audit-fix 2026-04-28（caller-passed triggerSource）**：`triggerSource` 必须由 caller 显式提供，
/// 不再硬编码 `.floatingToolbar`——否则 ⌥Space 命令面板路径触发的 invocation 会被错误标记为
/// floatingToolbar，污染 InvocationReport / 日志 / 后续遥测。默认参数 `.floatingToolbar` 保留
/// 是为了让 mouseUp 浮条这条最常见路径的 onPick 闭包不必显式传入。
/// 4 处 caller 行为：
/// 1. `tryCaptureAndShowToolbar` → FloatingToolbarPanel.onPick → 默认 `.floatingToolbar`（不必传）
/// 2. `showCommandPalette` → CommandPalettePanel.onPick → **必须显式传 `.commandPalette`**
/// 3. `onRegenerate` 闭包 → 闭包内 capture 当前 method 入口的 `triggerSource`，原样回传
/// 4. `onRetry` 闭包 → 同 onRegenerate，capture + 回传
@MainActor
func execute(tool: SliceCore.V2Tool, payload: SelectionPayload, triggerSource: TriggerSource = .floatingToolbar) {
    guard let container = self.container else { return }

    // F9.2 step 1：取消旧 stream（防止旧 invocation 仍 producing 时新 invocation 已开始）
    // 协作式 cancel：旧 consumer Task 在下次 await 检查到 cancelled flag 后退出；
    // 在那之前可能仍 yield 已 buffered 的事件——R5.X step 2 把 setActive 提前正是为了挡这层 race。
    streamTask?.cancel()

    // F2.2：单一入口构造 ExecutionSeed（替代散在多处的字段拷贝）
    // triggerSource 由 caller 显式提供（详见 doc comment）
    let seed = payload.toExecutionSeed(triggerSource: triggerSource)
    let invocationId = seed.invocationId

    // F9.2 step 2（4th-loop R5.X 修订）：**先 setActive 切 gate**，再 open 重置 panel
    // 让 gate 成为第一道闸门——切到新 invocationId 之后，旧 invocation 的任何 events
    // （chunk / .finished / .failed / .notImplemented）经过 gate.shouldAccept 时一律返回 false
    // → 即使 panel 已 reset、即使 per-event guard 漏放、即使未来某条 panel API 变 async 引入 yield，
    // stale event 都不会再污染 B 的 panel。
    // F2.2 R2 walking back + F3.4 R3：gate 是 @MainActor class，setActiveInvocation 是同步函数；
    // execute(tool:payload:) 已在 @MainActor 上下文，**直接 sync 调用**——禁止用 Task wrapper
    container.invocationGate.setActiveInvocation(invocationId)

    // 提取 model 用于 ResultPanel 标题：ToolKind 是 enum 不是 optional property，用 if case 解构
    // 真实 PromptTool.provider 类型是 ProviderSelection enum；只有 .fixed case 携带 modelId
    // audit-fix 2026-04-28：fallback 必须是非空字符串（"default"）保证 D-29 视觉等价——
    // v1 ResultPanel 的 model badge 永远展示一段文字（即使是 provider.defaultModel），
    // 空串 "" 会让 SwiftUI 渲染零宽 badge / 空角标，与 v1 行为不等价。
    let modelLabel: String = {
        guard case .prompt(let promptTool) = tool.kind else { return "default" }
        if case .fixed(_, let modelId) = promptTool.provider {
            return modelId ?? "default"
        }
        // .capability / .cascade 模式：v0.2 不暴露真实 model；用 "default" 占位（视觉等价 v1 行为）
        return "default"
    }()

    // F9.2 step 3 + F8.3 ordering ①（4th-loop R5.X 修订：setActive 之后再 open）
    // open ResultPanel（含 onDismiss + onRegenerate callback 挂载）
    // 注意 ResultPanel.open 真实参数 label 是 `anchor:` 不是 `at:`
    // F2.2 R2 walking back + F3.4 R3：onDismiss 内调 invocationGate.clearActiveInvocation(ifCurrent:)
    // —— InvocationGate 是 Orchestration target 内独立 @MainActor class，被 adapter + AppDelegate 共用
    // F6.1 R6 修订：必须传 onRegenerate（v1 AppDelegate.swift:351-355 真实传入；ResultPanel.swift:73 默认 nil）；
    // 漏传会让 ResultPanel 顶部"重新生成"按钮静默失效，违反 D-29 视觉/行为等价 + M3.5 回归清单 Regenerate 项
    container.resultPanel.open(
        toolName: tool.name,
        model: modelLabel,
        anchor: payload.screenPoint,
        onDismiss: { [weak self] in
            self?.streamTask?.cancel()
            // F9.2 step 5：dismiss 时清空 active id，**仅当当前 active 仍是本 invocation**
            // gate 是 @MainActor class（不是 actor），同步调用即可——无需 Task wrapper
            self?.container?.invocationGate.clearActiveInvocation(ifCurrent: invocationId)
        },
        onRegenerate: { [weak self] in
            // F6.1 R6：与 v1 AppDelegate 等价语义——cancel 旧 stream + 重新 execute 同 tool/payload
            // F9.2 自动保护：execute(tool:payload:) 入口本身会 cancel streamTask 后 setActive 新 invocation；
            // 旧 stream 的 defer 走 clearActiveInvocation(ifCurrent: oldId)，guard 不命中 → 不会误清新 invocation
            // audit-fix 2026-04-28：闭包 capture 入口的 triggerSource，重新 execute 时保持原 source
            self?.streamTask?.cancel()
            Self.log.info("onRegenerate: re-running tool=\(tool.name, privacy: .public) source=\(triggerSource.rawValue, privacy: .public)")
            self?.execute(tool: tool, payload: payload, triggerSource: triggerSource)
        }
    )

    // F8.3 ordering ② 创建 stream（producer task 启动；ExecutionEngine.execute 是 nonisolated）
    let stream = container.executionEngine.execute(tool: tool, seed: seed)

    // ExecutionEvent → ResultPanel 翻译 helper
    let consumer = ExecutionEventConsumer(
        onRetry: { [weak self] in self?.execute(tool: tool, payload: payload, triggerSource: triggerSource) },
        onOpenSettings: { [weak self] in self?.showSettings() }  // 真实方法名 showSettings()，不是 openSettings()
    )

    // F8.3 ordering ③ 启 consumer Task 消费 events
    streamTask = Task { @MainActor [weak self] in
        guard let self else { return }
        defer {
            // stream 结束（无论成败）清空 active id —— 用 ifCurrent: invocationId guard
            // 防止旧 stream 的 defer 晚于新 invocation setActive 运行时把新 invocation 误清空
            // F3.4 R3：调 invocationGate（不是 adapter）；gate 是 @MainActor class，sync 调用即可
            self.container?.invocationGate.clearActiveInvocation(ifCurrent: invocationId)
        }
        do {
            for try await event in stream {
                // F7.1 R7：F9.2 single-flight 边界扩大——chunk 路径 R4 已经被 gatedAppend gate；
                // 但 ExecutionEventConsumer 处理 .finished / .failed / .notImplemented 直接调
                // panel.finish() / panel.fail()，不经过 gatedAppend；如果 A yield 终态事件
                // 后 B 已 open，A 的 stale .failed/.finished 会污染 B 的面板。
                // 修法：consumer.handle 前加 shouldAccept guard，让所有 events（含终态）
                // 都受 InvocationGate 保护——stale invocation 的事件全部静默丢弃。
                // 这是补 R3/R4 InvocationGate 抽象的边界（chunk → all panel-mutating events），
                // 不是 walking back R3/R4 决议（gate 实现 + adapter 1 行委托均不变）。
                guard self.container?.invocationGate.shouldAccept(invocationId: invocationId) == true else {
                    continue
                }
                consumer.handle(event, panel: container.resultPanel)  // handle 是 sync，不需要 await
            }
        } catch is CancellationError {
            // F8.3：silent；ResultPanel.onDismiss → cancel 链路触发
        } catch let urlErr as URLError where urlErr.code == .cancelled {
            // silent
        } catch let sliceError as SliceError {
            // F7.1 R7：catch 段同样要 gate——stream 抛错与 user Regenerate 之间存在 race window
            // （A 抛 SliceError 后 B 已 setActive 之前 A 的 catch 才执行），不 gate 会让 A 的错误
            // 污染 B 的 panel。stale invocation 的错误同样静默丢弃（用户已转向 B，A 的错误对用户已无意义）。
            guard self.container?.invocationGate.shouldAccept(invocationId: invocationId) == true else {
                return
            }
            container.resultPanel.fail(
                with: sliceError,
                onRetry: { [weak self] in self?.execute(tool: tool, payload: payload, triggerSource: triggerSource) },
                onOpenSettings: { [weak self] in self?.showSettings() }
            )
        } catch {
            // catch-all：用 Iteration A0 新增的 .execution(.unknown(_)) case
            // localizedDescription 进 reason 已被 SliceError.developerContext 脱敏为 <redacted>
            // F7.1 R7：与 SliceError catch 同 gate 语义
            guard self.container?.invocationGate.shouldAccept(invocationId: invocationId) == true else {
                return
            }
            container.resultPanel.fail(
                with: .execution(.unknown(error.localizedDescription)),
                onRetry: { [weak self] in self?.execute(tool: tool, payload: payload, triggerSource: triggerSource) },
                onOpenSettings: { [weak self] in self?.showSettings() }
            )
        }
    }
}
```

- [ ] **Step D2: 删除原 v1 execute 函数**

`func execute(tool: SliceCore.Tool, payload: SelectionPayload)`（line 331 v1）已经被新版 D1 整段替换；不需要单独删除步骤。但需 grep 确认没有遗留：

```
grep -n "func execute(tool: SliceCore.Tool" SliceAIApp/AppDelegate.swift
```
Expected: 0 命中（仅剩 V2Tool 版本）

> **note**：
> - `ResultPanel.open` 真实参数 label 是 `anchor:`（见 `Windowing/ResultPanel.swift:71`），不是 `at:`。
> - `ResultPanel.fail` 真实第一个参数 label 是 `with:`（见 `Windowing/ResultPanel.swift:139`）。
> - `ToolKind.prompt` 是 enum case 不是 optional property — 用 `if case .prompt(let promptTool) = tool.kind`。
> - `PromptTool.provider` 类型是 `ProviderSelection` enum，只有 `.fixed(providerId:modelId:)` 带 modelId。
> - `AppDelegate.showSettings()` 是真实方法名（line 389），不是 `openSettings()`。
> - **F2.2 R2 walking back + F3.4 R3**：`InvocationGate` 是 **`@MainActor` final class（不是 actor）**，在 Orchestration target；`setActiveInvocation` / `clearActiveInvocation(ifCurrent:)` / `shouldAccept(invocationId:)` 是同步函数。execute(tool:payload:) 在 @MainActor 上下文，**直接 sync 调用 `container.invocationGate.*` 即可**，禁止用 `Task { @MainActor in await ... }` wrapper（R1 fix 误以为 adapter 是 actor 引入了 race：setActive Task 未运行时 stream 已发首 chunk → gate active 仍 nil → 首段被 drop；defer Task 晚于新 invocation setActive 运行时把新 invocation 误清空）。`clearActiveInvocation(ifCurrent:)` 必须传 invocationId 让 gate 内部 guard 只清自己 invocation。**注意**：调用是 `container.invocationGate`（不是 `container.resultPanelAdapter` — adapter 不再暴露 setActive/clearActive 方法，全部委托 gate）。

- [ ] **Step D3: 验证编译通过（部分 — caller 类型还没切）**

Run: `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build 2>&1 | tail -50`
Expected: BUILD FAILED — 因为 FloatingToolbarPanel / CommandPalettePanel 等 caller 仍调 `execute(tool: SliceCore.Tool, ...)`；execute 签名已切到 V2Tool 但 Toolbar/Palette `show` 仍传 v1 Tool

记录所有 callsite，进 Iteration F 一起切（Iteration F 会改 Toolbar/Palette show 签名）。

### Iteration E: SettingsViewModel 切 V2ConfigurationStore + loadError state【F2.3 R2 真实结构修订】

- [ ] **Step E1: 改 SettingsViewModel store 类型 + @Published 类型【按真实 SettingsViewModel 结构】**

⚠️ **F2.3 R2 修订**：grep `SettingsViewModel.swift` 真实结构（line 21-27）：

```swift
@Published public var configuration: Configuration  // v1 聚合 @Published
@Published public var appearance: AppearanceMode    // 与 configuration.appearance 同步
```

**没有** `self.providers / self.tools / self.triggers / self.hotkeys` 这些独立 @Published 字段——R1 plan 的 reload 模板写错了字段名。

把 `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift` 顶部：

```swift
private let store: any ConfigurationProviding
@Published public var configuration: Configuration
@Published public var appearance: AppearanceMode
```

改为（M3.0 Step 1 切到 V2；类型名 V2ConfigurationStore / V2Configuration 在 Step 3 再 rename）：

```swift
private let store: V2ConfigurationStore
@Published public var configuration: V2Configuration
@Published public var appearance: AppearanceMode  // 字段名不变（V2Configuration.appearance 也叫这个）
/// F8.2：ViewModel 层 reload 失败暴露给 UI 显示，禁止 default 覆盖内存态
@Published public var loadError: SliceError?
```

把 init 签名：

```swift
public init(store: any ConfigurationProviding, keychain: any KeychainAccessing) {
```

改为：

```swift
public init(store: V2ConfigurationStore, keychain: any KeychainAccessing) {
```

init 内 "用默认值占位" 段同步改成 V2Configuration 默认值（**F3.1 R3 修订**：真实方法名是 `initial()` 不是 `make()`）：

```swift
// 改前：self.configuration = Configuration.default()
// 改后（DefaultV2Configuration 在 Iteration C 之前已存在 / Task 9 rename 后是 DefaultConfiguration）：
self.configuration = DefaultV2Configuration.initial()  // F3.1 R3：真实静态方法名 initial()，不是 make()
self.appearance = configuration.appearance
```

> **audit-fix 2026-04-29 — 必须保留 init 末尾的 detached reload Task**：当前 SettingsViewModel.swift line 56-58 末尾有：
>
> ```swift
> // 使用 [weak self] 捕获弱引用，避免在 Swift 6 严格并发下 self 在 init
> // 尚未完成时被强引用持有的诊断
> Task { [weak self] in await self?.reload() }
> ```
>
> 此 detached Task 是首屏渲染从默认占位过渡到磁盘真值的核心机制——**必须保留不变**，不能删除也不能合并到 init 同步段。implementer 改 store 类型 / @Published 类型时不要顺手清掉这一行。这条 Task 是 R9 walking back 论证 "loadError 永远 nil" 的关键依赖之一（详见 §Step E4.5 完整论证链）。

- [ ] **Step E2: 改 reload() — 用真实 @Published configuration + appearance + loadError 模式**

定位 `func reload() async` (~ line 84)，改为（注意：**不是赋值 self.providers/self.tools 等独立字段**，而是赋值聚合 self.configuration + self.appearance）：

```swift
public func reload() async {
    do {
        let cfg = try await store.current()
        // F2.3 R2：按真实 SettingsViewModel 结构——只有两个 @Published（configuration 聚合 + appearance）
        // Pages/*SettingsPage.swift 通过 viewModel.configuration.tools / .providers / .triggers / .hotkeys 访问
        self.configuration = cfg
        self.appearance = cfg.appearance  // 真实 V2Configuration 字段名是 appearance（不是 appearanceMode）
        self.loadError = nil
    } catch let error as SliceError {
        // F8.2：禁止 default 覆盖内存态——暴露 loadError 让 UI 显示
        self.loadError = error
    } catch {
        self.loadError = .configuration(.invalidJSON("<redacted>"))
    }
}
```

> **note F2.3 R2**：所有读取配置的 SwiftUI 代码（如 `Pages/ToolsSettingsPage.swift` 内 `ForEach(viewModel.configuration.tools)`）保持不变；只有 ViewModel 自身字段换 `Configuration` → `V2Configuration` 类型。原 v1 plan 写的 `self.providers / self.tools / self.triggers / self.hotkeys` 散落字段是不存在的——是 R1 fix 残留的臆造。

- [ ] **Step E3: 改 addTool / addProvider 适配 V2 struct（真实位置在 Pages/ 而非 SettingsViewModel）**

⚠️ **F1.2 R1 修订**：addTool / addProvider 真实位置 grep 结果：

```
grep -rn "func addTool\|func addProvider" SliceAIKit/Sources/SettingsUI/
# SliceAIKit/Sources/SettingsUI/Pages/ProvidersSettingsPage.swift:200:    private func addProvider() {
# SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift:270:    private func addTool() {
```

不在 `SettingsViewModel.swift` 内，而是在 `Pages/` 内的 SwiftUI View 私有方法。改造对象：

**Pages/ToolsSettingsPage.swift line 270 `addTool()`**：定位现有 v1 `Tool(...)` 构造，改为（**V2Tool 真实 14 个 init 参数 — F2.3 R2 修订**）：

```swift
private func addTool() {
    // PromptTool 真实字段（按 SliceCore/ToolKind.swift line 53）：
    //   systemPrompt: String? / userPrompt: String / contexts: [ContextRequest] /
    //   provider: ProviderSelection / temperature: Double? / maxTokens: Int? / variables: [String: String]
    let prompt = PromptTool(
        systemPrompt: nil,
        userPrompt: "",
        contexts: [],   // v0.2 不暴露 contexts UI；空 array
        provider: .fixed(
            providerId: viewModel.configuration.providers.first?.id ?? "",  // F2.3 R2：viewModel.configuration.providers 不是 viewModel.providers
            modelId: nil
        ),
        temperature: 0.7,
        maxTokens: nil,  // v0.2 不暴露 maxTokens UI；nil 表示用 Provider 默认
        variables: [:]
    )
    // V2Tool 真实 14 个 init 参数（按 SliceCore/V2Tool.swift line 36 顺序，F2.3 R2 验证）
    let newTool = V2Tool(
        id: UUID().uuidString,
        name: "新工具",
        icon: "wand.and.stars",      // F2.3 R2：必填 — SF Symbol 名称
        description: nil,             // 可选；用户在 ToolEditorView 填
        kind: .prompt(prompt),
        visibleWhen: nil,             // v0.2 不暴露 ToolMatcher UI；nil 表示总是可见
        displayMode: .window,         // v0.2 默认 .window（D-30b 妥协）
        outputBinding: nil,           // v0.2 不暴露 sideEffect UI
        permissions: [],              // 默认空；用户在 ToolEditorView 加
        provenance: .firstParty,
        budget: nil,                  // v0.2 不暴露 budget UI
        hotkey: nil,                  // 用户后续在 HotkeySettingsPage 绑定
        labelStyle: .icon,            // F3.1 R3：真实 ToolLabelStyle case 是 .icon/.name/.iconAndName（不是 .iconOnly）
        tags: []                      // v0.2 不暴露 tags UI
    )
    // ... 既有 save 逻辑（按当前文件 274-285 行实际写入 viewModel.configuration.tools.append + viewModel.save() 等）
}
```

**Pages/ProvidersSettingsPage.swift line 200 `addProvider()`**：

```swift
private func addProvider() {
    let providerId = UUID().uuidString
    // V2Provider 真实 init 顺序（按 SliceCore/V2Provider.swift line 32）：id, kind, name, baseURL, apiKeyRef, defaultModel, capabilities
    // F2.3 R2：openAICompatible 必须有 baseURL（V2Provider.validate() 在 save 时强制；nil 会拒绝写盘）
    let newProvider = V2Provider(
        id: providerId,
        kind: .openAICompatible,
        name: "新供应商",
        // swiftlint:disable:next force_unwrapping
        baseURL: URL(string: "https://api.openai.com/v1")!,  // 默认 OpenAI；用户后续 ProviderEditorView 改
        apiKeyRef: "keychain:\(providerId)",  // CLAUDE.md "新增 Provider 时 apiKeyRef 必须用 keychain:<provider.id>"
        defaultModel: "gpt-4o-mini",
        capabilities: []
    )
    // ... 既有 save 逻辑
}
```

> **note F2.3 R2**：
> - **V2Tool init 真实有 14 个参数**（不是 R1 plan 写的 7 个）——`icon` / `description` / `visibleWhen` / `budget` / `hotkey` / `labelStyle` / `tags` 都是 R1 漏的。`icon` / `labelStyle` 是非 Optional 必填。`description` 是 String? 可填 nil，但 plan 应给出默认值。
> - **V2Provider init 真实顺序**是 `id, kind, name, baseURL, ...`（不是 R1 plan 写的 `id, name, kind, ...`）——参数名是 named，顺序错会被编译器抓但 implementer 容易看走眼。
> - **`openAICompatible.baseURL` 必须非 nil**——`V2Provider.validate()`（line 70+）会 throw `SliceError.configuration(.validationFailed("Provider '\(id)': kind=openAICompatible requires non-nil baseURL"))`。R1 plan 写 `baseURL: nil` 会让首次 save 失败。
> - addTool/addProvider 函数体后续保存路径用 `viewModel.configuration.tools.append(newTool)` + `await viewModel.save()`（实际方法名按 SettingsViewModel.swift `func save() async throws` line 93 为准）。

**Pages/ToolsSettingsPage+Row.swift**：定位 Row VM struct（如 `private struct ToolRow { let tool: Tool; ... }`），改 `Tool` → `V2Tool`。

⚠️ **audit-fix 2026-04-28 新增（行级改动）**：真实 `ToolsSettingsPage+Row.swift:90` 直接访问 v1 顶层字段 `tool.userPrompt`：

```swift
// 真实当前代码 line 90：
let subtitle = tool.description ?? String(tool.userPrompt.prefix(40))
```

V2Tool **没有顶层 `userPrompt` 属性**——userPrompt 是 PromptTool 的字段，必须 `tool.kind` switch 进 `.prompt(let promptTool)` 再读 `promptTool.userPrompt`。改造为：

```swift
// V2Tool 改造：subtitle 优先 description，否则按 ToolKind 取展示文本
let subtitle: String = {
    if let description = tool.description, !description.isEmpty { return description }
    if case .prompt(let promptTool) = tool.kind {
        return String(promptTool.userPrompt.prefix(40))
    }
    // .capability / .cascade 模式：v0.2 不暴露 userPrompt 等价文本，给 tool.name 兜底
    return tool.name
}()
```

> **note**：漏改这一行会让"工具列表展开行"在 V2 切换后编译失败（V2Tool 无 userPrompt 属性），是 implementer 切换类型时容易在 SettingsPage 树深处遗漏的高风险点。

- [ ] **Step E4: 改 setAPIKey / readAPIKey / testProvider 等参数类型**

把 `SettingsViewModel.swift` 内 `setAPIKey(_:for:)` 等方法的 `Provider` 参数改为 `V2Provider`：

```bash
grep -n "func setAPIKey\|func readAPIKey\|func testProvider\|func deleteProvider" SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift
```

每个签名内 `Provider` → `V2Provider`；同时 `Provider.keychainAccount` 计算属性如不存在于 V2Provider，需要按 `apiKeyRef` 字段提取（`provider.apiKeyRef.replacingOccurrences(of: "keychain:", with: "")` 或新增 V2Provider extension）。

- [ ] **Step E4.5: SettingsViewModel.save() 守护 loadError 状态【F8.1 R8 + F9.1 R9 walking back 简化】**

> **F9.1 R9 walking back R8 fix**：codex R9 review 揭示 R8 原方案（SettingsScene loadError banner UI + grep gate + M3.5 §4.2.5 Step 13 损坏 config-v2.json 验收）**与 D-27 mini-spec 决议不相容**——AppContainer.bootstrap 在 line 811 `_ = try await v2ConfigStore.current()` 已 eager 触发配置加载，损坏 config-v2.json 会在此处 throws → bootstrap throws → AppDelegate Task catch → `showStartupErrorAlertAndExit` → app 退出，**SettingsViewModel.reload() 永远不会运行，loadError 永远是 nil，SettingsScene banner 永远不显示**。R8 加的 UI binding + 验收路径在 v0.2 D-27 架构下不可达。**修法：保留 save guard（defensive future hook，不引入 bug 也不依赖触发场景）+ 删除 banner UI step + 删除 grep gate 6 + 删除 M3.5 §4.2.5 Step 13**。R5 F2.3 决议的 loadError 字段 + reload catch set 仍保留（同 defensive future hook —— Phase 2 manual refresh / cross-process consistency check 接入时启用）。
>
> **完整论证链（audit-fix 2026-04-28 补）**：以上"loadError 永远 nil"的关键支点是 V2ConfigurationStore 的 cached 语义——单看 bootstrap fail-fast 不够（因为 SettingsViewModel.init line 58 `Task { [weak self] in await self?.reload() }` 是 detached Task，会在 bootstrap 之后再次走 store.current()）。需要一并审计 `V2ConfigurationStore.swift`：
> 1. line 22 `private var cached: V2Configuration?` —— actor-isolated 缓存。
> 2. line 44-50 `current()`：`if let cached { return cached }` 命中即返回，不再走 disk load。
> 3. line 38-43 注释明确声明"错误不缓存"——bootstrap 第一次 current() 成功 → cached 已是有效 V2Configuration；后续任何 current() 调用都直接返回内存缓存。
> 4. SettingsViewModel.reload() 走 `await store.current()`（V2-only adapter 内部桥到 V2ConfigurationStore.current()）—— **bootstrap 已成功的前提下，reload() 命中缓存，绝不会再 throw**。
>
> 这就闭合了"v0.2 loadError 永远 nil"的论证：bootstrap 成功 → cached 有效 → init:58 detached reload Task 命中缓存零 throw → loadError 留空 → save guard vacuous false。Phase 2 引入 manual refresh / cross-process consistency 时，如果新增"主动 invalidate cached + 重读 disk"路径，loadError 才会真正被填充——届时再启用 banner UI + 验收。
>
> **R5 决议保留范围（不动）**：Step E2 reload() catch 段写 `self.loadError = error`；@Published `loadError: SliceError?` 字段；defensive 防 default 覆盖内存态。
>
> **R8 决议保留范围（仅 save guard）**：SettingsViewModel.save() 首行 `if let err = self.loadError { throw ... }` —— v0.2 永远不会 trigger（loadError 永远 nil），但代码保留作为 future hook，避免 Phase 2 加 manual refresh 时漏写守护。
>
> **R8 决议删除范围（不可达）**：SettingsScene banner UI step（Step E4.5.b 旧版）；编译前 grep gate 6（Step E4.5.c 旧版 + Iteration J Step J0 gate 6 实际脚本）；M3.5 §4.2.5 Step 13 损坏 config-v2.json 验收。

修改 `SettingsViewModel.swift` line 93+ `func save() async throws`：

```swift
public func save() async throws {
    // F8.1 R8 + F9.1 R9：defensive guard——v0.2 D-27 架构下 loadError 永远 nil（bootstrap fail-fast 提前退出），
    // 此 guard 是 vacuous false 不影响行为；保留作为 Phase 2 引入 manual refresh / cross-process
    // consistency check 后的 future hook，避免那时漏写守护把 default 写回覆盖损坏 config-v2.json
    if let err = self.loadError {
        throw SliceError.configuration(.validationFailed("config-v2.json load failed; refusing to save default placeholder over broken file"))
    }
    // ... 既有 save 逻辑
}
```

> **note F9.1 R9**：本 step 不再要求修改 SettingsScene.swift / Pages / Editor 任何 UI 文件 —— v0.2 loadError 永远 nil，UI binding 是 dead code 反而增加 implementer 心智负担。Phase 2 加 manual refresh feature 时再扩 banner UI + 同步加 grep gate 即可。Step J0 grep gate 不增加新关。
>
> **后续 implementer 注意**：`SliceError.configuration(.validationFailed(_))` 是真实 case（M1+M2 已合 main，对照 SliceCore/SliceError.swift line 153）；不引入新 case。错误 message 是固定字符串（不拼用户内容），无 redaction 风险。

- [ ] **Step E5: 编译验证**

Run: `cd SliceAIKit && swift build 2>&1 | tail -30`
Expected: SettingsViewModel.swift + SettingsScene.swift 编译通过；其他依赖 SettingsViewModel 的文件可能报错（ToolEditorView / ProviderEditorView），下个 iteration 修

### Iteration F: FloatingToolbarPanel + CommandPalettePanel show 签名切换 + SettingsScene/Editor 数据 binding

- [ ] **Step F0: 改 FloatingToolbarPanel.show + CommandPalettePanel.show 签名（解 Iteration D 编译失败）**

⚠️ **F1.2 R1 修订**：grep 结果显示 `[Tool]` / `(Tool) -> Void` 仍出现在 Toolbar/Palette 真实代码：

```bash
grep -n "public func show" SliceAIKit/Sources/Windowing/FloatingToolbarPanel.swift SliceAIKit/Sources/Windowing/CommandPalettePanel.swift
# CommandPalettePanel.swift:27:    public func show(tools: [Tool], preview: String?, onPick: @escaping (Tool) -> Void)
# FloatingToolbarPanel.swift:57:    public func show(tools: [...]
```

**FloatingToolbarPanel.swift line 57 改 show 签名**：

```swift
// 改前：
// public func show(tools: [Tool], anchor: CGPoint, ..., onPick: @escaping (Tool) -> Void)
// 改后：
public func show(
    tools: [V2Tool],
    anchor: CGPoint,
    // ... 其他既有参数（按真实 line 57 签名）
    onPick: @escaping @MainActor (V2Tool) -> Void
)
```

函数体内任何 `tool.systemPrompt` / `tool.userPrompt` 等直接 v1 字段访问都不再可用——FloatingToolbarPanel 只用 `tool.name` / `tool.id` 等 V2Tool 顶层字段做按钮渲染，无需深入 `kind`。

**CommandPalettePanel.swift line 27 同样改 show 签名**：

```swift
public func show(
    tools: [V2Tool],
    preview: String?,
    onPick: @escaping @MainActor (V2Tool) -> Void
)
```

> **note**：Toolbar/Palette `show` 是被 `AppDelegate` 调用的——`tryCaptureAndShowToolbar(_:)`（mouseUp 浮条路径，AppDelegate.swift:248）+ `showCommandPalette()`（⌥Space 命令面板路径，AppDelegate.swift:306）。caller 端 `tools: container.configStore.current().tools` 在 Task 7 Iteration E reload 切换后即返回 `[V2Tool]`；类型自动匹配。
>
> `onPick` 闭包内必须按 caller 路径显式传 `triggerSource`：
>
> - **mouseUp 浮条路径**：`tryCaptureAndShowToolbar` 的 `onPick: { [weak self] tool in self?.execute(tool: tool, payload: payload) }` —— 用 `execute` 默认参数 `.floatingToolbar`，可省略。
> - **⌥Space 命令面板路径**：`showCommandPalette` 的 `onPick: { [weak self] tool in self?.execute(tool: tool, payload: payload, triggerSource: .commandPalette) }` —— **必须显式传 `.commandPalette`**，否则会被 execute 默认参数错误标记为 `.floatingToolbar`。审计这一点的 grep gate 见 §Iteration J Step J0 gate 7（audit-fix 2026-04-28 新增；编号 6 为 R9 walking back 删除的 R8 gate 历史槽位，特意跳过避免与历史标注冲突）。

- [ ] **Step F1: 改 SettingsScene.swift 的 ViewModel 类型引用**

把 `SettingsScene.swift` 内 `@StateObject var viewModel: SettingsViewModel` 这种引用都跟随；如果有 init 参数 `Tool` / `Provider` 改为 `V2Tool` / `V2Provider`。

- [ ] **Step F2: 改 ToolEditorView.swift binding（D-29 + F5.1 R5 修订：处理 String? optional 字段 + Round-1 修订：providerId / displayMode 改 V2 路径）**

> **F5.1 R5 修订**：`PromptTool.systemPrompt: String?`（M1 已合 main，对照真实 `SliceAIKit/Sources/SliceCore/Tool.swift:9` 与等价 V2 PromptTool）；`Binding<String>` 的 getter 必须返回 `String` 而非 `String?`，否则 `Binding(get:set:)` 类型不匹配 + Step F5 编译失败。所有 String? 字段必须用 `?? ""` 桥接，setter 把空字符串映射回 nil 与"清空 = 删除字段"语义对齐。
>
> **Round-1 codex review 2026-04-28 修订（finding R1.1）**：原 F2 binding 表只覆盖 6 个字段（systemPrompt/userPrompt/temperature/variables/modelId/description），**完全漏掉 ToolEditorView.swift 真实存在的 v1-only 绑定 `$tool.providerId` (line 168) 和 `$tool.displayMode + DisplayMode.allCases` (line 214-216)**。V2Tool 没有顶层 `providerId`（仅 PromptTool.provider 内嵌），切 V2 后 line 168 编译失败；V2Tool 顶层有 `displayMode: PresentationMode`（不是 v1 `DisplayMode`），`DisplayMode.allCases` 调用对 PresentationMode 不工作 + 私有 extension `DisplayMode.displayLabel` 也只对 v1 enum 写。这两点会让 Step F5 SettingsUI 编译门禁失败 + D-29 视觉等价无落点。本节 binding 表已扩展至 9 个字段，并补 Picker 改造步骤——见下表 + Step F3 修订。

按 D-29 binding 表 + F5.1 真实字段类型 + Round-1 R1.1 修订（**新增 providerId / displayMode 行**）：

| ToolEditorView 字段 | 来源（V2 路径） | 真实类型 | binding 处理 |
|---|---|---|---|
| `systemPrompt` | PromptTool（kind 内） | `String?` | extractor + getter `?? ""`，setter `nil` if empty |
| `userPrompt` | PromptTool（kind 内） | `String` | extractor + getter / setter 直传（无需 `?? ""`） |
| `temperature` | PromptTool（kind 内） | `Double?` | extractor + getter `?? 0.3`（保 v1 默认值），setter 写回 `Double` |
| `variables` | PromptTool（kind 内） | `[String: String]` | 集合 binding 用 var-let extract（见模板）；保持 v1 variablesCard / addVariable 调用形态 |
| `modelId` | PromptTool.provider .fixed | `String?` | extractor 解构 `.fixed(let providerId, let modelId)`；setter 重新构造 `.fixed(providerId, newModel?)` |
| `providerId` | PromptTool.provider .fixed | `String` | 同上但提取 / 写回 `providerId` 字段；**v0.2 仅支持 `.fixed` case，UI 层不暴露 `.capability` / `.cascade`**（与 §Step F2 末尾 v0.2 范围一致） |
| `description` | V2Tool（顶层） | `String?` | 直接 `tool.description` 读写 + `?? ""` 桥（同 systemPrompt 处理；无需 PromptTool extractor） |
| `displayMode` | V2Tool（顶层） | `PresentationMode` | 直接 `tool.displayMode` 读写（不进 PromptTool）；**Picker 数据源用 `editablePresentationModes` 白名单**，既不用 `DisplayMode.allCases`，也不用 `PresentationMode.allCases`；**displayLabel extension 改写到 `PresentationMode`**（具体见 Step F3 修订） |
| `labelStyle` | V2Tool（顶层） | `ToolLabelStyle` | 直接 `tool.labelStyle` 读写；既有 `Picker` 调用 `style.displayLabel` 仍可用（ToolLabelStyle 已有 displayLabel） |
| `name` / `icon` / `tags` | V2Tool（顶层） | `String` / `String` / `[String]` | 直接读写顶层；切 V2 后类型不变 |

PromptTool extractor 模板（systemPrompt / modelId 等 `String?` 字段统一形状）：

```swift
// 改前：tool.systemPrompt
// 改后：（PromptTool extractor — F5.1 R5 处理 String?）
private var systemPromptBinding: Binding<String> {
    Binding(
        get: {
            if case .prompt(let promptTool) = self.tool.kind {
                return promptTool.systemPrompt ?? ""   // F5.1 R5：String? → String
            }
            return ""
        },
        set: { newValue in
            if case .prompt(var promptTool) = self.tool.kind {
                // F5.1 R5：清空映射回 nil，避免持久化空字符串污染 schema
                promptTool.systemPrompt = newValue.isEmpty ? nil : newValue
                self.tool.kind = .prompt(promptTool)
            }
        }
    )
}

// userPrompt 非 optional — 直接读写
private var userPromptBinding: Binding<String> {
    Binding(
        get: {
            if case .prompt(let promptTool) = self.tool.kind {
                return promptTool.userPrompt
            }
            return ""
        },
        set: { newValue in
            if case .prompt(var promptTool) = self.tool.kind {
                promptTool.userPrompt = newValue
                self.tool.kind = .prompt(promptTool)
            }
        }
    )
}

// providerId binding — Round-1 R1.1 新增 / Round-3 R3.1 修订（切 provider 时清空 modelId）
// V2Tool 没有顶层 providerId，必须解构 PromptTool.provider .fixed。
//
// **Round-3 R3.1 修订**：原 setter 保留旧 modelId 是错的——真实 PromptExecutor.swift:267 写
//   `if case .fixed(_, let modelId) = selection, let modelId { return modelId }`，
// ProviderResolver.swift:55 用 `case .fixed(let providerId, _):` 显式忽略 modelId。这意味着
// 一个 modelId 非 nil 的 .fixed selection 会被原样发给新 provider，跨供应商时会发一个对方不识别
// 的模型字符串（如 OpenAI gpt-4o-mini 发给 DeepSeek），请求直接失败。**正确语义：切 provider 时
// modelId 必须清空（== nil），让 PromptExecutor.resolveModel 走 v1Provider.defaultModel 分支**。
private var providerIdBinding: Binding<String> {
    Binding(
        get: {
            if case .prompt(let promptTool) = self.tool.kind,
               case .fixed(let providerId, _) = promptTool.provider {
                return providerId
            }
            return ""   // .capability / .cascade case：v0.2 UI 不暴露；返回空让 Picker 显示首项或"请先添加 Provider"
        },
        set: { newProviderId in
            if case .prompt(var promptTool) = self.tool.kind {
                // Round-3 R3.1：切 provider 必须清 modelId；否则 PromptExecutor 会把旧 modelId 发给新 provider
                promptTool.provider = .fixed(providerId: newProviderId, modelId: nil)
                self.tool.kind = .prompt(promptTool)
            }
        }
    )
}

// modelId binding — Round-1 R1.1 新增；同源于 PromptTool.provider .fixed，仅改 modelId 部分
private var modelIdBinding: Binding<String> {
    Binding(
        get: {
            if case .prompt(let promptTool) = self.tool.kind,
               case .fixed(_, let modelId) = promptTool.provider {
                return modelId ?? ""
            }
            return ""
        },
        set: { newModelText in
            if case .prompt(var promptTool) = self.tool.kind,
               case .fixed(let providerId, _) = promptTool.provider {
                let normalized: String? = newModelText.isEmpty ? nil : newModelText
                promptTool.provider = .fixed(providerId: providerId, modelId: normalized)
                self.tool.kind = .prompt(promptTool)
            }
        }
    )
}

// temperature binding — F5.1 R5 提到了 Double formatter 桥但未给完整模板；本轮补全
private var temperatureBinding: Binding<Double> {
    Binding(
        get: {
            if case .prompt(let promptTool) = self.tool.kind {
                return promptTool.temperature ?? 0.3   // v1 既有默认值
            }
            return 0.3
        },
        set: { newValue in
            if case .prompt(var promptTool) = self.tool.kind {
                promptTool.temperature = newValue
                self.tool.kind = .prompt(promptTool)
            }
        }
    )
}

// variables binding — F5.1 R5 提到了"集合 binding"但未给完整模板；本轮补全
// 注意：variables 是 [String: String]，SwiftUI 没有现成的 dict binding；ToolEditorView line 254/286/319 用 keys.sorted() + 单 key binding 的模式，
// 改造时把 `tool.variables` 替换为 `variablesAccessor` (computed var) 用 PromptTool extractor 暴露 read，单 key write 复用 set 模式。
private var variablesAccessor: [String: String] {
    if case .prompt(let promptTool) = self.tool.kind {
        return promptTool.variables
    }
    return [:]
}

private func setVariableValue(_ value: String, for key: String) {
    if case .prompt(var promptTool) = self.tool.kind {
        promptTool.variables[key] = value
        self.tool.kind = .prompt(promptTool)
    }
}

private func removeVariable(forKey key: String) {
    if case .prompt(var promptTool) = self.tool.kind {
        promptTool.variables.removeValue(forKey: key)
        self.tool.kind = .prompt(promptTool)
    }
}

private func addVariable(_ key: String) {
    let trimmed = key.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return }
    if case .prompt(var promptTool) = self.tool.kind {
        guard promptTool.variables[trimmed] == nil else { return }
        promptTool.variables[trimmed] = ""
        self.tool.kind = .prompt(promptTool)
    }
}
```

> **note**：v0.2 ToolEditorView 仅暴露 `.prompt` kind 编辑（D-29 决议）。三态切换器 / contexts / sideEffects / advanced ProviderSelection 都隐藏。`providerIdBinding` 的 getter / setter 假设 `promptTool.provider` 永远是 `.fixed` case（addTool 创建时即写 `.fixed`，UI 不提供切到 `.capability` / `.cascade` 的入口）；若 implementer 未来加 capability / cascade UI，需要扩 ProviderSelection 切换逻辑。
> **F5.1 R5 反模式警告**：`Binding<String>` getter 直接 `return promptTool.systemPrompt`（无 `?? ""`）会让 Swift 编译器报 `Cannot convert value of type 'String?' to expected argument type 'String'`。所有 PromptTool 内 `String?` 字段（systemPrompt / modelId / description）binding 路径都必须按上面模板加 `?? ""`。
> **Round-1 R1.1 增量替换清单**（implementer 改 ToolEditorView.swift 时按本表逐行替换 v1 → V2 binding 调用）：
>
> | 真实代码行 | v1 写法 | V2 改写 |
> |---|---|---|
> | line 85-86 | `tool.description` get/set 闭包 | 不变（V2 顶层仍是 `description: String?`） |
> | line 99 | `$tool.labelStyle` | 不变（V2 顶层仍是 `labelStyle: ToolLabelStyle`） |
> | line 125-126 | `tool.systemPrompt` get/set 闭包 | 改用 `systemPromptBinding` |
> | line 142 | `$tool.userPrompt` | 改用 `userPromptBinding` |
> | line 168 | `$tool.providerId` | 改用 `providerIdBinding` |
> | line 183-184 | `tool.modelId` get/set 闭包 | 改用 `modelIdBinding` |
> | line 198-199 | `tool.temperature` get/set 闭包 | 改用 `temperatureBinding` |
> | line 205 | `tool.temperature ?? 0.3`（display） | 改用 `temperatureBinding.wrappedValue`（保持 display 等价） |
> | line 214-216 | `$tool.displayMode + DisplayMode.allCases` | 见 Step F3（直接 `$tool.displayMode` + `editablePresentationModes` 白名单） |
> | line 243+ | `tool.variables.isEmpty` 等 | 替换为 `variablesAccessor.isEmpty` 等同义读 |
> | line 254 | `Array(tool.variables.keys.sorted())` | 替换为 `Array(variablesAccessor.keys.sorted())` |
> | line 286-287 | `tool.variables[key]` get/set 闭包 | 改用 `Binding(get: { variablesAccessor[key] ?? "" }, set: { setVariableValue($0, for: key) })` |
> | line 296 | `tool.variables.removeValue(forKey: key)` | 改用 `removeVariable(forKey: key)` |
> | line 319-320 | `tool.variables[trimmed] = ""` | 改用 `addVariable(trimmed)` |

- [ ] **Step F3: 改 ToolEditorView "展示模式" Picker 适配 V2 PresentationMode + 加 v0.2 提示文字（D-30b 风险段 + Round-1 R1.1 修订）**

> **Round-1 codex review 2026-04-28 修订（finding R1.1）**：原 F3 只提"加提示文字"，没改 Picker binding 类型。真实 ToolEditorView line 214-216 用 `Picker("", selection: $tool.displayMode) { ForEach(DisplayMode.allCases, ...) { Text(mode.displayLabel) } }`，line 393-401 有 `private extension DisplayMode { var displayLabel }`。V2 切换后：
> 1. `$tool.displayMode` 类型从 v1 `DisplayMode` 变成 `PresentationMode`（V2Tool.swift:26 + OutputBinding.swift:29）；Picker 编译器接受（types 都 Hashable + CaseIterable），但...
> 2. `DisplayMode.allCases` 仍引用 v1 enum，本 step 单 commit 内 v1 `DisplayMode` 还存在（M3.0 Step 1 的 5 步 rename 把 v1 删除是 Task 10 的事），但即使如此，混用 v1 enum 跟 V2 字段类型会让 ForEach 给出 v1 case 但 Picker 期望 V2 case，运行时 selection 写不进 `tool.displayMode`。
> 3. `mode.displayLabel` 调用对 v1 DisplayMode case 走私有 extension；切到 PresentationMode 后该 extension 不可达，编译失败。
>
> 修法：Picker 的 ForEach 改用 `editablePresentationModes` 白名单（**Round-2 R2.1 修订** — 见下方代码块）+ 加本地 `private extension PresentationMode { var displayLabel: String }` 复制 v1 displayLabel 逻辑。**Round-2 R2.2 修订（本 loop = M3 plan 第三次 codex review，2026-04-29）**：原文写"原 `private extension DisplayMode + displayLabel`（line 393-401）保留不删（v1 DisplayMode 仍存在到 Task 10），等 Task 10 删 v1 类型时一起清理"是错的——v1 `DisplayMode` 类型定义在 `SliceAIKit/Sources/SliceCore/Tool.swift`（line 14 `public var displayMode: DisplayMode` 与 enum 同 file，参 Tool.swift 1-80 行），**Task 8 (M3.0 Step 2)** 会 `git rm Tool.swift` 删掉 v1 DisplayMode 类型；那时 ToolEditorView.swift line 393-405 的 `private extension DisplayMode { displayLabel }` 引用的类型已不存在 → Step 2 commit 即编译失败（违反每步 4 关 CI gate）。即使把删除拖到 Task 10，**Task 10 (M3.0 Step 4)** 把 V2 `PresentationMode` rename 回 `DisplayMode` 后，下方新加的 `private extension PresentationMode { displayLabel }`（rename 后变成 `private extension DisplayMode { displayLabel }`）会与残留的旧 extension **同名同成员冲突**（Swift 同 file 不允许多个同名 extension 上有同名 member）。**正确做法**：本 step F3 内**同步删除** ToolEditorView.swift line 393-405 旧 `private extension DisplayMode + displayLabel`（详见下方代码块后的"Round-2 R2.2 同步删除"动作）；§J0 新增 gate 10 grep `private extension DisplayMode` / `DisplayMode.allCases` 必须 0 命中以兜底。

把 ToolEditorView.swift line 214-221 改为（**Round-2 R2.1 修订：Picker 数据源用 v1 等价子集，不直接用 `PresentationMode.allCases`**）：

```swift
// 展示模式 Picker — Round-1 R1.1：V2Tool.displayMode 类型是 PresentationMode（不是 v1 DisplayMode）
// Round-2 R2.1：PresentationMode 真实 6 个 case（window/bubble/replace/file/silent/structured，
//   见 OutputBinding.swift:29-41），但 v0.2 仅 v1 三态等价（D-29 视觉/行为等价边界）。Picker 数据源
//   显式列举三个子集 case，禁止用 PresentationMode.allCases —— 否则会暴露 file/silent/structured
//   三个 v0.2 还未实现的模式给用户，且 ExecutionEngine 在 v0.2 阶段都 fallback 到 window
//   （D-30b），用户保存的非 window 模式无意义。
SettingsRow("展示模式") {
    Picker("", selection: $tool.displayMode) {   // V2Tool.displayMode: PresentationMode
        ForEach(Self.editablePresentationModes, id: \.self) { mode in
            Text(mode.displayLabel).tag(mode)
        }
    }
    .pickerStyle(.menu)
    .labelsHidden()
}

// v0.2 D-30b 风险提示（只展示，不影响 Picker 行为）
Text("v0.2 暂时全部以窗口模式展示，Phase 2 起 bubble / replace 等模式生效")
    .font(.caption)
    .foregroundStyle(.secondary)
```

在 `ToolEditorView` struct 内部加一个静态白名单（与 Picker 同 file 同 type；让"v0.2 暴露子集"成为可被 grep 检索的明确边界）：

```swift
// MARK: - v0.2 可编辑展示模式白名单 — Round-2 R2.1 新增
//
// 显式列举与 v1 DisplayMode 等价的三个 case，避免直接用 PresentationMode.allCases 暴露
// file/silent/structured 三个 v0.2 还未实现的模式给用户（D-29 视觉/行为等价边界）。
// 若 Phase 2 加 bubble / replace UI 实装，先在这里加 case，再放开 Picker 暴露。
private static let editablePresentationModes: [PresentationMode] = [.window, .bubble, .replace]
```

在 ToolEditorView.swift 文件**末尾**追加 PresentationMode 的同名 extension，并在本 step 内同步删除旧 `private extension DisplayMode { ... displayLabel }`。**Round-2 R2.1 修订：switch 必须 exhaustive 覆盖 6 个 case**（v0.2 不暴露的 3 个 case 也要返回字符串以满足 Swift exhaustive switch 编译要求）；**Round-2 R2.2 修订**：旧 DisplayMode extension 不能保留，否则 Task 8 删除 v1 `DisplayMode` 后会编译失败，Task 10 rename 后还会产生同名成员冲突。

```swift
// MARK: - PresentationMode + displayLabel — Round-1 R1.1 新增 / Round-2 R2.1 exhaustive 修订
//
// V2Tool.displayMode 类型是 PresentationMode（OutputBinding.swift:29-41 共 6 case），不是 v1 DisplayMode。
// Picker 的 Text(mode.displayLabel) 调用需要 PresentationMode case 的 displayLabel；本 extension 与 v1
// DisplayMode displayLabel 字符串等价（D-29 视觉等价 — 只对 v0.2 暴露的 3 个 case）。
// 旧 `private extension DisplayMode` 必须在本 step 同步删除，避免后续 Task 8/10 编译冲突。
//
// Round-2 R2.1：PresentationMode 是 enum 必须 exhaustive switch；file/silent/structured 三个 v0.2
// 不暴露的 case 也要 case 化返回内部标签（即使不展示给用户也要编译通过）。Picker 数据源已用
// editablePresentationModes 白名单挡住 — 这里是兜底，避免未来其他地方意外用到 displayLabel 时崩溃。
private extension PresentationMode {
    var displayLabel: String {
        switch self {
        case .window:     return "窗口"
        case .bubble:     return "气泡"
        case .replace:    return "原地替换"
        // v0.2 不暴露给 UI 的 3 个 case — 返回内部标签兜底，编译期 exhaustive 要求
        case .file:       return "file"
        case .silent:     return "silent"
        case .structured: return "structured"
        }
    }
}
```

**Round-2 R2.2 同步删除 ToolEditorView.swift line 393-405 旧 v1 DisplayMode extension**（必须与上方 PresentationMode displayLabel extension 在同一 commit 落地——本 step F3 是 M3.0 Step 1 内的子步骤，commit 边界即 M3.0 Step 1 commit）：

把 ToolEditorView.swift line 393-405 整段（含 `// MARK: - DisplayMode + displayLabel` 注释）删除：

```swift
// MARK: - DisplayMode + displayLabel
//
// 为 DisplayMode 补充本地化展示标签（文件内 extension，避免污染 SliceCore）
private extension DisplayMode {
    /// 用于 Picker 展示的中文标签
    var displayLabel: String {
        switch self {
        case .window:  return "浮窗"
        case .bubble:  return "气泡（v0.2）"
        case .replace: return "替换（v0.2）"
        }
    }
}
```

> **删除后 grep 验证**：`rg "private extension DisplayMode|DisplayMode\\.allCases" SliceAIKit/Sources/SettingsUI/ToolEditorView.swift` 必须 0 命中（§J0 gate 10 兜底）。
> **理由回顾**：v1 `DisplayMode` 类型在 Task 8 (M3.0 Step 2) `git rm Tool.swift` 时被删；ToolEditorView 内的旧 extension 引用类型即不存在 → Step 2 commit 编译失败。Task 10 (M3.0 Step 4) PresentationMode → DisplayMode rename 后旧 extension 又会与新 PresentationMode displayLabel extension 同名同成员冲突。F3 同步删除是唯一可行的实施顺序。
> **保留的 ToolLabelStyle extension**（line 407-419 `private extension ToolLabelStyle { displayLabel }`）**不动**——`ToolLabelStyle` 在 V2 切换中不变（V2Tool.labelStyle 仍是 ToolLabelStyle 类型），与本 finding 无关。

- [ ] **Step F4: 改 ProviderEditorView.swift binding（D-29 + F5.1 R5 修订：处理 baseURL: URL? optional）**

> **F5.1 R5 修订**：`V2Provider.baseURL: URL?`（M1 已合 main，对照 `SliceAIKit/Sources/SliceCore/V2Provider.swift:20`，`.anthropic` / `.gemini` 协议族允许 nil；`.openAICompatible` / `.ollama` 在 `validate()` 中强制非 nil）。真实 v1 ProviderEditorView 多处把 `provider.baseURL` 当 non-optional `URL` 用，切 V2 后会编译失败：
> - `ProviderEditorView.swift:76` `baseURLText = provider.baseURL.absoluteString` — `URL?` 无 `.absoluteString`
> - `ProviderEditorView.swift:213` `try await onTestKey(key, provider.baseURL, provider.defaultModel)` — `onTestKey` 签名是 `(String, URL, String)`，`URL?` 无法直传
> - `ProviderEditorView.swift:109-110` `if let url = URL(string: newValue) { provider.baseURL = url }` — `URL` 赋值给 `URL?` 是合法（隐式包），无需改

D-29 binding 调整：

1. **`provider.kind` 写死 `.openAICompatible`**（v0.2 不暴露 picker；保存时若 baseURL == nil → `V2Provider.validate()` 抛 `.validationFailed("...requires non-nil baseURL")`，UI 必须 guard）
2. **`provider.capabilities` 写死 `[]`**（v0.2 不暴露 capability picker；M2 ProviderResolver 在 capabilities 为空时只用 defaultModel 不做能力路由）
3. **baseURL: URL? 三处编译失败修复（必须逐字 patch）**：

   ```swift
   // 改前 ProviderEditorView.swift:76
   baseURLText = provider.baseURL.absoluteString
   // 改后（F5.1 R5）：URL? → String，nil 显示空字符串
   baseURLText = provider.baseURL?.absoluteString ?? ""
   ```

   ```swift
   // 改前 ProviderEditorView.swift:213（testKey() async 内）
   try await onTestKey(key, provider.baseURL, provider.defaultModel)
   // 改后（F5.1 R5）：guard URL? 非 nil 才调用 onTestKey；nil 显示错误消息
   guard let baseURL = provider.baseURL else {
       testMessage = ProviderStatusMessage(
           text: "测试失败：Base URL 未配置",
           isError: true
       )
       isTesting = false
       print("[ProviderEditorView] testKey: baseURL is nil — skip test")
       return
   }
   try await onTestKey(key, baseURL, provider.defaultModel)
   ```

4. **保留视觉等价的字段**：`name` / `defaultModel` / `apiKey` / 测试连接行为均不变；只对 baseURL 做 optional 处理。
5. **`provider.kind` / `provider.capabilities` 在 SettingsScene.addProvider 创建时已写死**（Iteration E.Step E3 已修订，对应 F5.1 R5 fix 路径）；ProviderEditorView 只读，不暴露给 UI。

> **note**：v0.2 D-29 视觉等价硬约束 + F5.1 R5 编译可行性：implementer 必须**两处都改**（line 76 + line 213），不要只改其中一处。Step F5 `swift build` 会同时验证两处。
> **F5.1 R5 反模式警告**：把 `provider.baseURL` 当 `URL` 用（`provider.baseURL.absoluteString` / `f(provider.baseURL)`）会让 Swift 编译器报 `Value of optional type 'URL?' must be unwrapped`。切到 V2Provider 后**所有** baseURL 访问点都必须 `?.absoluteString ?? ""`（read 路径）或 `guard let` / `if let`（write / pass 路径）。

- [ ] **Step F5: 编译验证**

Run: `cd SliceAIKit && swift build 2>&1 | tail -30`
Expected: SettingsUI 全部模块编译通过

### Iteration G: MenuBarController + AppDelegate + SettingsViewModel 共 6 处 configStore.current() audit【F8.2】

> **Audit fix（2026-04-28）**：原 plan 写 "7 处" 是错的。grep 真实命中：
> - MenuBarController.refreshConfigStateIndicator (line 67) — 1 处
> - AppDelegate.applicationDidFinishLaunching 主题初始化 Task (line 89) — 1 处
> - AppDelegate.reloadHotkey (line 159) — 1 处
> - AppDelegate.onMouseUp (line 229) — 1 处
> - AppDelegate.showCommandPalette (line 309) — 1 处
> - SettingsViewModel.reload (line 85) — 1 处（Iteration E.Step E2 已改）
>
> 合计 **6 处**；本 Iteration 改前 5 处（SettingsViewModel.reload 已在 E2 完成）。

- [ ] **Step G1: 改 MenuBarController.swift line 67**

把：

```swift
let cfg = await container.configStore.current()
```

改为（注意需要错误策略——UI 路径 catch 后 log skip 不弹 alert）：

```swift
do {
    let cfg = try await container.configStore.current()
    // ... 既有逻辑
} catch {
    // F8.2 UI 路径策略：log skip 不弹 alert（避免抢屏；用户配置损坏走启动 NSAlert 链路兜底）
    Logger(subsystem: "com.sliceai.app", category: "menubar").warning("configStore.current() failed: \(error.localizedDescription, privacy: .private)")
    return
}
```

- [ ] **Step G2: 改 AppDelegate 4 处 configStore.current()（line 89/159/229/309）**

每处都按 G1 同样的 do/catch + log skip 模式改。具体 4 处的 caller method（grep 验证 2026-04-28）：

| Line | Caller method | 用途 |
|---|---|---|
| 89 | `applicationDidFinishLaunching` 内主题初始化 Task | 读 cfg.appearance 同步给 ThemeManager |
| 159 | `reloadHotkey()` | 读 cfg.triggers.commandPaletteEnabled 决定是否注册 ⌥Space |
| 229 | `onMouseUp()` | 读 cfg.triggers.floatingToolbarEnabled + triggerDelayMs |
| 309 | `showCommandPalette()` | 读 cfg.tools 喂给 commandPalette.show |

策略一致——失败就 skip 当前 UI 动作不抢屏（与 D-27 启动 NSAlert 区分：UI 路径要求避免抢屏，配置错误依赖启动链路兜底）。

- [ ] **Step G3: 改 SettingsViewModel.swift line 85（已在 Iteration E.Step E2 改过 reload；这里若有其他 configStore.current() 引用同步加 try）**

```
grep -n "configStore.current\|store.current" SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift
```

每处都按 E2 模式（loadError 暴露写入 @Published 字段；audit-fix 2026-04-29：v0.2 D-27 架构下 loadError 永远 nil，UI 不消费此字段，仅作 Phase 2 future hook，详见 Step E4.5 R9 walking back 论证）。

- [ ] **Step G4: grep gate 验证 0 漏改**

```
grep -rn "await .*configStore\\.current\\(\\|await .*store\\.current\\(" SliceAIApp/ SliceAIKit/Sources/SettingsUI/ | grep -v "try await"
```
Expected: 0 命中（所有 await ...current() 都是 try await）

### Iteration H: AppContainer 删 v1 装配字段 + rename v2ConfigStore → configStore

> **audit-fix 2026-04-29 — 子步骤强制顺序约束**：本 Iteration 内的子步骤 **1 → 2 → 3 → 4 → 5** 必须严格按顺序执行，不可对调。
> - 子步骤 1（删旧 v1 `configStore` 字段声明）必须先于子步骤 2（rename `v2ConfigStore` → `configStore`）。如果先 rename 再删旧字段，rename 那一刻同名字段会同时存在两个 `configStore`，Swift 编译器报 `invalid redeclaration of 'configStore'`，整个文件直接编译失败。
> - 子步骤 3（删 bootstrap() 内 v1 装配代码段）必须先于子步骤 4（bootstrap() 内 `v2ConfigStore` 全部 rename），原理同上——bootstrap() 函数体内的同名局部变量也会冲突。
> - 子步骤 5（init 参数列表删 v1 字段）依赖子步骤 1 已完成；implementer 必须确认 1 已落地再改 init 签名，否则 init 调用方仍会传 v1 类型。
> - 实操推荐：每完成一个子步骤就跑一次 `cd SliceAIKit && swift build 2>&1 | tail -30` 看错误是否符合预期；不要一次性五步全做完才编译。

- [ ] **Step H1: 删 v1 字段 + rename**

回到 `SliceAIApp/AppContainer.swift`：

1. 删除 v1 字段声明（**必须先于 step 2**）：
   ```swift
   let configStore: FileConfigurationStore       // 删
   let toolExecutor: ToolExecutor                // 删
   ```

2. 把 `v2ConfigStore: V2ConfigurationStore` rename 为 `configStore: V2ConfigurationStore`（注意：类型名 V2ConfigurationStore 还不变，Step 3 才 rename 类型）：
   ```swift
   let configStore: V2ConfigurationStore         // 原 v2ConfigStore
   ```

3. 删除 bootstrap() 内 v1 装配代码段（**必须先于 step 4**）：
   ```swift
   // 删：
   let configStore = FileConfigurationStore(fileURL: FileConfigurationStore.standardFileURL())
   let toolExecutor = ToolExecutor(...)

   // SettingsViewModel 暂时引用 v2ConfigStore — 子步骤 4 才会把局部变量统一 rename 为 configStore
   // F2.1 R1 修订（4th-loop 2026-04-30）：子步骤 3 完成时 v1 `configStore` 局部变量已删，且 v2 还没改名；
   // 此处必须写 v2ConfigStore，否则 swift build 报 `cannot find 'configStore' in scope`。
   let settingsViewModel = SettingsViewModel(store: v2ConfigStore, keychain: keychain)
   ```

4. 把 bootstrap() 内 **所有** `v2ConfigStore` 引用 rename 为 `configStore`（同时调整 init 调用参数列表）：

   ```swift
   let v2URL = appSupport.appendingPathComponent("config-v2.json")
   let legacyURL = appSupport.appendingPathComponent("config.json")
   let configStore = V2ConfigurationStore(fileURL: v2URL, legacyFileURL: legacyURL)  // ← 改名
   _ = try await configStore.current()
   ```

   显式 rename 清单（implementer 必须每一项都改完，再跑编译）：

   | 位置（grep 关键字） | 子步骤 3 后样子 | 子步骤 4 完成后 |
   |---|---|---|
   | `let v2ConfigStore = V2ConfigurationStore(...)` 声明 | `let v2ConfigStore = V2ConfigurationStore(fileURL:legacyFileURL:)` | `let configStore = V2ConfigurationStore(fileURL:legacyFileURL:)` |
   | `_ = try await v2ConfigStore.current()` 触发首次迁移 | `_ = try await v2ConfigStore.current()` | `_ = try await configStore.current()` |
   | `SettingsViewModel(store: v2ConfigStore, ...)` 装配 | `SettingsViewModel(store: v2ConfigStore, ...)` | `SettingsViewModel(store: configStore, ...)` |
   | `themeManager.onModeChange = { ... v2ConfigStore ... }`（若 bootstrap() 当前引用 v2ConfigStore） | `... v2ConfigStore ...` | `... configStore ...` |
   | `AppContainer(configStore: v2ConfigStore, ...)` 主 init 调用 | `configStore: v2ConfigStore` | `configStore: configStore` |
   | 任何其它 `v2ConfigStore` 残留 | — | 必须为 0 |

   验证 gate：
   ```bash
   grep -n "v2ConfigStore" SliceAIApp/AppContainer.swift
   ```
   Expected: 0 命中。子步骤 4 完成后 bootstrap() 内不应再出现 `v2ConfigStore` 字面量。

5. 删除 init 参数列表中的 v1 字段：
   ```swift
   private init(
       configStore: V2ConfigurationStore,        // 现在是 v2 类型
       // toolExecutor: ToolExecutor,            // 删
       keychain: KeychainStore,
       ...
   )
   ```

- [ ] **Step H2: 改 themeManager.onModeChange 内 store 引用【F3.1 R3 真实 V2ConfigurationStore API】**

⚠️ **F3.1 R3 修订**：grep V2ConfigurationStore 真实方法（line 18-79）只有 `current() / update(_:) / load() / save(_:)`。**没有 updateAppearance(_:)**。同时 V2Configuration 字段名是 `appearance`（不是 `appearanceMode`）。必须用 read-modify-write 模式：

bootstrap 内（仅一种正确写法 — read-modify-write）：

```swift
let store = configStore  // 现在是 V2ConfigurationStore
themeManager.onModeChange = { @MainActor mode in
    Task {
        do {
            var cfg = try await store.current()
            cfg.appearance = mode  // F3.1 R3：真实字段名 appearance（不是 appearanceMode）
            try await store.update(cfg)  // F3.1 R3：用 update(_:) — 真实没有 updateAppearance(_:) 方法
        } catch {
            // appearance 更新失败静默；CLAUDE.md "无自由日志" 规范
        }
    }
}
```

> **note F3.1 R3**：
> - 不要写 `try await store.updateAppearance(mode)` — V2ConfigurationStore 没有这个方法。
> - 不要写 `cfg.appearanceMode = mode` — V2Configuration 字段名是 `appearance`（来自 v0.1 沿用，没改名）。
> - `update(_:)` 是 actor 方法，async throws — `try? await` 静默吞错符合"无自由日志"规范。

- [ ] **Step H3: 编译验证**

Run: `xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build 2>&1 | tail -30`
Expected: BUILD SUCCEEDED

如果某个 caller 仍引用 `container.toolExecutor` / `container.v2ConfigStore` / 旧 v1 store → 修

### Iteration I: 加 spy tests 覆盖 D-30 / F8.3 / F9.2 / F3.2【F3.4 R3 重写：直接测真实 InvocationGate】

> **F3.4 R3 walking back R2 决议**：R2 写的 `SingleFlightInvocationTests` 用 SpyAdapter copy single-flight 契约——只能证明 SpyAdapter 自己合契约，不能证明生产 ResultPanelWindowSinkAdapter 的真实行为。R3 修订：
> 1. 删除本 Iteration 内 `SingleFlightInvocationTests.swift` 的 SpyAdapter 模式；
> 2. 由 Task 3 新增的 `InvocationGateTests.swift` 替代——直接 import + 测试 `Orchestration.InvocationGate` 真实实现；
> 3. `SingleWriterContractTests.swift`（用 SpyWindowSink 测 OutputDispatcher → sink chunk 写入次数）保留——它测的是 OutputDispatcher 自身契约，spy 只代表 sink 收到 chunk 计数，符合"测真实路径而不是 copy contract"原则。
> 4. 新增 `ExecutionStreamOrderingTests.swift`（fake stream/engine 确定性测试）覆盖 ExecutionEvent → OutputDispatcher → InvocationGate → ResultPanel 的 ordering：先 setActive 再 producer 发首 chunk，验证首段不丢；setActive 之前 cancel 旧 stream 的 defer 不会清新 invocation。

- [ ] **Step I1: ~~创建 SingleFlightInvocationTests.swift（SpyAdapter 模式）~~ — F3.4 R3 删除**

R3 决议：本 Step 删除；single-flight 行为测试由 Task 3.Step 2 创建的 `InvocationGateTests.swift` 直接覆盖（测真实 InvocationGate，含 5 个 case：overlapping / clearIfCurrent guard / R2 race regression / dismiss before first chunk / first chunk after setActive）。本 Iteration 不再创建 SpyAdapter copy。

参考依赖：`InvocationGateTests.swift` 已在 Task 3.Step 2 落地。

> **被替代原因**：SpyAdapter 是 copy 出来的契约 — 实际生产 ResultPanelWindowSinkAdapter 改了 single-flight 实现，SpyAdapter 不会同步变化，会出现"测试通过但生产代码已 broken" 假阳性。F3.4 R3 通过把状态抽到 Orchestration target 的 InvocationGate 解决了这个问题——测真实代码本身。

F3.4 R3 删除：本 Step 旧 SpyAdapter 代码块整段移除——已被 Task 3.Step 2 创建的 `InvocationGateTests.swift` 替代（直接测真实 InvocationGate，不是 copy 出来的 spy）。

- [ ] **Step I2: 加 ExecutionStreamOrderingTests（fake stream/engine 确定性测试）— F3.4 R3 新增；4th-loop R4.X 修订：XCTest 风格统一**

> **4th-loop R4.X 修订（2026-04-30 完整审核）**：旧版本用 Swift Testing `@Suite` / `@Test`，但 OrchestrationTests target 100% XCTest。**修法**：用 XCTest 风格；保留 `@MainActor` class 标记 + 内嵌 `actor ChunkCollector` + 内嵌 `@MainActor final class GateBackedSpySink` 的辅助类型不变。

新建 `SliceAIKit/Tests/OrchestrationTests/AdapterContractTests/ExecutionStreamOrderingTests.swift`：

```swift
import Foundation
import XCTest
@testable import Orchestration
import SliceCore

/// F8.3 ordering + F9.2 single-flight 端到端 fake stream 测试
///
/// **F3.4 R3 + F4.2 R4 修订**：用真实 OutputDispatcher → SinkAdapter（实现 WindowSinkProtocol，
/// 内部调真实 InvocationGate.gatedAppend）的完整路径，而非手写 `if gate.shouldAccept ...` 判断。
/// SinkAdapter 与生产 `ResultPanelWindowSinkAdapter.append` 实现等价（都是 1 行
/// `gate.gatedAppend(...) { sink(...) }`），只是把 panel.append 替换成 spy collector，
/// 因此对 dispatcher → adapter → gate → sink 的整条 chain 都是真实代码路径，不存在假阳性。
@MainActor
final class ExecutionStreamOrderingTests: XCTestCase {

    /// 测试用 sink 收集器；与生产 panel.append 等价 — 接收 String chunk
    actor ChunkCollector {
        var chunks: [String] = []
        func append(_ chunk: String) { chunks.append(chunk) }
    }

    /// 测试 sink — 与生产 ResultPanelWindowSinkAdapter.append 实现等价（仅把 panel.append 换成 collector.append）
    /// 这样 dispatcher → 本 sink 走的是和生产 adapter 同一份 gatedAppend 调用模式
    @MainActor
    final class GateBackedSpySink: WindowSinkProtocol {
        let gate: InvocationGate
        let collector: ChunkCollector

        init(gate: InvocationGate, collector: ChunkCollector) {
            self.gate = gate
            self.collector = collector
        }

        func append(chunk: String, invocationId: UUID) async throws {
            // 与生产 adapter 同一行：gate.gatedAppend 委托
            gate.gatedAppend(chunk: chunk, invocationId: invocationId) { [collector] c in
                Task { await collector.append(c) }
            }
        }
    }

    /// ordering: setActive 之后 dispatcher.handle → sink 收到
    func test_setActiveBeforeFirstChunk_acceptsFirst() async throws {
        let gate = InvocationGate()
        let collector = ChunkCollector()
        let sink = GateBackedSpySink(gate: gate, collector: collector)
        let dispatcher = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()

        // ordering：先 setActive → 再 dispatcher.handle 发 chunk
        gate.setActiveInvocation(invocationId)
        _ = try await dispatcher.handle(chunk: "FIRST", mode: .window, invocationId: invocationId)
        // gatedAppend 内 Task 异步把 chunk 写入 collector — 等一拍
        try await Task.sleep(nanoseconds: 50_000_000)
        let chunks = await collector.chunks
        XCTAssertEqual(chunks, ["FIRST"])
    }

    /// race: setActive 之前 dispatcher.handle → gate 拒绝 → sink 不收到
    func test_firstChunkBeforeSetActive_isDropped() async throws {
        let gate = InvocationGate()
        let collector = ChunkCollector()
        let sink = GateBackedSpySink(gate: gate, collector: collector)
        let dispatcher = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()

        // 错的 ordering：dispatcher.handle 先于 setActive；模拟 R1 Task wrapper 引入的 race
        _ = try await dispatcher.handle(chunk: "LOST", mode: .window, invocationId: invocationId)
        // setActive 才 fire
        gate.setActiveInvocation(invocationId)
        try await Task.sleep(nanoseconds: 50_000_000)

        let chunks = await collector.chunks
        XCTAssertTrue(chunks.isEmpty)  // FIRST 被 drop — gate 在 dispatcher → adapter chain 内拒绝
    }

    /// F9.2 stale defer race: A 的 defer 晚到 不能误清空 B 的 chunk
    func test_staleClearAfterSwitch_doesNotEvictNew() async throws {
        let gate = InvocationGate()
        let collector = ChunkCollector()
        let sink = GateBackedSpySink(gate: gate, collector: collector)
        let dispatcher = OutputDispatcher(windowSink: sink)
        let a = UUID()
        let b = UUID()

        gate.setActiveInvocation(a)
        gate.setActiveInvocation(b)
        gate.clearActiveInvocation(ifCurrent: a)  // A 的 defer 晚到 → ifCurrent guard 应阻止

        _ = try await dispatcher.handle(chunk: "B-OK", mode: .window, invocationId: b)
        try await Task.sleep(nanoseconds: 50_000_000)

        let chunks = await collector.chunks
        XCTAssertEqual(chunks, ["B-OK"])
    }

    /// 4th-loop R5.X 新增：stale event after reopen — A 在 B setActive+open 之后 yield 的事件应被 gate 拒绝
    ///
    /// 模拟 codex post-audit adversarial review 的 race scenario：用户 Regenerate / 连续触发 →
    /// AppDelegate.execute 走"cancel A → setActive B → open B → ..."流程；A 的 consumer Task 在 cancel
    /// 与 setActive(B) 之间因协作式 cancel 仍可能 yield 已 buffered 的 chunk / 终态事件。
    /// 修订后 ordering（setActive 提到 open 之前）确保 gate 在 panel reset 之前就切换；A 的 stale event
    /// 必被 `shouldAccept(invocationId: A)` 返回 false 而拒绝。
    /// 这个测试不模拟 cancel + Task 调度细节（属 SliceAIAppTests target），而是单元化验证 gate 层的不变量：
    /// 一旦 setActive(B) 完成，对 A 的 dispatcher.handle / consumer guard 都返回拒绝。
    func test_staleEventAfterReopen_isDropped() async throws {
        let gate = InvocationGate()
        let collector = ChunkCollector()
        let sink = GateBackedSpySink(gate: gate, collector: collector)
        let dispatcher = OutputDispatcher(windowSink: sink)
        let a = UUID()
        let b = UUID()

        // Phase 1: A active；A 的合法 chunk 应进入 collector
        gate.setActiveInvocation(a)
        _ = try await dispatcher.handle(chunk: "A-CHUNK", mode: .window, invocationId: a)

        // Phase 2: 模拟用户触发 Regenerate / 新工具 — 修订后 ordering：
        //   streamTask?.cancel()                                  // cancel A
        //   container.invocationGate.setActiveInvocation(b)       // 第一道闸门：gate 立刻切到 B
        //   container.resultPanel.open(...)                       // 之后才 reset panel
        gate.setActiveInvocation(b)

        // Phase 3: A 的 stale event 来到（chunk 路径 + 终态路径模拟）
        // 3a: stale chunk via dispatcher → adapter → gate.gatedAppend → 应被 shouldAccept(A)=false 拒绝
        _ = try await dispatcher.handle(chunk: "STALE-A-FINISH-CHUNK", mode: .window, invocationId: a)
        // 3b: 模拟 AppDelegate consumer Task body 内 shouldAccept guard（line 2095）对终态事件的判定
        let staleAcceptedByGate = gate.shouldAccept(invocationId: a)
        XCTAssertFalse(staleAcceptedByGate, "setActive(B) 之后 gate 必须拒绝 A 的 invocation——consumer.handle(.finished/.failed/.notImplemented) 不会被调")

        // Phase 4: B 的合法 chunk
        _ = try await dispatcher.handle(chunk: "B-CHUNK", mode: .window, invocationId: b)
        try await Task.sleep(nanoseconds: 50_000_000)

        // 期望 collector：仅 A-CHUNK（phase 1，A 仍 active 时合法写入）+ B-CHUNK（phase 4）
        // STALE-A-FINISH-CHUNK 被 gate 拒绝，**没有**进入 collector
        let chunks = await collector.chunks
        XCTAssertEqual(chunks, ["A-CHUNK", "B-CHUNK"])
    }
}
```

Run: `cd SliceAIKit && swift test --filter OrchestrationTests.ExecutionStreamOrderingTests`
Expected: 4 PASS

> **note F3.4 R3**：第二个 test (`test_firstChunkBeforeSetActive_isDropped`) 是反向 verification——它**故意演示** race 后果（首段丢失）来证明 plan 强制要求 "setActive 必须 sync 在 stream 创建前调用"（Task 7 Iteration D 已落地）。如果 implementer 误把 setActive 放 Task wrapper，生产代码会出现这个 race；本测试不直接捕获生产 race（需要 SliceAIAppTests target），但通过单元化演示 race 来强化 documentation gate。
>
> **note 4th-loop R5.X**：第四个 test (`test_staleEventAfterReopen_isDropped`) 是 codex post-audit adversarial review 触发的纵深防御 invariant 测试——验证 setActive 提到 open 之前后，A 的 stale event（无论 chunk 路径还是终态路径）都先被 gate 拦截，不再依赖 per-event guard 必须正确放置。implementer 改动 AppDelegate.execute ordering 时，本测试可作为 regression 防御。

- [ ] **Step I3: 加 D-30 单一写入测试（4th-loop R4.X 修订：XCTest 风格统一）**

> **4th-loop R4.X 修订（2026-04-30 完整审核）**：旧版本用 Swift Testing `@Suite` / `@Test` / `#expect`，但 OrchestrationTests target 100% XCTest。**修法**：用 XCTest 风格（`final class : XCTestCase` + `XCTAssertEqual`），与同 target 既有 13 文件同模式。

新建 `SliceAIKit/Tests/OrchestrationTests/AdapterContractTests/SingleWriterContractTests.swift`：

```swift
import Foundation
import XCTest
@testable import Orchestration
import SliceCore

/// F3.2 单一写入所有者契约 — 验证 ExecutionEvent 流的 .llmChunk 不被双写
final class SingleWriterContractTests: XCTestCase {

    /// SpyWindowSink 模拟 ResultPanelWindowSinkAdapter 收 chunk
    actor SpyWindowSink: WindowSinkProtocol {
        var appendCalls: [(chunk: String, invocationId: UUID)] = []
        func append(chunk: String, invocationId: UUID) async throws {
            appendCalls.append((chunk, invocationId))
        }
    }

    /// OutputDispatcher.handle: each chunk appends sink exactly once (.window)
    func test_outputDispatcher_chunkAppendOnce_perChunk() async throws {
        let sink = SpyWindowSink()
        let dispatcher = OutputDispatcher(windowSink: sink)
        let invocationId = UUID()

        // 模拟 5 个 chunk
        for chunk in ["a", "b", "c", "d", "e"] {
            _ = try await dispatcher.handle(chunk: chunk, mode: .window, invocationId: invocationId)
        }

        let calls = await sink.appendCalls
        XCTAssertEqual(calls.count, 5)
        XCTAssertEqual(calls.map(\.chunk), ["a", "b", "c", "d", "e"])
    }
}
```

> **note F3.4 R3**：`test_eventConsumer_doesNotAppendChunkToResultPanel` spy test 真实需要在 SliceAIApp test target 跑（依赖 ResultPanel），plan 期暂时省略 — F3.2 单一写入契约由 ExecutionEventConsumer 内 `case .llmChunk` 仅 logger.debug 不调 panel.append 的代码 + exhaustive switch 编译期保证 + SingleWriterContractTests 测 dispatcher → sink 写入次数 三层覆盖。

Run: `cd SliceAIKit && swift test --filter OrchestrationTests`
Expected: All PASS（含 OutputDispatcherFallbackTests + InvocationGateTests + ExecutionStreamOrderingTests + SingleWriterContractTests + 既有 OrchestrationTests）

#### Mini-spec §M3.2 Exit DoD 测试名映射【audit-fix 2026-04-28 补】

mini-spec §M3.2 Exit DoD 列出了三个测试名约束作为单元化验收门槛。本 plan 落地时按 F3.4 R3 决议**直接测真实 InvocationGate**，废弃 R2 SpyAdapter copy 模式，因此实际落地的测试名与 mini-spec 文字不完全字面对应。implementer 在对照 mini-spec 验收时使用以下映射：

| mini-spec §M3.2 Exit DoD 描述 | 本 plan 落地的真实 test |
|---|---|
| "single-flight invocation 契约（重叠 invocation 拒绝陈旧 chunk）" | Task 3 `InvocationGateTests.test_overlappingInvocations_dropStale` + `test_staleClearAfterSwitch_doesNotEvictNew` |
| "ordering invariant（setActive 先于首 chunk）" | Task 7 Iteration I `ExecutionStreamOrderingTests.test_setActiveBeforeFirstChunk_chunkAccepted` |
| "single writer contract（每 chunk 写入 panel exactly once）" | Task 7 Iteration I `SingleWriterContractTests.test_outputDispatcher_chunkAppendOnce_perChunk` |

> mini-spec R11/R12 alignment 已同步；本映射解释 mini-spec 验收描述与 plan 实际落地测试名的差异，让 implementer 跑测验收时一眼对得上。

### Iteration J: 4 关 CI gate + 单 commit Step 1

- [ ] **Step J0: plan-vs-real-code grep audit【F3.1 R3 必加 + F4.3 R4 修订 exit code】**

R1+R2+R3+R4 累计发现 plan 里有多处臆造的真实 API（DefaultV2Configuration.make / .iconOnly / .appearanceMode / updateAppearance / .execution 漏全仓 audit / Task wrapper 误用 / .validationFailed 无参 / sed \b / R3 改 invocationGate 后 gate 3 pattern 漏匹配 / `rg && echo` 0 命中误判通过 等）。在 4 关 CI gate 之前必须跑下述 grep gate，**任何 gate exit ≠ 0 → 修，全部 exit 0 → 进 Step J1**。

> **F4.3 R4 修订**：
> 1. 把 `rg ... && echo` 模式改成 `if rg ...; then exit 1; fi`——`rg` 0 命中时 exit 1，shell 短路使 `&& echo` 不执行，但脚本整体 exit 0 误判通过。新模式直接用 rg 退出码做正向判定：rg exit 0（有命中）→ shell exit 1；rg exit 1（无命中）→ shell exit 0。
> 2. gate 3 同时匹配 `resultPanelAdapter` + `invocationGate` 两条路径（R3 把 setActive/clearActive 从 adapter 迁到 gate，但 plan 历史步骤里仍可能错调 `await resultPanelAdapter.setActive...` 或新写代码错调 `await container.invocationGate.setActive...`）。
> 3. gate 3 还检查"clear 调用必须带 `ifCurrent:` label"——R2 fix 的关键不变量，丢了就回到 race。

```bash
set -e

echo "=== gate 1: 真实 V2 API 误名 ==="
if rg -n "DefaultV2Configuration\.make\(\)|DefaultConfiguration\.make\(\)|\.iconOnly\b|\bappearanceMode\b|updateAppearance\(" SliceAIApp/ SliceAIKit/ --type swift; then
  echo "FAIL gate 1：真实 API 是 .initial() / .icon / appearance / update(_:)"
  exit 1
fi
echo "PASS gate 1"

echo "=== gate 2: 所有 switch on SliceError 都含 case .execution（exhaustive）==="
# 找所有 switch on SliceError 的 case 列表，过滤"含 .selection 但不含 .execution"的
SLICE_SWITCH=$(rg -n "switch[^{]*\b(SliceError|sliceError)\b" SliceAIApp/ SliceAIKit/ --type swift -A 12 || true)
MISSING=$(echo "$SLICE_SWITCH" | awk '
  /^--/ {
    if (block && block ~ /case[ \t]+\.selection/ && block !~ /case[ \t]+\.execution/) print block
    block = ""; next
  }
  { block = block $0 "\n" }
  END {
    if (block && block ~ /case[ \t]+\.selection/ && block !~ /case[ \t]+\.execution/) print block
  }
')
if [ -n "$MISSING" ]; then
  echo "FAIL gate 2：以下 switch 缺 case .execution（A0.4 已加 InvocationOutcome.ErrorKind.from；implementer 须把新发现的也补全）"
  echo "$MISSING"
  exit 1
fi
echo "PASS gate 2"

echo "=== gate 3: F9.2 race walking back — 不能再有 Task wrapper / 不带 ifCurrent: 的 clear ==="
# Round-4 R4.1 修订（2026-04-28）：旧 3a 单行 await pattern 漏掉两类合法绕过：
#   1) 多行 Task wrapper（`Task { @MainActor in\n    container.invocationGate.setActiveInvocation(id)\n}`）
#   2) 不带 await 的 Task wrapper（@MainActor 同步方法在 @MainActor closure 里不需要 await）
# 这两种绕过都会重新打开 R2/R3 已修过的 race window：setActive 延后到异步任务 → stream 首 chunk 时 active 仍 nil → 丢首段；
# clear 晚到 → 旧 invocation 的 defer 误清空新 invocation 的 active。
# 修法：用 rg -U（multi-line PCRE）抽取整个 `Task { ... }` block，发现内部包含
# `.setActiveInvocation(` 或 `.clearActiveInvocation(` 即 fail——不依赖 await，跨多行匹配。
# 3a) 任何 Task { ... .setActive/.clearActiveInvocation ... } 都禁止（multi-line + 不依赖 await）
if rg -nU "Task\b[^{]*\{[^}]*\.(setActiveInvocation|clearActiveInvocation)\(" SliceAIApp/ --type swift; then
  echo "FAIL gate 3a：Task wrapper 内调用 setActiveInvocation / clearActiveInvocation 被禁；@MainActor sync 方法须直接 sync 调用"
  echo "提示：不论同行 / 多行 / 是否带 await，包在 Task block 都会延后调用 → 重新打开 R2/R3 已修过的丢首 chunk / 误清新 invocation race window"
  exit 1
fi
# 3b) 任何 await 调用 setActive/clearActive 都禁止（@MainActor sync method 不需要 await）
if rg -n "\bawait\b[^;\n]*\.(setActiveInvocation|clearActiveInvocation)" SliceAIApp/ --type swift; then
  echo "FAIL gate 3b：setActive/clearActive 是同步 method，不要 await"
  exit 1
fi
# 3c) clearActiveInvocation 必须带 ifCurrent: label（不带 label 的旧 API 已废弃）
if rg -n "\.clearActiveInvocation\(\)" SliceAIApp/ SliceAIKit/ --type swift; then
  echo "FAIL gate 3c：clearActiveInvocation 必须传 ifCurrent: invocationId（防止 A 的 defer 清空 B）"
  exit 1
fi
# 3d) Round-4 R4.1 新增：setActive/clearActive 直接调用必须出现在 execute(...)、onDismiss、defer 三个上下文之一。
# 这是定位检查不是结构检查——只看相邻上下文是否含 `func execute(` / `onDismiss:` / `defer {`，命中 0 个 → 提示 implementer 确认。
if rg -n "\.(setActiveInvocation|clearActiveInvocation)\(" SliceAIApp/ --type swift > /tmp/cxc-gate3d-callsites.txt; then
  while IFS= read -r line; do
    file=$(echo "$line" | cut -d: -f1)
    lineno=$(echo "$line" | cut -d: -f2)
    # 取该 callsite 上下 8 行；如果都不含 execute/onDismiss/defer 关键词 → fail
    context=$(sed -n "$((lineno-8)),$((lineno+8))p" "$file")
    if ! echo "$context" | grep -qE "func execute\(|onDismiss:|defer\s*\{"; then
      echo "FAIL gate 3d：$file:$lineno setActive/clearActive 调用上下文 ±8 行未发现 execute/onDismiss/defer 关键词；实施时 setActive 应在 execute(...) 内、clearActive 应在 onDismiss 闭包或 streamTask defer 内"
      rm -f /tmp/cxc-gate3d-callsites.txt
      exit 1
    fi
  done < /tmp/cxc-gate3d-callsites.txt
  rm -f /tmp/cxc-gate3d-callsites.txt
fi
echo "PASS gate 3"

echo "=== gate 4: SliceError.configuration(.validationFailed) 必带 String ==="
if rg -n "\.validationFailed\)" SliceAIKit/ SliceAIApp/ --type swift; then
  echo "FAIL gate 4：.validationFailed 必须带固定脱敏字符串 .validationFailed(\"...\")"
  exit 1
fi
echo "PASS gate 4"

echo "=== gate 5: 新 SliceAIApp 文件已注册到 pbxproj ==="
PBXFILE=SliceAI.xcodeproj/project.pbxproj
for F in ResultPanelWindowSinkAdapter ExecutionEventConsumer; do
  for KIND in "PBXBuildFile:in Sources" "PBXFileReference:swift"; do
    LABEL=$(echo "$KIND" | cut -d: -f1)
    if ! grep -q "/\* $F\.swift" "$PBXFILE"; then
      echo "FAIL gate 5：$F.swift 未在 pbxproj 出现（$LABEL 部分至少需 1 行；见 Task 3 Step 3.5 / Task 7 Step C1.5）"
      exit 1
    fi
  done
done
echo "PASS gate 5"

echo "=== gate 7（audit-fix 2026-04-28）：showCommandPalette 必须显式传 triggerSource: .commandPalette ==="
# 不传等于让 execute 走默认参数 .floatingToolbar，污染命令面板路径的 invocation source 标记。
# 在 showCommandPalette 函数体（含 onPick 闭包）内必须能找到至少一处 ".commandPalette"。
# 方法：先把 showCommandPalette 函数体提取出来，再在体内 grep。
PALETTE_BODY=$(awk '
  /func showCommandPalette/ { capture=1; depth=0 }
  capture {
    print
    n_open  = gsub(/\{/, "{")
    n_close = gsub(/\}/, "}")
    depth += n_open - n_close
    if (depth == 0 && n_open + n_close > 0) { capture = 0; print "---END---" }
  }
' SliceAIApp/AppDelegate.swift)
if ! echo "$PALETTE_BODY" | grep -q "\.commandPalette"; then
  echo "FAIL gate 7：showCommandPalette 函数体内未发现 .commandPalette 字面量；onPick 闭包应显式传 triggerSource: .commandPalette"
  echo "提示：execute 默认参数是 .floatingToolbar，不显式传会让命令面板路径被错误标记"
  exit 1
fi
echo "PASS gate 7"

echo "=== gate 8（Round-1 R1.1 2026-04-28）：ToolEditorView 切 V2 后必须删除 v1-only binding ==="
# 切到 V2 后 V2Tool 没有顶层 providerId（仅 PromptTool.provider .fixed 内嵌），ToolEditorView.swift 内任何
# `tool.providerId` / `$tool.providerId` 都是切换不彻底的标志，编译期会报错；本 gate 提前 grep 兜底。
if rg -n "\\\$?tool\\.providerId\\b" SliceAIKit/Sources/SettingsUI/ToolEditorView.swift; then
  echo "FAIL gate 8a：ToolEditorView 仍有 tool.providerId 引用；V2Tool 无该顶层字段，必须用 providerIdBinding（Step F2）"
  exit 1
fi
# DisplayMode.allCases 是 v1 enum 列举；V2Tool.displayMode 类型是 PresentationMode
if rg -n "\\bDisplayMode\\.allCases\\b" SliceAIKit/Sources/SettingsUI/ToolEditorView.swift; then
  echo "FAIL gate 8b：ToolEditorView 仍用 DisplayMode.allCases；V2 切换后必须用 editablePresentationModes 白名单（Step F3 + R2.1）"
  exit 1
fi
echo "PASS gate 8"

echo "=== gate 9（Round-2 R2.1 2026-04-28）：ToolEditorView Picker 不得暴露 v0.2 未实装的 PresentationMode case ==="
# 真实 PresentationMode 有 6 个 case (window/bubble/replace/file/silent/structured)；v0.2 仅暴露前 3 个等价 v1 DisplayMode 的子集。
# 直接用 PresentationMode.allCases 会把 file/silent/structured 暴露给用户 → 用户保存这些 case →
# ExecutionEngine v0.2 阶段 D-30b 全 fallback 到 window，用户行为无意义；必须用 editablePresentationModes 白名单。
if rg -n "PresentationMode\\.allCases" SliceAIKit/Sources/SettingsUI/ToolEditorView.swift; then
  echo "FAIL gate 9a：ToolEditorView 直接用 PresentationMode.allCases；必须用 editablePresentationModes 白名单（Step F3 + R2.1）"
  exit 1
fi
# 兜底：editablePresentationModes 必须存在于 ToolEditorView.swift（白名单声明丢失 = Picker 数据源不存在）
if ! rg -n "editablePresentationModes\\s*:\\s*\\[PresentationMode\\]" SliceAIKit/Sources/SettingsUI/ToolEditorView.swift; then
  echo "FAIL gate 9b：ToolEditorView 缺 editablePresentationModes: [PresentationMode] 静态白名单（Step F3 + R2.1）"
  exit 1
fi
echo "PASS gate 9"

echo "=== gate 10（Round-2 R2.2 2026-04-29，本 loop = M3 plan 第三次 codex review）：ToolEditorView 切 V2 后必须删除旧 v1 DisplayMode extension ==="
# v1 DisplayMode 在 Task 8 (M3.0 Step 2) `git rm SliceCore/Tool.swift` 时被删除；
# ToolEditorView.swift line 393-405 旧 `private extension DisplayMode { displayLabel }` 必须在 Step F3
# 同步删除，否则 Step 2 commit 即编译失败（违反每步 4 关 CI gate）。Task 10 (M3.0 Step 4)
# PresentationMode → DisplayMode rename 后旧 extension 又会与新 PresentationMode displayLabel
# extension 同名同成员冲突（Swift 同 file 不允许多个同名 extension 上同名 member）。
# 注意：编号 6 历史跳过（R8 walking back 删除）；本 loop 新增 gate 从 10 起，不复用 6。
if rg -n "private extension DisplayMode" SliceAIKit/Sources/SettingsUI/ToolEditorView.swift; then
  echo "FAIL gate 10：ToolEditorView 仍含 'private extension DisplayMode'；切 V2 时必须在 Step F3 同步删除（Round-2 R2.2 修订）"
  exit 1
fi
echo "PASS gate 10"

echo "=== gate 11（Round-3 R3.1 2026-04-29，本 loop = M3 plan 第三次 codex review）：ExecutionEventConsumer 不得用 String(describing:) 公开记录 SideEffect / Permission；MCPToolRef 必须 .private ==="
# JSONLAuditLog.scrubSideEffect (line 215-258) 把 SideEffect 各字段 (appendToFile path/header；notify
# title/body；runAppIntent params；callMCP server/tool/params；writeMemory tool/entry) 全 Redaction.scrub；
# Permission 关联值 (network host / fileRead-Write path / shellExec commands / mcp server-tools / memoryAccess scope / appIntents bundleId 等) 同口径敏感；MCPToolRef 整体替换为
# MCPToolRef(server:"<redacted>",tool:"<redacted>")。OSLog public 任何字段展开 = 脱敏失守。
# - 11a: SideEffect 必须用 caseName helper，不允许 String(describing: sideEffect)
# - 11b: Permission 必须用 caseName helper，不允许 String(describing: permission)
# - 11c: MCPToolRef 允许 String(describing: ref) 但 privacy 必须 .private（同行匹配）
if rg -n 'String\(describing:\s*sideEffect\)' SliceAIApp/ExecutionEventConsumer.swift; then
  echo "FAIL gate 11a：ExecutionEventConsumer 仍用 String(describing: sideEffect)；必须用 sideEffect.caseName（Step C1.4 caseName extension）"
  exit 1
fi
if rg -n 'String\(describing:\s*permission\)' SliceAIApp/ExecutionEventConsumer.swift; then
  echo "FAIL gate 11b：ExecutionEventConsumer 仍用 String(describing: permission)；必须用 permission.caseName（Step C1.4 caseName extension）"
  exit 1
fi
# 11c: MCPToolRef 同行 ref + privacy: .public 即视为脱敏失守；必须 .private
if rg -nU 'String\(describing:\s*ref\)[^,]*,\s*privacy:\s*\.public' SliceAIApp/ExecutionEventConsumer.swift; then
  echo "FAIL gate 11c：ExecutionEventConsumer 用 String(describing: ref) privacy: .public；MCPToolRef 必须 .private（与 args 同口径，与 JSONLAuditLog 脱敏边界对齐）"
  exit 1
fi
echo "PASS gate 11"

echo
echo "=== ALL GATES PASS ==="
```

任何 gate FAIL → 修对应文件再跑；全部 PASS 才进 Step J1。

> **note F4.3 R4 — `set -e` 与 `exit` 的组合行为**：
> - 头部 `set -e` 让中间任何命令失败立即 abort（不再要求每行都连 `&&`）。
> - 各 gate 内部的 `if rg ...; then exit 1; fi` 显式 exit 1 触发 fail，shell 立即返回 1。
> - 末行 `=== ALL GATES PASS ===` 只在 5 个 gate 都未触发 exit 1 时才打印；CI 检查最末行 string 即可知是否通过。
>
> **F9.1 R9 walking back**：原 R8 gate 6（loadError 必须有 UI 消费）已删除——R9 review 揭示 SettingsScene banner UI 在 v0.2 D-27 架构下不可达（bootstrap eager `v2ConfigStore.current()` 失败 fail-fast 提前退出，loadError 永远 nil）。grep gate 不再要求 SettingsScene 内出现 loadError 引用；loadError 字段 + reload catch set + save guard 仍保留作 defensive future hook（Phase 2 manual refresh 接入时启用）。

- [ ] **Step J1: 跑 4 关 CI gate**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
All green.

- [ ] **Step J2: 实机触发链测试（M3.0 Step 1 验收）**

启动 app → Safari 划词 → 浮条 → 点 "Translate" → ResultPanel 出流式 token

期望：
- Chunk 顺序无丢失（首段不丢）
- ResultPanel 显示 V2 触发链产物
- ⌥Space → 命令面板 → 选工具 → 同上

cancel test：触发后立即点 Close → stream 静默退出（无错误 alert）

stress test（F9.2 手工）：
1. 触发 A → 立即触发 B（cancel A） → 立即触发 C（cancel B） → ...连 5 次
2. E 的 ResultPanel 内容仅含 E 的 chunk

- [ ] **Step J3: 验证 grep gate F8.2**

```
grep -rn "await .*configStore\\.current\\(\\|await .*store\\.current\\(" SliceAIApp/ SliceAIKit/Sources/SettingsUI/ | grep -v "try await"
```
Expected: 0 命中

- [ ] **Step J4: Commit M3.0 Step 1（单 commit；D-26 + 用户 Q3 决策 A）**

```bash
git add -A
git status   # 检查改动文件清单约 30+ 个，无意外文件
git commit -m "$(cat <<'EOF'
refactor(slicecore): switch app callers to V2* + drop v1 AppContainer wiring + audit configStore.current()

- AppDelegate.execute 改调 ExecutionEngine（含 F8.3 ordering + F9.2 single-flight invocation 契约）
- 新增 ExecutionEventConsumer 翻译 14 个 ExecutionEvent case（D-30）
- SelectionPayload.toExecutionSeed extension（F2.2）+ Source.toSelectionOrigin mapping
- OutputDispatcher 5 个 non-window mode fallback 到 .window + 首 chunk 节流 log（D-30b/F2.3 v0.2 妥协）
- SettingsViewModel 切 V2ConfigurationStore + loadError state（F8.2）
- ToolEditorView / ProviderEditorView binding 切 V2Tool / V2Provider（D-29）
- AppContainer 删 v1 字段（configStore: FileConfigurationStore / toolExecutor）+ rename v2ConfigStore → configStore
- 7 处 configStore.current() callsite audit 加 try await + UI catch skip / ViewModel loadError 策略（F8.2）
- 加 tests：OutputDispatcherFallbackTests / InvocationGateTests（Task 3 已建）/ ExecutionStreamOrderingTests / SingleWriterContractTests
- LLMProviders / Orchestration target 不动 — protocol 升级移到 Step 2 与 v1 Provider 删除同 commit

D-26 / F1.1 / F1.3 / F2.2 / F2.3 / F3.2 / F4.1 / F5.1 / F8.1 / F8.2 / F8.3 / F9.2 修订；M3.0 Step 1。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 8: M3.0 Step 2 — 删 v1 7 文件 + LLMProviderFactory 升级 + SelectionReader 新建（单 commit）

**目标**：同 commit 删除 v1 SliceCore 7 个文件 + 升级 LLMProviderFactory protocol 到接收 V2Provider + 删 PromptExecutor.toV1Provider helper + 删 v1 SelectionSource protocol + 新建 SelectionReader protocol。所有改动必须同 commit（任一分开就编译失败）。

**Files:**
- Delete (in M3.0 Step 2): 7 个 v1 SliceCore 文件
- Delete: `SliceAIKit/Sources/SelectionCapture/SelectionSource.swift`（v1 protocol 文件）
- Delete (若存在): `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift` / `ConfigurationTests.swift` / `ToolExecutorTests.swift`
- Modify: `SliceAIKit/Sources/SliceCore/LLMProvider.swift`（protocol upgrade）
- Modify: `SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift`（V2Provider 字段提取）
- Modify: `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift`（删 toV1Provider helper + callsite 改）
- Modify: `SliceAIKit/Sources/SelectionCapture/ClipboardSelectionSource.swift`（implements SelectionReader）
- Modify: `SliceAIKit/Sources/SelectionCapture/AXSelectionSource.swift`（implements SelectionReader；F1.4 R1 修订真实文件名）
- Modify: `SliceAIKit/Sources/SelectionCapture/SelectionService.swift`（internal type 引用 SelectionSource → SelectionReader）
- Create: `SliceAIKit/Sources/SelectionCapture/SelectionReader.swift`（含 protocol + struct；不带额外错误枚举——v1 真实定义里没有）

- [ ] **Step 1: git rm v1 SliceCore 7 文件**

```bash
cd /Users/majiajun/workspace/SliceAI/.worktrees/phase-0-m3
git rm SliceAIKit/Sources/SliceCore/Tool.swift
git rm SliceAIKit/Sources/SliceCore/Provider.swift
git rm SliceAIKit/Sources/SliceCore/Configuration.swift
git rm SliceAIKit/Sources/SliceCore/ConfigurationStore.swift
git rm SliceAIKit/Sources/SliceCore/ConfigurationProviding.swift
git rm SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift
git rm SliceAIKit/Sources/SliceCore/ToolExecutor.swift
```

- [ ] **Step 2: git rm v1 SelectionSource protocol**

```bash
git rm SliceAIKit/Sources/SelectionCapture/SelectionSource.swift
```

- [ ] **Step 3: 枚举 + 删除 / 迁移所有 v1 类型测试引用（F1.3 R1 修订）**

⚠️ **F1.3 R1 修订**：v1 类型测试引用不止 3 个文件。**实施前必须 grep 确认完整清单**：

```bash
rg -l "DefaultConfiguration|FileConfigurationStore|ConfigurationProviding|ToolExecutor|currentSchemaVersion|ConfigMigrator" SliceAIKit/Tests/SliceCoreTests/
```

预期命中（截至 grep 时）：
- `DefaultConfigurationTests.swift` — v1 `DefaultConfiguration` 函数测试 → **整文件 git rm**（v1 类型删除后无意义）
- `ConfigurationStoreTests.swift` — v1 `FileConfigurationStore` 行为测试 → **整文件 git rm**（v1 类型删除）
- `ToolExecutorTests.swift` — v1 `ToolExecutor` actor 测试 → **整文件 git rm**（v1 类型删除）
- `ConfigMigratorV1ToV2Tests.swift` — v1→v2 migration 测试 → **保留但内部改造**：删除 v1 Swift 类型构造路径，改为硬编码 v1 JSON 字符串（schemaVersion: 1 + tools/providers JSON 文本）+ 调 V2ConfigurationStore.load 触发 migration → assert V2Configuration 结果
- `V2ConfigurationStoreTests.swift` — V2ConfigurationStore.load 行为测试。grep 命中是因为内部用了 `DefaultConfiguration` 作为 fixture → **保留但替换 fixture**：构造 V2Configuration 直接量代替 `DefaultConfiguration()` 调用
- `V2ConfigurationTests.swift` — V2Configuration Codable 测试。grep 命中可能是 `currentSchemaVersion` 断言（v1 Configuration 上的 static 属性）→ **保留但改 assert**：改为 hardcoded `2`（V2 schemaVersion）
- `ConfigurationAppearanceTests.swift` —（如果 grep 命中）测 Configuration.appearance 字段 → 按内容判断：若用 v1 Configuration → git rm；若用 V2Configuration → 保留

执行操作：

```bash
# 1. 直接 git rm（整文件依赖 v1 类型）
git rm SliceAIKit/Tests/SliceCoreTests/DefaultConfigurationTests.swift
git rm SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift
git rm SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift

# 2. 检查 ToolTests / ConfigurationTests（v1 文件名占用即将给 V2* rename 用，需先移走）
ls SliceAIKit/Tests/SliceCoreTests/{ToolTests,ConfigurationTests}.swift 2>/dev/null
# 若存在 → 检查内容：
#   - 引用 v1 Tool / v1 Configuration → git rm（V2*Tests 在 Step 9 (Task 9) git mv 时会接管文件名）
#   - 引用 V2Tool / V2Configuration → 已经是 V2 测试但文件名错；git rm 让 Task 9 git mv V2*Tests.swift 到 ToolTests.swift 时不冲突

git rm SliceAIKit/Tests/SliceCoreTests/ToolTests.swift           # 若存在且为 v1
git rm SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift  # 若存在且为 v1

# 3. 文件名保留但内部改造（Step 10 验证 4 关 CI gate 时如某文件编译失败 → 用下面"内部改造模板"修）
#    ConfigMigratorV1ToV2Tests.swift / V2ConfigurationStoreTests.swift / V2ConfigurationTests.swift
```

**ConfigMigratorV1ToV2Tests.swift 改造模板**（关键示例）：

```swift
// 改前（依赖 v1 Tool / Provider / Configuration Swift struct 构造）：
// let v1Cfg = Configuration(schemaVersion: 1, tools: [Tool(...)], providers: [Provider(...)])
// let data = try JSONEncoder().encode(v1Cfg)
// 改后（hardcoded JSON 字符串；不依赖 v1 Swift 类型）：
let v1Json = """
{
    "schemaVersion": 1,
    "tools": [{ "id": "translate", "name": "翻译", "systemPrompt": "...", ... }],
    "providers": [{ "id": "openai", "name": "OpenAI", "apiKeyRef": "keychain:openai", ... }]
}
""".data(using: .utf8)!
// 写入临时文件 → V2ConfigurationStore.load → assert 结果是 V2Configuration（schemaVersion=2）
```

**V2ConfigurationTests.swift 内 v1 currentSchemaVersion 断言改造（4th-loop R4.X 修订：XCTest 风格统一）**：

> **4th-loop R4.X 修订（2026-04-30 完整审核）**：旧版本"改后"模板用 `#expect(...)`（Swift Testing），但真实 `SliceAIKit/Tests/SliceCoreTests/V2ConfigurationTests.swift` 是 XCTest（`import XCTest` + `XCTestCase`）；implementer 照抄会 compile fail。**修法**：改后模板用 `XCTAssertEqual(...)` 与既有文件风格一致。

```swift
// 改前：
// XCTAssertEqual(loadedConfig.schemaVersion, Configuration.currentSchemaVersion)  // v1 static
// 改后：
XCTAssertEqual(loadedConfig.schemaVersion, 2)  // V2 schemaVersion 写死
```

> **note**：本 step 的 file grep 是 R1 时点结果；implementer 实施时**必须重新 grep**避免遗漏（M2 合入后可能有新增 test）。每个文件按"整删 vs 改造内部"分类，禁止 commit 前 4 关 CI gate 任何 test 文件编译失败。

- [ ] **Step 4: 创建 SelectionReader.swift（直接照搬 v1 SelectionSource.swift 内容，仅 protocol rename）**

⚠️ **F1.4 R1 修订**：plan 不允许臆造字段。**实施期必须先备份真实 v1 SelectionSource.swift**：

```bash
git show HEAD:SliceAIKit/Sources/SelectionCapture/SelectionSource.swift > /tmp/v1_selection_source.swift
cat /tmp/v1_selection_source.swift
```

真实 v1 文件结构（M2 已合入 main，grep 校验过）：

- `import CoreGraphics / Foundation / SliceCore`
- `public protocol SelectionSource: Sendable { func readSelection() async throws -> SelectionReadResult? }`
- `public struct SelectionReadResult: Sendable, Equatable` — **6 字段（无 timestamp）**：
  `text / appBundleID / appName / url / screenPoint / source: SelectionPayload.Source`
- **没有额外错误枚举**（M2 用 `try? await readSelection()` + nil 兜底；不细分错误）

写入 `SliceAIKit/Sources/SelectionCapture/SelectionReader.swift`（仅 protocol 改名 + 文件 header；其余字段照搬）：

```swift
// SliceAIKit/Sources/SelectionCapture/SelectionReader.swift
import CoreGraphics
import Foundation
import SliceCore

/// 读取一次选中文字的抽象来源
///
/// **D-28 决策**：M3 删除 v1 protocol SelectionSource（SelectionCapture/SelectionSource.swift）+
/// 改名为 SelectionReader（避免与 SliceCore 的 v2 enum SelectionSource 撞名）；
/// 实现类 `ClipboardSelectionSource` / `AXSelectionSource` 类型名保持不变（仅协议名改）
public protocol SelectionReader: Sendable {
    /// 读取当前选中文字；拿不到返回 nil
    func readSelection() async throws -> SelectionReadResult?
}

/// 读取结果，包含 text 与来源的应用信息
public struct SelectionReadResult: Sendable, Equatable {
    public let text: String
    public let appBundleID: String
    public let appName: String
    public let url: URL?
    public let screenPoint: CGPoint
    public let source: SelectionPayload.Source

    /// 构造一次选中文字的读取结果，包含捕获到的文本以及调用方应用的元数据
    public init(
        text: String,
        appBundleID: String,
        appName: String,
        url: URL?,
        screenPoint: CGPoint,
        source: SelectionPayload.Source
    ) {
        self.text = text
        self.appBundleID = appBundleID
        self.appName = appName
        self.url = url
        self.screenPoint = screenPoint
        self.source = source
    }
}
```

> **note**：
> - **`async throws` 不是 `async`**——v1 真实签名带 throws；改成 non-throwing 会让 ClipboardSelectionSource / AXSelectionSource 的 `try await readClipboardWithRestore()` 调用编译失败。
> - **没有 timestamp 字段**——plan 此前误加 timestamp 是错的；timestamp 由 `SelectionService.capture()` 在包装到 `SelectionPayload` 时附加（用 `Date()`），不属于读取层。
> - **没有额外错误枚举**——M2 用 nil 兜底；M3 不引入新 error 类型，避免改动 ClipboardSelectionSource / AXSelectionSource 内部错误处理逻辑。

- [ ] **Step 5: 改 ClipboardSelectionSource / AXSelectionSource implements SelectionReader**

⚠️ **F1.4 R1 修订**：真实文件名是 `AXSelectionSource.swift`（不是旧版 plan 误写的另一个文件名）。grep 校验：

```bash
ls SliceAIKit/Sources/SelectionCapture/
# AXSelectionSource.swift / ClipboardSelectionSource.swift / PasteboardProtocol.swift /
# SelectionService.swift / SelectionSource.swift / SystemCopyKeystrokeInvoker.swift
```

改造对象（按真实代码）：

- `ClipboardSelectionSource.swift line 32`：`public final class ClipboardSelectionSource: SelectionSource, @unchecked Sendable` → 把 `: SelectionSource` 改为 `: SelectionReader`
- `AXSelectionSource.swift line 10`：`public struct AXSelectionSource: SelectionSource` → 把 `: SelectionSource` 改为 `: SelectionReader`

实现 `func readSelection() async throws -> SelectionReadResult?` 不动（既有 logic 仍工作；签名一致）。

- [ ] **Step 6: 改 SelectionService 内 protocol 引用**

```bash
grep -n "SelectionSource\|SelectionReader" SliceAIKit/Sources/SelectionCapture/SelectionService.swift
```

把 `let primary: any SelectionSource` 改为 `let primary: any SelectionReader`；同理 fallback 字段、init 参数、Test 注入等。

```bash
# 同步搜 Tests 目录
grep -rn "any SelectionSource" SliceAIKit/Tests/SelectionCaptureTests/
```

每处都改为 `any SelectionReader`；编译期 Swift 会强制要求 protocol 名一致。

- [ ] **Step 7: 升级 LLMProviderFactory protocol（与 v1 Provider 删除同 commit）**

把 `SliceAIKit/Sources/SliceCore/LLMProvider.swift` 内：

```swift
public protocol LLMProviderFactory: Sendable {
    func make(for provider: Provider, apiKey: String) throws -> any LLMProvider
}
```

改为（V2Provider 命名；Step 3 rename 后是 Provider）：

```swift
public protocol LLMProviderFactory: Sendable {
    func make(for provider: V2Provider, apiKey: String) throws -> any LLMProvider
}
```

- [ ] **Step 8: 改 OpenAIProviderFactory.make 实现【F2.4 R2 真实 SliceError case 修订】**

⚠️ **F2.4 R2 修订**：grep 真实 SliceError.ConfigurationError（`SliceCore/SliceError.swift:153`）：

```swift
case validationFailed(String)  // String 关联值是必传的
```

R1 plan 写 `.validationFailed`（无参）会编译失败。改为：

把 `SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift` 内 make 实现改为（接收 V2Provider；validationFailed 带固定脱敏 message）：

```swift
public func make(for provider: V2Provider, apiKey: String) throws -> any LLMProvider {
    // F8.1：V2Provider 字段提取——先校验 kind，再解 baseURL（V2Provider.baseURL 是 Optional）
    // F2.4 R2：validationFailed 带 String 关联值；这里用固定脱敏 message（不拼用户输入）
    guard provider.kind == .openAICompatible else {
        throw SliceError.configuration(.validationFailed(
            "OpenAIProviderFactory only supports kind=openAICompatible"
        ))
    }
    guard let baseURL = provider.baseURL else {
        throw SliceError.configuration(.validationFailed(
            "OpenAIProviderFactory requires non-nil baseURL"
        ))
    }
    return OpenAICompatibleProvider(baseURL: baseURL, apiKey: apiKey)
}
```

> **note F2.4 R2**：`.validationFailed(String)` 真实必带 String 关联值。固定 message 不拼接 provider id 等用户输入字段，避免 developerContext 脱敏后丢失关键诊断信息（`SliceError.developerContext` 对 `.validationFailed` 输出 `<redacted>`，所以**这里的 message 主要服务 `userMessage`**）。如果实施期发现 SliceError.ConfigurationError 已有更精准 case（如 `.unsupportedProviderKind` / `.missingBaseURL`），优先用精准 case；当前真实只有 `.validationFailed`。

- [ ] **Step 8.5: 全仓 grep LLMProviderFactory impl 排查 — 同 commit 改造测试 helper【F2.4 R2 + F3.2 R3 必修】**

⚠️ **F3.2 R3 修订**：`MockLLMProvider.swift` 内**真有** `MockLLMProviderFactory: LLMProviderFactory` 类（同文件 line 87+），不是只有 LLMProvider mock。R2 表格漏改这一项会让 PromptExecutor / ExecutionEngine 测试整批编译失败。修订后表格：

```bash
# 任何对 LLMProviderFactory protocol 实现的位置；upgrade protocol 后必须同步改 impl 签名
rg -n "\\: LLMProviderFactory\b\|LLMProviderFactory[^A-Za-z]" SliceAIKit/Tests/ SliceAIApp/ SliceAIKit/Sources/ --type swift
```

R3 时点已知命中（implementer 实施时再 rg 一次确保 R3 后无新增）：

| 文件 | 现状 | M3.0 Step 2 处理 |
|---|---|---|
| `SliceAIKit/Sources/LLMProviders/OpenAIProviderFactory.swift` | 生产 impl，接收 v1 Provider | 本 Step 8 改 — 接收 V2Provider + .validationFailed("...") 带 String |
| `SliceAIKit/Sources/SliceCore/LLMProvider.swift`（protocol 定义） | protocol `make(for: Provider, ...)` | 本 Step 7 改 — protocol 签名 `make(for: V2Provider, ...)` |
| `SliceAIKit/Tests/SliceCoreTests/ToolExecutorTests.swift`（4 个 LLMProviderFactory impl: FakeFactory / CapturingFactory / ThrowingFactory / ThrowingStreamFactory） | v1 impl，捕获 v1 Provider | F1.3 R1 已要求**整文件 git rm**（与 ToolExecutor 同 commit 删）— 无需单独改 |
| **`SliceAIKit/Tests/OrchestrationTests/Helpers/MockLLMProvider.swift` 内 `MockLLMProviderFactory: LLMProviderFactory`（line 87+）** | **v1 impl**：`var capturedProvider: Provider?` + `func make(for provider: Provider, ...)` | **F3.2 R3 必改**：State.capturedProvider 类型 `Provider?` → `V2Provider?`；computed prop `capturedProvider: Provider?` → `V2Provider?`；func make signature `for provider: Provider` → `for provider: V2Provider`；同步改所有 `XCTAssertEqual(spy.capturedProvider, ...)` 等断言用 V2Provider 实例 |
| `SliceAIKit/Tests/LLMProvidersTests/` | 直接测 OpenAIProviderFactory | 实施期 grep 验证：若有引用 `make(for: Provider, ...)` → 改为 `V2Provider`；若无 → 不动 |

**MockLLMProviderFactory 改造后真实代码模板**（基于 line 87+ 真实结构）：

```swift
final class MockLLMProviderFactory: LLMProviderFactory, @unchecked Sendable {
    private struct State {
        var capturedProvider: V2Provider?  // F3.2 R3：v1 Provider → V2Provider
        var capturedAPIKey: String?
    }
    // ... existing init / state / makeError ...

    var capturedProvider: V2Provider? {  // F3.2 R3：返回类型同步
        state.withLock { $0.capturedProvider }
    }
    var capturedAPIKey: String? { state.withLock { $0.capturedAPIKey } }

    func make(for provider: V2Provider, apiKey: String) throws -> any LLMProvider {  // F3.2 R3：参数类型同步
        state.withLock { state in
            state.capturedProvider = provider
            state.capturedAPIKey = apiKey
        }
        if let err = makeError { throw err }
        return self.provider
    }
}
```

```bash
# 检查所有 caller / assertion 是否仍用 v1 Provider 实例
grep -rn "MockLLMProviderFactory\|capturedProvider" SliceAIKit/Tests/OrchestrationTests/
```

所有 `MockLLMProviderFactory(provider: ...)` 构造保持不变（`provider: any LLMProvider` 不变）；
所有 `assert spy.capturedProvider == someProvider` 的 someProvider 必须是 V2Provider 实例。

每处都改为 V2Provider 调用；不改 / 漏改 → Step 10 4 关 CI gate 编译失败。

- [ ] **Step 9: 改 PromptExecutor.swift 删 toV1Provider helper + callsite**

定位 `SliceAIKit/Sources/Orchestration/Executors/PromptExecutor.swift` 第 280-303 行的 `private func toV1Provider(_:)`，整段删除。

定位 line 171/197/211（按 mini-spec §3.1.5 修订表）：

```swift
// line 171（改前）：
let v1Provider = try toV1Provider(provider)

// 改后：直接用 v2 provider（已是 V2Provider 类型）
// （删除这一行）
```

```swift
// line 197（改前）：
fallback: v1Provider.defaultModel

// 改后：
fallback: provider.defaultModel
```

```swift
// line 211（改前）：
let llm = try llmProviderFactory.make(for: v1Provider, apiKey: apiKey)

// 改后：
let llm = try llmProviderFactory.make(for: provider, apiKey: apiKey)
```

```swift
// line 174（改前）：
let keychainAccount = v1Provider.keychainAccount

// 改后（V2Provider 也有同名字段或类似 — 对照 V2Provider.swift 真实结构）：
let keychainAccount = provider.keychainAccount  // 或 provider.apiKeyRef.removingPrefix("keychain:") 等
```

> **note**：`keychainAccount` 在 v1 Provider 是计算属性；V2Provider 是否也有需对照真实代码确认。如果 V2Provider 没有同名属性，需要新加 extension 或用 `apiKeyRef` 字段提取。

- [ ] **Step 10: 验证 4 关 CI gate**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```

Expected: All PASS.

如果某处仍引用 `Tool` / `Provider` / `Configuration` v1 类型 → 切到 V2*；
如果某 v1 Test 仍 import 已删类型 → git rm 该 Test。

- [ ] **Step 11: 实机触发链测试（与 v0.1 等价）**

启动 app → Safari 划词翻译 → 验证仍流式正常。

- [ ] **Step 12: Commit M3.0 Step 2**

```bash
git add -A
git status   # 检查含 git rm 7+1 文件 + Modify LLMProvider/OpenAIProviderFactory/PromptExecutor + Create SelectionReader.swift + Modify Clipboard/AX/Service

git commit -m "$(cat <<'EOF'
refactor(slicecore): delete v1 7 files + upgrade LLMProviderFactory protocol + add SelectionReader

- 删除 v1 SliceCore 7 文件：Tool / Provider / Configuration / FileConfigurationStore /
  ConfigurationProviding / DefaultConfiguration / ToolExecutor（必须同 commit；ToolExecutor 依赖前 6 个）
- 删除 v1 SelectionCapture/SelectionSource.swift（protocol 改名）
- LLMProviderFactory.make protocol 升级接收 V2Provider；OpenAIProviderFactory 内部 V2Provider 字段提取
- 删除 PromptExecutor.toV1Provider helper（line 280-303）+ callsite line 171/174/197/211 改为直接用 V2Provider
- 新建 SelectionCapture/SelectionReader.swift：protocol SelectionReader + SelectionReadResult（真实 v1 文件没有额外错误枚举）
- ClipboardSelectionSource / AXSelectionSource implements SelectionReader（类型名不变）
- SelectionService.swift internal type 引用跟随
- v1 SelectionPayload.swift 与 SelectionPayloadTests.swift 保留（D-28：触发层包装类型）

D-26 Step 2 / D-28 / F6.1 / F8.1 修订；M3.0 Step 2。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 9: M3.0 Step 3 — git mv V2* → 正名

**目标**：把 5 个 V2* 文件 git mv 到正名；类型名 `V2Tool` → `Tool` 等同步全局替换；测试文件同步 rename。

**Files:**
- Rename (git mv): 5 个源文件 + 4 个测试文件 + 全局 sed 替换类型名

- [ ] **Step 1: git mv 5 个源文件**

```bash
cd /Users/majiajun/workspace/SliceAI/.worktrees/phase-0-m3
git mv SliceAIKit/Sources/SliceCore/V2Tool.swift              SliceAIKit/Sources/SliceCore/Tool.swift
git mv SliceAIKit/Sources/SliceCore/V2Provider.swift          SliceAIKit/Sources/SliceCore/Provider.swift
git mv SliceAIKit/Sources/SliceCore/V2Configuration.swift     SliceAIKit/Sources/SliceCore/Configuration.swift
git mv SliceAIKit/Sources/SliceCore/V2ConfigurationStore.swift SliceAIKit/Sources/SliceCore/ConfigurationStore.swift
git mv SliceAIKit/Sources/SliceCore/DefaultV2Configuration.swift SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift
```

- [ ] **Step 2: git mv 4 个测试文件**

```bash
git mv SliceAIKit/Tests/SliceCoreTests/V2ToolTests.swift            SliceAIKit/Tests/SliceCoreTests/ToolTests.swift
git mv SliceAIKit/Tests/SliceCoreTests/V2ProviderTests.swift        SliceAIKit/Tests/SliceCoreTests/ProviderTests.swift
git mv SliceAIKit/Tests/SliceCoreTests/V2ConfigurationTests.swift   SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift
git mv SliceAIKit/Tests/SliceCoreTests/V2ConfigurationStoreTests.swift SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift
```

- [ ] **Step 3: 全局类型名替换（按 \b boundary 规避合成名）【F2.5 R2 改 perl — BSD sed 不支持 \b】**

⚠️ **F2.5 R2 修订**：本机 BSD sed 实测（`echo "alpha V2Tool beta V2ToolKit gamma" | sed -E 's/\bV2Tool\b/Tool/g'`）输出仍保留 `V2Tool`——`\b` word boundary 在 BSD sed 不工作。改用 portable `perl -pi -e`。验证：

```bash
# dry-run 验证 perl boundary 工作；不改任何文件
echo "alpha V2Tool beta V2ToolKit gamma V2ToolKitTests" | perl -pe 's/\bV2Tool\b/Tool/g'
# 期望输出：alpha Tool beta V2ToolKit gamma V2ToolKitTests
# （V2Tool 替换；V2ToolKit / V2ToolKitTests 因 V2Tool 后跟 K 不是 word boundary，正确保留）

# 备份 — 失败时可 reset
cp -r SliceAIKit/Sources SliceAIKit/Tests SliceAIApp /tmp/m3_rename_backup_$(date +%s)/

# 改：源文件 + 测试文件用 perl word boundary 替换
find SliceAIKit/Sources SliceAIKit/Tests SliceAIApp -name "*.swift" -exec perl -pi -e '
  s/\bV2ConfigurationStore\b/ConfigurationStore/g;
  s/\bDefaultV2Configuration\b/DefaultConfiguration/g;
  s/\bV2Configuration\b/Configuration/g;
  s/\bV2Provider\b/Provider/g;
  s/\bV2Tool\b/Tool/g;
' {} \;

# 注意 perl 替换顺序：长 prefix 在前（V2ConfigurationStore 必须先于 V2Configuration；DefaultV2Configuration
# 必须先于 V2Configuration）；否则 V2Configuration → Configuration 后 V2ConfigurationStore 再替换会变 ConfigurationStore
# 而 DefaultV2Configuration 已变 DefaultConfiguration（部分前缀）— 单 perl -pi -e 命令多个 s/// 按顺序应用，OK

# 测试 class 名替换（同样 perl，长 prefix 在前）
find SliceAIKit/Tests -name "*.swift" -exec perl -pi -e '
  s/\bV2ConfigurationStoreTests\b/ConfigurationStoreTests/g;
  s/\bV2ConfigurationTests\b/ConfigurationTests/g;
  s/\bV2ToolTests\b/ToolTests/g;
  s/\bV2ProviderTests\b/ProviderTests/g;
' {} \;
```

- [ ] **Step 3.5: grep 验证替换前后【F2.5 R2 必加】**

```bash
# 替换前 / 替换后对比 — 确保所有 V2* 已被替换
echo "=== 替换后 V2* 残留检查 ==="
rg -n "\\bV2(Tool|Provider|Configuration|ConfigurationStore)\\b" SliceAIKit/Sources/ SliceAIKit/Tests/ SliceAIApp/ --type swift
echo "Expected: 0 命中（注释 / 文档字符串内的 V2* 字面值除外）"

echo "=== 替换后 DefaultV2Configuration 残留 ==="
rg -n "\\bDefaultV2Configuration\\b" SliceAIKit/Sources/ SliceAIKit/Tests/ SliceAIApp/ --type swift
echo "Expected: 0 命中"

echo "=== 检查长前缀是否被误伤 ==="
rg -n "\\bV2(ToolKit|ToolBox)\\b" SliceAIKit/ --type swift
echo "Expected: 0 命中（这些字面上不存在；如有需手工复核）"
```

如有非 0 命中：要么是注释 / 文档字符串内有意保留（保留即可），要么是 perl boundary 没匹配到（手工编辑修）。

- [ ] **Step 4: 验证 grep 无残留 V2* 命名**

```
grep -rn "\\bV2Tool\\b\\|\\bV2Provider\\b\\|\\bV2Configuration\\b\\|\\bV2ConfigurationStore\\b\\|\\bDefaultV2Configuration\\b" SliceAIKit/Sources/ SliceAIKit/Tests/ SliceAIApp/
```
Expected: 0 命中

- [ ] **Step 5: 验证 4 关 CI gate**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```

Expected: All PASS

如果有编译错（如 DefaultProviderResolver closure 内 `V2Configuration` 还有引用没替换）→ 全文 grep 找漏并补 sed。

- [ ] **Step 6: 验证 git follow rename 工作**

```
git log --follow --oneline SliceAIKit/Sources/SliceCore/Tool.swift | head -10
```
Expected: 能跟踪到 V2Tool.swift 时期的 commit history（git mv 应让 git follow 工作）

- [ ] **Step 7: Commit M3.0 Step 3**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(slicecore): rename V2* types and files to canonical names

- git mv V2Tool/V2Provider/V2Configuration/V2ConfigurationStore/DefaultV2Configuration → 正名
- 全局 sed -i '' 's/\bV2Tool\b/Tool/g' 等同步类型名替换（含 SliceAIKit/Sources + Tests + SliceAIApp）
- Tests class 名同步 rename
- git follow rename 验证：git log --follow Tool.swift 能跟踪到 V2Tool.swift 历史

D-26 Step 3 修订；M3.0 Step 3。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 10: M3.0 Step 4 — PresentationMode → DisplayMode

**目标**：把 M1 临时改名 `PresentationMode` rename 回 spec 原名 `DisplayMode`（v1 `DisplayMode` 已在 Step 2 删除，命名空间已腾出）。

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/OutputBinding.swift`（enum 定义）
- Modify: `SliceAIKit/Sources/SliceCore/ToolKind.swift`（V2Tool / PromptTool 的 displayMode 字段）
- Modify: 全部测试 + 全部引用（Orchestration / SettingsUI / SliceAIApp）

- [ ] **Step 1: 全局 perl 替换【F3.3 R3：BSD sed \b 不工作 — 必须用 perl】**

⚠️ **F3.3 R3 修订**：与 Task 9 同——BSD sed `\b` word boundary 实测失败（`echo "alpha PresentationMode beta" | sed -E 's/\bPresentationMode\b/DisplayMode/g'` 输出仍保留 `PresentationMode`）。改 perl：

```bash
# dry-run 验证 perl boundary
echo "alpha PresentationMode beta PresentationModeKit" | perl -pe 's/\bPresentationMode\b/DisplayMode/g'
# Expected: alpha DisplayMode beta PresentationModeKit （PresentationModeKit 因后跟 K 不是 word boundary，正确保留）

# 备份
cp -r SliceAIKit/Sources SliceAIKit/Tests SliceAIApp /tmp/m3_step4_backup_$(date +%s)/

# 用 perl 替换（portable + 真正支持 \b）
find SliceAIKit/Sources SliceAIKit/Tests SliceAIApp -name "*.swift" -exec perl -pi -e 's/\bPresentationMode\b/DisplayMode/g' {} \;
```

- [ ] **Step 2: 验证 grep 无残留**

```
rg -n "\bPresentationMode\b" SliceAIKit/Sources/ SliceAIKit/Tests/ SliceAIApp/ --type swift
```
Expected: 0 命中（注释 / 文档字符串内有意保留的 PresentationMode 字面值除外，需手工复核）

- [ ] **Step 3: 验证 4 关 CI gate**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
Expected: All PASS

- [ ] **Step 4: Commit M3.0 Step 4**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(slicecore): rename PresentationMode to DisplayMode

把 M1 临时改名（避 v1 enum DisplayMode 命名冲突）rename 回 spec 原名。
v1 DisplayMode 已在 Step 2 删除，命名空间已腾出。
全局 perl -pi -e 's/\bPresentationMode\b/DisplayMode/g' 替换（F3.3 R3：BSD sed \b 失败改 perl）。

D-26 Step 4；M3.0 Step 4。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 11: M3.0 Step 5 — SelectionOrigin → SelectionSource

**目标**：把 M1 临时改名 `SelectionOrigin` rename 回 spec 原名 `SelectionSource`（v1 `protocol SelectionSource` 已在 Step 2 改名为 `SelectionReader`，命名空间已腾出）。

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/SelectionContentType.swift`（enum 定义）
- Modify: `SliceAIKit/Sources/SliceCore/SelectionSnapshot.swift`（字段类型）
- Modify: `SliceAIKit/Sources/SliceCore/SelectionPayload.swift`（payload.source 字段类型 + toSelectionOrigin → toSelectionSource）
- Modify: 全部测试 + 全部引用

- [ ] **Step 1: 全局 perl 替换【F3.3 R3：BSD sed \b 不工作 — 必须用 perl】**

⚠️ **F3.3 R3 修订**：与 Task 9 / Task 10 同 — perl 替代 BSD sed。

```bash
# dry-run 验证
echo "alpha SelectionOrigin beta SelectionOriginType" | perl -pe 's/\bSelectionOrigin\b/SelectionSource/g'
# Expected: alpha SelectionSource beta SelectionOriginType （SelectionOriginType 后跟 T 不是 word boundary，正确保留）

# 备份
cp -r SliceAIKit/Sources SliceAIKit/Tests SliceAIApp /tmp/m3_step5_backup_$(date +%s)/

# 一次 perl 命令处理两个 rename（顺序：toSelectionOrigin 在前，避免后续 SelectionOrigin 替换误伤）
find SliceAIKit/Sources SliceAIKit/Tests SliceAIApp -name "*.swift" -exec perl -pi -e '
  s/\btoSelectionOrigin\b/toSelectionSource/g;
  s/\bSelectionOrigin\b/SelectionSource/g;
' {} \;
```

- [ ] **Step 2: ~~rename `toSelectionOrigin` 方法~~（F3.3 R3：已合入 Step 1 单 perl 命令）**

- [ ] **Step 3: 验证 grep 无残留**

```
grep -rn "\\bSelectionOrigin\\b\\|\\btoSelectionOrigin\\b" SliceAIKit/Sources/ SliceAIKit/Tests/ SliceAIApp/
```
Expected: 0 命中

> **note**：rename 后 `SelectionSource` enum 与 v1 `protocol SelectionSource` 名字冲突——但 v1 protocol 已在 Step 2 改为 `SelectionReader` + 物理文件 git rm，所以 namespace 干净。如果 grep 还有 `: SelectionSource {` 这种 protocol conformance → 那就是漏改的，回 Step 2 补 SelectionReader 替换。

- [ ] **Step 4: 验证 4 关 CI gate**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
Expected: All PASS

- [ ] **Step 5: Commit M3.0 Step 5**

```bash
git add -A
git commit -m "$(cat <<'EOF'
refactor(selectioncapture): rename SelectionOrigin to SelectionSource

把 M1 临时改名（避 v1 protocol SelectionSource 命名冲突）rename 回 spec 原名。
v1 protocol SelectionSource 已在 Step 2 改名为 SelectionReader 并 git rm 物理文件，命名空间已腾出。
toSelectionOrigin() helper 同步 rename 为 toSelectionSource()。

D-26 Step 5 / D-28；M3.0 Step 5。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Task 12: M3.2 验收 — 触发链端到端手工 + ordering / single-flight 实测

**目标**：跑触发链端到端手工验证 + F8.3 ordering + F9.2 single-flight 手工 stress；spy tests 已在 Step 1 Iteration I 落地。

**Files:** （无代码改动；纯验收）

- [ ] **Step 1: 4 关 CI gate（基线）**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
Expected: All PASS

- [ ] **Step 2: 实机启动 + Safari 划词触发链**

启动 app → 在 Safari 选中 "hello world" → 浮条出现 → 点 "Translate" → ResultPanel 出流式 token

期望：
- ResultPanel 流式正常
- 首段不丢失（F8.3 ordering 验证）
- 与 v0.1 视觉等价

- [ ] **Step 3: ⌥Space 命令面板触发链**

⌥Space → 命令面板弹出 → 搜索 → 选 "Translate" → ResultPanel 出流式 token

期望：同 Step 2

- [ ] **Step 4: cancellation 链路验证（Round-5 R5.1 修订：与 ExecutionEngine 真实"cancel 不写 audit"语义对齐）**

> **Round-5 R5.1 修订（2026-04-28）**：旧 Step 4 期望 "audit log 含 cancel 记录或 stream 提前结束记录"，与真实 ExecutionEngine 取消语义直接矛盾——`SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift:163` 明示"此处 isCancelled=true。onTermination 已 finish continuation；**本路径不写 audit**、不 yield failed"；`+Steps.swift:59` 同口径"静默退出，防止 cancel 后仍走 finishFailure 写'取消但记 .failed' 歧义 audit"。按旧 Step 4 验收必然失败；implementer 为通过验收可能给取消路径补写 audit → 破坏现有审计语义（用户取消被错误地记成 success/failed）。修法：验证 **UI/流行为**而不是 audit 记录，并显式检查 audit.jsonl **不含**该 invocation 的 success/failed 终态。

操作：
1. 触发任意 prompt tool（mouseUp 浮条 → 选 Translate）
2. ResultPanel 弹出后**立即**点 "Close"（叉号）/ 点面板外区域（outside-click monitor）
3. 观察 ~3-5 秒

期望（UI / 流行为）：
- ResultPanel 立即关闭（与 v0.1 行为等价；无 alert / error popover）
- 关闭后**不再**有任何 chunk / token 出现（即使是被 cancel 的旧 stream 已经 yield 但未渲染的内容也不应再画到 panel）
- 重新触发同 tool → 新 ResultPanel 内容仅含**新** invocation 的 chunk，不含被 cancel 的旧 invocation 残留 token（验证 InvocationGate single-flight + shouldAccept guard 生效）

期望（audit.jsonl — 反向验证：cancel **不**写 audit）：
```bash
# 取消触发前的 audit.jsonl 行数；触发并 cancel 后再查；行数应保持不变（cancel 路径静默不写）
BEFORE=$(wc -l < ~/Library/Application\ Support/SliceAI/audit.jsonl 2>/dev/null || echo 0)
# ... 执行触发 + cancel 步骤 ...
AFTER=$(wc -l < ~/Library/Application\ Support/SliceAI/audit.jsonl 2>/dev/null || echo 0)

# 重要：差值应为 0（cancel invocation 没有 success/failed 任何终态写入）；
# 如果差值 > 0 → 说明 ExecutionEngine 取消路径被错误改成写 audit，违反 ExecutionEngine.swift:163
# +Steps.swift:59/151/260 的"静默不写 audit"约束
test "$AFTER" = "$BEFORE" || {
  echo "FAIL: cancel 路径意外写了 audit ($((AFTER-BEFORE)) 条新记录)；违反 ExecutionEngine cancel 语义"
  tail -5 ~/Library/Application\ Support/SliceAI/audit.jsonl
  exit 1
}
echo "PASS: cancel 路径未写 audit（与 ExecutionEngine 设计一致）"
```

> **Why audit 反向验证而不是正向**：v0.2 阶段 cancel 不暴露独立 ExecutionEvent / InvocationOutcome（如未来要审计 cancel，需要在 Orchestration 设计 explicit cancellation outcome + 同步实现 + 测试 + release notes，不是手工验收里硬要求 audit 记录）。当前 v0.2 cancel = "用户已转向他处，记任何东西都没意义"；本 Step 用反向 assertion 防止 implementer 为通过 gate 而破坏 audit 语义。

- [ ] **Step 5: F9.2 single-flight stress 验证**

连续触发 5 次：A → 立即触发 B（cancel A） → 立即触发 C（cancel B） → D → E

每次触发间隔 < 100ms（手工或写 Apple Script 自动化）。

期望：E 的 ResultPanel 内容**仅含 E 的 chunk**——不含 A/B/C/D 残留 token。

- [ ] **Step 6: tests 全绿（F3.4 R3 更新清单）**

```
(cd SliceAIKit && swift test --filter "OrchestrationTests.InvocationGateTests")           # F3.4 R3：直接测真实 gate 替代 SpyAdapter
(cd SliceAIKit && swift test --filter "OrchestrationTests.ExecutionStreamOrderingTests")  # F3.4 R3：fake stream + 真实 gate ordering
(cd SliceAIKit && swift test --filter "OrchestrationTests.OutputDispatcherFallbackTests")
(cd SliceAIKit && swift test --filter "OrchestrationTests.SingleWriterContractTests")
(cd SliceAIKit && swift test --filter "SliceCoreTests.SelectionPayloadTests/test_toExecutionSeed_mapsFields")  # 当前真实 XCTest class 内的 seed mapping 用例
```
Expected: 全 PASS

- [ ] **Step 7: M3.2 标记完成**

无 commit；如果 Step 1-6 全过 → M3.2 完成；进 M3.3。

---

## Task 13: M3.3 验收 — 4 启动场景验证

**目标**：4 个启动场景逐一验证（v2 存在 / 仅 v1 / 都不在 / v2 损坏）行为正确。

**Files:** （无代码改动；纯验收）

- [ ] **Step 1: 场景 A — v2 存在**

```bash
ls ~/Library/Application\ Support/SliceAI/config-v2.json
# 应存在
open SliceAI.app
```

期望：app 启动直接读 config-v2.json；触发 ⌥Space 工具列表与 config-v2.json 内容一致。

- [ ] **Step 2: 场景 B — 仅 v1 存在（migrator 路径）**

```bash
mv ~/Library/Application\ Support/SliceAI/config-v2.json /tmp/config-v2-backup.json
ls ~/Library/Application\ Support/SliceAI/   # 应仅含 config.json
open SliceAI.app
```

期望：
- App 启动跑 migrator
- ~/Library/Application Support/SliceAI/config-v2.json 自动创建
- diff config.json (v1) 与 v0.1 时一致（v1 永不修改）
- 工具列表与 config.json 等价（migrator 不丢字段）

```bash
# 验证 v1 未变
diff ~/Library/Application\ Support/SliceAI/config.json /tmp/config_v1_v01_backup.json   # 假设有 v01 时备份
```

- [ ] **Step 3: 场景 C — 都不存在（first-launch 写 default）**

```bash
APP_SUPPORT="$HOME/Library/Application Support/SliceAI"
BACKUP_ROOT="$(mktemp -d /tmp/sliceai-backup.XXXXXX)"
echo "BACKUP_ROOT=$BACKUP_ROOT"
if [ -d "$APP_SUPPORT" ]; then
  mv "$APP_SUPPORT" "$BACKUP_ROOT/SliceAI"
fi
open SliceAI.app
```

期望：
- App 启动写 DefaultConfiguration.initial() 到 config-v2.json
- ~/Library/Application Support/SliceAI/config-v2.json 含 4 个内置工具
- ~/Library/Application Support/SliceAI/config.json **不**存在（v1 永不被写）

```bash
ls -la ~/Library/Application\ Support/SliceAI/
# 应有：config-v2.json（新建）+ cost.sqlite + audit.jsonl；无 config.json
```

恢复：

```bash
APP_SUPPORT="$HOME/Library/Application Support/SliceAI"
if [ -d "$BACKUP_ROOT/SliceAI" ]; then
  rm -rf "$APP_SUPPORT"
  mv "$BACKUP_ROOT/SliceAI" "$APP_SUPPORT"
fi
rmdir "$BACKUP_ROOT" 2>/dev/null || true
```

- [ ] **Step 4: 场景 D — v2 损坏（启动失败 UX 验证）**

```bash
echo "broken json {{{ }}}" > ~/Library/Application\ Support/SliceAI/config-v2.json
open SliceAI.app
```

期望：
- App 启动后弹 NSAlert "SliceAI 启动失败" + 描述 "配置文件损坏" 或类似
- 点击退出后 dock icon 立即消失
- App **不**进入正常状态（不静默覆盖损坏的 config-v2.json）

恢复：

```bash
mv /tmp/config-v2-backup.json ~/Library/Application\ Support/SliceAI/config-v2.json
```

- [ ] **Step 5: 单测覆盖验证**

```
(cd SliceAIKit && swift test --filter "SliceCoreTests.ConfigurationStoreTests")
```
Expected: 含 `test_load_withNeither_writesDefaultToV2Path` 在 PASS 列表中

- [ ] **Step 6: M3.3 标记完成**

无 commit；如果 Step 1-5 全过 → M3.3 完成；进 M3.4。

---

## Task 14: M3.4 — grep validation 收尾

**目标**：grep 验证 v1 类型族 + V2* 命名 + PresentationMode + SelectionOrigin 在源码 / 测试中残留 = 0；如有残留回 M3.0 修。

**Files:** （无代码改动；纯 grep）

- [ ] **Step 1: 跑收尾 grep（按 mini-spec §M3.4 改造点）**

```bash
grep -rn "\\bToolExecutor\\b\\|\\bFileConfigurationStore\\b\\|\\bConfigurationProviding\\b\\|\\bV2Tool\\b\\|\\bV2Provider\\b\\|\\bV2Configuration\\b\\|\\bV2ConfigurationStore\\b\\|\\bDefaultV2Configuration\\b\\|\\bPresentationMode\\b\\|\\bSelectionOrigin\\b" SliceAIKit/Sources/ SliceAIKit/Tests/ SliceAIApp/
```
Expected: 0 命中（除了 docs/ 历史归档不进 grep 范围）

如果有命中：

- 命中是 v1 残留 → 回 M3.0 Step 1/2 修
- 命中是临时 rename 残留（PresentationMode / SelectionOrigin 等）→ 回 M3.0 Step 4/5 修
- 命中在注释 / docstring → 直接编辑改成正名

- [ ] **Step 2: 验证 4 关 CI gate**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
Expected: All PASS

- [ ] **Step 3: M3.4 标记完成**

无 commit（本 task 不动代码）；进 M3.5。

---

## Task 15: M3.5 — 13 项手工回归（用户执行）

**目标**：用户拿 PR 跑 13 项手工回归（spec §4.2.5 原 8 项 + mini-spec 新增 4 项 + Round-3 R3.1 新增 1 项）；每项报告"通过 / 不通过"。

**Files:** （无代码改动；用户执行）

> **执行人**：用户。Claude 提供 spec / 命令 / 期望；用户拿到 PR 后跑回归并反馈。
>
> 任一项 **不通过** → reset 该 task；回到 implementation 修；重跑全 13 项（影响范围分析后可能仅需子集，但 v0.2 用户基数小、回归慢成本可接受）。

### Spec §4.2.5 原 8 项

- [ ] **Step 1: Safari 划词翻译 → 弹浮条 → 点 "Translate" → ResultPanel 流式**

期望：流式 token 正常出（与 v0.1 视觉等价）

- [ ] **Step 2: ⌥Space → 命令面板 → 搜索 → 选工具 → ResultPanel 流式**

期望：同上

- [ ] **Step 3: Regenerate / Copy / Pin / Close / Retry / Open Settings 等 ResultPanel 6 个 panel 操作**

期望：每个按钮行为与 v0.1 视觉 + 行为等价

> **F6.1 R6 + F7.1 R7 必验断言**（Regenerate 是 D-29 行为等价 + F9.2 single-flight 全路径交叉点）：
> - **a. 流式中点 Regenerate**：触发 ToolA → 流式 chunk 流出 → 中途点 Regenerate → 期望旧 streamTask cancel（Console 看 `[ResultPanel] dismiss/cancel` 或 stream 终止）+ 同 ToolA 立即重新 execute（新 invocationId）+ ResultPanel 流式区重置 + 后续 chunk 不会与旧流交叉。
> - **b. 完成后点 Regenerate**：触发 ToolA → 流式正常 finish → 点 Regenerate → 期望同 ToolA 重新 execute（新 invocationId）+ ResultPanel 流式区重置 + 不残留旧文本。
> - **c. F9.2 single-flight chunk 路径交叉验证**：a 场景中旧 stream 的 defer 走 `clearActiveInvocation(ifCurrent: oldId)` —— 因 active 已被新 invocation set，guard 不命中 → 不会清新 invocation 的 active id（R2 walking back + R3 InvocationGate.ifCurrent 核心契约，必验）。
> - **d. F7.1 R7 stale terminal event 验证**（关键新增——chunk 路径 R4 已护，事件路径 R7 才补）：
>     1. 取一个**响应慢**的 prompt（让 stream 至少 3 秒才 yield .finished）触发 ToolA；
>     2. 在 A 流式中（流出几个 chunk 后）点 Regenerate → B（同 ToolA 新 invocation）立即开始；
>     3. 等待 ~5 秒，期望 ResultPanel **只显示 B 的内容** —— 不出现 A 的"已完成"/"已失败"状态闪烁（A 的 .finished 应被 invocationGate.shouldAccept guard 静默丢弃）；
>     4. 重复时把 A 换成**会失败**的配置（如 baseURL 故意写错触发 .failed）+ B 用正常配置 —— 期望 ResultPanel 只显示 B 的流式（不出现 A 的红色错误提示）。
> - 失败信号：
>     1. 点 Regenerate 后 ResultPanel 文本不刷新 / Console 无 `onRegenerate: re-running tool=...` log → plan 漏 onRegenerate（F6.1 fix 失效）；
>     2. 新 chunk 与旧 chunk 同时显示 → InvocationGate.gatedAppend 失效 / chunk 路径 ifCurrent guard 失效；
>     3. **B 流式中突然出现 A 的"已完成"绿色 + 文本闪烁，或 A 的红色错误提示** → consumer.handle 前的 invocationGate.shouldAccept guard 失效（F7.1 R7 fix 失效）；
>     4. defer 内 `clearActiveInvocation(ifCurrent:)` 把 B 的 active id 误清 → B 后续 chunk 全部 reject → B 流式区永久空白。

- [ ] **Step 4: Accessibility 权限降级行为验证（拆 a/b 两子场景，覆盖"降级"完整语义）**

> **Round-1 R1.1 修订（2026-04-29 本 loop = M3 plan 第三次 codex review）**：旧版 Step 4 期望"关闭 Accessibility 后用 Cmd+C 备份恢复路径仍能取到选区文字"，与真实代码不可达——`SliceAIApp/AppDelegate.swift:221` 明示"两个 global monitor 依赖 Accessibility 权限；权限缺失时回调不会被触发"；`SliceAIKit/Sources/SelectionCapture/SystemCopyKeystrokeInvoker.swift:5-6` 明示"需要 App 获得 Accessibility 权限，否则 `post(tap:)` 会被系统静默吞掉，前台 App 无法收到按键事件"。AX 完全 revoke 后 mouseUp 不响应 + ⌘C 合成被吞，SelectionService.capture() 双路均 nil；旧描述会让 implementer 为通过验收去做超出 M3 scope 的权限绕过（如改 CGEvent 注入路径或读 NSPasteboard 而不发 ⌘C）。**修法**：拆 Step 4 为 (a) AX revoked 失败 UX + (b) AX 已授权但目标 app 不暴露 AX 文本时的真实 fallback 命中；保留 Step 4 单项编号，13 项总数不变。**2026-04-30 优化**：mini-spec 已同步为同一语义，不再存在 plan/spec drift。

**Sub-step 4 (a): AX 权限 revoke 后的失败 UX**

操作：System Settings → Privacy & Security → Accessibility → 关闭 SliceAI → 重启 app → 触发（鼠标划词 + ⌥Space 命令面板各试一次）

期望：
1. 鼠标划词**不**弹出虚假浮条（mouseUp global monitor 因 AX 缺失不触发；AppDelegate.swift:221 注释明示）；
2. ⌥Space 命令面板能弹出（hotkey 走 Carbon `RegisterEventHotKey` 不依赖 AX），但触发执行时 SelectionService.capture() 双路均 nil，UX 不渲染流式（具体表现以实现为准——如不弹 ResultPanel 或弹 fail 文案，但**不**应弹"启动失败"NSAlert）；
3. Permissions Onboarding 横幅 / AccessibilityMonitor 提示路径保持可见，引导用户重新授权；
4. **不**弹 NSAlert "SliceAI 启动失败"（AX revoke 不属于 startupError；启动 UX 路径与 Step 12 严格区分——Step 12 仅在 AppContainer.bootstrap throws 时触发）。

**Sub-step 4 (b): AX 已授权但目标 app 不暴露 AX 文本的 Cmd+C fallback 命中**

操作：（完成 4 (a) 后）恢复 AX 权限 → 重启 app → 在 Figma / Slack / VSCode 等不暴露 AX 文本树的应用划词触发

期望：
1. SelectionService.capture() 主路径（AXSelectionSource）取不到 → fallback（ClipboardSelectionSource via SystemCopyKeystrokeInvoker）取到 → 浮条 / ResultPanel 正常显示选区文字；
2. Console log `capture: shown bundle=<id> len=<n> src=clipboardFallback`（src 字段区分 AX 命中 vs Cmd+C fallback 命中，参见 AppDelegate.swift:288）；
3. 黑名单（appBlocklist）+ minimumSelectionLength + ClipboardSelectionSource changeCount 三道防线均生效（fallback 路径不绕过）。

> 失败信号：
> 1. (a) 关权限后划词仍弹浮条 → mouseUp global monitor 未拆装或装在错误 hookpoint；
> 2. (a) ⌥Space 触发后弹 NSAlert "SliceAI 启动失败" → 错误地把 capture 失败路由到 startupError UX（应只在 bootstrap throws 时弹）；
> 3. (b) Figma 划词浮条不出 → ClipboardSelectionSource changeCount 校验过严或 fallback 链路被绕过；
> 4. (b) Console log src 字段始终为 `accessibility` 或缺失 → SelectionPayload.source 映射 helper 错。

- [ ] **Step 5: 无 API Key 时的错误提示**

操作：Settings → 清空 OpenAI Provider 的 API Key → 触发 → 验证 ResultPanel.fail UX（"请先在设置中配置 API Key"或类似）

- [ ] **Step 6: 修改 Tool / Provider 后配置立即生效并写入 config-v2.json**

操作：Settings → 改某个 Tool 的 systemPrompt → 保存 → cat config-v2.json 验证字段更新 → 触发该 Tool → 验证 prompt 已生效

- [ ] **Step 7: 删除 config-v2.json 后重启：app 能从 config.json 重新 migrate**

操作：备份 config-v2.json → 删除 → 重启 app → 验证 migrator 跑 + diff config.json 仍未变

- [ ] **Step 8: 同一机器切回旧分支 / 旧 build：旧 app 读取原 config.json 仍正常**

操作：git stash → 切到 main pre-M3 commit → 重 build → 启动 → 验证 v0.1 行为仍工作 → 切回当前分支

### Mini-spec 新增 4 项

- [ ] **Step 9: F1.4 编辑自定义变量 → 写盘 + 占位符替换**

操作：
1. Settings → 加自定义变量 `key=value`
2. cat config-v2.json 验证含 variables 字段
3. 在 prompt 加 `{{key}}`
4. 触发 → 验证模型收到的 prompt 含替换值

- [ ] **Step 10: F1.5 全新安装（删除整个 SliceAI app support 目录）→ 自动写默认 config-v2.json**

操作：
```bash
APP_SUPPORT="$HOME/Library/Application Support/SliceAI"
BACKUP_ROOT="$(mktemp -d /tmp/sliceai-backup.XXXXXX)"
echo "BACKUP_ROOT=$BACKUP_ROOT"

if [ -d "$APP_SUPPORT" ]; then
  mv "$APP_SUPPORT" "$BACKUP_ROOT/SliceAI"
fi

open SliceAI.app
ls "$APP_SUPPORT"
```
期望：含 config-v2.json + cost.sqlite + audit.jsonl；config-v2.json 含 4 个内置工具默认配置

恢复（验证后在同一终端执行；若换终端，用上面输出的 `BACKUP_ROOT=...` 路径重新赋值，避免覆盖用户原配置）：
```bash
APP_SUPPORT="$HOME/Library/Application Support/SliceAI"
if [ -d "$BACKUP_ROOT/SliceAI" ]; then
  rm -rf "$APP_SUPPORT"
  mv "$BACKUP_ROOT/SliceAI" "$APP_SUPPORT"
fi
rmdir "$BACKUP_ROOT" 2>/dev/null || true
```

- [ ] **Step 11: F2.3 v1 含 displayMode = .bubble / .replace 的 tool 配置经 migrator 后能正常出 ResultPanel（不报 .notImplemented）**

操作：
1. 临时手改 ~/Library/Application Support/SliceAI/config.json 把某个工具的 displayMode 改为 "bubble"
2. 删除 config-v2.json
3. 重启 app（trigger migrator）
4. 在 Safari 划词触发该工具
5. 验证 ResultPanel 出现并正常流式
6. Console 应有 "fallback to .window sink" 警告 log

- [ ] **Step 12: F2.4 启动失败 UX：appSupport 目录不可写时弹 NSAlert + 退出**

操作：
```bash
APP_SUPPORT="$HOME/Library/Application Support/SliceAI"
mkdir -p "$APP_SUPPORT"
ORIG_MODE="$(stat -f '%Lp' "$APP_SUPPORT")"
chmod 555 "$APP_SUPPORT"
open SliceAI.app
```
期望：弹 NSAlert "SliceAI 启动失败" + 描述；点击退出后 dock icon 立即消失（**不**进入正常状态）

恢复：
```bash
chmod "$ORIG_MODE" "$APP_SUPPORT"
```

> **F9.1 R9 walking back R8 — 原 Step 13（损坏 config-v2.json → SettingsScene 横幅 + save 不覆盖）已删除**：
> R9 review 验证此场景与 D-27 mini-spec 决议不相容：plan §AppContainer.bootstrap 在 line 811 `_ = try await v2ConfigStore.current()` eager 触发配置加载；损坏 config-v2.json 会让该行 throws → bootstrap throws → AppDelegate Task catch → `showStartupErrorAlertAndExit` → app 退出。SettingsViewModel.reload() 永远不会运行；loadError 永远是 nil；SettingsScene banner 永远不显示。Step 13 验收路径在 v0.2 不可达。
>
> v0.2 替代回归：损坏 config-v2.json 启动场景的预期行为是"NSAlert 提示 + 退出"，已由 `Step 12: F2.4 启动失败 UX：appSupport 目录不可写时弹 NSAlert + 退出` 覆盖（同一 startupError UX 路径）。loadError state + save guard 保留作 Phase 2 future hook（manual refresh / cross-process consistency check 接入时启用）；Phase 2 引入此 feature 后再加专门的回归验收项。

- [ ] **Step 13: F3.1 ToolEditorView 切 Provider 清空 modelId（Round-3 R3.1 新增）**

操作：
1. Settings → Tools → 选一个已有 prompt tool（或新建一个）
2. 在 Provider 区段：模型覆写填一个非空的 `gpt-4o-mini`（或任何具体模型 id）
3. Provider Picker 切换到**另一个不同的 provider**（如果只有 1 个 provider，先 Settings → Providers 加一个 DeepSeek/Moonshot 等不同 provider）
4. 关闭 Settings 窗口（保存）
5. `cat ~/Library/Application\ Support/SliceAI/config-v2.json | jq '.tools[] | select(.kind.prompt) | .kind.prompt.provider'`

期望：
- Picker 切 provider 后，UI 上"模型覆写"输入框立即清空（modelId 显示为 placeholder）
- config-v2.json 内对应 tool 的 `kind.prompt.provider.fixed.modelId` 是 `null` 或字段缺省
- 实际触发执行该 tool 时，控制台日志显示用的是新 provider 的 `defaultModel`，不是旧 `gpt-4o-mini`

> **Why this exists**：providerIdBinding setter 在切 provider 时清空 modelId（plan §F2 Round-3 R3.1 修订）。漏掉清空会让旧 modelId 被发给新 provider，请求直接失败（如 OpenAI gpt-4o-mini 发给 DeepSeek API），用户难以诊断。本回归 step 验证 setter 行为按预期落地。

- [ ] **Step 14: 验收报告**

用户报告每项"通过 / 不通过"。如某项未通过 → reset 相关 task → 回 implementation 修 → 重跑该项 + 影响范围内的其他项。

- [ ] **Step 15: M3.5 标记完成**

无 commit；如 13 项全通过 → M3.5 完成；进 M3.6。

---

## Task 16: M3.6 — 文档归档 + v0.2.0 release tag + DMG

**目标**：归档 M3 实施过程；发 v0.2.0 tag + 打 unsigned DMG。

**Files:**
- Modify: `README.md`（项目模块表 + V2* → 正名 + 加 Orchestration / Capabilities 模块说明）
- Modify: `CLAUDE.md`（架构总览段更新）
- Create: `docs/Module/SliceCore.md`
- Create: `docs/Module/Orchestration.md`
- Create: `docs/Module/Capabilities.md`
- Create: `docs/Task-detail/2026-04-28-phase-0-m3-mini-spec.md`（mini-spec 实施过程归档）
- Create: `docs/Task-detail/2026-04-28-phase-0-m3-implementation.md`（implementation plan 实施过程归档）
- Modify: `docs/Task_history.md`（加 M3 索引）
- Modify: `docs/v2-refactor-master-todolist.md`（M3 状态 ⏳ → ✅）

- [ ] **Step 1: 更新 README.md**

把 README 中"项目模块"段的 v1 命名（Tool / Provider / Configuration / FileConfigurationStore）改回 v2 spec 原名。加 Orchestration / Capabilities 两个模块的描述。

- [ ] **Step 2: 更新 CLAUDE.md "架构总览"段**

CLAUDE.md 当前架构总览段写的是 v1 + v2-additive；M3 后要改为：
- 移除 "v1 ToolExecutor 触发链" 描述
- 改为 "v2 ExecutionEngine + 10 依赖" 描述
- "触发与执行流" 段把 ToolExecutor → ExecutionEngine
- 模块表加 Orchestration / Capabilities 两行

- [ ] **Step 3: 创建 docs/Module/SliceCore.md / Orchestration.md / Capabilities.md**

按 user CLAUDE.md §1.1 模块文档规范：每个文件含模块功能、技术实现、接口定义、运行逻辑、代码实现说明。

- [ ] **Step 4: 创建 docs/Task-detail/2026-04-28-phase-0-m3-mini-spec.md**

归档 mini-spec 实施过程：
- 任务背景：M3 mini-spec 设计阶段
- 任务结果：mini-spec 已 Codex review loop 10 轮 approve
- 引用 mini-spec 文件路径 + codex-loop log 路径

- [ ] **Step 5: 创建 docs/Task-detail/2026-04-28-phase-0-m3-implementation.md**

归档 implementation 实施过程：
- 任务背景：M3 16 个 task 的实施
- 任务结果：M3.1 → M3.5 全部通过
- ToDoList：本 plan 的 Task 1-16 完成情况
- 修改文件清单：所有改动文件
- 测试结果：4 关 CI gate 全绿 + 13 项手工回归全通过

- [ ] **Step 6: 更新 docs/Task_history.md**

加 M3 索引：

> **编号规则**：本 plan/spec 口径对齐修复已占用 Task 35；如果实施时 `Task_history.md` 最高编号仍是 35，则 M3 implementation 归档使用 Task 36。若期间又新增任务，按当前最高编号 + 1，不硬编码。

```markdown
## Task 36：Phase 0 M3 — Switch to V2

- 任务名称：Phase 0 M3 mini-spec 设计 + implementation
- 任务描述：完成 v1 → v2 类型族切换；接入 ExecutionEngine 真实启动路径；发 v0.2.0
- 任务开始时间：2026-04-28
- 任务详细记录：[mini-spec 归档](Task-detail/2026-04-28-phase-0-m3-mini-spec.md) + [implementation 归档](Task-detail/2026-04-28-phase-0-m3-implementation.md)
- 任务结果：M3.0~M3.6 7 task 全过；v0.2.0 unsigned DMG 已发
```

- [ ] **Step 7: 更新 docs/v2-refactor-master-todolist.md**

把 §3.3 M3 各项的 ⏳ 改为 ✅；末尾加 "M3 完成于 2026-04-XX，详见 [Task-detail](Task-detail/2026-04-28-phase-0-m3-implementation.md)"。

- [ ] **Step 8: Commit M3.6 文档**

```bash
git add README.md CLAUDE.md docs/
git commit -m "$(cat <<'EOF'
docs(m3): archive M3 implementation + update README/CLAUDE.md/Module docs

- README + CLAUDE.md 架构总览：v1 ToolExecutor → v2 ExecutionEngine；加 Orchestration / Capabilities 模块
- docs/Module/SliceCore.md / Orchestration.md / Capabilities.md 新建（按 user CLAUDE.md §1.1 文档规范）
- docs/Task-detail/2026-04-28-phase-0-m3-mini-spec.md + 2026-04-28-phase-0-m3-implementation.md 归档
- docs/Task_history.md + master todolist M3 状态 → ✅

D-31；M3.6 文档归档段。

Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>
EOF
)"
```

- [ ] **Step 9: 跑 4 关 CI gate（最后一次确认）**

```
(cd SliceAIKit && swift build)
(cd SliceAIKit && swift test --parallel --enable-code-coverage)
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```
Expected: All PASS

- [ ] **Step 10: 跑 scripts/build-dmg.sh 0.2.0 + 显式计算 SHA256（Round-2 R2.4 修订；本 loop = M3 plan 第三次 codex review）**

> **Round-2 R2.4 修订（2026-04-29 本 loop）**：旧 Step 10 末行写"SHA256 也输出"是错的——`scripts/build-dmg.sh`（line 76）只 echo `[build-dmg] Built: <path>`，**不计算 SHA256**。release.yml CI 在 line 28-32 用独立 step `Compute SHA256` 跑 `shasum -a 256 ... | awk '{print $1}'` 写入 `${{ steps.sha.outputs.sha }}`，再插入 release body line 57 的 `SHA256:` 字段。本地预检若不显式跑同口径 `shasum`，Step 13 manual fallback 无 SHA256 可用 + Step 14 / Step 13.5（本 loop 新增）三方一致性检查无法做。**修法**：Step 10 加显式 `shasum -a 256` 命令并把结果写到本地文件 `build/SliceAI-0.2.0.dmg.sha256` 供 Step 13 / Step 13.5 引用。

```bash
# 1) 跑打包脚本
scripts/build-dmg.sh 0.2.0

# 2) 显式计算 SHA256（与 release.yml `Compute SHA256` step 完全同口径）
BUILD_SHA256=$(shasum -a 256 build/SliceAI-0.2.0.dmg | awk '{print $1}')

# 3) 写入校验和文件，标准 shasum 格式（"<hex>  <path>"），供后续 step + 第三方 verify 使用
echo "$BUILD_SHA256  build/SliceAI-0.2.0.dmg" | tee build/SliceAI-0.2.0.dmg.sha256

# 4) 终端回显，方便 implementer 记录
echo "BUILD_SHA256=$BUILD_SHA256"
```

Expected:
- 文件 `build/SliceAI-0.2.0.dmg` 存在；
- 文件 `build/SliceAI-0.2.0.dmg.sha256` 存在，内容为 `<64位 hex>  build/SliceAI-0.2.0.dmg` 格式（可被 `shasum -a 256 -c` 复核）；
- 终端输出 `BUILD_SHA256=<64位 hex>` —— implementer 必须记录此值；Step 13 manual fallback / Step 13.5 三方一致性检查都要复用。

- [ ] **Step 11: 验证 DMG 可安装 + 启动**

```bash
open build/SliceAI-0.2.0.dmg
# 拖到 Applications，启动测试
```

期望：DMG 内 .app 可启动，行为与开发 build 一致。

- [ ] **Step 12: 推 M3 PR + merge**

```bash
git push origin feature/phase-0-m3-switch-to-v2
gh pr create --title "Phase 0 M3 — Switch to V2 + v0.2.0 release" --body "$(cat <<'EOF'
## Summary
- 接入 v2 ExecutionEngine 真实启动路径；删除 v1 类型族；rename V2*/PresentationMode/SelectionOrigin 回 spec 原名
- 4 个内置工具实机行为与 v0.1 等价；F8.3 ordering + F9.2 single-flight invocation 契约落地
- 13 项手工回归全过（spec §4.2.5 原 8 项 + mini-spec 新增 4 项 + Round-3 R3.1 新增 1 项）
- v0.2.0 unsigned DMG 已打：build/SliceAI-0.2.0.dmg

## Test plan
- [x] 4 关 CI gate 全绿（swift build / test / xcodebuild / swiftlint --strict）
- [x] M3.5 13 项手工回归全过（用户验证）
- [x] M3.0 5 步小 commit 序列（D-26）+ 每步四关绿
- [x] M3.1 additive 装配 + v1 触发链全程可用
- [x] M3.2 触发链端到端 + ordering / single-flight 实测
- [x] M3.3 4 启动场景验证（v2 / 仅 v1 / 都不在 / v2 损坏）

## Reference
- mini-spec: `docs/superpowers/specs/2026-04-28-phase-0-m3-mini-spec.md`（10 轮 Codex review approve）
- implementation plan: `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`
- codex-loop log: `docs/Task-detail/codex-loop-phase-0-m3-mini-spec.md`

🤖 Generated with [Claude Code](https://claude.com/claude-code)
EOF
)"
```

PR review approve 后 merge。

- [ ] **Step 13: 发 v0.2.0 tag + GitHub Release（Round-6 R6.1 修订：SemVer 一致性）**

> **Round-6 R6.1 修订（2026-04-28）**：旧 plan 写 `git tag v0.2`，但 Step 10 本地预检用 `scripts/build-dmg.sh 0.2.0` 产物 `build/SliceAI-0.2.0.dmg`；`.github/workflows/release.yml:23` 把 tag 剥 `v` 前缀作 version，所以 `v0.2` → version `0.2` → CI 产 `build/SliceAI-0.2.dmg`。三方版本不一致：本地预检 `0.2.0`、tag `v0.2`、CI 产物 `0.2`。修法：统一 SemVer `v0.2.0`，让本地预检 / tag / CI 产物三方文件名严格一致；同步更新 PR 文案 / release title / 验证步骤的所有 `v0.2` 文案为 `v0.2.0`。

```bash
git checkout main
git pull
git tag v0.2.0    # SemVer：必须 MAJOR.MINOR.PATCH 三段；release.yml 剥 `v` 前缀后得 0.2.0，与 build-dmg.sh 0.2.0 输出文件名严格一致
git push origin v0.2.0
```

> **note**：本步推 tag 后，`.github/workflows/release.yml` 触发 → `Extract version` 步骤把 `v0.2.0` 转为 `0.2.0` → `Build DMG` 用 `scripts/build-dmg.sh 0.2.0` 重建 → 产物 `build/SliceAI-0.2.0.dmg` 与 Step 10 本地预检 100% 同名（也保证 SHA256 在同一构建文件上计算）。如果 Step 13 误推 `v0.2` → CI 会构建 `SliceAI-0.2.dmg`，与本地预检的 `SliceAI-0.2.0.dmg` 文件名不一致，下载方文案 / Release notes / SHA256 全部错位。

GitHub Actions `.github/workflows/release.yml` 应该自动跑（按 `v*` tag 触发）；输出 GitHub Release（draft）含 SliceAI-0.2.0.dmg 附件。

如未自动触发（**Round-7 R7.1 修订：fallback 必须用同一 SemVer tag `v0.2.0`，不能裸 v0.2 / Round-2 R2.4 修订：fallback notes 必须含 SHA256 + Installation 步骤，与自动 release.yml body 字段对齐**）：

```bash
# Round-7 R7.1：手动 fallback 必须绑到 v0.2.0 tag（与 Actions 自动 release 同 tag），否则会创建/引用
# 错误的 v0.2 tag、上传 SliceAI-0.2.0.dmg 但 release 元数据写 v0.2，重新引入 R6 修过的版本错位。
#
# Round-2 R2.4：unsigned DMG 是公开分发的安全敏感产物，release notes 必须含 SHA256 + Installation
# 安装步骤（与 .github/workflows/release.yml line 46-57 自动 release body 字段一致）；fallback 路径
# 不能比自动路径"少给"信息让下载方无法核验完整性。

# 1) 从 Step 10 写入的校验和文件读 SHA256
SHA256_FILE="build/SliceAI-0.2.0.dmg.sha256"
if [ ! -f "$SHA256_FILE" ]; then
  echo "ERROR: $SHA256_FILE missing — run Step 10 first to compute SHA256" >&2
  exit 1
fi
BUILD_SHA256=$(awk '{print $1}' "$SHA256_FILE")

# 2) 用 mktemp + unquoted heredoc 让 ${BUILD_SHA256} 展开；避免 inline `--notes "$(cat <<'EOF'..."`
#    单引号 EOF 阻止变量展开的陷阱（旧 plan 的 fallback 就是这个错）。
NOTES_FILE=$(mktemp -t sliceai-release-notes.XXXXXX)
cat > "$NOTES_FILE" <<EOF
Phase 0 底层重构完成；无用户可见新功能；archival milestone。

v0.2.0 = M1 (V2 数据模型) + M2 (Orchestration/Capabilities 引擎) + M3 (V2 接入 + v1 删除 + rename)

### Checksum
SHA256: ${BUILD_SHA256}

### Installation
Unsigned DMG. 安装步骤：
1. 双击 DMG，将 SliceAI.app 拖到 /Applications；
2. 首次启动需绕过 Gatekeeper：右键 → Open，或运行
   xattr -d com.apple.quarantine /Applications/SliceAI.app
3. 授予 Accessibility 权限；
4. 在 Settings 填 OpenAI API key（或任意 OpenAI 兼容 baseURL+key）。

变更详见 docs/Task-detail/2026-04-28-phase-0-m3-implementation.md
EOF

# 3) 用 --notes-file 替代 --notes，避免 shell 展开 / 引号嵌套出错
gh release create v0.2.0 --draft \
  --title "SliceAI v0.2.0 — Phase 0 完成" \
  --notes-file "$NOTES_FILE" \
  build/SliceAI-0.2.0.dmg

rm -f "$NOTES_FILE"
```

> **Round-7 R7.1 grep 兜底**：执行 Step 13 前 implementer 必须跑 `rg "gh release create v0\.2\b|git tag v0\.2\b|git push origin v0\.2\b" docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md` 验证 0 命中（裸 `v0.2` tag 引用已全部清除）。本 plan 内其他文件路径名 / 注释里出现 `v0.2` 是合法（指 v0.2 版本号语义不是 tag 字符串），grep pattern 用 `\b` 边界 + 命令前缀限定避免误报。

- [ ] **Step 13.5: release artifact 完整性检查（Round-2 R2.4 修订 + Round-7 R7.1 修订；本 loop = M3 plan 第三次 codex review）**

> **Round-7 R7.1 修订（2026-04-29 本 loop）**：旧 R2.4 版本 Step 13.5 把 `LOCAL_SHA == REMOTE_SHA` 作为硬要求是错的——`scripts/build-dmg.sh`（line 16-77）每次 build 都跑 `xcodebuild archive`（嵌入 timestamp / build path / DT_TOOLCHAIN_BUILD 等动态字段）+ `hdiutil create -format UDZO`（压缩容器含 mtime 字段）+ unsigned 不带 codesign 归一化，**没有任何可复现构建（reproducible build）约束**（无 `SOURCE_DATE_EPOCH` / 无 `--norm` / 无 `ditto --norm`）。在自动 release 路径下，`.github/workflows/release.yml`（line 25-26）会在 GitHub-hosted runner 重新跑 `scripts/build-dmg.sh`，CI 的 binary timestamps / build paths 与本地预检 binary 必然不同 → CI_SHA ≠ LOCAL_SHA 是 expected behavior，不是 plan failure。旧 Step 13.5 line 4683 `if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then exit 1` 在自动路径下必 FAIL，implementer 要么卡死 release 要么绕过 gate。**修法**：按 release 路径分支验证：(a) 通用一致性（无论 auto / manual）：tag / artifact 文件名 / release body SHA == 远端 artifact SHA（同源一致性）；(b) Manual fallback 专属：LOCAL_SHA == REMOTE_SHA（fallback 路径上传的就是本地 binary，必须一致）；(c) Auto path 下 LOCAL ≠ REMOTE 是 advisory 不是 FAIL。implementer 用 `RELEASE_PATH={auto|manual}` env var 显式声明本次走哪条路径（默认 auto）。

```bash
# RELEASE_PATH=auto（默认；正常路径：tag 推上后 GitHub Actions 自动 release.yml 重建 + 上传）
# RELEASE_PATH=manual（fallback：自动 release 失败，用户跑了 Step 13 后半段 gh release create 上传本地 binary）
RELEASE_PATH="${RELEASE_PATH:-auto}"
LOCAL_SHA=$(awk '{print $1}' build/SliceAI-0.2.0.dmg.sha256 2>/dev/null || echo "")
echo "RELEASE_PATH=$RELEASE_PATH LOCAL_SHA=${LOCAL_SHA:-<none>}"

# (1) 拉 release JSON（含 body + assets + tagName）
RELEASE_JSON=$(gh release view v0.2.0 --json body,assets,name,tagName)

# (2) 通用：tag 一致性（SemVer v0.2.0；R6 + R7 修订已挡裸 v0.2，这里再次兜底）
TAG_NAME=$(echo "$RELEASE_JSON" | jq -r .tagName)
if [ "$TAG_NAME" != "v0.2.0" ]; then
  echo "FAIL: release tagName=$TAG_NAME, expected v0.2.0"
  exit 1
fi

# (3) 通用：artifact 文件名 == SliceAI-0.2.0.dmg（与 SemVer / build-dmg.sh 输出严格一致）
if ! echo "$RELEASE_JSON" | jq -r '.assets[].name' | grep -qx "SliceAI-0.2.0.dmg"; then
  echo "FAIL: release artifact 文件名不是 SliceAI-0.2.0.dmg"
  echo "$RELEASE_JSON" | jq -r '.assets[].name'
  exit 1
fi

# (4) 下载远端 artifact 复算 REMOTE_SHA
TMPDMG=$(mktemp -t sliceai-release-verify.XXXXXX.dmg)
gh release download v0.2.0 --pattern "SliceAI-0.2.0.dmg" --output "$TMPDMG" --clobber
REMOTE_SHA=$(shasum -a 256 "$TMPDMG" | awk '{print $1}')
rm -f "$TMPDMG"
echo "REMOTE_SHA=$REMOTE_SHA"

# (5) 通用：release body SHA == REMOTE_SHA（同源一致性；挡 release.yml notes 与 artifact 错位 / 用户改过 body 但 artifact 没变）
if ! echo "$RELEASE_JSON" | jq -r .body | grep -qF "$REMOTE_SHA"; then
  echo "FAIL: release body 不含 REMOTE_SHA=$REMOTE_SHA（body 与 artifact 不同源；下载方无法核验）"
  echo "--- release body ---"
  echo "$RELEASE_JSON" | jq -r .body
  exit 1
fi

# (6) 路径分支：LOCAL_SHA 比对策略
if [ "$RELEASE_PATH" = "manual" ]; then
  # Manual fallback：用户跑了 Step 13 后半段 gh release create 上传 build/SliceAI-0.2.0.dmg；
  # LOCAL_SHA 与 REMOTE_SHA 必须一致（同一个本地 binary 上传）
  if [ -z "$LOCAL_SHA" ]; then
    echo "FAIL: manual fallback 路径缺 build/SliceAI-0.2.0.dmg.sha256；先跑 Step 10 计算 LOCAL_SHA"
    exit 1
  fi
  if [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    echo "FAIL: manual fallback SHA mismatch（上传的 binary 与本地预检不一致）"
    echo "  LOCAL_SHA  = $LOCAL_SHA"
    echo "  REMOTE_SHA = $REMOTE_SHA"
    exit 1
  fi
  echo "PASS (manual fallback): release artifact + body + LOCAL 三方 SHA 一致 ($REMOTE_SHA)"
elif [ "$RELEASE_PATH" = "auto" ]; then
  # Auto path：GitHub Actions release.yml 重建 binary，CI_SHA != LOCAL_SHA 是 expected
  # （scripts/build-dmg.sh 不是可复现构建：xcodebuild archive timestamp + hdiutil UDZO mtime 等动态字段）；
  # 通用检查 (2)(3)(5) 已守住"远端 artifact + body 同源 + SemVer 文件名一致"。
  if [ -n "$LOCAL_SHA" ] && [ "$LOCAL_SHA" != "$REMOTE_SHA" ]; then
    echo "advisory (auto path): LOCAL_SHA != REMOTE_SHA 是 expected（CI 重建 binary，scripts/build-dmg.sh 不带可复现构建约束）"
    echo "  LOCAL_SHA  = $LOCAL_SHA"
    echo "  REMOTE_SHA = $REMOTE_SHA"
  fi
  echo "PASS (auto path): release artifact + body 同源 ($REMOTE_SHA)"
else
  echo "FAIL: 未知 RELEASE_PATH=$RELEASE_PATH（必须为 auto 或 manual）"
  exit 1
fi
```

Expected: 末行 `PASS (auto path): ...` 或 `PASS (manual fallback): ...`；任一项 FAIL 即停止 release，回查：
- (2)/(3) FAIL → tag / artifact 命名错位（检查 Step 13 是否真用 v0.2.0 推 tag）；
- (5) FAIL → release body 与 artifact 不同源（auto path 罕见；manual fallback 多半是 Step 13 fallback 命令 `${BUILD_SHA256}` 没正确展开 → 检查是否用了 unquoted heredoc）；
- (6) Manual mismatch → 上传的 binary 与本地预检不同（多半是 fallback 命令前 `build/SliceAI-0.2.0.dmg` 被覆盖；重跑 Step 10 即可）。

> **note (R7.1 修订核心)**：旧 R2.4 版本 Step 13.5 假设 LOCAL_SHA == REMOTE_SHA 总是成立，但 `scripts/build-dmg.sh` 不是 reproducible build——`xcodebuild archive` 内嵌 timestamps / build paths / `DT_TOOLCHAIN_BUILD` 动态字段 + `hdiutil -format UDZO` 容器有 mtime；CI 与 local 在不同 host 跑 binary 必然不同。如果未来要让 LOCAL == REMOTE 总成立，需要把 scripts/build-dmg.sh 改成可复现构建（`SOURCE_DATE_EPOCH` + `xcrun strip` / `ditto --norm` / 锁定 toolchain / 锁定 macOS SDK 等）—— 这是 v0.2 范围之外的 build infrastructure 改造，留 Phase 2+ 跟进。本 step 通过路径分支验证（通用同源一致性 + manual 路径 byte-equal）已覆盖完整性 / 真实性 / 一致性三大目标，不需要 LOCAL == REMOTE 硬约束。

- [ ] **Step 14: 验证 release 可下载**

打开 GitHub Release 页面（draft）→ 检查 SliceAI-0.2.0.dmg 附件存在 → 下载 + 安装 + 启动验证。

无问题后把 draft → publish。

- [ ] **Step 15: M3.6 完成**

git tag 已推；release 已发布；docs 已 merge；M3 标记完成。

---

## Self-Review Checklist (writing-plans skill 强制)

After 完整 plan 写完，对照 mini-spec 检查覆盖：

**1. Spec coverage:**

| mini-spec 段 | plan 覆盖 task |
|---|---|
| §M3.1 Sub-step A (F1.5 V2ConfigStore 写盘) | Task 1 |
| §M3.1 Sub-step B (Xcode deps) | Task 2 |
| §M3.1 Sub-step C (adapter + AppContainer additive) | Task 3 + 4 |
| §M3.1 Sub-step D (AppDelegate async bootstrap) | Task 5 |
| §M3.1 Sub-step E (冒烟) | Task 6 |
| §M3.0 Step 1 (caller switch + audit) | Task 7（含 D-30b OutputDispatcher 修订；含 spy tests Iteration I） |
| §M3.0 Step 2 (v1 7 文件删 + LLMProviderFactory 升级 + SelectionReader) | Task 8 |
| §M3.0 Step 3 (rename V2* → 正名) | Task 9 |
| §M3.0 Step 4 (PresentationMode → DisplayMode) | Task 10 |
| §M3.0 Step 5 (SelectionOrigin → SelectionSource) | Task 11 |
| §M3.2 (触发链端到端验收) | Task 12 |
| §M3.3 (4 启动场景) | Task 13 |
| §M3.4 (grep validation) | Task 14 |
| §M3.5 (13 项手工回归) | Task 15 |
| §M3.6 (文档归档 + v0.2.0 release) | Task 16 |
| D-26 (5 步序列) | Task 7-11 |
| D-27 (10 依赖装配) | Task 4 |
| D-28 (SelectionPayload 保留 + SelectionReader 新建) | Task 8 |
| D-29 (SettingsUI binding 策略) | Task 7 Iteration F |
| D-30 (ExecutionEventConsumer 14 case) | Task 7 Iteration C |
| D-30b (non-window fallback) | Task 7 Iteration A |
| D-31 (v0.2.0 release tag 时机) | Task 16 Step 13 |
| F8.3 ordering invariant + spy test | Task 7 Iteration D + Iteration I |
| F9.2 single-flight invocation 契约 + 2 spy tests | Task 3 + Task 7 Iteration D + Iteration I |
| F8.2 7 处 configStore.current() audit | Task 7 Iteration G |
| F3.2 单一写入测试 | Task 7 Iteration I (SingleWriterContractTests) |

**Gaps:** 无。所有 mini-spec §M3.x sub-step + D-26~D-31 + F1~F9 修订都映射到 task。

**2. Placeholder scan:**
- 无 "TBD" / "TODO" / "implement later"
- 无 "Add appropriate error handling" 类口号
- 无 "Write tests for the above"（每个 spy test 都有完整代码）
- "Similar to Task N" 这种引用 — 检查后无；每个 task 步骤独立可读

**3. Type consistency:**
- `setActiveInvocation(_:)` / `clearActiveInvocation()` / `append(chunk:invocationId:)` — Task 3 + Task 7 一致
- `ResultPanelWindowSinkAdapter` 名 — Task 3 创建 + Task 4 装配 + Task 7 引用 一致
- `ExecutionEventConsumer` — Task 7 Iteration C 创建 + Task 7 Iteration D 使用 一致
- `V2Tool` / `V2Provider` 命名 — Task 7 之前用 V2*, Task 9 后用正名 — 已在每个 task 标注命名时机

**Spec coverage status: COMPLETE.**

---

## Execution Handoff

**Plan complete and saved to `docs/superpowers/plans/2026-04-28-phase-0-m3-switch-to-v2.md`. Two execution options:**

**1. Subagent-Driven (recommended)** - 我 dispatch 一个新 subagent 跑每 task，task 间复盘；适合 16 个 task 这种体量

**2. Inline Execution** - 在当前 session 用 executing-plans，batch + checkpoint review

**Which approach?**

如果选 1：REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`
如果选 2：REQUIRED SUB-SKILL: `superpowers:executing-plans`

---

> **本 plan 完成 = Phase 0 M3 真正可以开始 implementation**。
> 约 4800 行；16 个 task；按 mini-spec 已 approve 的 §M3.0~§M3.6 设计逐 task 落地。
