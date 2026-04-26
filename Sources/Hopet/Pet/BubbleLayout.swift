import Foundation
import CoreGraphics

/// 会话气泡环绕布局算法（架构文档 §12.4）。
public enum BubbleLayout {
    public struct Params {
        public var petRadius: CGFloat = 64
        public var bubbleRadius: CGFloat = 32
        public var gap: CGFloat = 16
        public var maxBubblesPerRing: Int = 6
        public var ringAngularOffsetDegrees: CGFloat = 30

        public init() {}
    }

    public struct Slot {
        public let ring: Int
        public let angleDegrees: Double
        public let offsetX: CGFloat
        public let offsetY: CGFloat
    }

    public static func radius(forRing ring: Int, params: Params = .init()) -> CGFloat {
        params.petRadius
            + params.gap
            + CGFloat(2 * ring + 1) * params.bubbleRadius
            + CGFloat(ring) * params.gap
    }

    public static func slots(count: Int, params: Params = .init()) -> [Slot] {
        guard count > 0 else { return [] }
        var slots: [Slot] = []
        slots.reserveCapacity(count)

        var index = 0
        var ring = 0
        while index < count {
            let remaining = count - index
            let inThisRing = min(params.maxBubblesPerRing, remaining)
            let r = radius(forRing: ring, params: params)
            let baseOffset = Double(params.ringAngularOffsetDegrees) * Double(ring)
            for k in 0..<inThisRing {
                let angle = (360.0 / Double(params.maxBubblesPerRing)) * Double(k) + baseOffset
                let radians = angle * .pi / 180
                let x = CGFloat(cos(radians)) * r
                let y = CGFloat(sin(radians)) * r
                slots.append(Slot(ring: ring, angleDegrees: angle, offsetX: x, offsetY: y))
            }
            index += inThisRing
            ring += 1
        }
        return slots
    }
}
