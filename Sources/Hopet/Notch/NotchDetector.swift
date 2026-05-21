import AppKit

/// 检测主屏是否有刘海，并给出灵动岛在 collapsed / expanded 两种态下的 rect。
public enum NotchDetector {
    public struct Layout {
        public let hasNotch: Bool
        public let screen: NSScreen
        /// collapsed 态：紧贴屏顶的横条（刘海下沿对齐或菜单栏下沿对齐）。
        public let topBarRect: CGRect
        /// expanded 态：从 visibleFrame.maxY 向下延伸的下拉卡片区域。
        /// 横向居中、宽度 <= 720pt、高度 <= visibleFrame.height - 40，
        /// 保证永远不越过菜单栏。
        public let expandedRect: CGRect
    }

    /// expanded 态最大宽度（pt）。超出会侵占屏边距视觉上不像"灵动岛下拉"。
    private static let expandedMaxWidth: CGFloat = 720
    /// expanded 态最大高度上限（pt）。配合 visibleFrame.height - 40 取小值。
    private static let expandedMaxHeight: CGFloat = 520
    /// expanded 区域距屏边的最小留白。
    private static let expandedSideMargin: CGFloat = 80

    public static func detect() -> Layout? {
        guard let screen = NSScreen.main else { return nil }
        let safeTop = screen.safeAreaInsets.top
        let frame = screen.frame
        let visible = screen.visibleFrame

        let collapsedHeight: CGFloat = max(28, safeTop)
        let topBar = CGRect(
            x: frame.midX - 280,
            y: frame.maxY - collapsedHeight,
            width: 560,
            height: collapsedHeight
        )

        let expandedWidth = min(expandedMaxWidth, max(360, visible.width - expandedSideMargin * 2))
        let expandedHeight = min(expandedMaxHeight, max(180, visible.height - 40))
        let expanded = CGRect(
            x: visible.midX - expandedWidth / 2,
            y: visible.maxY - expandedHeight,
            width: expandedWidth,
            height: expandedHeight
        )

        return Layout(
            hasNotch: safeTop > 0,
            screen: screen,
            topBarRect: topBar,
            expandedRect: expanded
        )
    }
}
