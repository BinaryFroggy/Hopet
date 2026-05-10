import Foundation
import SwiftUI

/// v0.1 简化主题包：默认用 glyph 占位，已就绪的状态可挂载逐帧动画。
/// `isUserProvided` 区分内置与 ~/.hopet/themes 来源；后者可在 ThemesTab 删除。
public struct ThemePackage: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let version: String
    public let author: String?
    public let description: String?
    public let glyphs: [PetState: String]
    public let animations: [PetState: FrameAnimation]
    public let accentOverrides: [PetState: ColorToken]
    public let isUserProvided: Bool
    public let sourceDirectory: URL?

    public init(
        id: String,
        name: String,
        version: String,
        author: String?,
        description: String?,
        glyphs: [PetState: String],
        animations: [PetState: FrameAnimation] = [:],
        accentOverrides: [PetState: ColorToken] = [:],
        isUserProvided: Bool = false,
        sourceDirectory: URL? = nil
    ) {
        self.id = id
        self.name = name
        self.version = version
        self.author = author
        self.description = description
        self.glyphs = glyphs
        self.animations = animations
        self.accentOverrides = accentOverrides
        self.isUserProvided = isUserProvided
        self.sourceDirectory = sourceDirectory
    }

    public func glyph(for state: PetState) -> String {
        glyphs[state] ?? state.badgeText
    }

    public func animation(for state: PetState) -> FrameAnimation? {
        animations[state]
    }
}

/// 逐帧动画来源：内置主题用 PNG 帧目录（Bundle.module），用户主题用单个 GIF 文件。
/// See preferences.md §4.1.
public enum FrameAnimation: Hashable, Sendable {
    case bundlePNG(directory: String, framesPerSecond: Double)
    case gifFile(url: URL)
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
