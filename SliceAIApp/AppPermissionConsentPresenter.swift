// SliceAIApp/AppPermissionConsentPresenter.swift
import AppKit
import Foundation
import Orchestration
import OSLog
import SliceCore

private let appPermissionConsentLog = Logger(
    subsystem: "com.sliceai.app",
    category: "AppPermissionConsentPresenter"
)

/// AppKit 运行期权限确认弹窗。
///
/// Orchestration 只依赖 `PermissionConsentPresenting`，因此 App 层在这里完成 NSAlert 展示。
/// presenter 不提供 persistent approval；跨启动授权只能由 Settings 写入。
@MainActor
final class AppPermissionConsentPresenter: PermissionConsentPresenting {

    /// 构造 App 权限确认 presenter。
    init() {}

    /// 请求用户确认某条权限。
    ///
    /// - Parameter request: Orchestration 生成的权限确认请求。
    /// - Returns: 用户选择的授权决策；不会返回 `.persistent`。
    nonisolated func requestConsent(_ request: PermissionConsentRequest) async -> PermissionConsentDecision {
        await MainActor.run {
            Self.presentConsentAlert(for: request)
        }
    }

    /// 在主线程展示 NSAlert 并映射按钮结果。
    ///
    /// - Parameter request: 权限确认请求。
    /// - Returns: 用户选择的授权决策。
    private static func presentConsentAlert(for request: PermissionConsentRequest) -> PermissionConsentDecision {
        appPermissionConsentLog.notice("presenting permission consent alert")

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "SliceAI 请求运行期权限"
        alert.informativeText = [
            "权限：\(permissionCaseName(request.permission))",
            "来源：\(provenanceSummary(request.provenance))",
            "风险：\(operationRiskCopy(for: request.permission))",
            "提示：\(request.uxHint)",
        ].joined(separator: "\n\n")

        alert.addButton(withTitle: "本次允许")
        alert.addButton(withTitle: "本次会话允许")
        alert.addButton(withTitle: "拒绝")

        // Orchestration 对高风险 each-time 权限只允许 one-time；保留按钮但禁用，避免误导用户。
        if !request.allowedScopes.contains(.session), alert.buttons.indices.contains(1) {
            alert.buttons[1].isEnabled = false
        }

        let response = alert.runModal()
        switch response {
        case .alertFirstButtonReturn:
            appPermissionConsentLog.debug("permission consent approved once")
            return .approve(scope: .oneTime)
        case .alertSecondButtonReturn:
            appPermissionConsentLog.debug("permission consent approved for session")
            return .approve(scope: .session)
        default:
            appPermissionConsentLog.debug("permission consent denied by user")
            return .deny(reason: "user denied runtime permission")
        }
    }

    /// 返回权限 case 名称和关键关联值摘要。
    ///
    /// - Parameter permission: 待展示的权限。
    /// - Returns: 面向用户的短名称。
    private static func permissionCaseName(_ permission: Permission) -> String {
        switch permission {
        case .network(let host):
            return "network(\(host))"
        case .fileRead(let path):
            return "fileRead(\(path))"
        case .fileWrite(let path):
            return "fileWrite(\(path))"
        case .clipboard:
            return "clipboard"
        case .clipboardHistory:
            return "clipboardHistory"
        case .shellExec(let commands):
            return "shellExec(\(commands.joined(separator: ", ")))"
        case .mcp(let server, let tools):
            return "mcp(\(server), tools: \(tools?.joined(separator: ", ") ?? "all"))"
        case .screen:
            return "screen"
        case .systemAudio:
            return "systemAudio"
        case .memoryAccess(let scope):
            return "memoryAccess(\(scope))"
        case .appIntents(let bundleId):
            return "appIntents(\(bundleId))"
        }
    }

    /// 生成人类可读的来源摘要。
    ///
    /// - Parameter provenance: 工具或能力来源。
    /// - Returns: 简短来源说明。
    private static func provenanceSummary(_ provenance: Provenance) -> String {
        switch provenance {
        case .firstParty:
            return "内置工具"
        case .communitySigned(let publisher, _):
            return "社区签名：\(publisher)"
        case .selfManaged:
            return "用户自行管理"
        case .unknown(let importedFrom, _):
            return "未验证来源：\(importedFrom?.absoluteString ?? "未知")"
        }
    }

    /// 根据权限生成风险说明。
    ///
    /// - Parameter permission: 待说明的权限。
    /// - Returns: 操作风险文案。
    private static func operationRiskCopy(for permission: Permission) -> String {
        switch permission {
        case .network(let host):
            return "将访问网络主机 \(host)，可能发送当前上下文。"
        case .fileRead(let path):
            return "将读取本地文件 \(path) 的内容。"
        case .fileWrite(let path):
            return "将写入或修改本地文件 \(path)。"
        case .clipboard:
            return "将读取或写入当前剪贴板内容。"
        case .clipboardHistory:
            return "将访问剪贴板历史内容。"
        case .shellExec(let commands):
            return "将执行 shell 命令：\(commands.joined(separator: ", "))。"
        case .mcp(let server, let tools):
            return "将调用 MCP server \(server) 的工具：\(tools?.joined(separator: ", ") ?? "全部工具")。"
        case .screen:
            return "将读取屏幕内容或截图。"
        case .systemAudio:
            return "将使用系统音频输出能力。"
        case .memoryAccess(let scope):
            return "将访问记忆范围 \(scope)。"
        case .appIntents(let bundleId):
            return "将触发应用 \(bundleId) 的 App Intent 或快捷指令。"
        }
    }
}
