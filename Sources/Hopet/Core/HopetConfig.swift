import Foundation

/// 用户偏好的事实之源，落盘在 `HopetPaths.configFile`（`~/.hopet/config.json`）。
/// See preferences.md §4.3.
public struct HopetConfig: Codable, Equatable, Sendable {
    public var version: Int
    public var appearance: Appearance
    public var activeThemeId: String
    public var listeners: Listeners

    public init(
        version: Int = 1,
        appearance: Appearance = .system,
        activeThemeId: String = "hopi.default",
        listeners: Listeners = .init()
    ) {
        self.version = version
        self.appearance = appearance
        self.activeThemeId = activeThemeId
        self.listeners = listeners
    }

    public static let `default` = HopetConfig()

    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case light, dark, system
    }

    public struct Listeners: Codable, Equatable, Sendable {
        public var claudeCode: Bool
        public var codex: Bool

        public init(claudeCode: Bool = true, codex: Bool = false) {
            self.claudeCode = claudeCode
            self.codex = codex
        }
    }
}

extension HopetConfig {
    /// 读 `~/.hopet/config.json`。文件缺失或非法时降级为默认值，并 warn；不抛异常。
    /// schema 升级时若读到未知 version，整体降级到默认值（见 preferences.md §4.3）。
    public static func load() -> HopetConfig {
        let url = HopetPaths.configFile
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            return .default
        }
        do {
            let decoded = try JSONDecoder().decode(HopetConfig.self, from: data)
            guard decoded.version == 1 else {
                HopetLog.warn("HopetConfig: unknown version \(decoded.version), fallback to default.")
                return .default
            }
            return decoded
        } catch {
            HopetLog.warn("HopetConfig: decode failed, fallback to default: \(error)")
            return .default
        }
    }

    /// 同步落盘。失败仅 warn，不抛——内存值优先于磁盘可达性。
    public func save() {
        let url = HopetPaths.configFile
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            HopetLog.warn("HopetConfig: save failed: \(error)")
        }
    }
}
