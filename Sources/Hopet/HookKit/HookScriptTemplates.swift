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

    /// Hopet 注入到 `~/.hope-agent/config.json` 的 `hooks` 字段里的全部条目。
    ///
    /// Hope Agent 是 Tauri 桌面 / 守护进程形态的本地 AI 助手，自带一套**字段级对齐
    /// Claude Code 协议**的 hooks 系统（`command` 类型把 hook input JSON 喂 stdin、
    /// 同名 PascalCase 事件、`tool_input.command` 对齐），所以这里的注册结构与 Claude
    /// 完全同构，hopet-emit 不需任何 hope-agent 专属解析。
    ///
    /// ask-user 与 Claude 殊途同归：hope-agent 用自己的 `Elicitation` / `ElicitationResult`
    /// 事件（而非 Claude 的 `PreToolUse + tool_name=AskUserQuestion` 分流——hope-agent 的
    /// `tool_name` 是内部名 `exec`，那套 filter 命中不了），但 `Elicitation` 映射到
    /// `permission_ask` 且把问题以 **Claude AskUserQuestion 形状**同步发出，故 Hopet 复用同一
    /// 张答题卡、经 `updatedInput.answers` 同步回包，气泡里直接作答、体验与 Claude 完全一致。
    ///
    /// `PermissionRequest` 与 Claude 完全同构：hope-agent 已让该事件可决策——hook 返回的
    /// `hookSpecificOutput.decision.behavior`（allow/deny）经 `submit_approval_response`
    /// 注入审批，与 GUI / IM 幂等竞争（第一个决策生效）。所以宠物气泡的 Allow / Deny 真正
    /// 控制 hope-agent，permission_ask 的同步回包链是通的。无需设 timeout：hope-agent 把该
    /// hook 的截止时间钳到自己的 `approval_timeout_secs`（审批超时），与 GUI 弹窗同寿命。
    static func hopeAgentHooks(emitPath: String) -> [String: [[String: Any]]] {
        func entry(_ command: String) -> [String: Any] {
            ["hooks": [["type": "command", "command": command]]]
        }
        return [
            "SessionStart": [
                entry("\(emitPath) --tool hope-agent --event session_start")
            ],
            "SessionEnd": [
                entry("\(emitPath) --tool hope-agent --event session_end")
            ],
            "UserPromptSubmit": [
                entry("\(emitPath) --tool hope-agent --event user_prompt")
            ],
            "PreToolUse": [
                entry("\(emitPath) --tool hope-agent --event pre_tool_use")
            ],
            "PostToolUse": [
                entry("\(emitPath) --tool hope-agent --event post_tool_use")
            ],
            "PostToolUseFailure": [
                entry("\(emitPath) --tool hope-agent --event error")
            ],
            // 权限请求只走 PermissionRequest（与 Claude 同构）；hope-agent 让该事件可决策，
            // 气泡 Allow/Deny 经 hopet-emit 的 Claude 回包格式注入审批。不要在别处重复发
            // permission_ask，否则一个权限事件会触发两次 popup。
            "PermissionRequest": [
                entry("\(emitPath) --tool hope-agent --event permission_ask")
            ],
            "Stop": [
                entry("\(emitPath) --tool hope-agent --event stop")
            ],
            "StopFailure": [
                entry("\(emitPath) --tool hope-agent --event error")
            ],
            // ask-user 走 Elicitation，但映射到 permission_ask：hope-agent 把问题以 Claude
            // AskUserQuestion 形状（tool_name=AskUserQuestion + tool_input.questions）同步发出，
            // Hopet 据 tool_name 归一为 askUser、复用现有答题卡，并经 updatedInput.answers 同步回包，
            // 与 Claude 的 AskUserQuestion 完全一条路径、零特殊适配。
            "Elicitation": [
                entry("\(emitPath) --tool hope-agent --event permission_ask")
            ],
            // 在别处（hope-agent GUI / IM）作答时清掉气泡上的待答卡。
            "ElicitationResult": [
                entry("\(emitPath) --tool hope-agent --event ask_user_resolved")
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
