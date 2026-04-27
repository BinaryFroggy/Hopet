# Hopet v0.1 文档评审记录

> 评审对象：[architecture.md](./architecture.md)、[features.md](./features.md)  
> 评审日期：2026-04-26  
> 状态：Draft review notes

---

## 1. 总体结论

两个文档的产品方向清楚：Hopet 的核心价值是把 AI CLI 会话状态转译成桌面宠物和刘海条信号。但 v0.1 目前存在三个主要风险：

1. **状态来源不够可靠**：尤其是权限请求、等待用户回答、Codex 生命周期。
2. **MVP 范围前后不一致**：核心能力、功能矩阵、路线图对多会话、主题导入、注入 session 的描述不完全一致。
3. **落地细节需要收紧**：hook 脚本 JSON 生成、heartbeat 超时、主题 manifest schema、分发策略等都需要在实现前明确。

建议先把 v0.1 定义为：

- Claude Code 优先；
- 默认主题优先；
- 新开终端气泡输入优先；
- 多会话、Codex 细粒度、主题导入、注入 session 均明确降级或后移。

---

## 2. P0 问题

P0 表示会直接影响 Hopet 核心卖点，必须在 v0.1 实现前澄清。

### P0-1：权限请求状态会误报或漏报

相关位置：

- `architecture.md` 8.4 Claude Code hook 样例把 `Notification` 映射为 `permission_ask`
- `features.md` 3.1 把 `permission-prompt` 作为关键高优先级状态

当前设计：

```text
Claude Notification hook -> Hopet permission_ask -> 宠物显示“需要权限确认”
```

问题：

Claude Code 的 `Notification` 不只代表权限请求，也可能代表 idle prompt、认证成功、其他通知。如果 Hopet 把所有 `Notification` 都映射成 `permission_ask`，就会出现误报：

```text
Claude 只是提示正在等待输入
Hopet 却显示红色“需要权限确认”
```

建议修正：

1. 优先使用 Claude Code 的 `PermissionRequest` hook 映射到 `permission_ask`。
2. 如果继续使用 `Notification`，必须加 matcher 或在脚本里判断：

```text
notification_type == "permission_prompt"
```

3. 在 `StateEvent.payload` 中保留 `tool_name`、`tool_input`、`message` 等最小必要字段，方便刘海条显示“需要确认 Bash / Edit / Write”。

### P0-2：`ask-user` 状态目前没有真实入口

相关位置：

- `architecture.md` 6.3 定义了 `PetState.askUser`
- `architecture.md` 7.1/7.2 定义了 `ask_user` 状态转换
- `features.md` 3.1 写了 `ask-user` 动画和通知
- 但 `architecture.md` 8.4 Claude hook 样例没有任何 hook 会 emit `ask_user`

当前问题：

状态机画了：

```text
responding / thinking -> askUser: ask_user
```

但 hook 安装样例只注册了：

```text
UserPromptSubmit
PreToolUse
PostToolUse
Notification
Stop
SubagentStop
SessionStart
```

没有任何一个明确生成：

```json
{ "event": "ask_user" }
```

结果是：`ask-user` 动画和通知在真实运行中可能永远不会出现。

建议修正：

1. 明确 `ask_user` 的事件来源，例如：
   - Claude `Elicitation` / `ElicitationResult`；
   - 某类特定 tool 或 MCP 交互；
   - transcript 解析；
   - 或 `Notification` 的 `idle_prompt` 临时映射。
2. 如果 v0.1 无法可靠识别，就把 `ask-user` 从 v0.1 移到 v0.2，并在 features 矩阵中标注。
3. 如果临时把 `idle_prompt` 映射成 `ask_user`，文档需要说明这是粗粒度状态，不等价于真正的 AskUserQuestion。

---

## 3. P1 问题

P1 表示会影响 MVP 可交付质量，需要在实现计划中处理。

### P1-1：Codex v0.1 “start/stop 基本状态”承诺偏乐观

相关位置：

- `features.md` 2.1 写 Codex v0.1 支持“基本（start/stop）”
- `architecture.md` 8.5 写 Codex 目前以 `notify` 字段为主，初版映射完成事件为 `stop`

问题：

Codex 的 `notify` 更接近“turn 完成通知”，不是完整生命周期 hook。它可以较可靠地告诉 Hopet “一次 turn 完成了”，但很难仅凭它知道：

- session 何时 start；
- 是否正在 responding；
- 是否进入 tool-use；
- 是否需要 permission；
- 是否 ask user。

建议修正：

1. v0.1 功能矩阵改为“Codex 完成通知实验支持”，不要写 start/stop 完整基本链路。
2. 若必须支持 start，需要设计额外 wrapper，例如：
   - Hopet 从气泡新开 Codex 时主动创建 session；
   - 用户通过 `hopet codex` wrapper 启动；
   - 未来通过 MCP 或 Codex hooks 扩展补齐。

### P1-2：v0.1 范围在两个文档之间不一致

