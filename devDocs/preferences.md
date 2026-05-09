# Hopet · 管理面板（Preferences v0.2）设计

> 本文件是「管理面板」子系统的事实之源。代码与本文档同 PR 修改，注释引用使用章节级路径，例如 `See preferences.md §5.3`。
>
> 与 `architecture.md` / `features.md` 的关系：本文档不复述全局状态机与 hook 协议，仅描述菜单栏入口下的偏好面板（Preferences 窗口）的结构、数据模型与运行时行为。

---

## §1 目标与非目标

### §1.1 目标

在现有 Preferences 窗口中扩展三块能力，从菜单栏 "Open Preferences…" 入口直达：

1. **宠物管理**：选择启用哪一套宠物主题；支持上传自定义主题（每个 PetState 一份 GIF + 主题名），运行时解析 GIF 作为对应状态动画。
2. **外观**：明亮 / 深色 / 跟随系统。
3. **监听设置**：勾选要监听的 AI 终端（Claude Code / Codex …），Claude Code 默认勾选。

并将上述设置持久化到 `~/.hopet/config.json`，启动时恢复。

### §1.2 非目标（v0.2 不做）

- 导入 `.hopettheme` zip 包（保留给 v0.3，含 zip slip 防护）。
- 主题市场 / 远程同步。
- Codex 监听的真实 install 路径。Codex 在 UI 上以可勾选项呈现，但底层 `HookInstaller.install(.codex)` 仍按现状报 unimplemented；v0.2 将 listener 写入 config，不真正调用 install。
- 自定义主题的 `accentOverrides`、`glyphs` 自定义。
- 自定义主题作者元信息编辑、版本号、签名。

---

## §2 入口与窗口

- 菜单栏入口：保持 `MenuBarItem.swift` 现有的 "Open Preferences…" 菜单项，**不新增菜单项**。
- 窗口：沿用 `PreferencesWindowController` 单例（NSWindow + SwiftUI HostingController）。
- TabView 顺序变更：在 **Themes** 与 **Bindings** 之间插入新 **Appearance** Tab。其余 6 个 Tab 顺序不变。

最终 Tab 顺序：

```
Overview · Themes · Appearance · Bindings · Hooks · Behavior · Notifications · About
```

监听设置仍归 **Hooks** Tab，不另起新 Tab——避免与现有 HookDoctor / 安装流程割裂。

---

## §3 Tab 映射

| 用户需求 | 落点 | 改动概览 |
|---|---|---|
| 宠物管理 | 增强 `ThemesTab` | 新增 "Import Theme…" 按钮、自定义主题列表项、Delete 按钮；用 `FrameAnimationView` 渲染主题预览首帧（替换占位 🦭）；按 §11 像素风规范包裹 |
| 外观 | 新增 `AppearanceTab` | 单 Picker（明亮 / 深色 / 跟随系统），实时生效；按 §11 像素风规范渲染 |
| 监听设置 | 重做 `HooksTab` | 把 Install/Uninstall 双按钮收敛为 Toggle 列表；Claude Code 默认开；Codex 显示但底层 install 报错时不致命，UI 层退回未勾选并提示；按 §11 像素风规范渲染 |

不动其他 Tab：Overview / Bindings / Behavior / Notifications / About 保持原样（但 §11 复用部件提升后，它们也会自然继承像素外壳，无需逐个改写）。Bindings 因 `themes.themes` 增加用户主题项而自然受益，无需修改。

> **整体风格约束**：所有 Tab 内容的视觉规范见 §11，与宠物气泡、刘海条同语言（pixel pitch=2、阶梯圆角、硬黑描边、块状投影、顶部高光、亮/暗自适应）。

---

## §4 数据模型

### §4.1 `FrameAnimation` 改为 enum（破坏性，仅 App 内部）

当前形态：

```swift
public struct FrameAnimation: Hashable, Sendable {
    public let resourceDirectory: String
    public let framesPerSecond: Double
}
```

改为：

```swift
public enum FrameAnimation: Hashable, Sendable {
    /// 内置主题：Bundle 内 PNG 帧序列目录。沿用现有 build-pet-animation.py 产物。
    case bundlePNG(directory: String, framesPerSecond: Double)

    /// 用户主题：~/.hopet/themes/<id>/<state>.gif
    case gifFile(url: URL)
}
```

破坏性影响：

- `DefaultTheme.hopiAnimations()` 改为构造 `.bundlePNG(directory:framesPerSecond:)`，行为等价。
- 所有 `FrameAnimation(resourceDirectory:framesPerSecond:)` 调用点（实施期 grep 全仓）改为 `.bundlePNG(...)`。
- 调用方读取 `framesPerSecond` 的代码（`FrameAnimationView` 内部）改为 switch enum。

不向外暴露第三种 case。`accentOverrides` / `glyphs` 与 enum 无关，不受影响。

### §4.2 `ThemePackage` 扩展

