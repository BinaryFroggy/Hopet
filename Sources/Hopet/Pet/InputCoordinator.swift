import AppKit
import Foundation
import UserNotifications

/// 协调来自气泡 UI 的两类用户操作：
/// - 点击宠物本体：弹 NSOpenPanel 选目录 → 用 `open -a Terminal` 打开终端 + 把首条命令复制到剪贴板。
/// - 气泡上 Allow/Deny / AskUserQuestion 答题：转发给 PermissionPrompter 通过挂起的 socket 回写。
///
/// **不再做"在气泡里输入消息往 session 注入"**。macOS 没有可靠的跨终端宿主反向 stdin 注入路径
/// （TIOCSTI 受 controlling tty 限制；AppleScript 仅 iTerm/Terminal 支持；IDE 扩展自己 spawn 的
/// claude PTY master fd 第三方进程拿不到），强行做只能在很窄的场景下"看着像通了"。
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
