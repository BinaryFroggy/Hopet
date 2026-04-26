import SwiftUI

struct AboutTab: View {
    var body: some View {
        VStack(spacing: 12) {
            Text("🦭 Hopet").font(.system(size: 24, weight: .bold))
            Text("v0.1.0 · MVP scaffolding")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Divider().padding(.horizontal, 80)
            Text("把 Claude Code / Codex 的会话生命周期翻译成桌面上的小动物表情。")
                .font(.system(size: 12))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Spacer()
            Link("Open feedback", destination: URL(string: "https://github.com/")!)
                .font(.system(size: 11))
        }
        .padding()
    }
}
