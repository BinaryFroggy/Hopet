import SwiftUI

/// 外观偏好：明亮 / 深色 / 跟随系统。即时生效，落盘到 `~/.hopet/config.json`。
/// See preferences.md §6.4 / §11.6.
struct AppearanceTab: View {
    @ObservedObject var configStore: ConfigStore

    var body: some View {
        PreferencesPaneScaffold("Appearance") {
            PixelCard("DISPLAY MODE", titleTint: PixelPalette.candyPink) {
                VStack(alignment: .leading, spacing: 14) {
                    PixelSegmentedControl(
                        selection: Binding(
                            get: { configStore.current.appearance },
                            set: { newValue in
                                configStore.update { $0.appearance = newValue }
                            }
                        ),
                        options: [
                            (.light,  "Light"),
                            (.dark,   "Dark"),
                            (.system, "System"),
                        ]
                    )

                    Text(hint)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var hint: String {
        switch configStore.current.appearance {
        case .light:  return "Force Light. App ignores system appearance changes."
        case .dark:   return "Force Dark. App ignores system appearance changes."
        case .system: return "Follow System. Pet, notch, and panels switch with macOS."
        }
    }
}
