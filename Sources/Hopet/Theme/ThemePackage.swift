import Foundation
import SwiftUI

/// v0.1 简化的主题包：不包含动画帧，仅给每个 PetState 提供
/// glyph（emoji 或 ASCII 字形）+ accent color override。
/// 后续接入 SpriteKit 动画时，再扩展 `frames: [URL]` 字段。
public struct ThemePackage: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String?
    public let description: String?
    public let glyphs: [PetState: String]
    public let accentOverrides: [PetState: ColorToken]

    public init(
        id: String,
        name: String,
        version: String,
        author: String?,
        description: String?,
        glyphs: [PetState: String],
        accentOverrides: [PetState: ColorToken] = [:]
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.glyphs = glyphs
        self.accentOverrides = accentOverrides
    }

    public func glyph(for state: PetState) -> String {
        glyphs[state] ?? state.badgeText
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
