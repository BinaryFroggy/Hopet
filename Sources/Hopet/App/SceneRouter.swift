import AppKit

/// 协调 App 内的所有子系统：socket 服务端、定时器、宠物窗口、刘海条、面板。
@MainActor
public final class SceneRouter {
    public let registry: SessionRegistry
    public let themes: ThemeStore
    public let inputCoordinator: InputCoordinator
    public let hookInstaller: HookInstaller

    private let aggregator: PetAggregator
    private let thinkingTimer: ThinkingTimer
    private let decayTimer: CompletedDecayTimer
    private let permissionPrompter: PermissionPrompter
    private var router: EventRouter
    private var server: SocketServer?

    public let petWindowController: PetWindowController
    public let notchController: NotchWindowController
    public let preferencesController: PreferencesWindowController

    public init() {
        let registry = SessionRegistry()
        let themes = ThemeStore()
        let prompter = PermissionPrompter(registry: registry)
        let coordinator = InputCoordinator(registry: registry, permissionPrompter: prompter)
        let installer = HookInstaller()
        self.registry = registry
        self.themes = themes
        self.inputCoordinator = coordinator
        self.hookInstaller = installer

        self.aggregator = PetAggregator(registry: registry)
        self.thinkingTimer = ThinkingTimer(registry: registry)
        self.decayTimer = CompletedDecayTimer(registry: registry)
        self.permissionPrompter = prompter
        self.router = EventRouter(registry: registry, permissionPrompter: prompter)

        self.petWindowController = PetWindowController(
            registry: registry,
            themes: themes,
            inputCoordinator: coordinator
        )
        self.notchController = NotchWindowController(registry: registry)
        self.preferencesController = PreferencesWindowController(
            registry: registry,
            themes: themes,
            hookInstaller: installer,
            petWindowController: petWindowController
        )
    }

    public func boot() {
        do {
            try HopetPaths.ensureDirectories()
            try? hookInstaller.ensureEmitBinary()

            // 启动即自动安装 / 升级 Claude hooks（幂等，已存在的会被覆盖最新版本）。
            do {
                try hookInstaller.install(.claudeCode)
                HopetLog.trace("claude hooks installed/refreshed.")
            } catch {
                HopetLog.trace("claude hooks install failed: \(error)")
            }

            // restore recent sessions
            for session in PersistentStore.loadRecent() {
                registry.upsert(session)
            }

            let router = self.router
            let server = SocketServer { data, reply in
                Task { @MainActor in router.handleRaw(data, reply: reply) }
            }
            try server.start()
            self.server = server

            thinkingTimer.start()
            decayTimer.start()
            petWindowController.showAll()
            // 刘海条暂不展示，等三态/降级顶条视觉打磨完再开。controller / wiring 保留。
            // notchController.show()
            HopetLog.info("Hopet booted.")
            HopetLog.trace("booted ok.")
        } catch {
            HopetLog.error("boot failed: \(error)")
            HopetLog.trace("boot failed: \(error)")
        }
    }

    public func shutdown() {
        PersistentStore.save(Array(registry.sessions.values))
        thinkingTimer.stop()
        decayTimer.stop()
        notchController.hide()
        server?.stop()
    }

    public func openPreferences() { preferencesController.show() }
    public func toggleAllPets()   { petWindowController.toggleAll() }
}
