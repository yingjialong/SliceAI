# Phase 2 Skill Registry MVP Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Skill Registry MVP so SliceAI can scan user-selected Claude/Codex-style skill roots, show skills in Settings, bind up to 5 enabled skills to Agent Tools, and let AgentExecutor progressively load `SKILL.md` through the conceptual `sliceai.load_skill` pseudo-tool. The OpenAI-compatible function name is `sliceai_load_skill`.

**Architecture:** `SliceCore` owns canonical skill/config models. `Capabilities` owns filesystem scanning, `SKILL.md` parsing, registry snapshots, and diagnostics. `Orchestration` consumes only skills bound to the current Agent Tool and exposes a local pseudo-tool; `SettingsUI` manages roots and bindings; `SliceAIApp` wires the real registry.

**Tech Stack:** Swift 6.0, macOS 14+, SwiftPM package `SliceAIKit`, SwiftUI Settings UI, XCTest, existing `ExecutionEvent` tool-call lifecycle, no new third-party dependency.

---

## Scope Check

This plan implements the single MVP frozen in `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`. It does not implement marketplace, remote install, scripts, `references/` / `assets/` resource reading, Prompt Tool skill binding, DisplayMode work, TTS, or English Tutor.

The plan intentionally uses a small in-house frontmatter parser. Replacing it with `SwiftSkill` or a YAML library is not part of this implementation because the current app baseline is Swift 6.0 / macOS 14+.

## File Structure

### SliceCore

- Modify `SliceAIKit/Sources/SliceCore/Skill.swift`
  - Canonical skill model, manifest fields, source ref, registry state, settings, overrides.
- Modify `SliceAIKit/Sources/SliceCore/Configuration.swift`
  - Add `skillSettings`.
  - Increment schema version.
- Modify `SliceAIKit/Sources/SliceCore/ToolKind.swift`
  - Replace single `AgentTool.skill` with `AgentTool.skills`.
  - Add custom `Codable` compatibility for legacy `skill`.
- Modify `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
  - Set `skillSettings: .empty`.
  - Agent tools use `skills: []`.
- Modify `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift`
  - Ensure validation catches Agent Tool skill count > 5.
- Modify tests:
  - `SliceAIKit/Tests/SliceCoreTests/SkillTests.swift`
  - `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`
  - `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`
  - `SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift`

### Capabilities

- Replace `SliceAIKit/Sources/Capabilities/Skills/SkillRegistryProtocol.swift`
  - Protocol returns `SliceCore.Skill` and registry snapshot types.
- Modify `SliceAIKit/Sources/Capabilities/Skills/MockSkillRegistry.swift`
  - Keep actor mock, add snapshot and load behavior.
- Create `SliceAIKit/Sources/Capabilities/Skills/SkillMarkdownParser.swift`
  - Parse `SKILL.md` frontmatter/body.
- Create `SliceAIKit/Sources/Capabilities/Skills/SkillDirectoryScanner.swift`
  - Discover candidates from configured roots.
- Create `SliceAIKit/Sources/Capabilities/Skills/LocalSkillRegistry.swift`
  - Actor composing scanner + parser + settings into snapshots.
- Create `SliceAIKit/Tests/CapabilitiesTests/Fixtures/Skills/...`
  - Local fixtures for valid, missing-description, duplicate, disabled, and oversize cases.
- Modify tests:
  - `SliceAIKit/Tests/CapabilitiesTests/SkillRegistryProtocolTests.swift`
  - Create `SliceAIKit/Tests/CapabilitiesTests/SkillMarkdownParserTests.swift`
  - Create `SliceAIKit/Tests/CapabilitiesTests/SkillDirectoryScannerTests.swift`
  - Create `SliceAIKit/Tests/CapabilitiesTests/LocalSkillRegistryTests.swift`

### Orchestration

- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
  - Inject `SkillRegistryProtocol`.
  - Keep run-time loaded skill set.
- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCatalog.swift`
  - Extend catalog with built-in pseudo-tool.
- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`
  - Dispatch provider function `sliceai_load_skill` locally before MCP gate and display it as conceptual `sliceai.load_skill`.
- Modify `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`
  - Add skill metadata block with 8,000 character budget.
- Modify `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`
  - Cover pseudo-tool, metadata, denial, duplicate loading, and no-MCP side effects.

### SettingsUI

- Create `SliceAIKit/Sources/SettingsUI/SkillsViewModel.swift`
  - Async snapshot reload, source add/delete/reorder, override changes.
- Create `SliceAIKit/Sources/SettingsUI/Pages/SkillsPage.swift`
  - Roots management and skill list.
- Modify `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`
  - Add sidebar item.
- Modify `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`
  - Add Agent Skills section.
- Modify `SliceAIKit/Sources/SettingsUI/ToolEditorView+Bindings.swift`
  - Add selected skill binding, max 5 guard.
- Create `SliceAIKit/Tests/SettingsUITests/SkillsViewModelTests.swift`
  - Test source/override behavior.
- Create `SliceAIKit/Tests/SettingsUITests/ToolEditorSkillsBindingTests.swift`
  - Test binding codec and max 5 behavior.

### App Wiring and Docs

- Modify `SliceAIApp/AppContainer.swift`
  - Construct `LocalSkillRegistry` from config store.
  - Inject registry into `ExecutionEngine` and `AgentExecutor`.
- Modify `README.md`, `docs/Task-detail/2026-05-20-phase-2-skill-registry-mvp-spec.md`, `docs/Module/Capabilities.md` if present, and `docs/v2-refactor-master-todolist.md`.

---

## Task 0: Preflight and Worktree

**Files:**
- Read: `docs/superpowers/specs/2026-05-20-phase-2-skill-registry-mvp.md`
- Read: `CLAUDE.md`
- Read: `SliceAIKit/Package.swift`

- [ ] **Step 1: Confirm current branch and working tree**

Run:

```bash
git status -sb
git branch --show-current
```

Expected:

```text
## main...origin/main [ahead 1]
main
```

If there are unrelated user changes, do not revert them. Record them before continuing.

- [ ] **Step 2: Create implementation branch or worktree**

Run:

```bash
git switch -c codex/phase-2-skill-registry-mvp
```

Expected:

```text
Switched to a new branch 'codex/phase-2-skill-registry-mvp'
```

If the branch exists, run:

```bash
git switch codex/phase-2-skill-registry-mvp
```

- [ ] **Step 3: Run baseline focused tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SkillTests|ToolKindTests|ConfigurationTests|SkillRegistryProtocolTests|AgentExecutorTests|SettingsUITests'
```

Expected: PASS. If existing tests fail before edits, stop and document the baseline failure in the task detail.

---

## Task 1: SliceCore Skill Schema and Codable Compatibility

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/Skill.swift`
- Modify: `SliceAIKit/Sources/SliceCore/Configuration.swift`
- Modify: `SliceAIKit/Sources/SliceCore/ToolKind.swift`
- Modify: `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
- Modify: `SliceAIKit/Sources/SliceCore/ConfigurationStore.swift`
- Compile-fix references to `AgentTool(skill:)` across `SliceAIKit/Sources` and `SliceAIKit/Tests`
- Test: `SliceAIKit/Tests/SliceCoreTests/SkillTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ConfigurationStoreTests.swift`

- [ ] **Step 1: Write failing SliceCore tests**

First update existing `SkillTests.swift` tests that lock the old M1 `SkillManifest` / `Skill` shape. Remove or rewrite:

- `test_skillManifest_codable`
- `test_skill_carriesProvenance_andRoundtrips`
- `test_skillManifest_goldenJSON_fieldOrder`

Those tests currently construct `SkillManifest(name:description:version:triggers:requiredCapabilities:)` and `Skill(id:path:manifest:resources:provenance:)`; after this task there is one canonical Phase 2 shape with `canonicalName`, `skillFile`, `source`, and `state`.

Add these replacement tests to `SkillTests.swift`:

```swift
func test_skillSettings_defaultsRoundTrip() throws {
    let settings = SkillSettings(
        sources: [
            SkillSource(
                id: "source-home",
                displayName: "Home Skills",
                rootPath: "/Users/test/.agents/skills",
                isEnabled: true,
                order: 0
            )
        ],
        overrides: ["writing": .off]
    )

    let data = try JSONEncoder().encode(settings)
    let decoded = try JSONDecoder().decode(SkillSettings.self, from: data)

    XCTAssertEqual(decoded, settings)
    XCTAssertEqual(decoded.overrides["writing"], .off)
}

func test_skillManifest_minimalCodableFields() throws {
    let manifest = SkillManifest(
        name: "writing",
        description: "Use when editing long-form text.",
        disableModelInvocation: false,
        allowedTools: ["Bash", "Read"],
        userInvocable: true,
        rawFrontmatter: "name: writing",
        instructionsCharacterCount: 120
    )

    let data = try JSONEncoder().encode(manifest)
    let decoded = try JSONDecoder().decode(SkillManifest.self, from: data)

    XCTAssertEqual(decoded, manifest)
}
```

