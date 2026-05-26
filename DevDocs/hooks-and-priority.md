# Hopet Hooks 映射与状态优先级 v0.1

> 版本：0.1（初版）
> 最后更新：2026-04-26
> 数据源：[Claude Code Hooks 官方文档](https://code.claude.com/docs/en/hooks)（2026-04-26 抓取）

本文件是 [architecture.md](./architecture.md) §7（状态机）与 §8（IPC 协议）的扩展附录，集中说明：

1. Claude Code 全部 hook 事件的清单与语义
2. Hopet 对每个 hook 的处理策略（订阅 / 忽略 / 路由到何种 `EventKind`）
3. `PetState` 的优先级排序（用于多会话 → 单宠物的状态聚合）
4. 状态聚合算法的具体规则与边界情况

---

## 1. Claude Code Hook 全集

下表对照官方文档列出 Claude Code 当前公布的所有 hook，并标记 Hopet v0.1 / v0.2 的处理策略。

| # | Hook 名称 | 触发时机 | 关键 stdin 字段 | 是否阻塞能力 | Hopet v0.1 |
| -- | --- | --- | --- | --- | --- |
| 1 | `SessionStart` | Session 开始或恢复 | `source` (startup/resume/clear/compact)、`model` | 否 | ✅ 注册 → `session_start` |
| 2 | `SessionEnd` | Session 终止 | `reason` (clear/resume/logout/prompt_input_exit/...) | 否 | ✅ 注册 → `session_end`（淘汰对应气泡） |
| 3 | `UserPromptSubmit` | 用户提交 prompt | `prompt` 文本 | ✅ 可阻塞 | ✅ 注册 → `user_prompt`（不阻塞，仅观测） |
| 4 | `UserPromptExpansion` | 斜杠命令展开 | `command_name`、`expansion_type`、`command_args` | ✅ | ⛔ v0.1 不订阅 |
| 5 | `PreToolUse` | 工具调用前 | `tool_name`、`tool_input`、`tool_use_id` | ✅ allow/deny/ask/defer | ✅ 注册（路由 AskUserQuestion → `ask_user`，其它 → `pre_tool_use`） |
| 6 | `PermissionRequest` | 权限对话框出现 | `tool_name`、`tool_input`、`permission_suggestions` | ✅ allow/deny | ✅ 注册 → `permission_ask` |
| 7 | `PermissionDenied` | auto 模式自动拒绝 | `tool_name`、`tool_input` | 否 | ⛔ v0.1 不订阅（v0.2 可考虑作为单独动画） |
| 8 | `PostToolUse` | 工具成功 | `tool_name`、`tool_input`、`tool_response`、`duration_ms` | ✅ block/feedback | ✅ 注册（路由 AskUserQuestion → `ask_user_resolved`，其它 → `post_tool_use`） |
| 9 | `PostToolUseFailure` | 工具失败 | `tool_name`、`tool_input`、`error`、`is_interrupt`、`duration_ms` | 否 | ✅ 注册 → `error`（携带 `is_interrupt` 区分用户中断 vs 异常） |
| 10 | `PostToolBatch` | 一批并行工具完成 | (batch metadata) | ✅ | ⛔ v0.1 不订阅 |
| 11 | `Notification` | 通知发送 | `notification_type` | 否 | ⛔ 不订阅。早期作为 `PermissionRequest` 的兼容回退路径，但在实际 Claude 版本里两条 hook 会同步并发触发，导致同一权限事件双发；改为只信 `PermissionRequest`，缺它则降级为无气泡。 |
| 12 | `SubagentStart` | Subagent 启动 | `agent_type` | 否 | ⛔ v0.1 不订阅（聚合到主 session 的 toolUse） |
| 13 | `SubagentStop` | Subagent 完成 | `agent_type` | ✅ | ⛔ v0.1 不订阅 |
| 14 | `TaskCreated` | TaskCreate 创建 task | (task metadata) | ✅ | ⛔ v0.1 不订阅 |
| 15 | `TaskCompleted` | task 标记完成 | (task metadata) | ✅ | ⛔ v0.1 不订阅 |
| 16 | `Stop` | Claude 完成回复 | `transcript_path`（必有）；部分版本带 `assistant_message` 字段 | ✅ | ✅ 注册 → `stop`，hopet-emit 从 `transcript_path` 反向扫描，遇到本轮 user prompt 即停止（避免取到上一轮残留的 end_turn），只接受位于其后的 `stop_reason=="end_turn"` assistant text；同时跳过中间 `tool_use` turn 的过渡文本。end_turn 行尚未 flush 时用 `DispatchSource` 监听 transcript write/extend，事件即重读，5s 超时兜底（hook fire-and-forget，不阻塞 Claude）。截断 120 字符后随 payload 上行（字段名 `assistant_message`）。EventRouter 写入 `Session.lastAssistantMessage`，供默认气泡第二行展示；下一次 `UserPromptSubmit` 清空 |
| 17 | `StopFailure` | turn 因 API 错误终止 | `error_type` (rate_limit/auth_failed/billing_error/...) | 否 | ✅ 注册 → `error`（携带 error_type） |
| 18 | `TeammateIdle` | Agent team 队友 idle | (team metadata) | ✅ | ⛔ v0.1 不订阅 |
| 19 | `InstructionsLoaded` | CLAUDE.md / .claude/rules/*.md 加载 | `file_path`、`load_reason`、`memory_type` | 否 | ⛔ 不订阅 |
| 20 | `ConfigChange` | 配置文件变化 | `source` (user_settings/project_settings/...) | ✅（除 policy） | ⛔ 不订阅 |
| 21 | `CwdChanged` | 工作目录变化 | (directory info) | 否 | ⚠️ v0.1 不订阅；v0.2 可用于更新气泡显示 |
| 22 | `FileChanged` | 监视的文件变化 | `file_path` | 否 | ⛔ 不订阅 |
| 23 | `WorktreeCreate` | 创建 worktree | (worktree metadata) | ✅（任意非零退出阻塞） | ⛔ 不订阅 |
| 24 | `WorktreeRemove` | 移除 worktree | (worktree metadata) | 否 | ⛔ 不订阅 |
| 25 | `PreCompact` | 上下文压缩前 | `trigger` (manual/auto) | ✅ | ⛔ v0.1 不订阅（v0.2 可考虑作为短暂"整理中"动画） |
| 26 | `PostCompact` | 压缩完成 | (compaction metadata) | 否 | ⛔ 不订阅 |
| 27 | `Elicitation` | MCP server 请求用户输入 | `server` 名称 | ✅ accept/decline/cancel | ⚠️ v0.1 不订阅（路由仅含 AskUserQuestion）；v0.2 同样路由到 `ask_user` |
| 28 | `ElicitationResult` | 用户响应 MCP elicitation | `server`、`content` | ✅ override/block | ⚠️ v0.1 不订阅；v0.2 路由到 `ask_user_resolved` |

### 1.1 实际订阅的 Claude Code hook

```
SessionStart → session_start
SessionEnd → session_end
UserPromptSubmit → user_prompt
PreToolUse → ask_user (when tool_name=AskUserQuestion) | pre_tool_use (otherwise)
PostToolUse → ask_user_resolved (when tool_name=AskUserQuestion) | post_tool_use (otherwise)
PostToolUseFailure → error
PermissionRequest → permission_ask
Stop → stop
StopFailure → error
```

> 权威源：`Sources/Hopet/HookKit/HookScriptTemplates.swift` 的 `claudeHooks(emitPath:)`。
>
> 注 1：早期版本同时注册 `Notification --require notification_type=permission_prompt` 作为 `PermissionRequest` 的兼容回退；实测会与 `PermissionRequest` 同步并发触发，把同一次权限请求双发，所以彻底移除。
>
> 注 2：`error` 事件**不再切换** `PetState`。`PostToolUseFailure` 在 Claude 实际使用中包含 `grep`/`head` 等命令的非零退出，发得过于频繁，每次都把海豹切到 `error-interrupted` 会让用户误以为会话异常。代码把 `error` 改为只触发 `cancelPending`（清掉挂起的权限/答题气泡）但保留当前 `PetState` 不变（见 `SessionStateMachine.swift` 的注释）。`errorInterrupted` 状态值仍保留，等未来出现真正的"会话级错误"事件源再启用。

### 1.2 Codex CLI 实际订阅的 6 个 hook（v0.2+）

Codex CLI 0.129.0-alpha 起公开了与 Claude 几乎一致的细粒度生命周期 hook 体系（启用方式：`~/.codex/config.toml` 设 `[features] codex_hooks = true`，配置文件 `~/.codex/hooks.json`，结构与 Claude `hooks` 字典同形）。Hopet v0.2 起直接接入这套 hook，取代 v0.1 仅有的 `[notify]` 完成通知。

```
SessionStart → session_start
UserPromptSubmit → user_prompt
PreToolUse → pre_tool_use
PostToolUse → post_tool_use
PermissionRequest → permission_ask
Stop → stop
```

Codex 当前**不暴露**这些 Claude 有的事件，因此 Hopet 不订阅、靠 IPC 端的其它路径兜底：

- `SessionEnd` — 用架构 §7.3 的"60 分钟无事件回收"路径替代
- `AskUserQuestion` — Codex 没有这个内置 tool；问询场景由 `PermissionRequest` 承载
- `PostToolUseFailure` / `StopFailure` — Codex 不分流错误事件
- `Notification` / `Compact` / `Subagent*` / `Task*` — Codex 不发

**Payload 命名差异**：

| 字段 | Claude | Codex | hopet-emit 处理 |
| --- | --- | --- | --- |
| 事件名 | `hookEventName`（camelCase） | `hook_event_name`（snake_case） | 不读取（白名单未含此字段） |
| session id | `session_id` | `session_id`（**常为空串**） | Codex 路径下空时从 `transcript_path` 的 `rollout-<date>-<uuid>.jsonl` 抽 uuid 兜底成 `codex-<uuid>` |
| 工具相关 | `tool_name` / `tool_input` / `tool_use_id` | 同 | 直接复用白名单 |
| Stop 防递归 | — | `stop_hook_active`（true 时必须静默退出，否则递归） | Codex 路径下识别后 `exit 0` |

**Permission 回包格式**：Codex 与 Claude 一致，输出 `{ hookSpecificOutput: { hookEventName: "PermissionRequest", decision: { behavior: "allow"|"deny", message? } } }`，`hopet-emit.emitDecision()` 现成可用。

> 已知体验注意点：若同机器上 Codex `hooks.json` 同时被多个工具（如 clawd-on-desk）注册了 `PermissionRequest`，多个 hook 会并发收到事件并各自请求决策。Hopet 的合并策略保留其它工具条目（只 append/卸载自己的 marker 行），不主动清理别人——多端决策的优先级由 Codex 内部规则决定。

### 1.3 Codex VSCode / Cursor 插件本地会话监听

Codex VSCode / Cursor 插件不走 `~/.codex/hooks.json`，因此 CLI hook 链不会收到插件主会话的生命周期事件。Hopet App 启动后额外只读监听 `~/.codex/sessions/**/rollout-*.jsonl`，筛选 `session_meta.originator == "codex_vscode"` 或 `source == "vscode"` 且 `thread_source != "subagent"` 的主会话，把本地 JSONL 事件桥接到同一套 `EventRouter`：

```
task_started → user_prompt
user_message → user_prompt（刷新 prompt/title）
function_call / custom_tool_call → pre_tool_use
最后一个 function_call_output / custom_tool_call_output → post_tool_use
task_complete → stop
turn_aborted → stop（assistant_message = "Turn aborted"）
```

这条路径不是同步 hook：插件内的权限审批仍由 Codex VSCode / Cursor 自己处理，Hopet 不展示可交互审批卡，也不回写 Allow / Deny / Handoff 决策；`permission_ask` 继续只来自 Codex CLI hook。rollout 里即使能看到 `exec_command` 的 `sandbox_permissions = "require_escalated"`，Hopet 也只把它视为普通 `tool-use`。

---

## 2. PetState 优先级

新设计中宠物**全局唯一**，所有 AI 工具的所有活跃 session 共用一只宠物；宠物展示的 `aggregatedState` 等于所有活跃 session 中**优先级最高**的那个 session 状态。

| 优先级 | PetState | 含义 | 选定理由 |
| --- | --- | --- | --- |
| **P0** | `askUser` | Claude 调用 AskUserQuestion 等待用户回答 | 用户操作直接阻塞会话推进，必须最高 |
| **P1** | `permissionPrompt` | Claude 弹出权限请求 | 同样阻塞，但比 askUser 偶尔可"用户跳过"略低 |
| **P2** | `errorInterrupted` | tool / turn 失败（保留枚举值，但 v0.1 起没有事件源能切到这个状态——见 §1.1 注 2） | 用户需感知，但已是终态、不阻塞下一动作 |
| **P3** | `toolUse` | 正在执行 tool | 当前正在做事，需要清晰的"忙碌"信号 |
| **P4** | `thinking` | 长时间思考（`responding` 持续 ≥ 8s） | 比普通回复更"重"，应优于 responding |
| **P5** | `responding` | 普通回复中 | — |
| **P6** | `completed` | 刚完成（持续 2s 后回 idle） | 短暂状态，不应压住其它会话的真实活动 |
| **P7** | `idle` | 空闲 | 兜底 |

数字越小优先级越高。Hopet 内部约定 `func priority(_ state: PetState) -> Int` 返回 0–7。

### 2.1 设计权衡说明

- **askUser > permissionPrompt**：两者都阻塞，但 AskUserQuestion 通常是 Claude 主动的对话式提问，必须用户回答才能继续；权限请求虽然也阻塞，但用户至少可在终端"全部允许"快速放行。askUser 的紧迫度更高。
- **errorInterrupted > toolUse**：错误是终态信号，需要用户感知；如果同时有别的会话还在 toolUse，宠物显示错误更重要（用户能立刻意识到"有一个会话失败了，去看看"），别的会话的进度信号可以等错误处理完。
- **completed < toolUse / responding**：当 A 会话刚完成、B 会话还在跑，宠物应当显示 B 的活跃状态；若把 completed 放高，会出现"一个会话完成把整只宠物变成欢呼"的误导。
- **error-interrupted vs completed**：两者都是"刚结束"，但前者需要警示，所以 P2；后者只是收尾庆祝，所以 P6。

### 2.2 同优先级的 tie-break

当多个 session（无论来自哪个 AI 工具）处于同一优先级状态时：

1. 先按 `stateSince` 时间倒序（最近变更的在前）
2. 再按 `sessionId` 字母序（确定性）

宠物动画始终展示 tie-break 后第一个 session 的状态。但**该 session 对应的会话气泡**会以"高亮边框"标识当前是它在驱动宠物动画。

---

## 3. 聚合算法

### 3.1 触发条件

每当任何 session 的 `currentState` 变化、任何 session 被加入或移除、Core 定时器把 `responding` 升级为 `thinking`，都会触发宠物重新聚合。

### 3.2 算法

```swift
func recomputeAggregatedState() {
    let sessions = registry.activeSessions     // 跨所有 AI 工具的活跃 session
    guard !sessions.isEmpty else {
        pet.aggregatedState = .idle             // 无活跃会话 → idle
        pet.drivenBySessionId = nil
        return
    }

    let sorted = sessions.sorted { a, b in
        let pa = priority(a.currentState)
        let pb = priority(b.currentState)
        if pa != pb { return pa < pb }
        if a.stateSince != b.stateSince { return a.stateSince > b.stateSince }
        return a.id < b.id
    }
    let leader = sorted.first!
    pet.aggregatedState = leader.currentState
    pet.drivenBySessionId = leader.id
}
```

### 3.3 边界情况

| 场景 | 行为 |
| --- | --- |
| 所有 session 都被淘汰 | 宠物 → `idle`（保留位置，不消失），但所有气泡随 session 被移除 |
| 单个 session 短暂闪过 `completed`（2s timer） | 仅当该 session 是 leader 时，宠物才会显示 completed 庆祝；否则宠物维持 leader 的状态、该 session 气泡自身播放完成动画 |
| 新 session 接入瞬间为 `idle`（session_start） | 不影响宠物聚合（idle 优先级最低） |
| 宠物 P0 askUser 期间，另一 session 完成（completed） | 宠物保持 askUser 不变；该完成 session 的气泡自播放小庆祝、2s 后回 idle |
| AskUserQuestion 触发时 | 该 session 气泡自动展开为答题卡，用户作答后通过挂起的 PermissionRequest hook 同步回包 `updatedInput.answers`，跨所有终端宿主工作（详见 [features.md §3.4.2](./features.md)） |
| Subagent 触发同步类 hook（permission_ask / ask_user） | `hopet-emit` 识别 `parent_session_id` / `agent_id` 等 subagent 标记，给事件打 `isSubagent=true`；`EventRouter` 同 `transcript_path` 找到主 session 并把事件 reroute 过去——气泡始终挂在用户能看到的主会话上，子 agent 自己不创建气泡 |

### 3.4 反例（明确不做的事）

- ❌ 不做"加权 / 平均"的状态：状态是离散的，平均没有意义
- ❌ 不做"轮播展示所有 session"：宠物只演一种动画，多 session 的差异由气泡承载
- ❌ 不做"按时间衰减优先级"：错误状态不会因为时间过去就降级，必须由后续事件覆盖

---

## 4. 同步与版本

- 本文件、`architecture.md` §7、`features.md` §3.1 三处涉及优先级的描述必须保持一致。任何调整须三处同步修改。
- `EventKind`（`architecture.md` §6.4）的增删需在本文件 §1 表格中同步标注 v0.1 / v0.2。
- 当 Claude Code 官方发布新 hook 时，更新本文件 §1 表格并在 architecture §13 里程碑里规划是否纳入下一版本。
