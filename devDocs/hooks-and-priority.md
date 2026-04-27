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
| 11 | `Notification` | 通知发送 | `notification_type` | 否 | ✅ 注册 → `permission_ask`，仅当 `notification_type == permission_prompt`（兼容回退路径） |
| 12 | `SubagentStart` | Subagent 启动 | `agent_type` | 否 | ⛔ v0.1 不订阅（聚合到主 session 的 toolUse） |
| 13 | `SubagentStop` | Subagent 完成 | `agent_type` | ✅ | ⛔ v0.1 不订阅 |
| 14 | `TaskCreated` | TaskCreate 创建 task | (task metadata) | ✅ | ⛔ v0.1 不订阅 |
| 15 | `TaskCompleted` | task 标记完成 | (task metadata) | ✅ | ⛔ v0.1 不订阅 |
| 16 | `Stop` | Claude 完成回复 | (turn metadata) | ✅ | ✅ 注册 → `stop` |
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

### 1.1 v0.1 实际订阅的 8 个 hook

```
SessionStart → session_start
SessionEnd → session_end
UserPromptSubmit → user_prompt
PreToolUse → ask_user (when tool_name=AskUserQuestion) | pre_tool_use (otherwise)
PostToolUse → ask_user_resolved (when tool_name=AskUserQuestion) | post_tool_use (otherwise)
PostToolUseFailure → error
PermissionRequest → permission_ask
Notification → permission_ask (when notification_type=permission_prompt)
Stop → stop
StopFailure → error
```

> 注：`PostToolUseFailure` / `StopFailure` 是从训练知识里漏掉的事件，把它们纳入后 `error-interrupted` 状态在 v0.1 即拥有真实事件源，无需等 v0.2。

---

## 2. PetState 优先级

新设计中宠物按 **AI 工具** 而非 session 实例化，宠物所展示的 `aggregatedState` 等于其下所有活跃 session 中**优先级最高**的那个 session 状态。

| 优先级 | PetState | 含义 | 选定理由 |
| --- | --- | --- | --- |
| **P0** | `askUser` | Claude 调用 AskUserQuestion 等待用户回答 | 用户操作直接阻塞会话推进，必须最高 |
| **P1** | `permissionPrompt` | Claude 弹出权限请求 | 同样阻塞，但比 askUser 偶尔可"用户跳过"略低 |
| **P2** | `errorInterrupted` | tool / turn 失败 | 用户需感知，但已是终态、不阻塞下一动作 |
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

当同一 AI 下多个 session 处于同一优先级状态时：

1. 先按 `stateSince` 时间倒序（最近变更的在前）
2. 再按 `sessionId` 字母序（确定性）

宠物动画始终展示 tie-break 后第一个 session 的状态。但**该 session 对应的会话气泡**会以"高亮边框"标识当前是它在驱动宠物动画。

---

## 3. 聚合算法

### 3.1 触发条件

每当任何 session 的 `currentState` 变化、任何 session 被加入或移除、Core 定时器把 `responding` 升级为 `thinking`，都会触发对应宠物的重新聚合。

### 3.2 算法

```swift
func recomputeAggregatedState(for tool: AITool) {
    let sessions = registry.activeSessions(of: tool)
    guard !sessions.isEmpty else {
        pet(of: tool).aggregatedState = .idle      // 无活跃会话 → idle
        pet(of: tool).drivenBySessionId = nil
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
    pet(of: tool).aggregatedState = leader.currentState
    pet(of: tool).drivenBySessionId = leader.id
}
```

### 3.3 边界情况

| 场景 | 行为 |
| --- | --- |
| 所有 session 都被淘汰 | 宠物 → `idle`（保留位置，不消失），但所有气泡随 session 被移除 |
| 单个 session 短暂闪过 `completed`（2s timer） | 仅当该 session 是 leader 时，宠物才会显示 completed 庆祝；否则宠物维持 leader 的状态、该 session 气泡自身播放完成动画 |
| 新 session 接入瞬间为 `idle`（session_start） | 不影响宠物聚合（idle 优先级最低） |
| 宠物 P0 askUser 期间，另一 session 完成（completed） | 宠物保持 askUser 不变；该完成 session 的气泡自播放小庆祝、2s 后回 idle |
| AskUserQuestion 触发时 | 该 session 气泡自动展开为答题卡，用户作答后通过挂起的 PermissionRequest hook 同步回包 `updatedInput.answers`，跨所有终端宿主工作（详见 [features.md §3.4.3](./features.md)） |

### 3.4 反例（明确不做的事）

- ❌ 不做"加权 / 平均"的状态：状态是离散的，平均没有意义
- ❌ 不做"轮播展示所有 session"：宠物只演一种动画，多 session 的差异由气泡承载
- ❌ 不做"按时间衰减优先级"：错误状态不会因为时间过去就降级，必须由后续事件覆盖

---

## 4. 同步与版本

- 本文件、`architecture.md` §7、`features.md` §3.1 三处涉及优先级的描述必须保持一致。任何调整须三处同步修改。
- `EventKind`（`architecture.md` §6.4）的增删需在本文件 §1 表格中同步标注 v0.1 / v0.2。
- 当 Claude Code 官方发布新 hook 时，更新本文件 §1 表格并在 architecture §13 里程碑里规划是否纳入下一版本。
