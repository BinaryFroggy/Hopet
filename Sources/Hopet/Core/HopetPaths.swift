import Foundation

/// `~/.hopet/` 下所有路径的单一权威。
public enum HopetPaths {
    public static var home: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".hopet", isDirectory: true)
    }

    public static var bin:    URL { home.appendingPathComponent("bin",    isDirectory: true) }
    public static var run:    URL { home.appendingPathComponent("run",    isDirectory: true) }
    public static var state:  URL { home.appendingPathComponent("state",  isDirectory: true) }
    public static var themes: URL { home.appendingPathComponent("themes", isDirectory: true) }
    public static var logs:   URL { home.appendingPathComponent("logs",   isDirectory: true) }

    public static var socket:        URL { run.appendingPathComponent("hopetd.sock") }
    public static var configFile:    URL { home.appendingPathComponent("config.json") }
    public static var bindingsFile:  URL { home.appendingPathComponent("bindings.json") }

    public static var emitBinary: URL { bin.appendingPathComponent("hopet-emit") }
    public static var ptyBinary:  URL { bin.appendingPathComponent("hopet-pty") }

    /// 启动时确保所有目录存在（幂等）。
    public static func ensureDirectories() throws {
        let fm = FileManager.default
        for dir in [home, bin, run, state, themes, logs] {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
}
