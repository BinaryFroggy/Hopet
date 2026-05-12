import Foundation

/// 内置 Hopi 主题。8 个 PetState 各自接入一段像素风小海豹逐帧动画；
/// glyph 保留作为渲染失败时的文字回退。
public enum DefaultTheme {
    public static let hopi = ThemePackage(
        id: "hopi.default",
        name: "Hopi",
        version: "0.1.0",
        author: "Hopet Team",
        description: "Default theme: pixel-art seal animations for every PetState.",
        glyphs: [
            .idle:             "🦭 zZz",
            .responding:       "🦭 ⌨️",
            .thinking:         "🦭 💭",
            .toolUse:          "🦭 🛠",
            .permissionPrompt: "🦭 ⚠️",
            .askUser:          "🦭 ❓",
            .completed:        "🦭 ✓",
            .errorInterrupted: "🦭 ⚡️"
        ],
        animations: hopiAnimations()
    )

    private static func hopiAnimations() -> [PetState: FrameAnimation] {
        // 目录名严格对齐 PetState.rawValue（与 user theme manifest.json 的 animation
        // key 同一套 kebab-case slug），字典只承担 PetState → 目录的拼接。
        // seal-responding 的帧已经在 sprite 阶段按 0.82 缩好并居中（详见
        // scripts/build-pet-animation.py 的 --scale 用法），渲染层不再做二次缩放。
        let suffix: [PetState: String] = [
            .idle:             "seal-idle",
            .thinking:         "seal-thinking",
            .responding:       "seal-responding",
            .toolUse:          "seal-tool-use",
            .permissionPrompt: "seal-permission-prompt",
            .askUser:          "seal-ask-user",
            .completed:        "seal-completed",
            .errorInterrupted: "seal-error-interrupted"
        ]
        return suffix.mapValues {
            FrameAnimation.bundlePNG(
                directory: "Resources/Themes/Hopi/\($0)",
                framesPerSecond: 8
            )
        }
    }
}
