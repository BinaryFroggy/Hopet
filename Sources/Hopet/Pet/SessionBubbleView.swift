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
    /// 手动关闭：用户点 defaultCard / askUserCard 右上角的 ✕。
    /// 真活会话被误关时下一次状态事件会冷启重建（详见 InputCoordinator.dismissSession）。
    let onDismiss: () -> Void

    public init(
        bubble: SessionBubble,
        isLeader: Bool,
        stateDurationPhrase: String,
        onResolvePermission: @escaping (String, String?) -> Void = { _, _ in },
        onResolveAskUser: @escaping ([String: String], Bool) -> Void = { _, _ in },
        onDismiss: @escaping () -> Void = {}
    ) {
        self.bubble = bubble
        self.isLeader = isLeader
        self.stateDurationPhrase = stateDurationPhrase
        self.onResolvePermission = onResolvePermission
        self.onResolveAskUser = onResolveAskUser
        self.onDismiss = onDismiss
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
        .help("Hand off to terminal")
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

    /// defaultCard / askUserCard 右上角的"清除气泡"按钮：
    /// 比 paletteDismissButton 更小、更低对比度，避免在闲置卡片里抢眼。
    /// 仅从 registry 移除该 session；真活会话下一次事件冷启会重建气泡，僵尸气泡则永久消失。
    @ViewBuilder
    private func defaultDismissButton(action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(Color.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color.secondary.opacity(0.45)))
        }
        .buttonStyle(.plain)
        .help("Dismiss this bubble (if the session is still active, it will reappear on the next state change)")
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
            Text("\(bubble.tool.displayName) wants to run this action")
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
                Button("Deny") { popThen { onResolvePermission("deny", nil) } }
                    .buttonStyle(PixelButtonStyle(tint: SessionBubbleView.denyRose, prominent: true))
                Spacer()
                Button("Handoff") { popThen { onResolvePermission("ask", nil) } }
                    .buttonStyle(PixelButtonStyle(tint: SessionBubbleView.handoffGray, prominent: true))
                Button("Allow") { popThen { onResolvePermission("allow", nil) } }
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
                Text("Approve this plan?")
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
                planOptionRow(index: 1, label: "Run the plan", isPrimary: true) {
                    popThen { onResolvePermission("allow", nil) }
                }
                planOptionRow(index: 2, label: "Keep planning") {
                    popThen { onResolvePermission("deny", "User wants to keep planning") }
                }
            }

            TextField("Or tell Claude what to do instead…", text: $planFeedback, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .lineLimit(1...3)
                .focused($inputFocused)
                .font(.system(size: 10))
                .onSubmit { submitPlanFeedback() }

            Text("To auto-approve future runs, press Shift+Tab in the Claude Code terminal to toggle auto-accept mode")
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
                Text(total > 1 ? "❓ Waiting for your answer (\(idx + 1)/\(total))" : "❓ Waiting for your answer")
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
                    TextField("Custom answer…", text: bindingForAnswer(of: q.question), axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(1...4)
                        .focused($inputFocused)
                        .font(.system(size: 10))
                        .onSubmit { advanceOrSubmit(pa: pa) }
                }
            }

            HStack {
                if idx > 0 {
                    Button("Previous") { elicitationIndex = idx - 1 }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
                Spacer()
                Button(idx < total - 1 ? "Next" : "Send") {
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
    /// 这条路径没带 requestId，无法同步回包，只能展示提示让用户回到原终端作答。
    /// pendingQuestion 通常由协议层在下一次状态变更时自然清空，视图随即回到 defaultCard；
    /// 右上角的 ✕ 兜底——遇到僵尸卡片（事件未到达）让用户手动清掉。
    private var askUserCard: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center) {
                Text("❓ Waiting for your answer")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                defaultDismissButton { popThen(onDismiss) }
            }
            if let q = bubble.pendingQuestion {
                Text(q)
                    .font(.system(size: 10))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
            Text("Please answer in the originating terminal / Claude UI.")
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
                    .truncationMode(.tail)

                Spacer(minLength: 6)

                Text(stateDurationPhrase)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()

                defaultDismissButton { popThen(onDismiss) }
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
