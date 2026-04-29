import Foundation
import SwiftUI

/// v0.1 简化主题包：默认用 glyph 占位，已就绪的状态可挂载逐帧动画。
public struct ThemePackage: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String?
    public let description: String?
    public let glyphs: [PetState: String]
    public let animations: [PetState: FrameAnimation]
    public let accentOverrides: [PetState: ColorToken]

    public init(
        id: String,
        name: String,
        version: String,
        author: String?,
        description: String?,
        glyphs: [PetState: String],
        animations: [PetState: FrameAnimation] = [:],
        accentOverrides: [PetState: ColorToken] = [:]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.glyphs = glyphs
        self.animations = animations
        self.accentOverrides = accentOverrides
    }

    public func glyph(for state: PetState) -> String {
        glyphs[state] ?? state.badgeText
    }

    public func animation(for state: PetState) -> FrameAnimation? {
        animations[state]
    }
}

/// 逐帧 PNG 动画：指向 bundle 内一个目录，里面所有 PNG 按文件名排序作为帧序列。
public struct FrameAnimation: Hashable, Sendable {
    public let resourceDirectory: String
    public let framesPerSecond: Double

    public init(resourceDirectory: String, framesPerSecond: Double) {
        self.resourceDirectory = resourceDirectory
        self.framesPerSecond = framesPerSecond
    }
}

/// 抽象的 RGB token，避免主题层直接依赖 SwiftUI.Color。
public struct ColorToken: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public init(_ r: Double, _ g: Double, _ b: Double) {
        red = r; green = g; blue = b
    }
    public var color: Color { Color(red: red, green: green, blue: blue) }
}
