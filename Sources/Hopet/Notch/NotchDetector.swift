import AppKit

/// 检测主屏是否有刘海，并给出刘海下边界 rect。
public enum NotchDetector {
    public struct Layout {
        public let hasNotch: Bool
        public let screen: NSScreen
        public let topBarRect: CGRect       // 紧贴屏顶的横条
    }

    public static func detect() -> Layout? {
        guard let screen = NSScreen.main else { return nil }
        let safeTop = screen.safeAreaInsets.top
        let frame = screen.frame
        let height: CGFloat = max(28, safeTop)
        let topBar = CGRect(
            x: frame.midX - 280,
            y: frame.maxY - height,
            width: 560,
            height: height
        )
        return Layout(hasNotch: safeTop > 0, screen: screen, topBarRect: topBar)
    }
}
