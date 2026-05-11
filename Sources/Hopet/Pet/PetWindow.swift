import AppKit
import SwiftUI

/// 宿主一只宠物的非激活、跨 Space、置顶 NSPanel。
public final class PetWindow: NSPanel {
    /// 宠物舞台容器尺寸。布局：海豹（128px）固定在窗口底部 80px 留白上方，气泡列从海豹头顶
    /// 自下往上堆 5 条；宽度按最宽气泡卡片（plan-approval = 320）+ 余量；高度按 1 个 plan-approval
    /// (~400) + 海豹 + padding 估算，能让最常见与最坏情形都不裁切，又不至于把太多空白塞进窗口
    /// 让用户拖窗口时拖到的全是顶部空气、海豹永远爬不到屏幕上半部分。
    /// 拖动通过 constrainFrameRect 约束到 screen.visibleFrame 内，不会跑到屏幕外。
    /// PetStageView / hosting view / Window 必须使用同一组尺寸。
    public static let stageSize = CGSize(width: 380, height: 620)

    public init(contentView: NSView, initialOrigin: CGPoint) {
        let frame = NSRect(origin: initialOrigin, size: NSSize(width: PetWindow.stageSize.width, height: PetWindow.stageSize.height))
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
        self.title = "Hopet"
        self.titlebarAppearsTransparent = true
    }

    public override var canBecomeKey: Bool { true }
    public override var canBecomeMain: Bool { false }

    /// 拖动 / 程序设置 frame 都路过它。把窗口完整约束到当前 screen 的 visibleFrame（去 menu bar / dock）。
    /// 横向额外留 `horizontalEdgeInset` 边距，让海豹贴边时和屏幕边沿之间有视觉呼吸空间。
    /// 窗口比 visibleFrame 大时退化为不强求贴齐，仅锁不出界。
    private static let horizontalEdgeInset: CGFloat = 30

    /// 纯函数 clamp：给定 rect 与 visibleFrame，按 horizontalEdgeInset 把 rect 锁进可视区。
    /// AppKit 坐标 y 朝上：visible.minY 是 dock 上沿，maxY 是 menu bar 下沿。
    private static func clamp(_ rect: NSRect, into visible: NSRect) -> NSRect {
        var r = rect
        if r.width + horizontalEdgeInset * 2 <= visible.width {
            r.origin.x = min(max(r.origin.x, visible.minX + horizontalEdgeInset),
                             visible.maxX - horizontalEdgeInset - r.width)
        }
        if r.height <= visible.height {
            r.origin.y = min(max(r.origin.y, visible.minY), visible.maxY - r.height)
        }
        return r
    }

    /// isMovableByWindowBackground 拖动直接调 setFrameOrigin，绕过 constrainFrameRect，
    /// 必须在这里截一道才能让左右上下都被 clamp。
    public override func setFrameOrigin(_ point: NSPoint) {
        super.setFrameOrigin(constrainFrameRect(NSRect(origin: point, size: frame.size), to: self.screen).origin)
    }

    public override func setFrame(_ frameRect: NSRect, display flag: Bool) {
        super.setFrame(constrainFrameRect(frameRect, to: self.screen), display: flag)
    }

    /// 系统路径（zoom / 多屏切换 / NSWindowRestoration）+ setFrame/setFrameOrigin 都走这一条。
    public override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        let target = screen ?? self.screen ?? NSScreen.main
        guard let visible = target?.visibleFrame else { return frameRect }
        return PetWindow.clamp(frameRect, into: visible)
    }
}

/// `NSHostingView` 子类：让窗口非 key 时的第一次点击直接送到按钮，
/// 而不是被 macOS 用来"激活窗口"吞掉（典型场景：用户在 Claude 终端里时
/// 切回宠物气泡按「允许」会感觉第一次没反应）。
public final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    public override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
