import SwiftUI

public struct PreferencesView: View {
    @ObservedObject var registry: SessionRegistry
    @ObservedObject var themes: ThemeStore
    let hookInstaller: HookInstaller
    let petWindowController: PetWindowController

    public init(
        registry: SessionRegistry,
        themes: ThemeStore,
        hookInstaller: HookInstaller,
        petWindowController: PetWindowController
    ) {
        self.registry = registry
        self.themes = themes
        self.hookInstaller = hookInstaller
        self.petWindowController = petWindowController
    }

    public var body: some View {
        TabView {
            OverviewTab(registry: registry, controller: petWindowController)
                .tabItem { Label("Overview", systemImage: "rectangle.grid.2x2") }
            ThemesTab(themes: themes)
                .tabItem { Label("Themes", systemImage: "paintbrush") }
            BindingsTab(themes: themes)
                .tabItem { Label("Bindings", systemImage: "link") }
            HooksTab(installer: hookInstaller)
                .tabItem { Label("Hooks", systemImage: "bolt.fill") }
            BehaviorTab()
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
            NotificationsTab()
                .tabItem { Label("Notifications", systemImage: "bell") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(minWidth: 600, minHeight: 420)
        .padding()
    }
}
