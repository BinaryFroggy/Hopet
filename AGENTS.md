# Hopet · Agent 协作规范

本文件是 Hopet 仓库面向 AI 编码 agent（Claude Code / Codex CLI 等）的唯一权威规范。`CLAUDE.md` 通过 `@AGENTS.md` 引用本文件，规则改动只在本文件进行。

## 0. 项目

macOS 桌面 AI 宠物，将 Claude Code / Codex CLI 的会话生命周期映射到桌面状态。Swift 5.10 / macOS 14+ / SwiftPM。两个 executable target：`Hopet`（App）与 `hopet-emit`（hook 投递 CLI）。

## 1. 文档

- 架构、状态机、优先级、hook 协议的事实之源在 `DevDocs/`。注释引用使用章节级指引，例如 `See architecture.md §7.1`。
- 注释解释意图与约束，不复述代码。
- README 仅描述已实现能力。未实现项需明确标注。

## 2. Swift 代码风格

### 2.1 模块组织

源码位于 `Sources/Hopet/`，按职责分目录：


| 目录         | 职责                                           |
| ---------- | -------------------------------------------- |
| `App/`     | NSApplication 入口、AppDelegate、菜单栏、SceneRouter |
| `Core/`    | 状态机、聚合器、Session 注册表、日志、路径、计时器（纯逻辑、可单测）       |
| `Models/`  | 值类型、enum、Codable 数据结构                        |
| `IPC/`     | Unix Domain Socket、长度前缀帧、hook 同步通道           |
| `HookKit/` | Claude / Codex hook settings 的 merge 安装与卸载   |
| `Pet/`     | 桌面宠物 NSPanel、气泡布局与渲染、权限 / AskUser 交互         |
| `Notch/`   | 刘海条三态渲染与降级顶条                                 |
| `Panel/`   | 偏好面板 Tab 骨架                                  |
| `Theme/`   | 主题包、color token                              |


新增文件应归入贴切的现有目录，不另起新层级。`Sources/hopet-emit/` 为独立 CLI target，禁止反向依赖主 App 符号。

### 2.2 命名与可见性

- 公共类型与 API 显式声明 `public`；模块内部默认 `internal`，省略关键字。
- 工具与算法集合优先使用 caseless `enum` 作为命名空间，参考 `HopetLog`、`SessionStateMachine`、`HopetPaths`。不使用空 `struct` 或全局函数。
- `@MainActor` 标注于面向 UI 的聚合器与控制器，参考 `PetAggregator`。
- 跨模块的异步状态使用 Combine `PassthroughSubject` / `CurrentValueSubject`，避免直接暴露 `@Published`。

### 2.3 实现取舍

- 不实现做不完整的功能，宁可移除。
- 不为假想的未来需求引入抽象。三段相似代码优于一个早产的 protocol。
- 错误处理仅在系统边界进行（用户输入、socket 解码、外部 settings 文件）。模块内部信任调用方，不写防御性 `guard`。
- 日志统一走 `HopetLog`。终端事件流追踪使用 `HopetLog.trace(tag:_:)`，结构化日志使用 `.info / .warn / .error`。禁止使用 `print`。

### 2.4 IPC 与 Hook 协议

- 跨进程消息统一使用长度前缀 JSON 帧，编解码集中在 `IPC/`。业务代码不得自行拼装字节。
- 新增 hook 字段需先更新 `DevDocs/hooks-and-priority.md` 字段表，再修改 `hopet-emit` 的 flag 解析与 `HookKit` 的 settings merge。代码与文档同 PR 提交。
- Permission Allow/Deny 与 AskUserQuestion 同步回包是协议级承诺。修改这两条路径需保留跨终端宿主兼容性。

## 3. 测试与构建

- 构建：`swift build`。运行 App：`swift run Hopet`。运行 CLI：`swift run hopet-emit --help`。
- 提交前 `swift build` 必须通过。`Core/` 下纯逻辑改动应在 `test/` 增补单测；状态机、聚合器、帧解码为高优先级测试对象。
- 不引入外部依赖。`Package.swift` 的 `dependencies: []` 为有意约束。新增依赖须在 PR 描述中说明理由并经人类同意。

## 4. Commit 规范

