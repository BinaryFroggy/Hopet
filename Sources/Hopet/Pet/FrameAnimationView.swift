import AppKit
import SwiftUI

struct FrameAnimationView: View {
    let animation: FrameAnimation

    var body: some View {
        TimelineView(.animation(minimumInterval: frameDuration)) { context in
            let frames = FrameImageCache.frames(in: animation.resourceDirectory)
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
        1 / max(animation.framesPerSecond, 1)
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