Add these tests to `ToolKindTests.swift`:

```swift
func test_agentTool_decodesLegacySingleSkillIntoSkillsArray() throws {
    let json = Data(#"""
    {
      "systemPrompt": "agent sys",
      "initialUserPrompt": "{{selection}}",
      "contexts": [],
      "provider": { "fixed": { "providerId": "openai", "modelId": null } },
      "skill": { "id": "writing", "pinVersion": null },
      "mcpAllowlist": [],
      "builtinCapabilities": [],
      "maxSteps": 3,
      "stopCondition": "finalAnswerProvided"
    }
    """#.utf8)

    let decoded = try JSONDecoder().decode(AgentTool.self, from: json)

    XCTAssertEqual(decoded.skills, [SkillReference(id: "writing", pinVersion: nil)])
}

func test_agentTool_encodesOnlySkillsArray() throws {
    let agent = AgentTool(
        systemPrompt: nil,
        initialUserPrompt: "{{selection}}",
        contexts: [],
        provider: .fixed(providerId: "openai", modelId: nil),
        skills: [SkillReference(id: "writing", pinVersion: nil)],
        mcpAllowlist: [],
        builtinCapabilities: [],
        maxSteps: 3,
        stopCondition: .finalAnswerProvided,
        toolCallPolicy: nil
    )

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let json = try XCTUnwrap(String(data: try encoder.encode(agent), encoding: .utf8))

    XCTAssertTrue(json.contains(#""skills":[{"id":"writing"}]"#), json)
    XCTAssertFalse(json.contains(#""skill":"#), json)
}
```

Add to `ConfigurationTests.swift`:

```swift
func test_configurationDefaultsSkillSettingsWhenMissing() throws {
    let json = Data(#"""
    {
      "schemaVersion": 3,
      "providers": [],
      "tools": [],
      "hotkeys": { "toggleCommandPalette": "option+space" },
      "triggers": {
        "floatingToolbarEnabled": true,
        "commandPaletteEnabled": true,
        "triggerDelayMs": 120,
        "minimumSelectionLength": 1
      },
      "telemetry": { "enabled": false },
      "appBlocklist": [],
      "appearance": "auto"
    }
    """#.utf8)

    let decoded = try JSONDecoder().decode(Configuration.self, from: json)

    XCTAssertEqual(decoded.skillSettings, .empty)
}
```

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SkillTests|ToolKindTests|ConfigurationTests'
```

Expected: FAIL with compile errors for `SkillSettings`, `AgentTool.skills`, and new `SkillManifest` initializer.

- [ ] **Step 3: Implement SliceCore models**

Replace `SliceAIKit/Sources/SliceCore/Skill.swift` with this shape, preserving existing `SkillResource` and `SkillReference` compatibility:

```swift
import Foundation

/// 本地 skill 资源；对应用户配置 root 下的 Claude / Codex 风格 skill 包。
public struct Skill: Identifiable, Sendable, Codable, Equatable {
    /// 稳定 id；MVP 中等于 canonicalName。
    public let id: String
    /// 用户可见名称；优先来自 SKILL.md frontmatter name，缺省使用目录名。
    public let canonicalName: String
    /// skill 根目录路径。
    public let path: URL
    /// SKILL.md 文件绝对路径。
    public let skillFile: URL
    /// 从 SKILL.md frontmatter 解析出的 manifest。
    public var manifest: SkillManifest
    /// supporting files 索引；MVP 只展示，不读取内容。
    public var resources: [SkillResource]
    /// 信任来源；用户配置的外部 roots 默认为 selfManaged。
    public var provenance: Provenance
    /// 来源 root 摘要，供 UI 展示和冲突诊断。
    public var source: SkillSourceRef
    /// registry 合并后的运行期状态。
    public var state: SkillRegistryState

    /// 构造 Skill。
    public init(
        id: String,
        canonicalName: String,
        path: URL,
        skillFile: URL,
        manifest: SkillManifest,
        resources: [SkillResource],
        provenance: Provenance,
        source: SkillSourceRef,
        state: SkillRegistryState
    ) {
        self.id = id
        self.canonicalName = canonicalName
        self.path = path
        self.skillFile = skillFile
        self.manifest = manifest
        self.resources = resources
        self.provenance = provenance
        self.source = source
        self.state = state
    }
}

/// `SKILL.md` frontmatter 的最小兼容解析结果。
public struct SkillManifest: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let disableModelInvocation: Bool
    public let allowedTools: [String]
    public let userInvocable: Bool?
    public let rawFrontmatter: String
    public let instructionsCharacterCount: Int

    /// 构造 SkillManifest。
    public init(
        name: String,
        description: String,
        disableModelInvocation: Bool = false,
        allowedTools: [String] = [],
        userInvocable: Bool? = nil,
        rawFrontmatter: String = "",
        instructionsCharacterCount: Int = 0
    ) {
        self.name = name
        self.description = description
        self.disableModelInvocation = disableModelInvocation
        self.allowedTools = allowedTools
        self.userInvocable = userInvocable
        self.rawFrontmatter = rawFrontmatter
        self.instructionsCharacterCount = instructionsCharacterCount
    }
}
```

Append settings and state types in the same file:

```swift
/// Skill 来源 root 的轻量引用。
public struct SkillSourceRef: Sendable, Codable, Equatable {
    public let sourceId: String
    public let rootPath: String

    /// 构造 SkillSourceRef。
    public init(sourceId: String, rootPath: String) {
        self.sourceId = sourceId
        self.rootPath = rootPath
    }
}

/// Registry 合并 source、frontmatter、override 后的可展示状态。
public enum SkillRegistryState: String, Sendable, Codable {
    case enabled
    case disabled
    case defaultDisabled
    case parseError
    case shadowed
    case sourceError
    case tooLarge
}

/// 用户 skill 配置，随 config-v2.json 持久化。
public struct SkillSettings: Sendable, Codable, Equatable {
    public var sources: [SkillSource]
    public var overrides: [String: SkillEnablementOverride]

    /// 空 skill 设置。
    public static let empty = SkillSettings(sources: [], overrides: [:])

    /// 构造 SkillSettings。
    public init(sources: [SkillSource], overrides: [String: SkillEnablementOverride]) {
        self.sources = sources
        self.overrides = overrides
    }
}

/// 用户配置的 skill root。
public struct SkillSource: Identifiable, Sendable, Codable, Equatable {
    public let id: String
    public var displayName: String
    public var rootPath: String
    public var isEnabled: Bool
    public var order: Int

    /// 构造 SkillSource。
    public init(id: String, displayName: String, rootPath: String, isEnabled: Bool, order: Int) {
        self.id = id
        self.displayName = displayName
        self.rootPath = rootPath
        self.isEnabled = isEnabled
        self.order = order
    }
}

/// Skill 启停 override；缺省时遵循 SKILL.md frontmatter。
public enum SkillEnablementOverride: String, Sendable, Codable {
    case on
    case off
}
```

- [ ] **Step 4: Update Configuration**

In `Configuration.swift`, increment schema and add `skillSettings` with backward-compatible decoding:

```swift
public var skillSettings: SkillSettings

public static let currentSchemaVersion = 3
```

Use a manual `init(from:)` that decodes `skillSettings` with default `.empty`:

```swift
self.skillSettings = try c.decodeIfPresent(SkillSettings.self, forKey: .skillSettings) ?? .empty
```

Update the public initializer to accept `skillSettings: SkillSettings = .empty`.

- [ ] **Step 5: Update AgentTool Codable**

In `ToolKind.swift`, replace `public var skill: SkillReference?` with:

```swift
public var skills: [SkillReference]
```

Add manual `Codable` for `AgentTool`:

```swift
private enum CodingKeys: String, CodingKey {
    case systemPrompt, initialUserPrompt, contexts, provider, skill, skills,
         mcpAllowlist, builtinCapabilities, maxSteps, stopCondition, toolCallPolicy
}

public init(from decoder: any Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    self.systemPrompt = try c.decodeIfPresent(String.self, forKey: .systemPrompt)
    self.initialUserPrompt = try c.decode(String.self, forKey: .initialUserPrompt)
    self.contexts = try c.decode([ContextRequest].self, forKey: .contexts)
    self.provider = try c.decode(ProviderSelection.self, forKey: .provider)
    let newSkills = try c.decodeIfPresent([SkillReference].self, forKey: .skills)
    let legacySkill = try c.decodeIfPresent(SkillReference.self, forKey: .skill)
    self.skills = newSkills ?? legacySkill.map { [$0] } ?? []
    self.mcpAllowlist = try c.decode([MCPToolRef].self, forKey: .mcpAllowlist)
    self.builtinCapabilities = try c.decode([BuiltinCapability].self, forKey: .builtinCapabilities)
    self.maxSteps = try c.decode(Int.self, forKey: .maxSteps)
    self.stopCondition = try c.decode(StopCondition.self, forKey: .stopCondition)
    self.toolCallPolicy = try c.decodeIfPresent(AgentToolCallPolicy.self, forKey: .toolCallPolicy)
}

