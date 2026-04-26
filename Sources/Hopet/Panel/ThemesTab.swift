import SwiftUI

struct ThemesTab: View {
    @ObservedObject var themes: ThemeStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Installed Themes").font(.headline)
            ForEach(themes.themes, id: \.id) { t in
                HStack(alignment: .top, spacing: 12) {
                    Text("🦭")
                        .font(.system(size: 36))
                        .frame(width: 48, height: 48)
                        .background(Color.gray.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(t.name).font(.system(size: 13, weight: .semibold))
                            Text("v\(t.version)").font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        if let desc = t.description {
                            Text(desc).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Text("id: \(t.id)").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    if themes.activeThemeId == t.id {
                        Text("Active").font(.caption).foregroundStyle(.green)
                    } else {
                        Button("Apply") { themes.activeThemeId = t.id }
                    }
                }
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(Color.gray.opacity(0.05)))
            }
            Text("v0.1 暂不支持导入 .hopettheme，将在 v0.2 启用（含 zip slip 防护）。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(8)
    }
}
