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
    private let codexVscodeWatcher: CodexVscodeSessionWatcher
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
        let eventRouter = EventRouter(
            registry: registry,
            permissionPrompter: prompter,
            isToolListening: { [weak configStore] tool in
                configStore?.current.listeners[tool] ?? true
            }
        )
        self.router = eventRouter
        self.codexVscodeWatcher = CodexVscodeSessionWatcher(router: eventRouter)

        self.petWindowController = PetWindowController(
            registry: registry,
            themes: themes,
            inputCoordinator: coordinator
        )
        self.notchController = NotchWindowController(
            registry: registry,
            inputCoordinator: coordinator,
            onUserRequestedClose: {
                // 用户点灵动岛右上角关闭：写持久化设置，让 BehaviorTab 的开关视觉
                // 与下次启动行为都同步反映为 OFF。下面的 NotificationCenter sink
                // 会接到 didChangeNotification 调 hide() 真正关掉窗口。
                UserDefaults.standard.set(false, forKey: "notch.enabled")
            }
        )
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
            ensureHooksInstalled()
            themes.reload()

            configStore.$current
                .map(\.appearance)
                .removeDuplicates()
                .sink { [weak self] in self?.applyAppearance($0) }
                .store(in: &configCancellables)

            // @Published 在 willSet 阶段 emit——sink 拿到的 configStore.current 仍是旧值，
            // 必须用闭包参数里的新 listeners，否则 toggle off 后 sweep 看到的还是 on。
            configStore.$current
                .map(\.listeners)
                .removeDuplicates()
                .sink { [weak self] listeners in self?.enforceListenerMute(listeners: listeners) }
                .store(in: &configCancellables)

            // pending 清空 / 状态切换时再扫一遍，让 toggle off 期间挂起的会话在挂起
            // 解除瞬间被清掉。.added 不会触发 mute，.removed 会无限递归——都跳过。
            registry.mutations
                .compactMap { mut -> Void? in
                    switch mut {
                    case .fieldsUpdated, .stateChanged: return ()
                    case .added, .removed: return nil
                    }
                }
                .sink { [weak self] _ in
                    guard let self else { return }
                    let listeners = self.configStore.current.listeners
                    // 两个 listener 都开着时无人会被静音，跳过 activeSessions 扫描。
                    guard !listeners.claudeCode || !listeners.codex else { return }
                    self.enforceListenerMute(listeners: listeners)
                }
                .store(in: &configCancellables)

            let router = self.router
            let server = SocketServer { data, channel in
                Task { @MainActor in router.handleRaw(data, channel: channel) }
            }
            try server.start()
            self.server = server

            thinkingTimer.start()
            decayTimer.start()
            codexVscodeWatcher.start()
            wirePetVisibility()
            wireNotchVisibility()
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
        codexVscodeWatcher.stop()
        notchController.hide()
        server?.stop()
    }

    public func openPreferences() { preferencesController.show() }
    public func togglePet() {
        UserDefaults.standard.set(!petWindowController.isVisible, forKey: "pet.visible")
    }

    /// 把外观偏好映射到 `NSApp.appearance`：light → .aqua / dark → .darkAqua / system → nil。
    /// See preferences.md §6.4.
    private func applyAppearance(_ appearance: HopetConfig.Appearance) {
        switch appearance {
        case .light:  NSApp.appearance = NSAppearance(named: .aqua)
        case .dark:   NSApp.appearance = NSAppearance(named: .darkAqua)
        case .system: NSApp.appearance = nil
        }
    }

    /// 启动时确保所有已识别 AI 工具的 hook 都已落盘。已安装则跳过（避免每次启动重写文件与
    /// 堆积备份）。listener toggle 不再影响这里——toggle 只在 EventRouter 入口做静音。
    /// 真正卸载 Hopet hook 走 Hooks Tab 的显式入口（v0.3 计划）。
    private func ensureHooksInstalled() {
        for tool in AITool.recognized {
            installIfNeeded(tool)
        }
    }

    private func installIfNeeded(_ tool: AITool) {
        guard !hookInstaller.isInstalled(tool) else { return }
        do {
            try hookInstaller.install(tool)
            HopetLog.trace("\(tool.displayName) hooks installed at boot.")
        } catch {
            HopetLog.warn("\(tool.displayName) hook install failed: \(error)")
        }
    }

    /// 把宠物窗口可见性与 UserDefaults `pet.visible` 绑定。Overview 首页开关与菜单栏
    /// "Toggle Pet Visibility" 都写这个 key；默认显示宠物，用户关闭后下次启动保持隐藏。
    private func wirePetVisibility() {
        let initial = UserDefaults.standard.object(forKey: "pet.visible") as? Bool ?? true
        if initial { petWindowController.show() }

        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .map { _ in UserDefaults.standard.object(forKey: "pet.visible") as? Bool ?? true }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] visible in
                visible ? self?.petWindowController.show() : self?.petWindowController.hide()
            }
            .store(in: &configCancellables)
    }

    /// 把灵动岛窗口的显示状态与 UserDefaults `notch.enabled` 绑定。Overview / Behavior 上的
    /// 开关、灵动岛右上角关闭按钮都通过写这同一个 key 触发 show/hide，单一真相源。
    /// `notch.fallbackBarEnabled` 也纳入监听，让无刘海屏幕的降级顶条开关即时生效。
    /// 启动时读一次决定初始可见，之后用 didChangeNotification 监听变化。
    private func wireNotchVisibility() {
        let initial = NotchVisibilityPreference.current()
        if initial.enabled { notchController.show() }

        NotificationCenter.default
            .publisher(for: UserDefaults.didChangeNotification, object: UserDefaults.standard)
            .map { _ in NotchVisibilityPreference.current() }
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] preference in
                guard let self else { return }
                if preference.enabled {
                    self.notchController.hide()
                    self.notchController.show()
                } else {
                    self.notchController.hide()
                }
            }
            .store(in: &configCancellables)
    }

    /// 折中静音清扫：扫一遍 registry，把"工具 listener 关闭 + 当前无待决策"的 session
    /// 整体移除。带 pending 的留着，等用户落决策后 registry.mutations 再次触发本函数
    /// 把它一并清掉。幂等。`listeners` 须由调用方传入，详见 boot() 里 sink 的注释。
    private func enforceListenerMute(listeners: HopetConfig.Listeners) {
        let victims = registry.activeSessions.filter { !listeners[$0.tool] && $0.pendingKind == nil }
        guard !victims.isEmpty else { return }
        for s in victims {
            HopetLog.trace("listener-mute",
                "remove sid=\(s.id.hopetShortId) tool=\(s.tool.rawValue) state=\(s.currentState.rawValue)")
            permissionPrompter.cancelPending(sessionId: s.id)
            registry.remove(s.id)
            router.purgeTranscriptMaps(for: s.id)
        }
    }
}

private struct NotchVisibilityPreference: Equatable {
    let enabled: Bool
    let fallbackBarEnabled: Bool

    static func current() -> NotchVisibilityPreference {
        NotchVisibilityPreference(
            enabled: UserDefaults.standard.object(forKey: "notch.enabled") as? Bool ?? true,
            fallbackBarEnabled: UserDefaults.standard.object(forKey: "notch.fallbackBarEnabled") as? Bool ?? false
        )
    }
}
