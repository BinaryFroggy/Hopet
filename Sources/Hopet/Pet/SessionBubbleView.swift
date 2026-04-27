import SwiftUI

/// 单个会话气泡。折叠态 64×64，展开态根据 pendingPermission / pendingAskUser / pendingQuestion 自适应。
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
    let bubble: SessionBubble
    let isLeader: Bool
    /// 折叠态用的紧凑耗时，例如 "5m" / "30s"。
    let elapsedShort: String
    /// 展开态用的描述：运行中显示"已运行 X"，闲置显示"X 前"。
    let stateDurationPhrase: String
    let onTap: () -> Void
    let onResolvePermission: (String) -> Void  // "allow" / "deny" / "ask"
    /// AskUserQuestion 答题提交回调。`answers` 形如 `{ "问题文案": "回答" }`；
    /// `cancel = true` 表示用户取消（让 Claude 走自身 UI）。
    let onResolveAskUser: ([String: String], Bool) -> Void
    let onDismiss: () -> Void

    public init(
        bubble: SessionBubble,
        isLeader: Bool,
        elapsedShort: String,
        stateDurationPhrase: String,
        onTap: @escaping () -> Void,
        onResolvePermission: @escaping (String) -> Void = { _ in },
        onResolveAskUser: @escaping ([String: String], Bool) -> Void = { _, _ in },
        onDismiss: @escaping () -> Void
    ) {
        self.bubble = bubble
        self.isLeader = isLeader
        self.elapsedShort = elapsedShort
        self.stateDurationPhrase = stateDurationPhrase
        self.onTap = onTap
        self.onResolvePermission = onResolvePermission
        self.onResolveAskUser = onResolveAskUser
        self.onDismiss = onDismiss
    }

    @FocusState private var inputFocused: Bool
    /// 结构化 AskUserQuestion 的答题暂存：问题文案 → 用户当前输入。
    @State private var elicitationAnswers: [String: String] = [:]
    /// 多问题时的当前页索引。单问题时恒为 0。
    @State private var elicitationIndex: Int = 0

    /// 肥皂泡"炸开"动画期间渲染的粒子。
    @State private var popParticles: [PopParticle] = []

    public var body: some View {
        ZStack {
            if bubble.expanded {
                expandedCard
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.35, anchor: .center).combined(with: .opacity),
                        removal: .bubblePopOut
                    ))
            } else {
                collapsedDot
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.6, anchor: .center).combined(with: .opacity),
                        removal: .scale(scale: 0.6, anchor: .center).combined(with: .opacity)
                    ))
            }

            // 炸开粒子层：从中心向外飞溅 + 缩小淡出。
            ForEach(popParticles) { p in
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.85), bubble.state.accentColor.opacity(0.55)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.7), lineWidth: 0.4)
                    )
                    .frame(width: p.size, height: p.size)
                    .blur(radius: 0.4)
                    .shadow(color: bubble.state.accentColor.opacity(0.35), radius: 1.5)
                    .offset(x: p.offsetX, y: p.offsetY)
                    .opacity(p.opacity)
                    .scaleEffect(p.scale)
            }
            .allowsHitTesting(false)
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.78), value: bubble.expanded)
    }

    /// 触发"炸开 → 执行 action"：先散粒子，再调闭包。所有让大泡泡消失的入口都走它。
    /// - 默认普通态点击收起：`popThen { onTap() }`
    /// - 决策类按钮：`popThen { onResolvePermission(...) }` / `popThen { onResolveAskUser(...) }`
    /// - 关闭按钮：`popThen { onDismiss() }`
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

    private var collapsedDot: some View {
        // 是否处于"运行中"状态：决定折叠态时间前缀图标。
        let isRunning: Bool = {
            switch bubble.state {
            case .thinking, .responding, .toolUse, .askUser, .permissionPrompt: return true
            case .idle, .completed, .errorInterrupted: return false
            }
        }()

        return VStack(spacing: 1) {
            HStack(spacing: 3) {
                Circle()
                    .fill(bubble.state.accentColor)
                    .frame(width: 5, height: 5)
                Text(bubble.displayCwd)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .truncationMode(.middle)
            }
            HStack(spacing: 2) {
                Image(systemName: isRunning ? "play.fill" : "clock")
                    .font(.system(size: 7))
                Text(elapsedShort)
                    .font(.system(size: 9, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(.secondary)
        }
        .modifier(BubbleTextLegibility())
        .padding(.horizontal, 6)
        .frame(width: 64, height: 64)
        .modifier(SoapBubbleChrome(
            shape: .circle,
            accent: bubble.state.accentColor,
            emphasis: isLeader ? 1.4 : 1.0
        ))
        .contentShape(Circle())
        .onTapGesture { onTap() }
    }

    @ViewBuilder
    private var expandedCard: some View {
        // 优先级：权限请求 > 结构化 AskUserQuestion > 早期 fire-and-forget pendingQuestion > 普通输入。
        // 同时只能渲染一种主体内容。
        if bubble.pendingPermission != nil {
            permissionCard.modifier(ExpandedCardChrome(accent: bubble.state.accentColor))
        } else if bubble.pendingAskUser != nil {
            elicitationCard.modifier(ExpandedCardChrome(accent: bubble.state.accentColor))
        } else if bubble.pendingQuestion != nil {
            askUserCard.modifier(ExpandedCardChrome(accent: bubble.state.accentColor))
        } else {
            // 普通态：横向不规则大气泡，整张卡可点击收起。
            defaultCard.modifier(IrregularBubbleChrome(accent: bubble.state.accentColor))
        }
    }

    /// 权限请求卡片（PermissionRequest hook 触发）。
    private var permissionCard: some View {
        let pp = bubble.pendingPermission!
        return VStack(alignment: .leading, spacing: 14) {
            // Header：工具名（caps tracking）+ 隐藏式关闭。
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(bubble.state.accentColor)
                Text(pp.toolName.uppercased())
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.8)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(action: { popThen { onResolvePermission("ask") } }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.primary.opacity(0.06)))
                }
                .buttonStyle(.plain)
                .help("交还终端处理")
            }

            // 主标题
            Text("Claude 想执行此操作")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.primary)

            // 详情：command / filePath
            if let cmd = pp.command {
                detailBlock {
                    Text(cmd)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.primary)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let fp = pp.filePath {
                detailBlock {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        Text(fp)
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

            // 操作按钮：所有按钮都先播炸开动画再回调
            HStack(spacing: 8) {
                Button("拒绝") { popThen { onResolvePermission("deny") } }
                    .buttonStyle(GlassPillButtonStyle(tint: .red, prominent: false))
                Spacer()
                Button("交还终端") { popThen { onResolvePermission("ask") } }
                    .buttonStyle(GlassPillButtonStyle(tint: .gray, prominent: false))
                Button("允许") { popThen { onResolvePermission("allow") } }
                    .keyboardShortcut(.return, modifiers: [])
                    .buttonStyle(GlassPillButtonStyle(tint: .green, prominent: true))
            }
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
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

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(total > 1 ? "❓ 在等你回答（\(idx + 1)/\(total)）" : "❓ 在等你回答")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: {
                    popThen { onResolveAskUser([:], true) }  // cancel：先炸开再取消
                }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("交还终端处理")
            }

            if let q = current {
                Text(q.question)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(4)

                if let opts = q.options, !opts.isEmpty {
                    // 选项：点击即填入答案。多选先简化为"点哪个就提交哪个"，与单选一致。
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(opts, id: \.self) { opt in
                            Button(action: {
                                elicitationAnswers[q.question] = opt
                                advanceOrSubmit(pa: pa)
                            }) {
                                HStack {
                                    Text(opt)
                                        .font(.system(size: 11))
                                    Spacer()
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(Color.secondary.opacity(0.12))
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("自定义回答…", text: bindingForAnswer(of: q.question), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .focused($inputFocused)
                    .onSubmit { advanceOrSubmit(pa: pa) }
            }

            HStack {
                if idx > 0 {
                    Button("上一题") { elicitationIndex = idx - 1 }
                        .buttonStyle(.bordered)
                }
                Spacer()
                Button(idx < total - 1 ? "下一题" : "发送") {
                    advanceOrSubmit(pa: pa)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled((elicitationAnswers[current?.question ?? ""] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(12)
        .frame(width: 360, height: 220)
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
            let cur = (elicitationAnswers[q.question] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cur.isEmpty else { return }
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
        elicitationIndex = 0
    }

    /// 旧 fire-and-forget pendingQuestion 卡片（PreToolUse `tool_name=AskUserQuestion` 路径）。
    /// 这条路径没带 requestId，无法同步回包，只能展示提示让用户回到原终端作答。
    /// 新版本若 PermissionRequest 同步路径触发，会优先走 elicitationCard。
    private var askUserCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("❓ 在等你回答")
                    .font(.system(size: 12, weight: .semibold))
                Spacer()
                Button(action: { popThen { onDismiss() } }) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            if let q = bubble.pendingQuestion {
                Text(q)
                    .font(.system(size: 11))
                    .foregroundStyle(.primary)
                    .lineLimit(4)
            }
            Text("请到原终端 / Claude UI 回答。")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 320, height: 130)
    }

    /// 默认卡片：横向不规则大气泡。展示目录、标题（若有）、状态持续时长。整张卡再点击一次收起。
    private var defaultCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(bubble.state.accentColor)
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 3) {
                if bubble.hasTitle {
                    Text(bubble.displayCwd)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(bubble.displayTitle)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    // 没有真实标题：只渲染目录，不再补占位"标题"行，避免重复。
                    Text(bubble.displayCwd)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 3) {
                // 状态文字保持中性色：状态色由左侧小圆点承担，文字不再夹带 emoji 也不再换色。
                Text(bubble.state.badgeLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
                Text(stateDurationPhrase)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .modifier(BubbleTextLegibility())
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(width: 360, alignment: .leading)
        .frame(minHeight: 76)
        .contentShape(Rectangle())
        .onTapGesture { popThen { onTap() } }
    }
}

/// 让文字在透明肥皂泡里于任何背景色下都可读：
/// 暗影压底（暗背景下也能看清文字轮廓）+ 极淡亮影提边（白底下文字不会"消失"）。
private struct BubbleTextLegibility: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(color: Color.black.opacity(0.45), radius: 1.4, x: 0, y: 0.5)
            .shadow(color: Color.white.opacity(0.22), radius: 0.7, x: 0, y: -0.3)
    }
}

/// 肥皂泡炸开动画期间的单个水珠粒子。
private struct PopParticle: Identifiable {
    let id = UUID()
    let angle: Double      // 飞溅方向（度）
    let size: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
    var opacity: Double
    var scale: CGFloat
}

/// 大泡泡退出时的"绽开"过渡：放大 + 模糊 + 淡出。配合粒子层模拟肥皂泡炸开。
private struct BubbleBlurModifier: ViewModifier {
    let blur: CGFloat
    func body(content: Content) -> some View {
        content.blur(radius: blur)
    }
}

private extension AnyTransition {
    static var bubblePopOut: AnyTransition {
        .scale(scale: 1.45, anchor: .center)
            .combined(with: .opacity)
            .combined(with: .modifier(
                active: BubbleBlurModifier(blur: 10),
                identity: BubbleBlurModifier(blur: 0)
            ))
    }
}

/// 普通态使用的"横向不规则大气泡"外壳：稳重半透底 + 轻状态色染色 + 柔和模糊光晕。
/// 与折叠态的 `SoapBubbleChrome` 分离：展开态优先保证文字可读，不放高光斑/薄膜彩虹环之类装饰。
private struct IrregularBubbleChrome: ViewModifier {
    let accent: Color

    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 32,
            bottomLeadingRadius: 22,
            bottomTrailingRadius: 36,
            topTrailingRadius: 26,
            style: .continuous
        )
    }

    func body(content: Content) -> some View {
        content
            .background(
                ZStack {
                    shape.fill(Color.white.opacity(0.40))
                    shape.fill(accent.opacity(0.10))
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                }
                .compositingGroup()
            )
            .overlay(
                shape.stroke(Color.white.opacity(0.28), lineWidth: 0.6)
                    .blur(radius: 0.5)
            )
            .overlay(
                shape.stroke(Color.white.opacity(0.16), lineWidth: 1.4)
                    .blur(radius: 6)
            )
            .shadow(color: accent.opacity(0.18), radius: 8, x: 0, y: 3)
            .shadow(color: Color.black.opacity(0.10), radius: 4, x: 0, y: 1)
    }
}

/// 肥皂泡风格外壳：背景几乎完全透明，靠光泽 rim + 左上反光斑 + 底部状态色辉光"显形"。
/// 折叠态用 `.circle`，展开横向气泡用 `.irregular(...)`。决策类卡片走 `ExpandedCardChrome`，保留稳重风格。
private struct SoapBubbleChrome: ViewModifier {
    enum Shape {
        case circle
        case irregular(topLeading: CGFloat, topTrailing: CGFloat, bottomLeading: CGFloat, bottomTrailing: CGFloat)
    }

    let shape: Shape
    let accent: Color
    /// 描边粗度倍率（leader 状态下放大）。
    let emphasis: CGFloat

    func body(content: Content) -> some View {
        // .plusLighter 让所有"光"层叠加只增亮不变浑浊，模拟肥皂泡多次反光。
        content
            .background(
                ZStack {
                    fill(Color.white.opacity(0.26))
                    fill(accent.opacity(0.08))
                    fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10), Color.white.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    fill(
                        RadialGradient(
                            colors: [accent.opacity(0.22), accent.opacity(0.04), Color.clear],
                            center: UnitPoint(x: 0.7, y: 0.85),
                            startRadius: 0,
                            endRadius: 90
                        )
                    )
                    .blendMode(.plusLighter)
                    stroke(
                        AngularGradient(
                            colors: [
                                Color(red: 0.85, green: 0.95, blue: 1.0).opacity(0.30),
                                accent.opacity(0.30),
                                Color(red: 1.0, green: 0.85, blue: 0.95).opacity(0.30),
                                Color.white.opacity(0.34),
                                Color(red: 0.78, green: 1.0, blue: 0.92).opacity(0.30),
                                accent.opacity(0.34),
                                Color(red: 0.85, green: 0.95, blue: 1.0).opacity(0.30)
                            ],
                            center: .center
                        ),
                        lineWidth: 1.8
                    )
                    .blur(radius: 3.2)
                    .blendMode(.plusLighter)
                    fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.32),
                                Color.white.opacity(0.10),
                                Color.white.opacity(0)
                            ],
                            center: UnitPoint(x: 0.26, y: 0.20),
                            startRadius: 0,
                            endRadius: 36
                        )
                    )
                    .blendMode(.plusLighter)
                    fill(
                        RadialGradient(
                            colors: [
                                Color.white.opacity(0.18),
                                Color.white.opacity(0.05),
                                Color.white.opacity(0)
                            ],
                            center: UnitPoint(x: 0.78, y: 0.78),
                            startRadius: 0,
                            endRadius: 16
                        )
                    )
                    .blendMode(.plusLighter)
                }
                .compositingGroup()
            )
            .overlay(
                stroke(Color.white.opacity(0.14), lineWidth: 1.2 * emphasis)
                    .blur(radius: 6.5)
            )
            .shadow(color: accent.opacity(0.18), radius: 7, x: 0, y: 3)
            .shadow(color: Color.black.opacity(0.07), radius: 3, x: 0, y: 1)
    }

    @ViewBuilder
    private func fill<S: ShapeStyle>(_ style: S) -> some View {
        switch shape {
        case .circle:
            Circle().fill(style)
        case let .irregular(tl, tr, bl, br):
            UnevenRoundedRectangle(
                topLeadingRadius: tl,
                bottomLeadingRadius: bl,
                bottomTrailingRadius: br,
                topTrailingRadius: tr,
                style: .continuous
            ).fill(style)
        }
    }

    @ViewBuilder
    private func stroke<S: ShapeStyle>(_ style: S, lineWidth: CGFloat) -> some View {
        switch shape {
        case .circle:
            Circle().stroke(style, lineWidth: lineWidth)
        case let .irregular(tl, tr, bl, br):
            UnevenRoundedRectangle(
                topLeadingRadius: tl,
                bottomLeadingRadius: bl,
                bottomTrailingRadius: br,
                topTrailingRadius: tr,
                style: .continuous
            ).stroke(style, lineWidth: lineWidth)
        }
    }
}

