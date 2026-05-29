import XCTest
@testable import SliceCore

/// ExecutionRunPolicy 的编码、默认值和 Playground 语义测试。
final class ExecutionRunPolicyTests: XCTestCase {

    /// 生产默认策略应该真实执行输出和 MCP，并由 isDryRun 决定 side effect 模式。
    func test_defaultPolicyForProductionReflectsDryRunFlag() {
        let normal = ExecutionRunPolicy.production(isDryRun: false)
        XCTAssertEqual(normal.source, .production)
        XCTAssertEqual(normal.sideEffects, .real)
        XCTAssertEqual(normal.mcpToolCalls, .realWithPermissionBroker)
        XCTAssertEqual(normal.outputRouting, .production)

        let dryRun = ExecutionRunPolicy.production(isDryRun: true)
        XCTAssertEqual(dryRun.source, .production)
        XCTAssertEqual(dryRun.sideEffects, .dryRun)
        XCTAssertEqual(dryRun.mcpToolCalls, .realWithPermissionBroker)
        XCTAssertEqual(dryRun.outputRouting, .production)
    }

    /// Playground 默认策略必须真实调用 LLM、禁用 MCP、dry-run side effects，并路由到预览输出。
    func test_defaultPlaygroundPolicyDisablesMCPUntilUserConfirms() {
        let policy = ExecutionRunPolicy.playground(allowMCPToolCalls: false)
        XCTAssertEqual(policy.source, .playground)
        XCTAssertEqual(policy.sideEffects, .dryRun)
        XCTAssertEqual(policy.mcpToolCalls, .disabled)
        XCTAssertEqual(policy.outputRouting, .playgroundPreview)
    }

    /// 用户显式允许 MCP 后，Playground 才能在 PermissionBroker 闭环下真实调用 MCP。
    func test_playgroundPolicyAllowsMCPOnlyWhenExplicitlyEnabled() {
        let policy = ExecutionRunPolicy.playground(allowMCPToolCalls: true)
        XCTAssertEqual(policy.mcpToolCalls, .realWithPermissionBroker)
    }

    /// policy 必须可稳定编码，便于 ExecutionSeed 和审计测试使用。
    func test_policyCodableRoundtrip() throws {
        let policy = ExecutionRunPolicy.playground(allowMCPToolCalls: true)
        let data = try JSONEncoder().encode(policy)
        let decoded = try JSONDecoder().decode(ExecutionRunPolicy.self, from: data)
        XCTAssertEqual(decoded, policy)
    }
}