public func encode(to encoder: any Encoder) throws {
    var c = encoder.container(keyedBy: CodingKeys.self)
    try c.encodeIfPresent(systemPrompt, forKey: .systemPrompt)
    try c.encode(initialUserPrompt, forKey: .initialUserPrompt)
    try c.encode(contexts, forKey: .contexts)
    try c.encode(provider, forKey: .provider)
    try c.encode(skills, forKey: .skills)
    try c.encode(mcpAllowlist, forKey: .mcpAllowlist)
    try c.encode(builtinCapabilities, forKey: .builtinCapabilities)
    try c.encode(maxSteps, forKey: .maxSteps)
    try c.encode(stopCondition, forKey: .stopCondition)
    try c.encodeIfPresent(toolCallPolicy, forKey: .toolCallPolicy)
}
```

Update every `AgentTool(...)` initializer call from `skill:` to `skills:` before running focused tests. SwiftPM compiles the full package even with a test filter, so this must be part of Task 1, not left for later UI/orchestration tasks.

Run this search and migrate every result:

```bash
rg -n "AgentTool\\(|skill:" SliceAIKit/Sources SliceAIKit/Tests
```

Known affected areas at plan time:

- `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
- `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Actions.swift`
- `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift`
- `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- `SliceAIKit/Tests/OrchestrationTests/PermissionGraphTests.swift`
- Orchestration helper code that pattern-matches or forwards `AgentTool.skill`

Rewrite the existing `ToolKindTests.test_agentTool_codable_roundtrip` to use `skills:` and update any legacy JSON tests so old `"skill": null` decodes to `skills == []`.

- [ ] **Step 6: Add validation for max 5 skills**

In `Tool.validate()`, extend validation:

```swift
if case .agent(let agent) = kind, agent.skills.count > 5 {
    throw SliceError.configuration(.validationFailed(
        "Tool '\(id)': Agent tools can bind at most 5 skills"
    ))
}
```

- [ ] **Step 7: Run SliceCore tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SkillTests|ToolKindTests|ConfigurationTests|ConfigurationStoreTests'
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add SliceAIKit/Sources/SliceCore SliceAIKit/Tests/SliceCoreTests
git commit -m "feat(core): add skill settings schema"
```

---

## Task 2: SKILL.md Parser and Directory Scanner

**Files:**
- Create: `SliceAIKit/Sources/Capabilities/Skills/SkillMarkdownParser.swift`
- Create: `SliceAIKit/Sources/Capabilities/Skills/SkillDirectoryScanner.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/SkillMarkdownParserTests.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/SkillDirectoryScannerTests.swift`

- [ ] **Step 1: Write failing parser tests**

Create `SkillMarkdownParserTests.swift`:

```swift
import XCTest
import SliceCore
@testable import Capabilities

final class SkillMarkdownParserTests: XCTestCase {
    func test_parseValidSkillMarkdown() throws {
        let text = """
        ---
        name: writing
        description: Use when editing long-form text.
        disable-model-invocation: false
        allowed-tools:
          - Read
          - Bash
        user-invocable: true
        ---

        Follow these writing rules.
        """

        let result = try SkillMarkdownParser().parse(text, directoryName: "fallback")

        XCTAssertEqual(result.manifest.name, "writing")
        XCTAssertEqual(result.manifest.description, "Use when editing long-form text.")
        XCTAssertEqual(result.manifest.allowedTools, ["Read", "Bash"])
        XCTAssertEqual(result.instructions.trimmingCharacters(in: .whitespacesAndNewlines), "Follow these writing rules.")
    }

    func test_parseFallsBackToDirectoryNameWhenNameMissing() throws {
        let text = """
        ---
        description: Useful for summaries.
        ---
        Summarize carefully.
        """

        let result = try SkillMarkdownParser().parse(text, directoryName: "summary")

        XCTAssertEqual(result.manifest.name, "summary")
        XCTAssertEqual(result.manifest.description, "Useful for summaries.")
    }

    func test_parseRejectsInvalidBoolean() {
        let text = """
        ---
        name: bad
        description: Bad bool.
        disable-model-invocation: maybe
        ---
        Body
        """

        XCTAssertThrowsError(try SkillMarkdownParser().parse(text, directoryName: "bad"))
    }

    func test_parseMissingDescriptionReturnsWarning() throws {
        let text = """
        ---
        name: no-description
        ---
        Body
        """

        let result = try SkillMarkdownParser().parse(text, directoryName: "fallback")

        XCTAssertEqual(result.manifest.description, "")
        XCTAssertTrue(result.warnings.contains(.missingDescription))
    }
}
```

- [ ] **Step 2: Write failing scanner tests**

Create `SkillDirectoryScannerTests.swift`:

```swift
import XCTest
import SliceCore
@testable import Capabilities

final class SkillDirectoryScannerTests: XCTestCase {
    func test_scannerFindsRootCollectionAndClaudeCodexLayouts() throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("direct/SKILL.md"), name: "direct")
        try writeSkill(root.appendingPathComponent(".claude/skills/claude-skill/SKILL.md"), name: "claude-skill")
        try writeSkill(root.appendingPathComponent(".agents/skills/codex-skill/SKILL.md"), name: "codex-skill")
        try writeSkill(root.appendingPathComponent(".codex/skills/local-codex/SKILL.md"), name: "local-codex")

        let source = SkillSource(id: "root", displayName: "Root", rootPath: root.path, isEnabled: true, order: 0)
        let candidates = try SkillDirectoryScanner().candidates(in: source)

        XCTAssertEqual(Set(candidates.map(\.directory.lastPathComponent)), [
            "direct", "claude-skill", "codex-skill", "local-codex"
        ])
    }

    func test_scannerDoesNotRecurseDeeply() throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("a/b/c/SKILL.md"), name: "deep")

        let source = SkillSource(id: "root", displayName: "Root", rootPath: root.path, isEnabled: true, order: 0)
        let candidates = try SkillDirectoryScanner().candidates(in: source)

        XCTAssertTrue(candidates.isEmpty)
    }

    func test_scannerRejectsSymlinkEscapingSourceRoot() throws {
        let root = try makeTempRoot()
        let outside = try makeTempRoot()
        try writeSkill(outside.appendingPathComponent("escape/SKILL.md"), name: "escape")
        let link = root.appendingPathComponent("escape")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: outside.appendingPathComponent("escape"))

        let source = SkillSource(id: "root", displayName: "Root", rootPath: root.path, isEnabled: true, order: 0)
        let result = try SkillDirectoryScanner().scan(in: source)

        XCTAssertTrue(result.candidates.isEmpty)
        XCTAssertTrue(result.rejections.contains { $0.reason == .symlinkEscapesSourceRoot })
    }
}
```

Add helper methods in the same test file:

```swift
private func makeTempRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("sliceai-skill-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func writeSkill(_ url: URL, name: String) throws {
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try """
    ---
    name: \(name)
    description: \(name) description
    ---
    Instructions for \(name).
    """.write(to: url, atomically: true, encoding: .utf8)
}
```

- [ ] **Step 3: Run tests to verify red**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SkillMarkdownParserTests|SkillDirectoryScannerTests'
```

Expected: FAIL with missing parser/scanner types.

- [ ] **Step 4: Implement parser**

Create `SkillMarkdownParser.swift`:

```swift
import Foundation
import SliceCore

/// 解析 Claude / Codex 风格 SKILL.md 的最小 frontmatter 子集。
public struct SkillMarkdownParser: Sendable {
    public static let maxSkillBytes = 128 * 1024

    /// 解析 SKILL.md 文本。
    public init() {}

