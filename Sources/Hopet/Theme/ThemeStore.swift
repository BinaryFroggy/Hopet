import Foundation
import Combine

/// 已安装主题的内存目录。v0.1 仅含内置 hopi.default。
@MainActor
public final class ThemeStore: ObservableObject {
    @Published public private(set) var themes: [ThemePackage] = [DefaultTheme.hopi]
    @Published public var activeThemeId: String = DefaultTheme.hopi.id

    public init() {}

    public func theme(_ id: String) -> ThemePackage {
        themes.first { $0.id == id } ?? DefaultTheme.hopi
    }

    public var activeTheme: ThemePackage { theme(activeThemeId) }
}
