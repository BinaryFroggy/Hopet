import SwiftUI

/// AI ↔ Theme 绑定：v0.1 全局单一主题。每个 AI 都用 `themes.activeTheme` 渲染。
/// 下拉选择全局主题；Picker 弹出菜单保持系统外观（preferences.md §11.2.3 的不像素化部件清单）。
/// See preferences.md §11.6.
struct BindingsTab: View {
    @ObservedObject var themes: ThemeStore

    var body: some View {
        PreferencesPaneScaffold("Bindings") {
            PixelCard("GLOBAL THEME", titleTint: PixelPalette.sky) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("v0.1 ships a single global theme for every AI. Per-tool bindings arrive in v0.2.")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Picker("", selection: $themes.activeThemeId) {
                        ForEach(themes.themes, id: \.id) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .font(.system(size: 12, design: .monospaced))
                }
            }

            PixelCard("PER-TOOL", titleTint: PixelPalette.mint) {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(SessionRegistry.activeTools, id: \.self) { tool in
                        HStack {
                            Text(tool.displayName)
                                .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                .frame(width: 120, alignment: .leading)
                            Text("→ \(themes.activeTheme.name)")
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text("(globally bound)")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
            }
        }
    }
}
