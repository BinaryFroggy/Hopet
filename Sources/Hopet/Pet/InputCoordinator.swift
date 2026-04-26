import AppKit
import Foundation
import UserNotifications

/// v0.1 输入注入协调器。
/// - 点击宠物本体：弹 NSOpenPanel 选目录 → 用 `open -a Terminal` 打开终端，并把首条 prompt 复制到剪贴板。
/// - 点击会话气泡：把文本复制到剪贴板 + 通知用户去对应终端粘贴。
/// (PTY wrapper 路径 v0.1 暂未实现；接口位置已留好。)
@MainActor
public final class InputCoordinator {
    private unowned let registry: SessionRegistry
    private unowned let permissionPrompter: PermissionPrompter

    public init(registry: SessionRegistry, permissionPrompter: PermissionPrompter) {
        self.registry = registry
        self.permissionPrompter = permissionPrompter
    }

    /// 用户在气泡 UI 上点 Allow / Deny / Ask 时调用。
    public func resolvePermission(sessionId: String, requestId: String, decision: String) {
        permissionPrompter.resolve(sessionId: sessionId, requestId: requestId, decision: decision)
    }

    /// 用户在 AskUserQuestion 气泡里提交答案时调用。
    /// answers: 问题文案 → 用户作答字符串。cancel = true 表示让 Claude 走自身 UI。
    public func resolveAskUser(sessionId: String, requestId: String, answers: [String: String], cancel: Bool = false) {
        permissionPrompter.resolveAskUser(
            sessionId: sessionId,
            requestId: requestId,
            answers: answers,
            cancel: cancel
        )
    }

    public func openNewSessionDialog(for tool: AITool) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "选择启动 \(tool.displayName) 的目录"
        panel.title = "Hopet · 新建 \(tool.displayName) 会话"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.promptForFirstMessage(tool: tool, cwd: url.path)
        }
    }

    private func promptForFirstMessage(tool: AITool, cwd: String) {
        let alert = NSAlert()
        alert.messageText = "在 \(cwd) 启动 \(tool.displayName)"
        alert.informativeText = "可在下方输入首条消息（可留空）。点击「启动」后会打开终端并把命令复制到剪贴板。"
        let textField = NSTextField(frame: NSRect(x: 0, y: 0, width: 360, height: 80))
        textField.placeholderString = "向 \(tool.displayName) 发送一条消息…"
        alert.accessoryView = textField
        alert.addButton(withTitle: "启动")
        alert.addButton(withTitle: "取消")
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let firstMessage = textField.stringValue
        spawnTerminal(tool: tool, cwd: cwd, firstMessage: firstMessage)
    }

    private func spawnTerminal(tool: AITool, cwd: String, firstMessage: String) {
        let cliCommand = tool.cliBinary ?? "claude"
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        let script = "cd \"\(cwd)\" && \(cliCommand)" +
                     (firstMessage.isEmpty ? "" : " \"\(firstMessage.replacingOccurrences(of: "\"", with: "\\\""))\"")
        pasteboard.setString(script, forType: .string)

        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-a", "Terminal", cwd]
        try? task.run()

        notify(title: "Hopet 已打开终端", body: "首行命令已复制到剪贴板，⌘V 粘贴即可。")
    }

    /// 把消息「注入」到指定 session：
    /// - 优先 TerminalAutomation 走 AppleScript 直送（iTerm/Terminal）。
    /// - 失败兜底：复制到剪贴板 + NSLog（避免 UNUserNotificationCenter 在未打包时崩溃）。
    public func submit(text: String, toSessionId sessionId: String) {
        let session = registry.session(sessionId)
        let sid = sessionId.hopetShortId
        HopetLog.trace("submit sid=\(sid) tty=\(session?.terminalTty ?? "nil") termApp=\(session?.terminalApp ?? "nil")")
        let result = TerminalAutomation.send(
            text: text,
            tty: session?.terminalTty,
            termApp: session?.terminalApp
        )
        switch result {
        case .sent:
            HopetLog.trace("submit OK via TerminalAutomation")
            HopetLog.info("submit → \(sid) via TerminalAutomation")
        case .fallback(let reason):
            HopetLog.trace("submit FALLBACK: \(reason)")
            HopetLog.warn("TerminalAutomation fallback (\(reason)); copied to clipboard")
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            notify(
                title: "已复制到剪贴板",
                body: "请到 session \(sid) 对应的终端窗口粘贴 (⌘V)。"
            )
        }
    }

    private func notify(title: String, body: String) {
        // UNUserNotificationCenter.current() 在没有 bundleIdentifier 时（`swift run` 裸二进制）会直接 abort，
        // 所以未打包成 .app 时降级到 NSLog，避免崩溃。
        guard Bundle.main.bundleIdentifier != nil else {
            NSLog("[Hopet] %@ — %@", title, body)
            return
        }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString,
                                            content: content,
                                            trigger: nil)
        center.add(request, withCompletionHandler: nil)
    }
}
