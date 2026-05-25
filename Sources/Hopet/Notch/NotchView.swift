import SwiftUI

/// 灵动岛展开内容的语义来源。任一非 nil 即触发下拉展开；优先级与 SessionBubbleView 一致：
/// permission/planApproval > askUser > completed。所有判定基于 registry 的派生状态，
/// 没有自带状态机——pendingPermission 被 PermissionPrompter 清空后，reason 自动消失，
/// SwiftUI 重算 → 灵动岛回到 collapsed。
public enum ExpandReason: Equatable {
    case permission(Session, PendingPermission)
    case planApproval(Session, PendingPermission)
    case askUser(Session, PendingAskUser)
    case completed(Session)
    case details(Session?)
}

public enum NotchPresentation: Equatable {
    case collapsed
    case expanded(height: CGFloat)
}

/// 派生当前展开理由。`completedSuppressedSessionId` 用来配合"会话结束摘要 3s 后自动收起"
/// ——卡片自行用 Task.sleep 通知容器把该 session id 加入抑制集合，下一次重算就跳过 completed。
@MainActor
public func currentExpandReason(
    registry: SessionRegistry,
    completedSuppressedSessionId: String? = nil
) -> ExpandReason? {
    guard let sid = registry.pet.drivenBySessionId,
          let session = registry.session(sid) else {
        return nil
    }

    if let pp = session.pendingPermission {
        return pp.isPlanApproval ? .planApproval(session, pp) : .permission(session, pp)
    }
    if let ask = session.pendingAskUser {
        return .askUser(session, ask)
    }
    if registry.pet.aggregatedState == .completed,
       completedSuppressedSessionId != session.id {
        return .completed(session)
    }
    return nil
}

/// 灵动岛 SwiftUI 视图。`collapsed` 顶条 28pt、`expanded` 下拉卡片占 layout.expandedRect。
/// 窗口尺寸切换由 `onPresentationChange` 上报给 NotchWindowController 完成。
public struct NotchView: View {
    @ObservedObject var registry: SessionRegistry
    let layout: NotchDetector.Layout
    let onResolvePermission: (_ sessionId: String, _ requestId: String, _ decision: String, _ reason: String?) -> Void
    let onResolveAskUser: (_ sessionId: String, _ requestId: String, _ answers: [String: String], _ cancel: Bool) -> Void
    let onCloseNotch: () -> Void
    let onPresentationChange: (NotchPresentation) -> Void

    @State private var completedSuppressed: String? = nil
    @State private var completedHeldSessionId: String? = nil
    @State private var completedContentHeight: CGFloat = 0
    @State private var manualExpanded = false
    @State private var hoverCollapsed = false
    @State private var userCollapsedReasonIdentity: String? = nil

    public init(
        registry: SessionRegistry,
        layout: NotchDetector.Layout,
        onResolvePermission: @escaping (String, String, String, String?) -> Void,
        onResolveAskUser: @escaping (String, String, [String: String], Bool) -> Void,
        onCloseNotch: @escaping () -> Void,
        onPresentationChange: @escaping (NotchPresentation) -> Void
    ) {
        self.registry = registry
        self.layout = layout
        self.onResolvePermission = onResolvePermission
        self.onResolveAskUser = onResolveAskUser
        self.onCloseNotch = onCloseNotch
        self.onPresentationChange = onPresentationChange
    }

    private var reason: ExpandReason? {
        if let live = rawReason, identity(of: live) != userCollapsedReasonIdentity {
            return live
        }
        if manualExpanded { return .details(detailSession) }
        return nil
    }

    private var rawReason: ExpandReason? {
        if let live = currentExpandReason(registry: registry, completedSuppressedSessionId: completedSuppressed) {
            return live
        }
        guard registry.pet.aggregatedState == .idle,
              let held = completedHeldSessionId,
              completedSuppressed != held,
              let session = registry.session(held) else {
            return nil
        }
        return .completed(session)
    }

    private var detailSession: Session? {
        if let sid = registry.pet.drivenBySessionId,
           let session = registry.session(sid) {
            return session
        }
        return registry.activeSessions.sorted { a, b in
            if a.lastActivityAt != b.lastActivityAt { return a.lastActivityAt > b.lastActivityAt }
            return a.id < b.id
        }.first
    }

