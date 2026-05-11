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

    /// Hopet 注入到 ~/.codex/hooks.json `hooks` 字典里的全部条目（架构文档 §8.5）。
    ///
    /// Codex CLI 0.129.0-alpha 起公开了与 Claude Code 几乎一致的细粒度生命周期 hook
    /// （`[features] codex_hooks = true` 启用，文件 `~/.codex/hooks.json`）。共 6 个事件，
    /// 无 SessionEnd / AskUserQuestion / PostToolUseFailure / StopFailure，因此映射比 Claude 精简。
    static func codexHooks(emitPath: String) -> [String: [[String: Any]]] {
        func entry(_ command: String, timeout: Int) -> [String: Any] {
            ["hooks": [["type": "command", "command": command, "timeout": timeout]]]
        }
        // PermissionRequest 走双向同步回包，用户可能长时间不点。Codex 跟 Claude 一样
        // 把 hook timeout 当上限——给一个足够大的值让用户自由决策；其它非阻塞 hook 30s 够用。
        let permissionTimeout = 590
        let stateTimeout = 30
        return [
            "SessionStart": [
                entry("\(emitPath) --tool codex --event session_start", timeout: stateTimeout)
            ],
            "UserPromptSubmit": [
                entry("\(emitPath) --tool codex --event user_prompt", timeout: stateTimeout)
            ],
            "PreToolUse": [
                entry("\(emitPath) --tool codex --event pre_tool_use", timeout: stateTimeout)
            ],
            "PostToolUse": [
                entry("\(emitPath) --tool codex --event post_tool_use", timeout: stateTimeout)
            ],
            "PermissionRequest": [
                entry("\(emitPath) --tool codex --event permission_ask", timeout: permissionTimeout)
            ],
            "Stop": [
                entry("\(emitPath) --tool codex --event stop", timeout: stateTimeout)
            ]
        ]
    }

    /// 区分 "Hopet 写的" 与 "用户写的" 的标记字符串。卸载时用它筛选 hopet-emit 命令。
    static let hopetMarker = "/.hopet/bin/hopet-emit"

    /// `~/.codex/config.toml` 里旧版 `[notify]` 块的起止标记。v0.2 起 Codex 走 hooks.json，
    /// install 时顺手清掉历史 notify 注入，避免一个 stop 事件被 notify + hooks.json 双发。
    static let codexNotifyBlockBegin = "# >>> hopet-managed >>>"
    static let codexNotifyBlockEnd = "# <<< hopet-managed <<<"
}
