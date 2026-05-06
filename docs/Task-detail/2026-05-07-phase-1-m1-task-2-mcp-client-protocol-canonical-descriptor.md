# Phase 1 M1 Task 2 · MCP Client Protocol Uses Canonical Descriptor

## 任务背景

M1 Task 1 已经把 MCP JSON/value contract 下沉到 SliceCore，但 Capabilities 的 `MCPClientProtocol` 仍保留了一份重复的 `MCPDescriptor`，且 `MockMCPClient` 仍使用 `[String: String]` 参数和 `[MCPToolRef]` 工具列表。Task 2 需要把 MCP client protocol 收敛到 SliceCore canonical 类型，避免后续真实 MCP client、AgentExecutor 和配置层之间出现字段翻译与双类型漂移。

## 现有问题

- Capabilities 内部重复定义 `MCPDescriptor`，与 SliceCore canonical `MCPDescriptor` 命名和语义冲突。
- `MCPClientProtocol.tools(for:)` 返回 `[MCPToolRef]`，无法携带 tool title、description、input schema。
- `MCPClientProtocol.call(ref:args:)` 仍使用 `[String: String]`，无法承载 MCP tool 的结构化 JSON 参数。
- `MockMCPClient` 只记录 callCount，缺少最近一次结构化参数和查询 descriptor 记录，不利于上层测试定位。
- `MCPClientError.developerContext` 需要继续保证 tool ref 脱敏，避免泄露用户 server/tool 名称。
- 代码质量 review 指出 `MCPDescriptor` 只手写了 id-only `hash(into:)`，但 `Equatable` 仍是全字段合成，导致同 id 配置更新后无法命中 `[MCPDescriptor: ...]` 字典。
- 代码质量 review 指出 `MCPClientProtocol.swift` 顶部注释仍暗示 `MCPDescriptor` 与 `MCPClientError` 集中在同一文件，已不符合 Task 2 后的 canonical 类型边界。
- 复审 P3 指出 `MCPDescriptor` 改为 id identity 后，原 Codable round-trip 测试继续用 `XCTAssertEqual(d, decoded)` 会失去字段级验证能力。

## 实施方案

1. 先更新 Capabilities 测试，新增指定的三个测试方法，覆盖 canonical SliceCore descriptor、结构化参数记录和 tool ref 脱敏。
2. 运行 `swift test --filter CapabilitiesTests.MCPClientProtocolTests`，确认测试红灯，记录失败原因。
3. 最小修改 SliceCore `MCPDescriptor`，如需要仅补 `Hashable` 能力，使其可作为 `[MCPDescriptor: ...]` 的 key。
4. 删除 Capabilities 内重复 `MCPDescriptor`，协议改为使用 SliceCore canonical `MCPDescriptor`、`MCPToolDescriptor` 和 `MCPJSONValue.Object`。
5. 更新 `MockMCPClient` 的存储结构、公开记录字段和 `.toolNotFound(ref:)` 行为。
6. 运行目标测试、全量测试和 `git diff --check`，确认无回归。
7. 更新任务文档、README/模块文档（如有必要），提交单独 commit。
8. Review fix：新增红灯测试锁定 `MCPDescriptor` 的 id identity 语义，手写 `==` 与 `hash(into:)` 保持一致，并修正文档注释。
9. Review fix P3：将 `MCPDescriptor` stdio / SSE Codable round-trip 测试改为逐字段断言，避免 id-only Equatable 掩盖字段解码错误。

## ToDoList

- [x] 创建任务文档并登记 Task_history。
- [x] 编写失败测试。
- [x] 运行红灯测试并记录失败原因。
- [x] 实现 canonical MCPDescriptor 协议收敛。
- [x] 更新 MockMCPClient 结构化参数和 descriptor 记录。
- [x] 运行目标测试、全量测试和 diff 检查。
- [x] Review fix：补充 `MCPDescriptor` id identity 红灯测试。
- [x] Review fix：手写 `MCPDescriptor.==` 并修正注释/文档。
- [x] Review fix：重新运行指定测试和全量验证。
- [x] Review fix P3：将 MCPDescriptor Codable round-trip 测试改为字段级断言。
- [x] 更新文档完成态并提交 commit。

## 变动文件清单

