import AppKit
import SwiftUI

/// 管理两只宠物窗口（Claude / Codex）的可见性、位置与拖拽持久化。
@MainActor
public final class PetWindowController {
    private let registry: SessionRegistry
    private let themes: ThemeStore
    private let inputCoordinator: InputCoordinator
    private var windows: [AITool: PetWindow] = [:]

    public init(
        registry: SessionRegistry,
        themes: ThemeStore,
        inputCoordinator: InputCoordinator
    ) {
        self.registry = registry
        self.themes = themes
        self.inputCoordinator = inputCoordinator
    }

    public func showAll() {
        for tool in SessionRegistry.activeTools {
            ensureWindow(for: tool).orderFrontRegardless()
        }
    }

    public func toggleAll() {
        let anyVisible = windows.values.contains { $0.isVisible }
        if anyVisible {
            windows.values.forEach { $0.orderOut(nil) }
        } else {
            showAll()
        }
    }

    public func locate(_ tool: AITool) {
        guard let win = windows[tool] else { return }
        win.makeKeyAndOrderFront(nil)
        // 简单的"闪烁定位"：alpha 抖动一次。
        win.alphaValue = 0.3
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.4
            win.animator().alphaValue = 1.0
        }
    }

    private func ensureWindow(for tool: AITool) -> PetWindow {
        if let existing = windows[tool] { return existing }

        let origin = registry.pets[tool]?.screenPosition ?? .zero
        let stageView = PetStageView(
            registry: registry,
            themes: themes,
            tool: tool,
            onPetClick: { [weak self] in
                self?.inputCoordinator.openNewSessionDialog(for: tool)
            },
            onSubmit: { [weak self] sessionId, text in
                self?.inputCoordinator.submit(text: text, toSessionId: sessionId)
            },
            onResolvePermission: { [weak self] sessionId, requestId, decision in
                self?.inputCoordinator.resolvePermission(
                    sessionId: sessionId,
                    requestId: requestId,
                    decision: decision
                )
            },
            onResolveAskUser: { [weak self] sessionId, requestId, answers, cancel in
                self?.inputCoordinator.resolveAskUser(
                    sessionId: sessionId,
                    requestId: requestId,
                    answers: answers,
                    cancel: cancel
                )
            }
        )
        let hosting = FirstClickHostingView(rootView: stageView)
        hosting.frame = NSRect(x: 0, y: 0, width: 720, height: 720)

        let win = PetWindow(tool: tool, contentView: hosting, initialOrigin: origin)
        windows[tool] = win
        return win
    }
}