```swift
public struct ThemePackage {
    // …已有字段保持不变…
    public let isUserProvided: Bool      // 默认 false；用户主题为 true，可在 ThemesTab 删除
    public let sourceDirectory: URL?     // 用户主题目录绝对路径；nil 表示内置
}
```

`DefaultTheme.hopi` 显式传 `isUserProvided: false, sourceDirectory: nil`。

### §4.3 `HopetConfig`（新增 Codable）

落盘到 `HopetPaths.configFile` = `~/.hopet/config.json`。

```jsonc
{
  "version": 1,
  "appearance": "system",          // "light" | "dark" | "system"
  "activeThemeId": "hopi.default",
  "listeners": {
    "claudeCode": true,
    "codex": false
  }
}
```

字段约束：

- `version`: 当前固定 `1`，未来 schema 演进时用于迁移。读到未知 version 降级到默认值并 `HopetLog.warn`。
- `appearance`: 仅接受三个枚举字符串；未知值降级 `"system"`。
- `activeThemeId`: 启动时若指向不存在的主题（用户删除目录后），降级 `"hopi.default"`。
- `listeners.claudeCode` 默认 `true`；首次创建 config 时即写入 `true`，对应 §1.1「Claude Code 默认勾选」。
- `listeners.codex` 默认 `false`，留给 v0.3 真实启用。

新增 `Sources/Hopet/Core/HopetConfig.swift`：纯 Codable 值类型 + 静态 `load()` / `save()`，错误降级而非抛出。

---

## §5 自定义主题文件协议

### §5.1 目录结构

```
~/.hopet/themes/
  <user-theme-id>/
    manifest.json
    idle.gif
    thinking.gif
    responding.gif
    tool-use.gif
    permission-prompt.gif
    ask-user.gif
    completed.gif
    error-interrupted.gif
```

文件名严格对齐 `PetState.rawValue`（见 `Sources/Hopet/Models/PetState.swift`），共 8 个 GIF 文件。**任意一个缺失 = 主题非法**（§5.3 校验）。

### §5.2 manifest.json

```jsonc
{
  "schemaVersion": 1,
  "id": "user.<slug>.<uuid8>",
  "name": "<用户输入>",
  "createdAt": "2026-05-09T12:34:56Z"
}
```

字段说明：

- `schemaVersion`: 当前固定 `1`；未来字段扩展按版本号迁移。
- `id`: 由 App 生成，格式 `user.<slug>.<uuid8>`。
  - `slug`：用户输入名经规整（小写、ASCII、空格转连字符、剥离非字母数字）；空 slug 时填 `theme`。
  - `uuid8`：UUID 前 8 字符；防止重名碰撞。
  - 与内置 `hopi.default` 命名空间不重叠（前缀 `user.` 强保留）。
- `name`: 用户在导入 sheet 中填写的展示名，长度上限 32 字符（UTF-8 截断）。
- `createdAt`: ISO8601 字符串，仅作元数据展示，不参与排序逻辑。

启动期扫描：`ThemeStore.reload()` 遍历 `~/.hopet/themes/*/manifest.json`，解码失败的目录跳过并 `HopetLog.warn`，不阻断其他主题加载。

### §5.3 导入流程（UI 行为）

1. 用户在 ThemesTab 点 "Import Theme…"。
2. SwiftUI sheet 弹出，包含：
   - 主题名输入框（必填，trim 后非空）。
   - 8 个 GIF 拖拽 / 选择槽，按 `PetState.allCases` 顺序排列：idle → thinking → responding → toolUse → permissionPrompt → askUser → completed → errorInterrupted。每槽显示状态英文名 + 状态色圆点，便于对照。
   - 每槽支持：拖拽 GIF 文件落入；点击调起 NSOpenPanel（仅允许 `.gif` UTI）；选中后显示文件名 + 缩略首帧。
3. "Import" 按钮启用条件：主题名非空 ∧ 8 槽全部选中。任一槽空则按钮禁用，sheet 底部红字列出缺失状态名。
4. 点击 Import：
   1. 生成 `id`，创建 `~/.hopet/themes/<id>/`。
   2. 对 8 个源文件依次调用 `CGImageSourceCreateWithURL` 校验：
      - 必须能创建 source。
      - 帧数 ≥ 1。
      - UTI 必须是 `public.gif`（避免改后缀绕过）。
   3. 任一校验失败 → 删除半成品目录、报错红字、保留 sheet 内容供修正。
   4. 全部通过 → 复制 8 个 GIF 到目录，重命名为 `<rawValue>.gif`。
   5. 写 `manifest.json`。
   6. 关闭 sheet，触发 `ThemeStore.reload()`，新主题出现在列表。
   7. **不自动设为 active**；用户在列表里手动点 "Apply"。
