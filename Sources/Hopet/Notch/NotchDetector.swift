import AppKit

/// 检测主屏是否有刘海，并给出灵动岛在 collapsed / expanded 两种态下的 rect。
public enum NotchDetector {
    public struct Layout {
        public let hasNotch: Bool
        public let screen: NSScreen
        /// 顶部纯黑保留区：有刘海屏覆盖从屏幕顶端到系统 safe area 底部的区域，
        /// 防止物理刘海下沿与菜单栏底部之间露出缝隙。
        public let notchReservedHeight: CGFloat
        /// collapsed 态真正承载状态文字 / 色点的底部条高度。
        public let collapsedStripHeight: CGFloat
        /// collapsed 态：有刘海时从屏幕顶端开始；无刘海时贴菜单栏下沿。
        public let topBarRect: CGRect
        /// expanded 态最大区域：有刘海时从屏幕顶端向下延伸，无刘海时从菜单栏下沿向下延伸。
        /// 实际高度由内容测量后再包裹，最多不超过该 rect 的高度。
        public let expandedRect: CGRect
    }

    private struct NotchGeometry {
        let rect: CGRect
    }

    /// collapsed 态优先贴近物理刘海宽度，避免默认态变成横跨菜单栏的大胶囊。
    private static let fallbackCollapsedWidth: CGFloat = 184
    private static let collapsedMinWidth: CGFloat = 160
    private static let collapsedMaxWidth: CGFloat = 220
    private static let collapsedNotchPadding: CGFloat = 0
    private static let collapsedStripHeight: CGFloat = 26
    /// expanded 态最大宽度（pt）。从 collapsed 宽度向两侧展开。
    private static let expandedMaxWidth: CGFloat = 560
    /// expanded 区域距屏边的最小留白。
    private static let expandedSideMargin: CGFloat = 48

    public static func detect() -> Layout? {
        guard let screen = preferredScreen() else { return nil }
        let safeTop = screen.safeAreaInsets.top
        let frame = screen.frame
        let visible = screen.visibleFrame
        let hasNotch = safeTop > 0
        let topAnchorY = hasNotch ? frame.maxY : visible.maxY
        let notchReservedHeight = hasNotch ? safeTop : 0

        let collapsedWidth = Self.collapsedWidth(for: screen, hasNotch: hasNotch)
        let collapsedHeight = notchReservedHeight + Self.collapsedStripHeight
        let topBar = CGRect(
            x: frame.midX - collapsedWidth / 2,
            y: topAnchorY - collapsedHeight,
            width: collapsedWidth,
            height: collapsedHeight
        )

        let expandedWidth = min(expandedMaxWidth, max(320, visible.width - expandedSideMargin * 2))
        let expandedHeight = min(frame.height / 4, max(120, visible.height - 40))
        let expanded = CGRect(
            x: frame.midX - expandedWidth / 2,
            y: topAnchorY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )

        return Layout(
            hasNotch: hasNotch,
            screen: screen,
            notchReservedHeight: notchReservedHeight,
            collapsedStripHeight: Self.collapsedStripHeight,
            topBarRect: topBar,
            expandedRect: expanded
        )
    }

    private static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
    }

    private static func collapsedWidth(for screen: NSScreen, hasNotch: Bool) -> CGFloat {
        guard hasNotch, let notchWidth = notchGeometry(on: screen)?.rect.width else {
            return fallbackCollapsedWidth
        }
        return min(collapsedMaxWidth, max(collapsedMinWidth, notchWidth + collapsedNotchPadding))
    }

    /// `auxiliaryTop*Area` is Swift-private in the SDK, so use KVC to read the
    /// ObjC properties and infer the notch gap between the two menu bar
    /// auxiliary areas. See DevDocs/features.md §3.2.
    private static func notchGeometry(on screen: NSScreen) -> NotchGeometry? {
        guard let leftValue = screen.value(forKey: "auxiliaryTopLeftArea") as? NSValue,
              let rightValue = screen.value(forKey: "auxiliaryTopRightArea") as? NSValue else {
            return nil
        }
        let left = leftValue.rectValue
        let right = rightValue.rectValue
        let gap = right.minX - left.maxX
        guard gap > 0 else { return nil }

        let top = max(left.maxY, right.maxY)
        let bottom = min(left.minY, right.minY)
        let height = top - bottom
        guard height > 0 else { return nil }
        return NotchGeometry(rect: CGRect(x: left.maxX, y: bottom, width: gap, height: height))
    }
}
