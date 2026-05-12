import SwiftUI

/// 主题选择：全局单一主题。所有 AI 工具共用同一只宠物、同一套动画。
/// 下拉选择全局主题；Picker 弹出菜单保持系统外观（preferences.md §11.2.3 的不像素化部件清单）。
/// See preferences.md §11.6.
struct BindingsTab: View {
    @ObservedObject var themes: ThemeStore

    var body: some View {
        PreferencesPaneScaffold("Bindings") {
            PixelCard("GLOBAL THEME", titleTint: PixelPalette.sky) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hopet now has a single global pet; all AI tools share this theme.")
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
        }
    }
}