    /// 解析 SKILL.md，返回 manifest 与正文。
    /// - Parameters:
    ///   - text: 文件文本。
    ///   - directoryName: 缺少 name 时使用的目录名。
    /// - Returns: 解析结果。
    public func parse(_ text: String, directoryName: String) throws -> SkillMarkdownParseResult {
        let parts = try splitFrontmatter(text)
        let fields = try parseFields(parts.frontmatter)
        let name = fields.scalars["name"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = fields.scalars["description"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        var warnings: Set<SkillMarkdownWarning> = []
        if description.isEmpty {
            warnings.insert(.missingDescription)
        }
        let disable = try parseBool(fields.scalars["disable-model-invocation"] ?? "false")
        let userInvocable = try fields.scalars["user-invocable"].map(parseBool)
        let manifest = SkillManifest(
            name: (name?.isEmpty == false ? name : directoryName) ?? directoryName,
            description: description,
            disableModelInvocation: disable,
            allowedTools: fields.lists["allowed-tools"] ?? fields.scalars["allowed-tools"].map { [$0] } ?? [],
            userInvocable: userInvocable,
            rawFrontmatter: parts.frontmatter,
            instructionsCharacterCount: parts.body.count
        )
        return SkillMarkdownParseResult(manifest: manifest, instructions: parts.body, warnings: warnings)
    }
}

/// SKILL.md 解析结果。
public struct SkillMarkdownParseResult: Sendable, Equatable {
    public let manifest: SkillManifest
    public let instructions: String
    public let warnings: Set<SkillMarkdownWarning>
}

/// SKILL.md 可恢复解析警告；registry 决定警告如何影响 state。
public enum SkillMarkdownWarning: String, Sendable, Codable, Equatable {
    case missingDescription
}
```

Add private helpers in the same file:

```swift
private struct FrontmatterParts {
    let frontmatter: String
    let body: String
}

private struct ParsedFields {
    var scalars: [String: String] = [:]
    var lists: [String: [String]] = [:]
}
```

Implement `splitFrontmatter`, `parseFields`, and `parseBool` as line-based helpers with Chinese comments around list parsing. Print no free-form logs from parser; callers log diagnostics.

When `description` is absent or trims to empty, keep `manifest.description == ""` and include `.missingDescription` in `warnings`. Do not throw: the registry must keep the skill visible in Settings as `.defaultDisabled` with a warning diagnostic, because the user can still inspect and fix the package.

- [ ] **Step 5: Implement scanner**

Create `SkillDirectoryScanner.swift`:

```swift
import Foundation
import SliceCore

/// 从用户配置的 root 中发现 SKILL.md 候选文件。
public struct SkillDirectoryScanner: Sendable {
    public static let maxCandidatesPerSource = 200
    private let fileManager: FileManager

    /// 构造扫描器。
    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    /// 发现一个 source root 下的候选 skill。
    public func candidates(in source: SkillSource) throws -> [SkillCandidate] {
        try scan(in: source).candidates
    }

    /// 发现候选 skill，并返回被安全规则拒绝的路径摘要。
    public func scan(in source: SkillSource) throws -> SkillDirectoryScanResult {
        guard source.isEnabled else { return SkillDirectoryScanResult(candidates: [], rejections: []) }
        let root = URL(fileURLWithPath: source.rootPath).standardizedFileURL
        let resolvedRoot = root.resolvingSymlinksInPath()
        let patterns = candidateParentDirectories(root: root)
        var candidates: [SkillCandidate] = []
        var rejections: [SkillDirectoryScannerRejection] = []
        if fileManager.fileExists(atPath: root.appendingPathComponent("SKILL.md").path) {
            appendCandidateIfAllowed(
                directory: root,
                skillFile: root.appendingPathComponent("SKILL.md"),
                source: source,
                resolvedRoot: resolvedRoot,
                candidates: &candidates,
                rejections: &rejections
            )
        }
        for parent in patterns {
            let children = try directChildrenWithSkillFiles(parent: parent, source: source, root: root)
            for child in children {
                appendCandidateIfAllowed(
                    directory: child.directory,
                    skillFile: child.skillFile,
                    source: source,
                    resolvedRoot: resolvedRoot,
                    candidates: &candidates,
                    rejections: &rejections
                )
            }
        }
        return SkillDirectoryScanResult(candidates: Array(candidates.prefix(Self.maxCandidatesPerSource)), rejections: rejections)
    }
}

/// Scanner 结果；registry 将 rejections 映射为 UI diagnostics。
public struct SkillDirectoryScanResult: Sendable, Equatable {
    public let candidates: [SkillCandidate]
    public let rejections: [SkillDirectoryScannerRejection]
}

/// Scanner 发现的候选 skill 目录。
public struct SkillCandidate: Sendable, Equatable {
    public let source: SkillSource
    public let directory: URL
    public let skillFile: URL
}

/// Scanner 拒绝候选的原因。
public struct SkillDirectoryScannerRejection: Sendable, Equatable {
    public let source: SkillSource
    public let path: URL
    public let reason: SkillDirectoryScannerRejectionReason
}

public enum SkillDirectoryScannerRejectionReason: Sendable, Equatable {
    case symlinkEscapesSourceRoot
}
```

Add helper `candidateParentDirectories(root:)` returning:

```swift
[
    root,
    root.appendingPathComponent("skills", isDirectory: true),
    root.appendingPathComponent(".claude/skills", isDirectory: true),
    root.appendingPathComponent(".agents/skills", isDirectory: true),
    root.appendingPathComponent(".codex/skills", isDirectory: true)
]
```

Use `contentsOfDirectory(at:includingPropertiesForKeys:)` and only inspect one level.

For every candidate directory and `SKILL.md`, resolve symlinks with `resolvingSymlinksInPath()` and require both resolved paths to stay under the resolved source root. Implement a small path-prefix helper that compares path components, not string prefixes, so `/tmp/root2` is not treated as inside `/tmp/root`. Rejected symlink escapes must appear in `SkillDirectoryScanResult.rejections` and must not appear in `candidates`.

- [ ] **Step 6: Run parser/scanner tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SkillMarkdownParserTests|SkillDirectoryScannerTests'
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/Capabilities/Skills SliceAIKit/Tests/CapabilitiesTests
git commit -m "feat(capabilities): parse and scan local skills"
```

---

## Task 3: LocalSkillRegistry Actor and Diagnostics

**Files:**
- Modify: `SliceAIKit/Sources/Capabilities/Skills/SkillRegistryProtocol.swift`
- Modify: `SliceAIKit/Sources/Capabilities/Skills/MockSkillRegistry.swift`
- Create: `SliceAIKit/Sources/Capabilities/Skills/LocalSkillRegistry.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/SkillRegistryProtocolTests.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/LocalSkillRegistryTests.swift`

- [ ] **Step 1: Write failing registry tests**

Create `LocalSkillRegistryTests.swift`:

```swift
import XCTest
import SliceCore
@testable import Capabilities

final class LocalSkillRegistryTests: XCTestCase {
    func test_snapshotReturnsEnabledSkillFromConfiguredSource() async throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("writing/SKILL.md"), name: "writing", description: "Write clearly.")
        let settings = SkillSettings(sources: [source(root)], overrides: [:])
        let registry = LocalSkillRegistry(settingsProvider: { settings })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.map(\.canonicalName), ["writing"])
        XCTAssertEqual(snapshot.skills.first?.state, .enabled)
    }

    func test_duplicateNamesShadowLowerPrioritySource() async throws {
        let first = try makeTempRoot()
        let second = try makeTempRoot()
        try writeSkill(first.appendingPathComponent("writing/SKILL.md"), name: "writing", description: "First.")
        try writeSkill(second.appendingPathComponent("writing/SKILL.md"), name: "writing", description: "Second.")
        let settings = SkillSettings(
            sources: [source(first, id: "first", order: 0), source(second, id: "second", order: 1)],
            overrides: [:]
        )
        let registry = LocalSkillRegistry(settingsProvider: { settings })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.filter { $0.state == .enabled }.count, 1)
        XCTAssertEqual(snapshot.skills.filter { $0.state == .shadowed }.count, 1)
    }

    func test_loadSkillInstructionsReturnsBody() async throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("writing/SKILL.md"), name: "writing", description: "Write.", body: "Use active voice.")
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let payload = try await registry.loadSkillInstructions(id: "writing")

        XCTAssertEqual(payload.canonicalName, "writing")
        XCTAssertTrue(payload.instructions.contains("Use active voice."))
    }

    func test_missingDescriptionIsDefaultDisabledAndDiagnosed() async throws {
        let root = try makeTempRoot()
        try writeSkill(root.appendingPathComponent("writing/SKILL.md"), name: "writing", description: nil)
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.first?.state, .defaultDisabled)
        XCTAssertTrue(snapshot.diagnostics.contains { $0.code == .missingDescription })
    }

    func test_oversizeSkillFileIsTooLargeAndNotLoadable() async throws {
        let root = try makeTempRoot()
        try writeOversizeSkill(root.appendingPathComponent("huge/SKILL.md"))
        let registry = LocalSkillRegistry(settingsProvider: {
            SkillSettings(sources: [source(root)], overrides: [:])
        })

        let snapshot = try await registry.snapshot()

        XCTAssertEqual(snapshot.skills.first?.state, .tooLarge)
        do {
            _ = try await registry.loadSkillInstructions(id: "huge")
            XCTFail("oversize skill must not be loadable")
        } catch {
            // Expected.
        }
    }
}
```

Reuse helper methods from scanner tests or create local helpers in this test file. Keep helpers private to avoid cross-test coupling. Let `writeSkill(..., description: nil)` omit the frontmatter key entirely; do not write `description:`.

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
swift test --package-path SliceAIKit --filter 'LocalSkillRegistryTests|SkillRegistryProtocolTests'
```

Expected: FAIL because protocol and `LocalSkillRegistry` do not match.

- [ ] **Step 3: Update registry protocol**

Replace `SkillRegistryProtocol.swift` with protocol and types:

```swift
import Foundation
import SliceCore

/// Skill 注册表协议：提供 snapshot 查询和 SKILL.md 按需加载。
public protocol SkillRegistryProtocol: Sendable {
    /// 返回当前 registry 快照。
    func snapshot() async throws -> SkillRegistrySnapshot
    /// 按 canonical skill id 查找 active skill。
    func findSkill(id: String) async throws -> Skill?
    /// 加载完整 SKILL.md 指令正文。
    func loadSkillInstructions(id: String) async throws -> SkillInstructionPayload
}
```

Delete the old `Capabilities.Skill` struct from `SkillRegistryProtocol.swift`. After Task 1 there must be exactly one canonical `Skill`, imported from `SliceCore`; leaving the old three-field `Capabilities.Skill` creates ambiguous references and stale tests.

Define `SkillRegistrySnapshot`, `SkillInstructionPayload`, `SkillRegistryDiagnostic`, and `SkillRegistryDiagnosticCode` in the same file. Use this diagnostic code set for MVP:

```swift
public enum SkillRegistryDiagnosticCode: String, Sendable, Codable, Equatable {
    case sourceUnreadable
    case parseError
    case missingDescription
    case tooLarge
    case duplicateName
    case symlinkEscape
}
```

Rewrite `SkillRegistryProtocolTests.swift`; do not keep tests that construct the removed `Capabilities.Skill(id:name:manifestPath:)` shape or call the removed `allSkills()` API. Replacement coverage:

- Empty `MockSkillRegistry` snapshot has no skills and no diagnostics.
- `MockSkillRegistry.findSkill(id:)` returns only enabled injected `SliceCore.Skill` values.
- `MockSkillRegistry.loadSkillInstructions(id:)` returns injected payloads and throws for missing payloads.
- `SkillRegistrySnapshot` / `SkillInstructionPayload` round-trip with `SliceCore.Skill`.

- [ ] **Step 4: Implement LocalSkillRegistry**

Create `LocalSkillRegistry.swift`:

```swift
import Foundation
import OSLog
import SliceCore

/// 文件系统 backed skill registry。
public actor LocalSkillRegistry: SkillRegistryProtocol {
    private let logger = Logger(subsystem: "com.sliceai.capabilities", category: "LocalSkillRegistry")
    private let settingsProvider: @Sendable () async -> SkillSettings
    private let scanner: SkillDirectoryScanner
    private let parser: SkillMarkdownParser

    /// 构造 LocalSkillRegistry。
    public init(
        settingsProvider: @escaping @Sendable () async -> SkillSettings,
        scanner: SkillDirectoryScanner = SkillDirectoryScanner(),
        parser: SkillMarkdownParser = SkillMarkdownParser()
    ) {
        self.settingsProvider = settingsProvider
        self.scanner = scanner
        self.parser = parser
    }

    /// 生成 registry 快照。
    public func snapshot() async throws -> SkillRegistrySnapshot {
        let settings = await settingsProvider()
        var skills: [Skill] = []
        var diagnostics: [SkillRegistryDiagnostic] = []
        for source in settings.sources.sorted(by: { $0.order < $1.order }) where source.isEnabled {
            appendSource(source, settings: settings, skills: &skills, diagnostics: &diagnostics)
        }
        applyShadowing(to: &skills, diagnostics: &diagnostics)
        logger.debug("skill registry snapshot generated count=\(skills.count, privacy: .public)")
        return SkillRegistrySnapshot(
            sources: settings.sources,
            skills: skills,
            diagnostics: diagnostics,
            generatedAt: Date()
        )
    }
}
```

Implement helper methods with Chinese comments:

- `appendSource(_:settings:skills:diagnostics:)`
- `makeSkill(candidate:settings:)`
- `state(for:manifest:settings:)`
- `applyShadowing(to:diagnostics:)`

Helper behavior:

- `appendSource` calls `scanner.scan(in:)`, maps scanner `.symlinkEscapesSourceRoot` rejections to `.symlinkEscape` diagnostics, then calls `makeSkill` for each candidate. A source-level scanner failure becomes a `.sourceUnreadable` diagnostic and does not abort other sources.
- `makeSkill` reads `SKILL.md` as `Data` first and checks `data.count <= SkillMarkdownParser.maxSkillBytes` before constructing `String`. Oversize files create a visible `Skill` with `state == .tooLarge`, `manifest.name` falling back to the directory name, empty instructions count, and a `.tooLarge` diagnostic; they are not loadable.
- `makeSkill` maps parser `.missingDescription` warning to a `.missingDescription` diagnostic and lets `state(for:parseResult:settings:)` make the skill `.defaultDisabled` unless override is `.on`.
- `state` precedence is: `.off` override -> `.disabled`; parse/size/source errors -> their error state; missing description -> `.defaultDisabled` unless `.on`; `disableModelInvocation == true` -> `.defaultDisabled` unless `.on`; `.on` -> `.enabled`; otherwise `.enabled`.
- `applyShadowing` groups by `canonicalName` after source-order scan, keeps the first `.enabled` skill active, marks later `.enabled` duplicates `.shadowed`, and adds `.duplicateName` diagnostics. Already disabled/default-disabled/error skills keep their state and are not promoted over an enabled earlier duplicate.

Diagnostics should use short UI messages and log only fixed fields.

Implement `loadSkillInstructions(id:)` by recomputing a snapshot, finding an enabled active skill, re-reading its `SKILL.md` with the same size guard, parsing it, and returning the body. Do not load `.defaultDisabled`, `.disabled`, `.shadowed`, `.parseError`, `.sourceError`, or `.tooLarge` skills.

- [ ] **Step 5: Update MockSkillRegistry**

Make `MockSkillRegistry` accept `[Skill]` and optional instruction payloads:

```swift
public final actor MockSkillRegistry: SkillRegistryProtocol {
    private let skills: [Skill]
    private let instructions: [String: SkillInstructionPayload]

    public init(skills: [Skill] = [], instructions: [String: SkillInstructionPayload] = [:]) {
        self.skills = skills
        self.instructions = instructions
    }

    public func snapshot() async throws -> SkillRegistrySnapshot {
        SkillRegistrySnapshot(sources: [], skills: skills, diagnostics: [], generatedAt: Date())
    }

    public func findSkill(id: String) async throws -> Skill? {
        skills.first { $0.id == id && $0.state == .enabled }
    }

    public func loadSkillInstructions(id: String) async throws -> SkillInstructionPayload {
        if let payload = instructions[id] { return payload }
        throw SliceError.configuration(.validationFailed("Skill not loadable: <redacted>"))
    }
}
```

- [ ] **Step 6: Run Capabilities tests**

Run:

```bash
swift test --package-path SliceAIKit --filter CapabilitiesTests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/Capabilities/Skills SliceAIKit/Tests/CapabilitiesTests
git commit -m "feat(capabilities): add local skill registry"
```

---

## Task 4: AgentExecutor Pseudo-Tool and Metadata Prompt

**Files:**
- Modify: `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCatalog.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor+ToolCalls.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`

- [ ] **Step 1: Write failing AgentExecutor tests**

Add tests to `AgentExecutorTests.swift`:

```swift
func test_agentWithBoundSkillExposesLoadSkillToolAndMetadata() async throws {
    let skill = makeSkill(name: "writing")
    let payload = makeSkillPayload(name: "writing", instructions: "Follow writing rules.")
    let registry = MockSkillRegistry(skills: [skill], instructions: ["writing": payload])
    let llm = MockToolCallingLLMProvider(turns: [
        toolCallTurn(id: "skill-1", name: "sliceai_load_skill", arguments: "{\"name\":\"writing\"}"),
        finalAnswerTurn("Done")
    ])
    let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient(), skillRegistry: registry)
    let agent = makeAgent(allowlist: [], skills: [SkillReference(id: "writing", pinVersion: nil)])

    let events = await collectEvents(from: await executor.run(
        tool: makeTool(agent: agent),
        agent: agent,
        resolved: makeResolvedContext(),
        provider: MockProvider.openAIStub()
    ))

    XCTAssertTrue(events.contains { event in
        if case .toolCallProposed(_, let ref, _) = event {
            return ref == AgentBuiltInTool.loadSkillRef
        }
        return false
    })
    XCTAssertTrue(events.contains { event in
        if case .toolCallResult(_, let summary) = event { return summary.contains("writing") }
        return false
    })
    XCTAssertTrue(llm.capturedToolRequests.first?.tools.contains { $0.name == "sliceai_load_skill" } ?? false)
    XCTAssertTrue(llm.capturedToolRequests.first?.messages.map(\.content).joined(separator: "\n").contains("Available SliceAI skills") ?? false)
}

func test_loadSkillRejectsUnboundSkillWithoutCallingMCP() async throws {
    let skill = makeSkill(name: "writing")
    let registry = MockSkillRegistry(skills: [skill], instructions: ["writing": makeSkillPayload(name: "writing")])
    let mcp = makeMCPClient()
    let llm = MockToolCallingLLMProvider(turns: [
        toolCallTurn(id: "skill-1", name: "sliceai_load_skill", arguments: "{\"name\":\"writing\"}"),
        finalAnswerTurn("Done")
    ])
    let executor = makeExecutor(llm: llm, mcpClient: mcp, skillRegistry: registry)
    let agent = makeAgent(allowlist: [], skills: [])

    let events = await collectEvents(from: await executor.run(
        tool: makeTool(agent: agent),
        agent: agent,
        resolved: makeResolvedContext(),
        provider: MockProvider.openAIStub()
    ))

    XCTAssertTrue(events.contains { event in
        if case .toolCallError(_, let summary) = event { return summary.contains("not bound") }
        return false
    })
    let mcpCallCount = await mcp.callCount
    XCTAssertEqual(mcpCallCount, 0)
}

func test_agentWithoutBoundSkillsHidesLoadSkillToolAndMetadata() async throws {
    let llm = MockToolCallingLLMProvider(turns: [finalAnswerTurn("Done")])
    let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient())
    let agent = makeAgent(allowlist: [], skills: [])

