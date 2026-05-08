import SwiftUI

/// 一只宠物 + 紧贴它头顶的会话气泡列。整体放进 PetWindow 里。
///
/// 气泡列从下往上堆叠：最贴近宠物的是最新一个会话，越上越旧；最多保留 5 条，
/// 第 6 个新会话进来时把最旧那条挤出列表。空状态下只显示宠物。
public struct PetStageView: View {
    @ObservedObject var registry: SessionRegistry
    @ObservedObject var themes: ThemeStore
    let tool: AITool
    /// (sessionId, requestId, decision, reason). `reason` 仅在 plan-approval 卡片的 deny 路径上非 nil。
    let onResolvePermission: (String, String, String, String?) -> Void
    /// (sessionId, requestId, answers, cancel)
    let onResolveAskUser: (String, String, [String: String], Bool) -> Void

    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// 列表最多展示几个会话气泡。超出的旧会话被滚出视野（仍存在于 registry，仅不显示）。
    private static let maxVisibleBubbles: Int = 5
    /// 气泡列与宠物头顶之间的视觉间距。
    private static let bubbleToPetGap: CGFloat = 6
    /// 气泡之间的纵向间距。
    private static let interBubbleSpacing: CGFloat = 6
    /// 宠物距离窗口底部的留白。clamp 到屏幕底之后，这一段就是海豹和 dock 之间的安全距离。
    private static let petBottomPadding: CGFloat = 30

    public init(
        registry: SessionRegistry,
        themes: ThemeStore,
        tool: AITool,
        onResolvePermission: @escaping (String, String, String, String?) -> Void,
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

    /// 列表里的会话：按 `startedAt` 升序倒排，最新的排数组开头。
    /// 注意 ForEach 渲染时再做一次 reverse —— 想让"最新会话紧贴宠物"，VStack 里
    /// 它必须出现在最后一个位置。
    private var sessions: [Session] {
        registry.activeSessions(of: tool)
            .sorted { $0.startedAt > $1.startedAt }
            .prefix(PetStageView.maxVisibleBubbles)
            .map { $0 }
    }

    public var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // 旧 → 新（自上而下）。VStack 末项 = 最新会话，紧贴宠物头顶。
            VStack(spacing: PetStageView.interBubbleSpacing) {
                ForEach(Array(sessions.reversed())) { session in
                    SessionBubbleView(
                        bubble: makeBubble(session: session),
                        isLeader: pet.drivenBySessionId == session.id,
                        stateDurationPhrase: session.stateDurationPhrase(now: now),
                        onResolvePermission: { decision, reason in
                            guard let pp = session.pendingPermission else { return }
                            onResolvePermission(session.id, pp.requestId, decision, reason)
                        },
                        onResolveAskUser: { answers, cancel in
                            guard let pa = session.pendingAskUser else { return }
                            onResolveAskUser(session.id, pa.requestId, answers, cancel)
                        }
                    )
                    .transition(.asymmetric(
                        insertion: .move(edge: .bottom).combined(with: .opacity),
                        removal: .opacity
                    ))
                }
            }
            .padding(.bottom, PetStageView.bubbleToPetGap)
            .animation(.spring(response: 0.32, dampingFraction: 0.82), value: sessions.map(\.id))

            PetBadgeView(
                tool: tool,
                state: pet.aggregatedState,
                theme: themes.activeTheme
            )

            Spacer().frame(height: PetStageView.petBottomPadding)
        }
        .frame(width: PetWindow.stageSize.width, height: PetWindow.stageSize.height)
        .onReceive(timer) { now = $0 }
    }

    private func makeBubble(session: Session) -> SessionBubble {
        SessionBubble(
            id: session.id,
            tool: session.tool,
            displayTitle: session.displayTitle,
            hasTitle: session.title != nil,
            displayCwd: session.cwdLastComponent,
            state: session.currentState,
            lastAssistantMessage: session.lastAssistantMessage,
            pendingQuestion: session.pendingQuestion,
            pendingAskUser: session.pendingAskUser,
            pendingPermission: session.pendingPermission
        )
    }
}