相关位置：

- `architecture.md` 1.2 把多会话、多宠物、主题系统、气泡输入列为核心能力
- `architecture.md` 13 又把多会话完整支持、主题导入、注入 session 放到 v0.2
- `features.md` 2.1 写 v0.1 多会话基础 ≤3、主题导入为 v0.2、主题绑定 v0.1 为全局

问题：

读者会不清楚 v0.1 到底交付什么：

- 多会话是 v0.1 还是 v0.2？
- `.hopettheme` 导入是 v0.1 非目标还是 v0.2？
- 空闲气泡是否只新开终端，还是可注入 session？
- Codex 是基本支持还是 v0.2 才完整支持？

建议修正：

把 v0.1 明确成一张“必须交付 / 明确不交付 / 实验支持”表。

建议 v0.1 must-have：

- Claude Code hooks；
- 单会话或最多 3 会话的状态展示；
- 默认 Hopi 主题；
- PetWindow + NotchWindow；
- 气泡输入新开终端；
- Hook 安装与诊断。

建议 v0.1 explicitly out：

- 注入当前 session；
- 自定义主题导入；
- Codex 细粒度状态；
- Sparkle；
- CLI 伴侣。

### P1-3：30 秒 heartbeat 降级会误伤长工具调用

相关位置：

- `architecture.md` 7.3：Session 30s 未收到任何事件且未处于 idle，状态降级为 `idle`

问题：

长时间工具调用很常见，例如：

- `npm install`
- `xcodebuild`
- `pytest`
- 长 Bash 命令
- 大型文件搜索或生成

这些场景可能在 `pre_tool_use` 后几分钟没有任何事件。如果 30 秒无事件就降级 `idle`，宠物会错误显示“空闲”，核心信号失真。

建议修正：

1. `toolUse` 状态不要用 30 秒自动降级。
2. 改为：
   - `responding` 超过 8 秒可切 `thinking`；
   - `toolUse` 保持到 `post_tool_use` / `error` / `stop`；
   - 超长 toolUse 可显示 elapsed timer 或 “执行较久”；
   - orphan session 清理保留 60 分钟策略。
3. 如果需要 heartbeat，需要明确 heartbeat 来源，而不是假设 hook 会持续发送。

### P1-4：Hook 脚本 JSON 拼接不安全

相关位置：

- `architecture.md` 8.4 的 `emit.sh` 样例

当前样例通过 heredoc 拼接 JSON：

```bash
PAYLOAD=$(cat <<JSON
{"schema":1,"sessionId":"$SESSION_ID","tool":"claude-code","event":"$EVENT","timestamp":"$(date -u +%FT%TZ)","cwd":"$PWD","payload":$CC_JSON}
JSON
)
```

问题：

如果 `SESSION_ID`、`PWD`、payload 中包含引号、反斜杠、换行或非法 JSON，可能生成坏 JSON。更严重时，payload 字段可能破坏外层结构。

建议修正：

使用 `jq` 生成 JSON，或提供一个小型 helper binary。示例方向：

```bash
PAYLOAD="$(jq -n \
  --arg sessionId "$SESSION_ID" \
  --arg event "$EVENT" \
  --arg timestamp "$(date -u +%FT%TZ)" \
  --arg cwd "$PWD" \
  --argjson payload "$CC_JSON" \
  '{schema:1, sessionId:$sessionId, tool:"claude-code", event:$event, timestamp:$timestamp, cwd:$cwd, payload:$payload}')"
```

如果不想依赖 `jq`，HopetHookKit 可以安装一个 `hopet-emit` 小工具，由 Swift 负责 JSON 编码和 socket 发送。

### P1-5：Theme manifest 与 Swift model 不一致

相关位置：

- `architecture.md` 6.6：`AnimationClip.frames` 定义为 `[String]`
- `architecture.md` 9.2：manifest 示例中 `frames` 是 glob 字符串

问题：

Swift model：

```swift
let frames: [String]
```

manifest 示例：

```json
"frames": "sprites/idle/*.png"
```

这无法直接 Codable 解码。

另外：

```swift
let animations: [PetState: AnimationClip]
```

如果 JSON key 是 `"tool-use"`、`"permission-prompt"` 这类字符串，最好显式说明需要自定义 decoder，或把类型改为：

```swift
let animations: [String: AnimationClip]
```

建议修正：

1. 二选一：
   - `frames` 统一为数组；
   - 或 model 改为支持 `framesGlob` / `frames`。
2. 文档明确导入时由 `ThemeLoader` 展开 glob，运行时 `ThemePackage` 使用 `[String]`。
3. 把 manifest schema 与 Swift runtime model 分成两个结构，避免概念混用。

---

## 4. P2 问题

P2 表示不会阻塞 MVP，但会影响用户预期、安全性或后续维护。

### P2-1：Homebrew / Gatekeeper 分发表述不准确

相关位置：

- `architecture.md` 4.3 构建与发布

问题：