    _ = await collectEvents(from: await executor.run(
        tool: makeTool(agent: agent),
        agent: agent,
        resolved: makeResolvedContext(),
        provider: MockProvider.openAIStub()
    ))

    let request = try XCTUnwrap(llm.capturedToolRequests.first)
    XCTAssertFalse(request.tools.contains { $0.name == AgentBuiltInTool.loadSkillName })
    XCTAssertFalse(request.messages.map(\.content).joined(separator: "\n").contains("Available SliceAI skills"))
}

func test_duplicateLoadSkillReturnsAlreadyLoadedAndDoesNotReload() async throws {
    let skill = makeSkill(name: "writing")
    let registry = CountingSkillRegistry(skill: skill, payload: makeSkillPayload(name: "writing"))
    let llm = MockToolCallingLLMProvider(turns: [
        toolCallTurn(id: "skill-1", name: "sliceai_load_skill", arguments: "{\"name\":\"writing\"}"),
        toolCallTurn(id: "skill-2", name: "sliceai_load_skill", arguments: "{\"name\":\"writing\"}"),
        finalAnswerTurn("Done")
    ])
    let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient(), skillRegistry: registry)
    let agent = makeAgent(allowlist: [], skills: [SkillReference(id: "writing", pinVersion: nil)])

    let events = await collectEvents(from: await executor.run(
        tool: makeTool(agent: agent),
        agent: agent,
        resolved: makeResolvedContext(),
        provider: MockProvider.openAIStub()
    ))

    let loadCount = await registry.loadCount
    XCTAssertEqual(loadCount, 1)
    XCTAssertTrue(events.contains { event in
        if case .toolCallResult(_, let summary) = event { return summary.contains("already loaded") }
        return false
    })
}

