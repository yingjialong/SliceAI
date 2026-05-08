# Phase 1 MCP Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build SliceAI v0.3 Phase 1: real MCP configuration/calls, five ContextProviders, permission UI gate, first Agent tool, ResultPanel tool-call visibility, per-tool hotkeys, remote MCP transport, five-server E2E, and release-ready docs.

**Architecture:** Keep the existing App thin-shell + `SliceAIKit` package boundary. `SliceCore` owns stable models only; `Capabilities` owns MCP transport, stores, context providers, and grant persistence; `Orchestration` owns PermissionGraph/Broker and AgentExecutor; `SliceAIApp` owns AppKit permission dialogs, runtime wiring, ResultPanel lifecycle, and hotkey registration.

**Tech Stack:** macOS 14+, Swift 6 strict concurrency, SwiftPM local package, AppKit + SwiftUI, Carbon hotkeys, URLSession, Foundation `Process`, JSON-RPC 2.0, MCP `stdio`, MCP `Streamable HTTP`, XCTest.

---

## Current Execution State

- This plan was synced into `feature/phase-1-mcp-context` on 2026-05-08 from the root planning workspace.
- M1 Tasks 1-5 and M2 Tasks 6-9 are already implemented, reviewed, and recorded in `docs/Task-detail/`.
- The next executable task is **M3 Task 10: LLM Tool Calling Contract**.
- The historical task checkboxes below preserve the original implementation plan snapshot. Use `docs/v2-refactor-master-todolist.md` and the task detail records as the source of truth for completed M1/M2 status.

## Preconditions

- Work from a fresh implementation worktree, not the root planning workspace.
- Do not implement before this plan receives a plan review result of `APPROVED` or `COMMENT`.
- All SwiftPM commands run from `SliceAIKit/`; app target commands run from repository root.
- Official MCP transport docs checked on 2026-05-06:
  - `https://modelcontextprotocol.io/specification/draft/basic/transports`
  - `https://modelcontextprotocol.io/specification/2025-06-18/basic/transports`
- The official transport contract defines standard `stdio` and `Streamable HTTP`; `Streamable HTTP` replaces old `HTTP+SSE`. Phase 1 does not implement old `HTTP+SSE`.

## Scope Boundary

This is one total Phase 1 plan because the accepted design intentionally ships a coherent v0.3 DoD. The plan is split into four independently reviewable milestones:

- **M1:** MCP data contract, server store, Claude Desktop import, stdio client, MCP Settings page.
- **M2:** PermissionGraph coverage semantics, five ContextProviders, persistent/session grants, AppKit UI gate.
- **M3:** AgentExecutor, OpenAI-compatible tool calling, ResultPanel tool call state, `web-search-summarize`.
- **M4:** Streamable HTTP, per-tool hotkeys, five-server E2E, release docs.

Out of scope:

- Skill runtime.
- Pipeline execution.
- Marketplace/signing/notarization.
- Shell capability.
- Replacing Prompt Tool behavior beyond contract migrations required for MCP JSON arguments.

## File Structure Map

### SliceCore

- Modify: `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
  - Add `.streamableHTTP`.
  - Keep `.sse` decodable as a deprecated unsupported legacy value; Settings and routing reject it.
  - Preserve decode compatibility for `.websocket`, but validation rejects new websocket configs.
- Create: `SliceAIKit/Sources/SliceCore/MCPJSONValue.swift`
  - Foundation-only recursive JSON value.
  - Codable, Equatable, Sendable.
  - Helpers for rendering string leaves and redacted summaries.
- Create: `SliceAIKit/Sources/SliceCore/MCPContentItem.swift`
  - MCP result content items: text, image, resourceLink, embeddedResource.
  - Structured content and meta use `MCPJSONValue`.
- Create: `SliceAIKit/Sources/SliceCore/MCPToolDescriptor.swift`
  - MCP `tools/list` descriptor: ref, title, description, inputSchema.
  - `inputSchema` uses transparent `MCPJSONValue.Object`.
- Modify: `SliceAIKit/Sources/SliceCore/OutputBinding.swift`
  - Change `SideEffect.callMCP` params from `[String: String]` to `MCPJSONValue.Object`.
- Modify: `SliceAIKit/Sources/SliceCore/ToolKind.swift`
  - Change `PipelineStep.mcp` args from `[String: String]` to `MCPJSONValue.Object`.
  - Keep PipelineExecutor unimplemented in Phase 1.
- Modify: `SliceAIKit/Sources/SliceCore/Permission.swift`
  - Keep data model; no broadening of shell permissions.
- Modify: `SliceAIKit/Sources/SliceCore/ConfigurationComponents.swift`
  - Add `toolHotkeys: [String: String]` or extend existing `HotkeyBindings` with per-tool mapping.
- Modify: `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
  - Add the first Agent tool `web-search-summarize`.

### Capabilities

- Modify: `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
  - Delete duplicate simplified `MCPDescriptor`.
  - Use `SliceCore.MCPDescriptor`.
  - Change call args/result to `MCPJSONValue.Object` and `MCPCallResult`.
- Modify: `SliceAIKit/Sources/Capabilities/MCP/MockMCPClient.swift`
  - Track call count and last arguments for tests.
- Create: `SliceAIKit/Sources/Capabilities/MCP/MCPServerStore.swift`
  - Load/save `~/Library/Application Support/SliceAI/mcp.json`.
  - Validate provenance and transport.
- Create: `SliceAIKit/Sources/Capabilities/MCP/ClaudeDesktopMCPImporter.swift`
  - Import `mcpServers` dictionaries.
- Create: `SliceAIKit/Sources/Capabilities/MCP/MCPJSONRPC.swift`
  - JSON-RPC request/response/error framing.
- Create: `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift`
  - Lazy process start, initialize, tools/list, tools/call, idle timeout.
- Create: `SliceAIKit/Sources/Capabilities/MCP/RoutingMCPClient.swift`
  - Single `MCPClientProtocol` facade used by AgentExecutor.
  - Routes by `MCPDescriptor.transport`.
- Create: `SliceAIKit/Sources/Capabilities/MCP/StreamableHTTPMCPClient.swift`
  - M4 remote transport.
- Create: `SliceAIKit/Sources/Capabilities/MCP/MCPDiagnosticLog.swift`
  - Redacted stderr/transport diagnostics.
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/SelectionContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/AppWindowTitleContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/AppURLContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/ClipboardCurrentContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/FileReadContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/Permissions/PersistentPermissionGrantStore.swift`
  - JSON store for persistent grants; session grants remain memory-only.

### Orchestration

- Modify: `SliceAIKit/Sources/Orchestration/Permissions/EffectivePermissions.swift`
  - Replace raw `Set.subtracting` undeclared calculation with case-aware coverage.
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionGraph.swift`
  - Use coverage semantics and real provider inferred permissions.
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBrokerProtocol.swift`
  - Add UI-gate request types if needed without importing AppKit.
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift`
  - Keep MCP non-cacheable.
  - Use persistent/session stores only for cacheable tiers.
- Create: `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
  - ReAct loop, allowlist check, every-time MCP approval, maxSteps, timeout.
- Create: `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`
  - Build context-aware agent messages.
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
  - Route `.agent` to `AgentExecutor`.
- Modify: `SliceAIKit/Sources/Orchestration/Events/ExecutionEvent.swift`
  - Add exact tool lifecycle events: proposed with id, denied, error.

### LLMProviders

- Modify: `SliceAIKit/Sources/SliceCore/ChatTypes.swift`
  - Add `ChatTool`, `ChatToolCall`, `ChatToolCallDelta`, `ChatToolRequest`, `ChatToolChoice`, `ChatStreamEvent`.
- Modify: `SliceAIKit/Sources/SliceCore/LLMProvider.swift`
  - Add tool-calling stream API while preserving prompt stream API behavior.
- Modify: `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift`
  - Encode `tools`, `tool_choice`, and decode streaming tool call deltas.
- Modify: `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift`
  - Support tool-calling request bodies and streaming tool-call chunks.

### SettingsUI

- Modify: `SliceAIKit/Package.swift`
  - Add `Capabilities` to the `SettingsUI` target dependencies.
  - Add `SettingsUITests` target for non-visual view-model logic.
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`
  - Add sidebar item for MCP Servers.
- Create: `SliceAIKit/Sources/SettingsUI/Pages/MCPServersPage.swift`
- Create: `SliceAIKit/Sources/SettingsUI/MCPServersViewModel.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`
  - Add agent/MCP allowlist editor and per-tool hotkey editor.
- Modify: `SliceAIKit/Sources/SettingsUI/HotkeyEditorView.swift`
  - Reuse for per-tool hotkeys.

### Windowing / SliceAIApp

- Modify: `SliceAIKit/Sources/Windowing/ResultContentView.swift`
  - Render tool call lifecycle rows.
- Modify: `SliceAIKit/Sources/Windowing/ResultPanel.swift`
  - Expose methods for tool call status updates.
- Modify: `SliceAIApp/ExecutionEventConsumer.swift`
  - Translate tool-call events into ResultPanel states.
- Modify: `SliceAIApp/AppContainer.swift`
  - Wire real MCP store/client, real ContextProviders, permission UI adapter.
- Modify: `SliceAIApp/AppDelegate.swift`
  - Register multiple hotkeys and route per-tool hotkeys to `execute(tool:payload:triggerSource:)`.
- Create: `SliceAIApp/AppPermissionConsentPresenter.swift`
  - AppKit alert/sheet bridge for PermissionBroker.
- Create: `SliceAIApp/AppContextAdapters.swift`
  - MainActor adapters for front app title/url and pasteboard when needed.

### Docs

- Create: `docs/Module/MCPClient.md`
- Create: `docs/Module/ContextProviders.md`
- Modify: `README.md`
- Modify: `docs/Task_history.md`
- Modify: `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
- Modify: `docs/v2-refactor-master-todolist.md`

