<p align="right">
  <a href="./README.md">English</a> · <b>简体中文</b>
</p>

<p align="center">
  <img src="./DevDocs/assets/hopi-cardboard-box-pixel.png" alt="Hopet" width="160" />
</p>

<h1 align="center">Hopet</h1>

<p align="center">
  一只住在 macOS 桌面上的 AI 宠物，把
  <a href="https://claude.com/claude-code">Claude Code</a> 和
  <a href="https://github.com/openai/codex">Codex CLI</a>
  的会话动态画在你眼前。
</p>

<p align="center">
  <a href="./LICENSE"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT" /></a>
  <img src="https://img.shields.io/badge/Swift-5.10-F05138.svg?logo=swift&logoColor=white" alt="Swift 5.10" />
  <img src="https://img.shields.io/badge/macOS-14%2B-000000.svg?logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-555555.svg?logo=apple&logoColor=white" alt="Apple Silicon | Intel" />
  <img src="https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg" alt="SwiftPM compatible" />
  <img src="https://img.shields.io/badge/SwiftUI-AppKit-007AFF.svg" alt="SwiftUI + AppKit" />
</p>

---

## 项目介绍

Hopet 是一只常驻 macOS 桌面的 AI 编程宠物，它把 Claude Code / Codex CLI 的会话状态变成可见、可感知的桌面反馈：思考、执行工具、等待确认、请求权限、完成或失败，都能通过宠物动画、气泡提示和状态栏表现出来。

它不是另一个聊天窗口，而是一个轻量的工作陪伴层，让开发者在写代码时不用频繁切回终端，也能直观看到 AI agent 当前在做什么、是否需要你介入，以及一次会话是否顺利推进。

Hopet 让本来隐藏在命令行里的 agent 生命周期变得更清楚、更亲近，也让长时间的 AI 协作多了一点秩序和温度。

发布版默认使用内置的 **Hopi 主题**——一只可爱的像素风小海豹，每个状态对应一段动画；如果你想换一只自己的宠物，只要给你的宠物准备一个名字和8张GIF图片拖进去即可。

## 功能

### 会话感知

- **8 态状态机**，覆盖 agent 的每一次有意义的转换：`idle`、`responding`、`thinking`、`tool-use`、`permission-prompt`、`ask-user`、`completed`、`error-interrupted`
- **多 session 聚合**——所有活跃 session 共用一只宠物，宠物始终呈现优先级最高的那个状态（AskUser > Permission > Error > Tool > Thinking > Responding > Completed > Idle）
- **Leader 高亮**——驱动当前宠物状态的那个 session 会被显眼地标出来，让你一眼看清"是谁在找我"

### Hook 集成

- **一键安装 / 卸载** Claude Code 与 Codex CLI 的 hook settings，采用安全的 JSON merge，绝不覆盖你已有的 hook
- **Unix Domain Socket IPC**，所有从 CLI helper 进入 App 的事件都走长度前缀 JSON 帧
- **`hopet-emit` CLI 工具**，完整支持 `--require` / `--exclude` / 点号嵌套字段路径——安装到 `~/.hopet/bin/`，由注册好的 hook 直接调用
- **同步回包通道**——`PermissionRequest` 和 `AskUserQuestion` 的答案沿着同一条挂起的 hook socket 回传给 agent，因此 Allow/Deny 和结构化答题在 iTerm、Apple Terminal、VS Code、Cursor、Ghostty、Warp 等所有终端宿主里行为一致

### 桌面宠物

- **悬浮 `NSPanel`**——盖在普通窗口之上而不抢焦点，跨所有 Space，不出现在 `⌘Tab` 循环里
- **Sprite 动画**——由当前主题驱动，Hopi 主题内置 8 段动画，状态切换时短暂交叉淡入
- **拖拽移动**，位置自动记忆
- **内嵌交互气泡**——权限请求会原位展开为 Allow / Deny / 交给终端 三选一卡片；AskUserQuestion 会展开为分页答题卡，每个问题提供选项按钮和自由文本兜底

### 主题系统

- **内置 Hopi 主题**——8 段像素海豹动画随 App 一同打包
- **自定义主题**——填一个名字 + 准备 8 张 GIF（每个 `PetState` 一张）即可导入；导入流程会通过 UTI 和帧数校验图片，复制到 `~/.hopet/themes/<id>/` 并写入 `manifest.json`，任何一步失败都会整次回滚，目录里绝不会出现半成品
- **从偏好面板直接 Apply / Delete**——用户主题和内置 Hopi 并存，App 升级后仍然保留

### 偏好面板

