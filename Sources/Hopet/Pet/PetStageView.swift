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

    /// 可视区目标可见数：用来推导 `bubbleAreaMaxHeight`，并不是硬上限——
    /// 卡片膨胀（permission / elicitation / plan-approval）时单卡占高更大，可见数自然变少。
    private static let maxVisibleBubbles: Int = 5
    /// 单个 default 卡片的估算高度（两行文本 + 内外 padding），见 SessionBubbleView.defaultCard。
    private static let defaultBubbleHeight: CGFloat = 56
    /// 气泡可视区域的最大高度：约 5 个 default 卡片 + 间距，超出则启用垂直滚动。
    private static let bubbleAreaMaxHeight: CGFloat =
        defaultBubbleHeight * CGFloat(maxVisibleBubbles)
        + interBubbleSpacing * CGFloat(maxVisibleBubbles - 1)
        + contentVerticalPadding * 2
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

    /// 少于 5 条时视口跟内容等高，否则离海豹头顶会出现一截空白；超过 5 条时 cap 住启用滚动。
    private func bubbleViewportHeight(sessions: [Session]) -> CGFloat {
        guard !sessions.isEmpty else { return 0 }
        let measured = scrollMetrics.contentHeight > 0
            ? scrollMetrics.contentHeight
            : estimatedBubbleContentHeight(count: sessions.count)
        return min(measured, PetStageView.bubbleAreaMaxHeight)
    }

    private func estimatedBubbleContentHeight(count: Int) -> CGFloat {
        let visibleCount = min(count, PetStageView.maxVisibleBubbles)
        let spacingCount = max(visibleCount - 1, 0)
        return PetStageView.defaultBubbleHeight * CGFloat(visibleCount)
            + PetStageView.interBubbleSpacing * CGFloat(spacingCount)
            + PetStageView.contentVerticalPadding * 2
    }

    public var body: some View {
        let sessions = self.sessions
        let ids = sessions.map(\.id)
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
                    scrollMetrics = metrics
                }
                .onAppear {
                    if let oldest = ids.last {
                        proxy.scrollTo(oldest, anchor: .bottom)
                    }
                }
                // 维持"最旧气泡贴海豹"的锚定语义：session 变化时重新对齐底部，
                // 否则 ScrollView cap 后新气泡会把旧的顶到不可见区。
                .onChange(of: ids) { _, newIds in
                    guard let oldest = newIds.last else { return }
                    withAnimation(.easeOut(duration: 0.25)) {
                        proxy.scrollTo(oldest, anchor: .bottom)
                    }
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
