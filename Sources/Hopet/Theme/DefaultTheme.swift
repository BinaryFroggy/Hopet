import Foundation

/// 内置 Hopi 主题。v0.1 用 emoji 占位海豹动画。
public enum DefaultTheme {
    public static let hopi = ThemePackage(
        id: "hopi.default",
        name: "Hopi",
        version: "0.1.0",
        author: "Hopet Team",
        description: "v0.1 占位主题：用文字徽章代替海豹精灵图。",
        glyphs: [
            .idle:             "🦭 zZz",
            .responding:       "🦭 ⌨️",
            .thinking:         "🦭 💭",
            .toolUse:          "🦭 🛠",
            .permissionPrompt: "🦭 ⚠️",
            .askUser:          "🦭 ❓",
            .completed:        "🦭 ✓",
            .errorInterrupted: "🦭 ⚡️"
        ]
    )
}