标准 macOS 偏好窗口，共 7 个 Tab：

| Tab | 用途 |
| --- | --- |
| Overview | 宠物当前状态快照与活跃 session 列表 |
| Themes | 内置主题 + 用户主题，导入 / 应用 / 删除 |
| Appearance | 宠物渲染相关选项 |
| Hooks | Claude Code / Codex hook 安装状态与诊断 |
| Behavior | 拖拽吸附、idle 可见性、动画帧率等 |
| Notifications | 各类横幅通知的分类开关 |
| About | 版本号、构建号、致谢 |

## 效果展示

Hopi 主题覆盖全部 8 个 `PetState`，下方每张 GIF 就是 App 内实际播放的动画，按优先级从高到低排列。

<table width="100%">
  <tr>
    <td align="center" width="25%"><img src="./DevDocs/assets/HopiGif/seal-ask-user.gif" alt="Ask User" width="200" /></td>
    <td align="center" width="25%"><img src="./DevDocs/assets/HopiGif/seal-permission-prompt.gif" alt="Permission Prompt" width="200" /></td>
    <td align="center" width="25%"><img src="./DevDocs/assets/HopiGif/seal-error-interrupted.gif" alt="Error / Interrupted" width="200" /></td>
    <td align="center" width="25%"><img src="./DevDocs/assets/HopiGif/seal-tool-use.gif" alt="Tool Use" width="200" /></td>
  </tr>
  <tr>
    <td align="center" width="25%"><b>Ask User</b></td>
    <td align="center" width="25%"><b>Permission Prompt</b></td>
    <td align="center" width="25%"><b>Error / Interrupted</b></td>
    <td align="center" width="25%"><b>Tool Use</b></td>
  </tr>
  <tr>
    <td align="center" width="25%"><img src="./DevDocs/assets/HopiGif/seal-thinking.gif" alt="Thinking" width="200" /></td>
    <td align="center" width="25%"><img src="./DevDocs/assets/HopiGif/seal-responding.gif" alt="Responding" width="200" /></td>
    <td align="center" width="25%"><img src="./DevDocs/assets/HopiGif/seal-completed.gif" alt="Completed" width="200" /></td>
    <td align="center" width="25%"><img src="./DevDocs/assets/HopiGif/seal-idle.gif" alt="Idle" width="200" /></td>
  </tr>
  <tr>
    <td align="center" width="25%"><b>Thinking</b></td>
    <td align="center" width="25%"><b>Responding</b></td>
    <td align="center" width="25%"><b>Completed</b></td>
    <td align="center" width="25%"><b>Idle</b></td>
  </tr>
</table>

<p align="center">
  <img src="./DevDocs/assets/hopi-permission.gif" alt="Hopi permission prompt" width="535" />
</p>

## 快速开始

环境要求：macOS 14+，Swift 5.10+。

一条命令搞定——首次运行会自动编译两个 target 并启动 App：

```bash
swift run Hopet
```

App 起来后，去 **Hooks** Tab 给 Claude Code（以及 Codex，如果你用的话）点一下 _Install_。安装是非破坏性的，可以随时在同一面板撤销；这一步也会把 `hopet-emit` helper 复制到 `~/.hopet/bin/`。

想换一只自己的宠物，进 **Themes** Tab，点 _Import Theme…_，填一个名字，选好 8 张 GIF（每个状态一张）即可。

### 构建产物与故障排查

工程会产出两个可执行文件，日常用的时候不需要手动调用——`swift run Hopet` 自动 build，Hooks Tab 的安装步骤会把 helper 落到位。

- **`Hopet`**——主 App，启动后驻留菜单栏，点击图标打开偏好面板
- **`hopet-emit`**——长度前缀 JSON 帧投递工具，安装到 `~/.hopet/bin/hopet-emit`，由 Claude Code / Codex CLI 的 hook 自动调用

排查问题时可能用到：

```bash
swift build                  # 只编译两个 target，不启动 App
swift run hopet-emit --help  # 查看 CLI helper 支持的 flag
```

## 架构与协议

- [DevDocs/architecture.md](./DevDocs/architecture.md)——状态机、聚合器、IPC 帧格式与模块边界
- [DevDocs/features.md](./DevDocs/features.md)——功能清单与 UI 行为的详细说明
- [DevDocs/hooks-and-priority.md](./DevDocs/hooks-and-priority.md)——hook 事件 schema 与优先级解析
- [DevDocs/preferences.md](./DevDocs/preferences.md)——偏好项键值与主题导入契约

## 许可

许可信息见仓库根目录。