5. 错误 / 边界：
   - 用户取消 sheet：不创建任何文件。
   - 同名（slug 相同）多次导入：`uuid8` 保证 id 不冲突，不阻断；ThemesTab 列表会同时显示两条同名主题。文档登记此为已知边角，v0.2 不去重。
   - 写文件失败（磁盘满 / 权限）：回滚已复制文件并删除目录，保留 sheet。

### §5.4 删除自定义主题

- ThemesTab 列表项对 `isUserProvided == true` 的主题显示 "Delete" 按钮。
- 点击后 NSAlert 二次确认（"Remove theme '<name>'? GIF files will be deleted."）。
- 确认后：
  - 若该主题为当前 active：先把 `activeThemeId` 切回 `"hopi.default"` 并落盘 config，再删目录。
  - 否则直接删目录。
- 内置 `hopi.default` 不显示 Delete 按钮。

---

## §6 运行时

### §6.1 启动顺序

`SceneRouter.boot()` 在现有 `applicationDidFinishLaunching` 流程基础上插入新步骤（粗体为新增）：

1. `HopetPaths.ensureDirectories()`（已有，确保 `~/.hopet/themes/` 存在）。
2. **`HopetConfig.load()`**：读 `config.json`，文件不存在则用默认值并立即 `save()` 落盘，建立首次安装基线。
3. **`applyAppearance(config.appearance)`**：在 SceneRouter 的 `@MainActor` 上调用 `NSApp.appearance = NSAppearance(named: ...)`：
   - `light` → `.aqua`
   - `dark`  → `.darkAqua`
   - `system` → `nil`（清空 override，跟随系统）
4. `ThemeStore` 初始化：构造时持有 `ConfigStore` 引用；调用 `reload()`：
   - 把 `[DefaultTheme.hopi]` 作为基底。
   - 扫描 `~/.hopet/themes/*/manifest.json`，构造用户 `ThemePackage`（含 8 个 `.gifFile(url:)`）。
   - `activeThemeId = config.activeThemeId`，若 id 不在 `themes` 中则降级 `"hopi.default"` 并写回 config。
5. **按 `config.listeners` 调用 `HookInstaller.install/uninstall`**：仅当当前安装态与 config 不一致时执行变更，避免每次启动都重写 `~/.claude/settings.json`。Codex 路径调用失败仅 `HopetLog.warn`，不影响启动。
6. 后续：SocketServer / 宠物窗口启动等，均沿用现状。

### §6.2 ConfigStore（@MainActor ObservableObject）

新增 `Sources/Hopet/Core/ConfigStore.swift`：

```swift
@MainActor
public final class ConfigStore: ObservableObject {
    @Published public private(set) var current: HopetConfig
    public init(initial: HopetConfig) { self.current = initial }

    public func update(_ mutate: (inout HopetConfig) -> Void) {
        var next = current
        mutate(&next)
        guard next != current else { return }
        current = next
        do { try next.save() } catch { HopetLog.warn(...) }
    }
}
```

调用方：

- `AppearanceTab` 通过 `@ObservedObject` 注入，绑定到 Picker。
- `HooksTab` 写 `listeners`。
- `ThemeStore` 读写 `activeThemeId`。

落盘失败不回滚内存值——优先 UI 响应正确，下一次成功 save 会覆盖；这与项目 `Core/` 的「错误处理仅在系统边界」原则一致（见 AGENTS.md §2.3）。

### §6.3 GIF 渲染

新增 `Sources/Hopet/Pet/GIFAnimationView.swift`：

- 输入 `URL`（指向 `~/.hopet/themes/<id>/<state>.gif`）。
- 启动时一次性解码：用 `CGImageSourceCreateWithURL(url, nil)` 读所有帧；每帧读取：
  - `CGImageSourceCreateImageAtIndex` → `NSImage`
  - `CGImageSourceCopyPropertiesAtIndex` → `kCGImagePropertyGIFDictionary` → `kCGImagePropertyGIFUnclampedDelayTime`，回退 `kCGImagePropertyGIFDelayTime`，再回退 0.1s。
- 累积帧时间线：`durations: [TimeInterval]`，`totalDuration = sum`，每个 tick 用 `(elapsed % totalDuration)` 二分定位当前帧 index。这样保留 GIF 内嵌的可变帧延迟（决策见用户答复 §0）。
- 渲染：`TimelineView(.animation(minimumInterval: minDuration))` 包裹 `Image(nsImage:)`，缩放 `.scaledToFit()`，与 `FrameAnimationView` 视觉一致。
- 缓存：模仿现有 `FrameImageCache` 模式，新增 `GIFFrameCache`，key = `URL.path` + `mtime`（`FileManager.default.attributesOfItem(...)` 取 `.modificationDate`）。删除/重导入主题后 mtime 变化即自动失效，无需手动 invalidate。

`Sources/Hopet/Pet/FrameAnimationView.swift` 改为 dispatcher：

