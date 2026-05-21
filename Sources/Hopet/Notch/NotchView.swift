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
}

public enum NotchPresentation: Equatable {
    case collapsed
    case expanded
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
        currentExpandReason(registry: registry, completedSuppressedSessionId: completedSuppressed)
    }

    private var presentation: NotchPresentation {
        reason == nil ? .collapsed : .expanded
    }

    public var body: some View {
        ZStack(alignment: .top) {
            Color.clear
            if let r = reason {
                expandedContent(r)
                    .frame(width: layout.expandedRect.width, height: layout.expandedRect.height)
                    .background(VisualEffectBackground(cornerRadius: 22))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                collapsedContent
                    .frame(width: layout.topBarRect.width, height: layout.topBarRect.height)
                    .background(VisualEffectBackground(cornerRadius: 14))
                    .clipShape(Capsule())
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.spring(response: 0.32, dampingFraction: 0.82), value: presentation)
        .onChange(of: presentation) { _, newValue in
            onPresentationChange(newValue)
        }
        .onChange(of: completedSessionId) { _, newValue in
            // pet 退出 completed 态后清空抑制集合，下一次完成时仍能展开。
            if newValue == nil { completedSuppressed = nil }
        }
    }

    private var completedSessionId: String? {
        registry.pet.aggregatedState == .completed ? registry.pet.drivenBySessionId : nil
    }

    // MARK: - Collapsed

    @ViewBuilder
    private var collapsedContent: some View {
        let pet = registry.pet
        let session = pet.drivenBySessionId.flatMap { registry.session($0) }
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
            .task(id: session.id) {
                // 摘要展示 ~3s 后自动抑制，让下一次 mutation 重算把展开收回去。
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                completedSuppressed = session.id
            }
        }
    }
}
