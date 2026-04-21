import SwiftUI

/// 动画时长 / 曲线预设（对应 spec §3.6）
public enum SliceAnimation {
    /// 120ms easeOut — hover 反馈
    public static let quick      = Animation.easeOut(duration: 0.12)
    /// 180ms easeOut — 出现 / 消失
    public static let standard   = Animation.easeOut(duration: 0.18)
    /// 250ms easeInOut — 主题切换
    public static let deliberate = Animation.easeInOut(duration: 0.25)
    /// 80ms easeOut — 按压
    public static let press      = Animation.easeOut(duration: 0.08)
    /// 1.4s linear 无限循环 — 进度条滑动
    public static let progress   = Animation.linear(duration: 1.4).repeatForever(autoreverses: false)
}

/// Transition 组合预设（对应 spec §3.6）
///
/// `AnyTransition` 在 Swift 6 严格并发下不符合 `Sendable`，
/// 所有 transition 属性标注 `@MainActor`，确保只从主线程访问（UI 逻辑本就如此）。
public enum SliceTransition {
    /// 出现：scale 0.96→1 + opacity 0→1
    @MainActor
    public static let scaleFadeIn: AnyTransition = .scale(scale: 0.96).combined(with: .opacity)
    /// 从指定边缘滑入 + 渐显
    @MainActor
    public static func slideFadeIn(from edge: Edge) -> AnyTransition {
        .move(edge: edge).combined(with: .opacity)
    }
}
