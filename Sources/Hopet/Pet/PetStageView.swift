import SwiftUI

/// 一只宠物 + 它周围的环绕气泡。整体放进 PetWindow 里。
public struct PetStageView: View {
    @ObservedObject var registry: SessionRegistry
    @ObservedObject var themes: ThemeStore
    let tool: AITool
    let onPetClick: () -> Void
    let onResolvePermission: (String, String, String) -> Void  // (sessionId, requestId, decision)
    /// (sessionId, requestId, answers, cancel)
    let onResolveAskUser: (String, String, [String: String], Bool) -> Void

    @State private var expandedBubbleId: String?
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(
        registry: SessionRegistry,
        themes: ThemeStore,
        tool: AITool,
        onPetClick: @escaping () -> Void,
        onResolvePermission: @escaping (String, String, String) -> Void,
        onResolveAskUser: @escaping (String, String, [String: String], Bool) -> Void
    ) {
        self.registry = registry
        self.themes = themes
        self.tool = tool
        self.onPetClick = onPetClick
        self.onResolvePermission = onResolvePermission
        self.onResolveAskUser = onResolveAskUser
    }

    private var pet: PetInstance {
        registry.pets[tool] ?? PetInstance(tool: tool)
    }

    private var sessions: [Session] {
        registry.activeSessions(of: tool)
            .sorted { $0.startedAt < $1.startedAt }
    }

    public var body: some View {
        ZStack {
            // 环绕气泡先渲染（在宠物之后避免遮挡，但 zIndex 控制叠放）
            ForEach(Array(zip(sessions.indices, sessions)), id: \.1.id) { idx, session in
                let slots = BubbleLayout.slots(count: sessions.count)
                let slot = slots[idx]
                let bubble = makeBubble(session: session, slot: slot)
                // 有任何待决策项时强制展开（这是用户必须看到的）。
                let mustExpand = session.pendingPermission != nil
                              || session.pendingAskUser != nil
                              || session.pendingQuestion != nil
                let isExpanded = mustExpand || (expandedBubbleId == session.id)
                let displayBubble = bubble.with(expanded: isExpanded)

                SessionBubbleView(
                    bubble: displayBubble,
                    isLeader: pet.drivenBySessionId == session.id,
                    elapsed: session.elapsedDescription(now: now),
                    onTap: {
                        expandedBubbleId = (expandedBubbleId == session.id) ? nil : session.id
                    },
                    onResolvePermission: { decision in
                        guard let pp = session.pendingPermission else { return }
                        onResolvePermission(session.id, pp.requestId, decision)
                    },
                    onResolveAskUser: { answers, cancel in
                        guard let pa = session.pendingAskUser else { return }
                        onResolveAskUser(session.id, pa.requestId, answers, cancel)
                        expandedBubbleId = nil
                    },
                    onDismiss: { expandedBubbleId = nil }
                )
                .offset(x: slot.offsetX, y: slot.offsetY)
                .zIndex(isExpanded ? 10 : 1)
            }

            PetBadgeView(
                tool: tool,
                state: pet.aggregatedState,
                theme: themes.activeTheme
            )
            .onTapGesture { onPetClick() }
            .zIndex(5)
        }
        .frame(width: 720, height: 720)
        .onReceive(timer) { now = $0 }
    }

    private func makeBubble(session: Session, slot: BubbleLayout.Slot) -> SessionBubble {
        SessionBubble(
            id: session.id,
            tool: session.tool,
            orbitAngle: slot.angleDegrees,
            orbitRing: slot.ring,
            displayTitle: session.displayTitle,
            displayCwd: session.cwdLastComponent,
            displayElapsed: session.elapsedDescription(now: now),
            state: session.currentState,
            expanded: false,
            pendingQuestion: session.pendingQuestion,
            pendingAskUser: session.pendingAskUser,
            pendingPermission: session.pendingPermission
        )
    }
}

private extension SessionBubble {
    func with(expanded: Bool) -> SessionBubble {
        var copy = self
        copy.expanded = expanded
        return copy
    }
}
