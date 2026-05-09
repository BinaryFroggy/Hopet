import SwiftUI

/// 一只宠物 + 紧贴它头顶的会话气泡列。整体放进 PetWindow 里。
///
/// 气泡列从下往上堆叠：最贴近宠物的是"第一个气泡"（即最早的会话），越上越新——
/// 新会话从上方滑入叠在已有气泡上面，旧气泡位置保持。可视区高度按
/// `maxVisibleBubbles` 个 default 卡片估算，超出后 ScrollView 锚定
/// 最旧气泡贴底，更新的气泡溢出到顶部之外，由右侧 PixelScrollThumb 提示并往上滚查看。
public struct PetStageView: View {
    @ObservedObject var registry: SessionRegistry
    @ObservedObject var themes: ThemeStore
    let tool: AITool
    /// (sessionId, requestId, decision, reason). `reason` 仅在 plan-approval 卡片的 deny 路径上非 nil。
    let onResolvePermission: (String, String, String, String?) -> Void
    /// (sessionId, requestId, answers, cancel)
    let onResolveAskUser: (String, String, [String: String], Bool) -> Void

    @State private var now: Date = Date()
    @State private var scrollMetrics = ScrollMetrics()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private static let scrollSpaceName = "petStageScroll"

    /// default 卡片场景下希望同时可见的条数；第 6 条开始进入滚动区。
    private static let maxVisibleBubbles: Int = 5
    /// 单个 default 卡片的估算高度（两行文本 + 内外 padding），见 SessionBubbleView.defaultCard。
    private static let defaultBubbleHeight: CGFloat = 56
    /// 展开卡片的保守估算高度。pending 刚出现时 ScrollView 仍握着旧的 default 高度，
    /// 必须先用这些 hint 撑开视口，下一轮 GeometryReader 才能量到真实高度。
    private static let permissionBubbleHeight: CGFloat = 260
    private static let planApprovalBubbleHeight: CGFloat = 430
    private static let askUserBubbleHeight: CGFloat = 390
    private static let legacyQuestionBubbleHeight: CGFloat = 120
    /// 普通气泡可视区域上限：约 5 个 default 卡片 + 间距。
    private static let defaultBubbleAreaMaxHeight: CGFloat =
        defaultBubbleHeight * CGFloat(maxVisibleBubbles)
        + interBubbleSpacing * CGFloat(maxVisibleBubbles - 1)
        + contentVerticalPadding * 2
    /// 展开卡片可视区域上限：取窗口可用空间。permission / plan-approval / askUser
    /// 变高时临时使用这个 cap，再配合 scrollTo 让边缘卡片不被裁切。
    private static let expandedBubbleAreaMaxHeight: CGFloat =
        PetWindow.stageSize.height
        - PetBadgeView.renderedSize
        - petBottomPadding
        - bubbleToPetGap
        - contentVerticalPadding * 2
    /// ScrollView 内容给描边预留的上下安全边。
    private static let contentVerticalPadding: CGFloat = 1
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

    /// 列表里的会话：按 `startedAt` 倒序——最新在数组头，最旧在数组末。
    /// VStack 末项（数组末）= 最旧会话 = 紧贴宠物头顶；新会话从顶部插入。
    private var sessions: [Session] {
        registry.activeSessions(of: tool)
            .sorted { $0.startedAt > $1.startedAt }
    }

    /// 少于 5 条普通气泡时视口跟内容等高，否则离海豹头顶会出现一截空白；
    /// 超过 5 条时 cap 住启用滚动。若存在 pending 展开卡片，临时放大 cap 让卡片完整进入视口。
    private func bubbleViewportHeight(sessions: [Session]) -> CGFloat {
        guard !sessions.isEmpty else { return 0 }
        let estimated = estimatedBubbleContentHeight(sessions: sessions)
        let measured = scrollMetrics.contentHeight > 0 ? scrollMetrics.contentHeight : estimated
        let maxHeight = pendingFocusId(in: sessions) == nil
            ? PetStageView.defaultBubbleAreaMaxHeight
            : PetStageView.expandedBubbleAreaMaxHeight
        return min(max(measured, estimated), maxHeight)
    }

