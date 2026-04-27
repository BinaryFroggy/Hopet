import AppKit
import SwiftUI

/// 宿主一只宠物的非激活、跨 Space、置顶 NSPanel。
public final class PetWindow: NSPanel {
    public let tool: AITool

    public init(tool: AITool, contentView: NSView, initialOrigin: CGPoint) {
        self.tool = tool
        let frame = NSRect(origin: initialOrigin, size: NSSize(width: 720, height: 720))
        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.level = NSWindow.Level(Int(CGWindowLevelForKey(.floatingWindow)) + 1)
        self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.contentView = contentView
        self.title = "Hopet · \(tool.displayName)"
        self.titlebarAppearsTransparent = true
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }
}

/// `NSHostingView` 子类：让窗口非 key 时的第一次点击直接送到按钮，
/// 而不是被 macOS 用来"激活窗口"吞掉（典型场景：用户在 Claude 终端里时
/// 切回宠物气泡按「允许」会感觉第一次没反应）。
public final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