---

## M1: MCP Configuration And Stdio Mainline

### Task 1: SliceCore MCP JSON Contract

**Files:**
- Create: `SliceAIKit/Sources/SliceCore/MCPJSONValue.swift`
- Create: `SliceAIKit/Sources/SliceCore/MCPContentItem.swift`
- Create: `SliceAIKit/Sources/SliceCore/MCPToolDescriptor.swift`
- Modify: `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
- Modify: `SliceAIKit/Sources/SliceCore/OutputBinding.swift`
- Modify: `SliceAIKit/Sources/SliceCore/ToolKind.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/MCPJSONValueTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/MCPContentItemTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/MCPDescriptorTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/OutputBindingTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ToolKindTests.swift`

- [ ] **Step 1: Write failing tests for JSON values and content items**

Add tests with these names:

```swift
func test_mcpJSONValue_roundTrips_nestedObject() throws
func test_mcpJSONValue_codableUsesTransparentRawJSONShape() throws
func test_mcpJSONValue_rendersStringLeavesWithoutChangingShape() throws
func test_mcpJSONValue_redactedSummary_redactsSecretKeys() throws
func test_mcpContentItem_roundTrips_textAndStructuredContent() throws
func test_mcpTransport_streamableHTTP_decodesAndEncodes() throws
func test_mcpTransport_websocket_decodesButIsNotCreatableInSettings() throws
func test_sideEffectCallMCP_acceptsNestedJSONParams() throws
func test_pipelineStepMCP_acceptsNestedJSONArgs() throws
```

Use this concrete assertion pattern:

```swift
let value: MCPJSONValue = .object([
    "query": .string("{{selection}}"),
    "limit": .number(3),
    "filters": .object(["safe": .bool(true)])
])
let rendered = value.renderingStringLeaves(variables: ["selection": "Swift MCP"])
XCTAssertEqual(rendered, .object([
    "query": .string("Swift MCP"),
    "limit": .number(3),
    "filters": .object(["safe": .bool(true)])
]))

let raw = Data(#"{"q":"hi","n":3,"nested":{"ok":true},"items":[null,"x"]}"#.utf8)
XCTAssertEqual(
    try JSONDecoder().decode(MCPJSONValue.self, from: raw),
    .object([
        "q": .string("hi"),
        "n": .number(3),
        "nested": .object(["ok": .bool(true)]),
        "items": .array([.null, .string("x")])
    ])
)
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter SliceCoreTests.MCPJSONValueTests
swift test --filter SliceCoreTests.MCPContentItemTests
swift test --filter SliceCoreTests.MCPDescriptorTests
```

Expected: tests fail with missing types or missing `.streamableHTTP`.

- [ ] **Step 3: Add SliceCore types**

Create `MCPJSONValue` with this public shape:

```swift
public enum MCPJSONValue: Sendable, Equatable, Codable {
    public typealias Object = [String: MCPJSONValue]

    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([MCPJSONValue])
    case object(Object)

    public func renderingStringLeaves(variables: [String: String]) -> MCPJSONValue
    public func redactedSummary(maxCharacters: Int) -> String
}
```

`MCPJSONValue` must not use synthesized enum `Codable`. It must use transparent raw JSON shape:

- encode `.null` as JSON `null`;
- encode `.bool`, `.number`, `.string` as their primitive JSON values;
- encode `.array` as a JSON array of transparent values;
- encode `.object` as a JSON object of transparent values;
- decode with `singleValueContainer()` and preserve the same raw JSON shape on re-encode.

The decoder order is:

```swift
if container.decodeNil() { self = .null; return }
if let value = try? container.decode(Bool.self) { self = .bool(value); return }
if let value = try? container.decode(Double.self) { self = .number(value); return }
if let value = try? container.decode(String.self) { self = .string(value); return }
if let value = try? container.decode([MCPJSONValue].self) { self = .array(value); return }
if let value = try? container.decode([String: MCPJSONValue].self) { self = .object(value); return }
throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unsupported JSON value")
```

`SideEffect.callMCP.params` and `PipelineStep.mcp.args` must decode and encode this same transparent JSON object shape. They must not emit Swift enum wrapper keys such as `{"string":"hi"}` or `{"object":{"q":{"string":"hi"}}}`.

Create `MCPContentItem` with this public shape:

```swift
public enum MCPContentItem: Sendable, Equatable, Codable {
    case text(String)
    case image(data: String, mimeType: String)
    case resourceLink(uri: String, name: String?, mimeType: String?)
    case embeddedResource(uri: String, text: String?, blob: String?, mimeType: String?)
}

public struct MCPCallResult: Sendable, Equatable, Codable {
    public let content: [MCPContentItem]
    public let structuredContent: MCPJSONValue?
    public let isError: Bool
    public let meta: MCPJSONValue.Object?
}
```

Keep `MCPCallResult` in `SliceCore`, not `Capabilities`.

Create `MCPToolDescriptor` in `SliceCore`:

```swift
public struct MCPToolDescriptor: Sendable, Equatable, Codable {
    public let ref: MCPToolRef
    public let title: String
    public let description: String?
    public let inputSchema: MCPJSONValue.Object
}
```

`inputSchema` is populated from MCP `tools/list` and is the only source AgentExecutor may use when building `ChatTool.inputSchema`.

- [ ] **Step 4: Update existing contracts**

Change these associated values:

```swift
case callMCP(ref: MCPToolRef, params: MCPJSONValue.Object)
case mcp(ref: MCPToolRef, args: MCPJSONValue.Object)
```

Change `MCPTransport`:

```swift
public enum MCPTransport: String, Sendable, Codable, CaseIterable {
    case stdio
    case streamableHTTP = "streamable-http"
    case sse
    case websocket
}
```

Add a helper used by store validation:

```swift
public var isCreatableInPhase1Settings: Bool {
    switch self {
    case .stdio, .streamableHTTP:
        return true
    case .sse, .websocket:
        return false
    }
}
```

- [ ] **Step 5: Run focused tests**

Run:

```bash
cd SliceAIKit
swift test --filter SliceCoreTests.MCPJSONValueTests
swift test --filter SliceCoreTests.MCPContentItemTests
swift test --filter SliceCoreTests.MCPDescriptorTests
swift test --filter SliceCoreTests.OutputBindingTests
swift test --filter SliceCoreTests.ToolKindTests
```

Expected: all listed tests pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore SliceAIKit/Tests/SliceCoreTests
git commit -m "feat(core): add structured mcp json contract"
```

### Task 2: MCP Client Protocol Uses Canonical Descriptor

**Files:**
- Modify: `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- Modify: `SliceAIKit/Sources/Capabilities/MCP/MockMCPClient.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/MCPClientProtocolTests.swift`

- [ ] **Step 1: Write failing protocol tests**

Add tests:

```swift
func test_mockMCPClient_usesSliceCoreDescriptor() async throws
func test_mockMCPClient_recordsStructuredArguments() async throws
func test_mcpClientError_developerContext_redactsToolRefs() throws
```

Core assertion:

```swift
let descriptor = MCPDescriptor(
    id: "brave",
    transport: .stdio,
    command: "npx",
    args: ["-y", "@modelcontextprotocol/server-brave-search"],
    url: nil,
    env: nil,
    capabilities: [.tools(["brave_web_search"])],
    provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))
)
let ref = MCPToolRef(server: "brave", tool: "brave_web_search")
let descriptorForTool = MCPToolDescriptor(
    ref: ref,
    title: "Brave Web Search",
    description: "Search the web",
    inputSchema: ["type": .string("object")]
)
let result = MCPCallResult(content: [.text("ok")], structuredContent: nil, isError: false, meta: nil)
let client = MockMCPClient(tools: [descriptor: [descriptorForTool]], responses: [ref: result])
_ = try await client.call(ref: ref, args: ["q": .string("SliceAI")])
XCTAssertEqual(await client.callCount, 1)
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.MCPClientProtocolTests
```

Expected: compile fails because `call(ref:args:)` still takes `[String: String]` or duplicate descriptor conflicts.

- [ ] **Step 3: Update protocol**

`MCPClientProtocol` must expose:

```swift
public protocol MCPClientProtocol: Sendable {
    func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolDescriptor]
    func call(ref: MCPToolRef, args: MCPJSONValue.Object) async throws -> MCPCallResult
}
```

Remove the duplicate `public struct MCPDescriptor` from `Capabilities/MCP/MCPClientProtocol.swift`.
Do not add a parallel schema cache in `AgentExecutor`; all tool names, descriptions, and input schemas must come through `MCPClientProtocol.tools(for:)`.

- [ ] **Step 4: Update mock**

`MockMCPClient` tracks:

```swift
public private(set) var callCount = 0
public private(set) var lastArguments: MCPJSONValue.Object?
public private(set) var lastToolsDescriptor: MCPDescriptor?
```

The mock must throw `.toolNotFound(ref:)` when no response exists for `ref`.

- [ ] **Step 5: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.MCPClientProtocolTests
swift test --filter OrchestrationTests
```

