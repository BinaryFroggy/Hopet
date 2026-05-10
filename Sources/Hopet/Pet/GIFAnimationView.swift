import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// 用户主题动画渲染：直接解码 `.gif` 文件，保留 GIF 内嵌的可变 delay。
/// See preferences.md §6.2.
struct GIFAnimationView: View {
    let url: URL

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
            let frames = GIFFrameCache.frames(at: url)
            if frames.images.isEmpty {
                Color.clear
            } else {
                let elapsed = context.date.timeIntervalSinceReferenceDate
                let phase = elapsed.truncatingRemainder(dividingBy: max(frames.totalDuration, 0.001))
                let index = frames.index(forElapsed: phase)
                Image(nsImage: frames.images[index])
                    .resizable()
                    .interpolation(.none)
                    .antialiased(false)
                    .scaledToFit()
            }
        }
    }
}

/// 解码后的 GIF 帧序列与每帧 duration（秒）。所有 duration 经过下限夹紧，
/// 避免 0 / 极小值在累计相位计算里发散。
struct GIFFrames {
    let images: [NSImage]
    let durations: [TimeInterval]
    let totalDuration: TimeInterval

    /// 根据已经流逝的相位（[0, totalDuration)）定位当前帧 index。
    /// 累加 durations 直到超过 elapsed；O(n) 对几十帧的 GIF 足够。
    func index(forElapsed elapsed: TimeInterval) -> Int {
        var acc: TimeInterval = 0
        for (i, d) in durations.enumerated() {
            acc += d
            if elapsed < acc { return i }
        }
        return durations.count - 1
    }
}

/// 全局 GIF 帧缓存。Key 为 url.path + mtime，文件被替换（重导入）时自动失效。
/// See preferences.md §6.2.
enum GIFFrameCache {
    private static var cache: [String: GIFFrames] = [:]
    private static let empty = GIFFrames(images: [], durations: [], totalDuration: 0)

    static func frames(at url: URL) -> GIFFrames {
        let key = cacheKey(for: url)
        if let hit = cache[key] { return hit }
        let decoded = decode(url)
        cache[key] = decoded
        return decoded
    }

    private static func cacheKey(for url: URL) -> String {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        let mtime = (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
        return "\(url.path)|\(mtime)"
    }

    private static func decode(_ url: URL) -> GIFFrames {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return empty }
        let count = CGImageSourceGetCount(source)
        guard count > 0 else { return empty }

        var images: [NSImage] = []
        var durations: [TimeInterval] = []
        for i in 0..<count {
            guard let cg = CGImageSourceCreateImageAtIndex(source, i, nil) else { continue }
            let size = NSSize(width: CGFloat(cg.width), height: CGFloat(cg.height))
            images.append(NSImage(cgImage: cg, size: size))
            durations.append(frameDuration(source: source, at: i))
        }
        let total = durations.reduce(0, +)
        return GIFFrames(images: images, durations: durations, totalDuration: total)
    }

    private static func frameDuration(source: CGImageSource, at i: Int) -> TimeInterval {
        guard
            let props = CGImageSourceCopyPropertiesAtIndex(source, i, nil) as? [CFString: Any],
            let gif = props[kCGImagePropertyGIFDictionary] as? [CFString: Any]
        else {
            return 0.1
        }
        if let d = gif[kCGImagePropertyGIFUnclampedDelayTime] as? TimeInterval, d > 0 {
            return max(d, 0.02)
        }
        if let d = gif[kCGImagePropertyGIFDelayTime] as? TimeInterval, d > 0 {
            return max(d, 0.02)
        }
        return 0.1
    }
}