    private func estimatedBubbleContentHeight(sessions: [Session]) -> CGFloat {
        let bubblesHeight = sessions.reduce(CGFloat(0)) { partial, session in
            partial + estimatedBubbleHeight(session)
        }
        let spacingCount = max(sessions.count - 1, 0)
        return bubblesHeight
            + PetStageView.interBubbleSpacing * CGFloat(spacingCount)
            + PetStageView.contentVerticalPadding * 2
    }

    private func estimatedBubbleHeight(_ session: Session) -> CGFloat {
        switch session.pendingKind {
        case .permission: return PetStageView.permissionBubbleHeight
        case .planApproval: return PetStageView.planApprovalBubbleHeight
        case .askUser: return PetStageView.askUserBubbleHeight
        case .legacyQuestion: return PetStageView.legacyQuestionBubbleHeight
        case .none: return PetStageView.defaultBubbleHeight
        }
    }

    public var body: some View {
        let sessions = self.sessions
        let ids = sessions.map(\.id)
        let pendingSig = pendingSignature(of: sessions)
        let viewportHeight = bubbleViewportHeight(sessions: sessions)

        return VStack(spacing: 0) {
            Spacer(minLength: 0)

            ScrollViewReader { proxy in
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: PetStageView.interBubbleSpacing) {
                        ForEach(sessions) { session in
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
                            .id(session.id)
                            .transition(.asymmetric(
                                insertion: .move(edge: .top).combined(with: .opacity),
                                removal: .opacity
                            ))
                        }
                    }
                    // 让 1px 描边不被 ScrollView 的 clip 切掉。
                    .padding(.vertical, PetStageView.contentVerticalPadding)
                    // 当 pending 弹窗把视口临时撑高，而内容本身不足一屏时，
                    // 保持气泡贴在海豹头顶向上展开，不让内容默认吸到 ScrollView 顶部。
                    .frame(minHeight: viewportHeight, alignment: .bottom)
                    .background(
                        GeometryReader { inner in
                            Color.clear
                                .preference(
                                    key: ScrollMetricsKey.self,
                                    value: ScrollMetrics(
                                        contentHeight: inner.size.height,
                                        offset: -inner.frame(in: .named(PetStageView.scrollSpaceName)).minY
                                    )
                                )
                        }
                    )
                }
                .coordinateSpace(name: PetStageView.scrollSpaceName)
                .frame(height: viewportHeight)
                .overlay(alignment: .trailing) {
                    PixelScrollThumb(
                        contentHeight: scrollMetrics.contentHeight,
                        viewportHeight: viewportHeight,
                        offset: scrollMetrics.offset
                    )
                    .padding(.trailing, 2)
                }
                .padding(.bottom, sessions.isEmpty ? 0 : PetStageView.bubbleToPetGap)
                .animation(.spring(response: 0.32, dampingFraction: 0.82), value: ids)
                .onPreferenceChange(ScrollMetricsKey.self) { metrics in
                    let previousContentHeight = scrollMetrics.contentHeight
                    scrollMetrics = metrics
                    guard abs(metrics.contentHeight - previousContentHeight) > 1 else { return }
                    DispatchQueue.main.async {
                        scrollToFocus(proxy: proxy, animated: true)
                    }
                }
                .onAppear {
                    scrollToFocus(proxy: proxy, animated: false)
                }
                .onChange(of: ids) { _, _ in
                    scrollToFocus(proxy: proxy, animated: true)
                }
                // 单条 session 在 default ↔ permission / plan-approval / askUser 之间切换时，
                // ids 不变但卡片高度会从 ~56 跳到 ~395。viewport cap 已能容纳大卡片，
                // 但 ScrollView 滚动位置不会自动对齐——必须显式 scrollTo 让弹窗完整可见。
                .onChange(of: pendingSig) { _, _ in
                    scrollToFocus(proxy: proxy, animated: true)
                }
            }

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

    /// 当前列表中"需要被自动聚焦"的 session id —— 即最先出现 pending 大卡片的那条。
    /// 多条同时 pending 时按 sessions 数组顺序取首条（最新会话排在数组前端，让用户先看到最新通知）。
    private func pendingFocusId(in sessions: [Session]) -> String? {
        sessions.first { $0.pendingKind != nil }?.id
    }