Expected: all Capabilities tests pass; Orchestration tests compile after call-site updates.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Capabilities/MCP SliceAIKit/Tests/CapabilitiesTests SliceAIKit/Tests/OrchestrationTests
git commit -m "feat(capabilities): use canonical mcp protocol contract"
```

### Task 3: MCP Server Store And Claude Desktop Import

**Files:**
- Create: `SliceAIKit/Sources/Capabilities/MCP/MCPServerStore.swift`
- Create: `SliceAIKit/Sources/Capabilities/MCP/ClaudeDesktopMCPImporter.swift`
- Create: `SliceAIKit/Sources/Capabilities/MCP/MCPServerValidation.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/MCPServerStoreTests.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/ClaudeDesktopMCPImporterTests.swift`

- [ ] **Step 1: Write failing store/import tests**

Add tests:

```swift
func test_store_roundTrips_mcpJSON() async throws
func test_store_rejectsUnknownProvenance() async throws
func test_store_rejectsRelativeCommandPath() async throws
func test_importer_acceptsClaudeDesktopStdioConfig() throws
func test_importer_rejectsRemoteURLBeforeM4() throws
func test_runnerConfirmationRequiredForNpxUvxNodePython() throws
```

Concrete import fixture:

```swift
let data = Data(#"""
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": ["-y", "@modelcontextprotocol/server-filesystem", "/Users/me/Documents"]
    }
  }
}
"""#.utf8)
let descriptors = try ClaudeDesktopMCPImporter().importDescriptors(
    from: data,
    provenance: .selfManaged(userAcknowledgedAt: Date(timeIntervalSince1970: 1))
)
XCTAssertEqual(descriptors.first?.id, "filesystem")
XCTAssertEqual(descriptors.first?.transport, .stdio)
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.MCPServerStoreTests
swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests
```

Expected: missing store/importer types.

- [ ] **Step 3: Implement store models**

Use this store schema:

```swift
public struct MCPServerConfiguration: Sendable, Codable, Equatable {
    public var schemaVersion: Int
    public var servers: [MCPDescriptor]
    public var runnerConfirmations: [RunnerConfirmation]
}

public struct RunnerConfirmation: Sendable, Codable, Equatable {
    public let command: String
    public let confirmedAt: Date
    public let confirmationText: String
}
```

Store path defaults to:

```swift
~/Library/Application Support/SliceAI/mcp.json
```

`MCPServerStore` must expose a read snapshot for runtime wiring:

```swift
public actor MCPServerStore {
    public func snapshot() async throws -> [MCPDescriptor]
}
```

`snapshot()` returns validated descriptors sorted by `id` for deterministic AgentExecutor tests.

- [ ] **Step 4: Implement validation**

Validation rules:

- `provenance == .unknown` fails.
- `.stdio` requires non-empty `command`.
- `.stdio` rejects commands containing `/../` after standardization.
- `.stdio` accepts absolute command paths or allowlisted runners: `npx`, `uvx`, `node`, `python`, `python3`.
- `.streamableHTTP` save only in M4; `.sse` remains deprecated and unsupported.
- `.websocket` always rejects new Settings/store writes.

- [ ] **Step 5: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.MCPServerStoreTests
swift test --filter CapabilitiesTests.ClaudeDesktopMCPImporterTests
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Capabilities/MCP SliceAIKit/Tests/CapabilitiesTests
git commit -m "feat(capabilities): add mcp server store"
```

### Task 4: Stdio MCP JSON-RPC Client

**Files:**
- Create: `SliceAIKit/Sources/Capabilities/MCP/MCPJSONRPC.swift`
- Create: `SliceAIKit/Sources/Capabilities/MCP/StdioMCPClient.swift`
- Create: `SliceAIKit/Sources/Capabilities/MCP/RoutingMCPClient.swift`
- Create: `SliceAIKit/Sources/Capabilities/MCP/MCPDiagnosticLog.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/MCPJSONRPCTests.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/StdioMCPClientTests.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/RoutingMCPClientTests.swift`
- Test fixture: `SliceAIKit/Tests/CapabilitiesTests/Fixtures/stdio-mcp-fixture.js`
- Modify: `SliceAIKit/Package.swift` if test resources are added.

- [ ] **Step 1: Write failing JSON-RPC tests**

Add tests:

```swift
func test_jsonRPCRequest_encodesInitialize() throws
func test_jsonRPCResponse_decodesToolList() throws
func test_jsonRPCError_isSeparatedFromToolExecutionError() throws
func test_stdioClient_listsToolsFromFixtureProcess() async throws
func test_stdioClient_callsToolWithStructuredArguments() async throws
func test_stdioClient_idleTimeoutStopsProcess() async throws
func test_stdioClient_redactsStderrDiagnostics() async throws
func test_routingClient_routesStdioDescriptorToStdioClient() async throws
func test_routingClient_rejectsUnsupportedRemoteTransportBeforeM4() async throws
```

- [ ] **Step 2: Add fixture script**

Create a deterministic Node fixture:

```javascript
#!/usr/bin/env node
const readline = require("readline");
const rl = readline.createInterface({ input: process.stdin });

function send(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

rl.on("line", (line) => {
  const msg = JSON.parse(line);
  if (msg.method === "initialize") {
    send(msg.id, { protocolVersion: "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "fixture", version: "1.0.0" } });
  } else if (msg.method === "tools/list") {
    send(msg.id, { tools: [{ name: "echo", description: "Echo query", inputSchema: { type: "object" } }] });
  } else if (msg.method === "tools/call") {
    send(msg.id, { content: [{ type: "text", text: msg.params.arguments.query }], isError: false });
  }
});
```

- [ ] **Step 3: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.MCPJSONRPCTests
swift test --filter CapabilitiesTests.StdioMCPClientTests
```

Expected: missing implementation types.

- [ ] **Step 4: Implement stdio client**

Required client behavior:

- Lazy start on first `tools(for:)` or `call(ref:args:)`.
- Send `initialize`, then `notifications/initialized`, then `tools/list`.
- Map every MCP `tools/list` item to `MCPToolDescriptor(ref:title:description:inputSchema:)`.
- Preserve `inputSchema` as transparent `MCPJSONValue.Object`; do not collapse it to `[String: String]`.
- Use newline-delimited JSON-RPC for stdio.
- Use actor isolation for process state.
- Idle timeout default: 5 minutes; tests inject a shorter timeout.
- Redact stderr with existing `Redaction`-style patterns: bearer, `sk-`, `Authorization`, `Cookie`.

Public initializer:

```swift
public init(
    descriptors: @escaping @Sendable () async throws -> [MCPDescriptor],
    idleTimeoutNanoseconds: UInt64 = 300 * 1_000_000_000,
    diagnosticLog: MCPDiagnosticLog = .disabled
)
```

Add `RoutingMCPClient` as the only MCP client facade injected into `ExecutionEngine` / `AgentExecutor`:

```swift
public actor RoutingMCPClient: MCPClientProtocol {
    public init(
        descriptors: @escaping @Sendable () async throws -> [MCPDescriptor],
        stdio: any MCPClientProtocol,
        streamableHTTP: (any MCPClientProtocol)? = nil
    )
}
```

Routing rules:

- resolve `MCPToolRef.server` to `MCPDescriptor.id` from `descriptors()`;
- delegate `.stdio` to `stdio`;
- before M4, return `.unsupportedTransport(.streamableHTTP)` for remote descriptors;
- `.sse` and `.websocket` always return unsupported transport; legacy HTTP+SSE is deprecated and not implemented;
- `AgentExecutor` never switches on `MCPTransport` directly.

- [ ] **Step 5: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.MCPJSONRPCTests
swift test --filter CapabilitiesTests.StdioMCPClientTests
swift test --filter CapabilitiesTests.RoutingMCPClientTests
swift test --filter CapabilitiesTests.MCPClientProtocolTests
```

Expected: all listed tests pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Capabilities/MCP SliceAIKit/Tests/CapabilitiesTests SliceAIKit/Package.swift
git commit -m "feat(capabilities): add stdio mcp client"
```

### Task 5: MCP Servers Settings Page

**Files:**
- Create: `SliceAIKit/Sources/SettingsUI/MCPServersViewModel.swift`
- Create: `SliceAIKit/Sources/SettingsUI/Pages/MCPServersPage.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/SettingsScene.swift`
- Modify: `SliceAIKit/Package.swift`
- Test: `SliceAIKit/Tests/SettingsUITests/MCPServersViewModelTests.swift`

- [ ] **Step 1: Add SettingsUI test target**

Add to `Package.swift`:

```swift
.target(
    name: "SettingsUI",
    dependencies: ["SliceCore", "LLMProviders", "HotkeyManager", "DesignSystem", "Permissions", "Capabilities"],
    swiftSettings: swiftSettings
)

.testTarget(
    name: "SettingsUITests",
    dependencies: ["SettingsUI", "SliceCore", "Capabilities"],
    swiftSettings: swiftSettings
)
```

Architectural choice: `MCPServersViewModel` lives in `SettingsUI` and imports `Capabilities` because it is non-visual settings orchestration over `MCPServerStore`, `ClaudeDesktopMCPImporter`, and `MCPClientProtocol`. Keep AppKit-specific runtime wiring in `SliceAIApp`.

- [ ] **Step 2: Write failing view model tests**

Add tests:

```swift
@MainActor
func test_importClaudeDesktopConfig_addsServerAndPersists() async throws

@MainActor
func test_unknownProvenanceShowsValidationError() async throws

@MainActor
func test_testConnectionCallsToolsList() async throws
```

The test should use a temp `MCPServerStore` file and a `MockMCPClient`.

- [ ] **Step 3: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter SettingsUITests.MCPServersViewModelTests
```

Expected: test target or view model missing.

- [ ] **Step 4: Implement view model**

Public API:

```swift
@MainActor
public final class MCPServersViewModel: ObservableObject {
    @Published public private(set) var servers: [MCPDescriptor]
    @Published public var validationMessage: String?

    public func reload() async
    public func importClaudeDesktopConfig(_ data: Data) async
    public func save(_ descriptor: MCPDescriptor) async
    public func delete(id: String) async
    public func testConnection(id: String) async
}
```

Every catch path prints a short Chinese debug log:

```swift
print("[MCPServersViewModel] testConnection: failed - \(error.localizedDescription)")
```

- [ ] **Step 5: Add page**

Settings page must provide:

- server list with enabled/name/transport/provenance;
- add/edit sheet for stdio fields;
- import Claude Desktop JSON button;
- test connection button;
- tool list preview after successful test.

- [ ] **Step 6: Run tests and build package**

Run:

```bash
cd SliceAIKit
swift test --filter SettingsUITests.MCPServersViewModelTests
swift build
```

Expected: tests pass and package builds.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Package.swift SliceAIKit/Sources/SettingsUI SliceAIKit/Tests/SettingsUITests
git commit -m "feat(settings): add mcp servers page"
```

---

## M2: Context And Permission Mainline

### Task 6: PermissionGraph Case-Aware Coverage

**Files:**
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/EffectivePermissions.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionGraph.swift`
- Modify: `SliceAIKit/Sources/Capabilities/SecurityKit/PathSandbox.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/PermissionGraphTests.swift`

- [ ] **Step 1: Write failing coverage tests**

Add tests:

```swift
func test_fileRead_declaredGlobCoversConcretePath() async throws
func test_fileRead_declaredDirectoryPrefixCoversConcretePath() async throws
func test_fileRead_declaredGlobDoesNotCoverSiblingEscape() async throws
func test_fileRead_pathSandboxHardDeniedDeclarationDoesNotCoverEffective() async throws
func test_mcp_declaredNilToolsCoversConcreteTool() async throws
func test_mcp_declaredToolSupersetCoversConcreteTool() async throws
func test_mcp_missingToolIsUndeclared() async throws
func test_shellExec_requiresExactCommandList() async throws
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.PermissionGraphTests
```

Expected: existing raw `Set.subtracting` reports false undeclared for positive coverage cases.

- [ ] **Step 3: Add coverage method**

Implement:

```swift
extension Permission {
    func covers(_ effective: Permission, fileNormalizer: FilePermissionNormalizing) -> Bool
}
```

Coverage rules:

- same scalar cases compare exactly;
- `.fileRead` covers `.fileRead` with exact path, directory prefix, or `*`/`**` glob only after `~` expansion, symlink resolution, and `..` standardization;
- `.fileRead` coverage returns `false` if either declared or effective path is `PathSandbox` hard-denied, even when the declared and effective strings are identical;
- `.fileWrite` mirrors `.fileRead`;
- `.mcp` requires same server and declared tools nil or declared tool set superset;
- `.shellExec` exact command array only.

Add the smallest `PathSandbox` helper needed by coverage:

```swift
public func isHardDenied(_ raw: String) -> Bool
```

Use it before exact, prefix, or glob matching. A hard-denied effective path must appear in `EffectivePermissions.undeclared`, which stops execution before any file IO.

- [ ] **Step 4: Replace undeclared computation**

`EffectivePermissions.undeclared` must return effective permissions that have no declared cover:

```swift
public var undeclared: Set<Permission> {
    union.filter { effective in
        !declared.contains { declared in declared.covers(effective, fileNormalizer: .default) }
    }
}
```

Adjust exact implementation to respect actor/test injection if the normalizer needs dependencies.

- [ ] **Step 5: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.PermissionGraphTests
swift test --filter OrchestrationTests.ExecutionEngineTests
swift test --filter CapabilitiesTests.PathSandboxTests
```

Expected: all listed tests pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Orchestration/Permissions SliceAIKit/Tests/OrchestrationTests
git commit -m "fix(orchestration): use permission coverage semantics"
```

### Task 7: Five ContextProviders

**Files:**
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/SelectionContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/AppWindowTitleContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/AppURLContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/ClipboardCurrentContextProvider.swift`
- Create: `SliceAIKit/Sources/Capabilities/ContextProviders/FileReadContextProvider.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/ContextProviderTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/ContextCollectorTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/PermissionGraphTests.swift`

- [ ] **Step 1: Write failing provider tests**

Add tests:

```swift
func test_selectionProvider_returnsSeedSelection() async throws
func test_windowTitleProvider_returnsFrontAppTitle() async throws
func test_appURLProvider_returnsFrontAppURL() async throws
func test_clipboardProvider_returnsInjectedPasteboardText() async throws
func test_fileReadProvider_readsWhitelistedFile() async throws
func test_fileReadProvider_rejectsHardDeniedPath() async throws
func test_contextProviders_inferPermissions() throws
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.ContextProviderTests
```

Expected: missing provider types.

- [ ] **Step 3: Implement providers**

Provider names:

```swift
"selection"
"app.windowTitle"
"app.url"
"clipboard.current"
"file.read"
```

Permission inference:

```swift
SelectionContextProvider.inferredPermissions(for: [:]) == []
AppWindowTitleContextProvider.inferredPermissions(for: [:]) == []
AppURLContextProvider.inferredPermissions(for: [:]) == []
ClipboardCurrentContextProvider.inferredPermissions(for: [:]) == [.clipboard]
FileReadContextProvider.inferredPermissions(for: ["path": "~/Docs/a.md"]) == [.fileRead(path: "~/Docs/a.md")]
```

`FileReadContextProvider.resolve` must normalize through `PathSandbox` before reading.

- [ ] **Step 4: Add cancellation checks**

Each provider that touches IO must call:

```swift
try Task.checkCancellation()
```

before and after the IO boundary.

- [ ] **Step 5: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.ContextProviderTests
swift test --filter OrchestrationTests.ContextCollectorTests
swift test --filter OrchestrationTests.PermissionGraphTests
```

Expected: all listed tests pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Capabilities/ContextProviders SliceAIKit/Tests/CapabilitiesTests SliceAIKit/Tests/OrchestrationTests
git commit -m "feat(capabilities): add core context providers"
```

### Task 8: Permission Grant Persistence And UI-Gate Protocol

**Files:**
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBrokerProtocol.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionBroker.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Permissions/PermissionGrantStore.swift`
- Create: `SliceAIKit/Sources/Capabilities/Permissions/PersistentPermissionGrantStore.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/PermissionBrokerTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/PermissionGrantStoreTests.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/PersistentPermissionGrantStoreTests.swift`

- [ ] **Step 1: Write failing grant tests**

Add tests:

```swift
func test_persistentGrant_roundTripsToDisk() async throws
func test_sessionGrant_doesNotPersistAcrossStoreInstances() async throws
func test_mcpPermission_isNeverCached() async throws
func test_networkWrite_isNeverCached() async throws
func test_dryRun_networkWriteReturnsWouldRequireConsent() async throws
func test_readonlyLocal_unknownRequiresConsent() async throws
func test_permissionBroker_callsConsentHandlerForFirstTimeLocalWrite() async throws
func test_permissionBroker_approvalRecordsSessionGrantForCacheableTier() async throws
func test_persistentStore_rejectsMCPPermission() async throws
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.PermissionBrokerTests
swift test --filter CapabilitiesTests.PersistentPermissionGrantStoreTests
```

Expected: persistent store and consent handler missing.

- [ ] **Step 3: Add UI-free consent protocol**

Keep AppKit outside Orchestration:

```swift
public struct PermissionConsentRequest: Sendable, Equatable {
    public let permission: Permission
    public let provenance: Provenance
    public let uxHint: ConsentUXHint
    public let allowedScopes: [GrantScope]
}

public enum PermissionConsentDecision: Sendable, Equatable {
    case approve(scope: GrantScope)
    case deny(reason: String)
}

public protocol PermissionConsentPresenting: Sendable {
    func requestConsent(_ request: PermissionConsentRequest) async -> PermissionConsentDecision
}
```

Choose this integration model for Phase 1: `PermissionBroker` owns the UI-free consent boundary. `ExecutionEngine` and `AgentExecutor` call `PermissionBroker.gate(effective:provenance:scope:isDryRun:)`; they do not import AppKit and do not call `PermissionConsentPresenting` directly.

Update broker construction to require an injected presenter:

```swift
public init(
    store: PermissionGrantStore = .init(),
    persistentStore: PersistentPermissionGrantStore? = nil,
    consentPresenter: any PermissionConsentPresenting
)
```

Test code uses `MockPermissionConsentPresenter`. App runtime injects `AppPermissionConsentPresenter` from `SliceAIApp`. Broker behavior:

- cache hit for cacheable tiers returns `.approved`;
- dry-run never calls the presenter;
- if consent is needed and `isDryRun == false`, broker calls `consentPresenter.requestConsent(_:)`;
- `.approve(scope: .oneTime)` returns `.approved` without writing a grant;
- `.approve(scope: .session)` records only cacheable permissions in `PermissionGrantStore` and returns `.approved`;
- `.approve(scope: .persistent)` is rejected by runtime presenter policy; persistent grants are Settings-only;
- `.deny(reason:)` returns `.denied(permission:reason:)`.

`GateOutcome.requiresUserConsent` remains in the protocol only for test doubles and compatibility with M2-era mocks; production `PermissionBroker` with a presenter must resolve non-dry-run consent into `.approved` or `.denied`.

- [ ] **Step 4: Implement persistence**

Persistent file path:

```text
~/Library/Application Support/SliceAI/permission-grants.json
```

Only `scope == .persistent` is written to disk. `scope == .session` stays in memory. `scope == .oneTime` is not cached.

`PersistentPermissionGrantStore.record(permission:provenance:scope:)` must reject non-cacheable tiers at the storage boundary:

```swift
case .mcp, .network, .shellExec, .appIntents:
    throw PermissionGrantStoreError.nonCacheablePermission(permission)
```

Do not rely only on broker call-site checks. Settings UI and future import paths must be unable to persist non-cacheable grants directly.

- [ ] **Step 5: Preserve MCP every-time confirmation**

Broker rule:

```swift
let hint = Self.uxHint(tier: tier, provenance: provenance)

if tier == .networkWrite || tier == .exec {
    if isDryRun {
        return .wouldRequireConsent(permission: permission, uxHint: hint)
    }

    let request = PermissionConsentRequest(
        permission: permission,
        provenance: provenance,
        uxHint: hint,
        allowedScopes: [.oneTime]
    )
    let decision = await consentPresenter.requestConsent(request)
    switch decision {
    case .approve:
        return .approved
    case .deny(let reason):
        return .denied(permission: permission, reason: reason)
    }
}
```

Never read or write grants for `.mcp`, `.network`, `.shellExec`, or `.appIntents`. Runtime approval of these permissions is one invocation only, even if a mock presenter returns `.approve(scope: .session)`.

- [ ] **Step 6: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.PermissionBrokerTests
swift test --filter OrchestrationTests.PermissionGrantStoreTests
swift test --filter CapabilitiesTests.PersistentPermissionGrantStoreTests
```

Expected: all listed tests pass.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/Orchestration/Permissions SliceAIKit/Sources/Capabilities/Permissions SliceAIKit/Tests
git commit -m "feat(orchestration): add permission consent grants"
```

### Task 9: AppContainer Wires Real Context And Permission UI

**Files:**
- Modify: `SliceAIApp/AppContainer.swift`
- Create: `SliceAIApp/AppPermissionConsentPresenter.swift`
- Create: `SliceAIApp/AppContextAdapters.swift`
- Modify: `SliceAIApp/ExecutionEventConsumer.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`

- [ ] **Step 1: Write failing wiring tests**

In Orchestration tests, add:

```swift
func test_executionFailsBeforeFileReadWhenPermissionUndeclared() async throws
func test_permissionDeniedYieldsFailedEventWithoutCrash() async throws
func test_permissionApprovedContinuesToPromptExecution() async throws
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.ExecutionEngineTests
```

Expected: permission UI adapter behavior not wired in tests.

- [ ] **Step 3: Add AppKit presenter**

`AppPermissionConsentPresenter` is `@MainActor` and uses `NSAlert`. It must show:

- permission case name;
- provenance summary;
- operation risk copy;
- buttons: approve once, approve for session, deny.

It must never offer persistent approval. Persistent grants are Settings-only.

- [ ] **Step 4: Wire permission presenter and providers in AppContainer**

Create the presenter and inject it into the broker:

```swift
let permissionPresenter = AppPermissionConsentPresenter()
let permissionBroker: any PermissionBrokerProtocol = PermissionBroker(
    store: PermissionGrantStore(),
    persistentStore: PersistentPermissionGrantStore(
        fileURL: appSupport.appendingPathComponent("permission-grants.json")
    ),
    consentPresenter: permissionPresenter
)
```

The presenter is the only AppKit-aware object in this chain. `PermissionBroker`, `ExecutionEngine`, and `AgentExecutor` stay AppKit-free.

Create one MCP server store and pass its snapshot provider into the runtime:

```swift
let mcpServerStore = MCPServerStore(fileURL: appSupport.appendingPathComponent("mcp.json"))
let mcpDescriptors: @Sendable () async throws -> [MCPDescriptor] = {
    try await mcpServerStore.snapshot()
}
let stdioMCPClient = StdioMCPClient(descriptors: mcpDescriptors)
let mcpClient: any MCPClientProtocol = RoutingMCPClient(
    descriptors: mcpDescriptors,
    stdio: stdioMCPClient
)
```

`ExecutionEngine` must pass `mcpDescriptors` and `mcpClient` to `AgentExecutor` when routing `.agent`. Do not make `AgentExecutor` read app support paths directly. Before M4, remote transports fail through `RoutingMCPClient.unsupportedTransport`; M4 fills the remote delegates without changing AgentExecutor.

Replace:

```swift
let providerRegistry = ContextProviderRegistry(providers: [:])
```

with a registry containing:

```swift
let appContextAdapters = AppContextAdapters()
let providerRegistry = ContextProviderRegistry(providers: [
    "selection": SelectionContextProvider(),
    "app.windowTitle": AppWindowTitleContextProvider(),
    "app.url": AppURLContextProvider(),
    "clipboard.current": ClipboardCurrentContextProvider(reader: appContextAdapters),
    "file.read": FileReadContextProvider(pathSandbox: PathSandbox(), fileManager: FileManager.default)
])
```

- [ ] **Step 5: Run build and focused tests**

Run:

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.ExecutionEngineTests
cd ..
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected: tests pass and app target builds.

- [ ] **Step 6: Commit**

```bash
git add SliceAIApp SliceAIKit/Tests/OrchestrationTests
git commit -m "feat(app): wire context providers and permission ui"
```

---

## M3: AgentExecutor And Tool Call UI

### Task 10: LLM Tool Calling Contract

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/ChatTypes.swift`
- Modify: `SliceAIKit/Sources/SliceCore/LLMProvider.swift`
- Modify: `SliceAIKit/Sources/LLMProviders/OpenAIDTOs.swift`
- Modify: `SliceAIKit/Sources/LLMProviders/OpenAICompatibleProvider.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ChatTypesTests.swift`
- Test: `SliceAIKit/Tests/LLMProvidersTests/OpenAIDTOsTests.swift`
- Test: `SliceAIKit/Tests/LLMProvidersTests/OpenAICompatibleProviderTests.swift`
- Fixture: `SliceAIKit/Tests/LLMProvidersTests/Fixtures/openai_chat_tool_call.sse`

- [ ] **Step 1: Write failing tool-call tests**

Add tests:

```swift
func test_chatTool_encodesOpenAISchema() throws
func test_chatToolRequest_encodesToolsAndToolChoice() throws
func test_chatMessage_toolResultEncodesOpenAIToolCallID() throws
func test_chatStreamEvent_decodesTextAndToolCallDeltas() throws
func test_openAIProvider_sendsToolsAndToolChoice() async throws
func test_openAIProvider_streamsToolCallArguments() async throws
```

- [ ] **Step 2: Add SSE fixture**

Fixture lines:

```text
data: {"choices":[{"delta":{"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"brave_web_search","arguments":"{\"q\""}}]},"finish_reason":null}]}

data: {"choices":[{"delta":{"tool_calls":[{"index":0,"function":{"arguments":":\"SliceAI\"}"}}]},"finish_reason":"tool_calls"}]}

data: [DONE]
```

- [ ] **Step 3: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter SliceCoreTests.ChatTypesTests
swift test --filter LLMProvidersTests.OpenAIDTOsTests
swift test --filter LLMProvidersTests.OpenAICompatibleProviderTests
```

Expected: missing tool call types.

- [ ] **Step 4: Add tool stream types**

Public shapes:

```swift
public struct ChatTool: Sendable, Codable, Equatable {
    public let name: String
    public let description: String
    public let inputSchema: MCPJSONValue.Object
}

public enum ChatToolChoice: Sendable, Codable, Equatable {
    case auto
    case none
    case required
}

public struct ChatToolRequest: Sendable, Codable, Equatable {
    public let model: String
    public let messages: [ChatMessage]
    public let tools: [ChatTool]
    public let toolChoice: ChatToolChoice?
    public let temperature: Double?
    public let maxTokens: Int?
}

public enum ChatStreamEvent: Sendable, Equatable {
    case textDelta(String)
    case toolCallDelta(ChatToolCallDelta)
    case finished(FinishReason)
}

public struct ChatToolCall: Sendable, Codable, Equatable {
    public let id: String
    public let name: String
    public let argumentsRaw: String
    public let arguments: MCPJSONValue.Object?
}

public struct ChatToolCallDelta: Sendable, Equatable {
    public let index: Int
    public let id: String?
    public let name: String?
    public let argumentsDelta: String
}
```

Extend `Role` and `ChatMessage` for tool-result feedback:

```swift
public enum Role: String, Sendable, Codable {
    case system, user, assistant, tool
}

public struct ChatMessage: Sendable, Codable, Equatable {
    public let role: Role
    public let content: String?
    public let toolCallID: String?
    public let toolCalls: [ChatToolCall]?
}
```

Encoding rules:

- normal system/user/assistant text messages encode `role` + `content`;
- assistant tool-call messages encode `role: "assistant"` + `tool_calls`; `function.arguments` is encoded from `argumentsRaw`;
- `arguments` is the parsed object used by AgentExecutor for MCP calls; it is nil when the model emitted malformed JSON;
- tool-result, denial, and error feedback encode `role: "tool"`, `tool_call_id`, and text `content`;
- `tool_call_id` is the provider string id from `ChatToolCall.id`, not the UI `UUID`.

Add the provider API:

```swift
public protocol LLMProvider: Sendable {
    func stream(request: ChatRequest) async throws -> AsyncThrowingStream<ChatChunk, any Error>
    func streamToolChat(request: ChatToolRequest) async throws -> AsyncThrowingStream<ChatStreamEvent, any Error>
}
```

Preserve existing prompt-stream API for PromptExecutor.

- [ ] **Step 5: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter SliceCoreTests.ChatTypesTests
swift test --filter LLMProvidersTests
```

Expected: all LLM provider tests pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/SliceCore SliceAIKit/Sources/LLMProviders SliceAIKit/Tests
git commit -m "feat(llm): add openai tool call streaming"
```

### Task 11: AgentExecutor ReAct Loop

**Files:**
- Create: `SliceAIKit/Sources/Orchestration/Executors/AgentExecutor.swift`
- Create: `SliceAIKit/Sources/Orchestration/Executors/AgentPromptBuilder.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine.swift`
- Modify: `SliceAIKit/Sources/Orchestration/Engine/ExecutionEngine+Steps.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/AgentExecutorTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/ExecutionEngineTests.swift`
- Helper: `SliceAIKit/Tests/OrchestrationTests/Helpers/MockToolCallingLLMProvider.swift`

- [ ] **Step 1: Write failing AgentExecutor tests**

Add tests:

```swift
func test_agentExecutor_callsAllowedMCPToolAndReturnsFinalAnswer() async throws
func test_agentExecutor_rejectsToolNotInAllowlistBeforeBroker() async throws
func test_agentExecutor_outOfAllowlistToolCallReturnsToolMessageWithoutBroker() async throws
func test_agentExecutor_denialIsReturnedAsToolResultAndModelFinalizes() async throws
func test_agentExecutor_mcpErrorYieldsToolCallErrorAndModelFinalizes() async throws
func test_agentExecutor_mcpResultIsErrorYieldsToolCallErrorEvent() async throws
func test_agentExecutor_invalidToolArgumentsAreSurfacedAsToolCallError() async throws
func test_agentExecutor_handlesParallelToolCallsWithMixedDenialAndSuccess() async throws
func test_agentExecutor_stopsAtMaxSteps() async throws
func test_agentExecutor_timesOutSingleToolCall() async throws
func test_agentExecutor_redactsMCPResultBeforeModelMessage() async throws
func test_agentExecutor_passesMCPInputSchemaToLLM() async throws
func test_agentExecutor_resolvesMCPDescriptorFromServerID() async throws
func test_agentExecutor_missingDescriptorFailsBeforeLLMCall() async throws
func test_agentExecutor_appendsAssistantToolCallMessageBeforeToolResult() async throws
func test_agentExecutor_streamsModelTextDeltasAsLLMChunkEvents() async throws
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.AgentExecutorTests
```

Expected: missing AgentExecutor.

- [ ] **Step 3: Implement AgentExecutor**

Constructor:

```swift
public actor AgentExecutor {
    public init(
        providerResolver: any ProviderResolverProtocol,
        mcpClient: any MCPClientProtocol,
        permissionBroker: any PermissionBrokerProtocol,
        mcpDescriptors: @escaping @Sendable () async throws -> [MCPDescriptor],
        toolCallTimeoutNanoseconds: UInt64 = 30 * 1_000_000_000
    )
}
```

Run method:

```swift
public func run(
    tool: Tool,
    agent: AgentTool,
    resolved: ResolvedExecutionContext,
    provider: Provider
) -> AsyncThrowingStream<ExecutionEvent, any Error>
```

Loop rules:

- build initial messages with selection and context bag;
- call `mcpDescriptors()` and index descriptors by `id`;
- for each `MCPToolRef.server` in `agent.mcpAllowlist`, resolve the matching `MCPDescriptor`;
- if a server id has no descriptor, fail before the first LLM call with `.failed(.configuration(.invalidTool(id: tool.id, reason: "MCP server not configured: <redacted>")))`;
- missing descriptor failure must not generate a synthetic `.toolCallError` row, because no provider `tool_call_id` exists yet;
- fetch `MCPToolDescriptor` values through `MCPClientProtocol.tools(for: descriptor)`;
- expose only descriptors whose `ref` appears in `agent.mcpAllowlist` as `ChatTool` values;
- set every `ChatTool.inputSchema` from `MCPToolDescriptor.inputSchema`;
- call `LLMProvider.streamToolChat(request:)`, not the prompt-only `stream(request:)`;
- yield existing `.llmChunk(delta:)` for every `ChatStreamEvent.textDelta`;
- let `ExecutionEngine` forward AgentExecutor events through the same OutputDispatcher path used by PromptExecutor; do not write directly to ResultPanel from AgentExecutor or ExecutionEventConsumer;
- assemble `ChatToolCall` from `ChatStreamEvent.toolCallDelta` chunks, preserving provider `tool_call_id` and raw accumulated `function.arguments`;
- after the stream finishes a tool-calling turn, parse each `argumentsRaw` into `MCPJSONValue.Object` and store it in `ChatToolCall.arguments`;
- if parse fails, keep `argumentsRaw`, set `arguments == nil`, and handle that tool call through the invalid-arguments branch below;
- when the current `streamToolChat` turn finishes with tool calls, append the assistant tool-call message before any tool result message:

```swift
messages.append(ChatMessage(
    role: .assistant,
    content: accumulatedAssistantText.isEmpty ? nil : accumulatedAssistantText,
    toolCallID: nil,
    toolCalls: assembledToolCalls
))
```

- process every `ChatToolCall` in `assembledToolCalls` order before issuing the next `streamToolChat(request:)`;
- append exactly one `role: .tool` message for every provider `tool_call_id`, regardless of success, denial, MCP error, invalid arguments, or out-of-allowlist;
- permission gating and `MCPClient.call` run sequentially within the assistant turn;
- on model tool call, validate allowlist before PermissionBroker or MCPClient;
- generate a UI `UUID` and store `providerToolCallID -> UUID` for ResultPanel correlation;
- yield `.toolCallProposed(id: uiToolCallID, ref: ref, argsDescription: redactedArgs)`;
- if the tool is not in `agent.mcpAllowlist`, yield `.toolCallDenied(id: uiToolCallID, reason: "Tool not allowed: <redacted>")`, append `ChatMessage(role:.tool, content:"Tool not allowed in this Agent allowlist", toolCallID:providerToolCallID, toolCalls:nil)`, never call `PermissionBroker.gate`, never call `MCPClient.call`, and continue the loop so the model can finalize or choose another allowed tool;
- if `ChatToolCall.arguments == nil`, yield `.toolCallError(id: uiToolCallID, summary: "invalid tool arguments")`, append `ChatMessage(role:.tool, content:"invalid tool arguments", toolCallID:providerToolCallID, toolCalls:nil)`, never call `PermissionBroker.gate`, never call `MCPClient.call`, and continue the loop so the model can retry or finalize;
- build the exact per-call permission: `.mcp(server: serverName, tools: [toolName])`;
- call `PermissionBroker.gate(effective: [permission], provenance: tool.provenance, scope: .oneTime, isDryRun: false)` for every MCP tool call;
- on `.approved`, yield `.toolCallApproved(id: uiToolCallID)`;
- on `.denied`, yield `.toolCallDenied(id: uiToolCallID, reason: redactedReason)`, append `ChatMessage(role:.tool, content:redactedDenial, toolCallID:providerToolCallID, toolCalls:nil)` to the model conversation, and let the model produce a final readable answer;
- on `.requiresUserConsent`, treat it as an integration error in production because Task 8 production broker must resolve presenter decisions internally; tests may still use this case for M2 mock compatibility;
- on `.wouldRequireConsent`, stop as invalid non-dry-run broker output;
- call `MCPClient.call`;
- on thrown MCP call error, yield `.toolCallError(id: uiToolCallID, summary: redactedError)`, append `ChatMessage(role:.tool, content:redactedError, toolCallID:providerToolCallID, toolCalls:nil)` to the model conversation, and let the model produce a final readable answer;
- if `MCPCallResult.isError == true`, yield `.toolCallError(id: uiToolCallID, summary: redactedToolErrorSummary)`, append `ChatMessage(role:.tool, content:"Tool execution error: \(redactedToolErrorSummary)", toolCallID:providerToolCallID, toolCalls:nil)` to the model conversation, and let the model produce a final readable answer;
- on `MCPCallResult.isError == false`, yield `.toolCallResult(id: uiToolCallID, summary: redactedToolSummary)`;
- on `MCPCallResult.isError == false`, append `ChatMessage(role:.tool, content:redactedToolSummary, toolCallID:providerToolCallID, toolCalls:nil)` to model messages;
- stop on final answer, maxSteps, timeout, or unrecoverable integration error.

`AgentExecutor` does not receive or call `PermissionConsentPresenting`; it only depends on `PermissionBrokerProtocol`. MCP approval is never persisted, and the broker must not record `.mcp` grants even when the presenter returns `.approve(scope: .session)`.

- [ ] **Step 4: Route `.agent` in ExecutionEngine**

Update `ExecutionEvent` before wiring ResultPanel:

```swift
case toolCallProposed(id: UUID, ref: MCPToolRef, argsDescription: String)
case toolCallApproved(id: UUID)
case toolCallResult(id: UUID, summary: String)
case toolCallDenied(id: UUID, reason: String)
case toolCallError(id: UUID, summary: String)
```

Existing consumers must be updated for the added `id` on `.toolCallProposed`.

Replace the `.agent` notImplemented branch with AgentExecutor pipeline after PermissionGraph and ContextCollector. Keep `.pipeline` not implemented.
`ExecutionEngine` owns an `AgentExecutor` instance constructed with the same `mcpDescriptors` closure injected by `AppContainer`.

- [ ] **Step 5: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter OrchestrationTests.AgentExecutorTests
swift test --filter OrchestrationTests.ExecutionEngineTests
```

Expected: agent and execution tests pass.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Orchestration SliceAIKit/Tests/OrchestrationTests
git commit -m "feat(orchestration): add agent executor"
```

### Task 12: ResultPanel Tool Call Lifecycle

**Files:**
- Modify: `SliceAIKit/Sources/Windowing/ResultContentView.swift`
- Modify: `SliceAIKit/Sources/Windowing/ResultPanel.swift`
- Modify: `SliceAIApp/ExecutionEventConsumer.swift`
- Test: `SliceAIKit/Tests/WindowingTests/ResultPanelToolCallStateTests.swift`
- Test: `SliceAIKit/Tests/OrchestrationTests/ExecutionEventTests.swift`

- [ ] **Step 1: Write failing state tests**

Add a pure state model in Windowing if none exists:

```swift
func test_toolCallState_transitionsProposedApprovedResult() throws
func test_toolCallState_recordsDenied() throws
func test_toolCallState_recordsError() throws
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter WindowingTests.ResultPanelToolCallStateTests
```

Expected: missing state model or panel API.

- [ ] **Step 3: Add state model**

Public or internal Windowing type:

```swift
public struct ResultToolCallState: Sendable, Equatable, Identifiable {
    public enum Status: Sendable, Equatable {
        case proposed
        case approved
        case result
        case denied
        case error
    }
    public let id: UUID
    public var title: String
    public var detail: String
    public var status: Status
}
```

- [ ] **Step 4: Update consumer**

Map events:

- `.llmChunk(delta:)` -> unchanged existing OutputDispatcher / ResultPanel text streaming path;
- `.toolCallProposed(id:ref:argsDescription:)` -> proposed row;
- `.toolCallApproved(id:)` -> approved;
- `.toolCallResult(id:summary:)` -> result;
- `.toolCallDenied(id:reason:)` -> denied row while the model final readable answer continues streaming;
- `.toolCallError(id:summary:)` -> error row while the model final readable answer continues streaming.

- [ ] **Step 5: Run tests and app build**

Run:

```bash
cd SliceAIKit
swift test --filter WindowingTests.ResultPanelToolCallStateTests
swift test --filter OrchestrationTests.ExecutionEventTests
cd ..
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected: tests pass and app builds.

- [ ] **Step 6: Commit**

```bash
git add SliceAIKit/Sources/Windowing SliceAIApp/ExecutionEventConsumer.swift SliceAIKit/Tests
git commit -m "feat(windowing): show agent tool calls"
```

### Task 13: Built-In `web-search-summarize` Agent Tool

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/DefaultConfiguration.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/DefaultConfigurationTests.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ToolTests.swift`

- [ ] **Step 1: Write failing default configuration tests**

Add tests:

```swift
func test_defaultConfiguration_containsWebSearchSummarizeAgentTool() throws
func test_webSearchSummarize_declaresMCPPermission() throws
func test_webSearchSummarize_requiresToolCallingProviderCapability() throws
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter SliceCoreTests.DefaultConfigurationTests
```

Expected: new default tool missing.

- [ ] **Step 3: Add tool**

Tool shape:

```swift
Tool(
    id: "web-search-summarize",
    name: "Web Search Summarize",
    icon: "magnifyingglass",
    description: "用 Brave Search MCP 搜索并总结选中内容",
    kind: .agent(AgentTool(
        systemPrompt: "You search the web only when needed and summarize with citations.",
        initialUserPrompt: "Search and summarize information related to:\n\n{{selection}}",
        contexts: [ContextRequest(key: .init(rawValue: "selection"), provider: "selection", args: [:], cachePolicy: .none, requiredness: .required)],
        provider: .capability(requires: [.toolCalling], prefer: []),
        skill: nil,
        mcpAllowlist: [MCPToolRef(server: "brave-search", tool: "brave_web_search")],
        builtinCapabilities: [],
        maxSteps: 6,
        stopCondition: .finalAnswerProvided
    )),
    permissions: [.mcp(server: "brave-search", tools: ["brave_web_search"])],
    provenance: .firstParty
)
```

Use actual initializer signatures from current `ContextRequest` and `ProviderSelection`.

- [ ] **Step 4: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter SliceCoreTests.DefaultConfigurationTests
swift test --filter SliceCoreTests.ToolTests
```

Expected: tests pass.

- [ ] **Step 5: Commit**

```bash
git add SliceAIKit/Sources/SliceCore SliceAIKit/Tests/SliceCoreTests
git commit -m "feat(core): add web search summarize tool"
```

---

## M4: Remote Transport, Per-Tool Hotkeys, E2E, Release Docs

### Task 14: Streamable HTTP Transport

**Files:**
- Create: `SliceAIKit/Sources/Capabilities/MCP/StreamableHTTPMCPClient.swift`
- Modify: `SliceAIKit/Sources/Capabilities/MCP/RoutingMCPClient.swift`
- Modify: `SliceAIApp/AppContainer.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/StreamableHTTPMCPClientTests.swift`
- Test: `SliceAIKit/Tests/CapabilitiesTests/RoutingMCPClientTests.swift`

- [ ] **Step 1: Write failing HTTP transport tests**

Use `URLProtocol` stubs. Add tests:

```swift
func test_streamableHTTP_initializePostsJSONRPCWithAcceptHeader() async throws
func test_streamableHTTP_usesSessionIDOnSubsequentRequests() async throws
func test_streamableHTTP_toolsCallAcceptsApplicationJSONResponse() async throws
func test_streamableHTTP_toolsCallAcceptsTextEventStreamResponse() async throws
func test_routingClient_routesStreamableHTTPDescriptorToHTTPClient() async throws
func test_routingClient_rejectsDeprecatedSSEDescriptor() async throws
```

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.StreamableHTTPMCPClientTests
```

Expected: missing streamable HTTP client.

- [ ] **Step 3: Implement Streamable HTTP**

Required request headers:

- `Accept: application/json, text/event-stream`
- `Content-Type: application/json`
- `MCP-Protocol-Version` after initialization
- `MCP-Session-Id` when server returns it

Security checks:

- local HTTP URLs must use localhost or 127.0.0.1 unless user explicitly configured a remote host;
- remote hosts require explicit URL and user-visible Settings validation.

- [ ] **Step 4: Reject deprecated SSE**

Routing and validation must keep `.sse` unsupported. Do not add fallback probes, endpoint-event handling, or a `LegacySSEMCPClient`.

- [ ] **Step 5: Wire routing client**

Update `RoutingMCPClient`:

```swift
case .streamableHTTP:
    guard let streamableHTTP else { throw MCPClientError.unsupportedTransport(.streamableHTTP) }
    return try await streamableHTTP.call(ref: ref, args: args)
case .sse:
    throw MCPClientError.unsupportedTransport(.sse)
```

Update `AppContainer` to construct:

```swift
let streamableHTTPClient = StreamableHTTPMCPClient(descriptors: mcpDescriptors)
let mcpClient: any MCPClientProtocol = RoutingMCPClient(
    descriptors: mcpDescriptors,
    stdio: stdioMCPClient,
    streamableHTTP: streamableHTTPClient
)
```

AgentExecutor wiring remains unchanged.

- [ ] **Step 6: Run tests**

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.StreamableHTTPMCPClientTests
swift test --filter CapabilitiesTests.RoutingMCPClientTests
```

Expected: all HTTP transport tests pass.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/Capabilities/MCP SliceAIKit/Tests/CapabilitiesTests SliceAIApp/AppContainer.swift
git commit -m "feat(capabilities): add streamable http mcp transport"
```

### Task 15: Per-Tool Hotkeys

**Files:**
- Modify: `SliceAIKit/Sources/SliceCore/ConfigurationComponents.swift`
- Modify: `SliceAIKit/Sources/SliceCore/ConfigMigratorV1ToV2.swift`
- Modify: `SliceAIKit/Sources/HotkeyManager/HotkeyRegistrar.swift`
- Modify: `SliceAIKit/Sources/SettingsUI/ToolEditorView+Sections.swift`
- Modify: `SliceAIApp/AppDelegate.swift`
- Test: `SliceAIKit/Tests/SliceCoreTests/ConfigurationTests.swift`
- Test: `SliceAIKit/Tests/HotkeyManagerTests/HotkeyTests.swift`

- [ ] **Step 1: Write failing hotkey tests**

Add tests:

```swift
func test_configurationStoresPerToolHotkeys() throws
func test_hotkeyConflict_detectsCommandPaletteConflict() throws
func test_hotkeyConflict_detectsToolToToolConflict() throws
func test_appDelegateHotkeyRouting_usesToolID() throws
```

Keep AppDelegate routing test as a pure helper test if needed; do not instantiate NSApp in SwiftPM tests.

- [ ] **Step 2: Run tests and confirm failure**

Run:

```bash
cd SliceAIKit
swift test --filter SliceCoreTests.ConfigurationTests
swift test --filter HotkeyManagerTests
```

Expected: per-tool hotkey storage/conflict helpers missing.

- [ ] **Step 3: Add config support**

Preferred model:

```swift
public struct HotkeyBindings: Sendable, Codable, Equatable {
    public var toggleCommandPalette: String
    public var tools: [String: String]
}
```

Decoder must default `tools` to `[:]` for existing config-v2 files.

- [ ] **Step 4: Add Settings UI**

Tool editor shows a hotkey recorder for each tool. Save path updates `configuration.hotkeys.tools[tool.id]`.

Conflict rules:

- duplicate normalized hotkey across tools fails UI validation;
- command palette hotkey conflicts with any tool hotkey;
- empty hotkey removes mapping.

- [ ] **Step 5: Register multiple hotkeys**

`AppDelegate.reloadHotkey()` registers:

- command palette hotkey when enabled;
- each valid tool hotkey;
- per-tool callback captures selection and runs that tool directly.

On parse/register failure, keep existing “no free logs” stance for noisy user config paths; Settings UI must show validation text.

- [ ] **Step 6: Run tests and app build**

Run:

```bash
cd SliceAIKit
swift test --filter SliceCoreTests.ConfigurationTests
swift test --filter HotkeyManagerTests
cd ..
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

Expected: tests pass and app builds.

- [ ] **Step 7: Commit**

```bash
git add SliceAIKit/Sources/SliceCore SliceAIKit/Sources/SettingsUI SliceAIKit/Sources/HotkeyManager SliceAIApp/AppDelegate.swift SliceAIKit/Tests
git commit -m "feat(app): add per-tool hotkeys"
```

### Task 16: Five MCP Server E2E And Release Documentation

**Files:**
- Create: `docs/Module/MCPClient.md`
- Create: `docs/Module/ContextProviders.md`
- Modify: `README.md`
- Modify: `docs/Task_history.md`
- Modify: `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`
- Modify: `docs/v2-refactor-master-todolist.md`
- Optional script: `scripts/phase1-mcp-e2e.sh`

- [ ] **Step 1: Create E2E checklist script**

If a script is used, it must accept installed servers and print clear manual commands:

```bash
#!/usr/bin/env bash
set -euo pipefail
echo "1. Configure filesystem MCP server in SliceAI Settings"
echo "2. Run tools/list from Settings test connection"
echo "3. Execute one safe read-only tool call"
```

The script must not contain secrets or API keys.

- [ ] **Step 2: Run full automated gate**

Run:

```bash
cd SliceAIKit
swift build
swift test --parallel --enable-code-coverage
cd ..
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```

Expected: all pass.

- [ ] **Step 3: Run five-server E2E checklist**

Manual evidence to record in task detail:

- filesystem: list tools + one safe read call;
- postgres: list tools + one read-only schema/query call;
- brave-search: list tools + one search;
- git: list tools + one read-only status/log call;
- sqlite: list tools + one read-only query.

- [ ] **Step 4: Run app scenario regression**

Manual evidence to record:

- Safari `web-search-summarize`;
- Notes `web-search-summarize`;
- Slack `web-search-summarize`;
- permission approval;
- permission denial;
- ResultPanel proposed/approved/result/error rows;
- per-tool hotkey trigger;
- command palette still opens with global hotkey.

- [ ] **Step 5: Write module docs**

`docs/Module/MCPClient.md` must cover:

- store path;
- Claude Desktop import;
- stdio lifecycle;
- Streamable HTTP lifecycle; deprecated `.sse` stays unsupported;
- permission and provenance model;
- diagnostics and redaction;
- E2E server matrix.

`docs/Module/ContextProviders.md` must cover:

- five provider names;
- args schema;
- inferred permissions;
- cancellation requirements;
- PathSandbox behavior for file.read.

- [ ] **Step 6: Update project docs**

Update:

- `README.md` status and feature list for v0.3 readiness;
- `docs/Task_history.md`;
- `docs/Task-detail/2026-05-06-phase-1-mcp-context-planning.md`;
- `docs/v2-refactor-master-todolist.md` Phase 1 status and snapshot.

- [ ] **Step 7: Commit**

```bash
git add README.md docs scripts
git commit -m "docs: record phase 1 mcp release readiness"
```

---

## Milestone Gates

### M1 Gate

Run:

```bash
cd SliceAIKit
swift build
swift test --filter SliceCoreTests
swift test --filter CapabilitiesTests
swift test --filter SettingsUITests
cd ..
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```

M1 passes when:

- Claude Desktop stdio config imports.
- Unknown provenance import is rejected.
- `npx`/`uvx`/`node`/`python` runner confirmation state is stored.
- stdio fixture can initialize/list/call.
- MCPServersPage builds and test connection works with mock client.

### M2 Gate

Run:

```bash
cd SliceAIKit
swift test --filter CapabilitiesTests.ContextProviderTests
swift test --filter OrchestrationTests.PermissionGraphTests
swift test --filter OrchestrationTests.PermissionBrokerTests
swift test --filter OrchestrationTests.ExecutionEngineTests
cd ..
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

M2 passes when:

- Five providers resolve or fail deterministically.
- `file.read` undeclared permission fails before file IO.
- File glob/prefix positive coverage passes.
- MCP `tools=nil` and superset coverage pass.
- Denied permission produces controlled failure.
- Dry-run network-write/exec still returns `wouldRequireConsent` and does not call the consent presenter.
- Non-cacheable grants (`.mcp`, `.network`, `.shellExec`, `.appIntents`) are rejected by persistent storage.
- Persistent grants survive restart; session grants do not.

### M3 Gate

Run:

```bash
cd SliceAIKit
swift test --filter LLMProvidersTests
swift test --filter OrchestrationTests.AgentExecutorTests
swift test --filter WindowingTests.ResultPanelToolCallStateTests
cd ..
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
```

M3 passes when:

- Agent loop runs one allowed MCP call and returns a final Markdown answer.
- Denied tool call is visible and stops cleanly.
- `web-search-summarize` exists in default config.
- ResultPanel shows proposed, approved, result, denied, and error lifecycle states.

### M4 Gate

Run:

```bash
cd SliceAIKit
swift build
swift test --parallel --enable-code-coverage
cd ..
xcodebuild -project SliceAI.xcodeproj -scheme SliceAI -configuration Debug build
swiftlint lint --strict
```

M4 passes when:

- Streamable HTTP tests pass.
- Deprecated `.sse` routing rejection tests pass.
- Per-tool hotkeys are configurable and conflict-checked.
- Five MCP server E2E evidence is recorded.
- Safari/Notes/Slack regression evidence is recorded.
- `docs/Module/MCPClient.md` and `docs/Module/ContextProviders.md` exist.

---

## Self-Review

### Spec Coverage

- MCPDescriptor unique source: Task 2.
- MCP JSON value/content item: Task 1 and Task 2.
- MCP tool input schemas: Task 1, Task 2, Task 4, and Task 11.
- MCPTransport Streamable HTTP and deprecated `.sse` rejection: Task 1 and Task 14.
- Permission default strategy and MCP non-cacheable grants: Task 8.
- PermissionGraph static closure and case-aware coverage: Task 6.
- MCP config, Claude import, stdio: Tasks 3-5.
- Five ContextProviders: Task 7.
- Permission UI gate: Tasks 8-9.
- AgentExecutor and `web-search-summarize`: Tasks 10-13.
- ResultPanel lifecycle UI: Task 12.
- Per-tool hotkeys: Task 15.
- Five server E2E and docs: Task 16.

### Red-Flag Scan

No unresolved markers, blank sections, or unspecified file paths remain. Each task includes concrete files, test names, commands, expected results, and commit commands.

### Type Consistency

- `MCPJSONValue.Object` is consistently used for MCP arguments.
- `MCPJSONValue` uses transparent raw JSON `Codable`, not synthesized enum wrapper JSON.
- `MCPCallResult` is placed in `SliceCore` and consumed by `Capabilities`.
- `MCPToolDescriptor.inputSchema` is the source for `ChatTool.inputSchema`.
- `MCPTransport.streamableHTTP` uses raw value `streamable-http`.
- `AgentExecutor` resolves `MCPToolRef.server` through the injected `mcpDescriptors` snapshot provider before calling `MCPClientProtocol.tools(for:)`.
- `RoutingMCPClient` is the single transport facade injected into AgentExecutor; M4 extends routing without changing AgentExecutor.
- `LLMProvider.streamToolChat(request:)` is the only tool-calling provider API, and prompt streaming remains on `stream(request:)`.
- AgentExecutor appends assistant `tool_calls` messages before appending any `role: "tool"` result, denial, or error message.
- AgentExecutor appends exactly one `role: "tool"` reply for every assistant `tool_call_id`, including invalid arguments and out-of-allowlist calls.
- `ChatToolCall.argumentsRaw` preserves provider wire history; parsed `arguments` may be nil for malformed JSON and must not be sent to MCP.
- Missing MCP descriptors fail before the first LLM call as configuration errors, not synthetic tool-call rows.
- AgentExecutor streams model text through existing `.llmChunk(delta:)` events and the normal OutputDispatcher path.
- Permission coverage is described as declared-permission `covers(effective)` rather than raw set subtraction.
- File permission coverage rejects `PathSandbox` hard-denied paths before exact, prefix, or glob matching.
- Permission UI consent is owned by `PermissionBroker` through an injected `PermissionConsentPresenting`; `ExecutionEngine` and `AgentExecutor` do not call AppKit or presenters directly.
- Tool call lifecycle events use stable IDs across proposed, approved, result, denied, and error rows.
- `MCPCallResult.isError == true` maps to `.toolCallError`, not `.toolCallResult`.
- `AgentExecutor` is routed through `ExecutionEngine`, not called directly from App UI.

---

## Execution Options After Plan Review

After this plan receives review approval:

1. **Subagent-Driven (recommended)** - Dispatch a fresh worker per task, review after each task, keep commits small.
2. **Inline Execution** - Execute tasks in this session using `superpowers:executing-plans`, with checkpoints after each milestone.