- `SliceAIKit/Sources/SliceCore/MCPDescriptor.swift`
- `SliceAIKit/Tests/SliceCoreTests/MCPDescriptorTests.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MCPClientProtocol.swift`
- `SliceAIKit/Sources/Capabilities/MCP/MockMCPClient.swift`
- `SliceAIKit/Tests/CapabilitiesTests/MCPClientProtocolTests.swift`
- `README.md`
- `docs/Module/Capabilities.md`
- `docs/Module/SliceCore.md`
- `docs/Task_history.md`
- `docs/Task-detail/2026-05-07-phase-1-m1-task-2-mcp-client-protocol-canonical-descriptor.md`

## 代码修改逻辑

- `MCPClientProtocol` 删除 Capabilities 内重复 `MCPDescriptor`，直接 `import SliceCore` 使用 canonical `MCPDescriptor`。
- `tools(for:)` 的返回值从 `[MCPToolRef]` 升级为 `[MCPToolDescriptor]`，让 client contract 能表达 title、description 和 `inputSchema`。
- `call(ref:args:)` 的参数从 `[String: String]` 升级为 `MCPJSONValue.Object`，与 `SideEffect.callMCP` / `PipelineStep.mcp` 的结构化 JSON 参数保持一致。
- `SliceCore.MCPDescriptor` 增加 `Hashable`，并手写 `==` / `hash(into:)` 均只按稳定 `id` 判断本地注册身份，避免为了字典 key 把 `MCPCapability` / `Provenance` 扩散成 Hashable。
- `MCPDescriptorTests` 的 stdio / SSE Codable round-trip 测试不再使用 `XCTAssertEqual(d, decoded)`，而是分别断言 `id`、`transport`、`command`、`args`、`url`、`env`、`capabilities`、`provenance`，确保 id identity 不削弱字段级契约测试。
- `MockMCPClient` 的 tools 注入改为 `[MCPDescriptor: [MCPToolDescriptor]]`，responses 继续用 `[MCPToolRef: MCPCallResult]`。
- `MockMCPClient` 暴露 `public private(set)` 的 `callCount`、`lastArguments`、`lastToolsDescriptor`，测试可验证调用次数、结构化参数和最近查询 descriptor。
- `MockMCPClient.call` 无论成功或 `.toolNotFound` 都先累计 `callCount` 并记录 `lastArguments`；ref 未命中时继续抛 `.toolNotFound(ref:)`。
- `MockMCPClient` 增加 `OSLog.Logger` 调试日志，server/tool/id 均用 private privacy，方便调试但不在系统日志明文泄露用户配置。
- `MCPClientError.developerContext` 保持三类 payload 脱敏，并新增 `test_mcpClientError_developerContext_redactsToolRefs` 锁定 tool ref 不泄露原始 server/tool 名称。
- `MCPClientProtocol.swift` 顶部注释改为“本文件只定义 protocol + MCPClientError，canonical MCP 类型来自 SliceCore”，消除重复 descriptor 删除后的过期注释。
- 本任务没有实现真实 MCP transport/client、没有实现 AgentExecutor tool calling，也没有添加 AgentExecutor schema cache。

## 测试用例与结果

- 红灯命令：
  - `swift test --filter CapabilitiesTests.MCPClientProtocolTests`：失败，原因符合预期。旧 `MockMCPClient` 仍要求 Capabilities 内重复定义的 `MCPDescriptor`、`tools` value 仍是 `[MCPToolRef]`、`call` 参数仍是 `[String: String]`，且尚未暴露 `lastArguments` / `lastToolsDescriptor`。
- 绿色命令：
  - `swift test --filter CapabilitiesTests.MCPClientProtocolTests`：通过，12 tests。
  - `swift test`：通过，595 tests。
  - `git diff --check`：通过，无 whitespace error。
- Review fix 红灯命令：
  - `swift test --filter SliceCoreTests.MCPDescriptorTests`：失败，原因符合预期。同 id、不同 transport/provenance/capabilities 的 descriptor 不相等，且作为 Dictionary key 查询返回 nil。
- Review fix 绿色命令：
  - `swift test --filter SliceCoreTests.MCPDescriptorTests`：通过，14 tests。
  - `swift test --filter CapabilitiesTests.MCPClientProtocolTests`：通过，12 tests。
  - `swift test`：通过，596 tests。
  - `git diff --check`：通过，无 whitespace error。
- Review fix P3 绿色命令：
  - `swift test --filter SliceCoreTests.MCPDescriptorTests`：通过，14 tests。
  - `swift test --filter CapabilitiesTests.MCPClientProtocolTests`：通过，12 tests。
  - `swift test`：首次运行出现 1 个未定位失败且输出截断；立即复跑通过，596 tests。
  - `git diff --check`：通过，无 whitespace error。
