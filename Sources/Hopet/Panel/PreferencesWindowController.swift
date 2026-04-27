import AppKit
import SwiftUI

@MainActor
public final class PreferencesWindowController {
    private var window: NSWindow?
    private let registry: SessionRegistry
    private let themes: ThemeStore
    private let hookInstaller: HookInstaller
    private let petWindowController: PetWindowController

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

    public func show() {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = PreferencesView(
            registry: registry,
            themes: themes,
            hookInstaller: hookInstaller,
            petWindowController: petWindowController
        )
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Hopet Preferences"
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        win.setContentSize(NSSize(width: 720, height: 480))
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
