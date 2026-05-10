import Combine
import Foundation

/// 已安装主题的内存目录。
/// - 内置：`DefaultTheme.hopi`。
/// - 用户主题：`~/.hopet/themes/<id>/manifest.json`，由 `reload()` 扫描加载（见 preferences.md §5）。
/// `activeThemeId` 与 `ConfigStore.current.activeThemeId` 双向同步。
@MainActor
public final class ThemeStore: ObservableObject {
    @Published public private(set) var themes: [ThemePackage] = [DefaultTheme.hopi]
    @Published public var activeThemeId: String {
        didSet { configStore.update { $0.activeThemeId = activeThemeId } }
    }

    private let configStore: ConfigStore
    private var cancellables: Set<AnyCancellable> = []

    public init(configStore: ConfigStore) {
        self.configStore = configStore
        self.activeThemeId = configStore.current.activeThemeId

        // config 外部修改（例如 reload 落盘失败回滚到默认）时反向同步到 @Published。
        configStore.$current
            .map(\.activeThemeId)
            .removeDuplicates()
            .sink { [weak self] id in
                guard let self, self.activeThemeId != id else { return }
                self.activeThemeId = id
            }
            .store(in: &cancellables)
    }

    public func theme(_ id: String) -> ThemePackage {
        themes.first { $0.id == id } ?? DefaultTheme.hopi
    }

    public var activeTheme: ThemePackage { theme(activeThemeId) }

    /// 重新扫描 `~/.hopet/themes/`：内置主题 + 解析成功的用户主题。
    /// 本阶段（A）仅刷出内置主题；用户主题扫描在阶段 D 接入（preferences.md §5.3）。
    /// 同时：若当前 `activeThemeId` 指向已不存在的主题，降级回 `hopi.default`。
    public func reload() {
        let userThemes = UserThemeStore.scan()
        themes = [DefaultTheme.hopi] + userThemes
        if !themes.contains(where: { $0.id == activeThemeId }) {
            activeThemeId = DefaultTheme.hopi.id
        }
    }
}