```swift
struct FrameAnimationView: View {
    let animation: FrameAnimation
    var body: some View {
        switch animation {
        case .bundlePNG(let dir, let fps): BundleFrameRenderer(directory: dir, fps: fps)
        case .gifFile(let url):            GIFAnimationView(url: url)
        }
    }
}
```

`BundleFrameRenderer` 即现有 `FrameAnimationView` 实现内联化的私有 View。外层 API 形态不变，所有调用点（`PetStageView` 等）不需要改。

### §6.4 外观切换实时生效

- `AppearanceTab` 内 Picker 绑定 `config.appearance`。
- `ConfigStore.update { $0.appearance = .dark }` 触发 `objectWillChange`。
- `SceneRouter` 订阅 `ConfigStore.$current.removeDuplicates(by: \.appearance)`，每次变化调用 `applyAppearance(_:)`。
- SwiftUI 视图通过 `@Environment(\.colorScheme)` 自然重绘，NSPanel / 刘海条 / 气泡均跟随。
- 切换时机：用户操作即时生效，不需重启。落盘异步发生（`ConfigStore.save` 同步写但失败不影响 UI）。

---

## §7 受影响的代码点

实施期参照本表分阶段提交（每阶段独立 commit，subject 形如 `feat(panel): ...`，遵循 AGENTS.md §4）：

| 文件 | 性质 | 说明 |
|---|---|---|
| `Sources/Hopet/Core/HopetConfig.swift` | 新增 | Codable 值类型 + load/save |
| `Sources/Hopet/Core/ConfigStore.swift` | 新增 | @MainActor ObservableObject 包裹 |
| `Sources/Hopet/Theme/PixelChrome.swift` | 新增 | 把 `SessionBubbleView` 内 `private` 的 `PixelChrome` / `PixelRoundedRectangle` / `PixelButtonStyle` 提升为 `internal`，再补面板专用部件（见 §11.2） |
| `Sources/Hopet/Pet/SessionBubbleView.swift` | 修改 | 删除内部 private 像素部件实现，改为 `import` 自 `Theme/PixelChrome.swift`；外观行为零变化 |
| `Sources/Hopet/Theme/ThemePackage.swift` | 修改 | `FrameAnimation` 改 enum；`ThemePackage` 加 `isUserProvided` / `sourceDirectory` |
| `Sources/Hopet/Theme/DefaultTheme.swift` | 修改 | 调整 enum case 构造，行为等价 |
| `Sources/Hopet/Theme/ThemeStore.swift` | 修改 | 注入 `ConfigStore`；新增 `reload()`；`activeThemeId` 持久化（didSet → ConfigStore） |
| `Sources/Hopet/Theme/UserThemeImporter.swift` | 新增 | sheet 提交后的校验、落盘、回滚 |
| `Sources/Hopet/Pet/FrameAnimationView.swift` | 修改 | 拆为外层 dispatcher；保留现有 PNG 渲染逻辑为私有 `BundleFrameRenderer` |
| `Sources/Hopet/Pet/GIFAnimationView.swift` | 新增 | ImageIO 解码 + GIFFrameCache |
| `Sources/Hopet/Panel/PreferencesView.swift` | 修改 | 注册新 `AppearanceTab`，调整 TabView 顺序 |
| `Sources/Hopet/Panel/ThemesTab.swift` | 修改 | "Import Theme…" 按钮、导入 sheet、Delete 按钮、预览首帧 |
| `Sources/Hopet/Panel/AppearanceTab.swift` | 新增 | 三选一 Picker |
| `Sources/Hopet/Panel/HooksTab.swift` | 修改 | Toggle 列表替换 Install/Uninstall 按钮；Codex 占位 |
| `Sources/Hopet/App/SceneRouter.swift` | 修改 | boot() 接入 ConfigStore；订阅 appearance 变化 |
| `Sources/Hopet/App/AppDelegate.swift` | 修改（如需） | 把 ConfigStore 注入到 PreferencesView 构造 |
| `test/HopetConfigTests.swift` | 新增 | 编解码、未知 version 降级、缺字段降级 |
| `test/UserThemeImporterTests.swift` | 新增 | 缺帧拒绝、坏 GIF 拒绝、id slug 规整、重名碰撞 |

实施分阶段建议：

- **阶段 A**：`HopetConfig` + `ConfigStore` + `SceneRouter` 接入（最小风险，不改 UI）。
- **阶段 A'（与 A 并行可做）**：把 `SessionBubbleView` 内 private 的像素部件提升到 `Theme/PixelChrome.swift`，作为 §11 基建。提升前后宠物气泡视觉应像素级一致（截图对比）。
- **阶段 B**：`AppearanceTab`（用户最易直观验证；同步使用 §11 部件）。
- **阶段 C**：`HooksTab` 改 Toggle（行为收敛但不引入新格式；用 §11 `PixelToggle` 渲染）。
- **阶段 D**：`FrameAnimation` enum 化 + `GIFAnimationView` + `UserThemeImporter` + `ThemesTab` 增强（最大块，依赖前三阶段稳定；导入 sheet 用 §11 `PixelDropSlot`）。

