import AppKit
import ApplicationServices
import Foundation

/// 把一段文本"自动发送"到指定 tty 对应的终端窗口/标签。
/// 优先级：
/// 1. iTerm2: 纯 AppleScript `write text`（直接写到 tty fd，**不需要 Accessibility**）。
/// 2. Apple Terminal: AppleScript 激活对应 tab + System Events 模拟 ⌘V + ↩（**需要 Accessibility**）。
/// 3. 其他终端 / 匹配失败：返回 .fallback，由调用方走剪贴板兜底。
@MainActor
public enum TerminalAutomation {

    public enum Result {
        case sent
        case fallback(reason: String)
    }

    /// 入口。`tty` 形如 `/dev/ttys003`；`termApp` 形如 `iTerm.app` / `Apple_Terminal`。
    public static func send(text: String, tty: String?, termApp: String?) -> Result {
        guard let tty, !tty.isEmpty else {
            return .fallback(reason: "no tty recorded for session")
        }
        switch normalize(termApp) {
        case .iterm:
            return sendViaITerm(text: text, tty: tty)
        case .appleTerminal:
            return sendViaAppleTerminal(text: text, tty: tty)
        case .unknown:
            return .fallback(reason: "unsupported terminal: \(termApp ?? "nil")")
        }
    }

    // MARK: - 终端识别

    private enum Kind {
        case iterm
        case appleTerminal
        case unknown
    }

    private static func normalize(_ termApp: String?) -> Kind {
        guard let raw = termApp?.lowercased() else { return .unknown }
        if raw.contains("iterm") { return .iterm }
        if raw.contains("apple_terminal") || raw == "terminal" { return .appleTerminal }
        return .unknown
    }

    // MARK: - iTerm2 路径（推荐：免 Accessibility）

    private static func sendViaITerm(text: String, tty: String) -> Result {
        // iTerm 的 `write text` 直接把字符送进 session 的 stdin，不经键盘事件。
        // 多行用 `\n` 分隔 + 末尾追加 newline=YES 让最后一行也提交。
        let script = """
        on run argv
            set targetTty to item 1 of argv
            set msg to item 2 of argv
            tell application "iTerm2"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is targetTty then
                                tell s
                                    write text msg newline yes
                                end tell
                                tell w to select
                                return "ok"
                            end if
                        end repeat
                    end repeat
                end repeat
                return "notfound"
            end tell
        end run
        """
        let output = runOSAScript(source: script, args: [tty, text])
        if output == "ok" {
            return .sent
        }
        return .fallback(reason: "iterm session not found for tty \(tty); raw=\(output ?? "nil")")
    }

    // MARK: - Apple Terminal 路径（需 Accessibility 权限）

    private static func sendViaAppleTerminal(text: String, tty: String) -> Result {
        // 1. 把文本放剪贴板。
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // 2. 激活对应 tab。
        let activateScript = """
        on run argv
            set targetTty to item 1 of argv
            tell application "Terminal"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is targetTty then
                            set selected of t to true
                            set frontmost of w to true
                            activate
                            return "ok"
                        end if
                    end repeat
                end repeat
                return "notfound"
            end tell
        end run
        """
        let activateResult = runOSAScript(source: activateScript, args: [tty])
        guard activateResult == "ok" else {
            return .fallback(reason: "terminal tab not found for tty \(tty); raw=\(activateResult ?? "nil")")
        }

        // 3. 模拟 ⌘V + Return。System Events keystroke 需要 Accessibility 权限。
        guard ensureAccessibilityTrusted() else {
            return .fallback(reason: "accessibility permission not granted")
        }

        // 给 Terminal 一个 tick 让前台切换稳定。
        usleep(80_000)

        let keystrokeScript = """
        tell application "System Events"
            keystroke "v" using command down
            delay 0.05
            key code 36
        end tell
        """
        let keyResult = runOSAScript(source: keystrokeScript, args: [])
        if keyResult == nil {
            return .fallback(reason: "system events keystroke failed (likely accessibility)")
        }
        return .sent
    }

    // MARK: - osascript 调用

    /// 用 /usr/bin/osascript -e 执行 AppleScript；带参数走 -- args，避免 escape 噩梦。
    /// 返回脚本最后表达式的字符串值；失败返回 nil。
    private static func runOSAScript(source: String, args: [String]) -> String? {
        let proc = Process()
        proc.launchPath = "/usr/bin/osascript"
        // osascript: `-` 读取 stdin 作为脚本，剩余参数原样传到 `on run argv`。
        proc.arguments = ["-"] + args
        let inPipe = Pipe()
        let outPipe = Pipe()
        let errPipe = Pipe()
        proc.standardInput = inPipe
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        do {
            try proc.run()
        } catch {
            HopetLog.trace("osascript launch failed: \(error)")
            return nil
        }
        inPipe.fileHandleForWriting.write(Data(source.utf8))
        try? inPipe.fileHandleForWriting.close()
        proc.waitUntilExit()
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        let str = String(data: outData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let errStr = String(data: errData, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        HopetLog.trace("osascript status=\(proc.terminationStatus) stdout=\(str ?? "") stderr=\(errStr)")
        guard proc.terminationStatus == 0 else { return nil }
        return str
    }

    // MARK: - Accessibility

    private static func ensureAccessibilityTrusted() -> Bool {
        // 使用不带 prompt 的检查；首次没权限时由调用层去引导用户授权（避免每次 submit 都弹系统框）。
        AXIsProcessTrusted()
    }

    /// 显式触发系统的"提示授权"对话（带 prompt 参数）。供 UI 在用户主动点击"去授权"按钮时调用。
    public static func requestAccessibilityWithPrompt() {
        let key = "AXTrustedCheckOptionPrompt" as CFString
        let opts: [CFString: Any] = [key: true]
        _ = AXIsProcessTrustedWithOptions(opts as CFDictionary)
    }
}
