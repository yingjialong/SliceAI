import XCTest
import SliceCore
import Orchestration
@testable import SettingsUI

/// Playground UI 状态 reducer 测试。
final class ToolPlaygroundStateTests: XCTestCase {

    /// streaming chunk 应在运行态持续累积为预览正文。
    func test_reduceStreamingChunksAccumulatesText() {
        var state = ToolPlaygroundState()
        state.reduce(.started(invocationId: UUID()), tool: makeTool(displayMode: .window))
        state.reduce(.llmChunk(delta: "hello"), tool: makeTool(displayMode: .window))
        state.reduce(.llmChunk(delta: " world"), tool: makeTool(displayMode: .window))

        XCTAssertEqual(state.status, .running)
        XCTAssertEqual(state.streamedText, "hello world")
    }

    /// structured display mode 完成时应解析顶层 JSON object key。
    func test_finishStructuredParsesTopLevelJSONObject() {
        var state = ToolPlaygroundState()
        let tool = makeTool(displayMode: .structured)
        state.reduce(.llmChunk(delta: #"{"word":"hello","score":1}"#), tool: tool)
        state.reduce(.finished(report: .stub(flags: [.playground, .dryRun], outcome: .dryRunCompleted)), tool: tool)

        XCTAssertEqual(state.status, .succeeded)
        XCTAssertEqual(state.displayPreview.kind, .structured)
        XCTAssertTrue(state.displayPreview.summary.contains("word"))
    }

    /// file display mode 应展示 dry-run append 目标路径，不真实写文件。
    func test_fileModeShowsWouldAppendSummary() {
        var state = ToolPlaygroundState()
        let tool = makeFileTool(path: "/tmp/out.md")
        state.reduce(.llmChunk(delta: "result"), tool: tool)
        state.reduce(.finished(report: .stub(flags: [.playground], outcome: .dryRunCompleted)), tool: tool)

        XCTAssertEqual(state.displayPreview.kind, .file)
        XCTAssertTrue(state.displayPreview.summary.contains("would append"))
        XCTAssertTrue(state.displayPreview.summary.contains("/tmp/out.md"))
    }

    /// prompt preview 和 dry-run 权限事件应被记录到 UI 状态。
    func test_promptAndPermissionEventsAreRecordedForPreview() {
        var state = ToolPlaygroundState()
        let tool = makeTool(displayMode: .window)

        state.reduce(.promptRendered(preview: "redacted prompt"), tool: tool)
        state.reduce(
            .permissionWouldBeRequested(permission: .clipboard, uxHint: "Clipboard access"),
            tool: tool
        )

        XCTAssertEqual(state.promptPreview, "redacted prompt")
        XCTAssertTrue(state.permissionRows.contains { row in
            row.contains("Clipboard access")
        })
    }

    /// finish / failed 事件应分别暴露 report 摘要与用户可读错误文案。
    func test_finishedAndFailedExposeReportAndErrorSummaries() {
        var state = ToolPlaygroundState()
        let tool = makeTool(displayMode: .window)
        let report = InvocationReport(
            invocationId: UUID(),
            toolId: "tool",
            declaredPermissions: [],
            effectivePermissions: [],
            flags: [.playground, .dryRun],
            startedAt: Date(timeIntervalSince1970: 0),
            finishedAt: Date(timeIntervalSince1970: 1),
            totalTokens: 12,
            estimatedCostUSD: Decimal(string: "0.42")!,
            outcome: .dryRunCompleted
        )

        state.reduce(.finished(report: report), tool: tool)

        XCTAssertTrue(state.reportSummary.contains("12"))
        XCTAssertTrue(state.reportSummary.contains("0.42"))
        XCTAssertTrue(state.reportSummary.contains("playground"))

        state.reduce(.failed(.provider(.unauthorized)), tool: tool)

        XCTAssertEqual(state.errorMessage, SliceError.provider(.unauthorized).userMessage)
    }

    /// 构造最小 Prompt Tool，供 reducer 测试聚焦状态行为。
    private func makeTool(displayMode: DisplayMode) -> Tool {
        Tool(
            id: "tool",
            name: "Tool",
            icon: "wand.and.stars",
            description: nil,
            kind: .prompt(PromptTool(
                systemPrompt: nil,
                userPrompt: "{{selection}}",
                contexts: [],
                provider: .fixed(providerId: "openai", modelId: nil),
                temperature: nil,
                maxTokens: nil,
                variables: [:]
            )),
            visibleWhen: nil,
            displayMode: displayMode,
            outputBinding: nil,
            permissions: [],
            provenance: .firstParty,
            budget: nil,
            hotkey: nil,
            labelStyle: .icon,
            tags: []
        )
    }

    /// 构造带 appendToFile side effect 的 file display tool。
    private func makeFileTool(path: String) -> Tool {
        var tool = makeTool(displayMode: .file)
        tool.outputBinding = OutputBinding(
            primary: .file,
            sideEffects: [.appendToFile(path: path, header: nil)]
        )
        return tool
    }
}