    private var presentation: NotchPresentation {
        guard let reason else { return .collapsed }
        return .expanded(height: expandedHeight(for: reason))
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let r = reason {
                let shape = NotchDropShape(radius: 22)
                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: layout.notchReservedHeight)
                    expandedContent(r)
                }
                    .frame(maxWidth: .infinity, minHeight: expandedHeight(for: r), maxHeight: expandedHeight(for: r), alignment: .top)
                    .background(
                        shape.fill(Color.black)
                    )
                    .clipShape(shape)
                    .clipped()
                    .overlay(alignment: .top) {
                        collapseButton
                            .padding(.top, layout.notchReservedHeight + 6)
                    }
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .offset(y: -8)),
                        removal: .opacity.combined(with: .offset(y: -6))
                    ))
            } else {
                let shape = NotchDropShape(radius: layout.topBarRect.height / 2)
                collapsedContent
                    .frame(width: layout.topBarRect.width, height: layout.topBarRect.height)
                    .background(shape.fill(Color.black))
                    .clipShape(shape)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.44, dampingFraction: 0.92, blendDuration: 0.12), value: presentation)
        .onAppear {
            onPresentationChange(presentation)
        }
        .onChange(of: presentation) { _, newValue in
            onPresentationChange(newValue)
        }
        .onChange(of: reasonIdentity) { _, _ in
            completedContentHeight = 0
        }
        .onChange(of: rawReasonIdentity) { _, newValue in
            if newValue == nil { userCollapsedReasonIdentity = nil }
        }
        .onChange(of: completedSessionId) { _, newValue in
            guard let newValue else { return }
            // Pet 的 completed 态 2s 后会回 idle；刘海完成摘要需要独立停留 3s。
            completedSuppressed = nil
            completedHeldSessionId = newValue
            userCollapsedReasonIdentity = nil
        }
        .onPreferenceChange(NotchCompletedContentHeightKey.self) { height in
            guard height > 0 else { return }
            let rounded = ceil(height)
            if abs(rounded - completedContentHeight) > 1 {
                completedContentHeight = rounded
            }
        }
    }

    private var completedSessionId: String? {
        registry.pet.aggregatedState == .completed ? registry.pet.drivenBySessionId : nil
    }

    private var reasonIdentity: String {
        guard let reason else { return "collapsed" }
        return identity(of: reason)
    }

    private var rawReasonIdentity: String? {
        rawReason.map(identity(of:))
    }

    private func identity(of reason: ExpandReason) -> String {
        switch reason {
        case let .permission(session, pending):
            return "permission:\(session.id):\(pending.requestId)"
        case let .planApproval(session, pending):
            return "plan:\(session.id):\(pending.requestId)"
        case let .askUser(session, pending):
            return "ask:\(session.id):\(pending.requestId)"
        case let .completed(session):
            return "completed:\(session.id)"
        case let .details(session):
            return "details:\(session?.id ?? "none")"
        }
    }

    private func expandedHeight(for reason: ExpandReason) -> CGFloat {
        let maxHeight = layout.expandedRect.height
        let contentMaxHeight = max(0, maxHeight - layout.notchReservedHeight)
        let raw: CGFloat = switch reason {
        case .permission:
            min(176, contentMaxHeight)
        case .planApproval:
            contentMaxHeight
        case .askUser:
            min(260, contentMaxHeight)
        case .completed:
            min(completedContentHeight > 0 ? completedContentHeight : 132, contentMaxHeight)
        case .details:
            min(260, contentMaxHeight)
        }
        return min(max(layout.notchReservedHeight + raw, layout.topBarRect.height), maxHeight)
    }

    private var collapseButton: some View {
        Button {
            collapseCurrentPanel()
        } label: {
            Image(systemName: "chevron.up.circle.fill")
                .symbolRenderingMode(.hierarchical)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white.opacity(0.74))
        }
        .buttonStyle(.plain)
        .help("收起面板")
    }

    // MARK: - Collapsed

    @ViewBuilder
    private var collapsedContent: some View {
        let pet = registry.pet
        VStack(spacing: 0) {
            Color.clear
                .frame(height: layout.notchReservedHeight)
            HStack(spacing: 8) {
                Circle()
                    .fill(pet.aggregatedState.accentColor)
                    .frame(width: 8, height: 8)
                Text(pet.aggregatedState.notchCaption)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.86))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if hoverCollapsed {
                    Button {
                        manualExpanded = true
                        userCollapsedReasonIdentity = nil
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .symbolRenderingMode(.hierarchical)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                    .buttonStyle(.plain)
                    .help("展开详情")
                }
            }
            .frame(maxWidth: .infinity, minHeight: layout.collapsedStripHeight, maxHeight: layout.collapsedStripHeight)
        }
        .padding(.horizontal, 12)
        .contentShape(Rectangle())
        .onHover { hovering in
            hoverCollapsed = hovering
        }
    }

    // MARK: - Expanded

    @ViewBuilder
    private func expandedContent(_ r: ExpandReason) -> some View {
        switch r {
        case let .permission(session, pp):
            NotchPermissionCard(
                session: session,
                pending: pp,
                onResolve: { decision, reason in
                    onResolvePermission(session.id, pp.requestId, decision, reason)
                },
                onClose: onCloseNotch
            )
        case let .planApproval(session, pp):
            NotchPlanApprovalCard(
                session: session,
                pending: pp,
                onResolve: { decision, reason in
                    onResolvePermission(session.id, pp.requestId, decision, reason)
                },
                onClose: onCloseNotch
            )
        case let .askUser(session, ask):
            NotchAskUserCard(
                session: session,
                pending: ask,
                onSubmit: { answers, cancel in
                    onResolveAskUser(session.id, ask.requestId, answers, cancel)
                },
                onClose: onCloseNotch
            )
        case let .completed(session):
            NotchCompletedSummaryCard(
                session: session,
                onClose: onCloseNotch
            )
            .background(
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: NotchCompletedContentHeightKey.self,
                        value: proxy.size.height
                    )
                }
            )
            .task(id: session.id) {
                // 摘要展示 ~3s 后自动抑制，让下一次 mutation 重算把展开收回去。
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                completedSuppressed = session.id
                if completedHeldSessionId == session.id {
                    completedHeldSessionId = nil
                }
            }
        case let .details(session):
            NotchDetailsCard(
                session: session,
                pet: registry.pet,
                onClose: onCloseNotch
            )
        }
    }

    private func collapseCurrentPanel() {
        manualExpanded = false
        if let reason {
            userCollapsedReasonIdentity = identity(of: reason)
            if case let .completed(session) = reason {
                completedSuppressed = session.id
                if completedHeldSessionId == session.id {
                    completedHeldSessionId = nil
                }
            }
        }
    }
}

private struct NotchCompletedContentHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct NotchDropShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.width / 2, rect.height)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - r, y: rect.maxY),
            control: CGPoint(x: rect.maxX, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX, y: rect.maxY - r),
            control: CGPoint(x: rect.minX, y: rect.maxY)
        )
        path.closeSubpath()
        return path
    }
}
