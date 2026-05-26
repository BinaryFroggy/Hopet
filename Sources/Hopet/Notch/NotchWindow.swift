import AppKit
import Combine
import SwiftUI

/// 灵动岛承载窗口：从屏顶下沿延伸的透明无边框面板。窗口本身负责"不超过菜单栏"的层级与
/// "可在 collapsed / expanded 两态间动画切换 frame"的能力。背景由 SwiftUI 端绘制。
public final class NotchWindow: NSPanel {
    public init(rect: NSRect, contentView: NSView) {
        super.init(
            contentRect: rect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        // 刘海下沿有一段位于系统菜单栏区域内；低于菜单栏会被其遮住，视觉上留下缝隙。
        // 窗口宽度按物理刘海 gap 收窄，所以提到 statusBar + 1 只覆盖刘海中心区域。
        self.level = NSWindow.Level(rawValue: NSWindow.Level.statusBar.rawValue + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        contentView.autoresizingMask = [.width, .height]
        self.contentView = contentView
        self.ignoresMouseEvents = false
    }

    public override var canBecomeKey: Bool { false }
    public override var canBecomeMain: Bool { false }
}

@MainActor
public final class NotchWindowController {
    private var window: NotchWindow?
    private let registry: SessionRegistry
    private let inputCoordinator: InputCoordinator
    /// 注入"灵动岛已被用户关闭"的副作用——由 SceneRouter 把 `notch.enabled = false`
    /// 写入 UserDefaults 完成；controller 自身不直接碰 UserDefaults，避免与 SceneRouter
    /// 的订阅链形成回环。
    private let onUserRequestedClose: () -> Void
    private var currentLayout: NotchDetector.Layout?

    public init(
        registry: SessionRegistry,
        inputCoordinator: InputCoordinator,
        onUserRequestedClose: @escaping () -> Void
    ) {
        self.registry = registry
        self.inputCoordinator = inputCoordinator
        self.onUserRequestedClose = onUserRequestedClose
    }

    public func show() {
        guard window == nil else { return }
        guard let layout = NotchDetector.detect() else { return }

        // 无刘海机型：默认不显示降级顶条，避免遮挡菜单栏。
        // 用户在偏好的 Notch 设置里把 notch.fallbackBarEnabled 打开后才显示。
        if !layout.hasNotch {
            let fallback = UserDefaults.standard.object(forKey: "notch.fallbackBarEnabled") as? Bool ?? false
            guard fallback else {
                HopetLog.info("notch bar skipped (no notch + fallback disabled)")
                return
            }
        }

        currentLayout = layout

        // 初始为 collapsed 顶条尺寸，确保启动瞬间保持和物理刘海融为一体。
        let initialRect = topBarFrame(in: layout)

        let view = NSHostingView(rootView: NotchView(
            registry: registry,
            layout: layout,
            onResolvePermission: { [weak self] sid, rid, dec, reason in
                self?.inputCoordinator.resolvePermission(
                    sessionId: sid, requestId: rid, decision: dec, reason: reason
                )
            },
            onResolveAskUser: { [weak self] sid, rid, answers, cancel in
                self?.inputCoordinator.resolveAskUser(
                    sessionId: sid, requestId: rid, answers: answers, cancel: cancel
                )
            },
            onCloseNotch: { [weak self] in
                self?.onUserRequestedClose()
            },
            onPresentationChange: { [weak self] presentation in
                self?.applyPresentation(presentation)
            }
        ))
        view.frame = NSRect(origin: .zero, size: initialRect.size)

        let win = NotchWindow(rect: initialRect, contentView: view)
        window = win
        win.orderFrontRegardless()
        HopetLog.info("notch bar shown (hasNotch=\(layout.hasNotch))")

        // 启动时先按当前 registry 派生一次 presentation——例如启动瞬间已经有
        // pending 决策的极端情形，避免必须等下一次 mutation 才扩大。
        if currentExpandReason(registry: registry) != nil {
            applyPresentation(.expanded(height: layout.topBarRect.height))
        }
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
        currentLayout = nil
    }

    /// 切换窗口 frame 到 collapsed / expanded 对应大小。
    /// SwiftUI 的内容已经在 frame 改变之前完成重排——窗口动画把 contentView 揭开，
    /// NSHostingView 用 autoresizingMask 跟随，视觉上是"从上往下、从中间向两侧展开"。
    private func applyPresentation(_ presentation: NotchPresentation) {
        guard let win = window, let layout = currentLayout else { return }
        win.hasShadow = presentation != .collapsed
        let target: NSRect = switch presentation {
        case .collapsed:
            topBarFrame(in: layout)
        case let .expanded(height):
            expandedFrame(height: height, in: layout)
        }
        if NSEqualRects(win.frame, target) { return }
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.42
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ctx.allowsImplicitAnimation = true
            win.animator().setFrame(target, display: true)
        }
    }

    /// collapsed 态窗口 frame：有刘海时贴屏幕顶端；无刘海降级时贴菜单栏下沿。
    private func topBarFrame(in layout: NotchDetector.Layout) -> NSRect {
        var rect = layout.topBarRect
        if !layout.hasNotch {
            rect.origin.y = layout.screen.visibleFrame.maxY - rect.height
        }
        return rect
    }

    /// expanded 态窗口 frame：横向居中，顶部锚点不动，按内容高度向下展开。
    private func expandedFrame(height: CGFloat, in layout: NotchDetector.Layout) -> NSRect {
        var rect = layout.expandedRect
        rect.size.height = min(max(height, layout.topBarRect.height), layout.expandedRect.height)
        rect.origin.y = layout.expandedRect.maxY - rect.height
        return rect
    }
}
