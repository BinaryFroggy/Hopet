import SwiftUI

/// 一只宠物 + 它周围的环绕气泡。整体放进 PetWindow 里。
public struct PetStageView: View {
    @ObservedObject var registry: SessionRegistry
    @ObservedObject var themes: ThemeStore
    let tool: AITool
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
        onResolvePermission: @escaping (String, String, String) -> Void,
        onResolveAskUser: @escaping (String, String, [String: String], Bool) -> Void
    ) {
        self.registry = registry
        self.themes = themes
        self.tool = tool
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
        let slots = BubbleLayout.slots(count: sessions.count)
        return ZStack {
            // 环绕气泡先渲染（在宠物之后避免遮挡，但 zIndex 控制叠放）
            ForEach(Array(zip(sessions.indices, sessions)), id: \.1.id) { idx, session in
                let slot = slots[idx]
                let bubble = makeBubble(session: session, slot: slot)
                // 有任何待决策项时强制展开（这是用户必须看到的）。
                let mustExpand = session.pendingPermission != nil
                              || session.pendingAskUser != nil
                              || session.pendingQuestion != nil
                let isExpanded = mustExpand || (expandedBubbleId == session.id)
                let displayBubble = bubble.with(expanded: isExpanded)
                let cardSize = expandedSize(for: session)
                let offset = bubbleOffset(slot: slot, isExpanded: isExpanded, cardSize: cardSize)

                SessionBubbleView(
                    bubble: displayBubble,
                    isLeader: pet.drivenBySessionId == session.id,
                    elapsedShort: session.elapsedDescription(now: now),
                    stateDurationPhrase: session.stateDurationPhrase(now: now),
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
                .offset(x: offset.x, y: offset.y)
                .animation(.spring(response: 0.32, dampingFraction: 0.78), value: isExpanded)
                .zIndex(isExpanded ? 10 : 1)
            }

            PetBadgeView(
                tool: tool,
                state: pet.aggregatedState,
                theme: themes.activeTheme
            )
            .zIndex(5)
        }
        .frame(width: PetWindow.stageSize.width, height: PetWindow.stageSize.height)
        .onReceive(timer) { now = $0 }
    }

    /// 展开后卡片的尺寸上限（与 SessionBubbleView 内部 frame 必须保持一致）。
    /// 部分卡片高度自适应内容，这里取保守上限，仅用于外推距离的"避让"计算 ——
    /// 估高一点只会让卡片离宠物更远，不会遮挡；估低则可能压到宠物。
    private func expandedSize(for session: Session) -> CGSize {
        if session.pendingPermission != nil { return CGSize(width: 380, height: 240) }
        if session.pendingAskUser != nil { return CGSize(width: 360, height: 220) }
        if session.pendingQuestion != nil { return CGSize(width: 320, height: 130) }
        return CGSize(width: 360, height: 96)
    }

    /// 折叠态保持原 slot 偏移；展开态沿 slot 方向把卡片外推，
    /// 保证卡片靠近宠物那一侧的边距宠物中心 ≥ 宠物半径 + 安全间距，绝不遮挡主体。
    private func bubbleOffset(slot: BubbleLayout.Slot, isExpanded: Bool, cardSize: CGSize) -> CGPoint {
        if !isExpanded {
            return CGPoint(x: slot.offsetX, y: slot.offsetY)
        }
        let theta = slot.angleDegrees * .pi / 180
        let dirX = CGFloat(cos(theta))
        let dirY = CGFloat(sin(theta))
        // 宠物 128×128 圆角矩形：水平/垂直方向半径 64，对角处略小，用 64 作为最保守半径。
        let petHalfExtent: CGFloat = 64
        let safeGap: CGFloat = 16
        let cardHalfExtentAlongDir = projectedHalfExtent(width: cardSize.width, height: cardSize.height, dirX: dirX, dirY: dirY)
        let minCenterDistance = petHalfExtent + safeGap + cardHalfExtentAlongDir
        let slotRadius = sqrt(slot.offsetX * slot.offsetX + slot.offsetY * slot.offsetY)
        let dist = max(slotRadius, minCenterDistance)
        return CGPoint(x: dirX * dist, y: dirY * dist)
    }

    /// 轴对齐矩形从中心沿单位方向 (dirX, dirY) 到边的距离。
    private func projectedHalfExtent(width: CGFloat, height: CGFloat, dirX: CGFloat, dirY: CGFloat) -> CGFloat {
        let ax = abs(dirX)
        let ay = abs(dirY)
        if ax < 1e-6 { return height / 2 }
        if ay < 1e-6 { return width / 2 }
        return min(width / (2 * ax), height / (2 * ay))
    }

    private func makeBubble(session: Session, slot: BubbleLayout.Slot) -> SessionBubble {
        SessionBubble(
            id: session.id,
            tool: session.tool,
            orbitAngle: slot.angleDegrees,
            orbitRing: slot.ring,
            displayTitle: session.displayTitle,
            hasTitle: session.title != nil,
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