func test_skillMetadataTruncatesDescriptionWhenOverBudget() async throws {
    let skills = (0..<5).map { index in
        makeSkill(
            name: "skill-\(index)",
            description: String(repeating: "d", count: 3_000),
            skillFile: URL(fileURLWithPath: "/tmp/skills/skill-\(index)/SKILL.md")
        )
    }
    let registry = MockSkillRegistry(skills: skills)
    let llm = MockToolCallingLLMProvider(turns: [finalAnswerTurn("Done")])
    let executor = makeExecutor(llm: llm, mcpClient: makeMCPClient(), skillRegistry: registry)
    let refs = skills.map { SkillReference(id: $0.id, pinVersion: nil) }
    let agent = makeAgent(allowlist: [], skills: refs)

    _ = await collectEvents(from: await executor.run(
        tool: makeTool(agent: agent),
        agent: agent,
        resolved: makeResolvedContext(),
        provider: MockProvider.openAIStub()
    ))

    let content = try XCTUnwrap(llm.capturedToolRequests.first?.messages.map(\.content).joined(separator: "\n"))
    let parts = content.components(separatedBy: "Available SliceAI skills for this tool:")
    XCTAssertEqual(parts.count, 2)
    let block = parts[1]
    XCTAssertLessThanOrEqual(block.count, 8_000)
    for skill in skills {
        XCTAssertTrue(block.contains("name: \(skill.canonicalName)"))
        XCTAssertTrue(block.contains("path: \(skill.skillFile.path)"))
    }
    XCTAssertTrue(block.contains("..."))
}
```

Update test helpers to accept `skillRegistry`, `skills`, and richer `makeSkill` parameters. Add a private `CountingSkillRegistry` actor in the test file for the duplicate-load test.

```swift
private func makeExecutor(
    llm: MockToolCallingLLMProvider,
    broker: MockPermissionBroker = MockPermissionBroker(),
    mcpClient: any MCPClientProtocol,
    descriptors: [MCPDescriptor]? = nil,
    timeout: UInt64 = 1_000_000_000,
    skillRegistry: any SkillRegistryProtocol = MockSkillRegistry()
) -> AgentExecutor
```

Add this test helper:

```swift
private actor CountingSkillRegistry: SkillRegistryProtocol {
    private let skill: Skill
    private let payload: SkillInstructionPayload
    private(set) var loadCount = 0

    init(skill: Skill, payload: SkillInstructionPayload) {
        self.skill = skill
        self.payload = payload
    }

    func snapshot() async throws -> SkillRegistrySnapshot {
        SkillRegistrySnapshot(sources: [], skills: [skill], diagnostics: [], generatedAt: Date())
    }

    func findSkill(id: String) async throws -> Skill? {
        skill.id == id && skill.state == .enabled ? skill : nil
    }

    func loadSkillInstructions(id: String) async throws -> SkillInstructionPayload {
        loadCount += 1
        return payload
    }
}
```

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
swift test --package-path SliceAIKit --filter AgentExecutorTests
```

Expected: FAIL with missing `skillRegistry` init parameter or pseudo-tool handling.

- [ ] **Step 3: Inject SkillRegistry into AgentExecutor**

In `AgentExecutor.swift`, add:

```swift
/// Skill registry，供内置 sliceai.load_skill pseudo-tool 按需加载 SKILL.md。
let skillRegistry: any SkillRegistryProtocol
```

Update `init`:

```swift
skillRegistry: any SkillRegistryProtocol = MockSkillRegistry(),
```

Assign to `self.skillRegistry`.

- [ ] **Step 4: Extend tool catalog**

In `AgentExecutor+ToolCatalog.swift`, add constants:

```swift
enum AgentBuiltInTool {
    /// Provider-visible function name. Dot is intentionally avoided because OpenAI-compatible function names
    /// allow only letters, numbers, underscores, and dashes.
    static let loadSkillName = "sliceai_load_skill"
    /// UI/lifecycle synthetic ref for the conceptual pseudo-tool `sliceai.load_skill`.
    static let loadSkillRef = MCPToolRef(server: "sliceai", tool: "load_skill")
}
```

Add `boundSkills: [Skill]` and `skillByName: [String: Skill]` to `AgentToolCatalog`.

When `agent.skills` is non-empty:

1. Resolve each `SkillReference` through `skillRegistry.findSkill(id:)`.
2. Fail with `SliceError.configuration(.invalidTool(...))` if missing or not enabled.
3. Append `ChatTool(name: AgentBuiltInTool.loadSkillName, ...)`.

Keep display copy and docs referring to the conceptual pseudo-tool as `sliceai.load_skill`, but never send a dotted function name to an OpenAI-compatible provider.

- [ ] **Step 5: Add metadata prompt builder**

In `AgentPromptBuilder.swift`, change `buildInitialMessages` signature:

```swift
static func buildInitialMessages(
    agent: AgentTool,
    resolved: ResolvedExecutionContext,
    boundSkills: [Skill]
) -> [ChatMessage]
```

Append metadata to the user prompt:

```swift
private static func appendSkillMetadata(_ prompt: String, boundSkills: [Skill]) -> String {
    guard !boundSkills.isEmpty else { return prompt }
    let lines = boundSkills.map { skill in
        "- name: \(skill.canonicalName)\n  description: \(skill.manifest.description)\n  path: \(skill.skillFile.path)"
    }
    let block = """

    Available SliceAI skills for this tool:
    \(lines.joined(separator: "\n"))

    Use sliceai_load_skill with the exact skill name when a skill is relevant.
    Do not assume instructions from a skill until you load it.
    """
    return prompt + block
}
```

Add a private 8,000 character budget helper with one testable contract:

- Build the skill metadata block separately from the original user prompt.
- The budget applies to the block after the `Available SliceAI skills for this tool:` marker.
- Name and path lines are fixed and must always be preserved for all bound skills in order.
- Description text uses the remaining budget after fixed lines and separators.
- Allocate description budget in bound-skill order; truncate a description only when it would exceed the remaining budget.
- Use ASCII `...` as the truncation suffix.
- If fixed name/path lines alone exceed 8,000 characters, keep them, truncate all descriptions to empty, and log `skill metadata fixed fields exceeded budget`; this should be unreachable with the 5-skill MVP cap but avoids dropping identity fields.

Sketch:

```swift
private static let maxSkillMetadataCharacters = 8_000

private static func skillMetadataBlock(boundSkills: [Skill]) -> String {
    // 先预留 name/path 固定行，再把剩余预算分配给 description。
}
```

- [ ] **Step 6: Handle pseudo-tool calls before MCP gate**

