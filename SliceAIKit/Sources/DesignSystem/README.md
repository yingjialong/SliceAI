# DesignSystem

集中管理 SliceAI 的视觉设计 tokens、通用 Components 与 Modifiers。

## 模块职责

- Colors / Typography / Spacing / Radius / Shadow / Animation / Material tokens
- ThemeManager 驱动的 Light / Dark / Auto 主题系统
- 可跨 UI 模块复用的 SwiftUI 组件（IconButton / PillButton / SectionCard 等）
- 通用 Modifiers（.glassBackground / .hoverHighlight / .pressScale）

## 依赖

- 仅依赖 SwiftUI + Foundation + AppKit（NSVisualEffectView）
- **禁止**依赖任何业务 target（SliceCore 除外且目前不需要）

## 消费方

- Windowing / SettingsUI / Permissions 均 depend on DesignSystem
- SliceCore 保持零 UI 依赖，不引入 DesignSystem

详见 `docs/superpowers/specs/2026-04-21-ui-polish-design.md`。