---

## §8 验证

`swift build` 通过仅是入门门槛，UI 改动须按 AGENTS.md §5 在 `swift run Hopet` 中本机验证。本节列出验收剧本：

1. **首次启动**：
   - 删除 `~/.hopet/config.json`，启动 App；检查 `~/.hopet/config.json` 被自动创建为默认值（appearance=system, activeThemeId=hopi.default, listeners.claudeCode=true）。
2. **外观实时切换**：
   - 切换 Picker 在「明亮」「深色」「跟随系统」之间循环；观察 NSPanel 背景、刘海条颜色、宠物气泡（SessionBubbleView）三处随之翻转。
   - 重启确认偏好恢复。
3. **默认主题动画**：
   - 触发 Claude Code 会话；观察 hopi 主题在 8 个状态下的 PNG 帧动画播放。期望与 v0.1 表现完全一致（回归基线）。
4. **导入合法自定义主题**：
   - 准备 8 个测试 GIF（任意分辨率），从 ThemesTab 点 Import Theme…，命名 "test-cat"，全部填入；点 Import；列表新增条目；点 Apply；触发会话验证 GIF 在对应 PetState 下渲染、帧率符合 GIF 内嵌 delay。
5. **拒绝缺帧上传**：
   - 只填 7 个槽，确认 Import 按钮禁用且 sheet 底部红字列出缺失状态名。
   - 故意改名 `.png` 为 `.gif` 拖入，确认 ImageIO 校验失败、整次回滚、目录不残留。
6. **删除当前 active 主题**：
   - 把 "test-cat" 设为 active；点 Delete；确认 active 自动切回 hopi.default、目录被删、宠物动画立即切换。
7. **监听 Toggle**：
   - 取消勾选 Claude Code → `HookDoctor` 显示未安装、`~/.claude/settings.json` 的 hopet 段被移除。
   - 重新勾选 → 重新安装。
   - Codex 勾选时 UI 不崩溃（底层 install 报 unimplemented，UI 提示「Codex 待 v0.3 启用」并保留勾选状态写入 config）。
8. **持久化**：
   - 完整修改三块设置 → 重启 App → 全部恢复。
9. **降级容错**：
   - 手动把 `~/.hopet/config.json` 写成非法 JSON → 启动 App 不崩溃，落回默认值并 warn。
   - 手动删除 `~/.hopet/themes/<active-id>/` → 启动 App，active 降级 `hopi.default`，config 自动写回。
10. **像素风一致性**（§11 验收）：
    - 把宠物气泡与 Preferences 各 Tab 截图横向对比：圆角阶梯颗粒、描边粗细、顶部高光带、块状投影偏移在亮 / 暗两套主题下视觉同源。
    - Tab 间切换时各 Tab 的卡片边距、按钮规格、字体度量一致（`PixelButtonStyle` / `PixelChrome` 默认值生效）。
    - 阶段 A' 提升 `PixelChrome` 后，宠物气泡截图与提升前像素级一致（无回归）。

单测覆盖（`swift test`）：

- `HopetConfigTests`: 编解码 round-trip、未知 version、缺字段、非法枚举值降级。
- `UserThemeImporterTests`: 8 槽完备性、UTI 校验、slug 规整、目录回滚（用 tmp 目录）。

不为以下场景写单测（成本高、收益低）：

- GIF 帧解码细节——交给 `GIFAnimationView` 在本机回归剧本中肉眼确认。
- AppKit `NSApp.appearance` 行为——交给本机验证。

---

## §9 开放问题

留给实施期登记，不阻塞 v0.2：

- 自定义主题 GIF 是否需要分辨率 / 文件大小 / 时长上限？v0.2 不限制；登记为观察项，若用户上传 4K 长 GIF 导致内存膨胀再加阈值。
- 自定义主题导入是否暴露 `accentOverrides` / 自定义 `glyphs`？v0.2 不暴露，沿用默认色板与 PetState glyph fallback。
- BindingsTab 在用户主题加入后是否需要新交互？当前 BindingsTab 已基于 `themes.themes` 渲染，自动受益；若用户希望按主题 × 工具粒度配置，留 v0.3。
- `manifest.json` 是否需要校验 `schemaVersion`？v0.2 仅认 `1`，未知版本跳过加载并 warn。
- 主题列表是否需要排序（内置优先、用户按 createdAt）？v0.2 默认顺序：内置 → 用户主题按 `createdAt` 升序。

---

## §10 与既有文档的关系

- `architecture.md`：本面板不引入新状态机或 IPC 协议，仅消费 `Theme/`、`HookKit/`、`Core/HopetPaths`。无需修改 architecture。
- `features.md`：「外观偏好」与「自定义主题」属于偏好面板局部能力，不进入用户场景叙事；不在 features 中重复描述。
- `hooks-and-priority.md`：监听 Toggle 不改变 hook 字段语义，不影响该文档。

