import AppKit

@MainActor
public final class MenuBarItem {
    private let item: NSStatusItem
    private let router: SceneRouter

    public init(router: SceneRouter) {
        self.router = router
        self.item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = item.button {
            if let icon = MenuBarItem.loadStatusBarIcon() {
                button.image = icon
                button.title = ""
            } else {
                button.title = "🦭"
            }
            button.toolTip = "Hopet"
        }

        let menu = NSMenu()
        menu.addItem(makeItem(title: "Open Preferences…", action: #selector(openPrefs), key: ","))
        menu.addItem(makeItem(title: "Toggle Pet Visibility", action: #selector(togglePets), key: "h"))
        menu.addItem(.separator())
        menu.addItem(makeItem(title: "Quit Hopet", action: #selector(quit), key: "q"))
        item.menu = menu
    }

    private func makeItem(title: String, action: Selector, key: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openPrefs() { router.openPreferences() }
    @objc private func togglePets() { router.togglePet() }
    @objc private func quit() { NSApp.terminate(nil) }

    private static func loadStatusBarIcon() -> NSImage? {
        let iconURL = Bundle.main.resourceURL?
            .appendingPathComponent("Hopet_Hopet.bundle/Resources/StatusBarIcon.png")
        guard let url = iconURL,
              let image = NSImage(contentsOf: url)
        else { return nil }
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }
}