本仓库遵循 [Conventional Commits 1.0](https://www.conventionalcommits.org/)。subject 使用英文，祈使语态，首字母小写，句尾不加句号。

### 4.1 格式

```
<type>(<scope>): <subject>

<body>

<footer>
```

- 主题行（含 `type(scope):`）不超过 72 字符。
- `(scope)` 可选；`!` 前缀表示破坏性变更，例如 `feat(ipc)!: ...`。
- 主题行与正文之间空一行；正文按 72 列硬换行。
- 一次提交一个意图。混杂改动须拆分。

### 4.2 type


| type       | 用途                          |
| ---------- | --------------------------- |
| `feat`     | 新功能或新能力                     |
| `fix`      | 修复 bug                      |
| `refactor` | 不改变外部行为的内部重构                |
| `perf`     | 性能优化                        |
| `docs`     | 文档变更（README / DevDocs / 注释） |
| `test`     | 仅增补或修复测试                    |
| `build`    | 构建系统、`Package.swift`、产物路径   |
| `ci`       | CI 配置                       |
| `chore`    | 无 source 影响的杂项清理与配置         |
| `revert`   | 回滚提交，正文注明被回滚的 commit hash   |


不在表内的 type 不得发明。删除功能使用 `refactor` 或带 `!` 的破坏性 `feat`，并在正文说明。

### 4.3 scope

scope 与源码目录或职责对齐，全小写。可用值：

`app` · `core` · `models` · `ipc` · `hookkit` · `pet` · `notch` · `panel` · `theme` · `emit` · `docs` · `build`

跨多个 scope 的改动留空 scope，不得使用 `(*)` 或 `(all)`。

### 4.4 subject

- 祈使语态：`add` / `fix` / `remove` / `rename`，不使用过去式或进行时。
- 首字母小写，句尾不加句号。
- 描述变更内容，不复述 diff，不写 PR 编号（PR 编号置于 footer）。
- 超过 72 字符表明主题不够聚焦，应先拆分 commit。

### 4.5 body

- 解释变更动机与权衡，不解释实现细节。
- 涉及 `DevDocs/` 决策时引用章节，例如 `See DevDocs/architecture.md §7.1`。
- 删除能力的提交，正文须说明删除原因。

### 4.6 footer

- 破坏性变更：`BREAKING CHANGE: <说明>`，与主题行 `!` 同时出现。
- 关联 issue：`Closes #123` 或 `Refs #45`。
- 回滚：`Reverts: <commit-sha>`。
- 禁止追加 `Co-Authored-By: Claude ...`、`Generated with ...` 等 AI 署名。

### 4.7 范例

推荐：

```
feat(pet): add soap-bubble visuals and burst transition

Replace the flat circle with a layered gradient and animate state
changes with a brief burst. Permission and AskUser bubbles stay
pinned until resolved.

See DevDocs/features.md §4.3.
```

```
fix(ipc): drop frames whose declared length exceeds the 1 MiB cap

A malformed length prefix could otherwise allocate unbounded memory
before the JSON decoder rejected the payload.

Closes #42
```

```
refactor(core)!: rename SessionStateMachine.transition to nextState

BREAKING CHANGE: callers using `transition(from:event:)` must migrate
to `nextState(from:event:)`. The new name reflects the pure-function
semantics described in DevDocs/architecture.md §7.1.
```

不接受：

```
update bubble                      # 未说明变更内容
Fixed a bug.                       # 大写、句号、过去时、信息缺失
feat: 修了一下气泡                  # subject 使用中文
chore: misc fixes + refactor pet   # 多意图混杂
WIP                                # 不接受 WIP 提交
```

### 4.8 禁止项

- 不得 `git commit --amend` 已 push 的提交。
- 不得 `--no-verify` 跳过 hook；pre-commit 失败应先修复根因。
- 不得提交 `.build/`、`~/.hopet/` 产物或本机绝对路径。
- 不得自动执行 `git push` / `git config` / `git reset --hard`，须经人类显式确认。
- 不得在 commit message 中附 AI 署名或工具尾注。


## 5. AI Agent 协作规则

- 改动代码前先读 `DevDocs/` 对应章节。状态机、聚合器、hook 协议的语义在文档中，凭直觉修改可能破坏跨 session 不变量。
- 不得新建 `*.md` 文件，除非人类明确要求。新增内容应合并入 `DevDocs/` 既有文档。
- UI 改动须本机验证：`swift run Hopet` 启动进程并触发对应 hook 路径，确认行为后再标记完成。`swift build` 通过不构成验证。
- 高风险操作须人类显式确认：删除文件、重命名目录、修改 `Package.swift` 拓扑、修改 hook 协议字段。

### 5.1 PetState 动画资产

切分 sprite sheet 与生成 GIF 预览**必须**调用 `scripts/build-pet-animation.py`，禁止内嵌临时 Python / shell 脚本重复造轮子。该脚本负责：固定 7×N 网格、cell 320×240 切片、自动清空旧帧、透明背景 GIF（magenta sentinel + 共享调色板）、对齐数据校验报告。

新增 / 替换某个 `PetState` 的动画素材：

1. 把源图放到 `DevDocs/assets/seal-<state>-spritesheet.png`，要求：
   - 透明背景 PNG，禁止白底（GIF 1-bit alpha 兜底由脚本处理）
   - 7 列 × N 行（N ∈ {3, 4}）规则等距网格，每帧严格 320 × 240
   - 整图 2240 × 720（21 帧）或 2240 × 960（28 帧）
   - 所有帧海豹本体共基线、水平中心 cx 偏差 ≤ 8 像素（脚本会校验并 warn）
2. 跑 `scripts/build-pet-animation.py <state>`（slug 用 kebab-case，如 `ask-user`、`tool-use`、`permission-prompt`）
3. 在 `Sources/Hopet/Theme/DefaultTheme.swift` 的 `animations` 字典里挂上对应 `PetState`：
   ```swift
   .askUser: FrameAnimation(resourceDirectory: "Resources/Themes/Hopi/seal-ask-user", framesPerSecond: 8)
   ```
4. `swift build` 通过后按 §5 第 3 条本机验证动画在对应状态下播放。

源图不规则（尺寸不整除、白底、行间漂移）时不要在脚本里加兜底逻辑修补单张图，应回到设计工具规整后再喂；脚本是约定的执行入口，不是图像修复器。

带 `-vN` 后缀（`-v2`、`-v3` ……）的源图均为草稿，脚本默认不读取也不应被 agent 主动选用；当且仅当人类显式点名某个版本时才传第二个参数 `scripts/build-pet-animation.py <state> DevDocs/assets/seal-<state>-spritesheet-v3.png` 临时跑一次。

某些 sprite 本体占满画框（典型如 `seal-responding` 海豹+笔记本几乎贴边），SwiftUI 用 `scaledToFit` 渲染后视觉会比其他状态偏大。这种情况用 `--scale` 把内容等比缩到与其他状态视觉一致，画框 320×240 保持不变、四周透明：`scripts/build-pet-animation.py responding --scale 0.82`。缩放在资产层完成，渲染层不需要再做二次缩放。

## 6. 与 `CLAUDE.md` 的关系

`CLAUDE.md` 通过 `@AGENTS.md` 引用本文件。规则改动只在本文件进行，`CLAUDE.md` 不得追加内容。