如未来面板规模扩张到独立子系统（含独立菜单 / 命令面板等），再考虑把本文件拆分为 `panel-architecture.md` + `panel-themes.md`。

---

## §11 像素风视觉一致性

> **核心原则**：Preferences 面板与桌面宠物气泡、刘海条共用一套 8-bit 像素风视觉语言。用户在「会话气泡上看到的圆角阶梯」与「Preferences 卡片上看到的圆角阶梯」必须像素级同源——这是把"管理面板"拉回 Hopet 主语境（而不是看起来像系统设置）的关键。

### §11.1 设计原则

1. **像素 pitch = 2pt**：所有阶梯几何（圆角、阴影偏移、高光带高度）以 2pt 为最小单位对齐。低于 2pt 的像素感会在 Retina 下被抗锯齿吞掉。
2. **硬黑描边**：所有边缘用纯黑（亮模式 `Color.black.opacity(0.85)`，暗模式同值）描线，宽度 1.5pt 起步。**绝不**使用系统默认的半透明灰描边。
3. **块状阴影**：投影是硬偏移、零模糊的纯色矩形（不是 `.shadow(radius:)`）。偏移量恒为 `pixel * 2 = 4pt`，方向自上而下。
4. **顶部高光带**：内层最顶端 4px 为白色不透明带（亮模式 0.45 / 暗模式 0.18），强化"自上方光源"的复古 UI 错觉。
5. **明暗双套**：light 用近白冷调底（RGB 0.97/0.97/0.99）+ accent 10% 染色；dark 用近黑冷调底（RGB 0.13/0.13/0.16）+ accent 40% 染色。亮 / 暗各自保 4:1+ 文字对比度。
6. **字体**：以系统等宽（`.system(_, design: .monospaced)`）为主，权重 bold / semibold；标题与按钮文字必须等宽。说明性长文允许用默认 SF Pro。**不引入第三方位图字体**——`Package.swift` 的依赖白名单仍为空（AGENTS.md §3）。
7. **抗锯齿**：所有装饰性图像（主题预览首帧、状态色圆点等）渲染时关闭插值（`.interpolation(.none)`、`.antialiased(false)`），保持像素硬边。
8. **过渡**：交互过渡用 `.linear(duration: 0.05)` 这类极短直线动画，避免缓动带来的"现代感"。

### §11.2 视觉资产清单

#### §11.2.1 已有部件（提升）

当前定义在 `Sources/Hopet/Pet/SessionBubbleView.swift` 内为 `private`，本次提升到 `Sources/Hopet/Theme/PixelChrome.swift`，可见性改 `internal`，对外即模块内任意视图可用：

| 部件 | 类型 | 提升前位置 | 提升后位置 |
|---|---|---|---|
| `PixelChrome` | `ViewModifier` | `SessionBubbleView.swift:609` | `Theme/PixelChrome.swift` |
| `PixelRoundedRectangle` | `Shape` | `SessionBubbleView.swift:667` | `Theme/PixelChrome.swift` |
| `PixelButtonStyle` | `ButtonStyle` | `SessionBubbleView.swift:718` | `Theme/PixelChrome.swift` |

提升的硬约束：

- **像素级零回归**：`SessionBubbleView` 改用提升后的部件后，宠物气泡视觉必须像素级一致（截图 diff 通过）。这是阶段 A' 的验收门槛。
- **不改公开 API 形态**：`PixelChrome(cornerRadius:accent:strokeWidth:strokeColor:)` 调用形态保持不变；只改 access level 和文件位置。
- **保留现有注释**：`PixelChrome` / `PixelRoundedRectangle` 头部的视觉语言注释整段搬迁，不重写。

#### §11.2.2 新增部件（面板专用）

| 部件 | 类型 | 用途 |
|---|---|---|
| `PixelCard` | `View` | `PixelChrome` 的便捷外壳：卡片背景 + 默认 padding（12pt）。ThemesTab 列表项、Hooks Toggle 行、Appearance Picker 容器都用它。 |
| `PixelToggle` | `View` | 像素方块开关，替代 SwiftUI `Toggle`。两态视觉：未开 = 灰底空心方框 + 黑描边；开 = accent 染色实心方框 + 顶部白高光 + 块状投影。Hooks Tab 用。 |
| `PixelSegmentedControl<Value: Hashable>` | `View` | 像素分段，替代 SwiftUI `Picker(.segmented)`。AppearanceTab（明亮 / 深色 / 跟随系统）用。每段是一个 `PixelButtonStyle.secondary`，选中段切到 `prominent` 风格。 |
| `PixelDropSlot` | `View` | 文件拖拽 / 选择槽，替代默认的虚线框。空槽 = 阶梯虚线边框 + 中央 monospaced 文案；填充后 = 缩略首帧 + 文件名 + 状态色圆点。导入 sheet（§5.3）用 8 个。 |
| `PixelTextField` | `View` | 像素输入框，包裹系统 `TextField` + `PixelChrome` 背景 + 关闭系统 focus ring，自绘 1.5pt 黑描边在 focus 态加亮高光带。导入 sheet 的主题名输入用。 |
| `PixelScrollThumb` | `View` | 像素滚动条拇指。已经在 `feat(pet): scroll bubble list with pixel scroll thumb` 提交里为气泡列表实现过；本次同步提升到 `Theme/PixelChrome.swift`，Preferences 长列表（ThemesTab 多主题）复用。 |

