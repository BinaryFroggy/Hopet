import SwiftUI

/// 刘海条 SwiftUI 视图。三态：collapsed / expanded / fullBubble。
public struct NotchView: View {
    @ObservedObject var registry: SessionRegistry

    public init(registry: SessionRegistry) {
        self.registry = registry
    }

    /// 当前最高优先级的"宠物 + 状态"——只展示一条。
    private var leader: (PetInstance, AITool, Session?)? {
        let candidates = registry.pets.values
            .sorted { $0.aggregatedState.priority < $1.aggregatedState.priority }
        guard let pet = candidates.first else { return nil }
        let session = pet.drivenBySessionId.flatMap { registry.session($0) }
        return (pet, pet.tool, session)
    }

    public var body: some View {
        HStack(spacing: 12) {
            if let (pet, tool, session) = leader {
                Circle()
                    .fill(pet.aggregatedState.accentColor)
                    .frame(width: 10, height: 10)
                Text(tool.displayName)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white)
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
