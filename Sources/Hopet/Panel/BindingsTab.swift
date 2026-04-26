import SwiftUI

struct BindingsTab: View {
    @ObservedObject var themes: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AI ↔ Theme Bindings").font(.headline)
            Text("v0.1 全局单一主题（所有 AI 共用）。v0.2 起开放每个 AI 单独绑定。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Picker("Global theme", selection: $themes.activeThemeId) {
                ForEach(themes.themes, id: \.id) { Text($0.name).tag($0.id) }
            }
            .pickerStyle(.menu)
            Divider()
            ForEach(SessionRegistry.activeTools, id: \.self) { tool in
                HStack {
                    Text(tool.displayName).font(.system(size: 12, weight: .semibold)).frame(width: 100, alignment: .leading)
                    Text("→ \(themes.activeTheme.name)").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Text("(globally bound)").font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .padding(8)
    }
}