> 命名约定：所有部件统一以 `Pixel` 前缀；放在 `Sources/Hopet/Theme/PixelChrome.swift` 单文件，超过 400 行时再按部件拆分。

#### §11.2.3 不像素化的部件

为避免破坏键盘 / VoiceOver / 双击编辑等系统级行为，以下部件 **保留系统外观**：

- macOS 原生 `TabView` 顶部分段：保持系统外观，仅对每个 Tab 的内容容器像素化。`TabView` 顶部条与窗口标题栏视觉上算"系统 chrome"，强行像素化会割裂 macOS 习惯（cmd+W、Tab 切换、tooltip 等）。
- 窗口标题栏 / 红黄绿按钮：完全保留系统外观。
- `NSAlert` 二次确认（删除主题）：保留系统对话框，不自绘。
- 文件选择 `NSOpenPanel`：系统对话框。
- 上下文菜单 / 右键菜单：系统外观。

这一边界写入 §11.7 检查清单，避免实施期混乱。

### §11.3 颜色 token

提升后的 `Theme/PixelChrome.swift` 暴露以下 token（`internal` 静态），所有面板控件统一引用：

```swift
enum PixelPalette {
    // 底色（baseFill）
    static func base(_ scheme: ColorScheme) -> Color {
        scheme == .dark
            ? Color(red: 0.13, green: 0.13, blue: 0.16)
            : Color(red: 0.97, green: 0.97, blue: 0.99)
    }

    // accent 染色比例
    static func accentTint(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.40 : 0.10
    }

    // 顶部高光带不透明度
    static func topHighlight(_ scheme: ColorScheme) -> Double {
        scheme == .dark ? 0.18 : 0.45
    }

    // 描边色（亮 / 暗共用同一硬黑）
    static let stroke = Color.black.opacity(0.85)

    // 块状阴影色
    static let shadow = Color.black.opacity(0.22)

    // 像素 pitch
    static let pixel: CGFloat = 2
}
```

数值取自现行 `PixelChrome` 实现，**不引入新色值**，保证提升前后零回归。Tab 内 accent 色仍按各自语义（Themes 用主题色 / Appearance 用 `.accentColor` / Hooks 用工具色）传入 `PixelChrome(accent:)`。

外观切换（§6.4）的实现路径：`@Environment(\.colorScheme)` 改变 → `PixelPalette.base(scheme)` 等返回不同值 → 所有使用部件的视图自动重绘。无需中央广播。

### §11.4 字体与排版规则

| 用途 | 字体 | 备注 |
|---|---|---|
| 标题（Tab 内 H1，如 "Installed Themes"） | `.system(size: 14, weight: .bold, design: .monospaced)` | 替代现行 `.headline`，强化像素感 |
| 卡片次标题（主题名） | `.system(size: 13, weight: .semibold, design: .monospaced)` | 与气泡 leader 主标题一致 |
| 元数据（id / 版本号 / 描述） | `.system(size: 11, design: .monospaced)`，`foregroundStyle(.secondary)` | 沿用 `ThemesTab.swift` 现状 |
| 长说明文本（Hooks Doctor 输出 / 错误 / 提示） | `.system(size: 11, design: .monospaced)` | 等宽显示路径 / 错误堆栈 |
| 按钮文字 | `PixelButtonStyle` 内置 `.system(size: 12, weight: .bold, design: .monospaced)` | 不可覆盖 |
| Picker / Toggle 标签 | `.system(size: 12, weight: .semibold, design: .monospaced)` | |

**禁止**：

- 不使用 `.title` / `.headline` / `.body` 等 SwiftUI 语义字体（它们会跳到 SF Pro）。
- 不使用 italic / 装饰性字重。
- 不引入第三方位图字体（依赖白名单约束）。

行距：用 SwiftUI 默认 + 1pt（`lineSpacing(1)`）；段落间距用 12pt 像素 grid 整数倍。

### §11.5 Tab 内布局规则

每个 Tab 的根 `body` 套统一外壳，避免每个 Tab 自己拍脑袋决定 padding：

```swift
PreferencesPaneScaffold(title: "Installed Themes") {
    // tab content
}
```

