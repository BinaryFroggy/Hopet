import AppKit
import Combine

/// 协调 App 内的所有子系统：socket 服务端、定时器、宠物窗口、刘海条、面板。
@MainActor
public final class SceneRouter {
    public let registry: SessionRegistry
    public let themes: ThemeStore
    public let inputCoordinator: InputCoordinator
    public let hookInstaller: HookInstaller
    public let configStore: ConfigStore

    private let aggregator: PetAggregator
    private let thinkingTimer: ThinkingTimer
    private let decayTimer: CompletedDecayTimer
    private let permissionPrompter: PermissionPrompter
    private var router: EventRouter
    private var server: SocketServer?
    private var configCancellables: Set<AnyCancellable> = []

    public let petWindowController: PetWindowController
    public let notchController: NotchWindowController
    public let preferencesController: PreferencesWindowController

    public init() {
        let registry = SessionRegistry()
        let configStore = ConfigStore()
        let themes = ThemeStore(configStore: configStore)
        let prompter = PermissionPrompter(registry: registry)
        let coordinator = InputCoordinator(registry: registry, permissionPrompter: prompter)
        let installer = HookInstaller()
        self.registry = registry
        self.configStore = configStore
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
            configStore: configStore,
            petWindowController: petWindowController
        )
    }

    public func boot() {
        do {
            try HopetPaths.ensureDirectories()
            try? hookInstaller.ensureEmitBinary()

            // 首次安装：落盘默认 config 建立基线（见 preferences.md §6.1）。
            if !FileManager.default.fileExists(atPath: HopetPaths.configFile.path) {
                configStore.current.save()
            }

            applyAppearance(configStore.current.appearance)
            applyListeners(configStore.current.listeners)
            themes.reload()

            // 监听 config 变化：appearance 即时应用，listeners 在 Toggle 翻转时同步装/卸 hooks。
            configStore.$current
                .map(\.appearance)
                .removeDuplicates()
                .sink { [weak self] in self?.applyAppearance($0) }
                .store(in: &configCancellables)
            configStore.$current
                .map(\.listeners)
                .removeDuplicates()
                .sink { [weak self] in self?.applyListeners($0) }
                .store(in: &configCancellables)

            let router = self.router
            let server = SocketServer { data, channel in
                Task { @MainActor in router.handleRaw(data, channel: channel) }
            }
            try server.start()
            self.server = server

            thinkingTimer.start()
            decayTimer.start()
            petWindowController.show()
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
        thinkingTimer.stop()
        decayTimer.stop()
        notchController.hide()
        server?.stop()
    }

    public func openPreferences() { preferencesController.show() }
    public func togglePet()       { petWindowController.toggle() }

    /// 把外观偏好映射到 `NSApp.appearance`：light → .aqua / dark → .darkAqua / system → nil。
    /// See preferences.md §6.4.
    private func applyAppearance(_ appearance: HopetConfig.Appearance) {
        switch appearance {
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    /// 仅当 listener 当前安装态与目标不一致时调用 install/uninstall，避免每次启动重写文件。
    /// Codex 路径失败仅 warn，不影响 Claude 安装与启动（见 preferences.md §6.1）。
    private func applyListeners(_ listeners: HopetConfig.Listeners) {
        sync(.claudeCode, desired: listeners.claudeCode)
        sync(.codex, desired: listeners.codex)
    }

    private func sync(_ tool: AITool, desired: Bool) {
        let installed = hookInstaller.isInstalled(tool)
        guard installed != desired else { return }
        do {
            if desired {
                try hookInstaller.install(tool)
                HopetLog.trace("\(tool.displayName) hooks installed.")
            } else {
                try hookInstaller.uninstall(tool)
                HopetLog.trace("\(tool.displayName) hooks uninstalled.")
            }
        } catch {
            HopetLog.warn("\(tool.displayName) hook sync failed: \(error)")
        }
    }
}
