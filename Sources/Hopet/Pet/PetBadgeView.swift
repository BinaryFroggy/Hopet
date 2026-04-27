import SwiftUI

/// 用文字代替海豹精灵图：圆胶囊里显示主题 glyph + 工具名 + 状态色边框。
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
        .animation(.easeInOut(duration: 0.2), value: state)
    }
}