文档写“Homebrew 会自动 `xattr -d com.apple.quarantine` 绕过 Gatekeeper”，这个表述风险较高。Homebrew Cask 对 quarantine 有自己的处理逻辑，官方 cask 对 Gatekeeper 不可启动的 unsigned app 也可能不接受。

建议修正：

1. 改成更保守的表述：

```text
未公证版本需要用户手动允许打开，或通过自有 tap 分发；是否能进入 Homebrew 官方 cask 取决于签名、公证和 Homebrew 规则。
```

2. v0.1 README 明确说明：
   - unsigned / ad-hoc signed app 的 Gatekeeper 限制；
   - TCC 权限可能在升级后丢失；
   - 推荐打开方式。

### P2-2：隐私边界需要补充“完整 payload 不落盘”

相关位置：

- `architecture.md` 8.4 hook payload 会把 Claude 输入 JSON 放进 `payload`
- `architecture.md` 10.3 写用户 prompt 只存最近一条 256 字符摘要

问题：

Hook 输入可能包含：

- 完整 prompt；
- tool input；
- 文件路径；
- cwd；
- tool response；
- transcript path。

文档虽然说只存 256 字符摘要，但没有明确日志、state、错误报告是否会记录完整 payload。

建议修正：

1. 在隐私章节增加规则：

```text
Core 可以在内存中处理完整 hook payload，但默认不得把完整 prompt、tool_input、tool_response 写入日志或持久化文件。
```

2. 日志只记录：
   - event kind；
   - sessionId hash 或短 id；
   - tool name；
   - timestamp；
   - 错误类型。
3. debug 模式如需记录 payload，必须单独开关并在 UI 明确提示。

### P2-3：全局快捷键需要说明权限和冲突策略

相关位置：

- `features.md` 7：`⌘⇧Space`、`⌘⇧H` 为全局快捷键

问题：

全局快捷键可能与系统、输入法、其他工具冲突。文档只写可自定义或关闭，但没有说明注册失败时如何处理。

建议修正：

1. Behavior Tab 增加快捷键录制/冲突提示。
2. 注册失败时：
   - 菜单栏红点或 warning；
   - 自动禁用该快捷键；
   - 提供重新录制入口。

### P2-4：主题导入需要补充 zip 安全校验

相关位置：

- `architecture.md` 9.3 主题校验规则
- `features.md` 3.6.2 导入 `.hopettheme`

问题：

当前校验关注 schema、文件存在、体积，但没有明确防止 zip slip：

```text
../../somewhere
/absolute/path
symlink escape
```

建议修正：

在 v0.2 主题导入规则中补充：

- 解压前检查 entry path；
- 禁止绝对路径；
- 禁止 `..` 路径穿越；
- 禁止或安全处理 symlink；
- staging 目录使用随机 uuid；
- move 前二次校验最终路径仍在 `~/.hopet/themes` 内。

---

## 5. 建议修改清单

### architecture.md

- 修正 Claude hook 样例：`Notification` 不再无条件映射 `permission_ask`。
- 增加 `PermissionRequest` / `Elicitation` 等事件映射说明。
- 明确 `ask_user` 的真实事件来源，或移出 v0.1。
- 收紧 Codex v0.1 描述，改成实验性完成通知。
- 修改 heartbeat 策略，避免长 toolUse 被误判 idle。
- 重写 `emit.sh` JSON 生成方式。
- 拆分 manifest schema 与 runtime model。
- 调整 Homebrew / Gatekeeper 分发说明。
- 隐私章节补充 payload 不落盘规则。

### features.md

- 调整功能矩阵，明确 v0.1 / v0.2 边界。
- 如果 `ask-user` 不进 v0.1，移到 v0.2 或标注实验。
- Codex v0.1 改成“完成通知实验支持”。
- 多会话 v0.1 写清楚是“最多 3 个基础展示”还是完全后移。
- 快捷键章节补充冲突与注册失败策略。

---

## 6. 待决策问题

1. v0.1 是否正式支持多会话？
2. v0.1 是否保留 `ask-user`，还是只保留 `permission-prompt`？
3. Codex v0.1 是否只做完成通知？
4. 气泡输入 v0.1 是否只允许新开终端？
5. 自定义主题导入是否完全后移到 v0.2？

这些问题先定下来，后续架构文档和功能文档会更容易保持一致。

---

## 7. 外部依据

- Claude Code hooks reference：`Notification`、`PermissionRequest`、`Elicitation`、`UserPromptSubmit` 等 hook 的事件语义。
- OpenAI Codex config reference：Codex 当前配置中的 `notify` 更适合作为完成通知，不等价于完整生命周期 hook。
- Apple `NSScreen` 文档：刘海相关区域应基于 `safeAreaInsets`、`auxiliaryTopLeftArea`、`auxiliaryTopRightArea` 等能力设计。
- Homebrew Cask 文档与规则：未签名 / 未公证 App 的 Gatekeeper 与 quarantine 行为需要保守描述。
