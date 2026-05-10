import SwiftUI

/// 关于。像素卡片居中展示版本与项目说明，全 monospaced。
/// See preferences.md §11.6.
struct AboutTab: View {
    var body: some View {
        PreferencesPaneScaffold("About") {
            HStack {
                Spacer()
                PixelCard("HOPET", titleTint: PixelPalette.candyPink) {
                    VStack(spacing: 10) {
                        Text("🦭 HOPET")
                            .font(.system(size: 22, weight: .bold, design: .monospaced))
                        Text("v0.1.0 · MVP")
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text("Maps Claude Code & Codex session lifecycle to a desktop pet.")
                            .font(.system(size: 11, design: .monospaced))
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: 360)
                            .foregroundStyle(.secondary)
                        Link("Open feedback", destination: URL(string: "https://github.com/")!)
                            .font(.system(size: 11, design: .monospaced))
                    }
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: 460)
                Spacer()
            }
        }
    }
}
