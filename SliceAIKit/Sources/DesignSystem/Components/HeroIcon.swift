import SwiftUI

/// Onboarding 每步的 88×88pt 渐变圆角方形图标
///
/// 结构：
/// - 底层：`RoundedRectangle` + `LinearGradient`（左上→右下）
/// - 内层边框：白色 30% 透明度描边，`plusLighter` 混合模式增强质感
/// - 内容：SF Symbol 或 emoji 文本（42pt，白色）
/// - 外层阴影：基于渐变终止色 35% 不透明度，扩散半径 32pt
///
/// 使用示例（SF Symbol）：
/// ```swift
/// HeroIcon(gradient: HeroIcon.Preset.violet, symbol: "sparkles", isSFSymbol: true)
/// ```
///
/// 使用示例（emoji）：
/// ```swift
/// HeroIcon(gradient: HeroIcon.Preset.pink, symbol: "🤖")
/// ```
public struct HeroIcon: View {

    /// 渐变色对（from → to，对应 topLeading → bottomTrailing）
    public let gradient: (Color, Color)

    /// 图标字符串：SF Symbol 名称 或 emoji / 纯文本
    public let symbol: String

    /// true 时用 `Image(systemName:)` 渲染；false 时用 `Text` 渲染
    public let isSFSymbol: Bool

    public init(gradient: (Color, Color), symbol: String, isSFSymbol: Bool = false) {
        self.gradient = gradient
        self.symbol = symbol
        self.isSFSymbol = isSFSymbol
    }

    // MARK: - Body

    public var body: some View {
        ZStack {
            // 渐变背景圆角方形
            RoundedRectangle(cornerRadius: SliceRadius.hero)
                .fill(
                    LinearGradient(
                        colors: [gradient.0, gradient.1],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // 内层高光描边，plusLighter 让白色与渐变叠加更通透
                    RoundedRectangle(cornerRadius: SliceRadius.hero)
                        .stroke(.white.opacity(0.3), lineWidth: 1)
                        .blendMode(.plusLighter)
                )

            // 图标内容层
            Group {
                if isSFSymbol {
                    Image(systemName: symbol)
                        .font(.system(size: 42, weight: .medium))
                } else {
                    // emoji 或纯文本
                    Text(symbol).font(.system(size: 42))
                }
            }
            .foregroundColor(.white)
        }
        .frame(width: 88, height: 88)
        // 外层彩色投影，半径 32pt 给人悬浮感
        .shadow(color: gradient.1.opacity(0.35), radius: 32, x: 0, y: 12)
    }

    // MARK: - Preset

    /// 内置渐变预设，供三步 Onboarding 复用，避免外部散落颜色硬编码
    public enum Preset {
        /// 紫色渐变 — 欢迎步（violet 400 → violet 600）
        public static let violet: (Color, Color) = (
            Color(red: 167 / 255, green: 139 / 255, blue: 250 / 255),
            Color(red: 124 / 255, green: 58 / 255, blue: 237 / 255)
        )

        /// 蓝紫渐变 — 权限步（indigo 400 → indigo 500）
        public static let indigo: (Color, Color) = (
            Color(red: 129 / 255, green: 140 / 255, blue: 248 / 255),
            Color(red: 99 / 255, green: 102 / 255, blue: 241 / 255)
        )

        /// 紫粉渐变 — 接入模型步（pink 400 → pink 600）
        public static let pink: (Color, Color) = (
            Color(red: 244 / 255, green: 114 / 255, blue: 182 / 255),
            Color(red: 219 / 255, green: 39 / 255, blue: 119 / 255)
        )
    }
}

// MARK: - Previews

#if DEBUG
#Preview("HeroIcon Presets") {
    HStack(spacing: 24) {
        HeroIcon(gradient: HeroIcon.Preset.violet, symbol: "sparkles", isSFSymbol: true)
        HeroIcon(gradient: HeroIcon.Preset.indigo, symbol: "lock.shield", isSFSymbol: true)
        HeroIcon(gradient: HeroIcon.Preset.pink, symbol: "cpu", isSFSymbol: true)
    }
    .padding(40)
    .background(Color.gray.opacity(0.1))
}

#Preview("HeroIcon Emoji") {
    HeroIcon(gradient: HeroIcon.Preset.violet, symbol: "🤖")
        .padding(40)
}
#endif
