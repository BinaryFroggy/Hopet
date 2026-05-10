import SwiftUI

/// Preferences 窗口根视图。自绘 PixelTabBar + 内容区，整体跑在 `PixelGridBackground` 背景里，
/// 与桌面宠物气泡 / 刘海条同语言。窗口标题栏由 `PreferencesWindowController` 配置为透明，
/// 让像素背景从顶端铺到底端（红黄绿按钮浮在像素背景上保留系统外观）。
/// See preferences.md §11.5.
public struct PreferencesView: View {
    @ObservedObject var registry: SessionRegistry
    @ObservedObject var themes: ThemeStore
    @ObservedObject var configStore: ConfigStore
    @State private var activeTab: PreferencesTab = .overview
    let hookInstaller: HookInstaller
    let petWindowController: PetWindowController

    public init(
        registry: SessionRegistry,
        themes: ThemeStore,
        hookInstaller: HookInstaller,
        configStore: ConfigStore,
        petWindowController: PetWindowController
    ) {
        self.registry = registry
        self.themes = themes
        self.configStore = configStore
        self.hookInstaller = hookInstaller
        self.petWindowController = petWindowController
    }

    public var body: some View {
        ZStack {
            PixelGridBackground()
            VStack(spacing: 10) {
                // 顶部留白让系统红黄绿按钮浮在像素背景上。
                Color.clear.frame(height: 24)
                PixelTabBar(selection: $activeTab)
                    .padding(.horizontal, 12)
                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .padding(.bottom, 12)
        }
        .frame(minWidth: 760, minHeight: 520)
    }

    @ViewBuilder
    private var content: some View {
        switch activeTab {
        case .overview:
            OverviewTab(registry: registry, controller: petWindowController)
        case .themes:
            ThemesTab(themes: themes)
        case .appearance:
            AppearanceTab(configStore: configStore)
        case .bindings:
            BindingsTab(themes: themes)
        case .hooks:
            HooksTab(installer: hookInstaller, configStore: configStore)
        case .behavior:
            BehaviorTab()
        case .notifications:
            NotificationsTab()
        case .about:
            AboutTab()
        }
    }
}

/// Tab 标识。顺序与 `PixelTabBar` 渲染顺序一致。See preferences.md §2.
enum PreferencesTab: String, CaseIterable, Hashable {
    case overview, themes, appearance, bindings, hooks, behavior, notifications, about

    var label: String {
        switch self {
        case .overview:      return "Overview"
        case .themes:        return "Themes"
        case .appearance:    return "Appearance"
        case .bindings:      return "Bindings"
        case .hooks:         return "Hooks"
        case .behavior:      return "Behavior"
        case .notifications: return "Notifs"
        case .about:         return "About"
        }
    }
}

/// 自绘像素分段 Tab 栏：替代系统 TabView 顶部分段，与气泡按钮同语言。
/// 每个 Tab 是 `PixelButtonStyle(compact: true)`，选中态切到 prominent + candyPink。
/// See preferences.md §11.2.2.
struct PixelTabBar: View {
    @Binding var selection: PreferencesTab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(PreferencesTab.allCases, id: \.self) { tab in
                let active = selection == tab
                Button(tab.label) {
                    selection = tab
                }
                .buttonStyle(PixelButtonStyle(
                    tint: active ? PixelPalette.candyPink : PixelPalette.sky,
                    prominent: active,
                    compact: true
                ))
            }
        }
        .padding(6)
        .pixelChrome(
            cornerRadius: 6,
            accent: PixelPalette.lemon,
            strokeWidth: 1.5,
            strokeColor: PixelPalette.chromeBlue
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
