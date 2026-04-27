import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private var router: SceneRouter?
    private var menuBar: MenuBarItem?

    public func applicationDidFinishLaunching(_ notification: Notification) {
        // 菜单栏型 App，不出现在 Dock。
        NSApp.setActivationPolicy(.accessory)

        let router = SceneRouter()
        self.router = router
        router.boot()
        self.menuBar = MenuBarItem(router: router)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        router?.shutdown()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