`PreferencesPaneScaffold`（在 `Sources/Hopet/Panel/PreferencesPaneScaffold.swift` 新增）职责：

- 顶部 14pt monospaced bold 标题。
- 内容区 12pt padding，宽度撑满。
- 长内容自动包裹 `ScrollView` + `PixelScrollThumb`。
- 暗 / 亮模式下底色用 `PixelPalette.base(scheme)`，与 `TabView` 容器层叠不冲突。

每个 Tab 内的卡片 / 列表项一律包 `PixelCard`，禁止裸 `RoundedRectangle.fill(Color.gray.opacity(0.05))` 这种现存写法（`ThemesTab.swift:34` 当前实现需重写）。

### §11.6 各 Tab 像素化映射

| Tab | 主要部件 | 备注 |
|---|---|---|
| ThemesTab | `PixelCard` ×N（每主题一张） + `PixelButtonStyle` 的 Apply / Delete + 顶部 `PixelButtonStyle.prominent` 的 "Import Theme…" | 主题预览首帧用 `FrameAnimationView` 渲染并叠 `PixelChrome` 边框，关闭抗锯齿 |
| AppearanceTab | `PixelSegmentedControl` 三选一 | 选项文字 "Light / Dark / System"；下方一行 monospaced 11pt 解释当前生效 |
| HooksTab | `PixelCard` ×N（每工具一张），每张含工具名 + `PixelToggle` + 状态文字（Installed / Not installed）；底部 "Run Hook Doctor" `PixelButtonStyle.secondary` + 输出区用 `PixelCard` 包裹的 monospaced ScrollView | 输出区背景 `PixelPalette.base(scheme)` 而非现状的 `Color.black.opacity(0.05)` |
| 导入 sheet | 顶部 `PixelTextField`（主题名）+ 8 个 `PixelDropSlot` 网格（2 列 × 4 行）+ 底部 Cancel / Import 按钮 | 缺帧提示用红色（`PetState.errorInterrupted.accentColor` 等价值）的 monospaced 11pt 文字 |

### §11.7 像素化检查清单（实施期 / Review 期共用）

提交前对每个修改 / 新增的视图打勾：

- [ ] 所有圆角矩形用 `PixelRoundedRectangle` 或 `PixelChrome`，**没有**裸 `RoundedRectangle`。
- [ ] 所有按钮 `.buttonStyle(PixelButtonStyle(...))`，**没有**默认 / `.borderedProminent` / `.bordered`。
- [ ] 所有边框是硬黑（`PixelPalette.stroke`），**没有** `.opacity(< 0.85)` 的描边。
- [ ] 所有阴影是块状（`offset` + `fill`），**没有** `.shadow(radius:)`。
- [ ] 所有文字使用 monospaced（按 §11.4 表格），**没有** `.headline` / `.title` 之类的语义字体。
- [ ] 所有图像 `.interpolation(.none).antialiased(false)`。
- [ ] 亮 / 暗两套模式都本机切换验证过（§8 步骤 2 + 步骤 10）。
- [ ] 不像素化的部件（§11.2.3）保持系统外观，未被错误包装 `PixelChrome`。

**Review 卡点**：未通过此清单的 PR 不合并；视觉差异通过 commit 截图对比定责。

### §11.8 风险与回滚

- **风险 1**：提升 `PixelChrome` 后宠物气泡出现像素级回归。
  - 缓解：阶段 A' 单独提交、独立 PR，提交前后各截图一份气泡（idle / askUser / permissionPrompt 三状态），diff 通过才合并。
- **风险 2**：自定义部件（如 `PixelToggle`）键盘可达性 / VoiceOver 表现退化。
  - 缓解：所有自绘部件包裹真实的系统控件作为可达性载体（`Toggle` 隐藏于自绘背景下，accessibility 属性透传），而非纯绘制。
- **风险 3**：暗模式下文字对比度不足。
  - 缓解：每个新部件验收时用 macOS 辅助功能 → 颜色滤镜 → 增加对比度 / 反转，肉眼检查不糊。
- **回滚**：§11 是面板独立子系统的视觉规范，与数据 / hook 协议无耦合；如风格需整体回退，仅需还原 `Theme/PixelChrome.swift` 的提升 + 把面板 Tab 切回原 SwiftUI 默认控件。Theme / Hook / Config 数据层不受影响。

---

## §12 与 §11 无关的开放风格问题（v0.3+）

- 是否替换 `TabView` 为自绘像素分段？v0.2 不替换（§11.2.3）；如未来面板 Tab 数量稳定 < 6，可考虑全像素化。
- 是否引入"主题包内自带 chrome 配色"——让用户主题不仅替换海豹动画，也覆盖 `PixelPalette`？v0.3 议题，需要 manifest schema 升级。
- 状态栏 `🦭` emoji 是否替换为像素图标？v0.3 议题，依赖 `NSImage` 模板色支持像素硬边渲染。