In `AgentExecutor+ToolCalls.swift`, add `loadedSkillNames` to run state:

```swift
private(set) var loadedSkillNames: Set<String> = []
```

Add method:

```swift
func handleLoadSkill(
    _ context: AgentToolCallContext,
    catalog: AgentToolCatalog,
    toolCallState: inout AgentToolCallRunState
) async -> ChatMessage
```

Behavior:

- Yield `.toolCallApproved`.
- Parse `name` argument from `MCPJSONValue.Object`.
- Reject names not in `catalog.skillByName`.
- If already loaded, yield `.toolCallResult` summary `Skill already loaded: <name>` and return matching tool message.
- Load payload via `skillRegistry.loadSkillInstructions(id:)`.
- Record loaded name.
- Yield `.toolCallResult` summary `Loaded skill: <name>`.
- Return tool message containing frontmatter summary and instructions.

In `AgentToolCatalog.ref(forToolName:)`, return `AgentBuiltInTool.loadSkillRef` when `name == AgentBuiltInTool.loadSkillName`.

In `processOneToolCall`, keep the existing lifecycle order: create `context`, resolve `ref`, yield `.toolCallProposed`, parse arguments, then branch to the pseudo-tool before MCP allowlist / policy / permission gate:

```swift
let context = AgentToolCallContext(uiId: UUID(), call: call, continuation: continuation)
let ref = catalog.ref(forToolName: call.name)
continuation.yield(.toolCallProposed(id: context.uiId, ref: ref, argsDescription: describeArguments(call)))
guard let args = call.arguments else {
    return failToolCall(context, summary: "invalid tool arguments", content: "invalid tool arguments")
}
if call.name == AgentBuiltInTool.loadSkillName {
    return await handleLoadSkill(context, catalog: catalog, toolCallState: &toolCallState)
}
```

Do not call `catalog.isAllowed`, `gateMCP`, or `mcpClient.call` for `AgentBuiltInTool.loadSkillName`. Add a test assertion that `.toolCallProposed` appears before `.toolCallApproved` for the pseudo-tool.

- [ ] **Step 7: Run Orchestration tests**

Run:

```bash
swift test --package-path SliceAIKit --filter AgentExecutorTests
```

Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add SliceAIKit/Sources/Orchestration/Executors SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift
git commit -m "feat(orchestration): load bound skills progressively"
```

---

## Task 5: Skills Settings Page

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/SkillsViewModel.swift`
- Create: `SliceAIKit/Sources/SettingsUI/Pages/SkillsPage.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`
- Test: `SliceAIKit/Tests/SettingsUITests/SkillsViewModelTests.swift`

- [ ] **Step 1: Write failing ViewModel tests**

Create `SkillsViewModelTests.swift`:

```swift
import XCTest
import SliceCore
import Capabilities
@testable import SettingsUI

@MainActor
final class SkillsViewModelTests: XCTestCase {
    func test_addSourceAppendsEnabledRootAndSavesConfiguration() async throws {
        let settings = try await makeSettingsViewModel()
        let viewModel = SkillsViewModel(settingsViewModel: settings, registry: MockSkillRegistry())

        await viewModel.addSource(path: "/Users/test/.agents/skills")

        XCTAssertEqual(settings.configuration.skillSettings.sources.count, 1)
        XCTAssertEqual(settings.configuration.skillSettings.sources[0].rootPath, "/Users/test/.agents/skills")
    }

    func test_setOverrideUpdatesConfiguration() async throws {
        let settings = try await makeSettingsViewModel()
        let viewModel = SkillsViewModel(settingsViewModel: settings, registry: MockSkillRegistry())

        await viewModel.setOverride(.off, for: "writing")

        XCTAssertEqual(settings.configuration.skillSettings.overrides["writing"], .off)
    }
}
```

Add tiny test helpers in `SkillsViewModelTests.swift`; do not change production `ConfigurationStore` just to support tests:

```swift
private func makeSettingsViewModel(
    initial: Configuration = DefaultConfiguration.initial()
) async throws -> SettingsViewModel {
    let fileURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("sliceai-settings-\(UUID().uuidString)/config-v2.json")
    let store = ConfigurationStore(fileURL: fileURL, legacyFileURL: nil)
    try await store.update(initial)
    let viewModel = SettingsViewModel(store: store, keychain: SettingsUITestKeychain())
    await viewModel.reload()
    return viewModel
}

private struct SettingsUITestKeychain: KeychainAccessing {
    func readAPIKey(providerId: String) async throws -> String? { nil }
    func writeAPIKey(_ value: String, providerId: String) async throws {}
    func deleteAPIKey(providerId: String) async throws {}
}
```

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
swift test --package-path SliceAIKit --filter SkillsViewModelTests
```

Expected: FAIL with missing `SkillsViewModel`.

- [ ] **Step 3: Implement SkillsViewModel**

Create `SkillsViewModel.swift`:

```swift
import Capabilities
import Foundation
import SliceCore

/// Skills 设置页视图模型，桥接 SettingsViewModel 与 SkillRegistry snapshot。
@MainActor
public final class SkillsViewModel: ObservableObject {
    @Published public private(set) var snapshot: SkillRegistrySnapshot?
    @Published public private(set) var loadError: String?

    private let settingsViewModel: SettingsViewModel
    private let registry: any SkillRegistryProtocol

    /// 构造 SkillsViewModel。
    public init(settingsViewModel: SettingsViewModel, registry: any SkillRegistryProtocol) {
        self.settingsViewModel = settingsViewModel
        self.registry = registry
    }

    /// 重新扫描 skill registry。
    public func reload() async {
        do {
            snapshot = try await registry.snapshot()
            loadError = nil
            print("[SkillsViewModel] reload: skill snapshot loaded")
        } catch {
            loadError = error.localizedDescription
            print("[SkillsViewModel] reload failed – \(error.localizedDescription)")
        }
    }
}
```

Add `addSource`, `removeSource`, `moveSource`, and `setOverride` methods that update `settingsViewModel.configuration.skillSettings`, call `settingsViewModel.save()`, then `reload()`.

- [ ] **Step 4: Implement SkillsPage**

Create `SkillsPage.swift` with:

- `SettingsPageShell(title: "Skills", subtitle: "管理本地 Claude / Codex 风格 skills。")`
- Source roots section with path, enabled toggle, delete button.
- Add root button using `NSOpenPanel` with directory selection.
- Skill list section showing canonical name, description, state, source path.
- Toggle for override `.on` / `.off` / default. Use a segmented picker with labels `默认`、`启用`、`禁用`.

Keep UI dense and settings-like; do not add marketing text or large hero cards.

- [ ] **Step 5: Add Settings sidebar item**

In `SettingsScene.swift`:

1. Import `Capabilities`.
2. Add `private let skillRegistry: any SkillRegistryProtocol`.
3. Update `SettingsScene.init` to accept `skillRegistry: any SkillRegistryProtocol = MockSkillRegistry()` and assign it. The default keeps tests and previews compiling before AppContainer wiring in Task 7.
4. Add `case skills` to `SidebarItem`.
5. Place `SidebarRow(item: .skills)` after `.tools`.
6. Add detail branch:

```swift
case .skills:
    SkillsPage(viewModel: SkillsViewModel(settingsViewModel: viewModel, registry: skillRegistry))
```

7. Add label/icon:

```swift
case .skills: return "Skills"
case .skills: return "sparkles"
```

- [ ] **Step 6: Run Settings tests**

Run:

```bash
swift test --package-path SliceAIKit --filter SettingsUITests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/SettingsUI SliceAIKit/Tests/SettingsUITests
git commit -m "feat(settings): add skills settings page"
```

---

## Task 6: Agent Tool Skill Binding UI

**Files:**
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView+Bindings.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/Pages/ToolsSettingsPage+Actions.swift`
- Test: `SliceAIKit/Tests/SettingsUITests/ToolEditorSkillsBindingTests.swift`

- [ ] **Step 1: Write failing binding tests**

Create `ToolEditorSkillsBindingTests.swift`:

```swift
import XCTest
import SliceCore
@testable import SettingsUI

final class ToolEditorSkillsBindingTests: XCTestCase {
    func test_skillSelectionRejectsMoreThanFiveSkills() {
        var agent = AgentTool(
            systemPrompt: nil,
            initialUserPrompt: "{{selection}}",
            contexts: [],
            provider: .fixed(providerId: "openai", modelId: nil),
            skills: [],
            mcpAllowlist: [],
            builtinCapabilities: [],
            maxSteps: 4,
            stopCondition: .finalAnswerProvided,
            toolCallPolicy: nil
        )

        let refs = (0..<6).map { SkillReference(id: "skill-\($0)", pinVersion: nil) }
        agent.setBoundSkills(refs)

        XCTAssertEqual(agent.skills.count, 5)
    }
}
```

Add a small extension in production or tests:

```swift
extension AgentTool {
    mutating func setBoundSkills(_ refs: [SkillReference]) {
        skills = Array(refs.prefix(5))
    }
}
```

