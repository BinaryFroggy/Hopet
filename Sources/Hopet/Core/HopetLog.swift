import Foundation
import os

public enum LogLevel: String { case debug, info, warn, error }

/// 极简日志：osLog + 可选写入 ~/.hopet/logs/hopet.log。
public enum HopetLog {
    private static let logger = Logger(subsystem: "com.hopet.app", category: "core")
    public static var level: LogLevel = .info

    public static func debug(_ msg: @autoclosure () -> String) { emit(.debug, msg()) }
    public static func info(_ msg: @autoclosure () -> String)  { emit(.info,  msg()) }
    public static func warn(_ msg: @autoclosure () -> String)  { emit(.warn,  msg()) }
    public static func error(_ msg: @autoclosure () -> String) { emit(.error, msg()) }

    /// 始终写入 stderr，带 `[hopet][tag]` 前缀。用于 `swift run` 终端追踪事件流。
    /// 不走 level 过滤、不走 os.Logger（os.Logger 由 debug/info/warn/error 负责）。
    public static func trace(_ tag: String, _ msg: String) {
        FileHandle.standardError.write(Data("[hopet][\(tag)] \(msg)\n".utf8))
    }

    /// `trace` 的无 tag 版本，写出 `[hopet] msg`。
    public static func trace(_ msg: String) {
        FileHandle.standardError.write(Data("[hopet] \(msg)\n".utf8))
    }

    private static func emit(_ severity: LogLevel, _ message: String) {
        guard severityRank(severity) >= severityRank(level) else { return }
        switch severity {
        case .debug: logger.debug("\(message, privacy: .public)")
        case .info:  logger.info("\(message, privacy: .public)")
        case .warn:  logger.warning("\(message, privacy: .public)")
        case .error: logger.error("\(message, privacy: .public)")
        }
    }

    private static func severityRank(_ s: LogLevel) -> Int {
        switch s {
        case .debug: return 0
        case .info:  return 1
        case .warn:  return 2
        case .error: return 3
        }
    }
}
