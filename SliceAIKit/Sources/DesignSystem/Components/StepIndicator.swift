import SwiftUI

/// Onboarding 三步进度指示器
///
/// 展示一组步骤节点（圆形）+ 连接线，根据 `currentIndex` 自动切换
/// pending / active / done 三态样式：
/// - done（已过）：勾形图标 + 浅紫填充
/// - active（当前）：数字 + 深紫填充 + 外圈光晕
/// - pending（未到）：数字 + 灰色填充
///
/// 使用示例：
/// ```swift
/// let steps = [
///     StepIndicator.Step(id: 1, label: "欢迎"),
///     StepIndicator.Step(id: 2, label: "权限"),
///     StepIndicator.Step(id: 3, label: "接入模型"),
/// ]
/// StepIndicator(steps: steps, currentIndex: 1)
/// ```
public struct StepIndicator: View {

    /// 单个步骤数据模型
    public struct Step: Identifiable {
        /// 步骤编号（从 1 开始，显示在节点内）
        public let id: Int
        /// 步骤标签（会转为全大写 + 宽字距展示）
        public let label: String

        public init(id: Int, label: String) {
            self.id = id
            self.label = label
        }
    }

    /// 步骤数组
    let steps: [Step]

    /// 当前激活步骤的下标（0-based）
    let currentIndex: Int

    public init(steps: [Step], currentIndex: Int) {
        self.steps = steps
        self.currentIndex = currentIndex
    }

    // MARK: - Body

    public var body: some View {
        HStack(spacing: SliceSpacing.lg) {
            ForEach(Array(steps.enumerated()), id: \.element.id) { idx, step in
                // 渲染节点（圆形图标 + 标签文字）
                nodeView(idx: idx, step: step)
                // 在相邻步骤之间插入连接线，最后一节点后不加
                if idx < steps.count - 1 {
                    connector(active: idx < currentIndex)
                }
            }
        }
    }

    // MARK: - Private Views

    /// 渲染单个步骤节点（圆形 + 标签）
    @ViewBuilder
    private func nodeView(idx: Int, step: Step) -> some View {
        // 根据 idx 与 currentIndex 的关系确定节点状态
        let state: NodeState = idx < currentIndex ? .done :
                               idx == currentIndex ? .active : .pending
        HStack(spacing: SliceSpacing.md) {
            // 圆形节点区域
            ZStack {
                Circle().fill(state.fill)
                if state == .done {
                    // done 态：显示勾
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(SliceColor.accentText)
                } else {
                    // active / pending 态：显示步骤编号
                    Text("\(step.id)")
                        .font(SliceFont.captionEmphasis)
                        .foregroundColor(state.textColor)
                }
            }
            .frame(width: 20, height: 20)
            // active 态：外圈光晕描边（浅紫 4pt）
            .overlay(
                Circle().stroke(
                    state == .active ? SliceColor.accentFillLight : .clear,
                    lineWidth: 4
                )
            )

            // 步骤标签文字
            Text(step.label.uppercased())
                .font(SliceFont.overline)
                .kerning(SliceKerning.wide)
                .foregroundColor(state.labelColor)
        }
    }

    /// 渲染步骤间连接线
    private func connector(active: Bool) -> some View {
        Rectangle()
            .fill(active ? SliceColor.accent.opacity(0.4) : SliceColor.divider)
            .frame(width: 38, height: 1.5)
    }

    // MARK: - NodeState

    /// 节点显示状态枚举，驱动颜色映射
    private enum NodeState: Equatable {
        case pending, active, done

        /// 节点圆形背景填充色
        var fill: Color {
            switch self {
            case .pending: return SliceColor.hoverFill
            case .active:  return SliceColor.accent
            case .done:    return SliceColor.accentFillLight
            }
        }

        /// 节点内数字文字颜色
        var textColor: Color {
            switch self {
            case .pending: return SliceColor.textTertiary
            case .active:  return .white
            case .done:    return SliceColor.accentText
            }
        }

        /// 步骤标签文字颜色
        var labelColor: Color {
            switch self {
            case .active: return SliceColor.accentText
            default:      return SliceColor.textTertiary
            }
        }
    }
}

// MARK: - Previews

#if DEBUG
#Preview("StepIndicator · step 2 active") {
    let steps = [
        StepIndicator.Step(id: 1, label: "欢迎"),
        StepIndicator.Step(id: 2, label: "权限"),
        StepIndicator.Step(id: 3, label: "接入模型")
    ]
    return StepIndicator(steps: steps, currentIndex: 1)
        .padding()
}

#Preview("StepIndicator · all done") {
    let steps = [
        StepIndicator.Step(id: 1, label: "欢迎"),
        StepIndicator.Step(id: 2, label: "权限"),
        StepIndicator.Step(id: 3, label: "接入模型")
    ]
    return StepIndicator(steps: steps, currentIndex: 3)
        .padding()
}
#endif
