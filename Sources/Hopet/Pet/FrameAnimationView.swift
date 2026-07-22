import AppKit
import SwiftUI

/// 帧动画 dispatcher：按 `FrameAnimation` 类型分发到 Bundle PNG、GIF 或 Codex 图集渲染器。
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
        case let .codexPetSpriteSheet(url, row, layout, fps):
            CodexPetSpriteSheetView(url: url, row: row, layout: layout, fps: fps)
        }
    }
}

/// Codex pet 的图集渲染器。读取连续的可见帧，并保留 v2 定义的逐帧时长；不在导入时转码 GIF，
/// 这样保留了原始透明通道并避免额外的磁盘副本。
private struct CodexPetSpriteSheetView: View {
    let url: URL
    let row: CodexPetAnimation
    let layout: CodexPetSpriteLayout
    let fps: Double

    var body: some View {
        TimelineView(.animation(minimumInterval: timelineInterval)) { context in
            let frames = CodexPetSpriteSheetCache.frames(at: url, row: row, layout: layout)
            if frames.images.isEmpty {
                Color.clear
            } else {
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let phase = elapsed.truncatingRemainder(dividingBy: max(frames.totalDuration, 0.001))
                Image(nsImage: frames.images[frames.index(forElapsed: phase)])
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            }
        }
    }

    private var timelineInterval: TimeInterval {
        layout.spriteVersionNumber == 2 ? 1.0 / 60.0 : 1 / max(fps, 1)
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
        let resourceDirectory = Bundle.main.resourceURL?
            .appendingPathComponent("Hopet_Hopet.bundle", isDirectory: true)
            .appendingPathComponent(directory, isDirectory: true)
        let urls = (resourceDirectory.flatMap {
            try? FileManager.default.contentsOfDirectory(
                at: $0,
                includingPropertiesForKeys: nil
            )
        } ?? [])
            .filter { $0.pathExtension == "png" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        let images = urls.compactMap { NSImage(contentsOf: $0) }
        cache[directory] = images
        return images
    }
}
