import SwiftUI

/// 宠物主体。主题提供逐帧动画时显示动画，否则回退到文字徽章。
public struct PetBadgeView: View {
    public let tool: AITool
    public let state: PetState
    public let theme: ThemePackage

    public init(tool: AITool, state: PetState, theme: ThemePackage) {
        self.tool = tool
        self.state = state
        self.theme = theme
    }

    public var body: some View {
        Group {
            if let animation = theme.animation(for: state) {
                FrameAnimationView(animation: animation)
                    .frame(width: 128, height: 128)
                    .shadow(color: state.accentColor.opacity(0.18), radius: 5, x: 0, y: 3)
            } else {
                fallbackBadge
            }
        }
        .animation(.easeInOut(duration: 0.2), value: state)
        .accessibilityLabel("\(tool.displayName) \(state.badgeLabel)")
    }

    private var fallbackBadge: some View {
        VStack(spacing: 4) {
            Text(theme.glyph(for: state))
                .font(.system(size: 28, weight: .semibold))
                .lineLimit(1)
            Text(tool.displayName)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(width: 128, height: 128)
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