Prefer production if UI bindings need the same helper.

- [ ] **Step 2: Run tests to verify red**

Run:

```bash
swift test --package-path SliceAIKit --filter ToolEditorSkillsBindingTests
```

Expected: FAIL with missing helper or `skills` initializer issues.

- [ ] **Step 3: Pass enabled skills into ToolEditorView**

Add property:

```swift
public let availableSkills: [Skill]
```

Update initializer and `ToolsSettingsPage.toolEditor(for:)`:

```swift
availableSkills: viewModel.availableSkillsForAgentTools
```

If `SettingsViewModel` cannot access registry directly, pass `[]` first and let Task 7 wire real data. The UI should still compile and hide the section when empty.

- [ ] **Step 4: Add bindings**

In `ToolEditorView+Bindings.swift`, add:

```swift
func isSkillBound(_ skill: Skill) -> Bool {
    guard case .agent(let agentTool) = tool.kind else { return false }
    return agentTool.skills.contains { $0.id == skill.id }
}

func setSkill(_ skill: Skill, bound: Bool) {
    guard case .agent(var agentTool) = tool.kind else { return }
    var refs = agentTool.skills
    if bound {
        guard refs.count < 5 else { return }
        guard !refs.contains(where: { $0.id == skill.id }) else { return }
        refs.append(SkillReference(id: skill.id, pinVersion: nil))
    } else {
        refs.removeAll { $0.id == skill.id }
    }
    agentTool.skills = refs
    tool.kind = .agent(agentTool)
    print("[ToolEditorView] agent skills updated for tool '\(tool.id)' count=\(refs.count)")
}
```

- [ ] **Step 5: Add Agent Skills section**

In `ToolEditorView+Sections.swift`, include `agentSkillsCard` after `agentPromptCard`.

```swift
var agentSkillsCard: some View {
    SectionCard("Skills") {
        if availableSkills.isEmpty {
            Text("没有可绑定的 enabled skills。")
                .font(SliceFont.caption)
                .foregroundColor(SliceColor.textTertiary)
        } else {
            ForEach(availableSkills) { skill in
                SettingsRow(skill.canonicalName) {
                    Toggle("", isOn: Binding(
                        get: { isSkillBound(skill) },
                        set: { setSkill(skill, bound: $0) }
                    ))
                    .labelsHidden()
                    .disabled(!isSkillBound(skill) && boundSkillCount >= 5)
                }
            }
        }
    }
}
```

Add `boundSkillCount` computed property.

- [ ] **Step 6: Run Settings tests**

Run:

```bash
swift test --package-path SliceAIKit --filter SettingsUITests
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/SettingsUI SliceAIKit/Tests/SettingsUITests
git commit -m "feat(settings): bind skills to agent tools"
```

---

## Task 7: AppContainer Wiring and Runtime Integration

**Files:**
- Modify: `SliceAIApp/AppContainer.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- Test: existing compile via `xcodebuild`

- [ ] **Step 1: Inspect current AppContainer wiring**

Run:

```bash
rg -n "MockSkillRegistry|AgentExecutor|ExecutionEngine|SettingsViewModel" SliceAIApp/AppContainer.swift
```

Expected: locations where mock registry and AgentExecutor are constructed.

- [ ] **Step 2: Wire LocalSkillRegistry**

In `AppContainer`, create a single registry:

```swift
let skillRegistry = LocalSkillRegistry(settingsProvider: { [configurationStore] in
    do {
        return try await configurationStore.current().skillSettings
    } catch {
        print("[AppContainer] skill settings load failed – \(error.localizedDescription)")
        return .empty
    }
})
```

Inject the same `skillRegistry` into:

- `ExecutionEngine`
- `AgentExecutor`
- Settings scene construction if SkillsPage needs direct registry access

- [ ] **Step 3: Expose available skills to SettingsViewModel**

Add optional registry to `SettingsViewModel`:

```swift
private let skillRegistry: (any SkillRegistryProtocol)?
@Published public private(set) var availableAgentSkills: [Skill] = []
```

Add method:

```swift
public func reloadSkills() async {
    guard let skillRegistry else {
        availableAgentSkills = []
        return
    }
    do {
        let snapshot = try await skillRegistry.snapshot()
        availableAgentSkills = snapshot.skills.filter { $0.state == .enabled }
        print("[SettingsViewModel] reloadSkills: loaded \(availableAgentSkills.count) enabled skills")
    } catch {
        availableAgentSkills = []
        print("[SettingsViewModel] reloadSkills failed – \(error.localizedDescription)")
    }
}
```

Call `reloadSkills()` from `reload()` after configuration loads.

- [ ] **Step 4: Compile app**

Run:

```bash
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
git add SliceAIApp/AppContainer.swift SliceAIKit/Sources/SettingsUI/SettingsViewModel.swift SliceAIKit/Sources/Orchestration/Engine SliceAIKit/Sources/Orchestration/Executors
git commit -m "feat(app): wire local skill registry"
```

---

## Task 8: Documentation, Fixtures, and Final Gate

**Files:**
- Modify: `README.md`
- Modify: `docs/v2-refactor-master-todolist.md`
- Modify: `docs/Task-detail/2026-05-20-phase-2-skill-registry-mvp-spec.md`
- Modify or create: `docs/Module/SkillRegistry.md`
- Test: full gate commands

- [ ] **Step 1: Create module documentation**

Create `docs/Module/SkillRegistry.md` with sections:

```markdown
# SkillRegistry 模块

## 模块职责

SkillRegistry 负责扫描用户配置的本地 skill roots，解析 Claude / Codex 风格 `SKILL.md`，生成可供 Settings 和 AgentExecutor 使用的 registry snapshot。

## MVP 边界

- 只读取 `SKILL.md`
- 不执行 scripts
- 不读取 references/assets
- 只支持 Agent Tool 绑定
- 通过 `sliceai.load_skill` 渐进式加载完整指令

## 目录扫描规则

记录 root、collection root、`.claude/skills`、`.agents/skills`、`.codex/skills` 和 `skills` 的一层扫描规则。

## 运行时流程

记录 Agent Tool 绑定 skills、metadata 注入、pseudo-tool 加载、ResultPanel lifecycle。

## 技术债务

记录 supporting files、完整 YAML、SwiftSkill 复评估、Codex duplicate name 语义和 `agents/openai.yaml`。
```

- [ ] **Step 2: Update project status docs**

Update:

- `README.md`: mention Skill Registry MVP implemented locally.
- `docs/v2-refactor-master-todolist.md`: mark Skill Registry MVP implementation completed and next step review/release gate.
- Task detail: add changed files, tests, and final result.

- [ ] **Step 3: Run focused tests**

Run:

```bash
swift test --package-path SliceAIKit --filter 'SkillTests|ToolKindTests|ConfigurationTests|CapabilitiesTests|AgentExecutorTests|SettingsUITests'
```

Expected: PASS.

- [ ] **Step 4: Run full SwiftPM tests**

Run:

```bash
swift test --package-path SliceAIKit
```

Expected: PASS.

- [ ] **Step 5: Run lint and whitespace checks**

Run:

```bash
swiftlint lint --strict
git diff --check
```

Expected: `swiftlint` reports `0 violations`, `git diff --check` prints nothing.

- [ ] **Step 6: Build app**

Run:

```bash
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 7: Commit docs and final gate record**

```bash
git add README.md docs SliceAIKit/Tests
git commit -m "docs: document skill registry mvp"
```

- [ ] **Step 8: Stop before PR or merge**

Do not publish `v0.3.0`, do not retag, do not create a release, and do not merge without user instruction. Report:

- commit list,
- tests run,
- any skipped manual checks,
- residual technical debt from the spec.

---

## Plan Self-Review

### Spec coverage

- Multiple local roots: Task 2 scanner, Task 3 registry, Task 5 Settings page.
- Claude/Codex frontmatter compatibility: Task 2 parser.
- Enable/disable and shadowing: Task 3 registry, Task 5 Settings page.
- Agent-only binding: Task 1 schema, Task 6 Tool editor.
- `sliceai.load_skill` progressive loading: Task 4 AgentExecutor.
- ResultPanel lifecycle visibility: Task 4 uses existing `ExecutionEvent.toolCall*` events.
- Prompt Tool non-scope: Task 6 hides section for non-agent tools.
- No supporting files/scripts/marketplace/DisplayMode: preserved as docs in Task 8 and no code tasks introduce them.

### Type consistency

- `AgentTool.skills` is introduced in Task 1 before UI and AgentExecutor tasks use it.
- `SkillRegistryProtocol.snapshot/loadSkillInstructions` is introduced in Task 3 before AgentExecutor and Settings use it.
- `sliceai.load_skill` is named once via `AgentBuiltInTool.loadSkillName`.
- `SkillSettings` lives in SliceCore and is available to Configuration, SettingsUI, and Capabilities.

### Commands

Each task has a focused test command and a commit command. Final gate covers focused tests, full SwiftPM tests, SwiftLint strict, whitespace, and Xcode Debug build.
