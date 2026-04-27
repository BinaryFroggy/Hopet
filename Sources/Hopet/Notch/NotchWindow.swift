import AppKit
import SwiftUI

/// 吸附在刘海下边缘 / 屏顶的薄条窗口。
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
        // 不要超过菜单栏（NSMainMenuWindowLevel = 24），否则会遮挡 🦭 图标。
        self.level = .floating
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
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

    public init(registry: SessionRegistry) {
        self.registry = registry
    }

    public func show() {
        guard let layout = NotchDetector.detect() else { return }

        // 无刘海机型：默认不显示降级顶条，避免遮挡菜单栏。
        // 用户在偏好的 Behavior Tab 里把 notch.fallbackBarEnabled 打开后才显示。
        if !layout.hasNotch {
            let fallback = UserDefaults.standard.object(forKey: "notch.fallbackBarEnabled") as? Bool ?? false
            guard fallback else {
                HopetLog.info("notch bar skipped (no notch + fallback disabled)")
                return
            }
        }

        // 用 visibleFrame.maxY 而不是 frame.maxY，确保始终在菜单栏下方。
        var rect = layout.topBarRect
        rect.origin.y = layout.screen.visibleFrame.maxY - rect.height

        let view = NSHostingView(rootView: NotchView(registry: registry))
        view.frame = NSRect(origin: .zero, size: rect.size)
        let win = NotchWindow(rect: rect, contentView: view)
        window = win
        win.orderFrontRegardless()
        HopetLog.info("notch bar shown (hasNotch=\(layout.hasNotch))")
    }

    public func hide() {
        window?.orderOut(nil)
        window = nil
    }
}
