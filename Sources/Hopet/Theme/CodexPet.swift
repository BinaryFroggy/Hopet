import AppKit
import Foundation
import ImageIO

/// Codex pet 的前 9 行标准动画。v2 在其后追加 2 行注视方向，不改变这些行的顺序。
public enum CodexPetAnimation: Int, CaseIterable, Codable, Hashable, Sendable {
    case idle
    case runRight
    case runLeft
    case waving
    case jumping
    case failed
    case waiting
    case running
    case review
}

/// Codex pet 图集版本的几何信息。v1 为旧 8×9 包；v2 为当前 8×11 包，后两行只提供
/// 指针朝向，Hopet 的会话状态渲染不会使用它们。
public struct CodexPetSpriteLayout: Hashable, Sendable {
    public let spriteVersionNumber: Int
    public let rows: Int

    public static let columns = 8
    public static let cellWidth = 192
    public static let cellHeight = 208

    public static let v1 = CodexPetSpriteLayout(spriteVersionNumber: 1, rows: 9)
    public static let v2 = CodexPetSpriteLayout(spriteVersionNumber: 2, rows: 11)

    public var spriteSheetWidth: Int { Self.columns * Self.cellWidth }
    public var spriteSheetHeight: Int { rows * Self.cellHeight }

    public static func resolve(spriteVersionNumber: Int?) -> CodexPetSpriteLayout? {
        switch spriteVersionNumber ?? 1 {
        case 1: return .v1
        case 2: return .v2
        default: return nil
        }
    }
}

/// Codex pet 的描述文件。`spritesheetPath` 必须指向包根目录下的 spritesheet.png 或 spritesheet.webp，
/// 避免导入过程中解析离开用户所选目录的路径。
public struct CodexPetManifest: Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let description: String
    public let spritesheetPath: String
    /// v1 包的可选分类；Codex v2 manifest 不再要求此字段。
    public let kind: String?
    /// 缺失时按 v1 处理；当前 Codex 导出的包使用 2。
    public let spriteVersionNumber: Int?

    public var layout: CodexPetSpriteLayout? {
        CodexPetSpriteLayout.resolve(spriteVersionNumber: spriteVersionNumber)
    }
}

/// 已完成格式校验的 Codex pet 包，供导入 sheet 暂存直至用户确认导入。
public struct CodexPetPackage: Hashable, Sendable {
    public let directory: URL
    public let spriteSheetURL: URL
    public let manifest: CodexPetManifest
    public let layout: CodexPetSpriteLayout
}

/// Codex 动作行 → Hopet 会话状态的固定默认映射。
/// runLeft 是移动方向而不是会话语义；Hopet 的宠物不按会话移动，因此不把它映射为状态。
public enum CodexPetStateMapping {
    public static func animation(for state: PetState) -> CodexPetAnimation {
        switch state {
        case .idle:             return .idle
        case .thinking:         return .review
        case .responding:       return .running
        case .toolUse:          return .runRight
        case .permissionPrompt: return .waiting
        case .askUser:          return .waving
        case .completed:        return .jumping
        case .errorInterrupted: return .failed
        }
    }
}

/// 裁切后的单行动画。v2 保留 Codex 定义的逐帧时长；v1 没有时长元数据，统一按 8 fps 播放。
struct CodexPetFrames {
    let images: [NSImage]
    let durations: [TimeInterval]
    let totalDuration: TimeInterval

    static let empty = CodexPetFrames(images: [], durations: [], totalDuration: 0)

    func index(forElapsed elapsed: TimeInterval) -> Int {
        var accumulated: TimeInterval = 0
        for (index, duration) in durations.enumerated() {
            accumulated += duration
            if elapsed < accumulated { return index }
        }
        return images.indices.last ?? 0
    }
}

enum CodexPetSpriteSheetError: LocalizedError {
    case invalidDimensions
    case emptyAnimation(CodexPetAnimation)
    case nonContiguousFrames(CodexPetAnimation)
    case unexpectedFrameCount(CodexPetAnimation, expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case .invalidDimensions:
            return "spritesheet dimensions do not match its declared version"
        case .emptyAnimation(let row):
            return "\(row) has no visible animation frames"
        case .nonContiguousFrames(let row):
            return "\(row) contains a blank frame before a later visible frame"
        case let .unexpectedFrameCount(row, expected, actual):
            return "\(row) has \(actual) visible frames; Codex v2 requires \(expected)"
        }
    }
}

