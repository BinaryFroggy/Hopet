import Foundation

/// 架构文档 §8.4.2 / §8.5 中给出的 hook 注册项。所有路径均通过 ~/.hopet/bin/hopet-emit。
enum HookScriptTemplates {
    /// Hopet 注入到 ~/.claude/settings.json `hooks` 字典里的全部条目。
    /// 每个 key 对应一组 [{ "hooks": [{ "type": "command", "command": "..." }] }]。
    static func claudeHooks(emitPath: String) -> [String: [[String: Any]]] {
        func entry(_ command: String) -> [String: Any] {
            ["hooks": [["type": "command", "command": command]]]
        }
        return [
            "SessionStart": [
                entry("\(emitPath) --tool claude-code --event session_start")
            ],
            "SessionEnd": [
                entry("\(emitPath) --tool claude-code --event session_end")
            ],
            "UserPromptSubmit": [
                entry("\(emitPath) --tool claude-code --event user_prompt")
            ],
            "PreToolUse": [
                entry("\(emitPath) --tool claude-code --event ask_user --require tool_name=AskUserQuestion"),
                entry("\(emitPath) --tool claude-code --event pre_tool_use --exclude tool_name=AskUserQuestion")
            ],
            "PostToolUse": [
                entry("\(emitPath) --tool claude-code --event ask_user_resolved --require tool_name=AskUserQuestion"),
                entry("\(emitPath) --tool claude-code --event post_tool_use --exclude tool_name=AskUserQuestion")
            ],
            "PostToolUseFailure": [
                entry("\(emitPath) --tool claude-code --event error")
            ],
            // 权限请求只走 PermissionRequest；不要重复在 Notification 上再发 permission_ask，
            // 否则一个权限事件会触发两次 popup（且 Notification 输出不被 Claude 当作决策回写）。
            "PermissionRequest": [
                entry("\(emitPath) --tool claude-code --event permission_ask")
            ],
            "Stop": [
                entry("\(emitPath) --tool claude-code --event stop")
            ],
            "StopFailure": [
                entry("\(emitPath) --tool claude-code --event error")
            ]
        ]
    }

    /// Codex `notify` 字段（架构文档 §8.5）。
    static func codexNotifyArguments(emitPath: String) -> [String] {
        [emitPath, "--tool", "codex", "--event", "stop"]
    }

    /// 区分 "Hopet 写的" 与 "用户写的" 的标记字符串。卸载时用它筛选 hopet-emit 命令。
    static let hopetMarker = "/.hopet/bin/hopet-emit"
}
