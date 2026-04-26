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
- 刘海条三态 / 无刘海机型降级顶条
- 默认 "Hopi" 主题（无图，仅状态文字 + 颜色 token）

## v0.1 暂未实现

- 海豹精灵图与 SpriteKit 动画（用文字代替）
- `hopet-pty` PTY wrapper（点击宠物本体走 `open -a Terminal`，输入注入退化为剪贴板）
- Accessibility 注入路径（v0.2）
- 第三方 `.hopettheme` 导入（v0.2）

## 文档

- [devDocs/architecture.md](./devDocs/architecture.md)
- [devDocs/features.md](./devDocs/features.md)
- [devDocs/hooks-and-priority.md](./devDocs/hooks-and-priority.md)
