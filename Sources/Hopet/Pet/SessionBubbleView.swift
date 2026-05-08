import SwiftUI

/// 单个会话气泡。永远以圆角矩形像素风卡片形式展示，根据 pendingPermission /
/// pendingAskUser / pendingQuestion 自适应内容；空闲态展示 cwd / 标题 / 状态徽章。
///
/// 可交互的输入只出现在 PermissionRequest hook 同步打通的两条路径上：
/// - `pendingPermission`：Allow / Deny / Ask 按钮，回包通过挂起的 socket。
/// - `pendingAskUser`：结构化 AskUserQuestion 答题，回包带 `updatedInput.answers`。
///
/// 其它情况（idle / 旧 fire-and-forget pendingQuestion）只展示状态信息，
/// 不再提供"自由输入消息"入口——macOS 没有可靠的跨终端宿主反向 stdin 注入路径
/// （TIOCSTI 受 controlling tty 限制、AppleScript 仅 iTerm/Terminal、第三方进程
/// 拿不到 IDE/CLI extension spawn 的 PTY master fd）。
public struct SessionBubbleView: View {
    /// 决策按钮配色。两者都跟 PixelButtonStyle(prominent: true) 搭配 → 实色背景 + 白字。
    /// 拒绝走玫红（视觉警示但不至于像纯红那么刺），交还终端走中浅灰（与"允许"的状态绿区分开）。
    static let denyRose = Color(red: 0.92, green: 0.32, blue: 0.50)
    static let handoffGray = Color(white: 0.62)

    let bubble: SessionBubble
    let isLeader: Bool
    /// 描述：运行中显示"已运行 X"，闲置显示"X 前"。
    let stateDurationPhrase: String
    /// (decision, reason). `decision` ∈ {"allow", "deny", "ask"}；`reason` 仅 deny 路径有意义
    /// （承载 plan-approval "继续规划" 默认理由或用户自定义反馈）。
    let onResolvePermission: (String, String?) -> Void
    /// AskUserQuestion 答题提交回调。`answers` 形如 `{ "问题文案": "回答" }`；
    /// `cancel = true` 表示用户取消（让 Claude 走自身 UI）。
    let onResolveAskUser: ([String: String], Bool) -> Void

    public init(
        bubble: SessionBubble,
        isLeader: Bool,
        stateDurationPhrase: String,
        onResolvePermission: @escaping (String, String?) -> Void = { _, _ in },
        onResolveAskUser: @escaping ([String: String], Bool) -> Void = { _, _ in }
    ) {
        self.bubble = bubble
        self.isLeader = isLeader
        self.stateDurationPhrase = stateDurationPhrase
        self.onResolvePermission = onResolvePermission
        self.onResolveAskUser = onResolveAskUser
    }

    @FocusState private var inputFocused: Bool
    /// 结构化 AskUserQuestion 的答题暂存：问题文案 → 用户当前输入。
    @State private var elicitationAnswers: [String: String] = [:]
    /// multiSelect 模式下当前已勾选的 label 集合：问题文案 → labels。
    /// 提交时由 advanceOrSubmit 把集合按插入顺序拼接成单个字符串写进 elicitationAnswers，
    /// 保持外部协议（`[String: String]`）不变。
    @State private var elicitationSelected: [String: [String]] = [:]
    /// 多问题时的当前页索引。单问题时恒为 0。
    @State private var elicitationIndex: Int = 0
    /// ExitPlanMode 卡片上的"自定义反馈"输入。提交时作为 deny 的 reason。
    @State private var planFeedback: String = ""

    /// "炸开"动画期间渲染的方块粒子（8-bit 风格，无柔光）。
    @State private var popParticles: [PopParticle] = []

    public var body: some View {
        ZStack {
            cardBody

            // 炸开粒子层：8-bit 风格用方块代替圆形，硬边描边，无模糊。
            ForEach(popParticles) { p in
                Rectangle()
                    .fill(bubble.state.accentColor)
                    .overlay(Rectangle().stroke(Color.black.opacity(0.85), lineWidth: 1))
                    .frame(width: p.size, height: p.size)
                    .offset(x: p.offsetX, y: p.offsetY)
                    .opacity(p.opacity)
                    .scaleEffect(p.scale)
            }
            .allowsHitTesting(false)
        }
    }

