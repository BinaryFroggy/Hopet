import AppKit
import SwiftUI

/// SwiftUI 包装的 `NSVisualEffectView`，给灵动岛 collapsed 顶条与 expanded 卡片
/// 共用的 macOS 系统磨玻璃背板。
///
/// 用 `.hudWindow` material + `.behindWindow` blendingMode 拿到偏黑色的 HUD 风
/// 模糊，比 `Color.black.opacity(0.85)` 在浅色桌面下更耐看，也保留 macOS 系统
/// 视觉一致性。`cornerRadius` 在外层 SwiftUI `.animation` 触发时随状态切换。
struct VisualEffectBackground: NSViewRepresentable {
    let material: NSVisualEffectView.Material
    let blendingMode: NSVisualEffectView.BlendingMode
    let cornerRadius: CGFloat

    init(
        material: NSVisualEffectView.Material = .hudWindow,
        blendingMode: NSVisualEffectView.BlendingMode = .behindWindow,
        cornerRadius: CGFloat
    ) {
        self.material = material
        self.blendingMode = blendingMode
        self.cornerRadius = cornerRadius
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material
        v.blendingMode = blendingMode
        v.state = .active
        v.wantsLayer = true
        v.layer?.cornerRadius = cornerRadius
        v.layer?.masksToBounds = true
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blendingMode
        v.layer?.cornerRadius = cornerRadius
    }
}
