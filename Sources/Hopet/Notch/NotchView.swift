import SwiftUI

/// 刘海条 SwiftUI 视图。三态：collapsed / expanded / fullBubble。
public struct NotchView: View {
    @ObservedObject var registry: SessionRegistry

    public init(registry: SessionRegistry) {
        self.registry = registry
    }

    /// 当前 leader session（驱动宠物动画的那条）。可能为空——所有 session 都退出后 pet 进 idle，
    /// `drivenBySessionId` 为 nil。
    private var leaderSession: Session? {
        registry.pet.drivenBySessionId.flatMap { registry.session($0) }
    }

    public var body: some View {
        let pet = registry.pet
        let session = leaderSession
        HStack(spacing: 12) {
            if session != nil || pet.aggregatedState != .idle {
                Circle()
                    .fill(pet.aggregatedState.accentColor)
                    .frame(width: 10, height: 10)
                if let tool = session?.tool {
                    Text(tool.displayName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(pet.aggregatedState.notchCaption)
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.8))
                if let s = session {
                    Text("· \(s.displayTitle)")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            } else {
                Text("Hopet — Idle")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.6))
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 28)
        .background(
            Capsule().fill(Color.black.opacity(0.85))
        )
    }
}