    /// 决策按钮按下的反馈动画：先散粒子，再调闭包回写决策。
    /// `pendingPermission` / `pendingAskUser` 解决后由协议层把字段置空，
    /// 视图自然重渲染回默认卡片（不再有"小气泡缩回"语义）。
    private func popThen(_ action: @escaping () -> Void) {
        guard popParticles.isEmpty else { return }  // 防抖：动画期间忽略二次触发
        let count = 10
        popParticles = (0..<count).map { i in
            PopParticle(
                angle: Double(i) * (360.0 / Double(count)) + Double.random(in: -14...14),
                size: CGFloat.random(in: 5...11),
                offsetX: 0,
                offsetY: 0,
                opacity: 1.0,
                scale: 0.6
            )
        }

        // 粒子飞溅 + 淡出
        withAnimation(.easeOut(duration: 0.5)) {
            for i in popParticles.indices {
                let radians = popParticles[i].angle * .pi / 180
                let dist = CGFloat.random(in: 55...110)
                popParticles[i].offsetX = CGFloat(cos(radians)) * dist
                popParticles[i].offsetY = CGFloat(sin(radians)) * dist
                popParticles[i].opacity = 0
                popParticles[i].scale = 1.2
            }
        }

        // 让大泡泡稍微滞后开始消失，营造"绽开 → 散开"的层次。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            action()
        }
        // 动画结束后清理粒子，避免反复累积。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
            popParticles = []
        }
    }

    /// 卡片主体：所有形态都共用同一种像素圆角矩形外壳，仅内部内容随
    /// pendingPermission / pendingAskUser / pendingQuestion 自适应。
    /// 优先级：plan-approval > permission > AskUserQuestion 答题 > 旧 fire-and-forget pendingQuestion > 默认信息卡。
    @ViewBuilder
    private var cardBody: some View {
        if let pp = bubble.pendingPermission, pp.isPlanApproval {
            planApprovalCard.modifier(decisionChrome())
        } else if bubble.pendingPermission != nil {
            permissionCard.modifier(decisionChrome())
        } else if bubble.pendingAskUser != nil {
            elicitationCard.modifier(decisionChrome())
        } else if bubble.pendingQuestion != nil {
            askUserCard.modifier(decisionChrome())
        } else {
            defaultCard.modifier(decisionChrome())
        }
    }

    /// 大气泡共用外壳：圆角矩形像素风。leader session 描边略加粗以区分谁在驱动宠物。
    private func decisionChrome() -> PixelChrome {
        PixelChrome(
            cornerRadius: 10,
            accent: bubble.state.accentColor,
            strokeWidth: isLeader ? 2.5 : 2,
            strokeColor: Color.black.opacity(0.92)
        )
    }

    /// permission / plan-approval 卡片右上角的"交还终端"X 按钮：xmark + handoffGray 圆底。
    @ViewBuilder
    private func handoffXButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 18, height: 18)
                .background(Circle().fill(SessionBubbleView.handoffGray))
        }
        .buttonStyle(.plain)
        .help("交还终端处理")
    }

    /// elicitation / askUser 卡片右上角的取消按钮：palette 渲染的 xmark.circle.fill。
    @ViewBuilder
    private func paletteDismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark.circle.fill")
                .symbolRenderingMode(.palette)
                .foregroundStyle(Color.white, SessionBubbleView.handoffGray)
        }
        .buttonStyle(.plain)
    }

    /// 权限请求卡片（PermissionRequest hook 触发）。
    private var permissionCard: some View {
        let pp = bubble.pendingPermission!
        return VStack(alignment: .leading, spacing: 10) {
            // Header：工具名（caps tracking）+ 隐藏式关闭。
            HStack(spacing: 6) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(bubble.state.accentColor)
                Text(pp.toolName.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .tracking(0.7)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                handoffXButton { popThen { onResolvePermission("ask", nil) } }
            }

            // 主标题
            Text("Claude 想执行此操作")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            // 详情：command / filePath
            if let cmd = pp.command {
                detailBlock {
                    Text(cmd)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(4)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let fp = pp.filePath {
                detailBlock {
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Text(fp)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // 操作按钮：所有按钮都先播炸开动画再回调
            HStack(spacing: 6) {
                Button("拒绝") { popThen { onResolvePermission("deny", nil) } }
                    .buttonStyle(PixelButtonStyle(tint: SessionBubbleView.denyRose, prominent: true))
                Spacer()
                Button("交还终端") { popThen { onResolvePermission("ask", nil) } }
                    .buttonStyle(PixelButtonStyle(tint: SessionBubbleView.handoffGray, prominent: true))
                Button("允许") { popThen { onResolvePermission("allow", nil) } }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(PixelButtonStyle(tint: .green, prominent: true))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 300)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// ExitPlanMode 专用卡片。auto-accept 不复刻——hook 协议表达不出 session 级模式翻转，
    /// 伪装成 "ask" 等于让用户连点两次。底部提示告知用户去终端自行切换。
    private var planApprovalCard: some View {
        let pp = bubble.pendingPermission!

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("接受此 plan?")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                handoffXButton { popThen { onResolvePermission("ask", nil) } }
            }

            if let plan = pp.plan {
                detailBlock {
                    ScrollView {
                        Text(plan)
                            .font(.system(size: 10))
                            .foregroundStyle(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 180)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                planOptionRow(index: 1, label: "允许执行", isPrimary: true) {
                    popThen { onResolvePermission("allow", nil) }
                }
                planOptionRow(index: 2, label: "继续规划") {
                    popThen { onResolvePermission("deny", "User wants to keep planning") }
                }
            }

            TextField("或者告诉 Claude 该怎么做…", text: $planFeedback, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .focused($inputFocused)
                .font(.system(size: 10))
                .onSubmit { submitPlanFeedback() }

            Text("如需后续自动放行，请到 Claude Code 终端按 Shift+Tab 切换 auto-accept 模式")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 320)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// plan-approval 卡片里的单条选项行：左侧编号徽标 + 标签。`isPrimary` 高亮第一项（与 CC 默认聚焦行为一致）。
    @ViewBuilder
    private func planOptionRow(
        index: Int,
        label: String,
        isPrimary: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Text("\(index)")
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isPrimary ? Color.white : .secondary)
                    .frame(width: 18, height: 18)
                    .background(
                        Circle().fill(isPrimary ? Color.accentColor : Color.secondary.opacity(0.18))
                    )
                Text(label)
                    .font(.system(size: 12, weight: isPrimary ? .semibold : .regular))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isPrimary ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.10))
            )
        }
        .buttonStyle(.plain)
        .keyboardShortcut(KeyEquivalent(Character("\(index)")), modifiers: [])
    }

    private func submitPlanFeedback() {
        let trimmed = planFeedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        planFeedback = ""
        popThen { onResolvePermission("deny", trimmed) }
    }

    /// 详情块的统一容器（底纹 + 细边）。
    @ViewBuilder
    private func detailBlock<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.primary.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.primary.opacity(0.06), lineWidth: 0.5)
            )
    }

    /// 结构化 AskUserQuestion 卡片：用户答完后通过挂起的 socket 同步回写 updatedInput.answers。
    /// 多问题时分页填写，最后一页提交时一次性回包。这条路径跨所有终端宿主工作（协议级而非系统级）。
    private var elicitationCard: some View {
        let pa = bubble.pendingAskUser!
        let total = max(1, pa.questions.count)
        let idx = min(elicitationIndex, total - 1)
        let current: AskUserQuestionItem? = pa.questions.indices.contains(idx) ? pa.questions[idx] : nil

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(total > 1 ? "❓ 在等你回答（\(idx + 1)/\(total)）" : "❓ 在等你回答")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                paletteDismissButton {
                    popThen { onResolveAskUser([:], true) }
                }
            }

            if let q = current {
                Text(q.question)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .lineLimit(4)

                if let opts = q.options, !opts.isEmpty {
                    // 单选：点选项即提交。多选：点选项是 toggle，靠"发送"按钮统一提交。
                    // 选项数 / description 长度都是外部协议决定的，所以包一层 ScrollView 兜住极端情况。
                    let multi = q.multiSelect == true
                    let selected = elicitationSelected[q.question] ?? []
                    ScrollView {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(opts, id: \.label) { opt in
                                let isSelected = multi && selected.contains(opt.label)
                                Button(action: {
                                    if multi {
                                        toggleSelection(question: q.question, option: opt.label)
                                    } else {
                                        elicitationAnswers[q.question] = opt.label
                                        advanceOrSubmit(pa: pa)
                                    }
                                }) {
                                    HStack(alignment: .top, spacing: 5) {
                                        if multi {
                                            Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                                                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                                                .padding(.top, 1)
                                        }
                                        VStack(alignment: .leading, spacing: 1) {
                                            Text(opt.label)
                                                .font(.system(size: 10, weight: .medium))
                                                .foregroundStyle(.primary)
                                            if let desc = opt.description, !desc.isEmpty {
                                                Text(desc)
                                                    .font(.system(size: 9))
                                                    .foregroundStyle(.secondary)
                                                    .fixedSize(horizontal: false, vertical: true)
                                            }
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 5)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(
                                        RoundedRectangle(cornerRadius: 6)
                                            .fill(Color.secondary.opacity(isSelected ? 0.22 : 0.12))
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                // multiSelect 时不渲染自定义输入框：多选语义本身已被勾选集合表达，
                // 同时显示文本框只会让"按钮选 + 文本输 + 谁覆盖谁"这条路径变模糊。
                if q.multiSelect != true {
                    TextField("自定义回答…", text: bindingForAnswer(of: q.question), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .font(.system(size: 10))
                        .onSubmit { advanceOrSubmit(pa: pa) }
                }
            }

            HStack {
                if idx > 0 {
                    Button("上一题") { elicitationIndex = idx - 1 }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
                Button(idx < total - 1 ? "下一题" : "发送") {
                    advanceOrSubmit(pa: pa)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(!hasAnswer(for: current))
            }
        }
        .padding(10)
        .frame(width: 300)
        .frame(minHeight: 180, maxHeight: 380)
        .onAppear { inputFocused = true }
    }

    private func bindingForAnswer(of question: String) -> Binding<String> {
        Binding(
            get: { elicitationAnswers[question] ?? "" },
            set: { elicitationAnswers[question] = $0 }
        )
    }

    private func advanceOrSubmit(pa: PendingAskUser) {
        let total = pa.questions.count
        let idx = min(elicitationIndex, max(0, total - 1))
        let q = pa.questions.indices.contains(idx) ? pa.questions[idx] : nil
        if let q {
            // multiSelect：把勾选集合按插入顺序拼成 ", " 分隔的字符串，写进 elicitationAnswers。
            // answers 协议规定 value 是 String；模型接收 "蓝色, 紫色" 这种文本仍可识别为多选。
            if q.multiSelect == true {
                let selected = elicitationSelected[q.question] ?? []
                guard !selected.isEmpty else { return }
                elicitationAnswers[q.question] = selected.joined(separator: ", ")
            } else {
                let cur = (elicitationAnswers[q.question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !cur.isEmpty else { return }
            }
        }
        if idx < total - 1 {
            elicitationIndex = idx + 1
            return
        }
        // 最后一题提交：先炸开再回写答案，气泡随后消失。
        let trimmed = elicitationAnswers.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.value.isEmpty }
        popThen { onResolveAskUser(trimmed, false) }
        elicitationAnswers.removeAll()
        elicitationSelected.removeAll()
        elicitationIndex = 0
    }

    private func toggleSelection(question: String, option: String) {
        var current = elicitationSelected[question] ?? []
        if let i = current.firstIndex(of: option) {
            current.remove(at: i)
        } else {
            current.append(option)
        }
        elicitationSelected[question] = current
    }

    /// "下一题" / "发送" 按钮的可用性：multiSelect 看勾选集合，单选看文本输入。
    private func hasAnswer(for q: AskUserQuestionItem?) -> Bool {
        guard let q else { return false }
        if q.multiSelect == true {
            return !(elicitationSelected[q.question]?.isEmpty ?? true)
        }
        return !(elicitationAnswers[q.question] ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty
    }

    /// 旧 fire-and-forget pendingQuestion 卡片（PreToolUse `tool_name=AskUserQuestion` 路径）。
    /// 这条路径没带 requestId，无法同步回包，只能展示提示让用户回到原终端作答；
    /// 新会话列表布局下卡片常驻显示，没有"关闭"语义——pendingQuestion 由协议层在
    /// 下一次状态变更时自然清空，视图随即回到 defaultCard。
    private var askUserCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("❓ 在等你回答")
                .font(.system(size: 11, weight: .semibold))
            if let q = bubble.pendingQuestion {
                Text(q)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
            Text("请到原终端 / Claude UI 回答。")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .frame(width: 260)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// 默认卡片：两行布局——
    /// - 第 1 行：状态圆点 + `cwd · title`（无 title 只显示 cwd）+ 右端 stateDurationPhrase
    /// - 第 2 行：最近一次 Claude 回复的开头，9pt secondary，最多 2 行；没有回复时回退到状态徽章
    ///   （状态文字已在第一行右端用耗时短语承担时间信息，这里 fallback 让卡片不出现空行抖动）
    private var defaultCard: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                Circle()
                    .fill(bubble.state.accentColor)
                    .frame(width: 6, height: 6)

                Text(headerLabel)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)

                Spacer(minLength: 6)

                Text(stateDurationPhrase)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            Text(secondLineText)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(width: 260, alignment: .leading)
    }

    /// 第一行：有真实标题时 `cwd · title`，否则只渲染 cwd。
    private var headerLabel: String {
        bubble.hasTitle
            ? "\(bubble.displayCwd) · \(bubble.displayTitle)"
            : bubble.displayCwd
    }

    /// 第二行：优先展示最近一次回复的开头；没回复就 fallback 到状态徽章文字（避免卡片高度跳变）。
    private var secondLineText: String {
        if let msg = bubble.lastAssistantMessage, !msg.isEmpty {
            return msg
        }
        return bubble.state.badgeLabel
    }
}

/// 炸开动画期间的单个像素方块。
private struct PopParticle: Identifiable {
    let id = UUID()
    let angle: Double      // 飞溅方向（度）
    let size: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    var opacity: Double
    var scale: CGFloat
}

/// 8-bit 像素风外壳：阶梯像素圆角 + 近白底 + 顶部高光 + 块状阴影。所有几何沿 `pixelSize` 方格对齐，
/// 圆角处呈现可见的 2pt 颗粒阶梯——视觉上对齐参考素材的复古 UI 边缘，与小海豹 sprite 同语言。
/// 描边宽度 / 颜色独立可调：leader session 偏好略粗的黑描边（强调），其余气泡保持基础粗细。
private struct PixelChrome: ViewModifier {
    let cornerRadius: CGFloat
    let accent: Color
    let strokeWidth: CGFloat
    let strokeColor: Color

    func body(content: Content) -> some View {
        // pixel pitch：圆角阶梯 / 阴影偏移按这个量化；描边宽度由 caller 单独控制，不必整数倍 pixel。
        let pixel: CGFloat = 2
        let strokeInset = strokeWidth

        return content
            .padding(strokeInset + 1)  // 让内容不撞到内层亮边
            .background(
                GeometryReader { _ in
                    let cr = self.cornerRadius
                    let outer = PixelRoundedRectangle(cornerRadius: cr, pixelSize: pixel)
                    let inner = PixelRoundedRectangle(
                        cornerRadius: max(pixel, cr - strokeInset),
                        pixelSize: pixel
                    )
                    ZStack {
                        // 1. 块状像素阴影：硬偏移、无模糊，边缘也是阶梯像素。
                        outer
                            .fill(Color.black.opacity(0.22))
                            .offset(x: 0, y: pixel * 2)
                        // 2. 描边底（外层 shape 整面填描边色，内层填浅色后只剩 strokeInset 宽的描边）。
                        outer.fill(strokeColor)
                        // 3. 内层：近白冷调主体 + accent 轻染 + 顶部高光带。padding(strokeInset) 让其向内缩。
                        ZStack {
                            inner.fill(Color(red: 0.97, green: 0.97, blue: 0.99))
                            // accent 轻染——状态色在卡片上隐隐透出，不抢内容。
                            inner.fill(accent.opacity(0.10))
                            // 顶部 4px 像素高光带，强调"自上而来的光源"。
                            inner
                                .fill(Color.white.opacity(0.45))
                                .mask(
                                    VStack(spacing: 0) {
                                        Rectangle().frame(height: pixel * 2)
                                        Spacer(minLength: 0)
                                    }
                                )
                        }
                        .padding(strokeInset)
                    }
                }
            )
    }
}

/// 像素化圆角矩形：把 4 个圆角拆成 `pixelSize` 大小的方格阶梯，整体呈现 8-bit UI 边缘的颗粒感。
/// 对每个角，按距离角心的圆形判定填哪些方格；中心由两条贯穿矩形构成，避免任何角度漏接。
private struct PixelRoundedRectangle: Shape {
    let cornerRadius: CGFloat
    let pixelSize: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = max(0, min(cornerRadius, min(rect.width, rect.height) / 2))
        // 中央贯通条：上下穿过的中柱 + 左右穿过的中横，两者并集 = 矩形 - 4 个角的方形空洞。
        if rect.width > 2 * r {
            path.addRect(CGRect(x: rect.minX + r, y: rect.minY,
                                width: rect.width - 2 * r, height: rect.height))
        }
        if rect.height > 2 * r {
            path.addRect(CGRect(x: rect.minX, y: rect.minY + r,
                                width: rect.width, height: rect.height - 2 * r))
        }

        // 4 个角：grid 采样，距离 corner anchor < r 的方格填入。
        let cells = max(1, Int(round(r / pixelSize)))
        guard cells > 0 else { return path }
        let cell = r / CGFloat(cells)
        let r2 = CGFloat(cells * cells)
        for cy in 0..<cells {
            for cx in 0..<cells {
                let dx = CGFloat(cells) - CGFloat(cx) - 0.5
                let dy = CGFloat(cells) - CGFloat(cy) - 0.5
                guard dx * dx + dy * dy <= r2 else { continue }
                let ox = CGFloat(cx) * cell
                let oy = CGFloat(cy) * cell
                // top-left
                path.addRect(CGRect(x: rect.minX + ox, y: rect.minY + oy,
                                    width: cell, height: cell))
                // top-right
                path.addRect(CGRect(x: rect.maxX - ox - cell, y: rect.minY + oy,
                                    width: cell, height: cell))
                // bottom-left
                path.addRect(CGRect(x: rect.minX + ox, y: rect.maxY - oy - cell,
                                    width: cell, height: cell))
                // bottom-right
                path.addRect(CGRect(x: rect.maxX - ox - cell, y: rect.maxY - oy - cell,
                                    width: cell, height: cell))
            }
        }
        return path
    }
}

/// 8-bit 风按钮样式。
/// - prominent=true：实色填充（用于主操作"允许"）。
/// - prominent=false：浅色填充 + 深描边（用于次操作）。
/// 共同点：圆角 4px、硬黑描边、按下时整体下移 1px 模拟"按入"。
private struct PixelButtonStyle: ButtonStyle {
    let tint: Color
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 4, style: .continuous)
        let pressed = configuration.isPressed
        return configuration.label
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : Color.black.opacity(0.85))
            .background(
                ZStack {
                    if !pressed {
                        // 未按下：渲染下方的实色"投影方块"。
                        shape
                            .fill(Color.black.opacity(0.85))
                            .offset(x: 0, y: 2)
                    }
                    shape.fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.22)))
                    shape.stroke(Color.black.opacity(0.85), lineWidth: 1.5)
                    // 顶部 1px 高光线，强化像素感。
                    shape
                        .inset(by: 1.5)
                        .stroke(Color.white.opacity(prominent ? 0.45 : 0.6), lineWidth: 1)
                }
            )
            .offset(x: 0, y: pressed ? 2 : 0)
            .animation(.linear(duration: 0.05), value: pressed)
    }
}
