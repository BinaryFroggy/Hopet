import AppKit
import SwiftUI

/// 管理全局唯一宠物窗口的可见性与拖拽。
@MainActor
public final class PetWindowController {
    private let registry: SessionRegistry
    private let themes: ThemeStore
    private let inputCoordinator: InputCoordinator
    private var window: PetWindow?

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

    public func toggle() {
        if let win = window, win.isVisible {
            win.orderOut(nil)
        } else {
            show()
        }
    }

    public func locate() {
        guard let win = window else { return }
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
            }
        )
        let hosting = FirstClickHostingView(rootView: stageView)
        hosting.frame = NSRect(origin: .zero, size: PetWindow.stageSize)

        let win = PetWindow(contentView: hosting, initialOrigin: origin)
        window = win
        return win
    }
}
