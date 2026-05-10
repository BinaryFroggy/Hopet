import AppKit
import SwiftUI

@MainActor
public final class PreferencesWindowController {
    private var window: NSWindow?
    private let registry: SessionRegistry
    private let themes: ThemeStore
    private let hookInstaller: HookInstaller
    private let configStore: ConfigStore
    private let petWindowController: PetWindowController

    public init(
        registry: SessionRegistry,
        themes: ThemeStore,
        hookInstaller: HookInstaller,
        configStore: ConfigStore,
        petWindowController: PetWindowController
    ) {
        self.registry = registry
        self.themes = themes
        self.hookInstaller = hookInstaller
        self.configStore = configStore
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
            configStore: configStore,
            petWindowController: petWindowController
        )
        let hosting = NSHostingController(rootView: view)
        let win = NSWindow(contentViewController: hosting)
        win.title = "Hopet"
        // 全尺寸内容 + 透明 titleBar：让像素背景从顶端铺到底端，红黄绿按钮浮在像素底色上保留
        // 系统外观（preferences.md §11.5 / §11.2.3）。
        win.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
        win.titlebarAppearsTransparent = true
        win.titleVisibility = .hidden
        win.isMovableByWindowBackground = true
        win.setContentSize(NSSize(width: 820, height: 560))
        win.minSize = NSSize(width: 760, height: 520)
        win.center()
        window = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
