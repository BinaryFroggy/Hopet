# Hopet

macOS 桌面 AI 宠物，把 Claude Code / Codex CLI 的会话生命周期翻译成桌面上的小动物表情。

> 当前为 v0.1 骨架代码，**所有状态以文字徽章呈现**，海豹动画放在 v0.1.x 主题资源到位后接入。

## 构建与运行

```bash
swift build
swift run Hopet            # 启动 macOS App（菜单栏小图标）
swift run hopet-emit --help # CLI helper（hooks 用它把事件投递到 socket）
```

构建产物：
- `Hopet`：主 App，启动后驻留菜单栏，点击图标可打开管理面板
- `hopet-emit`：长度前缀 JSON 帧投递工具，安装到 `~/.hopet/bin/hopet-emit`

## v0.1 已实现

- 完整状态机（8 态）+ 多 session 聚合 + 优先级 leader 高亮
- Unix Domain Socket IPC，长度前缀帧解码
- `hopet-emit` 全部 flag 支持（`--require` / `--exclude` / 字段路径点号嵌套）
- Claude Code / Codex hook settings 自动 merge 安装与卸载
- 菜单栏 + 偏好面板 7 Tab 骨架
- 桌面宠物 NSPanel + 文字徽章渲染 + 拖拽/位置记忆
- 会话气泡环绕布局算法（含外环 30° 偏移、屏幕边缘适应）
- 气泡上 **Permission Allow/Deny** 与 **AskUserQuestion 结构化答题** —— 通过挂起的 hook socket
  同步回包给 Claude（跨 iTerm / Apple Terminal / VS Code / Cursor 内嵌终端等所有宿主）
- 刘海条三态 / 无刘海机型降级顶条
- 默认 "Hopi" 主题（无图，仅状态文字 + 颜色 token）

## 关于"用 Hopet 给 Claude 发消息"

**v0.1 不做这件事**——既不支持气泡里自由打字注入到已有 session，也不支持点击宠物本体启动新会话。
两件事是同一类问题：macOS 没有可靠的跨终端宿主反向 stdin 注入路径（TIOCSTI 受 controlling tty
限制、AppleScript 仅 iTerm/Terminal、IDE 扩展自己 spawn 的 claude 子进程的 PTY master fd
第三方进程拿不到）；即便用"复制到剪贴板让用户粘贴"作引导，体验也是脱节的。

这不是 Hopet 的核心价值——它是状态感知层，不是 Claude 的输入 UI。要给 Claude 发新消息，照常在
你自己的终端 / Cursor / VS Code 内嵌终端打 `claude`、`codex` 即可，Hopet 通过 hook 自动感知
所有 session 的状态。

例外是 **Claude 主动开口**的两个场景：
- **Permission Allow/Deny**：跨所有宿主工作
- **AskUserQuestion 结构化答题**：跨所有宿主工作

它们走 hook 同步通道（协议级），跟终端注入无关。

## v0.1 暂未实现

- 海豹精灵图与 SpriteKit 动画（用文字代替）
- 第三方 `.hopettheme` 导入（v0.2）

## 文档

- [devDocs/architecture.md](./devDocs/architecture.md)
- [devDocs/features.md](./devDocs/features.md)
- [devDocs/hooks-and-priority.md](./devDocs/hooks-and-priority.md)
