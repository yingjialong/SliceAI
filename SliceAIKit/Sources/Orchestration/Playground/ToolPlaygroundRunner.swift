import CoreGraphics
import Foundation
import OSLog
import SliceCore

/// Playground 运行请求。
public struct ToolPlaygroundRunRequest: Sendable, Equatable {
    /// 未保存的 Tool 草稿。
    public let tool: Tool
    /// 临时 selection 文本。
    public let selectionText: String
    /// 临时前台 App 名称。
    public let appName: String
    /// 临时窗口标题。
    public let windowTitle: String?
    /// 临时 URL。
    public let url: URL?
    /// 是否允许本次运行真实调用 MCP。
    public let allowMCPToolCalls: Bool

    /// 构造 Playground 运行请求。
    public init(
        tool: Tool,
        selectionText: String,
        appName: String,
        windowTitle: String?,
        url: URL?,
        allowMCPToolCalls: Bool
    ) {
        self.tool = tool
        self.selectionText = selectionText
        self.appName = appName
        self.windowTitle = windowTitle
        self.url = url
        self.allowMCPToolCalls = allowMCPToolCalls
    }
}

/// Tool Playground 运行边界。
public protocol ToolPlaygroundRunning: Sendable {
    /// 执行一次 Playground 试跑。
    func run(_ request: ToolPlaygroundRunRequest) -> AsyncThrowingStream<ExecutionEvent, any Error>
}

/// 默认 Playground runner，复用专用 ExecutionEngine。
public struct ToolPlaygroundRunner: ToolPlaygroundRunning {
    private static let logger = Logger(
        subsystem: "com.sliceai.orchestration",
        category: "ToolPlaygroundRunner"
    )

    private let engine: ExecutionEngine

    /// 构造 runner。
    public init(engine: ExecutionEngine) {
        self.engine = engine
    }

    /// 构造 seed 并调用唯一执行入口。
    public func run(_ request: ToolPlaygroundRunRequest) -> AsyncThrowingStream<ExecutionEvent, any Error> {
        do {
            try request.tool.validate()
        } catch let error as SliceError {
            Self.logger.warning(
                "reject invalid playground tool \(request.tool.id, privacy: .public)"
            )
            Self.logger.debug(
                "validation error \(error.developerContext, privacy: .private)"
            )
            return Self.failureStream(error)
        } catch {
            Self.logger.warning(
                "reject invalid playground tool \(request.tool.id, privacy: .public)"
            )
            Self.logger.debug(
                "validation error \(error.localizedDescription, privacy: .private)"
            )
            return Self.failureStream(.configuration(.validationFailed("Tool.validate failed")))
        }

        Self.logger.debug(
            "run playground tool \(request.tool.id, privacy: .public)"
        )
        Self.logger.debug(
            "playground input length \(request.selectionText.count, privacy: .public)"
        )
        Self.logger.debug(
            "playground mcp allowed \(request.allowMCPToolCalls, privacy: .public)"
        )
        let seed = ExecutionSeed(
            invocationId: UUID(),
            selection: SelectionSnapshot(
                text: request.selectionText,
                source: .inputBox,
                length: request.selectionText.count,
                language: nil,
                contentType: .prose
            ),
            frontApp: AppSnapshot(
                bundleId: "com.sliceai.playground",
                name: request.appName,
                url: request.url,
                windowTitle: request.windowTitle
            ),
            screenAnchor: CGPoint(x: 0, y: 0),
            timestamp: Date(),
            triggerSource: .playground,
            isDryRun: true,
            runPolicy: .playground(allowMCPToolCalls: request.allowMCPToolCalls)
        )
        return engine.execute(tool: request.tool, seed: seed)
    }

    /// 构造一个只产出失败事件的 stream，避免非法 draft 进入 LLM / MCP 执行链。
    private static func failureStream(
        _ error: SliceError
    ) -> AsyncThrowingStream<ExecutionEvent, any Error> {
        AsyncThrowingStream { continuation in
            continuation.yield(.failed(error))
            continuation.finish()
        }
    }
}
