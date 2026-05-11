import SwiftUI

/// 宠物主体。主题提供逐帧动画时显示动画，否则回退到文字徽章。
public struct PetBadgeView: View {
    /// 渲染框尺寸；PetStageView 的视口高度计算依赖该值，必须保持单一来源。
    public static let renderedSize: CGFloat = 128

    public let state: PetState
    public let theme: ThemePackage

    public init(state: PetState, theme: ThemePackage) {
        self.state = state
        self.theme = theme
    }

    public var body: some View {
        Group {
            if let animation = theme.animation(for: state) {
                FrameAnimationView(animation: animation)
                    .frame(width: Self.renderedSize, height: Self.renderedSize)
                    .shadow(color: state.accentColor.opacity(0.18), radius: 5, x: 0, y: 3)
            } else {
                fallbackBadge
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state)
        .accessibilityLabel(state.badgeLabel)
    }

    private var fallbackBadge: some View {
        Text(theme.glyph(for: state))
            .font(.system(size: 36, weight: .semibold))
            .lineLimit(1)
            .frame(width: Self.renderedSize, height: Self.renderedSize)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(state.accentColor, lineWidth: state == .idle ? 1.5 : 3)
            )
            .shadow(color: state.accentColor.opacity(0.35), radius: 8, x: 0, y: 4)
    }
}