    /// pending 状态摘要：仅用于 onChange 等价比较。要捕获"哪条 session 进入/离开 pending"
    /// 以及 pending 类型切换——permission ↔ planApproval ↔ askUser 的展开高度差异显著，
    /// 必须触发重新对齐，所以摘要里带上 kind.rawValue。
    private func pendingSignature(of sessions: [Session]) -> [String] {
        sessions.compactMap { s in
            s.pendingKind.map { "\(s.id):\($0.rawValue)" }
        }
    }

    /// 把 ScrollView 滚动到"当前应聚焦"的气泡位置，让弹窗 / 默认锚定都不被裁切。
    /// 优先级：pending 大卡片 > oldest 默认锚定。靠边缘的卡片用 .top / .bottom 锚点，
    /// 否则 SwiftUI 默认的 minimal-scroll 行为会让大卡片露半张。
    private func scrollToFocus(proxy: ScrollViewProxy, animated: Bool) {
        let snap = self.sessions
        guard !snap.isEmpty else { return }

        let targetId: String
        let anchor: UnitPoint
        if let pendingId = pendingFocusId(in: snap),
           let idx = snap.firstIndex(where: { $0.id == pendingId }) {
            targetId = pendingId
            if idx == 0 {
                anchor = .top
            } else if idx == snap.count - 1 {
                anchor = .bottom
            } else {
                anchor = .center
            }
        } else {
            targetId = snap[snap.count - 1].id
            anchor = .bottom
        }

        let scroll = { proxy.scrollTo(targetId, anchor: anchor) }
        if animated {
            withAnimation(.easeOut(duration: 0.25)) { scroll() }
        } else {
            scroll()
        }
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

/// 滚动度量：内容总高度 + 当前向下偏移（content 顶距 viewport 顶的距离，向下滚动越大）。
private struct ScrollMetrics: Equatable {
    var contentHeight: CGFloat = 0
    var offset: CGFloat = 0
}

private struct ScrollMetricsKey: PreferenceKey {
    static let defaultValue = ScrollMetrics()
    static func reduce(value: inout ScrollMetrics, nextValue: () -> ScrollMetrics) {
        value = nextValue()
    }
}

/// 像素风滚动条 thumb：仅在内容超过 viewport 时显示。
/// 配色随 colorScheme 切换以匹配 PixelChrome；无交互（拖动不归它管）。
private struct PixelScrollThumb: View {
    @Environment(\.colorScheme) private var colorScheme
    let contentHeight: CGFloat
    let viewportHeight: CGFloat
    let offset: CGFloat

    private static let pixel: CGFloat = 2
    private static let thumbWidth: CGFloat = 6
    private static let minThumbHeight: CGFloat = 14

    var body: some View {
        GeometryReader { proxy in
            let trackHeight = proxy.size.height
            let overflow = max(0, contentHeight - viewportHeight)
            if overflow > 1 {
                let ratio = max(0, min(1, viewportHeight / max(contentHeight, 1)))
                let thumbH = max(PixelScrollThumb.minThumbHeight, Self.quantize(trackHeight * ratio))
                let normalized = min(max(offset / overflow, 0), 1)
                let thumbY = Self.quantize((trackHeight - thumbH) * normalized)
                let isDark = colorScheme == .dark
                let bodyFill: Color = isDark
                    ? Color(red: 0.32, green: 0.32, blue: 0.36)
                    : Color(red: 0.86, green: 0.86, blue: 0.90)
                let highlight: Double = isDark ? 0.30 : 0.70

                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .fill(Color.black.opacity(0.25))
                        .frame(width: PixelScrollThumb.thumbWidth, height: thumbH)
                        .offset(x: PixelScrollThumb.pixel, y: PixelScrollThumb.pixel)
                    Rectangle()
                        .fill(bodyFill)
                        .frame(width: PixelScrollThumb.thumbWidth, height: thumbH)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.white.opacity(highlight))
                                .frame(height: PixelScrollThumb.pixel)
                        }
                        .overlay(Rectangle().stroke(Color.black.opacity(0.85), lineWidth: 1))
                        .offset(y: thumbY)
                }
                .animation(.easeOut(duration: 0.12), value: [thumbH, thumbY])
            }
        }
        .frame(width: PixelScrollThumb.thumbWidth + PixelScrollThumb.pixel)
        .allowsHitTesting(false)
    }

    /// 对齐到 2px 网格，保持像素颗粒感不被亚像素抗锯齿模糊。
    private static func quantize(_ value: CGFloat) -> CGFloat {
        (value / pixel).rounded() * pixel
    }
}