/// 决策类卡片（权限/AskUser/旧 fire-and-forget）的毛玻璃外壳：
/// 厚一档的 material + 顶部高光 + 极细描边 + 双层柔和阴影，避免突兀的状态色硬边。
private struct ExpandedCardChrome: ViewModifier {
    let accent: Color

    private let cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return content
            .background(shape.fill(.regularMaterial))
            // 极细的边框，让边缘"切"出来
            .overlay(shape.stroke(Color.white.opacity(0.10), lineWidth: 0.5))
            // 顶部高光：从上往下渐变白，轻轻抹一层
            .overlay(
                shape.stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.35), Color.white.opacity(0)],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 0.6
                )
                .blendMode(.plusLighter)
            )
            // 状态色仅作为底部彩色阴影暗示，不再做硬描边
            .shadow(color: Color.black.opacity(0.22), radius: 22, x: 0, y: 10)
            .shadow(color: accent.opacity(0.14), radius: 6, x: 0, y: 2)
    }
}

/// 高级简约的胶囊按钮样式。
/// - prominent=true：实色填充（用于主操作"允许"）。
/// - prominent=false：玻璃感半透底 + 细边（用于次操作）。
private struct GlassPillButtonStyle: ButtonStyle {
    let tint: Color
    let prominent: Bool

    func makeBody(configuration: Configuration) -> some View {
        let shape = Capsule(style: .continuous)
        return configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .foregroundStyle(prominent ? Color.white : tint)
            .background(
                shape.fill(prominent ? AnyShapeStyle(tint) : AnyShapeStyle(tint.opacity(0.14)))
            )
            .overlay(
                shape.stroke(
                    prominent ? Color.white.opacity(0.25) : tint.opacity(0.32),
                    lineWidth: prominent ? 0.5 : 0.7
                )
            )
            .shadow(
                color: prominent ? tint.opacity(0.35) : .clear,
                radius: prominent ? 6 : 0,
                x: 0,
                y: prominent ? 2 : 0
            )
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .opacity(configuration.isPressed ? 0.85 : 1.0)
            .animation(.spring(response: 0.22, dampingFraction: 0.75), value: configuration.isPressed)
    }
}
