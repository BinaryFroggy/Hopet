import Foundation

/// 内置 Hopi 主题。8 个 PetState 各自接入一段像素风小海豹逐帧动画；
/// glyph 保留作为渲染失败时的文字回退。
public enum DefaultTheme {
    public static let hopi = ThemePackage(
        id: "hopi.default",
        name: "Hopi",
        version: "0.1.0",
        author: "Hopet Team",
        description: "默认主题：所有 PetState 使用像素风小海豹动画。",
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
        let suffix: [PetState: String] = [
            .idle:             "seal-idle",
            .thinking:         "seal-thinking",
            .responding:       "seal-working",
            .toolUse:          "seal-play-ball",
            .permissionPrompt: "seal-permission-prompt",
            .askUser:          "seal-ask-user",
            .completed:        "seal-completed",
            .errorInterrupted: "seal-error-interrupted"
        ]
        return suffix.mapValues {
            FrameAnimation(
                resourceDirectory: "Resources/Themes/Hopi/\($0)",
                framesPerSecond: 8
            )
        }
    }
}
