import Foundation

/// `MCPClientProtocol` 的内存 Mock 实现：构造期注入 tools 与 responses，运行期按字典查表回放。
///
/// 设计要点：
/// - **actor**：保证 actor isolation + Sendable 安全。`callCount` 这种可变状态必须串行更新，
///   actor 让我们零代价拿到这一保证；调用方需要 `await`，但 `MCPClientProtocol` 的方法本就
///   `async throws`，actor isolation 跳跃对 caller 透明。
/// - **production-side**：放在 `Sources/Capabilities/MCP/` 而非 Tests/Helpers，是因为：
///   1. 多个测试 target（OrchestrationTests / CapabilitiesTests / 未来 SliceAIAppTests）都要它，
///      只放在一个 Tests target 里其他 target import 不到；
///   2. Phase 1 真实 client 落地后，Mock 仍是 sample / demo / debug 入口，不应该跟测试耦合。
/// - **构造期注入 + 运行期只读**：`tools` 与 `responses` 在 init 落地后不再改动，避免做"先注入再
///   增删 stub"的复杂玩法——KISS。需要不同行为的测试就构造一个新 Mock。
/// - `tools(for:)` 字典 miss 返回 `[]` 而非 throw；这跟真实 MCP server "没有 tools 也是合法状态"
///   的行为一致（spec §3.4 Step 7 由 ExecutionEngine 在更高层决定空列表怎么处理）。
public final actor MockMCPClient: MCPClientProtocol {

    // MARK: - 注入状态

    /// server → 工具列表 的字典；`tools(for:)` 直接查表，未命中返回空数组。
    private let tools: [MCPDescriptor: [MCPToolRef]]

    /// 工具引用 → 期望响应 的字典；`call(ref:args:)` 命中即返回，未命中 throw `.toolNotFound`。
    /// 设计上故意忽略 `args`——M2 Mock 不验证参数，只按 ref 路由；测试需要"按参数变响应"时
    /// 改造成函数式注入即可，目前的 7 条用例不需要，KISS 优先。
    private let responses: [MCPToolRef: MCPCallResult]

    // MARK: - 调用统计（actor-isolated 可变状态）

    /// `call(ref:args:)` 累计调用次数（含 throw `.toolNotFound` 的失败次数，与"是否成功"无关）。
    /// 测试断言"我期望 caller 总共发起 N 次 MCP 调用"用。
    private var _callCount: Int = 0

    /// 暴露当前 `_callCount` 给测试断言用。actor isolation 自动序列化读，不用额外锁。
    public var callCount: Int { _callCount }

    // MARK: - 初始化

    /// 构造一个 Mock MCP client。
    /// - Parameters:
    ///   - tools: server → 工具列表 字典；缺失的 server 走"空 tools"分支。默认空字典 = 没有任何 server。
    ///   - responses: 工具引用 → 期望响应 字典；缺失的 ref 让 `call` throw `.toolNotFound`。默认空。
    public init(
        tools: [MCPDescriptor: [MCPToolRef]] = [:],
        responses: [MCPToolRef: MCPCallResult] = [:]
    ) {
        self.tools = tools
        self.responses = responses
    }

    // MARK: - MCPClientProtocol

    /// 直接查 `tools` 字典；未命中返回 `[]`（语义见类型注释）。
    public func tools(for descriptor: MCPDescriptor) async throws -> [MCPToolRef] {
        // 命中即返回拷贝；Swift Array 是 value type，调用方拿到的是独立副本，无并发风险
        tools[descriptor] ?? []
    }

    /// 在 `responses` 字典查 `ref`；命中返回，未命中 throw `.toolNotFound`。
    /// 无论是否命中都先 +1 调用计数——计数语义是"caller 发起调用次数"，而不是"成功次数"。
    public func call(ref: MCPToolRef, args: [String: String]) async throws -> MCPCallResult {
        _callCount += 1
        guard let response = responses[ref] else {
            throw MCPClientError.toolNotFound(ref: ref)
        }
        return response
    }
}
