import AppKit
import SwiftUI

/// 帧动画 dispatcher：按 `FrameAnimation` 类型分发到 Bundle PNG 渲染器或 GIF 渲染器。
/// 调用方（如 PetStageView）API 形态保持不变。
/// See preferences.md §6.2.
struct FrameAnimationView: View {
    let animation: FrameAnimation

    var body: some View {
        switch animation {
        case let .bundlePNG(directory, fps):
            BundleFrameRenderer(directory: directory, fps: fps)
        case let .gifFile(url):
            GIFAnimationView(url: url)
        }
    }
}

/// 内置主题用：从 Bundle.module 子目录加载 PNG 帧序列，按文件名排序作为帧。
private struct BundleFrameRenderer: View {
    let directory: String
    let fps: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: frameDuration)) { context in
            let frames = FrameImageCache.frames(in: directory)
            if frames.isEmpty {
                Color.clear
            } else {
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let index = Int((elapsed / frameDuration).rounded(.down)) % frames.count
                Image(nsImage: frames[index])
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            }
        }
    }

    private var frameDuration: TimeInterval {
        // fps=0 或负值会让 TimelineView 死循环；统一夹到 1。
        1 / max(fps, 1)
    }
}

private enum FrameImageCache {
    private static var cache: [String: [NSImage]] = [:]

    static func frames(in directory: String) -> [NSImage] {
        if let cached = cache[directory] { return cached }
        let urls = (Bundle.module.urls(forResourcesWithExtension: "png", subdirectory: directory) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let images = urls.compactMap { NSImage(contentsOf: $0) }
        cache[directory] = images
        return images
    }
}
