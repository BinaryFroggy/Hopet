import AppKit
import SwiftUI

/// 管理全局唯一宠物窗口的可见性与拖拽。
@MainActor
public final class PetWindowController {
    private let registry: SessionRegistry
    private let themes: ThemeStore
    private let inputCoordinator: InputCoordinator
    private var window: PetWindow?

    public var isVisible: Bool { window?.isVisible == true }

    public init(
        registry: SessionRegistry,
        themes: ThemeStore,
        inputCoordinator: InputCoordinator
    ) {
        self.registry = registry
        self.themes = themes
        self.inputCoordinator = inputCoordinator
    }

    public func show() {
        ensureWindow().orderFrontRegardless()
    }

    public func hide() {
        window?.orderOut(nil)
    }

    public func toggle() {
        if isVisible {
            hide()
        } else {
            show()
        }
    }

    public func locate() {
        let win = ensureWindow()
        win.makeKeyAndOrderFront(nil)
        // 简单的"闪烁定位"：alpha 抖动一次。
        win.alphaValue = 0.3
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            win.animator().alphaValue = 1.0
        }
    }

    private func ensureWindow() -> PetWindow {
        if let existing = window { return existing }

        let origin = registry.pet.screenPosition
        let stageView = PetStageView(
            registry: registry,
            themes: themes,
            onResolvePermission: { [weak self] sessionId, requestId, decision, reason in
                self?.inputCoordinator.resolvePermission(
                    sessionId: sessionId,
                    requestId: requestId,
                    decision: decision,
                    reason: reason
                )
            },
            onResolveAskUser: { [weak self] sessionId, requestId, answers, cancel in
                self?.inputCoordinator.resolveAskUser(
                    sessionId: sessionId,
                    requestId: requestId,
                    answers: answers,
                    cancel: cancel
                )
            },
            onDismiss: { [weak self] sessionId in
                self?.inputCoordinator.dismissSession(sessionId)
            },
            onStageHeightChange: { [weak self] height in
                self?.applyStageHeight(height)
            }
        )
        let initialHeight = PetStageView.stageHeight(sessions: registry.activeSessions)
        let hosting = FirstClickHostingView(rootView: stageView)
        hosting.frame = NSRect(origin: .zero, size: NSSize(width: PetWindow.stageWidth, height: initialHeight))

        let win = PetWindow(contentView: hosting, initialOrigin: origin, initialHeight: initialHeight)
        window = win
        return win
    }

    /// 把 PetStageView 算出的内容高度同步到 NSPanel。海豹钉在窗口底部，故保持
    /// origin.y 不变、只改 height——窗口顶部随气泡伸缩，海豹屏幕位置恒定。
    /// setFrame 会经 PetWindow.constrainFrameRect 重新 clamp，气泡撑高顶到 menu bar
    /// 时窗口被整体下压。
    private func applyStageHeight(_ height: CGFloat) {
        guard let win = window else { return }
        let current = win.frame
        guard abs(current.height - height) > 0.5 else { return }
        let newFrame = NSRect(x: current.origin.x, y: current.origin.y,
                              width: PetWindow.stageWidth, height: height)
        win.setFrame(newFrame, display: true)
    }
}
