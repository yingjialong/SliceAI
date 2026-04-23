import Foundation

/// 触发时前台 app 的元数据快照；`ExecutionSeed.frontApp` 字段的类型
///
/// 含可从 AX 直接拿到的三要素（bundleId / name / windowTitle）和浏览器专属的 url。
/// windowTitle / url 可能读取失败（权限 / app 不暴露），允许 nil。
///
/// **刻意不含 `processIdentifier` / `pid`**：Phase 0 M1 / Phase 1 的审计日志按
/// `bundleId + timestamp` 定位事件已足够；要等到 Phase 1+ 支持 "同一 app 多窗口"
/// 审计视图时再引入 pid。下游如有需要可在不破坏本字段集合的前提下追加。
public struct AppSnapshot: Sendable, Equatable, Codable {
    /// 前台 app 的 bundle identifier（如 `com.apple.Safari`）
    public let bundleId: String
    /// 人类可读名称（如 `Safari`）
    ///
    /// **调用方契约**：此字段非可选。`NSRunningApplication.localizedName` 本身可能为 nil
    /// （app 启动瞬间 / AX-only 触发路径），但 `AppSnapshot` 的构造方**必须**在此时用
    /// `bundleId` 做兜底；本类型不接受 nil name。这样下游（Task 6 `ExecutionSeed`、
    /// 审计日志、Prompt 模板 `{{frontApp.name}}`）都无需再做 nil 分支。
    public let name: String
    /// 浏览器类 app 的当前页面 URL；非浏览器或未读到时为 nil
    public let url: URL?
    /// 前台窗口标题；AX 读取失败时为 nil
    public let windowTitle: String?

    /// 构造前台 app 快照
    /// - Parameters:
    ///   - bundleId: Bundle identifier
    ///   - name: 人类可读名称
    ///   - url: 当前浏览器 URL，非浏览器传 nil
    ///   - windowTitle: 前台窗口标题，未读到传 nil
    public init(bundleId: String, name: String, url: URL?, windowTitle: String?) {
        self.bundleId = bundleId
        self.name = name
        self.url = url
        self.windowTitle = windowTitle
    }
}