/// 一次性解码并切分 Codex sprite sheet。缓存 key 纳入 mtime，重导入覆盖资源后会自然失效。
enum CodexPetSpriteSheetCache {
    private static var cache: [String: CodexPetFrames] = [:]

    static func frames(at url: URL, row: CodexPetAnimation, layout: CodexPetSpriteLayout) -> CodexPetFrames {
        let key = "\(url.path)|\(modificationTime(of: url))|\(row.rawValue)|\(layout.spriteVersionNumber)"
        if let cached = cache[key] { return cached }
        let frames = (try? decode(url: url, row: row, layout: layout)) ?? .empty
        cache[key] = frames
        return frames
    }

    static func validateStandardAnimations(at url: URL, layout: CodexPetSpriteLayout) throws {
        for row in CodexPetAnimation.allCases {
            _ = try decode(url: url, row: row, layout: layout)
        }
    }

    private static func modificationTime(of url: URL) -> TimeInterval {
        let attrs = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0
    }

    private static func decode(url: URL, row: CodexPetAnimation, layout: CodexPetSpriteLayout) throws -> CodexPetFrames {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let sheet = CGImageSourceCreateImageAtIndex(source, 0, nil),
              sheet.width == layout.spriteSheetWidth,
              sheet.height == layout.spriteSheetHeight
        else { throw CodexPetSpriteSheetError.invalidDimensions }

        var images: [NSImage] = []
        var encounteredBlank = false
        for column in 0..<CodexPetSpriteLayout.columns {
            let rect = CGRect(
                x: column * CodexPetSpriteLayout.cellWidth,
                y: row.rawValue * CodexPetSpriteLayout.cellHeight,
                width: CodexPetSpriteLayout.cellWidth,
                height: CodexPetSpriteLayout.cellHeight
            )
            guard let frame = sheet.cropping(to: rect) else {
                throw CodexPetSpriteSheetError.invalidDimensions
            }
            if hasVisiblePixels(frame) {
                guard !encounteredBlank else {
                    throw CodexPetSpriteSheetError.nonContiguousFrames(row)
                }
                images.append(
                    NSImage(
                        cgImage: frame,
                        size: NSSize(width: CodexPetSpriteLayout.cellWidth, height: CodexPetSpriteLayout.cellHeight)
                    )
                )
            } else {
                encounteredBlank = true
            }
        }

        guard !images.isEmpty else { throw CodexPetSpriteSheetError.emptyAnimation(row) }
        let durations = try durations(for: row, frameCount: images.count, layout: layout)
        return CodexPetFrames(
            images: images,
            durations: durations,
            totalDuration: durations.reduce(0, +)
        )
    }

    private static func durations(
        for row: CodexPetAnimation,
        frameCount: Int,
        layout: CodexPetSpriteLayout
    ) throws -> [TimeInterval] {
        guard layout.spriteVersionNumber == 2 else {
            return Array(repeating: 1.0 / 8.0, count: frameCount)
        }
        let milliseconds: [Int]
        switch row {
        case .idle:     milliseconds = [280, 110, 110, 140, 140, 320]
        case .runRight, .runLeft:
            milliseconds = [120, 120, 120, 120, 120, 120, 120, 220]
        case .waving:   milliseconds = [140, 140, 140, 280]
        case .jumping:  milliseconds = [140, 140, 140, 140, 280]
        case .failed:   milliseconds = [140, 140, 140, 140, 140, 140, 140, 240]
        case .waiting:  milliseconds = [150, 150, 150, 150, 150, 260]
        case .running:  milliseconds = [120, 120, 120, 120, 120, 220]
        case .review:   milliseconds = [150, 150, 150, 150, 150, 280]
        }
        guard frameCount == milliseconds.count else {
            throw CodexPetSpriteSheetError.unexpectedFrameCount(
                row,
                expected: milliseconds.count,
                actual: frameCount
            )
        }
        return milliseconds.map { TimeInterval($0) / 1_000 }
    }

    private static func hasVisiblePixels(_ image: CGImage) -> Bool {
        let width = image.width
        let height = image.height
        let bytesPerRow = width * 4
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let data = context.data else { return false }
        let pixels = data.bindMemory(to: UInt8.self, capacity: bytesPerRow * height)
        return stride(from: 3, to: bytesPerRow * height, by: 4).contains { pixels[$0] > 0 }
    }
}
